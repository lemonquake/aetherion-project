extends CharacterBody3D
## Stand-in player for tools/viewmodel_lab.gd: the fields the viewmodel and the weapon state read.

var eid := 7
var pid := 4242
var mode := Motor.GROUND
var flags := 0
var vault_t := -1.0
var held_prop_id := -1
var sprinting := false
var crouching := false
var health = null
var light = null
var inv = null
var wpn = null


func aim_basis() -> Basis:
	return global_transform.basis


func eye_position() -> Vector3:
	return global_position + Vector3.UP * 1.6
