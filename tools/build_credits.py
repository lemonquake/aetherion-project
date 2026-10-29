"""Writes game/data/credits.json: every asset in the game whose licence asks for attribution (CC BY, CC BY-SA), for
the in-game credits screen. Run again whenever assets are added.

    python -I tools/build_credits.py

Sources read:
- every source.json / sources/<id>.json under game/assets whose licence is CC BY or CC BY-SA (Sketchfab models: guns,
  gear, arms, r7 cars and props; Sleep street and nature models, which list their items; Wikimedia Commons sounds),
- game/assets/audio/r6/CREDITS.json (Freesound; the CC BY ones),
- the sounds copied from the owner's Sleep project (game/assets/audio/sleep): credited in that project's
  licences/*.md tables; each row whose file is shipped here is taken over.
CC0 assets need no credit and are left out (docs/ASSET_MANIFEST.md lists everything).

Each entry: {title, author, licence, licence_url, url, kind, used_for}.
"""
import html
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, 'game')
OUT = os.path.join(GAME, 'data', 'credits.json')
SLEEP_LICENCES = 'A:/3rd Harmonik/interior/game/licenses'

LICENCE_URLS = {
    'CC-BY-4.0': 'https://creativecommons.org/licenses/by/4.0/',
    'CC-BY-3.0': 'https://creativecommons.org/licenses/by/3.0/',
    'CC-BY-SA-4.0': 'https://creativecommons.org/licenses/by-sa/4.0/',
    'CC-BY-SA-3.0': 'https://creativecommons.org/licenses/by-sa/3.0/',
}


def norm_licence(s):
    s = s.strip().upper().replace(' ', '-')
    m = re.match(r'CC-BY(-SA)?-(\d\.\d)', s)
    return 'CC-BY%s-%s' % (m.group(1) or '', m.group(2)) if m else None


def rel(p):
    return os.path.relpath(p, ROOT).replace('\\', '/')


def entry(title, author, lic, url, kind, used):
    return {'title': html.unescape(title), 'author': html.unescape(author), 'licence': lic, 'licence_url': LICENCE_URLS.get(lic, ''), 'url': url,
            'kind': kind, 'used_for': used}


def from_source_files():
    out = []
    for root, _dirs, files in os.walk(os.path.join(GAME, 'assets')):
        for f in sorted(files):
            if not f.endswith('.json') or not (f == 'source.json' or os.path.basename(root) == 'sources'):
                continue
            p = os.path.join(root, f)
            try:
                j = json.load(open(p, encoding='utf-8'))
            except (ValueError, OSError):
                continue
            if not isinstance(j, dict):
                continue
            lic = norm_licence(str(j.get('license', '')))
            if not lic:
                continue
            kind = j.get('kind', 'model' if '/models/' in rel(p) else 'audio')
            if j.get('items'):
                for it in j['items']:
                    out.append(entry(it['title'], it['author'], lic, it['url'], kind,
                                     '%s/%s' % (rel(root), it.get('file', ''))))
                continue
            used = rel(os.path.join(os.path.dirname(root), os.path.splitext(f)[0])) if os.path.basename(root) == 'sources' else rel(root)
            out.append(entry(j.get('title', ''), ', '.join(j.get('authors', [])), lic, j.get('url', ''), kind, used))
    return out


def from_r6():
    out = []
    p = os.path.join(GAME, 'assets', 'audio', 'r6', 'CREDITS.json')
    for s in json.load(open(p, encoding='utf-8')):
        lic = norm_licence(str(s.get('license', '')))
        if lic:
            out.append(entry(s['title'], s['author'], lic, s['url'], 'audio', 'game/assets/audio/r6 (Freesound %s)' % s.get('id', '')))
    return out


def from_sleep_audio():
    """Rows `| file | [title](url) | author | licence |` in the Sleep project's licence notes, for files shipped here."""
    out = []
    shipped = set()
    for root, _d, files in os.walk(os.path.join(GAME, 'assets', 'audio', 'sleep')):
        shipped |= {f for f in files if f.endswith('.ogg')}
    if not os.path.isdir(SLEEP_LICENCES):
        print('note: %s not found; Sleep sound credits skipped' % SLEEP_LICENCES)
        return out
    seen = set()
    for f in sorted(os.listdir(SLEEP_LICENCES)):
        if not f.endswith('.md'):
            continue
        for line in open(os.path.join(SLEEP_LICENCES, f), encoding='utf-8'):
            cells = [c.strip() for c in line.strip().strip('|').split('|')]
            if len(cells) < 4:
                continue
            names = [n.strip() for n in re.split(r',\s*', cells[0])]
            hit = [n for n in names if n in shipped]
            m = re.match(r'\[(.+?)\]\((\S+?)\)', cells[1])
            lic = norm_licence(cells[3])
            if not hit or not m or not lic:
                continue
            key = (m.group(2), tuple(hit))
            if key in seen:
                continue
            seen.add(key)
            out.append(entry(m.group(1), cells[2], lic, m.group(2), 'audio', 'game/assets/audio/sleep: ' + ', '.join(hit)))
    return out


def main():
    items = from_source_files() + from_r6() + from_sleep_audio()
    items.sort(key=lambda e: (e['kind'] != 'model', e['used_for']))
    data = {
        '_doc': 'Assets whose licence requires attribution, for the in-game credits (generated by tools/build_credits.py; '
                'docs/ASSET_MANIFEST.md lists every asset incl. CC0).',
        'credits': items,
    }
    json.dump(data, open(OUT, 'w', encoding='utf-8', newline='\n'), indent=1, ensure_ascii=False)
    by = {}
    for e in items:
        by[e['licence']] = by.get(e['licence'], 0) + 1
    print('wrote %s: %d credits %s' % (rel(OUT), len(items), by))


if __name__ == '__main__':
    main()
