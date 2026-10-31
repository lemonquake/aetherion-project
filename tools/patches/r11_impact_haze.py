"""r11: bullet hits leave a slow cloud that hangs for a few seconds (dust on concrete and plaster, soil on dirt,
sawdust haze on wood, a thin grey wisp off metal), on top of the fast puff and debris they already throw.
    python -I tools/patches/r11_impact_haze.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

p = Patch('game/src/fx/particles.gd')
p.rep('''	"casing": {"mesh": "brass",''', '''	# r11: the after-cloud of a hit, slow and wide, hanging 3-4 s and drifting up a little.
	"haze": {"mesh": "puff", "amount": 4, "life": 3.6, "vel": [0.12, 0.45], "spread": 70.0, "gravity": 0.06, "damp": 1.1,
		"scale": [0.22, 0.36], "grow": 3.4, "color": Color(0.62, 0.6, 0.56, 0.2)},
	"haze_soil": {"mesh": "puff", "amount": 4, "life": 3.2, "vel": [0.12, 0.5], "spread": 60.0, "gravity": 0.03, "damp": 1.1,
		"scale": [0.24, 0.38], "grow": 3.2, "color": Color(0.42, 0.35, 0.26, 0.24)},
	"haze_wood": {"mesh": "puff", "amount": 3, "life": 3.0, "vel": [0.1, 0.4], "spread": 70.0, "gravity": 0.05, "damp": 1.2,
		"scale": [0.18, 0.3], "grow": 3.0, "color": Color(0.66, 0.56, 0.42, 0.18)},
	"wisp": {"mesh": "puff", "amount": 3, "life": 2.6, "vel": [0.15, 0.5], "spread": 40.0, "gravity": 0.25, "damp": 1.0,
		"scale": [0.1, 0.18], "grow": 3.6, "color": Color(0.5, 0.5, 0.5, 0.2)},
	"casing": {"mesh": "brass",''')
p.save()

p = Patch('game/src/fx/effects.gd')
p.rep('''const IMPACT_FX := {
	"metal": ["sparks"], "wood": ["splinters", "sawdust"], "glass": ["shards"], "flesh": ["blood_mist", "blood"],
	"dirt": ["soil", "soil_dust"], "fabric": ["lint"], "plastic": ["chips", "lint"], "foliage": ["leaves"],
	"concrete": ["dust", "chips"],
}''', '''const IMPACT_FX := {
	"metal": ["sparks", "wisp"], "wood": ["splinters", "sawdust", "haze_wood"], "glass": ["shards"], "flesh": ["blood_mist", "blood"],
	"dirt": ["soil", "soil_dust", "haze_soil"], "fabric": ["lint"], "plastic": ["chips", "lint"], "foliage": ["leaves"],
	"concrete": ["dust", "chips", "haze"],
}''')
p.save()
