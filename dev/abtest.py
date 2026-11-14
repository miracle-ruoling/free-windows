"""Run one A/B measurement: set ini overrides, restart the dock, sweep, measure.

usage: python dev/abtest.py <label> key=value [key=value ...]

Writes the probe frames to dev/ab_<label> and prints the content-anchoring summary for the
static band (client 1300..1450, which sits over a static illustration).
"""
import io
import os
import subprocess
import sys
import time

INI = os.path.expandvars(r'%LOCALAPPDATA%\Programs\Dock\dock.ini')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEV = os.path.join(ROOT, 'dev')


def write_ini(over):
    s = io.open(INI, encoding='utf-8-sig', newline='').read()
    kv, order = {}, []
    for l in s.splitlines():
        if '=' in l:
            k, v = l.split('=', 1)
            if k not in kv:
                order.append(k)
            kv[k] = v
    for k, v in over.items():
        if k not in kv:
            order.append(k)
        kv[k] = v
    io.open(INI, 'w', encoding='utf-8-sig', newline='').write(
        '\r\n'.join(['[dock]'] + ['%s=%s' % (k, kv[k]) for k in order]) + '\r\n')
    return {k: kv[k] for k in over}


def main():
    label = sys.argv[1]
    over = {}
    for a in sys.argv[2:]:
        k, v = a.split('=', 1)
        over[k] = v
    print('--- %s: %s' % (label, over))
    print('ini ->', write_ini(over))
    subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                    '-File', os.path.join(DEV, 'redeploy.ps1')],
                   capture_output=True)
    time.sleep(2.0)
    out1 = subprocess.run([sys.executable, os.path.join(DEV, 'motion_probe.py'),
                           os.path.join('dev', 'ab_' + label), '150', '800'],
                          cwd=ROOT, capture_output=True, text=True)
    print(out1.stdout.strip().splitlines()[-2:])
    time.sleep(1.0)
    out2 = subprocess.run([sys.executable, os.path.join(DEV, 'content_anchor.py'),
                           os.path.join('dev', 'ab_' + label), '1300', '1450', '60'],
                          cwd=ROOT, capture_output=True, text=True)
    tail = [l for l in out2.stdout.strip().splitlines() if
            l.startswith(('frames', 'sx on', 'corr'))]
    print('\n'.join(tail))
    log = os.path.expandvars(r'%LOCALAPPDATA%\Programs\Dock\dock.log')
    try:
        lines = io.open(log, encoding='utf-8', errors='replace').read().splitlines()
        fr = [l for l in lines if 'frame:' in l][-1]
        print('dock:', fr.split('] ')[-1] if '] ' in fr else fr)
    except Exception as e:
        print('log read failed', e)


if __name__ == '__main__':
    main()
