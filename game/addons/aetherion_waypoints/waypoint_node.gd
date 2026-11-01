@tool
extends Node3D
## (r23) One waypoint of a map's bot graph (src/ai/waypoints.gd) in the map editor. Its node name is its id
## (MM3-0412: map, level, number). Move it with the gizmo, duplicate it (Ctrl+D: the copy keeps the links), delete it,
## or set what it is below. Saved for the game with the Waypoints node's "Save for the game".

const COLORS := {"road": Color(0.95, 0.85, 0.2), "junction": Color(1.0, 0.6, 0.1), "plaza": Color(0.9, 0.9, 0.5),
	"area": Color(0.35, 0.85, 0.35), "corner": Color(0.2, 0.55, 0.3), "door": Color(0.2, 0.85, 1.0),
	"stair": Color(1.0, 0.35, 1.0), "escalator": Color(1.0, 0.35, 1.0), "hide": Color(0.65, 0.35, 1.0),
	"snipe": Color(1.0, 0.2, 0.2), "cover": Color(1.0, 0.6, 0.8)}

## What this place is. road / junction / plaza / area / corner: walking places; door: beside a door; stair /
## escalator: on one (escalators run one way); hide / snipe / cover: places bots hold (they face this node's forward,
## the blue arrow, when "faces" is on).
@export_enum("road", "junction", "plaza", "area", "corner", "door", "stair", "escalator", "hide", "snipe", "cover") var kind := "area":
	set(v):
		kind = v
		_look()
## 1 main road (routes prefer it), 2 secondary, 3 side way.
@export_range(1, 3) var priority := 2:
	set(v):
		priority = v
		_look()
## A name people know the place by (a shop, a court); the game fills it in when empty.
@export var place_name := ""
## Hold places: face this node's forward (-Z, the arrow) instead of the longest view the game finds.
@export var faces := false:
	set(v):
		faces = v
		_look()
## The waypoints joined to this one, by name. A join works both ways unless its kind is e (an escalator, one way from
## here). Use the toolbar's Link / Unlink rather than typing here.
@export var links: PackedStringArray = []
## Per link: w walk, t tight, d door, s stair, e escalator, v wade. The game's check sets walk / tight / door itself.
@export var link_kinds: PackedStringArray = []
## A point part way along a stair or an escalator (off the floor's walk).
@export var via := false

var _mi: MeshInstance3D = null
var _arrow: MeshInstance3D = null
var _label: Label3D = null
static var _mats := {}
static var _sphere: SphereMesh = null
static var _cone: CylinderMesh = null


func _ready() -> void:
	if Engine.is_editor_hint():
		_look()


func _look() -> void:
	if not is_inside_tree() or not Engine.is_editor_hint():
		return
	if _mi == null:
		if _sphere == null:
			_sphere = SphereMesh.new()
			_sphere.radius = 0.5
			_sphere.height = 1.0
			_sphere.radial_segments = 8
			_sphere.rings = 4
			_cone = CylinderMesh.new()
			_cone.top_radius = 0.0
			_cone.bottom_radius = 0.18
			_cone.height = 0.7
			_cone.radial_segments = 6
		_mi = MeshInstance3D.new()
		_mi.mesh = _sphere
		_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mi, false, Node.INTERNAL_MODE_FRONT)
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.font_size = 28
		_label.pixel_size = 0.0025
		_label.position = Vector3(0, 0.6, 0)
		_label.visibility_range_end = 9.0
		_label.outline_size = 6
		add_child(_label, false, Node.INTERNAL_MODE_FRONT)
	var r := {1: 0.32, 2: 0.24, 3: 0.17}.get(priority, 0.24) as float
	if kind in ["hide", "snipe", "cover", "door"]:
		r = maxf(r, 0.26)
	_mi.scale = Vector3.ONE * r * 2.0
	_mi.position = Vector3(0, 0.25, 0)
	_mi.material_override = _mat(kind)
	_label.text = "%s\n%s P%d" % [name, kind, priority]
	if faces and kind in ["hide", "snipe", "cover"]:
		if _arrow == null:
			_arrow = MeshInstance3D.new()
			_arrow.mesh = _cone
			_arrow.rotation = Vector3(-PI / 2.0, 0, 0)
			_arrow.position = Vector3(0, 0.25, -0.55)
			_arrow.material_override = _mat("door")
			add_child(_arrow, false, Node.INTERNAL_MODE_FRONT)
		_arrow.visible = true
	elif _arrow != null:
		_arrow.visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_POST_SAVE or what == NOTIFICATION_PATH_RENAMED:
		if _label != null:
			_label.text = "%s\n%s P%d" % [name, kind, priority]


static func _mat(k: String) -> StandardMaterial3D:
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = COLORS.get(k, Color.WHITE)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mats[k] = m
	return _mats[k]


func link_to(other: Node, code: String = "w") -> void:
	if other == self or str(other.name) in links:
		return
	links.append(str(other.name))
	link_kinds.append(code)


func unlink(other_name: String) -> void:
	var i := links.find(other_name)
	while i >= 0:
		links.remove_at(i)
		if i < link_kinds.size():
			link_kinds.remove_at(i)
		i = links.find(other_name)
