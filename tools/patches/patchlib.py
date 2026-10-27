"""Small helper for the pNN patch scripts: exact, counted text replacements that keep each file's line endings."""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class Patch:
    def __init__(self, rel):
        self.path = os.path.join(ROOT, rel)
        raw = open(self.path, 'rb').read().decode('utf-8')
        self.crlf = '\r\n' in raw
        self.s = raw.replace('\r\n', '\n')

    def rep(self, a, b, count=1):
        n = self.s.count(a)
        if n != count:
            raise SystemExit('%s: expected %d match(es), found %d for:\n%s' % (self.path, count, n, a[:200]))
        self.s = self.s.replace(a, b)

    def save(self):
        out = self.s.replace('\n', '\r\n') if self.crlf else self.s
        open(self.path, 'wb').write(out.encode('utf-8'))
        print('patched', os.path.relpath(self.path, ROOT))
