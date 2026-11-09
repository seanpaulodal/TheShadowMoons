class_name Targeting
extends RefCounted
## Finds who an attack hits. Anything that can be attacked is in the group
## "targetable" and has a `combatant` property (and optionally `target_radius`).


static func is_valid_target(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var fighter: Variant = node.get("combatant")
	return fighter is Combatant and not (fighter as Combatant).is_dead


## Distance on the ground from `from` to the surface of `target`.
static func distance(from: Node3D, target: Node3D) -> float:
	var a := from.global_position
	var b := target.global_position
	var radius := float(target.get("target_radius")) if target.get("target_radius") != null else 0.6
	return maxf(0.0, Vector2(a.x - b.x, a.z - b.z).length() - radius)


## Keeps `current` while it is still alive and in range, otherwise picks the
## nearest valid target in range. Returns null if there is none.
static func pick(from: Node3D, attack_range: float, current: Node3D = null) -> Node3D:
	if is_valid_target(current) and distance(from, current) <= attack_range:
		return current
	var best: Node3D = null
	var best_distance := INF
	for node in from.get_tree().get_nodes_in_group("targetable"):
		if not (node is Node3D) or not is_valid_target(node):
			continue
		var d := distance(from, node)
		if d <= attack_range and d < best_distance:
			best = node
			best_distance = d
	return best
