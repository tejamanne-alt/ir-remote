#!/usr/bin/env python3
"""Fails unless line coverage of files under a path prefix meets a minimum.

Usage: coverage_gate.py <lcov.info> <path-prefix> <min-percent>
Example: coverage_gate.py packages/ir_core/coverage/lcov.info lib/src/codecs/ 95
"""
import sys


def main():
    lcov, prefix, minimum = sys.argv[1], sys.argv[2], float(sys.argv[3])
    files = {}
    current = None
    with open(lcov) as f:
        for line in f:
            line = line.strip()
            if line.startswith('SF:'):
                current = line[3:]
                files.setdefault(current, [0, 0])
            elif line.startswith('DA:') and current is not None:
                _, hits = line[3:].split(',')[:2]
                files[current][1] += 1
                if int(hits) > 0:
                    files[current][0] += 1
    hit = total = 0
    for path, (h, t) in sorted(files.items()):
        if prefix in path.replace('\\', '/'):
            hit += h
            total += t
            print('%6.1f%%  %4d/%-4d %s' % (100.0 * h / t if t else 100, h, t, path))
    if total == 0:
        print('no files matched %r' % prefix)
        sys.exit(1)
    pct = 100.0 * hit / total
    print('TOTAL %.2f%% (%d/%d lines) for %s; minimum %.1f%%' % (pct, hit, total, prefix, minimum))
    sys.exit(0 if pct >= minimum else 1)


if __name__ == '__main__':
    main()
