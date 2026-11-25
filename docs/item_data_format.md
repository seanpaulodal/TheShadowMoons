# Item data (TSM_Master_Data.json)

601 items: 72 original, 79 class-set gear, 450 elemental weapons. Three file shapes are
accepted (ids inside a sheet-name wrapper, ids at the top, or a list of rows with an
`item_id` column). Columns, in order:

item_name, item_desc, item_rarity, item_type, dropped_by_enemy, drop_chance, drop_min,
drop_max, stackable, item_buy_value, item_sell_value, item_BType, item_BValue, dmg_min,
dmg_max, crit_chance_bonus, crit_dmg_bonus, elem_dmg, status_element, status_effect,
effect_chance, item_iconpath, item_class, weapon_type

## What the game does with each new column

- **item_class**: who may equip it. A class name (Warrior, Mage, Archer, Rogue, Gunner,
  Extreme, Brawler, Healer, Necromancer), several separated by commas, `All`, or empty
  (= every class). An unknown class name is a data error.
- **weapon_type**: shown in the item details ("Weapon - Greatsword"). Not enforced yet:
  `item_class` already limits weapons to a class.

## Where the other facts come from

| Fact | Source (first match wins) |
|---|---|
| Equip slot | an `equip_slot` column; `data/TSM_Item_Extra.json`; weapons = weapon slot; otherwise a word in the item id (helm, chest, gloves, pants, boots, ring, necklace) |
| Level requirement | a `level_req` column; `data/TSM_Item_Extra.json` (placeholders: weapon tier 1-10 = level 1, 30 ... 270; set gear 10-80 by price) |
| Bonus (item_BType / item_BValue) | Attack, Magic Attack, Defense, DEF, Max HP, Max Mana, Speed = that stat. STR, AGI, VIT, INT, DEX, WIS, LCK = that many attribute points |
| Element damage | `elem_dmg` as text "25 (Fire)", or as a number with the element in `status_element` |

Rules live in `data/TSM_Item_Rules.json` (slot_keywords, slot_defaults, btype_to_stat,
attribute_btypes) and `data/TSM_Element_Rules.json` (aliases: Wind counts as Nature).
Run `dev/gear_data_test.tscn` after changing the sheet: it lists any item with a problem.
