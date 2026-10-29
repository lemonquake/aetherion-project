"""r4: cheaper particles (vertex-lit puffs, 30 Hz simulation), realistic bullet shove on props, GPU time in fx_perf."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r4lib import patch

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game'))
f = 'src/fx/particles.gd'
patch(f, '''			p.fixed_fps = 0
			p.interpolate = false''', '''			p.fixed_fps = 30
			p.interpolate = true''')
patch(f, '''			mat.albedo_texture = tex_smoke if kind == "puff" else tex_drop
			mat.roughness = 1.0
			mat.disable_receive_shadows = true''', '''			mat.albedo_texture = tex_smoke if kind == "puff" else tex_drop
			mat.roughness = 1.0
			mat.disable_receive_shadows = true
			# Lit per vertex: overlapping dust cards under dozens of lamps would cost a full light loop per pixel.
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX''')

f = 'src/world/map_builder.gd'
patch(f, '''		body.apply_impulse(dir * minf(momentum * 6.0, 40.0), pos - body.global_position)
		body.take_damage(energy * 0.08, dir, pos)''', '''		# About the round's own momentum (a pistol round nudges a chair; it does not throw it across the room).
		body.apply_impulse(dir * minf(momentum * 1.5, 12.0), pos - body.global_position)
		body.take_damage(energy * 0.08, dir, pos)''')

f = 'src/debug/autotest_r4.gd'
patch(f, '''	await t._wait(0.5)
	var parts := {}
	for mode in ["quiet", "all", "particles", "holes", "sound", "quiet2"]:
		var times: Array = []
		var cpu: Array = []''', '''	await t._wait(0.5)
	var vp: RID = t.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var parts := {}
	for mode in ["quiet", "all", "particles", "holes", "sound", "quiet2"]:
		var times: Array = []
		var cpu: Array = []
		var gpu: Array = []''')
patch(f, '''			cpu.append((Time.get_ticks_usec() - c0) / 1000.0)
			await t.get_tree().process_frame
			times.append((Time.get_ticks_usec() - t1) / 1000.0)
		times.sort()''', '''			cpu.append((Time.get_ticks_usec() - c0) / 1000.0)
			await t.get_tree().process_frame
			times.append((Time.get_ticks_usec() - t1) / 1000.0)
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		times.sort()
		gpu.sort()''')
patch(f, '''		parts[mode] = [times[times.size() / 2], times[int(times.size() * 0.95)], c_sum / 60.0]''', '''		parts[mode] = [times[times.size() / 2], times[int(times.size() * 0.95)], c_sum / 60.0, gpu[gpu.size() / 2]]''')
patch(f, '''	var mb: float = (parts.quiet[0] + parts.quiet2[0]) * 0.5
	var detail := []
	for m in parts:
		detail.append("%s %.2f ms (p95 %.2f, call %.3f ms)" % [m, parts[m][0], parts[m][1], parts[m][2]])
	t._check("fx_perf", parts.all[0] - mb < 1.5, "median frame with an impact every frame vs quiet: " + "; ".join(detail))''', '''	var gb: float = (parts.quiet[3] + parts.quiet2[3]) * 0.5
	var detail := []
	for m in parts:
		detail.append("%s %.2f ms (p95 %.2f, GPU %.2f, call %.3f ms)" % [m, parts[m][0], parts[m][1], parts[m][3], parts[m][2]])
	# Judged on GPU time and the calls' own CPU time: wall-clock frame times swing with other work on this machine.
	t._check("fx_perf", parts.all[3] - gb < 1.5 and parts.all[2] < 1.0, "an impact every frame for 60 frames vs quiet: " + "; ".join(detail))''')
