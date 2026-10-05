#!/usr/bin/env python
"""Python 2.6-compatible watchdog, sent to the owned test Mac over SSH stdin."""
import base64
import json
import os
import signal
import subprocess
import time


def owned_processes(parent, executable):
    """Find this probe's live descendants; never select by executable basename."""
    listing = subprocess.Popen(['/bin/ps', '-axww', '-o', 'pid=,ppid=,command='],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    raw, error = listing.communicate()
    if listing.returncode:
        raise OSError('Cannot inspect probe descendants: ' + repr(error))
    if not isinstance(raw, str):
        raw = raw.decode('utf-8', 'replace')
    rows = []
    for line in raw.splitlines():
        fields = line.strip().split(None, 2)
        if len(fields) == 3:
            try:
                rows.append((int(fields[0]), int(fields[1]), fields[2]))
            except ValueError:
                pass
    descendants = set([parent])
    changed = True
    while changed:
        changed = False
        for pid, ppid, command in rows:
            if ppid in descendants and pid not in descendants:
                descendants.add(pid)
                changed = True
    return [pid for pid, ppid, command in rows
            if pid in descendants and
            (command == executable or command.startswith(executable + ' '))]


def run(config):
    cwd = config['cwd']
    executable = config['argv'][0]
    if os.path.dirname(executable) != cwd:
        raise ValueError('Probe executable must be in its owned directory')
    output_path = os.path.join(cwd, 'native.log')
    started = time.time()
    stream = open(output_path, 'wb')
    process = subprocess.Popen(config['argv'], cwd=cwd, stdout=stream,
                               stderr=subprocess.STDOUT, preexec_fn=os.setsid)
    timed_out = False
    cleanup_errors = []
    while process.poll() is None:
        if time.time() - started >= config['timeout_seconds']:
            timed_out = True
            # A rendezvous child deliberately has a separate process group.
            # Snapshot descendants before stopping their parent, then require
            # the exact executable path for every signal target.
            try:
                owned = owned_processes(process.pid, executable)
            except OSError as error:
                cleanup_errors.append(str(error))
                owned = []
            process.terminate()
            for pid in owned:
                try:
                    os.kill(pid, signal.SIGTERM)
                except OSError:
                    pass
            time.sleep(0.5)
            for pid in owned:
                try:
                    current = owned_processes(pid, executable)
                except OSError as error:
                    cleanup_errors.append(str(error))
                    current = []
                if pid in current:
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except OSError:
                        pass
            if process.poll() is None:
                process.kill()
            break
        time.sleep(0.1)
    return_code = process.wait()
    stream.close()
    stream = open(output_path, 'rb')
    contents = stream.read(1024 * 1024 + 1)
    stream.close()
    encoded = base64.b64encode(contents[:1024 * 1024])
    if not isinstance(encoded, str):
        encoded = encoded.decode('ascii')
    return {'return_code': return_code, 'timed_out': timed_out,
            'elapsed_seconds': round(time.time() - started, 3),
            'log_truncated': len(contents) > 1024 * 1024,
            'cleanup_errors': cleanup_errors,
            'log_base64': encoded}


# Replaced by the local runner before this file is passed over SSH stdin.
CONFIG = None
if __name__ == '__main__':
    print(json.dumps(run(CONFIG), sort_keys=True))
