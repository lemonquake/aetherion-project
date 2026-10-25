"""Replaces `var name :=` with `var name =` where Godot reports it cannot infer the type.
Reads a Godot log, edits the reported lines, prints how many it fixed."""
import re, sys
log = open(sys.argv[1], encoding='utf-8', errors='replace').read().splitlines()
fixes = {}
for i, line in enumerate(log):
    m = re.search(r'Cannot infer the type of "([a-z_][a-zA-Z0-9_]*)" variable', line)
    if not m:
        continue
    for j in range(i + 1, min(i + 4, len(log))):
        m2 = re.search(r'GDScript::reload \(res://(.+?):(\d+)\)', log[j])
        if m2:
            fixes.setdefault(m2.group(1), []).append((int(m2.group(2)), m.group(1)))
            break
n = 0
for path, items in fixes.items():
    p = 'A:/Python/aetherion-project/game/' + path
    lines = open(p, encoding='utf-8').read().split('\n')
    for ln, name in items:
        l = lines[ln - 1]
        new = re.sub(r'\bvar ' + re.escape(name) + r' :=', 'var ' + name + ' =', l, count=1)
        if new != l:
            lines[ln - 1] = new
            n += 1
    open(p, 'w', encoding='utf-8').write('\n'.join(lines))
print('fixed', n)
