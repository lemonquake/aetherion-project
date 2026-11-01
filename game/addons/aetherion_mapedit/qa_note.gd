@tool
extends Node3D
## (r26) A QA note pinned on the map: what is wrong or should change, right where it is. Add one with the 3D toolbar's
## "Pin a note" and a click on the spot. Saved with the map (Save map / Ctrl+S) to res://maps/<id>/qa.json, which
## Claude reads, fixes, and answers in "reply" (then sets the status to fixed). Red: open, amber: a question,
## green: fixed, grey: won't fix.

const STATUS_COLORS := {"open": Color(1.0, 0.2, 0.2), "question": Color(1.0, 0.7, 0.1), "fixed": Color(0.3, 0.9, 0.35),
	"wontfix": Color(0.6, 0.6, 0.6)}

## What is wrong here, or what should change. Be as exact as you like ("the step is 2 cm too high", "the doorway
## should face the court").
@export_multiline var text := "":
	set(v):
		text = v
		_look()
		_dirty()
@export_enum("open", "question", "fixed", "wontfix") var status := "open":
	set(v):
		status = v
		_look()
		_dirty()
## The piece the note is about (filled in from what was clicked; change it if it is about another).
@export var piece := "":
	set(v):
		piece = v
		_dirty()
@export var author := "":
	set(v):
		author = v
		_dirty()
## The answer after a fix (what was changed).
@export_multiline var reply := "":
	set(v):
		reply = v
		_look()
		_dirty()
@export var created := ""

var _pin: MeshInstance3D = null
var _head: MeshInstance3D = null
var _label: Label3D = null
static var _mats := {}


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_local_transform(true)
		_look()


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		_dirty()


func _dirty() -> void:
	if not is_inside_tree():
		return
	var n := get_parent()
	while n != null:
		if n.has_method("mark_notes_dirty"):
			n.mark_notes_dirty()
			return
		n = n.get_parent()


func to_dict() -> Dictionary:
	var p := position
	var par := get_parent()
	if par is Node3D:
		p = (par as Node3D).transform * p
	return {"id": str(name), "at": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)], "text": text,
		"status": status, "piece": piece, "author": author, "reply": reply, "created": created}


func from_dict(d: Dictionary) -> void:
	name = str(d.get("id", "N1")).validate_node_name()
	var a: Array = d.get("at", [0, 0, 0])
	position = Vector3(float(a[0]), float(a[1]), float(a[2]))
	text = str(d.get("text", ""))
	status = str(d.get("status", "open"))
	piece = str(d.get("piece", ""))
	author = str(d.get("author", ""))
	reply = str(d.get("reply", ""))
	created = str(d.get("created", ""))


func _look() -> void:
	if not is_inside_tree() or not Engine.is_editor_hint():
		return
	if _pin == null:
		_pin = MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.07
		cone.bottom_radius = 0.0
		cone.height = 0.6
		_pin.mesh = cone
		_pin.position = Vector3(0, 0.3, 0)
		add_child(_pin, false, Node.INTERNAL_MODE_FRONT)
		_head = MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.16
		sp.height = 0.32
		_head.mesh = sp
		_head.position = Vector3(0, 0.68, 0)
		add_child(_head, false, Node.INTERNAL_MODE_FRONT)
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.font_size = 34
		_label.pixel_size = 0.004
		_label.outline_size = 10
		_label.width = 900.0
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.position = Vector3(0, 1.25, 0)
		_label.no_depth_test = true
		_label.visibility_range_end = 40.0
		add_child(_label, false, Node.INTERNAL_MODE_FRONT)
	var col: Color = STATUS_COLORS.get(status, Color.WHITE)
	_pin.material_override = _mat(col)
	_head.material_override = _mat(col)
	_label.modulate = col.lerp(Color.WHITE, 0.55)
	var t := text if text != "" else "(write what is wrong here in the Inspector)"
	_label.text = "%s · %s\n%s%s" % [str(name), status, t, ("\n> " + reply) if reply != "" else ""]


static func _mat(c: Color) -> StandardMaterial3D:
	var k := c.to_html()
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		m.render_priority = 10
		_mats[k] = m
	return _mats[k]
