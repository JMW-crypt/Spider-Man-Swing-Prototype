extends Node3D

# Lightweight web-swinging prototype for Godot 4.x
# Designed for integrated graphics: simple geometry, compatibility renderer, limited shadows.

const GRAVITY := 22.0
const WALK_SPEED := 11.0
const AIR_CONTROL := 18.0
const JUMP_SPEED := 10.0
const MAX_FALL_SPEED := 45.0
const SWING_PULL := 28.0
const SWING_PUMP := 20.0
const MAX_SWING_SPEED := 42.0
const WEB_RANGE := 85.0
const MOUSE_SENSITIVITY := 0.0022

var player: CharacterBody3D
var camera_pivot: Node3D
var camera: Camera3D
var web_line: MeshInstance3D
var swing_anchor := Vector3.ZERO
var swinging := false
var yaw := 0.0
var pitch := -0.18
var speed_label: Label

func _ready() -> void:
    _setup_inputs()
    _build_world()
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _setup_inputs() -> void:
    _add_key("move_forward", KEY_W)
    _add_key("move_back", KEY_S)
    _add_key("move_left", KEY_A)
    _add_key("move_right", KEY_D)
    _add_key("jump", KEY_SPACE)
    _add_key("release_mouse", KEY_ESCAPE)
    if not InputMap.has_action("swing"):
        InputMap.add_action("swing")
        var mouse := InputEventMouseButton.new()
        mouse.button_index = MOUSE_BUTTON_LEFT
        InputMap.action_add_event("swing", mouse)

func _add_key(action: StringName, keycode: Key) -> void:
    if InputMap.has_action(action):
        return
    InputMap.add_action(action)
    var event := InputEventKey.new()
    event.physical_keycode = keycode
    InputMap.action_add_event(action, event)

func _build_world() -> void:
    RenderingServer.set_default_clear_color(Color("87b8df"))

    var world_env := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("87b8df")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("b9d1df")
    env.ambient_light_energy = 0.75
    env.fog_enabled = true
    env.fog_light_color = Color("a9c2d1")
    env.fog_density = 0.004
    world_env.environment = env
    add_child(world_env)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-52, -25, 0)
    sun.light_energy = 1.0
    sun.shadow_enabled = false
    add_child(sun)

    _make_static_box(Vector3(0, -1, 0), Vector3(260, 2, 260), Color("33434a"))

    var rng := RandomNumberGenerator.new()
    rng.seed = 12027
    for x in range(-5, 6):
        for z in range(-5, 6):
            if abs(x) <= 1 and abs(z) <= 1:
                continue
            var height := rng.randf_range(14.0, 42.0)
            var width := rng.randf_range(10.0, 16.0)
            var depth := rng.randf_range(10.0, 16.0)
            var pos := Vector3(x * 22.0, height * 0.5, z * 22.0)
            var color := Color.from_hsv(rng.randf_range(0.52, 0.66), 0.18, rng.randf_range(0.42, 0.68))
            _make_static_box(pos, Vector3(width, height, depth), color)

    player = CharacterBody3D.new()
    player.name = "Player"
    player.position = Vector3(0, 5, 12)
    add_child(player)

    var collider := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.55
    capsule.height = 1.8
    collider.shape = capsule
    player.add_child(collider)

    var body_mesh := MeshInstance3D.new()
    var capsule_mesh := CapsuleMesh.new()
    capsule_mesh.radius = 0.55
    capsule_mesh.height = 1.8
    body_mesh.mesh = capsule_mesh
    var player_mat := StandardMaterial3D.new()
    player_mat.albedo_color = Color("d9273e")
    body_mesh.material_override = player_mat
    player.add_child(body_mesh)

    camera_pivot = Node3D.new()
    camera_pivot.position = Vector3(0, 1.2, 0)
    player.add_child(camera_pivot)

    camera = Camera3D.new()
    camera.position = Vector3(0, 2.4, 8.5)
    camera.fov = 78.0
    camera.current = true
    camera_pivot.add_child(camera)

    web_line = MeshInstance3D.new()
    web_line.visible = false
    var web_mat := StandardMaterial3D.new()
    web_mat.albedo_color = Color.WHITE
    web_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    web_line.material_override = web_mat
    add_child(web_line)

    var canvas := CanvasLayer.new()
    add_child(canvas)
    var help := Label.new()
    help.text = "WASD move | Space jump | Hold Left Mouse swing | Esc release mouse"
    help.position = Vector2(18, 16)
    help.add_theme_color_override("font_color", Color.WHITE)
    help.add_theme_font_size_override("font_size", 18)
    canvas.add_child(help)
    speed_label = Label.new()
    speed_label.position = Vector2(18, 44)
    speed_label.add_theme_color_override("font_color", Color("ffe27a"))
    speed_label.add_theme_font_size_override("font_size", 18)
    canvas.add_child(speed_label)

func _make_static_box(pos: Vector3, size: Vector3, color: Color) -> void:
    var body := StaticBody3D.new()
    body.position = pos
    add_child(body)
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collision.shape = shape
    body.add_child(collision)
    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh_instance.mesh = mesh
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 0.9
    mesh_instance.material_override = mat
    body.add_child(mesh_instance)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        yaw -= event.relative.x * MOUSE_SENSITIVITY
        pitch = clamp(pitch - event.relative.y * MOUSE_SENSITIVITY, -1.15, 0.65)
    if event.is_action_pressed("release_mouse"):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
    if player == null:
        return
    camera_pivot.rotation = Vector3(pitch, yaw, 0)

    var input2 := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var forward := -camera_pivot.global_transform.basis.z
    var right := camera_pivot.global_transform.basis.x
    forward.y = 0
    right.y = 0
    forward = forward.normalized()
    right = right.normalized()
    var desired := (right * input2.x + forward * -input2.y).normalized()

    if Input.is_action_just_pressed("swing"):
        _try_start_swing()
    if Input.is_action_just_released("swing"):
        swinging = false
        web_line.visible = false

    if player.is_on_floor():
        if desired != Vector3.ZERO:
            player.velocity.x = move_toward(player.velocity.x, desired.x * WALK_SPEED, 35.0 * delta)
            player.velocity.z = move_toward(player.velocity.z, desired.z * WALK_SPEED, 35.0 * delta)
        else:
            player.velocity.x = move_toward(player.velocity.x, 0.0, 28.0 * delta)
            player.velocity.z = move_toward(player.velocity.z, 0.0, 28.0 * delta)
        if Input.is_action_just_pressed("jump"):
            player.velocity.y = JUMP_SPEED
    else:
        player.velocity += desired * AIR_CONTROL * delta
        player.velocity.y = max(player.velocity.y - GRAVITY * delta, -MAX_FALL_SPEED)

    if swinging:
        var to_anchor := swing_anchor - player.global_position
        var distance := to_anchor.length()
        if distance > WEB_RANGE * 1.3:
            swinging = false
            web_line.visible = false
        else:
            var rope_dir := to_anchor.normalized()
            player.velocity += rope_dir * SWING_PULL * delta
            if desired != Vector3.ZERO:
                player.velocity += desired * SWING_PUMP * delta
            if player.velocity.length() > MAX_SWING_SPEED:
                player.velocity = player.velocity.normalized() * MAX_SWING_SPEED
            _update_web()

    player.move_and_slide()
    if player.global_position.y < -20.0:
        player.global_position = Vector3(0, 8, 12)
        player.velocity = Vector3.ZERO
    speed_label.text = "Speed: %d" % int(player.velocity.length())

func _try_start_swing() -> void:
    var origin := camera.global_position
    var direction := -camera.global_transform.basis.z
    var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * WEB_RANGE)
    query.exclude = [player.get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if hit:
        swing_anchor = hit.position
    else:
        # Forgiving auto-anchor keeps the prototype fun even when aim misses.
        swing_anchor = player.global_position + direction * 28.0 + Vector3.UP * 24.0
    swinging = true
    web_line.visible = true
    _update_web()

func _update_web() -> void:
    var start := player.global_position + Vector3.UP * 0.7
    var delta := swing_anchor - start
    var length := delta.length()
    if length < 0.05:
        return
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = 0.035
    cylinder.bottom_radius = 0.035
    cylinder.height = length
    cylinder.radial_segments = 6
    web_line.mesh = cylinder
    web_line.global_position = start + delta * 0.5
    web_line.look_at(swing_anchor, Vector3.UP)
    web_line.rotate_object_local(Vector3.RIGHT, PI * 0.5)
