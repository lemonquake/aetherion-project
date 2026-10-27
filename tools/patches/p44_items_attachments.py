"""Attachment items now come from weapons.json (Defs.item builds them), so items.json drops its own copies.

    python -I tools/patches/p44_items_attachments.py
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'game', 'data', 'items.json')
d = json.load(open(p, encoding='utf-8'))
for k in [k for k, v in d['items'].items() if v.get('kind') == 'attachment']:
    del d['items'][k]
for k, v in d['items'].items():
    if k.startswith('ammo_') or k in ('battery', 'bandage', 'painkillers', 'splint', 'backpack_small', 'backpack_large'):
        v['model'] = k
d['_doc'] = d['_doc'] + " Weapon attachments are items too; their entries come from weapons.json (attachments)."
json.dump(d, open(p, 'w', encoding='utf-8', newline='\n'), indent=1, ensure_ascii=False)
print('items', len(d['items']))
