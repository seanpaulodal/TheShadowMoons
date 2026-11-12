class_name LootDrop
extends Node3D
## An item lying on the ground: a spinning gem, a coloured light beam and a
## name label, all in the item's rarity colour so it is easy to spot. Walk close
## to pick it up. It disappears after a while if nobody takes it.

var item_id: String = ""
var qty: int = 1
## Seconds before it can be picked up (so an item you drop does not jump straight back).
var pickup_delay: float = 0.0

var _life: float = 90.0
var _check_timer: float = 0.0
var _full_message_timer: float = 0.0
var _gem: MeshInstance3D


## Drops an item near `at`. `index` / `total` spread several drops around a circle
## so they do not sit on top of each other.
static func spawn(parent: Node, at: Vector3, drop_item_id: String, drop_qty: int = 1,
		index: int = 0, total: int = 1, delay: float = 0.0) -> LootDrop:
	var drop := LootDrop.new()
	drop.item_id = drop_item_id
	drop.qty = drop_qty
	drop.pickup_delay = delay
	parent.add_child(drop)
	var spread := float(DataRegistry.get_config("loot_rules").get("spread_radius", 1.4))
	var angle := TAU * float(index) / float(maxi(1, total))
	var ring := Vector3(cos(angle), 0.0, sin(angle)) * (spread if total > 1 else 0.0)
	drop.global_position = Vector3(at.x, 0.0, at.z) + ring
	return drop


func _ready() -> void:
	add_to_group("loot")
	_life = float(DataRegistry.get_config("loot_rules").get("despawn_seconds", 90.0))
	var color := TSMTheme.rarity_color(ItemDB.rarity(item_id))

	_gem = MeshInstance3D.new()
	var gem_mesh := BoxMesh.new()
	gem_mesh.size = Vector3(0.3, 0.3, 0.3)
	var gem_material := StandardMaterial3D.new()
	gem_material.albedo_color = color
	gem_material.emission_enabled = true
	gem_material.emission = color
	gem_material.emission_energy_multiplier = 1.2
	gem_mesh.material = gem_material
	_gem.mesh = gem_mesh
	_gem.position = Vector3(0, 0.55, 0)
	_gem.rotation = Vector3(0.6, 0.0, 0.6)
	add_child(_gem)

	var beam := MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.05
	beam_mesh.bottom_radius = 0.05
	beam_mesh.height = 3.0
	beam_mesh.radial_segments = 8
	var beam_material := StandardMaterial3D.new()
	beam_material.albedo_color = Color(color, 0.35)
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mesh.material = beam_material
	beam.mesh = beam_mesh
	beam.position = Vector3(0, 1.5, 0)
	add_child(beam)

	var label := Label3D.new()
	label.text = ItemDB.display_name(item_id) if qty <= 1 else "%s x%d" % [ItemDB.display_name(item_id), qty]
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 40
	label.pixel_size = 0.006
	label.outline_size = 10
	label.position = Vector3(0, 1.1, 0)
	add_child(label)


func _process(delta: float) -> void:
	if _gem != null:
		_gem.rotate_y(delta * 2.0)
	_life -= delta
	pickup_delay = maxf(0.0, pickup_delay - delta)
	_full_message_timer = maxf(0.0, _full_message_timer - delta)
	if _life <= 0.0:
		queue_free()
		return
	_check_timer += delta
	if _check_timer >= 0.1:
		_check_timer = 0.0
		_try_pick_up()


func remaining_seconds() -> float:
	return _life


func _try_pick_up() -> void:
	if pickup_delay > 0.0:
		return
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player == null or player.combatant == null or player.combatant.is_dead:
		return
	var radius := float(DataRegistry.get_config("loot_rules").get("pickup_radius", 1.8))
	var from_player := Vector2(player.global_position.x - global_position.x,
			player.global_position.z - global_position.z).length()
	if from_player > radius:
		return

	var result: Dictionary = Session.collect_item(item_id, qty)
	if result["ok"]:
		FloatingText.spawn(get_parent(), player.global_position + Vector3(0, 2.2, 0),
				"+ %s" % ItemDB.display_name(item_id), TSMTheme.rarity_color(ItemDB.rarity(item_id)), 0.9)
		queue_free()
	elif _full_message_timer <= 0.0:
		_full_message_timer = 2.0
		FloatingText.spawn(get_parent(), player.global_position + Vector3(0, 2.2, 0),
				"Bag is full", TSMTheme.ERROR, 0.9)
