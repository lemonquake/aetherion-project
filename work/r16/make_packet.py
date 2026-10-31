"""Blind review packet: the same viewpoints from two builds, labelled A and B in a random order per run. The mapping
goes to work/r16/critic_private/mapping.json (never into the packet).

    python -I work/r16/make_packet.py <before_dir> <after_dir> <packet_dir> <seed>
"""
import json, os, random, shutil, sys

before, after, packet, seed = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
views = ['atrium_l1', 'north_walk_l2', 'east_court_l3', 'west_court_l1', 'food_l5', 'walk_l4', 'dept_l2', 'dept_l1', 'restroom_l3', 'plaza_south']
r = random.Random(seed)
a_is_after = r.random() < 0.5
os.makedirs(packet, exist_ok=True)
for f in os.listdir(packet):
    os.remove(os.path.join(packet, f))
for i, v in enumerate(views):
    src_a = os.path.join(after if a_is_after else before, v + '_t450.png')
    src_b = os.path.join(before if a_is_after else after, v + '_t450.png')
    shutil.copy(src_a, os.path.join(packet, 'A_%02d.png' % (i + 1)))
    shutil.copy(src_b, os.path.join(packet, 'B_%02d.png' % (i + 1)))
priv = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'critic_private')
os.makedirs(priv, exist_ok=True)
with open(os.path.join(priv, 'mapping_%s.json' % os.path.basename(packet.rstrip('/\\'))), 'w') as f:
    json.dump({'A': 'after' if a_is_after else 'before', 'B': 'before' if a_is_after else 'after', 'seed': seed, 'views': views}, f, indent=1)
print('packet ready:', len(views), 'pairs')
