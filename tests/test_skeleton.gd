extends GutTest
## Issue #1 skeleton gates: project loads, toolchain pin holds, presets carry
## the required identity and no credentials.


const MENU_SCENE := "res://scenes/menu.tscn"


func test_main_scene_loads_and_instantiates() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), MENU_SCENE)
	var scene: PackedScene = load(MENU_SCENE)
	assert_not_null(scene, "menu scene missing")
	if scene != null:
		var inst: Node = scene.instantiate()
		assert_not_null(inst, "menu scene cannot instantiate")
		inst.free()


func test_toolchain_pin_matches_project() -> void:
	var file := FileAccess.open("res://docs/toolchain.json", FileAccess.READ)
	assert_not_null(file, "docs/toolchain.json missing")
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert_eq(parsed["engine_version"], "4.7.2-stable")
	assert_eq(parsed["engine"], "Godot")
	var features: PackedStringArray = ProjectSettings.get_setting("application/config/features")
	assert_true("4.7" in features, "project features do not declare 4.7")


func test_bundle_identity_in_presets() -> void:
	var text := _read("res://export_presets.cfg")
	assert_true(text.contains("name=\"Windows Desktop\""), "Windows Desktop preset missing")
	assert_true(text.contains("name=\"Android\""), "Android preset missing")
	assert_true(text.contains("name=\"iOS\""), "iOS preset missing")
	assert_true(
		text.contains("package/unique_name=\"com.infinityball.keepclash\""),
		"Android unique_name must be com.infinityball.keepclash",
	)
	assert_true(
		text.contains("application/bundle_identifier=\"com.infinityball.keepclash\""),
		"iOS bundle_identifier must be com.infinityball.keepclash",
	)


func test_export_presets_have_no_credentials() -> void:
	var text := _read("res://export_presets.cfg")
	var forbidden := ["keystore", "password", "ASC_KEY", "TEAM_ID", "mobileprovision", "codesign/identity"]
	for key in forbidden:
		assert_false(text.contains(key), "preset must not reference credential key: " + key)


func test_zero_network_contract() -> void:
	var file := FileAccess.open("res://docs/toolchain.json", FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert_eq(parsed["network"]["cloud_sync"], false)
	assert_eq(parsed["network"]["telemetry"], false)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "missing file: " + path)
	if file == null:
		return ""
	return file.get_as_text()
