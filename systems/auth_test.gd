extends Node
## Temporary M2.1 test.

const TEST_EMAIL := "tsm_test_01@example.com"
const TEST_PASSWORD := "Test1234!x"


func _ready() -> void:
	print("Configured: ", FirebaseService.is_configured())

	var result: Dictionary = await FirebaseService.sign_up(TEST_EMAIL, TEST_PASSWORD)
	if not result["ok"] and result["error"] == "EMAIL_EXISTS":
		print("Account exists, signing in instead...")
		result = await FirebaseService.sign_in(TEST_EMAIL, TEST_PASSWORD)
	print("Result: ", result)

	if result["ok"]:
		print("Signed in: ", FirebaseService.is_signed_in(), " | uid: ", FirebaseService.uid)

	FirebaseService.sign_out()
	print("After sign_out, signed in: ", FirebaseService.is_signed_in())

	var bad: Dictionary = await FirebaseService.sign_in(TEST_EMAIL, "wrong-password-123")
	print("Wrong password -> ", bad)
