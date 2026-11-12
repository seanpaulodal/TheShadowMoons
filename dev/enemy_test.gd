extends Node
## DEV ONLY. Checks enemies (M6): the loot table, rewards and saving, the enemy
## behaviour (notice, chase, attack, give up, die), loot on the ground, camps
## that sleep and wake, player death and the HUD. Needs no login and saves
## nothing. Run with F6 and read the Output panel.

const ENEMY_ROLLS := {"hit": 0.0, "parry": 99.9, "crit": 99.9, "block": 99.9, "weapon": 0.5, "status": 99.0}
const PLAYER_ROLLS := {"hit": 0.0, "parry": 99.9, "crit": 99.9, "block": 99.9, "weapon": 0.5, "status": 99.0}

var _passed: int = 0
var _failed: int = 0
var _world: Node3D
var _player: PlayerController
var _rewards_seen: Array = []


func _ready() -> void:
	await get_tree().process_frame
	Session.save_enabled = false
	_new_character("warrior")

	_test_loot_table()
	await _test_session_saving()
	await _build_arena()
	await _test_enemy_behaviour()
	await _test_rewards_and_loot()
	await _test_player_death()
	await _test_hud()
	await _test_camps()

	Session.save_enabled = true
	Session.clear()
	print("[enemy] RESULT: %d passed, %d failed" % [_passed, _failed])


# ---------- helpers ----------

func _eq(label: String, got: Variant, expected: Variant) -> void:
	_report(label, got == expected, "expected %s, got %s" % [str(expected), str(got)])


func _near(label: String, got: float, expected: float, tolerance: float = 0.011) -> void:
	_report(label, absf(got - expected) <= tolerance, "expected %s, got %s" % [str(expected), str(got)])


func _report(label: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passed += 1
		print("[enemy] PASS  ", label)
	else:
		_failed += 1
		print("[enemy] FAIL  %s  (%s)" % [label, detail])


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _new_character(class_id: String) -> void:
	Session.character = {
		"name": "Fighter", "class_id": class_id, "level": 1, "exp": 0, "rebirth": 0,
		"stat_points": 0, "gold": 0, "attributes": {}, "inventory": [], "equipment": {},
	}
	Session.slot = 1
	Session._fill_missing_fields()


func _spawn_enemy(enemy_id: String, home: Vector3, rolls: Dictionary = ENEMY_ROLLS) -> Enemy:
	var enemy := Enemy.new()
	enemy.setup(enemy_id, home, _world)
	enemy.test_rolls = rolls
	enemy.test_loot_rolls = {"all": 0.0}      # drops everything it can
	_world.add_child(enemy)
	return enemy


func _stand_at(position: Vector3) -> void:
	_player.global_position = position
	_player.velocity = Vector3.ZERO
	await _frames(2)


func _clear_enemies_and_loot() -> void:
	for node in get_tree().get_nodes_in_group("targetable"):
		if node is Enemy:
			node.queue_free()
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()


# Removes camps, dummies and obstacles so every test runs in an empty field.
func _build_arena() -> void:
	_world = load("res://maps/world_test.tscn").instantiate()
	add_child(_world)
	await _frames(3)
	_player = _world.player
	for camp in _world.camps:
		camp.queue_free()
	for child in _world.get_children():
		if child is TrainingDummy:
			child.queue_free()
		elif child is StaticBody3D:
			var shape_node := child.get_child(0) as CollisionShape3D
			if shape_node != null and shape_node.shape is BoxShape3D:
				var size := (shape_node.shape as BoxShape3D).size
				if maxf(size.x, maxf(size.y, size.z)) <= 6.5:
					child.queue_free()      # an obstacle (the ground and walls are bigger)
	_clear_enemies_and_loot()
	await _frames(3)
	Session.reward_granted.connect(func(summary: Dictionary) -> void: _rewards_seen.append(summary))


# ---------- loot table (pure) ----------

func _test_loot_table() -> void:
	print("[enemy] --- loot table ---")
	var everything := LootTable.roll("green_goblin", {"all": 0.0})
	var expected_listed := 0
	for item_id in DataRegistry.get_ids("items"):
		if ItemDB.drop_sources(item_id).has("green_goblin") and ItemDB.drop_chance(item_id) > 0.0:
			expected_listed += 1
	var ids: Array = []
	for entry in everything["items"]:
		ids.append(entry["item_id"])
	_eq("a goblin with the luckiest rolls drops every listed item plus 2 potions", ids.size(), expected_listed + 2)
	_eq("...including its wooden sword", ids.has("wooden_sword"), true)
	_eq("...a health potion sized for level 3", ids.has("potion_hp_minor"), true)
	_eq("...and a mana potion sized for level 3", ids.has("potion_mp_minor"), true)
	_eq("an item with drop chance 0 never drops", ids.has("lightning_spell"), false)
	_eq("EXP is the sheet's xp_reward", everything["exp"], 65)
	_eq("the unluckiest rolls drop nothing", LootTable.roll("green_goblin", {"all": 0.999})["items"], [])
	_eq("gold roll 0 gives the minimum (14)", LootTable.roll("green_goblin", {"gold": 0.0})["gold"], 14)
	_eq("gold roll 0.999 gives the maximum (33)", LootTable.roll("green_goblin", {"gold": 0.999})["gold"], 33)
	_eq("an unknown enemy gives nothing", LootTable.roll("not_an_enemy"), {"exp": 0, "gold": 0, "items": []})

	_eq("potion for level 3 (health)", LootTable.potion_for_level("health", 3), "potion_hp_minor")
	_eq("potion for level 24 stays minor", LootTable.potion_for_level("health", 24), "potion_hp_minor")
	_eq("potion for level 25 is small", LootTable.potion_for_level("health", 25), "potion_hp_small")
	_eq("potion for level 125 (mana)", LootTable.potion_for_level("mana", 125), "potion_mp_superior")
	_eq("potion for level 300", LootTable.potion_for_level("health", 300), "potion_hp_moonfall")
	var all_potions_exist := true
	for kind in ["health", "mana"]:
		for tier in DataRegistry.get_config("loot_rules")["potion_tiers"][kind]:
			if not ItemDB.exists(str(tier[1])):
				all_potions_exist = false
	_eq("every potion in the tier table exists in the item sheet", all_potions_exist, true)

	var rules := DataRegistry.get_config("loot_rules")
	rules["max_item_drops_per_kill"] = 2
	_eq("the drop limit in the rules is respected", LootTable.roll("green_goblin", {"all": 0.0})["items"].size(), 2)
	rules["max_item_drops_per_kill"] = 0

	_near("party bonus alone is none", ExpRules.party_multiplier(1), 1.0)
	_near("party of 3 gives +4%", ExpRules.party_multiplier(3), 1.04)
	_eq("EXP with a party of 3: 65 -> 67", ExpRules.exp_for_kill(65, 3), 67)
	_eq("parties do not exist yet: size 1", ExpRules.current_party_size(), 1)
	_eq("epic is purple, common is grey", [TSMTheme.rarity_color("Epic"), TSMTheme.rarity_color("Common")],
			[Color("b36bff"), Color("c8c8c8")])


# ---------- saving rewards ----------

func _test_session_saving() -> void:
	print("[enemy] --- saving rewards ---")
	var seen: Array = []
	var listener := func(summary: Dictionary) -> void: seen.append(summary)
	Session.reward_granted.connect(listener)

	var first := Session.grant_rewards(65, 20)
	_eq("rewards apply at once", [Session.character["exp"], Session.character["gold"]], [65, 20])
	_eq("...and wait to be saved", Session.has_unsaved_changes(), true)
	_eq("the HUD is told", seen.size(), 1)
	_eq("not enough for a level yet", first["summary"]["levels_gained"], 0)

	var second := Session.grant_rewards(100, 5)
	_eq("more EXP gives a level", second["summary"]["levels_gained"], 1)
	_eq("level 2, 65 EXP left over", [Session.character["level"], Session.character["exp"]], [2, 65])
	_eq("a level gives 5 stat points", Session.character["stat_points"], 5)
	_eq("gold adds up", Session.character["gold"], 25)

	_eq("pick up an item", Session.collect_item("healing_potion", 3)["ok"], true)
	_eq("...it is in the bag", Inventory.count(Session.character["inventory"], "healing_potion"), 3)
	var full: Array = []
	for i in Inventory.max_slots():
		full = Inventory.add(full, "iron_sword", 1)["inventory"]
	var kept_bag: Array = Session.character["inventory"]
	Session.character["inventory"] = full
	_eq("a full bag refuses new items", Session.collect_item("iron_ring", 1)["error"], "INVENTORY_FULL")
	Session.character["inventory"] = kept_bag

	Session.save_enabled = true       # not signed in, so the save must fail
	var failed := await Session.flush()
	_eq("a failed save is reported", failed["ok"], false)
	_eq("...and the changes keep waiting", Session.has_unsaved_changes(), true)
	_eq("...nothing was lost locally", Session.character["gold"], 25)
	Session.save_enabled = false
	_eq("with saving off, flush clears the queue", (await Session.flush())["ok"], true)
	_eq("...nothing waits any more", Session.has_unsaved_changes(), false)
	Session.reward_granted.disconnect(listener)
	_new_character("warrior")


# ---------- enemy behaviour ----------

func _test_enemy_behaviour() -> void:
	print("[enemy] --- behaviour ---")
	await _stand_at(Vector3(0, 0.2, 0))
	var goblin := _spawn_enemy("green_goblin", Vector3(0, 0, -12))
	await _frames(40)
	_eq("it has the sheet's health", goblin.combatant.max_health(), 145)
	_eq("...defense", goblin.combatant.stats["def_power"], 6.0)
	_eq("...level", goblin.combatant.level, 3)
	_eq("a player 12 units away is not noticed", goblin.state, Enemy.State.IDLE)
	_eq("it counts as one living enemy", Enemy.active_count, 1)

	var hits: Array = []
	_player.combatant.damaged.connect(func(result: Dictionary) -> void: hits.append(result))
	await _stand_at(Vector3(0, 0.2, -5))
	await _frames(25)
	_eq("a player 7 units away is noticed: it chases", goblin.state, Enemy.State.CHASE)
	var distance_before := goblin.global_position.distance_to(_player.global_position)
	await _frames(20)
	_report("...and gets closer", goblin.global_position.distance_to(_player.global_position) < distance_before)
	await _frames(100)
	_eq("it reaches the player and attacks", goblin.state, Enemy.State.ATTACK)
	_report("its first hit has landed", hits.size() >= 1, "%d hits" % hits.size())
	if hits.size() >= 1:
		_eq("goblin hit: (2 + attack 16) with 12 defense taken off = 16", hits[0]["damage"], 16)
		_eq("the player lost exactly that", _player.combatant.max_health() - _player.combatant.hp, 16 * hits.size())
	hits.clear()
	await _frames(180)
	_report("it keeps attacking every 1.2 seconds (2 to 3 hits in 3 s)", hits.size() >= 2 and hits.size() <= 3, "%d hits" % hits.size())
	_report("the player has a red damage number", FloatingText.active_count() >= 1)

	# Hit points bar follows health.
	goblin.combatant.take_damage(goblin.combatant.hp - 70)
	await _frames(2)
	_near("the health bar shows about half", goblin._bar_fill.region_rect.size.x / 64.0, 70.0 / 145.0, 0.02)

	# Hurt it from afar: it fights back even if it had not noticed the player.
	goblin.queue_free()
	_player.combatant.revive(1.0)
	_new_character("archer")
	_player.refresh_stats()
	await _frames(3)
	var far := _spawn_enemy("green_goblin", Vector3(0, 0, -40))
	await _stand_at(Vector3(0, 0.2, -30.2))      # 9.8 away: just outside noticing range
	await _frames(25)
	_eq("just outside its range it does not notice", far.state, Enemy.State.IDLE)
	var shot := _player.try_attack(PLAYER_ROLLS)
	_eq("an archer reaches it", shot["ok"], true)
	_eq("being hit makes it chase at once", far.state, Enemy.State.CHASE)

	# Giving up: the player runs away.
	await _frames(90)                 # it chases the archer for a while
	far.combatant.take_damage(50)
	await _stand_at(Vector3(0, 0.2, 60))
	await _frames(15)
	_eq("when the player gets too far it gives up and heads home", far.state, Enemy.State.RETURN)
	var waited := 0
	while far.state != Enemy.State.IDLE and waited < 800:
		await _frames(5)
		waited += 5
	_eq("it gets home", far.state, Enemy.State.IDLE)
	_eq("...and heals fully", far.combatant.hp, far.combatant.max_health())
	_report("...at its home spot", far.global_position.distance_to(Vector3(0, 0, -40)) < 1.6, str(far.global_position))
	far.queue_free()

	# Status effects on an enemy.
	_new_character("warrior")
	_player.refresh_stats()
	await _stand_at(Vector3(0, 0.2, 0))
	var slow_one := _spawn_enemy("green_goblin", Vector3(0, 0, -6))
	await _frames(10)
	_near("normal chase speed is the sheet's 4", slow_one._run_speed(), 4.0)
	slow_one.combatant.status.apply("Slow")
	_near("slowed: chase speed is cut by 35%", slow_one._run_speed(), 2.6, 0.02)
	slow_one.combatant.status.clear()
	slow_one.combatant.status.apply("Stun")
	var frozen_at := slow_one.global_position
	await _frames(40)
	_report("a stunned enemy does not move", slow_one.global_position.distance_to(frozen_at) < 0.05)
	slow_one.queue_free()
	await _frames(3)

	# Enemy status effects on the player.
	var biter := _spawn_enemy("green_goblin", Vector3(0, 0, -5), {"hit": 0.0, "parry": 99.9, "crit": 99.9, "block": 99.9,
			"weapon": 0.5, "status": 0.0, "status_pick": 0.0})
	await _frames(200)
	_eq("a goblin's hit can make the player bleed", _player.combatant.status.has("bleed"), true)
	biter.queue_free()
	_player.combatant.status.clear()
	_player.combatant.revive(1.0)
	_clear_enemies_and_loot()
	await _frames(3)


# ---------- rewards and loot ----------

func _test_rewards_and_loot() -> void:
	print("[enemy] --- rewards and loot ---")
	_new_character("warrior")
	_player.refresh_stats()
	_rewards_seen.clear()
	await _stand_at(Vector3(0, 0.2, 0))
	var goblin := _spawn_enemy("green_goblin", Vector3(0, 0, -4))
	var killed_log: Array = []
	goblin.killed.connect(func(_who: Enemy, rewards: Dictionary) -> void: killed_log.append(rewards))
	await _frames(120)          # it walks up to the player

	goblin.combatant.take_damage(goblin.combatant.hp - 5)
	var blow := _player.try_attack(PLAYER_ROLLS)
	_eq("the killing blow lands", blow["ok"], true)
	_eq("the goblin is dead", goblin.is_dead(), true)
	_eq("it announced its death once", killed_log.size(), 1)
	_eq("the player got the EXP", Session.character["exp"], 65)
	_report("...and gold from 14 to 33", Session.character["gold"] >= 14 and Session.character["gold"] <= 33, str(Session.character["gold"]))
	_eq("the reward was announced", _rewards_seen.size() >= 1, true)
	_eq("the killer is no longer targeted", _player.target, null)
	_eq("a corpse can not be targeted", Targeting.is_valid_target(goblin), false)

	var drops := get_tree().get_nodes_in_group("loot")
	_eq("loot lies on the ground", drops.size(), killed_log[0]["items"].size())
	_report("there is more than one drop", drops.size() > 1)
	var spread_ok := true
	for i in drops.size():
		for j in range(i + 1, drops.size()):
			if (drops[i] as Node3D).global_position.distance_to((drops[j] as Node3D).global_position) < 0.4:
				spread_ok = false
	_report("the drops are spread out, none on top of another", spread_ok)
	var first_drop := drops[0] as LootDrop
	_report("a drop shows a gem, a light beam and a name", first_drop.get_child_count() >= 3)

	# Not near enough: nothing is picked up.
	await _stand_at(Vector3(0, 0.2, 30))
	await _frames(15)
	_eq("walking far from the loot picks nothing up", get_tree().get_nodes_in_group("loot").size(), drops.size())

	# Walk onto each drop.
	var bag_before: int = Session.character["inventory"].size()
	for drop in get_tree().get_nodes_in_group("loot").duplicate():
		if not is_instance_valid(drop):
			continue      # an earlier pickup already took it (drops lie close together)
		await _stand_at((drop as Node3D).global_position + Vector3(0.3, 0.2, 0))
		await _frames(8)
	_eq("all the loot was picked up", get_tree().get_nodes_in_group("loot").size(), 0)
	_report("the items are in the bag", Session.character["inventory"].size() > bag_before)
	_eq("the sword from the drop list is there", Inventory.count(Session.character["inventory"], "wooden_sword"), 1)
	_eq("the sized potion is there", Inventory.count(Session.character["inventory"], "potion_hp_minor"), 1)

	# A full bag leaves the drop on the ground.
	var kept_bag: Array = Session.character["inventory"]
	var full: Array = []
	for i in Inventory.max_slots():
		full = Inventory.add(full, "iron_sword", 1)["inventory"]
	Session.character["inventory"] = full
	LootDrop.spawn(_world, Vector3(10, 0, 10), "iron_ring", 1)
	await _stand_at(Vector3(10.2, 0.2, 10))
	await _frames(15)
	_eq("with a full bag the drop stays", get_tree().get_nodes_in_group("loot").size(), 1)
	Session.character["inventory"] = kept_bag
	await _frames(15)
	_eq("with room again it is picked up", get_tree().get_nodes_in_group("loot").size(), 0)

	# An enemy that dies on its own gives nothing.
	var exp_before: int = Session.character["exp"]
	var lonely := _spawn_enemy("green_goblin", Vector3(-20, 0, -20))
	await _frames(3)
	lonely.combatant.take_damage(100000)
	_eq("an enemy that dies without the player's blow gives no EXP", Session.character["exp"], exp_before)
	_eq("...and drops nothing", get_tree().get_nodes_in_group("loot").size(), 0)

	# Rewards do not touch the enemy sheet.
	_eq("the goblin's sheet row is unchanged", [int(DataRegistry.get_enemy("green_goblin")["max_health"]),
			int(DataRegistry.get_enemy("green_goblin")["xp_reward"])], [145, 65])
	_eq("all 104 enemies are still there", DataRegistry.get_ids("enemies").size(), 104)
	_clear_enemies_and_loot()
	await _frames(3)


# ---------- player death ----------

func _test_player_death() -> void:
	print("[enemy] --- player death ---")
	_new_character("warrior")
	_player.refresh_stats()
	_player.revive()
	await _stand_at(Vector3(0, 0.2, 0))
	var deaths: Array = []
	_player.died.connect(func() -> void: deaths.append(true))
	_player.combatant.take_damage(_player.combatant.hp - 10)
	var killer := _spawn_enemy("green_goblin", Vector3(0, 0, -4))
	await _frames(200)
	_eq("the player dies", _player.is_dead(), true)
	_eq("the death was announced once", deaths.size(), 1)
	_eq("a dead player can not attack", _player.try_attack(PLAYER_ROLLS)["error"], "DEAD")
	await _frames(40)
	_eq("the enemy gives up on a dead player", killer.is_engaged(), false)

	_player.revive()
	_eq("revive: alive again", _player.is_dead(), false)
	_eq("revive: full health", _player.combatant.hp, _player.combatant.max_health())
	_report("revive: back at the starting point", _player.global_position.distance_to(_player.spawn_position) < 0.1)
	_clear_enemies_and_loot()
	await _frames(3)

	# Slow recovery when nothing is happening.
	_player.combatant.take_damage(60)
	var hp_low := _player.combatant.hp
	_player._combat_clock = 99.0
	await _frames(120)
	_report("out of combat, health slowly comes back", _player.combatant.hp > hp_low, "%d -> %d" % [hp_low, _player.combatant.hp])
	var in_combat := _player.combatant.hp
	_player._combat_clock = 0.0
	await _frames(60)
	_eq("but not while fighting", _player.combatant.hp, in_combat)


# ---------- HUD ----------

func _test_hud() -> void:
	print("[enemy] --- HUD ---")
	var hud: CombatHud = _world.combat_hud
	var before := hud._feed.get_child_count()
	Session.grant_rewards(30, 7)
	await _frames(2)
	_report("rewards show in the feed (EXP and gold lines)", hud._feed.get_child_count() >= before + 2)
	var level_before: int = Session.character["level"]
	Session.grant_rewards(100000, 0)
	await _frames(2)
	_report("a level up shows a banner", hud._banner.modulate.a > 0.5 and "LEVEL UP" in hud._banner.text, hud._banner.text)
	_report("...with the new level in it", str(Session.character["level"]) in hud._banner.text)
	_report("the player nameplate follows the level", str(Session.character["level"]) in _player._nameplate.text)
	_report("the level really went up", Session.character["level"] > level_before)

	_eq("the death panel is hidden while alive", hud._death_panel.visible, false)
	_player.combatant.take_damage(_player.combatant.hp)
	await _frames(2)
	_eq("the death panel shows when the player dies", hud._death_panel.visible, true)
	_player.revive()
	await _frames(2)
	_eq("it hides again after reviving", hud._death_panel.visible, false)


# ---------- camps ----------

func _test_camps() -> void:
	print("[enemy] --- camps ---")
	_world.queue_free()
	await _frames(3)
	_clear_enemies_and_loot()
	Enemy.active_count = 0
	_new_character("warrior")
	_world = load("res://maps/world_test.tscn").instantiate()
	add_child(_world)
	await _frames(3)
	_player = _world.player
	_eq("the world has 7 camps", _world.camps.size(), 7)

	var awake: Array = []
	var asleep: Array = []
	for camp in _world.camps:
		if camp.is_awake():
			awake.append(camp.enemy_id)
		else:
			asleep.append(camp.enemy_id)
	_eq("camps near the start are awake", awake.has("green_goblin") and awake.has("venomous_spider"), true)
	_eq("camps far away are asleep", asleep.has("bone_archer") and asleep.has("flame_imp"), true)
	var living := 0
	for camp in _world.camps:
		living += camp.alive_count()
	_eq("14 enemies are alive near the start (4 + 3 + 4 + 2 + 1)", living, 14)
	_eq("the sleeping camps have none at all", _camp(asleep[0]).alive_count() + _camp(asleep[1]).alive_count(), 0)
	_report("never more than the cap alive", Enemy.active_count <= 25)

	# Same camp, same spots.
	var homes_a: Array = []
	for slot in _camp("green_goblin")._slots:
		homes_a.append(slot["home"])
	var test_camp := EnemyCamp.new()
	test_camp.setup({"enemy_id": "green_goblin", "count": 4, "position": [24, -16], "radius": 8}, {}, _world)
	_world.add_child(test_camp)
	var same := true
	for i in 4:
		if not test_camp._slots[i]["home"].is_equal_approx(homes_a[i]):
			same = false
	_report("a camp always puts its enemies on the same spots", same)
	test_camp.queue_free()

	# Walking far wakes new camps and puts the old ones to sleep.
	await _stand_at(Vector3(-80, 0.2, -70))
	for camp in _world.camps:
		camp.tick(0.5)
	await _frames(3)
	_eq("the far camp wakes up", _camp("flame_imp").is_awake(), true)
	_eq("...and fills with 3 enemies", _camp("flame_imp").alive_count(), 3)
	_eq("the camp left behind sleeps", _camp("green_goblin").is_awake(), false)
	_eq("...and is empty", _camp("green_goblin").alive_count(), 0)

	# Back home: the goblins are there again.
	await _stand_at(Vector3(0, 0.2, 0))
	for camp in _world.camps:
		camp.tick(0.5)
	await _frames(3)
	_eq("coming back refills the goblin camp", _camp("green_goblin").alive_count(), 4)

	# Killing and respawning.
	var goblin_camp: EnemyCamp = _camp("green_goblin")
	var victim: Enemy
	for node in get_tree().get_nodes_in_group("targetable"):
		if node is Enemy and node.enemy_id == "green_goblin":
			victim = node
			break
	victim.combatant.take_damage(100000)
	await _frames(2)
	_eq("a killed enemy leaves the camp one short", goblin_camp.alive_count(), 3)
	goblin_camp.tick(15.0)
	_eq("after 15 seconds it has not come back", goblin_camp.alive_count(), 3)
	goblin_camp.tick(16.0)
	await _frames(2)
	_eq("after 30 seconds a new one has", goblin_camp.alive_count(), 4)

	# A fighting enemy is not removed when the player leaves.
	var fighter: Enemy
	for node in get_tree().get_nodes_in_group("targetable"):
		if node is Enemy and node.enemy_id == "green_goblin" and not node.is_dead():
			fighter = node
			break
	fighter.state = Enemy.State.CHASE
	await _stand_at(Vector3(-80, 0.2, -70))
	goblin_camp.tick(0.5)
	_eq("an enemy that is fighting stays", goblin_camp.alive_count() >= 1, true)

	# The cap.
	var map_rules: Dictionary = DataRegistry.get_config("world_camps")["map_1"]
	var normal_cap = map_rules["max_active_enemies"]
	map_rules["max_active_enemies"] = 3
	_clear_enemies_and_loot()
	await _frames(3)
	Enemy.active_count = 0
	for camp in _world.camps:
		for slot in camp._slots:
			slot["enemy"] = null
			slot["respawn_in"] = 0.0
	await _stand_at(Vector3(0, 0.2, 0))
	for camp in _world.camps:
		camp.tick(0.5)
	await _frames(3)
	_report("the active enemy cap is respected (3)", Enemy.active_count <= 3, str(Enemy.active_count))
	map_rules["max_active_enemies"] = normal_cap


func _camp(enemy_id: String) -> EnemyCamp:
	for camp in _world.camps:
		if camp.enemy_id == enemy_id:
			return camp
	return null
