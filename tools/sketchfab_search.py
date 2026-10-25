"""Search Sketchfab for downloadable CC-BY / CC0 models that are mirrored in Objaverse.

    python -I tools/sketchfab_search.py "pump shotgun" "mp5" ...

Prints uid | name | license | author | faces | objaverse path. Used to pick sources for tools/asset_sources.json.
"""
import gzip, json, os, sys, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
INDEX = os.path.join(HERE, 'cache', 'objaverse', 'object-paths.json.gz')
OK = ('CC Attribution', 'CC0 Public Domain', 'Public Domain')


def search(q, count=24):
    url = 'https://api.sketchfab.com/v3/search?' + urllib.parse.urlencode(
        {'type': 'models', 'q': q, 'downloadable': 'true', 'count': count, 'sort_by': '-likeCount'})
    req = urllib.request.Request(url, headers={'User-Agent': 'AetherionProject/0.1'})
    return json.load(urllib.request.urlopen(req, timeout=30)).get('results', [])


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    paths = json.load(gzip.open(INDEX, 'rt'))
    for q in sys.argv[1:]:
        print('==', q)
        for r in search(q):
            lic = (r.get('license') or {}).get('label', '?')
            if lic not in OK:
                continue
            p = paths.get(r['uid'])
            if not p:
                continue
            print(f"  {r['uid']} | {r['name'][:48]:48} | {lic:18} | {r['user']['username'][:20]:20} | {r.get('faceCount')}")


if __name__ == '__main__':
    main()
