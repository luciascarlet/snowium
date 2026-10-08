#!/usr/bin/env python3
"""Summarize native wheel input and Chromium frame diagnostics."""
import collections
import argparse
import json
import statistics
from pathlib import Path

def distribution(values):
    values = sorted(values)
    if not values:
        return {'count': 0}
    def percentile(p):
        index = (len(values)-1)*p
        lo = int(index)
        hi = min(lo+1, len(values)-1)
        return values[lo]+(values[hi]-values[lo])*(index-lo)
    return {'count': len(values), 'median': statistics.median(values),
            'p95': percentile(.95), 'max': values[-1]}

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--monotonic-scroll', action='store_true',
                    help='Measure position handoff for one manually verified, monotonically scrolling area')
parser.add_argument('directories', nargs='+')
options = parser.parse_args()
summaries = []
for arg in options.directories:
    directory = Path(arg)
    result = json.loads((directory/'results.json').read_text())
    events = sorted(json.loads((directory/'trace.json').read_text()), key=lambda e:e.get('ts', 0))
    pending = {}
    latencies = collections.defaultdict(list)
    scroll_times = []
    renderer_pids = set()
    unfinished = collections.Counter()
    frame_states = collections.Counter()
    scroll_threads = collections.Counter()
    for event in events:
        if event.get('name') == 'PipelineReporter' and event.get('ph') == 'b':
            report = event.get('args', {}).get('chrome_frame_reporter', {})
            if report.get('scroll_state') in ('SCROLL_MAIN_THREAD', 'SCROLL_COMPOSITOR_THREAD'):
                frame_states[report.get('state')] += 1
                scroll_threads[report['scroll_state']] += 1
        if event.get('name') != 'EventLatency':
            continue
        key = (event['pid'], str(event.get('id2', event.get('id'))))
        if event['ph'] == 'b':
            pending[key] = event
        elif event['ph'] == 'e' and key in pending:
            begin = pending.pop(key)
            kind = begin['args']['event_latency']['event_type']
            latencies[kind].append((event['ts']-begin['ts'])/1000)
            if kind in ('FIRST_GESTURE_SCROLL_UPDATE', 'GESTURE_SCROLL_UPDATE'):
                renderer_pids.add(event['pid'])
                scroll_times.extend([begin['ts'], event['ts']])
    for event in pending.values():
        unfinished[event['args']['event_latency']['event_type']] += 1
    # Use actual incoming scroll events through their final reported presentation,
    # excluding the idle lead-in and tail of the recording. Viz completion is a
    # browser-side diagnostic, not a measurement of Screen Sharing delivery.
    first, last = (min(scroll_times), max(scroll_times)) if scroll_times else (0, 0)
    frames = [e['ts']+e['dur'] for e in events
              if e.get('name') == 'Display::DrawAndSwap' and e.get('ph') == 'X'
              and first <= e['ts'] <= last]
    intervals = [(b-a)/1000 for a,b in zip(frames, frames[1:])]
    main_threads = {(e['pid'],e['tid']) for e in events if e.get('name') == 'thread_name'
                    and e['args'].get('name') == 'CrRendererMain' and e['pid'] in renderer_pids}
    tasks = [e for e in events if e.get('name') == 'ThreadControllerImpl::RunTask'
             and e.get('ph') == 'X' and (e['pid'], e['tid']) in main_threads
             and e['ts'] <= last and e['ts']+e.get('dur',0) >= first]
    scroll_latencies = latencies['FIRST_GESTURE_SCROLL_UPDATE']+latencies['GESTURE_SCROLL_UPDATE']
    updates = [e for e in events if e.get('name') == 'InputHandler::ScrollUpdate'
               and e.get('ph') == 'X' and e['pid'] in renderer_pids]
    notifications = [e for e in events if e.get('name') == 'NotifyDidScroll'
                     and e['pid'] in renderer_pids
                     and e.get('args', {}).get('delta', 0) != 0]
    reasons = [e.get('args', {}) for e in events
               if e.get('name') == 'Snowium.ScrollBeginReasons'
               and e['pid'] in renderer_pids]
    paints = [e for e in events if e.get('name') == 'Snowium.AquaScrollbar.Paint'
              and e['pid'] in renderer_pids and e.get('ph') == 'X' and e['ts'] <= last
              and e['ts'] + e.get('dur', 0) >= first]
    timeline = {}
    for name in ('UpdateLayoutTree', 'Layout', 'Paint', 'PrePaint',
                 'FunctionCall', 'FireAnimationFrame'):
        samples = [e for e in events if e.get('name') == name
                   and e.get('ph') == 'X' and (e['pid'], e['tid']) in main_threads
                   and first <= e['ts'] <= last]
        timeline[name] = {'count': len(samples),
                          'total_ms': sum(e.get('dur', 0)/1000 for e in samples)}
    summary = {
        'run': directory.name, 'recording_seconds': result['elapsedMs']/1000,
        'scroll_window_seconds': (last-first)/1e6,
        'scroll_input_updates': len(updates),
        'scroll_input_dy': sum(e.get('args', {}).get('dy', 0) for e in updates),
        'main_scroll_notifications': len(notifications),
        'scroll_begin_reasons': reasons,
        'aqua_paint_ms': distribution([e.get('dur', 0)/1000 for e in paints]),
        'aqua_paint_total_ms': sum(e.get('dur', 0)/1000 for e in paints),
        'scroll_latency_ms': distribution(scroll_latencies),
        'wheel_dispatch_ms': distribution(latencies['MOUSE_WHEEL']),
        'unfinished_latency_events': dict(unfinished),
        'draw_interval_ms': distribution(intervals),
        'draws_over_50ms': sum(v>50 for v in intervals),
        'draws_over_100ms': sum(v>100 for v in intervals),
        'scroll_reporter_states': dict(frame_states),
        'scroll_threads': dict(scroll_threads),
        'main_tasks_over_50ms': sum(e.get('dur',0)>50000 for e in tasks),
        'main_task_ms': distribution([e.get('dur',0)/1000 for e in tasks]),
        'main_timeline_during_scroll': timeline,
        'cpu_seconds_by_type': {},
    }
    # Requires one externally verified scroll area. The trace has no area ID,
    # so do not infer this solely from a superficially continuous value chain.
    # Reject incomplete or discontinuous notifications (e.g. scroll anchoring).
    # This is model handoff, not final scrollbar pixel presentation latency.
    if options.monotonic_scroll or directory.name.startswith('simple-'):
        consumed = [e for e in events if e.get('name') == 'ConsumedDelta'
                    and e['pid'] in renderer_pids
                    and e.get('args', {}).get('y', 0) > 0]
        arrivals = [n for n in notifications if n['pid'] in renderer_pids]
        total = sum(e['args']['y'] for e in consumed)
        continuous = (len(renderer_pids) == 1 and bool(arrivals) and
                      all(n['args']['delta'] > 0 for n in arrivals) and
                      abs(sum(n['args']['delta'] for n in arrivals)-total) < .01 and
                      all(abs(a['args']['cur_y']+a['args']['delta']-
                              b['args']['cur_y']) < .01
                          for a,b in zip(arrivals, arrivals[1:])))
        summary['consumed_input_dy'] = total
        if not continuous:
            summary['main_position_handoff_unavailable'] = 'Incomplete or discontinuous position chain'
        else:
            position = arrivals[0]['args']['cur_y']
            summary['initial_main_scroll_y'] = position
            delays = []
            for event in consumed:
                position += event['args']['y']
                arrival = next((n for n in arrivals
                                if n['ts'] >= event['ts'] and
                                n['args']['cur_y'] + n['args']['delta'] >= position), None)
                if arrival:
                    delays.append((arrival['ts'] - event['ts']) / 1000)
            summary['main_position_handoff_ms'] = distribution(delays)
    cpu = collections.Counter()
    for process in result['cpu']:
        cpu[process['type']] += process['seconds']
    summary['cpu_seconds_by_type'] = dict(cpu)
    summaries.append(summary)
print(json.dumps(summaries, indent=2))
