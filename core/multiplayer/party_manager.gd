class_name PartyManager
extends RefCounted
## Handles party creation, membership, and EXP bonuses.
## Bonus: 2% EXP per member (excluding self).

signal party_created(party_id: String)
signal member_joined(user_id: String)
signal member_left(user_id: String)
signal party_disbanded(party_id: String)

const EXP_BONUS_PER_MEMBER := 0.02
var _current_party: Dictionary = {}
var _current_user_id: String = ""

func _ready() -> void:
    EventBus.data_loaded.connect(func(_): _sync_from_session())
    Session.character_loaded.connect(func(character: Dictionary): _sync_from_session())
    Session.character_changed.connect(func(character: Dictionary): _sync_from_session())

func _sync_from_session() -> void:
    _current_user_id = FirebaseService.uid
    var party_id := Session.character.get("party_id", "")
    if party_id == "":
        # No party yet: this player is solo
        _current_party = {"leader": _current_user_id, "members": [_current_user_id], "id": _current_user_id}
        return
    # Party exists: look up existing membership
    _current_party = {"leader": party_id, "members": [party_id, _current_user_id], "id": party_id}
    party_created.emit(party_id)

func has_character() -> bool:
    return Session.has_character() if has_method("has_character") else false

func create_party() -> void:
    var uid := FirebaseService.uid
    if not has_character():
        return
    var result := Session.save_fields({"party_id": uid})
    if result["ok"]:
        _current_party = {"leader": uid, "members": [uid], "id": uid}
        party_created.emit(uid)

func join_party(party_id: String) -> void:
    var uid := FirebaseService.uid
    if uid == party_id:
        return
    var result := Session.save_fields({"party_id": party_id})
    if result["ok"]:
        _current_party = {"leader": party_id, "members": [party_id, uid], "id": party_id}
        member_joined.emit(party_id)
        party_created.emit(party_id)

func leave_party() -> void:
    var uid := FirebaseService.uid
    var party_id := _current_party.get("id", "")
    var result := Session.save_fields({"party_id": ""})
    if result["ok"]:
        _current_party = {"leader": uid, "members": [uid], "id": uid}
        member_left.emit(uid)
        party_disbanded.emit(party_id)

func member_count() -> int:
    return _current_party.get("members", []).size()

func get_exp_multiplier() -> float:
    var count := member_count()
    if count <= 1:
        return 1.0
    return 1.0 + (EXP_BONUS_PER_MEMBER * (count - 1))

func get_current_party() -> Dictionary:
    return _current_party.duplicate(true)

func is_leader() -> bool:
    return _current_party.get("leader", "") == FirebaseService.uid
