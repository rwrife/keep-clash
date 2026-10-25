extends SceneTree
## Regenerates the [input] section of project.godot from scripts/input_setup.gd.
## Run from the project root:
##   godot --headless -s tools/gen_input_map.gd
## Hand-editing [input] invites typos; edit InputSetup and re-run instead.


func _init() -> void:
	InputSetup.ensure()
	var cfg := ConfigFile.new()
	if cfg.load("res://project.godot") != OK:
		push_error("cannot load project.godot")
		quit(1)
		return
	for action in [InputSetup.ACTION_CCW, InputSetup.ACTION_CW, InputSetup.ACTION_PAUSE]:
		var events := InputMap.action_get_events(action)
		if events.is_empty():
			push_error("action has no events: %s" % action)
			quit(1)
			return
		cfg.set_value("input", action, {
			"deadzone": InputMap.action_get_deadzone(action),
			"events": events,
		})
	var err := cfg.save("res://project.godot")
	if err != OK:
		push_error("cannot save project.godot: %s" % error_string(err))
		quit(1)
		return
	print("input map regenerated")
	quit(0)
