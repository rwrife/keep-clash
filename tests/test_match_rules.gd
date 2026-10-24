extends GutTest
## Issue #2 gates for the pure match model: shield reflection, wall destruction
## order, last-keep-standing termination, seed-reproducible bots, star scoring,
## and analytic sweep (no tunneling at high ball speed).

const SEAT0 := Vector2(0, -12)


func _rules(seed_value: int = 7) -> MatchRules:
	var rules: MatchRules = MatchRules.new(seed_value)
	return rules


func _aim_at_core(rules: MatchRules, seat: int, angle: float, speed: float) -> void:
	## Unit-test-only setup: place the ball on a radial approach line, which lets
	## each wall sector be exercised independently of arena geometry.
	var center: Vector2 = MatchRules.SEAT_POSITIONS[seat]
	var outward := Vector2.RIGHT.rotated(angle)
	rules.ball_position = center + outward * 6.0
	rules.ball_velocity = -outward * speed
	rules.set_shield_angle(seat, angle + PI)


func test_rules_are_node_free_and_fixed_step() -> void:
	var rules := _rules()
	assert_true(rules is RefCounted, "rules must be a RefCounted")
	var as_object: Object = rules
	assert_false(as_object is Node, "rules module must not depend on Node")
	assert_eq(rules.ticks, 0)
	rules.step(1.0 / 120.0)
	assert_eq(rules.ticks, 1, "one step call is one fixed tick")
	rules.step(0.0)
	assert_eq(rules.ticks, 1, "non-positive dt must not advance the match")


func test_ball_reflects_off_shield_arc() -> void:
	var rules := _rules()
	rules.ball_position = Vector2(0, -4)
	rules.ball_velocity = Vector2(0, -10)
	var events: Array[Dictionary] = rules.step(0.6)
	assert_eq(events.size(), 1, "expected exactly one shield event")
	if events.is_empty():
		return
	assert_eq(events[0]["kind"], "shield")
	assert_eq(events[0]["seat"], 0)
	assert_almost_eq(rules.ball_velocity.x, 0.0, 0.001)
	assert_almost_eq(rules.ball_velocity.y, 10.0, 0.001)
	assert_eq(rules.keeps[0]["deflections"], 1)


func test_shield_outside_arc_lets_ball_hit_wall() -> void:
	var rules := _rules()
	rules.set_shield_angle(0, -PI / 2.0)
	rules.ball_position = Vector2(0, -4)
	rules.ball_velocity = Vector2(0, -10)
	var events: Array[Dictionary] = rules.step(0.75)
	assert_eq(events.size(), 1)
	if events.is_empty():
		return
	assert_eq(events[0]["kind"], "wall", "ball must reach the rampart behind a turned shield")
	assert_eq(events[0]["wall"], 2)
	assert_false(rules.keeps[0]["walls"][2])


func test_glancing_shield_deflection_uses_contact_normal() -> void:
	var rules := _rules()
	var incoming := Vector2(14, -2)
	rules.ball_position = Vector2.ZERO
	rules.ball_velocity = incoming
	rules.step(0.74)
	# Contact on seat 1's arc at normal (-0.77244, -0.63500); reflected vector is analytic.
	assert_almost_eq(rules.ball_velocity.x, -0.744, 0.02)
	assert_almost_eq(rules.ball_velocity.y, -14.122, 0.02)
	assert_almost_eq(rules.ball_velocity.length(), incoming.length(), 0.01, "deflection preserves speed")
	assert_eq(rules.keeps[1]["deflections"], 1)


func test_wall_sector_mapping() -> void:
	assert_eq(MatchRules.wall_sector(-PI / 2.0), 0)
	assert_eq(MatchRules.wall_sector(0.0), 1)
	assert_eq(MatchRules.wall_sector(PI / 2.0), 2)
	assert_eq(MatchRules.wall_sector(-PI), 0, "wrap boundary maps to the first sector")


func test_wall_segments_destroy_one_at_a_time_then_core() -> void:
	var rules := _rules()
	var walls: Array = rules.keeps[0]["walls"]
	for pass_number in range(3):
		_aim_at_core(rules, 0, [-PI / 2.0, 0.0, PI / 2.0][pass_number], 12.0)
		var events: Array[Dictionary] = rules.step(0.5)
		assert_eq(events.size(), 1, "pass %d: one wall per approach" % pass_number)
		if events.is_empty():
			return
		assert_eq(events[0]["kind"], "wall")
		assert_eq(events[0]["wall"], pass_number)
		assert_eq(walls.count(false), pass_number + 1, "exactly one segment dies per hit")
	assert_true(rules.keeps[0]["alive"], "core survives while any wall remains")

	_aim_at_core(rules, 0, PI / 2.0, 12.0)
	var events: Array[Dictionary] = rules.step(0.5)
	assert_eq(events[0]["kind"], "core")
	assert_false(rules.keeps[0]["alive"])
	assert_eq(walls.count(false), 3)


func test_last_keep_standing_ends_the_round() -> void:
	var rules := _rules()
	rules.keeps[2]["alive"] = false
	rules.keeps[3]["alive"] = false
	rules.keeps[0]["walls"] = [false, false, false]
	_aim_at_core(rules, 0, PI / 2.0, 12.0)
	var events: Array[Dictionary] = rules.step(0.5)
	var kinds: Array[String] = []
	for event in events:
		kinds.append(event["kind"])
	assert_has(kinds, "core")
	assert_has(kinds, "win", "round must announce a winner once one keep stands")
	assert_eq(rules.winner, 1)
	assert_true(rules.over)
	assert_true(rules.step(0.5).is_empty(), "a finished match must not advance")


func test_bot_behavior_is_seed_reproducible() -> void:
	var first := _rules(4242)
	var second := _rules(4242)
	var other := _rules(9001)
	var diverged := false
	for _tick in range(20):
		for seat in range(4):
			for difficulty in range(3):
				var a := first.bot_target(seat, difficulty)
				var b := second.bot_target(seat, difficulty)
				var c := other.bot_target(seat, difficulty)
				assert_eq(a, b)
				if absf(a - c) > 1e-6:
					diverged = true
	assert_true(diverged, "a different seed must change bot decisions")
	assert_eq(first.bot_target(0, 5), 0.0, "invalid difficulty is rejected")


func test_full_match_simulation_is_deterministic() -> void:
	var left := _rules(31337)
	var right := _rules(31337)
	left.serve(-PI / 2.0)
	right.serve(-PI / 2.0)
	for _tick in range(3000):
		for seat in range(4):
			left.set_shield_angle(seat, wrapf(left.bot_target(seat, 0), -PI, PI))
			right.set_shield_angle(seat, wrapf(right.bot_target(seat, 0), -PI, PI))
		left.step(1.0 / 120.0)
		right.step(1.0 / 120.0)
		if left.ball_velocity.is_zero_approx() and not left.over:
			# Model parks the ball after a core hit; the scene would serve again.
			left.serve(-PI / 2.0)
			right.serve(-PI / 2.0)
	assert_eq(left.ticks, right.ticks)
	assert_eq(left.winner, right.winner)
	assert_eq(left.ball_position, right.ball_position)
	var deflections := 0
	for seat in range(4):
		assert_eq(left.keeps[seat]["walls"], right.keeps[seat]["walls"])
		deflections += left.keeps[seat]["deflections"]
	assert_gt(deflections, 0, "simulation must actually produce shield deflections")


func test_star_scoring() -> void:
	var rules := _rules()
	rules.winner = 0
	assert_eq(rules.keeps[0]["walls"].count(true), 3)
	assert_eq(rules.stars_for(0), 2, "intact ramparts award a bonus star")
	assert_eq(rules.stars_for(1), 0, "losers earn nothing")
	rules.keeps[0]["deflections"] = 3
	assert_eq(rules.stars_for(0), 3, "three clean deflections award the skill star")
	rules.keeps[0]["walls"][0] = false
	assert_eq(rules.stars_for(0), 2)
	rules.winner = -1
	assert_eq(rules.stars_for(0), 0, "unfinished matches award nothing")


func test_sweep_prevents_tunneling_at_high_speed() -> void:
	## Sweep contract: entry time is solved analytically per tick, so a ball that
	## would leap past a keep between frames still resolves on that tick.
	var rules := _rules()
	rules.set_shield_angle(0, -PI / 2.0)
	rules.ball_position = Vector2(0, -8)
	rules.ball_velocity = Vector2(0, -2000.0)
	var dt := 1.0 / 120.0
	var swept := MatchRules.sweep_circle(rules.ball_position, rules.ball_velocity, dt, SEAT0, MatchRules.WALL_RADIUS)
	assert_gt(swept, 0.0)
	assert_true(swept <= dt, "a 2000 m/s ball must be caught inside one fixed tick")
	var endpoint := rules.ball_position + rules.ball_velocity * dt
	assert_true(endpoint.y < SEAT0.y, "naive integration would teleport the ball past the keep")
	var events: Array[Dictionary] = rules.step(dt)
	assert_eq(events.size(), 1)
	assert_eq(events[0]["kind"], "wall")
	assert_gt(rules.ball_position.distance_to(SEAT0), MatchRules.WALL_RADIUS,
		"ball resolves outside the rampart instead of passing through")


func test_sweep_ignores_already_overlapping_starts() -> void:
	assert_eq(MatchRules.sweep_circle(SEAT0, Vector2(0, -10), 1.0, SEAT0, MatchRules.WALL_RADIUS), -1.0,
		"overlapping starts are resolved by contact push-out, not by a new sweep")
