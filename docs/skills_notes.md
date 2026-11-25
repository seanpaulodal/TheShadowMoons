# Skills (first part: data, points, learning, slots, window)

Loaded from your TSM_Skill_Database package (data/TSM_Skills.json, TSM_Skill_Trees.json,
TSM_Class_Ultimates.json, TSM_Class_Special_Attacks.json, TSM_Skill_Effects.json). The
example per-character file is kept in docs/TSM_Player_Skills_Schema.json for reference.

## Rules that are NOT in your files (placeholders in data/TSM_Skill_Rules.json)
- points_per_level: 3 skill points per level.
- Every rank of a skill costs that skill's skill_point_cost. The class's level 1 skill is
  learned for free at rank 1 (its higher ranks cost points).
- Ultimates and special attacks: unlock by their own unlock_level (200 / 100) at rank 1,
  free; each higher rank (to 5) costs ability_rank_cost (8) points.
- require_trials: false. When true, ultimates and specials also need their trial (the trials
  will come with quests); Session.complete_trial("special" | "ultimate") records it.
- respec_gold: 0 (resetting skills is free for now; the price is respec_gold x level).

## What is saved on the character ("skills")
{"learned": {skill_id: rank}, "slots": {"skill_1".."skill_8": skill_id or ""},
 "abilities": {ability_id: rank}, "trials": {"special": bool, "ultimate": bool}}
Skill points are never stored: points = 3 x level minus the cost of the ranks above, so
they cannot get out of step. (Like the rest of the build, this is checked by the client
for now; the server check comes with the multiplayer backend.)

## Not built yet (next parts)
Casting, the hotbar, the class resource bar, targeting and every effect (damage, buff,
crowd control, defense, healing, damage over time, movement, execute), then summons,
the nine ultimates and the nine special attacks.
