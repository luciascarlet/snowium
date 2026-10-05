#!/usr/bin/env python3
"""Stage and run only Chromium 124 GN probes on the authorized Snow Leopard Mac.

Does not build, relink, sign, modify system settings, or touch the Chromium60 port.
"""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import struct
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'chromium-124.0.6367.207'
DEFAULT_REMOTE = '/Users/admin/Snowium/modern-port/native-regressions'

# Require every meaningful assertion, including all repeated round trips.
PROBES = {
    'runtime_smoke': (30, {
        'C++ thread-local isolation': 1, 'C++ thread-local destructors': 1,
        'monotonic clock': 1, 'future and condition variable': 1,
        'C++ exception and unwind': 1, 'bundled libc++ containers': 1,
        'bundled std::any': 1, 'bundled std::optional exception': 1,
        'bundled std::variant exception': 1}),
    'seatbelt_smoke': (30, {
        'unsupported extension tokens never grant access': 1,
        'sandbox parameters preserve quoted Unicode paths and deny other writes': 6}),
    'foundation_smoke': (30, {
        'allocate PartitionAlloc TLS key': 1,
        'base, PartitionAlloc and V8 TLS isolate parent and child values': 1,
        'PartitionAlloc protected discard/recommit cycles': 1,
        'V8 protected page decommit/recommit restores access': 1,
        'receive-only Mach creation owns no unwanted send right': 1,
        'Mach creation preserves requested queue limit and one send right': 1,
        'Chromium 124 read-only Mach shared-memory mapping': 1}),
    'font_smoke': (30, {
        'gfx Lucida Grande cascade retains and derives Lucida Grande': 1,
        'gfx Helvetica cascade retains and derives Lucida Grande': 1,
        'gfx Arial cascade retains and derives Lucida Grande': 1,
        'Skia custom RGB and native system pattern color conversion': 1,
        'Helvetica Skia glyph rasterization:': 1,
        'Times Skia glyph rasterization:': 1,
        'Courier Skia glyph rasterization:': 1,
        'Skia embedded TrueType and rotated glyphs:': 1,
        'PNG saved to ': 1}),
    'mach_rendezvous_smoke': (40, {
        'create child synchronization socket': 1,
        'prepare identity mapping and unrelated high descriptor': 1,
        'actual Chromium LaunchProcess starts registered child': 1,
        'parent directory, environment and descriptor flags remain unchanged': 1,
        'same-FD CLOEXEC mapping survives exec': 1,
        'unrelated parent descriptor is closed in child': 1,
        'child process group option is preserved': 1,
        'working directory is applied in child': 1,
        'child receives the requested environment overlay': 1,
        'actual Chromium child exchanges task right with zero incoming ports': 1,
        'child finishes Mach startup before higher level IPC': 1,
        "browser provider returns the authenticated child's task right": 1,
        'child exits cleanly': 1,
        'process-exit watcher removes the task port enrollment': 1,
        'failed exec is reported as launch failure': 1}),
    'mojo_channel_smoke': (30, {
        'create owned POSIX attachment': 1, 'prepare file data': 1,
        'create Mach attachment': 1, 'map attachment contents': 1,
        '32 actual Mojo messages preserve mixed handle order, bytes and memory': 1,
        'Darwin FD acknowledgments release all sender descriptors': 1}),
    'mojo_roundtrip_smoke': (60, {
        '[parent] launch child with inherited Mojo socket and task enrollment': 1,
        '[child] authenticate task port before Mojo initialization': 1,
        '[child] accept actual Mojo invitation': 1,
        '[parent] create convertible writable shared memory': 16,
        '[parent] wrap writable region as one Mach handle': 16,
        '[child] receive ordered FD/Mach/Mach/FD attachments and map shared memory': 16,
        '[parent] broker receives child Mach rights and FDs with shared writes intact': 16,
        '[child] parent confirms receipt before child exits': 1,
        '[parent] child completes 16 round trips and exits cleanly': 1}),
    'net_https_smoke': (80, {
        'verified HTTPS response:': 1,
        'reject invalid HTTPS certificate:': 1}),
}


# Preserve the eight-probe default; sandbox mode runs the same GN executable
# again in a separate owned directory and requires additional assertions.
DEFAULT_PROBES = tuple(PROBES)
SANDBOX_PROBE = 'mojo_roundtrip_renderer_sandbox'
SANDBOX_PROFILE = 'policy-renderer-ipc.sb'
PROBES[SANDBOX_PROBE] = (60, {
    **PROBES['mojo_roundtrip_smoke'][1],
    '[parent] prepare actual renderer source policy': 1,
    '[parent] send renderer policy over actual SeatbeltExec pipe': 1,
    '[child] renderer policy denies an unrelated filesystem write': 1,
})


def executable_name(name):
    return 'mojo_roundtrip_smoke' if name == SANDBOX_PROBE else name


def renderer_profile():
    sources = [SOURCE / 'sandbox/policy/mac' / name
               for name in ('common.sb', 'renderer.sb')]
    records = [file_record(path) for path in sources]
    data = sources[0].read_bytes() + b'\n' + sources[1].read_bytes()
    # Detect concurrent policy edits rather than recording mismatched sources.
    if records != [file_record(path) for path in sources]:
        raise RuntimeError('renderer policy sources changed during preflight')
    return data, {'source_files': records, 'size': len(data),
                  'sha256': hashlib.sha256(data).hexdigest()}


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def file_record(path):
    stat = path.stat()
    return {'path': str(path), 'size': stat.st_size,
            'mtime_ns': stat.st_mtime_ns, 'sha256': sha256(path)}


def verify_output(name, result, output):
    problems = []
    if result.get('return_code') != 0:
        problems.append('nonzero exit status: ' + str(result.get('return_code')))
    if result.get('timed_out'):
        problems.append('watchdog timeout')
    if result.get('log_truncated'):
        problems.append('log exceeded one MiB')
    if re.search(r'^FAIL(?:\s|$)', output, re.MULTILINE):
        problems.append('probe printed FAIL')
    lines = [line[5:] for line in output.splitlines() if line.startswith('PASS ')]
    for expected, minimum in PROBES[name][1].items():
        count = sum(line.startswith(expected) for line in lines)
        if count < minimum:
            problems.append('missing PASS assertion (%d/%d): %s' %
                            (count, minimum, expected))
    if name == 'net_https_smoke':
        if not re.search(r'^PASS verified HTTPS response:.* error=OK http=200 '
                         r'body_bytes=[1-9][0-9]* cert_status=0$', output, re.MULTILINE):
            problems.append('verified HTTPS status/body/certificate result missing')
        if not re.search(r'^PASS reject invalid HTTPS certificate:.* '
                         r'error=ERR_CERT_[A-Z_]+ http=0 body_bytes=0 ',
                         output, re.MULTILINE):
            problems.append('negative HTTPS case was not a certificate rejection')
    return problems


def run_checked(argv, timeout=60, **kwargs):
    result = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=timeout, **kwargs)
    if result.returncode:
        raise RuntimeError('%s exited %s: %s' %
                           (argv[0], result.returncode,
                            result.stderr.decode('utf-8', 'replace')[-3000:]))
    return result


def validate_png(path):
    data = path.read_bytes()
    if len(data) < 33 or data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
        raise RuntimeError('font artifact is not a PNG')
    width, height = struct.unpack('>II', data[16:24])
    if not width or not height:
        raise RuntimeError('font PNG has empty dimensions')
    return {'width': width, 'height': height, **file_record(path)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='admin@keine.local')
    parser.add_argument('--build-dir', type=Path, default=SOURCE / 'out/SnowLeopard')
    parser.add_argument('--only', help='comma-separated GN probe names; default: all eight')
    parser.add_argument('--renderer-sandbox', action='store_true',
                        help='add full renderer-policy IPC case; keeps the unsandboxed baseline')
    parser.add_argument('--run-id', default=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-%d' % os.getpid())
    parser.add_argument('--dry-run', action='store_true', help='read-only local preflight; no SSH or files written')
    parser.add_argument('--valid-url', default='https://example.com/')
    parser.add_argument('--invalid-url', default='https://expired.badssl.com/')
    args = parser.parse_args(argv)
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,79}', args.run_id):
        parser.error('run-id must be one safe path component')
    if args.host.startswith('-') or not re.fullmatch(r'[A-Za-z0-9_.@:-]+', args.host):
        parser.error('invalid SSH host')
    build = args.build_dir.resolve()
    if not build.is_relative_to((SOURCE / 'out').resolve()):
        parser.error('build-dir must be inside the Chromium124 source out directory')
    names = args.only.split(',') if args.only else list(DEFAULT_PROBES)
    if not names or len(set(names)) != len(names) or any(n not in PROBES for n in names):
        parser.error('unknown or duplicate probe; choices: ' + ','.join(PROBES))
    if args.renderer_sandbox and SANDBOX_PROBE not in names:
        names.append(SANDBOX_PROBE)
    for url in (args.valid_url, args.invalid_url):
        if not url.startswith('https://'):
            parser.error('both certificate-test URLs must use HTTPS')
    paths = list(dict.fromkeys(build / executable_name(name) for name in names))
    if 'net_https_smoke' in names:
        paths.append(build / 'icudtl.dat')
    absent = [str(path) for path in paths if not path.is_file()]
    if absent:
        print('Missing GN build inputs:\n' + '\n'.join(absent), file=sys.stderr)
        return 2
    for name in names:
        with (build / executable_name(name)).open('rb') as stream:
            if stream.read(8) != b'\xcf\xfa\xed\xfe\x07\x00\x00\x01':
                print('Expected thin x86_64 Mach-O GN executable: ' + name, file=sys.stderr)
                return 2
    records = {path.name: file_record(path) for path in paths}
    profile_data = None
    if SANDBOX_PROBE in names:
        profile_data, records[SANDBOX_PROFILE] = renderer_profile()
    remote_root = DEFAULT_REMOTE + '/' + args.run_id
    log_dir = ROOT / 'logs/native-regressions' / args.run_id
    if args.dry_run:
        print(json.dumps({'mode': 'read-only preflight', 'host': args.host,
                          'remote_directory': remote_root, 'local_logs': str(log_dir),
                          'probes': names, 'inputs': records}, indent=2))
        return 0
    # Never replace a prior run, locally or remotely.
    log_dir.mkdir(parents=True, exist_ok=False)
    # Leave an explicit incomplete record even if connection or staging fails.
    (log_dir / 'provenance.json').write_text(json.dumps({
        'schema_version': 1, 'status': 'setup_incomplete',
        'started_utc': datetime.now(timezone.utc).isoformat(),
        'host': args.host, 'build_directory': str(build),
        'remote_directory': remote_root, 'inputs': records}, indent=2) + '\n')
    staging = log_dir / 'inputs'
    staging.mkdir()
    for path in paths:
        dest = staging / path.name
        shutil.copy2(path, dest)
        if sha256(dest) != records[path.name]['sha256']:
            raise RuntimeError('GN output changed during staging: ' + str(path))
    if profile_data is not None:
        profile_path = staging / SANDBOX_PROFILE
        profile_path.write_bytes(profile_data)
        if sha256(profile_path) != records[SANDBOX_PROFILE]['sha256']:
            raise RuntimeError('staged renderer policy hash mismatch')
    ssh = ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10',
           '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=2', args.host]
    scp = ['scp', '-q', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10']
    host = run_checked(ssh + ['sw_vers -productVersion; uname -m; sysctl -n hw.cpu64bit_capable'])
    host_lines = host.stdout.decode('utf-8', 'replace').splitlines()
    if len(host_lines) != 3 or not host_lines[0].startswith('10.6.') or host_lines[2] != '1':
        raise RuntimeError('Expected a 64-bit-capable Snow Leopard target, got: ' + repr(host_lines))
    parent = shlex.quote(DEFAULT_REMOTE)
    run_checked(ssh + ['mkdir -p ' + parent + ' && mkdir ' + shlex.quote(remote_root)])
    provenance = {'schema_version': 1, 'started_utc': datetime.now(timezone.utc).isoformat(),
                  'host': args.host, 'os_version': host_lines[0],
                  'kernel_architecture': host_lines[1], 'cpu_64bit_capable': True,
                  'remote_directory': remote_root, 'build_directory': str(build),
                  'inputs': records, 'source_snapshots': {}, 'probes': {},
                  'note': 'Results apply to the recorded GN binary hashes. This runner does not prove that every source edit was rebuilt.'}
    sources = [SOURCE / 'chrome/VERSION', build / 'args.gn',
               ROOT / 'patches/chromium-124-snow-leopard.patch',
               Path(__file__), ROOT / 'scripts/native_probe_remote.py']
    if profile_data is not None:
        sources += [SOURCE / 'sandbox/policy/mac/common.sb',
                    SOURCE / 'sandbox/policy/mac/renderer.sb']
    sources += sorted(p for p in (ROOT / 'overlay/snow_leopard').rglob('*') if p.is_file())
    sources += sorted(p for p in (ROOT / 'runtime-compat/src').glob('*') if p.is_file())
    sources += [ROOT / 'runtime/libMacportsLegacySupport.a',
                ROOT / 'tls-compat/build/libsnowium_emutls.a',
                ROOT / 'runtime-compat/build-clang19-sdk14/libsnowium_arc.a',
                ROOT / 'link-stubs/provenance.json']
    for path in sources:
        if path.is_file():
            provenance['source_snapshots'][str(path.relative_to(ROOT))] = file_record(path)
    provenance_path = log_dir / 'provenance.json'
    def save():
        provenance_path.write_text(json.dumps(provenance, indent=2) + '\n')
    save()
    template = (ROOT / 'scripts/native_probe_remote.py').read_text()
    failures = 0
    for name in names:
        timeout, expected = PROBES[name]
        remote_dir = remote_root + '/' + name
        started = time.monotonic()
        entry = {'expected_exit': 0, 'expected_pass_minima': expected,
                 'remote_directory': remote_dir, 'status': 'running'}
        provenance['probes'][name] = entry
        save()
        print('RUN ' + name, flush=True)
        try:
            run_checked(ssh + ['mkdir ' + shlex.quote(remote_dir)])
            inputs = [staging / executable_name(name)]
            if name == SANDBOX_PROBE:
                inputs.append(staging / SANDBOX_PROFILE)
            if name == 'net_https_smoke': inputs.append(staging / 'icudtl.dat')
            run_checked(scp + [str(p) for p in inputs] + [args.host + ':' + remote_dir + '/'], timeout=90)
            command = [remote_dir + '/' + executable_name(name)]
            if name == SANDBOX_PROBE:
                command.append('--renderer-profile=' + remote_dir + '/' + SANDBOX_PROFILE)
            if name == 'font_smoke': command.append(remote_dir + '/font-smoke-124.png')
            if name == 'net_https_smoke': command += [args.valid_url, args.invalid_url]
            config = {'cwd': remote_dir, 'argv': command, 'timeout_seconds': timeout}
            script = template.replace('CONFIG = None', 'CONFIG = json.loads(' + repr(json.dumps(config)) + ')')
            transport = run_checked(ssh + ['/usr/bin/python -'], timeout=timeout + 30, input=script.encode())
            if transport.stderr:
                (log_dir / (name + '.transport.log')).write_bytes(transport.stderr)
            result = json.loads(transport.stdout)
            log_bytes = base64.b64decode(result.pop('log_base64'))
            log_path = log_dir / (name + '.log')
            log_path.write_bytes(log_bytes)
            errors = verify_output(name, result, log_bytes.decode('utf-8', 'replace'))
            entry.update(result)
            entry['argv'] = command
            entry['log'] = file_record(log_path)
            if name == 'font_smoke' and not errors:
                artifact = log_dir / 'font-smoke-124.png'
                run_checked(scp + [args.host + ':' + remote_dir + '/font-smoke-124.png', str(artifact)])
                entry['artifact'] = validate_png(artifact)
            entry['problems'] = errors
            entry['status'] = 'fail' if errors else 'pass'
        except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
            entry.update(status='fail', problems=[str(error)])
        entry['total_elapsed_seconds'] = round(time.monotonic() - started, 3)
        if entry['status'] != 'pass': failures += 1
        print(entry['status'].upper() + ' ' + name +
              (': ' + '; '.join(entry.get('problems', [])) if entry.get('problems') else ''), flush=True)
        save()
    provenance['finished_utc'] = datetime.now(timezone.utc).isoformat()
    provenance['status'] = 'fail' if failures else 'pass'
    save()
    print('Results: ' + str(provenance_path), flush=True)
    return 1 if failures else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
        print('Runner error: ' + str(error), file=sys.stderr)
        sys.exit(2)
