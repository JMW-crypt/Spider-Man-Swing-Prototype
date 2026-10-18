extends Node3D

var player: CharacterBody3D
var camera: Camera3D

func _ready():
	randomize()

	create_floor()
	create_sun()
	create_player()
	create_city()

func _physics_process(delta):

	if player == null:
		return

	var direction = Vector3.ZERO

	if Input.is_key_pressed(KEY_W):
		direction.z -= 1

	if Input.is_key_pressed(KEY_S):
		direction.z += 1

	if Input.is_key_pressed(KEY_A):
		direction.x -= 1

	if Input.is_key_pressed(KEY_D):
		direction.x += 1

	if Input.is_key_pressed(KEY_SPACE):
		direction.y += 1

	if direction.length() > 0:
		direction = direction.normalized()

	player.position += direction * 10.0 * delta

	camera.position = player.position + Vector3(0, 25, 25)
	camera.look_at(player.position)

func create_floor():

	var floor = MeshInstance3D.new()

	var mesh = BoxMesh.new()
	mesh.size = Vector3(150, 1, 150)

	floor.mesh = mesh
	floor.position = Vector3(0, -0.5, 0)

	add_child(floor)

func create_sun():

	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 45, 0)

	add_child(sun)

func create_player():

	player = CharacterBody3D.new()
	player.name = "Player"

	add_child(player)

	var collision = CollisionShape3D.new()
	collision.shape = CapsuleShape3D.new()
	player.add_child(collision)

	var body_mesh = MeshInstance3D.new()
	body_mesh.mesh = CapsuleMesh.new()
	player.add_child(body_mesh)

	camera = Camera3D.new()
	camera.current = true

	add_child(camera)

func create_city():

	for x in range(-40, 41, 12):

		for z in range(-40, 41, 12):

			if abs(x) < 12 and abs(z) < 12:
				continue

			var building = MeshInstance3D.new()

			var mesh = BoxMesh.new()

			var height = randf_range(5.0, 20.0)

			mesh.size = Vector3(6, height, 6)

			building.mesh = mesh

			building.position = Vector3(
				x,
				height / 2.0,
				z
			)

			add_child(building)
