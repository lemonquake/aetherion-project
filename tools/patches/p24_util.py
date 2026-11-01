"""r24 patch helper: exact text replacements that keep each file's own line endings (CRLF or LF)."""
import sys


def patch(path, pairs):
    raw = open(path, 'rb').read()
    crlf = b'\r\n' in raw
    text = raw.decode('utf-8').replace('\r\n', '\n')
    for old, new in pairs:
        n = text.count(old)
        if n != 1:
            sys.exit('%s: expected 1 match, found %d for:\n%s' % (path, n, old[:300]))
        text = text.replace(old, new)
    if crlf:
        text = text.replace('\n', '\r\n')
    open(path, 'wb').write(text.encode('utf-8'))
    print('patched', path, len(pairs))
