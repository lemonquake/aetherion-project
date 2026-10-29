extends Node3D
## Pooled particle effects. Every kind is a handful of one-shot GPUParticles3D made once when the match loads (and
## drawn once by the loading warm-up, so no shader compiles mid-fight); emit() moves the next free emitter of that
## kind to the spot, points it along the surface normal and restarts it. No node, mesh or material is created per
## shot. Works on Forward+, Mobile and the OpenGL fallback.

const FX := "res://assets/fx/"
const POOL := 6

## kind -> settings. mesh: "puff" (soft billboard), "streak" (velocity-aligned glowing streak), "chip" (small lit
## box), "sliver" (thin box aligned to its flight), "drop" (small soft billboard), "flake" (flat spinning card).
const KINDS := {
	"dust": {"mesh": "puff", "amount": 5, "life": 1.5, "vel": [0.4, 1.3], "spread": 50.0, "gravity": -0.25, "damp": 1.8,
		"scale": [0.1, 0.2], "grow": 2.4, "color": Color(0.6, 0.58, 0.54, 0.38)},
	"chips": {"mesh": "chip", "amount": 9, "life": 0.9, "vel": [2.0, 5.5], "spread": 40.0, "gravity": -9.8, "damp": 0.3,
		"scale": [0.008, 0.022], "grow": 1.0, "color": Color(0.5, 0.48, 0.45)},
	"splinters": {"mesh": "sliver", "amount": 8, "life": 0.9, "vel": [2.0, 5.0], "spread": 45.0, "gravity": -9.8, "damp": 0.4,
		"scale": [0.012, 0.03], "grow": 1.0, "color": Color(0.62, 0.48, 0.3)},
	"sawdust": {"mesh": "puff", "amount": 3, "life": 1.0, "vel": [0.3, 1.0], "spread": 50.0, "gravity": -0.4, "damp": 2.0,
		"scale": [0.07, 0.14], "grow": 2.0, "color": Color(0.62, 0.5, 0.36, 0.3)},
	"sparks": {"mesh": "streak", "amount": 16, "life": 0.35, "vel": [4.0, 11.0], "spread": 50.0, "gravity": -9.8, "damp": 0.5,
		"scale": [0.02, 0.05], "grow": 0.4, "color": Color(1.0, 0.72, 0.3), "glow": 4.0},
	"shards": {"mesh": "flake", "amount": 10, "life": 1.0, "vel": [1.0, 3.5], "spread": 60.0, "gravity": -9.8, "damp": 0.2,
		"scale": [0.012, 0.035], "grow": 1.0, "color": Color(0.75, 0.85, 0.88, 0.85)},
	"soil": {"mesh": "chip", "amount": 10, "life": 0.9, "vel": [1.5, 4.5], "spread": 30.0, "gravity": -9.8, "damp": 0.3,
		"scale": [0.012, 0.035], "grow": 1.0, "color": Color(0.24, 0.18, 0.12)},
	"soil_dust": {"mesh": "puff", "amount": 6, "life": 1.4, "vel": [0.5, 1.8], "spread": 35.0, "gravity": -0.6, "damp": 1.4,
		"scale": [0.12, 0.25], "grow": 2.4, "color": Color(0.36, 0.29, 0.21, 0.45)},
	"splash": {"mesh": "drop", "amount": 18, "life": 0.9, "vel": [2.0, 5.0], "spread": 18.0, "gravity": -9.8, "damp": 0.2,
		"scale": [0.03, 0.07], "grow": 0.8, "color": Color(0.75, 0.82, 0.85, 0.75)},
	"mist": {"mesh": "puff", "amount": 5, "life": 0.9, "vel": [0.6, 1.6], "spread": 40.0, "gravity": -0.8, "damp": 2.0,
		"scale": [0.12, 0.25], "grow": 2.0, "color": Color(0.8, 0.85, 0.88, 0.3)},
	"blood": {"mesh": "drop", "amount": 18, "life": 0.7, "vel": [1.5, 5.5], "spread": 30.0, "gravity": -9.8, "damp": 0.5,
		"scale": [0.007, 0.022], "grow": 0.9, "color": Color(0.26, 0.015, 0.015, 0.95)},
	"blood_mist": {"mesh": "puff", "amount": 6, "life": 0.35, "vel": [0.8, 2.2], "spread": 35.0, "gravity": -0.5, "damp": 4.0,
		"scale": [0.03, 0.07], "grow": 1.7, "color": Color(0.24, 0.02, 0.02, 0.32)},
	"lint": {"mesh": "puff", "amount": 4, "life": 0.9, "vel": [0.3, 1.0], "spread": 50.0, "gravity": -0.2, "damp": 2.0,
		"scale": [0.06, 0.12], "grow": 1.8, "color": Color(0.72, 0.7, 0.67, 0.3)},
	"leaves": {"mesh": "flake", "amount": 8, "life": 1.6, "vel": [0.6, 2.0], "spread": 70.0, "gravity": -2.0, "damp": 1.2,
		"scale": [0.02, 0.05], "grow": 1.0, "color": Color(0.22, 0.32, 0.14)},
	"muzzle": {"mesh": "puff", "amount": 5, "life": 1.3, "vel": [0.3, 1.2], "spread": 25.0, "gravity": 0.35, "damp": 2.4,
		"scale": [0.06, 0.14], "grow": 3.5, "color": Color(0.7, 0.7, 0.7, 0.28)},
	"chunk_dust": {"mesh": "puff", "amount": 8, "life": 1.8, "vel": [0.4, 1.4], "spread": 80.0, "gravity": -0.2, "damp": 1.6,
		"scale": [0.15, 0.3], "grow": 2.2, "color": Color(0.55, 0.5, 0.44, 0.35)},
	"fire": {"mesh": "puff", "amount": 14, "life": 0.45, "vel": [2.0, 6.0], "spread": 90.0, "gravity": 1.0, "damp": 6.0,
		"scale": [0.6, 1.2], "grow": 2.0, "color": Color(1.0, 0.55, 0.18, 0.9), "glow": 3.0},
	"smoke": {"mesh": "puff", "amount": 16, "life": 3.6, "vel": [0.6, 2.6], "spread": 80.0, "gravity": 0.45, "damp": 1.2,
		"scale": [0.8, 1.6], "grow": 2.6, "color": Color(0.22, 0.21, 0.2, 0.62)},
	"casing": {"mesh": "brass", "amount": 1, "life": 0.75, "vel": [1.6, 2.6], "spread": 22.0, "gravity": -9.8, "damp": 0.2,
		"scale": [0.011, 0.011], "grow": 1.0, "color": Color(0.82, 0.62, 0.28), "pool": 12},
	"blast_debris": {"mesh": "chip", "amount": 24, "life": 1.4, "vel": [5.0, 13.0], "spread": 85.0, "gravity": -9.8, "damp": 0.3,
		"scale": [0.02, 0.05], "grow": 1.0, "color": Color(0.28, 0.26, 0.24)},
}

var pools := {}    # kind -> [GPUParticles3D]
var _next := {}    # kind -> next index
var scale_amount := 1.0
var emitted := {}  # kind -> count (tests)


func setup() -> void:
	scale_amount = 0.6 if Settings.is_mobile() else 1.0
	var tex_smoke: Texture2D = load(FX + "fx_smoke.png")
	var tex_spark: Texture2D = load(FX + "fx_spark.png")
	var tex_drop: Texture2D = load(FX + "fx_drop.png")
	for kind in KINDS:
		var k: Dictionary = KINDS[kind]
		var draw := _draw_mesh(str(k.mesh), k, tex_smoke, tex_spark, tex_drop)
		var pm := _process_material(k)
		var list := []
		for i in int(k.get("pool", POOL)):
			var p := GPUParticles3D.new()
			p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved from _process
			p.one_shot = true
			p.emitting = false
			p.amount = maxi(int(round(float(k.amount) * scale_amount)), 2)
			p.lifetime = float(k.life)
			p.explosiveness = 1.0
			p.randomness = 0.3
			p.local_coords = false
			p.fixed_fps = 30
			p.interpolate = true
			p.process_material = pm
			p.draw_pass_1 = draw
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var ext := maxf(float(k.vel[1]) * float(k.life) * 0.7, 2.5)
			p.visibility_aabb = AABB(Vector3(-ext, -ext, -ext), Vector3(ext, ext, ext) * 2.0)
			p.layers = Defs.RENDER_WORLD | Defs.RENDER_INTERIOR
			add_child(p)
			list.append(p)
		pools[kind] = list
		_next[kind] = 0


func _process_material(k: Dictionary) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = float(k.spread)
	m.initial_velocity_min = float(k.vel[0])
	m.initial_velocity_max = float(k.vel[1])
	m.gravity = Vector3(0, float(k.gravity), 0)
	m.damping_min = float(k.damp) * 0.7
	m.damping_max = float(k.damp)
	m.scale_min = float(k.scale[0])
	m.scale_max = float(k.scale[1])
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.03 if str(k.mesh) != "puff" else 0.08
	var c: Color = k.color
	var grad := Gradient.new()
	grad.set_color(0, c)
	grad.set_color(1, Color(c.r, c.g, c.b, 0.0))
	if str(k.mesh) == "puff":
		grad.add_point(0.15, c)
	elif str(k.mesh) == "streak":
		grad.set_color(0, Color(1.0, 0.95, 0.8, c.a))
		grad.add_point(0.4, c)
	else:
		grad.add_point(0.75, c)
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	gt.width = 64
	m.color_ramp = gt
	var grow := float(k.get("grow", 1.0))
	if absf(grow - 1.0) > 0.01:
		var curve := Curve.new()
		curve.max_value = maxf(grow, 1.0)
		curve.add_point(Vector2(0, 1.0 if grow > 1.0 else 1.0))
		curve.add_point(Vector2(1, grow))
		var ct := CurveTexture.new()
		ct.curve = curve
		m.scale_curve = ct
	match str(k.mesh):
		"puff":
			m.angle_min = -180.0
			m.angle_max = 180.0
			m.angular_velocity_min = -30.0
			m.angular_velocity_max = 30.0
		"streak", "sliver":
			m.particle_flag_align_y = true
		"brass":
			m.angle_min = -180.0
			m.angle_max = 180.0
			m.angular_velocity_min = -900.0
			m.angular_velocity_max = 900.0
			m.particle_flag_rotate_y = true
		"chip", "flake":
			m.angle_min = -180.0
			m.angle_max = 180.0
			m.angular_velocity_min = -720.0
			m.angular_velocity_max = 720.0
			m.particle_flag_rotate_y = true
	return m


func _draw_mesh(kind: String, k: Dictionary, tex_smoke: Texture2D, tex_spark: Texture2D, tex_drop: Texture2D) -> Mesh:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	var mesh: Mesh
	match kind:
		"puff", "drop":
			var q := QuadMesh.new()
			q.size = Vector2(1, 1)
			mesh = q
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			mat.albedo_texture = tex_smoke if kind == "puff" else tex_drop
			mat.roughness = 1.0
			mat.disable_receive_shadows = true
			# Lit per vertex: overlapping dust cards under dozens of lamps would cost a full light loop per pixel.
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
			# Soft edges where a card meets a wall or the floor (needs the depth buffer: not on the OpenGL fallback).
			if RenderingServer.get_current_rendering_method() != "gl_compatibility":
				mat.proximity_fade_enabled = true
				mat.proximity_fade_distance = 0.35
			if k.has("glow"):
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			elif kind == "drop":
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"streak":
			var q2 := QuadMesh.new()
			q2.size = Vector2(0.35, 4.0)
			mesh = q2
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			mat.billboard_keep_scale = true
			mat.albedo_texture = tex_spark
		"sliver":
			var b := BoxMesh.new()
			b.size = Vector3(0.35, 3.0, 0.2)
			mesh = b
			mat.roughness = 0.9
		"flake":
			var b2 := BoxMesh.new()
			b2.size = Vector3(1.0, 0.12, 0.8)
			mesh = b2
			mat.roughness = 0.15 if k.color.b > 0.6 else 0.8
			mat.metallic_specular = 0.8
			if k.color.a < 1.0:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		"brass":
			# A spent case: a short brass tube (9 mm about 19 mm long; scale sets the size).
			var cy := CylinderMesh.new()
			cy.top_radius = 0.45
			cy.bottom_radius = 0.5
			cy.height = 2.0
			cy.radial_segments = 6
			cy.rings = 0
			mesh = cy
			mat.metallic = 0.9
			mat.roughness = 0.3
		_:
			var b3 := BoxMesh.new()
			b3.size = Vector3(1.0, 0.7, 0.85)
			mesh = b3
			mat.roughness = 0.95
	if k.has("glow") and kind == "streak":
		mat.albedo_color = Color(1, 1, 1) * float(k.glow) * 0.35
	mesh.surface_set_material(0, mat)
	return mesh


func emit(kind: String, pos: Vector3, normal: Vector3 = Vector3.UP, size: float = 1.0) -> void:
	var list: Array = pools.get(kind, [])
	if list.is_empty():
		return
	var i: int = _next[kind]
	_next[kind] = (i + 1) % list.size()
	var p: GPUParticles3D = list[i]
	var up := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	# Clouds start a little off the surface, so their cards do not cut into it.
	var lift := 0.12 if str(KINDS[kind].mesh) == "puff" else 0.02
	p.global_transform = Transform3D(Basis(x, up, z), pos + up * lift)
	p.amount_ratio = clampf(size, 0.25, 1.0)
	p.restart()
	emitted[kind] = int(emitted.get(kind, 0)) + 1


func warm(at: Transform3D) -> void:
	## Shown once in front of the loading screen's warm-up camera: process and draw shaders compile now.
	for kind in pools:
		emit(kind, at.origin + Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), 0.0), Vector3.UP, 1.0)
