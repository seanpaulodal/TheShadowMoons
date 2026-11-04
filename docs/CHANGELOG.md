# CHANGELOG

## [M1] Boot flow and data registry  (2026-11-04)

### Added
- autoload/event_bus.gd (EventBus: global signals)
- autoload/data_registry.gd (DataRegistry: loads and validates JSON data)
- ui/loading/boot.tscn and boot.gd (logo, splash, data check, scene change)
- maps/data_test.tscn and systems/data_test.gd (M1 test scene)
- data/TSM_Master_Data.json, TSM_Enemy_Data.json, TSM_Achievements.json

### Changed
- DataRegistry: unwraps sheet-name wrappers, supports column aliases,
  skips blank rows with a warning, treats null as missing, and safely
  reads non-numeric enemy levels
- Android export filter now includes data/*.json
- Main scene set to boot.tscn

### Fixed
- TSM_Enemy_Data.json: removed orphaned null block that split the file and
  left 13 boss enemies outside the Enemy_Data section (104 enemies now load)

### Known issues
- None

### Tests passed
- All three tables load with no errors or warnings

## [M0] Project setup  (YYYY-MM-DD)

### Added
- New Godot project (Mobile renderer), private GitHub repo
- Folder skeleton (28 folders) and 10 documentation stubs
- maps/m0_test.tscn

### Notes
- Project settings: 1920x1080, canvas_items stretch, expand aspect, landscape
