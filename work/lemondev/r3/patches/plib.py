"""Counted, line-ending-preserving replacements for the r3 patches."""
import sys


def patch(path, reps):
    s = open(path, 'rb').read().decode('utf-8')
    crlf = '\r\n' in s
    s = s.replace('\r\n', '\n')
    for r in reps:
        a, b = r[0], r[1]
        n = r[2] if len(r) > 2 else 1
        c = s.count(a)
        if c != n:
            print('MISMATCH in %s: %d (want %d) for:\n%s' % (path, c, n, a[:300]))
            sys.exit(1)
        s = s.replace(a, b)
    if crlf:
        s = s.replace('\n', '\r\n')
    open(path, 'wb').write(s.encode('utf-8'))
    print('patched', path, len(reps))
