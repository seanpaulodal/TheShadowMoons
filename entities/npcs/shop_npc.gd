class_name ShopNpc
extends StaticBody3D
## A shopkeeper standing in the world. Walk up to one and a Talk button appears.
## Which shop it runs (what it sells) is set in TSM_Shop_Rules.json.

var shop_id: String = ""
var display_name: String = ""
var target_radius: float = 0.6


## The closest shopkeeper within `radius` of `from`, or null.
static func nearest(from: Node3D, radius: float) -> ShopNpc:
	var best: ShopNpc = null
	var best_distance := INF
	for node in from.get_tree().get_nodes_in_group("shop_npc"):
		var npc := node as ShopNpc
		if npc == null:
			continue
		var distance := Vector2(from.global_position.x - npc.global_position.x,
				from.global_position.z - npc.global_position.z).length()
		if distance <= radius and distance < best_distance:
			best = npc
			best_distance = distance
	return best


func _ready() -> void:
	add_to_group("shop_npc")
	add_to_group("npc")
	var def := Shop.shop_def(shop_id)
	display_name = str(def.get("name", shop_id))

	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.55
	cylinder.height = 2.0
	shape.shape = cylinder
	shape.position = Vector3(0, 1.0, 0)
	add_child(shape)

	var robe_material := StandardMaterial3D.new()
	robe_material.albedo_color = Color("2f6f8f")
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.45
	body_mesh.height = 1.9
	body_mesh.material = robe_material
	body.mesh = body_mesh
	body.position = Vector3(0, 0.95, 0)
	add_child(body)

	var hat_material := StandardMaterial3D.new()
	hat_material.albedo_color = TSMTheme.ACCENT
	var hat := MeshInstance3D.new()
	var hat_mesh := CylinderMesh.new()
	hat_mesh.top_radius = 0.05
	hat_mesh.bottom_radius = 0.42
	hat_mesh.height = 0.6
	hat_mesh.material = hat_material
	hat.mesh = hat_mesh
	hat.position = Vector3(0, 2.1, 0)
	add_child(hat)

	var nameplate := Label3D.new()
	nameplate.text = display_name
	nameplate.modulate = TSMTheme.ACCENT
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.font_size = 44
	nameplate.pixel_size = 0.005
	nameplate.outline_size = 10
	nameplate.position = Vector3(0, 2.8, 0)
	add_child(nameplate)
