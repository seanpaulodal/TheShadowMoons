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

## Part 2: casting
- The MP bar is the class bar (Rage, Mana, Focus...): at least 100 for every class (the
  minimum max_mana in TSM_Stat_Rules.json), more with INT and WIS. Rules per class are in
  data/TSM_Class_Resources.json (start full or empty, refill, drain, gain from hits and kills).
- Skills hit the current target, or the nearest enemy in range. They cannot miss, but can
  crit. Damage = (base + attribute x scaling) x rank multiplier, then buffs, execute bonus,
  the target's defense (physical) or magic resist (everything else), element (holy, dark),
  crits and shields. Gear's attack power does not add to skills yet (only attributes do).
- A cast takes the skill's cast time (no moving restrictions); its cost and cooldown are
  taken at the start. Basic attacks wait while casting. Silence blocks casting. Death cancels.
- Several hits: the skill's damage is divided evenly between its hits (0.12 s apart).
- The skill data leaves effect details to the game, so tags decide them (see TSM_Skill_Rules.json):
  crowd control tags -> root / slow / silence; buff tags -> which stat (defense_buff = defense,
  mobility_buff = move speed, attack_speed_form = attack speed, magic_buff = magic power,
  attack_debuff and defense_and_speed_debuff = a debuff on the enemy; anything else = attack
  power); damage over time tags -> poison or dark; movement tags -> dash, backstep, teleport.
- Shields (damage_absorption_percent) cut damage taken by that percent for their duration.
- Keys 1 to 8 cast the slots. On the phone, four buttons sit around the ATK button; the small
  button swaps between slots 1-4 and 5-8.

## Not built yet (part 3)
Summons (10 summon skills are refused for now: "coming in the next update"), the nine
ultimates and the nine special attacks.
