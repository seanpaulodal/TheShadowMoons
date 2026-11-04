# DATABASE STRUCTURE

Last updated: M1

## 1. Data files (static game data)

All files live in `res://data/` and are loaded only by the `DataRegistry` autoload.
Nothing else parses these files directly.

| Table | File | ID field | Required fields | Rows loaded |
|---|---|---|---|---|
| items | TSM_Master_Data.json | item_id | item_id, item_name, item_type, item_rarity | ___ |
| enemies | TSM_Enemy_Data.json | enemy_id | enemy_id, enemy_name, enemy_level, max_health | 104 |
| achievements | TSM_Achievements.json | id | id, name, category, completion_target | ___ |

Source of truth: Google Sheets (TSM_Master_Data, TSM_Enemy_Data, TSM_Achievements),
exported to JSON. Edit the sheet, then re-export. Do not hand-edit the JSON.

JSON layout: each file is wrapped in one key named after the sheet
(for example `{"Enemy_Data": {"training_dummy": {...}, ...}}`), with rows keyed by ID.

## 2. Item fields

item_id, item_name, item_desc, item_rarity, item_type, buy price, sell price,
item_BType, item_BValue, damage stats, critical stats, elemental stats,
status info, effect info, item_iconpath, drop info.

## 3. Enemy fields

enemy_name, enemy_description, enemy_color, enemy_rarity, enemy_type, enemy_level,
max_health, max_mana, max_stamina, def_power, atk_power, atk_speed, move_speed,
chase_speed, roam_radius, atk_CD, atk_RNG, PTN_dropchance, MNA_dropchance,
xp_reward, gold_min, gold_max, accuracy, crit chance, crit DMG, evasion,
status_ELEM, block rate, block mitigation, parry rate, status_EFF, effect_chance,
enemy_icon, idle_anim, walk_anim, attack_anim, die_anim.

Rules:
- Enemy level never exceeds 2000 (training dummy excepted).
- Training dummy: level 999999, HP 999999, no rewards. Testing only.
- Enemy elemental weaknesses come from the ElementalSystem, not from this table.
  `status_ELEM` is the enemy's attack status, not a weakness.
- The enemy ID is the JSON key. DataRegistry copies it into the `enemy_id` field.
- Some columns contain spaces (`crit chance`, `crit DMG`, `block rate`,
  `block mitigation`, `parry rate`). Consider renaming them to snake_case
  before combat code is written (M5).

## 4. Achievement fields

id, name (alias: achievement_name), desc (alias: achievement_desc),
category (alias: achievement_category), reward_type, reward_value,
reward_item_id, completion_target, is_hidden, iconpath.

## 5. Validation rules (enforced by DataRegistry)

- Missing or null required field: row skipped, error logged with table,
  row number, ID and name.
- Completely blank row: skipped with a warning.
- Duplicate ID: second row skipped, error logged.
- Malformed JSON: file skipped, error logged with line number.
- Enemy level above 2000 or not a number: warning logged.
- Alternate column names listed under "aliases" in DataRegistry are copied
  into the canonical field.

## 6. Player data (cloud, Firestore)

Planned in M2. Not implemented yet.

## 7. Known data issues

- None at the end of M1. Enemy JSON was repaired by hand once (stray blank
  entry broke the Enemy_Data wrapper). Avoid hand-editing exported JSON.
