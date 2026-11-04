extends Node
## Temporary M1 test. Delete or keep out of release builds.

func _ready() -> void:
	var report := DataRegistry.get_report()
	print("=== DataRegistry report ===")
	print("Counts: ", report["counts"])
	print("Errors: ", report["errors"].size(), " | Warnings: ", report["warnings"].size())

	for table_name in ["items", "enemies", "achievements"]:
		var ids := DataRegistry.get_ids(table_name)
		print("--- %s: first 3 ids ---" % table_name)
		for i in mini(3, ids.size()):
			print(ids[i])

	var item_ids := DataRegistry.get_ids("items")
	if not item_ids.is_empty():
		print("Lookup test: ", DataRegistry.get_item(item_ids[0]))
	print("Missing id returns empty dict: ", DataRegistry.get_item("does_not_exist").is_empty())
