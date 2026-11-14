class_name GeneralaDie
extends RigidBody3D
## KayKit D6_B visuals with real rigid-body rolls and world-normal face detection.

const MODEL: PackedScene = preload("res://assets/kaykit/D6_B.gltf")
const MODEL_SCALE: float = 1.0 / 0.75
# Values 1..6 in the original KayKit mesh, verified against its visible pips.
# Native orientation: -Y=1, +X=2, +Z=3, -Z=4, -X=5, +Y=6.
const FACE_NORMALS: Array[Vector3] = [Vector3.DOWN, Vector3.RIGHT, Vector3.BACK, Vector3.FORWARD, Vector3.LEFT, Vector3.UP]

var die_index: int = 0
var _visual: Node3D
var _movement_tween: Tween

func _ready() -> void:
	mass = 0.7
	collision_layer = 2
	collision_mask = 3
	linear_damp = 0.65
	angular_damp = 0.8
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	var physics_material := PhysicsMaterial.new()
	physics_material.bounce = 0.26
	physics_material.friction = 0.75
	physics_material_override = physics_material
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * 0.98
	collision.shape = box
	add_child(collision)
	_visual = MODEL.instantiate() as Node3D
	_visual.name = "KayKitD6"
	_visual.scale = Vector3.ONE * MODEL_SCALE
	add_child(_visual)

func move_to(location: Vector3) -> void:
	var previous := global_position
	_reset_visual()
	position = location
	_visual.position = global_basis.inverse() * (previous - global_position)
	_movement_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_movement_tween.tween_property(_visual, "position", Vector3.ZERO, 0.22)

func _reset_visual() -> void:
	if is_instance_valid(_movement_tween):
		_movement_tween.kill()
	_visual.position = Vector3.ZERO

func top_value() -> int:
	var highest: float = -2.0
	var value: int = 1
	for face in range(6):
		var height := (global_basis * FACE_NORMALS[face]).dot(Vector3.UP)
		if height > highest:
			highest = height
			value = face + 1
	return value

func top_alignment() -> float:
	return (global_basis * FACE_NORMALS[top_value() - 1]).dot(Vector3.UP)

func show_value(value: int, yaw: float = 0.0) -> void:
	_reset_visual()
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	quaternion = Quaternion(Vector3.UP, yaw) * Quaternion(FACE_NORMALS[clampi(value, 1, 6) - 1], Vector3.UP)

func toss(origin: Vector3) -> void:
	_reset_visual()
	freeze = true
	position = origin
	# Uniform random orientation (Shoemake), independent of Euler angles.
	var u := randf()
	var a := randf() * TAU
	var b := randf() * TAU
	quaternion = Quaternion(sqrt(1.0 - u) * sin(a), sqrt(1.0 - u) * cos(a), sqrt(u) * sin(b), sqrt(u) * cos(b))
	freeze = false
	sleeping = false
	linear_velocity = Vector3(randf_range(-2.4, 2.4), randf_range(0.5, 2.0), randf_range(-1.4, 1.8))
	angular_velocity = Vector3(randf_range(-17, 17), randf_range(-17, 17), randf_range(-17, 17))
