extends GutTest


func _approach(rules: MatchRules, seat: int = 0) -> void:
	var center: Vector2 = rules.positions[seat]
	rules.ball_position = center + Vector2(0, 2.4)
	rules.ball_velocity = Vector2(0, -14)
	rules.set_shield_angle(seat, PI / 2.0)


func _item_rules(kind: String) -> MatchRules:
	var rules := MatchRules.new(17)
	rules.items = [{"kind": kind, "position": Vector2.ZERO, "cooldown": 0.0}]
	rules.ball_position = Vector2(-2, 0)
	rules.ball_velocity = Vector2(20, 0)
	return rules


func _kinds(events: Array[Dictionary]) -> Array:
	return events.map(func(event: Dictionary) -> String: return event["kind"])


func test_bump_requires_timed_contact_and_expires_to_normal_speed() -> void:
	var rules := MatchRules.new()
	_approach(rules)
	assert_true(rules.arm_bump(0))
	assert_false(rules.arm_bump(0), "cooldown prevents repeated presses")
	var events := rules.step(0.02)
	assert_has(_kinds(events), "bump")
	assert_gt(rules.ball_velocity.y, 28.0)
	assert_almost_eq(rules.ball_velocity.length(), 14.0 * MatchRules.BOOST_MULTIPLIER, 0.001)
	assert_eq(rules.bump_windows[0], 0.0, "one press powers only one contact")
	rules.ball_position = Vector2(1000, 1000)
	rules.step(MatchRules.BOOST_SECONDS + 0.01)
	assert_almost_eq(rules.ball_velocity.length(), 14.0, 0.001)
	assert_true(rules.arm_bump(0), "cooldown eventually recovers")


func test_early_and_late_bumps_do_not_power_a_return() -> void:
	var early := MatchRules.new()
	early.ball_velocity = Vector2.ZERO
	early.arm_bump(0)
	early.step(MatchRules.BUMP_WINDOW + 0.01)
	_approach(early)
	assert_does_not_have(_kinds(early.step(0.02)), "bump")
	assert_almost_eq(early.ball_velocity.length(), 14.0, 0.001)
	var late := MatchRules.new()
	_approach(late)
	late.step(0.02)
	late.arm_bump(0)
	assert_does_not_have(_kinds(late.step(0.02)), "bump")
	assert_almost_eq(late.ball_velocity.length(), 14.0, 0.001)


func test_contact_after_window_inside_same_tick_does_not_bump() -> void:
	var rules := MatchRules.new()
	_approach(rules)
	rules.arm_bump(0)
	rules.bump_windows[0] = 0.001
	assert_does_not_have(_kinds(rules.step(0.02)), "bump")


func test_dead_or_invalid_seats_cannot_bump() -> void:
	var rules := MatchRules.new()
	rules.keeps[0]["alive"] = false
	assert_false(rules.arm_bump(0))
	assert_false(rules.arm_bump(-1))
	assert_false(rules.arm_bump(4))
	rules.over = true
	assert_false(rules.arm_bump(1))


func test_speed_target_is_swept_and_boosts_without_stacking() -> void:
	var rules := _item_rules("speed")
	rules.ball_velocity = Vector2(2000, 0)
	assert_has(_kinds(rules.step(1.0 / 120.0)), "item", "fast balls cannot tunnel through targets")
	assert_lte(rules.ball_velocity.length(), MatchRules.MAX_BOOST_SPEED)
	var speed := rules.ball_velocity.length()
	rules.items[0]["cooldown"] = 0.0
	rules.ball_position = Vector2(-2, 0)
	rules.ball_velocity = Vector2.RIGHT * speed
	rules.step(0.1)
	assert_almost_eq(rules.ball_velocity.length(), speed, 0.001, "repeated boosts refresh, not multiply")
	assert_gt(rules.balls[0]["boost"], 2.9)
	rules.ball_position = Vector2(1000, 1000)
	rules.step(MatchRules.BOOST_SECONDS + 0.01)
	assert_almost_eq(rules.ball_velocity.length(), MatchRules.MAX_NORMAL_SPEED, 0.001)


func test_target_cooldown_and_respawn() -> void:
	var rules := _item_rules("speed")
	rules.step(0.1)
	assert_gt(rules.items[0]["cooldown"], 9.0)
	rules.ball_position = Vector2(-2, 0)
	rules.ball_velocity = Vector2(20, 0)
	assert_does_not_have(_kinds(rules.step(0.1)), "item")
	rules.ball_velocity = Vector2.ZERO
	rules.step(MatchRules.ITEM_RESPAWN)
	assert_eq(rules.items[0]["cooldown"], 0.0)
	rules.ball_position = Vector2(-2, 0)
	rules.ball_velocity = Vector2(20, 0)
	assert_has(_kinds(rules.step(0.1)), "item")


func test_split_creates_diverging_balls_and_respects_cap() -> void:
	var rules := _item_rules("split")
	rules.step(0.1)
	assert_eq(rules.balls.size(), 3)
	assert_gt(Vector2(rules.balls[1]["velocity"]).distance_to(rules.balls[2]["velocity"]), 1.0)
	for ball in rules.balls:
		assert_almost_eq(Vector2(ball["velocity"]).length(), 20.0, 0.001)
	rules.items[0]["cooldown"] = 0.0
	rules.ball_position = Vector2(-2, 0)
	rules.step(0.1)
	assert_eq(rules.balls.size(), MatchRules.MAX_BALLS)
	rules.items.clear()
	for ball in rules.balls:
		ball["position"] = Vector2(1000, 1000)
	rules.step(MatchRules.SPLIT_SECONDS + 0.1)
	assert_eq(rules.balls.size(), 1, "temporary extra balls expire")


func test_extra_ball_breaks_wall_and_core_hit_does_not_stop_other_balls() -> void:
	var rules := _item_rules("split")
	rules.step(0.1)
	rules.items.clear()
	var center: Vector2 = rules.positions[0]
	rules.set_shield_angle(0, -PI / 2.0)
	rules.balls[1]["position"] = center + Vector2(0, 1.3)
	rules.balls[1]["velocity"] = Vector2(0, -200)
	assert_has(_kinds(rules.step(0.01)), "wall")
	assert_false(rules.keeps[0]["walls"][2])
	rules.balls[1]["position"] = center + Vector2(0, 0.6)
	rules.balls[1]["velocity"] = Vector2(0, -200)
	assert_has(_kinds(rules.step(0.01)), "core")
	assert_false(rules.keeps[0]["alive"])
	assert_eq(rules.balls.size(), 2)
	assert_true(rules.has_moving_ball())
	assert_false(rules.over)


func test_last_core_hit_stops_every_ball_and_announces_one_winner() -> void:
	var rules := _item_rules("split")
	rules.step(0.1)
	rules.items.clear()
	rules.keeps[1]["alive"] = false
	rules.keeps[3]["alive"] = false
	rules.keeps[0]["walls"] = [false, false, false]
	rules.balls[0]["position"] = rules.positions[0] + Vector2(0, 0.6)
	rules.balls[0]["velocity"] = Vector2(0, -200)
	var kinds := _kinds(rules.step(0.01))
	assert_eq(kinds.count("win"), 1)
	assert_eq(rules.winner, 2)
	assert_false(rules.has_moving_ball())


func test_final_split_ball_becomes_persistent_before_splitting_again() -> void:
	var rules := _item_rules("split")
	rules.step(0.1)
	rules.balls[0]["velocity"] = Vector2.ZERO
	rules.balls[1]["life"] = 0.0
	rules.balls[2]["life"] = 0.0
	rules.step(0.01)
	assert_eq(rules.balls.size(), 1)
	assert_true(rules.has_moving_ball())
	assert_eq(rules.balls[0]["life"], -1.0)
	rules.items[0]["cooldown"] = 0.0
	rules.ball_position = Vector2(-2, 0)
	rules.ball_velocity = Vector2(20, 0)
	rules.step(0.1)
	rules.step(0.01)
	assert_eq(rules.balls.size(), 3, "splitting a survivor must not immediately expire the main ball")


func test_shrink_changes_collision_arc_and_recovers() -> void:
	var rules := _item_rules("shrink")
	rules.step(0.1)
	assert_gt(rules.shrink_remaining, 7.0)
	assert_almost_eq(rules.shield_half_arc(), MatchRules.SHIELD_HALF_ARC * MatchRules.SHRINK_SCALE, 0.001)
	rules.items.clear()
	var radial := Vector2.RIGHT.rotated(PI / 2.0 + 0.6)
	rules.ball_position = rules.positions[0] + radial * 3.0
	rules.ball_velocity = -radial * 14.0
	rules.set_shield_angle(0, PI / 2.0)
	var kinds := _kinds(rules.step(0.15))
	assert_does_not_have(kinds, "shield", "grazing approaches pass a narrowed shield")
	assert_has(kinds, "wall")
	rules.ball_position = Vector2(1000, 1000)
	rules.step(MatchRules.SHRINK_SECONDS)
	assert_eq(rules.shrink_remaining, 0.0)
	assert_eq(rules.shield_half_arc(), MatchRules.SHIELD_HALF_ARC)


func test_controller_freezes_effects_on_pause_and_resets_on_restart() -> void:
	var controller := RoundController.new(SeatRouting.make_solo_seats(0, false))
	assert_false(controller.bump(2), "no attacks during countdown")
	controller.state = RoundController.State.PLAYING
	assert_false(controller.bump(0), "humans cannot activate bot seats")
	assert_true(controller.bump(2))
	controller.rules.shrink_remaining = 5.0
	controller.rules.items[0]["cooldown"] = 5.0
	controller.rules.balls[0]["boost"] = 2.0
	controller.set_paused(true)
	assert_false(controller.bump(2))
	controller.advance(1.0)
	assert_eq(controller.rules.shrink_remaining, 5.0)
	assert_eq(controller.rules.items[0]["cooldown"], 5.0)
	assert_eq(controller.rules.balls[0]["boost"], 2.0)
	assert_eq(controller.rules.bump_cooldowns[2], MatchRules.BUMP_COOLDOWN)
	controller.restart()
	assert_eq(controller.rules.balls.size(), 1)
	assert_eq(controller.rules.shrink_remaining, 0.0)
	assert_eq(controller.rules.bump_cooldowns[2], 0.0)
	assert_eq(controller.rules.items[0]["cooldown"], 0.0)


func test_controller_rails_and_timeout_cover_all_balls() -> void:
	var controller := RoundController.new(SeatRouting.make_solo_seats(0, false))
	controller.rules.balls.append(MatchRules._new_ball(Vector2(17, 0), Vector2(30, 0)))
	controller._apply_rails()
	assert_eq(controller.rules.balls[1]["position"], Vector2(16, 0))
	assert_eq(controller.rules.balls[1]["velocity"], Vector2(-30, 0))
	controller._time_out()
	assert_false(controller.rules.has_moving_ball())


func test_reserve_cooldowns_advance_and_serve_clears_temporary_ball_metadata() -> void:
	var controller := RoundController.new(SeatRouting.make_solo_seats(0, false))
	controller.state = RoundController.State.PLAYING
	controller.rules.stop_balls()
	controller.timer = 1.0
	controller.rules.bump_cooldowns[2] = 0.5
	controller.rules.shrink_remaining = 0.5
	controller.rules.balls[0]["life"] = 0.01
	controller.tick()
	assert_lt(controller.rules.bump_cooldowns[2], 0.5)
	assert_lt(controller.rules.shrink_remaining, 0.5)
	controller.timer = 0.0
	controller.tick()
	assert_true(controller.rules.has_moving_ball())
	assert_eq(controller.rules.balls[0]["life"], -1.0)


func test_seeded_multiball_rounds_stay_reproducible() -> void:
	var left := _item_rules("split")
	var right := _item_rules("split")
	left.step(0.1)
	right.step(0.1)
	for tick in range(600):
		left.step(RoundController.TICK)
		right.step(RoundController.TICK)
	assert_eq(left.balls, right.balls)
	assert_eq(left.items, right.items)
	assert_eq(left.keeps, right.keeps)
