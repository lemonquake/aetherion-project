"""Exact-text patching for the r4 run: keeps each file's own line endings, reports every replacement, never
stops at the first miss (prints MISS and returns False)."""


def patch(path, old, new, count=1):
    b = open(path, 'rb').read()
    crlf = b'\r\n' in b
    s = b.decode('utf-8').replace('\r\n', '\n')
    n = s.count(old)
    if n != count:
        print('MISS %s (%d found, want %d): %s' % (path, n, count, old.strip().splitlines()[0][:70]))
        return False
    s = s.replace(old, new)
    if crlf:
        s = s.replace('\n', '\r\n')
    open(path, 'wb').write(s.encode('utf-8'))
    print('ok   %s' % path)
    return True
