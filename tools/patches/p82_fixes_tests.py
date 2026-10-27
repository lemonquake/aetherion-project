"""--autotest=fixes: checks for T/E, ping and minimap, doors, vaulting through windows and trash."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

t = Patch('game/src/debug/autotest_fixes.gd')
if '_grab_vs_use()' not in t.s:
    t.rep('''	await _tab_opens_box()
	for f in extra:''', '''	await _tab_opens_box()
	await _grab_vs_use()
	await _ping_minimap()
	await _doors()
	await _vault_window()
	await _trash_pass()
	for f in extra:''')
    t.s += open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'p82_fixes_tests.gd.txt'), encoding='utf-8').read()
    t.save()
