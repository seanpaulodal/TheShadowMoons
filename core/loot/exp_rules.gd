class_name ExpRules
extends RefCounted
## EXP rules after a kill. Only the player who lands the killing blow gets the
## EXP. A party adds a bonus on top (2% for every other member). Parties do not
## exist yet, so the party size is always 1 for now (the hook is here for later).


## How many players are in the killer's party (the killer included).
static func current_party_size() -> int:
	return 1


## 1.0 alone, 1.02 with one other member, 1.04 with two, ...
static func party_multiplier(party_size: int) -> float:
	var per_member := float(DataRegistry.get_config("combat_rules").get("party_exp_bonus_per_member", 0.02))
	return 1.0 + per_member * float(maxi(0, party_size - 1))


static func exp_for_kill(base_exp: int, party_size: int = 1) -> int:
	return int(floor(float(base_exp) * party_multiplier(party_size)))
