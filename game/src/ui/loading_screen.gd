extends CanvasLayer
## The loading screen: key art, the map and mode, a progress bar with what is being built right now, and a rotating
## line of nonsense to read while it fills. Up from the moment a match starts loading until it begins.
##
## The map is built in one long synchronous call (10-25 s), so nothing in the scene tree runs meanwhile. Everything
## here is drawn straight onto a canvas item of its own with RenderingServer calls, and progress() redraws the
## window itself (RenderingServer.force_draw) a few times a second while `sync` is set. After the build the same
## painter runs from _process (bar easing, waiting for the other players, then a fade into the match).

const JOKES := [
	"Asking a tricycle driver for directions. He says \"diyan lang\".",
	"Teaching the bots that walls are not doors.",
	"Counting balut. Lost count. Starting over.",
	"Untangling the wires on every lamp post. Gave up. Added more.",
	"Reminding the haze it was not invited.",
	"Polishing jeepney chrome to a mirror finish.",
	"Hiding the good loot under the bed, the way Lola would.",
	"Bribing the guard dog with pandesal.",
	"Convincing the roosters it is not 4 AM yet.",
	"Charging every SmarTab off the neighbour's extension cord.",
	"Laying hollow blocks one tsismis at a time.",
	"Painting lane lines nobody will follow.",
	"Telling the snipers the karaoke booth is not a sniper nest.",
	"Warming up the videoke for the victory song.",
	"Restocking the sari-sari store with ammo and chichirya.",
	"Explaining to Mang Kanor that this is a firefight, not a fiesta.",
	"Asking Marites what she heard. She heard everything.",
	"Taking in laundry that has hung on the line since 2019.",
	"Oiling every door hinge for maximum creak.",
	"Sweeping the rubble into piles you can walk through.",
	"Pointing a laser at the cat. The cat is unimpressed.",
	"Filling the canals with water of unknown origin.",
	"Handing out brains to the bots. Some got the big ones.",
	"Reminding Kuya Bert that crouching is not hiding.",
	"Negotiating the parking with Tito Boy's owner-type jeep.",
	"Unrolling banig mats in every bedroom.",
	"Flicking the faulty porch light until it works. It does not.",
	"Teaching the bots to say \"this way\" and mean it.",
	"Putting the tsinelas by the door. Shoes off inside, please.",
	"Rehearsing \"Bakit ka nandito?\" in every accent.",
]
const TIPS := [
	"Middle mouse pings the spot you look at for your team; your bots answer it.",
	"Hold V to point your laser. Enemies can follow the beam back to you.",
	"Bots with a role you can guess: rushers, campers, snipers and stalkers.",
	"Rubble, trash bags and junk heaps no longer stop you. Walls still do.",
	"The haze shrinks the play area. Smart bots leave early; so should you.",
	"Kerbs and low steps are climbed by walking into them, from any angle.",
	"A bot that says \"I'll go with you\" follows you until you lose it.",
]

var sync := false
var title := ""
var subtitle := ""
var _ci := RID()
var _root: Control
var _bg: Texture2D
var _frac := 0.0          # reported
var _shown := 0.0         # drawn (eases toward _frac)
var _what := "Getting ready"
var _joke_i := 0
var _joke_t := 0.0
var _tip := ""
var _last_paint_us := 0
var _fade := 1.0
var _closing := false
var _t0_us := 0
var _shot_done := false
var _draws := 0


func _init(map_title: String = "", mode_title: String = "") -> void:
	title = map_title
	subtitle = mode_title
	layer = 60


func _ready() -> void:
	UITheme.get_theme()   # loads the fonts
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_ci = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_ci, _root.get_canvas_item())
	for img in ["lobby_bg", "menu_bg"]:
		var p := "res://assets/ui/%s.jpg" % img
		if ResourceLoader.exists(p):
			_bg = load(p)
			break
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_joke_i = rng.randi_range(0, JOKES.size() - 1)
	_tip = TIPS[rng.randi_range(0, TIPS.size() - 1)]
	_t0_us = Time.get_ticks_usec()
	_paint()


func _exit_tree() -> void:
	if _ci.is_valid():
		RenderingServer.free_rid(_ci)
		_ci = RID()


func progress(frac: float, what: String) -> void:
	## Called during loading (also from inside the synchronous map build). Redraws at most ~16 times a second.
	_frac = clampf(maxf(_frac, frac), 0.0, 1.0)
	if what != "":
		_what = what
	if not sync:
		return
	var now := Time.get_ticks_usec()
	if now - _last_paint_us < 60000:
		return
	var dt := (now - _last_paint_us) / 1000000.0 if _last_paint_us > 0 else 0.0
	_last_paint_us = now
	_shown = _frac
	_advance_joke(minf(dt, 0.5))
	_paint()
	if OS.get_name() in ["Windows", "Linux", "macOS", "FreeBSD"]:
		# Keeps the window from being marked "not responding" during a long build.
		DisplayServer.process_events()
	RenderingServer.force_draw(true, 0.0)
	_draws += 1
	if not _shot_done and _frac >= 0.5 and Game.arg("loadshot") != null:
		# Tests: what the screen showed half way through the build.
		_shot_done = true
		DirAccess.make_dir_recursive_absolute(str(Game.arg("loadshot")).get_base_dir())
		get_viewport().get_texture().get_image().save_png(str(Game.arg("loadshot")))
		print("[loading] shot %s at %d%% after %d redraws: %s (frames drawn %d, in tree %s, ci %s, layer %d, visible %s, viewport %s)" % [str(Game.arg("loadshot")), int(_frac * 100.0), _draws, _what,
			Engine.get_frames_drawn(), str(is_inside_tree()), str(_ci.is_valid()), layer, str(visible), str(get_viewport().get_visible_rect().size)])


func finish() -> void:
	## The match has begun: fill the bar and fade out.
	_frac = 1.0
	_what = "Go!"
	_closing = true


func _advance_joke(dt: float) -> void:
	_joke_t += dt
	if _joke_t > 3.6:
		_joke_t = 0.0
		_joke_i = (_joke_i + 1) % JOKES.size()


func _process(dt: float) -> void:
	_shown = move_toward(_shown, _frac, dt * maxf(0.6, (_frac - _shown) * 3.0))
	_advance_joke(dt)
	if _closing and _shown >= 0.999:
		_fade = move_toward(_fade, 0.0, dt * 2.2)
		if _fade <= 0.0:
			queue_free()
			return
	_paint()


func _paint() -> void:
	if not _ci.is_valid() or not is_inside_tree():
		return
	var vs := get_viewport().get_visible_rect().size
	var a := _fade
	RenderingServer.canvas_item_clear(_ci)
	RenderingServer.canvas_item_add_rect(_ci, Rect2(Vector2.ZERO, vs), Color(0.015, 0.017, 0.022, a))
	if _bg:
		# Cover the screen, keep the art's aspect, drift a little.
		var ts := Vector2(_bg.get_width(), _bg.get_height())
		var k := maxf(vs.x / ts.x, vs.y / ts.y) * 1.06
		var t := (Time.get_ticks_usec() - _t0_us) / 1000000.0
		var off := Vector2(sin(t * 0.07) * 0.02, cos(t * 0.05) * 0.015) * vs
		var r := Rect2((vs - ts * k) * 0.5 + off, ts * k)
		RenderingServer.canvas_item_add_texture_rect(_ci, r, _bg.get_rid(), false, Color(0.62, 0.64, 0.68, a))
	# Darken toward the bottom where the text sits, and the top edge.
	var bands := 24
	for i in bands:
		var y0 := vs.y * (0.45 + 0.55 * i / bands)
		var al := 0.85 * pow(float(i + 1) / bands, 1.4)
		RenderingServer.canvas_item_add_rect(_ci, Rect2(0, y0, vs.x, vs.y * 0.55 / bands + 1.0), Color(0.01, 0.012, 0.016, al * a))
	RenderingServer.canvas_item_add_rect(_ci, Rect2(0, 0, vs.x, vs.y * 0.12), Color(0.01, 0.012, 0.016, 0.45 * a))
	var fc: Font = UITheme.font_condensed if UITheme.font_condensed else ThemeDB.fallback_font
	var fs: Font = UITheme.font_semibold if UITheme.font_semibold else ThemeDB.fallback_font
	var fr: Font = UITheme.font_regular if UITheme.font_regular else ThemeDB.fallback_font
	var m := clampf(vs.x * 0.05, 28.0, 90.0)
	var accent := Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, a)
	var text := Color(0.9, 0.92, 0.9, a)
	var dim := Color(0.7, 0.73, 0.72, a * 0.9)
	var outline := Color(0, 0, 0, 0.6 * a)
	# Title block, lower left.
	var base_y := vs.y - m - 150.0
	fs.draw_string(_ci, Vector2(m, base_y - 96.0), "LOADING", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, accent)
	fc.draw_string_outline(_ci, Vector2(m, base_y - 36.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, 6, outline)
	fc.draw_string(_ci, Vector2(m, base_y - 36.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, text)
	if subtitle != "":
		fs.draw_string(_ci, Vector2(m, base_y), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, dim)
	# The bar.
	var bw := vs.x - m * 2.0
	var by := vs.y - m - 70.0
	var bh := 10.0
	RenderingServer.canvas_item_add_rect(_ci, Rect2(m, by, bw, bh), Color(1, 1, 1, 0.1 * a))
	var fw := bw * clampf(_shown, 0.0, 1.0)
	RenderingServer.canvas_item_add_rect(_ci, Rect2(m, by, fw, bh), accent)
	# A glint running along the filled part.
	var gt := fmod((Time.get_ticks_usec() - _t0_us) / 1000000.0 * 0.6, 1.0)
	if fw > 30.0:
		var gx := m + fw * gt
		RenderingServer.canvas_item_add_rect(_ci, Rect2(gx - 14.0, by, 28.0, bh), Color(1, 0.95, 0.8, 0.35 * a))
	RenderingServer.canvas_item_add_rect(_ci, Rect2(m + fw - 3.0, by - 4.0, 6.0, bh + 8.0), Color(1.0, 0.92, 0.7, 0.9 * a))
	var pct := "%d%%" % int(round(_shown * 100.0))
	fc.draw_string(_ci, Vector2(m + bw - 120.0, by - 16.0), pct, HORIZONTAL_ALIGNMENT_RIGHT, 120.0, 40, text)
	fs.draw_string(_ci, Vector2(m, by - 16.0), _what + _dots(), HORIZONTAL_ALIGNMENT_LEFT, bw - 140.0, 24, text)
	# The joke under the bar, the tip above the title.
	var joke: String = JOKES[_joke_i]
	fr.draw_string(_ci, Vector2(m, by + bh + 38.0), joke, HORIZONTAL_ALIGNMENT_LEFT, bw, 22, dim)
	fr.draw_string(_ci, Vector2(m, m + 24.0), "Tip: " + _tip, HORIZONTAL_ALIGNMENT_LEFT, vs.x - m * 2.0, 20, Color(0.82, 0.84, 0.8, 0.8 * a))


func _dots() -> String:
	if _closing:
		return ""
	var n := int((Time.get_ticks_usec() - _t0_us) / 400000) % 4
	return ".".repeat(n)
