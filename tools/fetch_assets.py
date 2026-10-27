"""Download the third-party assets listed in tools/asset_sources.json, with provenance.

    python -I tools/fetch_assets.py [section ...]      # sections: polyhaven_models polyhaven_textures
                                                     #           polyhaven_hdris sketchfab kenney commons
    python -I tools/fetch_assets.py --manifest         # only rewrite docs/ASSET_MANIFEST.md

Every downloaded asset gets a source.json next to it (source URL, author, license, retrieval date, file
hashes). Files whose upstream MD5 is published (Poly Haven) are verified before they are kept.

Layout:
  game/assets/thirdparty/polyhaven/models/<id>/      glTF + bin + textures (real-world scale, used directly)
  game/assets/thirdparty/polyhaven/textures/<id>/    albedo.jpg normal.jpg roughness.jpg [ao.jpg]
  game/assets/thirdparty/polyhaven/hdri/<id>/        <id>_<res>.hdr
  tools/cache/sketchfab/<name>/<name>.glb            raw Objaverse mirror copy; processed by blender/ scripts
  tools/cache/kenney/<slug>/                          extracted pack; selected files copied by tools/import_audio.py
  tools/cache/commons/<file>                          raw Wikimedia Commons media
"""
import datetime
import gzip
import hashlib
import json
import os
import re
import sys
import urllib.parse
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, 'game')
TP = os.path.join(GAME, 'assets', 'thirdparty')
CACHE = os.path.join(ROOT, 'tools', 'cache')
SOURCES = os.path.join(ROOT, 'tools', 'asset_sources.json')
MANIFEST = os.path.join(ROOT, 'docs', 'ASSET_MANIFEST.md')
UA = {'User-Agent': 'AetherionProject/0.1 (asset fetch; contact via project owner)'}
TODAY = datetime.date.today().isoformat()


def get(url, timeout=120):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def get_json(url):
    return json.loads(get(url).decode('utf-8'))


def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + '.part'
    with open(tmp, 'wb') as f:
        f.write(data)
    os.replace(tmp, path)


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def write_source(folder, record):
    record.setdefault('retrieved', TODAY)
    files = {}
    for dirpath, _, names in os.walk(folder):
        for n in sorted(names):
            if n == 'source.json' or n.endswith('.import'):
                continue
            p = os.path.join(dirpath, n)
            files[os.path.relpath(p, folder).replace('\\', '/')] = sha256(p)
    record['files'] = files
    with open(os.path.join(folder, 'source.json'), 'w', encoding='utf-8') as f:
        json.dump(record, f, indent=2, ensure_ascii=False)


def download_checked(url, path, md5=None):
    if os.path.exists(path) and (md5 is None or hashlib.md5(open(path, 'rb').read()).hexdigest() == md5):
        return False
    data = get(url)
    if md5 and hashlib.md5(data).hexdigest() != md5:
        raise RuntimeError(f'MD5 mismatch for {url}')
    save(path, data)
    return True


# ------------------------------------------------------------------ Poly Haven

def ph_info(asset_id):
    info = get_json(f'https://api.polyhaven.com/info/{asset_id}')
    return {
        'source': 'Poly Haven',
        'title': info.get('name', asset_id),
        'url': f'https://polyhaven.com/a/{asset_id}',
        'authors': list(info.get('authors', {}).keys()),
        'license': 'CC0-1.0',
        'license_url': 'https://polyhaven.com/license',
        'attribution_required': False,
    }


def ph_model(asset_id, res):
    folder = os.path.join(TP, 'polyhaven', 'models', asset_id)
    if os.path.exists(os.path.join(folder, 'source.json')):
        return 'cached'
    files = get_json(f'https://api.polyhaven.com/files/{asset_id}')
    gl = files['gltf']
    r = res if res in gl else sorted(gl.keys(), key=lambda k: int(k[:-1]))[0]
    entry = gl[r]['gltf']
    download_checked(entry['url'], os.path.join(folder, os.path.basename(entry['url'])), entry.get('md5'))
    for rel, inc in entry.get('include', {}).items():
        download_checked(inc['url'], os.path.join(folder, rel), inc.get('md5'))
    rec = ph_info(asset_id)
    rec.update({'kind': 'model', 'resolution': r, 'modifications': 'none (imported as published)'})
    write_source(folder, rec)
    return r


TEX_MAPS = {'albedo': ['Diffuse', 'diff'], 'normal': ['nor_gl'], 'roughness': ['Rough', 'rough'],
            'ao': ['AO', 'ao'], 'arm': ['arm']}


def ph_texture(asset_id, res, maps=('albedo', 'normal', 'roughness', 'ao')):
    folder = os.path.join(TP, 'polyhaven', 'textures', asset_id)
    if os.path.exists(os.path.join(folder, 'source.json')):
        return 'cached'
    files = get_json(f'https://api.polyhaven.com/files/{asset_id}')
    got = []
    for out, keys in TEX_MAPS.items():
        if out not in maps:
            continue
        key = next((k for k in keys if k in files), None)
        if key is None:
            continue
        variants = files[key]
        r = res if res in variants else sorted(variants.keys(), key=lambda k: int(k[:-1]))[0]
        fmt = 'jpg' if 'jpg' in variants[r] else 'png'
        e = variants[r][fmt]
        download_checked(e['url'], os.path.join(folder, f'{out}.{fmt}'), e.get('md5'))
        got.append(out)
    rec = ph_info(asset_id)
    rec.update({'kind': 'texture', 'resolution': res, 'maps': got,
                'modifications': 'renamed map files (albedo/normal(OpenGL)/roughness/ao)'})
    write_source(folder, rec)
    return res


def ph_hdri(asset_id, res):
    folder = os.path.join(TP, 'polyhaven', 'hdri', asset_id)
    if os.path.exists(os.path.join(folder, 'source.json')):
        return 'cached'
    files = get_json(f'https://api.polyhaven.com/files/{asset_id}')
    e = files['hdri'][res]['hdr']
    download_checked(e['url'], os.path.join(folder, f'{asset_id}_{res}.hdr'), e.get('md5'))
    rec = ph_info(asset_id)
    rec.update({'kind': 'hdri', 'resolution': res, 'modifications': 'none'})
    write_source(folder, rec)
    return res


# ------------------------------------------------------------------ Sketchfab via Objaverse mirror

HF = 'https://huggingface.co/datasets/allenai/objaverse/resolve/main/'
_paths = None


def objaverse_paths():
    global _paths
    if _paths is None:
        idx = os.path.join(CACHE, 'objaverse', 'object-paths.json.gz')
        if not os.path.exists(idx):
            save(idx, get(HF + 'object-paths.json.gz'))
        _paths = json.load(gzip.open(idx, 'rt'))
    return _paths


def sketchfab(name, uid, purpose):
    folder = os.path.join(CACHE, 'sketchfab', name)
    if os.path.exists(os.path.join(folder, 'source.json')):
        return 'cached'
    meta = get_json(f'https://api.sketchfab.com/v3/models/{uid}')
    lic = (meta.get('license') or {})
    label = lic.get('label', '')
    if label not in ('CC Attribution', 'CC0 Public Domain'):
        raise RuntimeError(f'{name}: license {label!r} is not CC-BY or CC0')
    path = objaverse_paths().get(uid)
    if not path:
        raise RuntimeError(f'{name}: {uid} not in the Objaverse mirror')
    save(os.path.join(folder, name + '.glb'), get(HF + path, timeout=600))
    user = meta.get('user', {})
    rec = {
        'source': 'Sketchfab (downloaded from the Objaverse mirror, allenai/objaverse on Hugging Face)',
        'title': meta.get('name'),
        'url': f'https://sketchfab.com/3d-models/{uid}',
        'mirror_url': HF + path,
        'authors': [user.get('displayName') or user.get('username')],
        'author_url': user.get('profileUrl'),
        'license': 'CC-BY-4.0' if label == 'CC Attribution' else 'CC0-1.0',
        'license_url': lic.get('url') or ('https://creativecommons.org/licenses/by/4.0/' if label == 'CC Attribution'
                                          else 'https://creativecommons.org/publicdomain/zero/1.0/'),
        'attribution_required': label == 'CC Attribution',
        'kind': 'model', 'purpose': purpose,
        'modifications': 'pending: see the processed asset\'s own source.json',
    }
    write_source(folder, rec)
    return 'ok'


# ------------------------------------------------------------------ Kenney

def kenney(slug):
    folder = os.path.join(CACHE, 'kenney', slug)
    if os.path.exists(os.path.join(folder, 'source.json')):
        return 'cached'
    page = get(f'https://kenney.nl/assets/{slug}').decode('utf-8', 'replace')
    m = re.search(r'https://kenney\.nl/media/pages/assets/[^"\s]+?\.zip', page)
    if not m:
        raise RuntimeError(f'kenney {slug}: no zip link')
    url = m.group(0)
    zpath = os.path.join(CACHE, 'kenney', slug + '.zip')
    save(zpath, get(url, timeout=600))
    with zipfile.ZipFile(zpath) as z:
        for n in z.namelist():
            target = os.path.normpath(os.path.join(folder, n))
            if not target.startswith(os.path.normpath(folder)):
                raise RuntimeError('zip path escapes target')
        z.extractall(folder)
    rec = {'source': 'Kenney', 'title': slug, 'url': f'https://kenney.nl/assets/{slug}', 'download_url': url,
           'authors': ['Kenney (www.kenney.nl)'], 'license': 'CC0-1.0',
           'license_url': 'https://creativecommons.org/publicdomain/zero/1.0/', 'attribution_required': False,
           'kind': 'pack', 'modifications': 'selected files converted/copied by tools/import_audio.py'}
    write_source(folder, rec)
    return 'ok'


# ------------------------------------------------------------------ Wikimedia Commons

def commons(title, purpose):
    import time
    time.sleep(3.0)  # Wikimedia rate limits anonymous API clients
    folder = os.path.join(CACHE, 'commons', re.sub(r'[^A-Za-z0-9_.-]+', '_', title))
    if os.path.exists(os.path.join(folder, 'source.json')):
        return 'cached'
    api = ('https://commons.wikimedia.org/w/api.php?action=query&format=json&prop=imageinfo'
           '&iiprop=url|extmetadata|sha1&titles=' + urllib.parse.quote('File:' + title))
    pages = get_json(api)['query']['pages']
    page = next(iter(pages.values()))
    if 'imageinfo' not in page:
        raise RuntimeError(f'commons {title}: not found')
    ii = page['imageinfo'][0]
    em = ii.get('extmetadata', {})
    lic = em.get('LicenseShortName', {}).get('value', '')
    ok = any(k in lic.lower() for k in ('cc0', 'public domain', 'cc by 4.0', 'cc by 3.0', 'cc by 2.0', 'cc by-sa'))
    if not ok:
        raise RuntimeError(f'commons {title}: license {lic!r} not accepted')
    artist = re.sub('<[^>]+>', '', em.get('Artist', {}).get('value', 'unknown')).strip()
    save(os.path.join(folder, title.replace(' ', '_')), get(ii['url'], timeout=600))
    rec = {'source': 'Wikimedia Commons', 'title': title, 'url': ii.get('descriptionurl'), 'download_url': ii['url'],
           'authors': [artist], 'license': lic, 'license_url': em.get('LicenseUrl', {}).get('value', ''),
           'attribution_required': 'cc0' not in lic.lower() and 'public domain' not in lic.lower(),
           'share_alike': 'sa' in lic.lower().split(), 'kind': 'audio', 'purpose': purpose,
           'modifications': 'see the derived file\'s source.json'}
    write_source(folder, rec)
    return 'ok'


# ------------------------------------------------------------------ manifest

def collect_records():
    rows = []
    for base in (TP, os.path.join(GAME, 'assets'), os.path.join(GAME, 'addons')):
        for dirpath, _, names in os.walk(base):
            if 'source.json' in names:
                try:
                    rec = json.load(open(os.path.join(dirpath, 'source.json'), encoding='utf-8'))
                except Exception:
                    continue
                rec['_path'] = os.path.relpath(dirpath, ROOT).replace('\\', '/')
                rows.append(rec)
            if os.path.basename(dirpath) == 'sources':
                # Processed models keep one record per file: <folder>/sources/<id>.json describes <folder>/<id>.glb
                # (or <id>.gltf).
                for n in names:
                    if not n.endswith('.json'):
                        continue
                    try:
                        rec = json.load(open(os.path.join(dirpath, n), encoding='utf-8'))
                    except Exception:
                        continue
                    glb = os.path.join(os.path.dirname(dirpath), n[:-5] + '.glb')
                    if not os.path.exists(glb):
                        glb = glb[:-4] + '.gltf'
                    rec['_path'] = os.path.relpath(glb, ROOT).replace('\\', '/')
                    rows.append(rec)
    uniq = {r['_path']: r for r in rows}
    return sorted(uniq.values(), key=lambda r: (r.get('source', ''), r['_path']))


def write_manifest():
    rows = collect_records()
    lines = ['# Asset and dependency manifest', '',
             'Generated by `tools/fetch_assets.py --manifest` from every `source.json` in the project.',
             'Each folder\'s `source.json` also lists SHA-256 hashes of the shipped files.', '',
             '| Asset (project path) | Title | Source | Author(s) | License | Attribution | Modifications |',
             '|---|---|---|---|---|---|---|']
    for r in rows:
        authors = ', '.join(a for a in r.get('authors', []) if a)
        attr = 'required' if r.get('attribution_required') else 'not required'
        lines.append(f"| `{r['_path']}` | [{r.get('title', '')}]({r.get('url', '')}) | {r.get('source', '')} | "
                     f"{authors} | {r.get('license', '')} | {attr} | {r.get('modifications', '')} |")
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
    print('manifest rows:', len(rows))


def main():
    args = sys.argv[1:]
    if args == ['--manifest']:
        write_manifest()
        return
    src = json.load(open(SOURCES, encoding='utf-8'))
    sections = args or list(src.keys())
    failures = []
    for sec in sections:
        items = src.get(sec, {})
        for key, val in items.items():
            try:
                if sec == 'polyhaven_models':
                    res = ph_model(key, val or '1k')
                elif sec == 'polyhaven_textures':
                    res = ph_texture(key, val or '1k')
                elif sec == 'polyhaven_hdris':
                    res = ph_hdri(key, val or '2k')
                elif sec == 'sketchfab':
                    res = sketchfab(key, val['uid'], val.get('purpose', ''))
                elif sec == 'kenney':
                    res = kenney(key)
                elif sec == 'commons':
                    res = commons(key, val)
                else:
                    continue
                print(f'{sec}: {key}: {res}', flush=True)
            except Exception as e:  # keep going; report at the end
                failures.append(f'{sec}: {key}: {e}')
                print(f'{sec}: {key}: FAILED {e}', flush=True)
    write_manifest()
    if failures:
        print('\nFAILURES:\n  ' + '\n  '.join(failures))
        sys.exit(1)


if __name__ == '__main__':
    main()
