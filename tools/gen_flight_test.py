"""Generates scenes/test/flight_test.tscn (the grey-box flight arena).

Run once to (re)build the layout; after that, edit the scene in Godot.
Positions come from a fixed seed so the arena is the same every time.
"""
import math
import random
from pathlib import Path

ARENA = 110.0  # half-size of the walled square, metres
rng = random.Random(7)

out = []
w = out.append
w("[gd_scene format=3]\n")
w('[ext_resource type="Script" path="res://scripts/test/flight_test.gd" id="1_level"]')
w('[ext_resource type="PackedScene" path="res://scenes/ship/player_ship.tscn" id="2_ship"]')
w('[ext_resource type="Script" path="res://scripts/camera/rift_camera.gd" id="3_cam"]')
w('[ext_resource type="PackedScene" path="res://scenes/world/asteroid.tscn" id="4_ast"]')
w('[ext_resource type="PackedScene" path="res://scenes/world/target_dummy.tscn" id="5_dummy"]')
w('[ext_resource type="PackedScene" path="res://scenes/world/wind_stream.tscn" id="6_wind"]')
w('[ext_resource type="PackedScene" path="res://scenes/ui/flight_hud.tscn" id="7_hud"]')
w('[ext_resource type="Shader" path="res://shaders/space_grid.gdshader" id="8_grid"]\n')

w('''[sub_resource type="Environment" id="Env"]
background_mode = 1
background_color = Color(0.02, 0.016, 0.05, 1)
ambient_light_source = 2
ambient_light_color = Color(0.35, 0.3, 0.5, 1)
ambient_light_energy = 0.6
tonemap_mode = 2
glow_enabled = true
glow_intensity = 0.9
glow_bloom = 0.15
fog_enabled = true
fog_light_color = Color(0.12, 0.06, 0.2, 1)
fog_density = 0.004
''')
w('''[sub_resource type="ShaderMaterial" id="Mat_grid"]
render_priority = 0
shader = ExtResource("8_grid")
''')
w(f'''[sub_resource type="PlaneMesh" id="Mesh_grid"]
material = SubResource("Mat_grid")
size = Vector2({ARENA*2+60:.0f}, {ARENA*2+60:.0f})
''')
w(f'''[sub_resource type="BoxShape3D" id="Shape_wall_x"]
size = Vector3({ARENA*2+8:.0f}, 6, 4)
''')
w(f'''[sub_resource type="BoxShape3D" id="Shape_wall_z"]
size = Vector3(4, 6, {ARENA*2+8:.0f})
''')
w('''[sub_resource type="StandardMaterial3D" id="Mat_wall"]
transparency = 1
shading_mode = 0
albedo_color = Color(0.6, 0.3, 1, 0.25)
''')
w(f'''[sub_resource type="BoxMesh" id="Mesh_wall_x"]
material = SubResource("Mat_wall")
size = Vector3({ARENA*2+8:.0f}, 0.3, 4)
''')
w(f'''[sub_resource type="BoxMesh" id="Mesh_wall_z"]
material = SubResource("Mat_wall")
size = Vector3(4, 0.3, {ARENA*2+8:.0f})
''')

w('[node name="FlightTest" type="Node3D"]')
w('script = ExtResource("1_level")\n')
w('[node name="WorldEnvironment" type="WorldEnvironment" parent="."]')
w('environment = SubResource("Env")\n')
w('[node name="StarLight" type="DirectionalLight3D" parent="."]')
w('rotation = Vector3(-0.95, 0.6, 0)')
w('light_color = Color(1, 0.9, 0.75, 1)')
w('light_energy = 1.2')
w('shadow_enabled = true')
w('directional_shadow_max_distance = 120.0\n')
w('[node name="Grid" type="MeshInstance3D" parent="."]')
w('position = Vector3(0, -2.5, 0)')
w('cast_shadow = 0')
w('mesh = SubResource("Mesh_grid")\n')

w('[node name="Walls" type="Node3D" parent="."]\n')
for name, pos, axis in [("North", (0, 0, -ARENA - 2), "x"), ("South", (0, 0, ARENA + 2), "x"),
                        ("West", (-ARENA - 2, 0, 0), "z"), ("East", (ARENA + 2, 0, 0), "z")]:
    w(f'[node name="{name}" type="StaticBody3D" parent="Walls"]')
    w(f'position = Vector3({pos[0]:.1f}, 0, {pos[2]:.1f})')
    w('collision_mask = 0\n')
    w(f'[node name="Collision" type="CollisionShape3D" parent="Walls/{name}"]')
    w(f'shape = SubResource("Shape_wall_{axis}")\n')
    w(f'[node name="Mesh" type="MeshInstance3D" parent="Walls/{name}"]')
    w('position = Vector3(0, -1.5, 0)')
    w('cast_shadow = 0')
    w(f'mesh = SubResource("Mesh_wall_{axis}")\n')

w('[node name="PlayerShip" parent="." instance=ExtResource("2_ship")]\n')
w('[node name="RiftCamera" type="Camera3D" parent="." node_paths=PackedStringArray("target")]')
w('fov = 50.0')
w('far = 400.0')
w('script = ExtResource("3_cam")')
w('target = NodePath("../PlayerShip")\n')

# Asteroids: scattered rocks, keeping a clear spawn area and a clear lane
# for each wind stream.
w('[node name="Asteroids" type="Node3D" parent="."]\n')
placed = []
def clear(x, z, r):
    if math.hypot(x, z) < 18 + r:
        return False
    if abs(x - 55) < 8 + r and abs(z) < 75 + r:
        return False
    if abs(z + 55) < 8 + r and -95 - r < x < -5 + r:
        return False
    for px, pz, pr in placed:
        if math.hypot(x - px, z - pz) < r + pr + 7:
            return False
    return True
attempts = 0
while len(placed) < 26 and attempts < 5000:
    attempts += 1
    r = rng.uniform(1.8, 5.5)
    x = rng.uniform(-ARENA + 10, ARENA - 10)
    z = rng.uniform(-ARENA + 10, ARENA - 10)
    if clear(x, z, r):
        placed.append((x, z, r))
for i, (x, z, r) in enumerate(placed):
    w(f'[node name="Asteroid{i + 1:02d}" parent="Asteroids" instance=ExtResource("4_ast")]')
    w(f'position = Vector3({x:.1f}, 0, {z:.1f})')
    w(f'rotation = Vector3({rng.uniform(0, 3):.2f}, {rng.uniform(0, 6):.2f}, 0)')
    w(f'radius = {r:.1f}\n')

# Target dummies: a static gallery north of spawn, movers further out.
w('[node name="Targets" type="Node3D" parent="."]\n')
dummies = [(-12, -30, 0), (0, -34, 0), (12, -30, 0),
           (-40, 10, 10), (40, 20, 12), (0, 50, 14),
           (-70, -70, 0), (70, -80, 8), (-80, 70, 0), (80, 80, 10)]
for i, (x, z, patrol) in enumerate(dummies):
    w(f'[node name="Dummy{i + 1:02d}" parent="Targets" instance=ExtResource("5_dummy")]')
    w(f'position = Vector3({x}, 0, {z})')
    if patrol:
        w(f'patrol_distance = {patrol:.1f}')
    w('')

# Wind streams: one long north-bound lane on the east side and one
# west-bound lane in the north-west.
w('[node name="WindStreams" type="Node3D" parent="."]\n')
w('[node name="WindNorth" parent="WindStreams" instance=ExtResource("6_wind")]')
w('position = Vector3(55, 0, 0)')
w('length = 140.0\n')
w('[node name="WindWest" parent="WindStreams" instance=ExtResource("6_wind")]')
w('position = Vector3(-50, 0, -55)')
w('rotation = Vector3(0, 1.5708, 0)')
w('length = 80.0\n')

w('[node name="FlightHud" parent="." node_paths=PackedStringArray("ship") instance=ExtResource("7_hud")]')
w('ship = NodePath("../PlayerShip")')

Path(__file__).resolve().parent.parent.joinpath("scenes/test/flight_test.tscn").write_text("\n".join(out) + "\n")
print(f"wrote flight_test.tscn with {len(placed)} asteroids, {len(dummies)} targets")
