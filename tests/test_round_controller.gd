extends GutTest
## Issue #3 gates for the round loop: countdown -> play -> win/rematch/restart,
## pause, rails, timeout, bot-only termination, and 10 consecutive round-to-round
## transitions (the headless smoke requirement) at controller level.


func _solo(difficulty: int = 0, seed_value: int = 31337) -> RoundController:
	return RoundController.new(SeatRouting.make_solo_seats(difficulty, false), seed_value)


func _all_bots(difficulty: int = 0, seed_value: int = 31337) -> RoundController:
	var seats := SeatRouting.make_default_seats()
	for i in range(seats.size()):
		SeatRouting.set_bot(seats, i, difficulty)
	return RoundController.new(seats, seed_value)


func test_countdown_then_play_then_over() -> void:
	var controller := RoundController.new(
		SeatRouting.make_solo_seats(0, false), 31337)
	assert_eq(controller.state, RoundController.State.COUNTDOWN)
	assert_eq(controller.advance(0.1), 12, "advance converts frame time into fixed ticks")
	controller.run_to_end(RoundController.COUNTDOWN_SECONDS + 1.0)
	assert_eq(controller.state, RoundController.State.PLAYING, "countdown must end and serve")
	assert_false(controller.rules.ball_velocity.is_zero_approx(), "a live round has a moving ball")


func test_advance_is_ignored_while_paused() -> void:
	var controller := _solo()
	controller.set_paused(true)
	assert_eq(controller.advance(1.0), 0, "paused rounds must not simulate")
	assert_eq(controller.elapsed, 0.0)
	controller.set_paused(false)
	assert_gt(controller.advance(1.0), 0, "unpause resumes immediately")


func test_bot_only_round_terminates_and_rematch_loops_ten_rounds() -> void:
	var controller := _all_bots(2, 4242)
	for round_number in range(10):
		controller.run_to_end(200.0)
		assert_eq(controller.state, RoundController.State.ROUND_OVER,
			"round %d must reach an end state" % (round_number + 1))
		assert_true(controller.rules.over, "round %d rules must be over" % (round_number + 1))
		var result: Dictionary = controller.result
		assert_not_null(result.get("winner", null), "round %d must record a result" % (round_number + 1))
		controller.rematch()
		assert_eq(controller.state, RoundController.State.COUNTDOWN,
			"rematch %d returns to countdown" % (round_number + 1))
	assert_eq(controller.round_index, 10)


func test_restart_abandons_and_replays_immediately() -> void:
	var controller := _solo()
	controller.run_to_end(5.0)
	var frozen_position := controller.rules.ball_position
	controller.restart()
	assert_eq(controller.state, RoundController.State.COUNTDOWN)
	assert_ne(controller.round_index, 0)
	assert_ne(controller.rules.ball_position, frozen_position, "restart must reset the ball")
	assert_almost_eq(controller.timer, RoundController.COUNTDOWN_SECONDS, 0.0001)


func test_pause_mid_round_keeps_state_and_resumes() -> void:
	var controller := _solo()
	controller.run_to_end(3.0)
	controller.set_paused(true)
	var snapshot := controller.rules.ball_position
	assert_eq(controller.advance(2.0), 0)
	assert_eq(controller.rules.ball_position, snapshot, "pause freezes the ball")
	controller.set_paused(false)
	controller.advance(1.0)
	assert_ne(controller.rules.ball_position, snapshot, "resume continues the ball")


func test_round_over_ignores_pause() -> void:
	var controller := _all_bots(2, 77)
	controller.run_to_end(200.0)
	assert_eq(controller.state, RoundController.State.ROUND_OVER)
	controller.set_paused(true)
	assert_false(controller.paused, "pause is meaningless after the round ends")


func test_elimination_finish_is_recorded_without_the_clock() -> void:
	## Drive the last live opponent's core through the round controller, not
	## directly through MatchRules, and assert it records the decisive winner.
	var controller := _all_bots(2, 1337)
	controller.rules.keeps[0]["alive"] = false
	controller.rules.keeps[2]["alive"] = false
	controller.rules.keeps[3]["walls"] = [false, false, false]
	controller.state = RoundController.State.PLAYING
	var center: Vector2 = MatchRules.SEAT_POSITIONS[3]
	controller.rules.ball_position = center + Vector2(2.0, 0.0)
	controller.rules.ball_velocity = Vector2(-240.0, 0.0)
	controller.rules.set_shield_angle(3, PI)
	controller.targets[3] = PI
	controller.tick()
	assert_eq(controller.state, RoundController.State.ROUND_OVER)
	assert_false(controller.result["timed_out"], "an elimination must not be flagged as a timeout")
	assert_eq(controller.result["winner"], 1)
	assert_true(controller.result["stars"][1] >= 1, "the winner earns a star")


func test_difficulty_survives_the_controller_constructor() -> void:
	var controller := _all_bots(2, 5)
	for seat in range(4):
		assert_eq(controller.seats[seat]["difficulty"], 2)
	var solo := _solo(1, 5)
	for seat in range(4):
		if solo.seats[seat]["kind"] == "bot":
			assert_eq(solo.seats[seat]["difficulty"], 1)


func test_time_limit_declares_a_result() -> void:
	var controller := _solo()
	controller.time_limit = 2.0
	controller.run_to_end(10.0)
	assert_eq(controller.state, RoundController.State.ROUND_OVER, "timeout must end the round")
	assert_true(controller.result["timed_out"], "timeout must be recorded")


func test_ball_bounces_off_arena_rails() -> void:
	var controller := _solo()
	controller.run_to_end(0.3)
	controller.rules.ball_position = Vector2(RoundController.ARENA_HALF + 0.5, 3.0)
	controller.rules.ball_velocity = Vector2(20.0, 0.0)
	var rails_seen := 0
	for _i in range(5):
		for event in controller.rules.step(RoundController.TICK):
			if event["kind"] == "rail":
				rails_seen += 1
		controller._apply_rails()
		if controller.rules.ball_position.x < RoundController.ARENA_HALF:
			rails_seen += 1
			break
	assert_gt(controller.rules.ball_velocity.x * -1.0, 0.0, "rail hit must reverse outward velocity")
	assert_true(rails_seen > 0, "the ball must re-enter the arena after a rail hit")


func test_human_target_only_touches_that_seat() -> void:
	## set_target must write exactly one entry of the target array; other seats
	## keep whatever the bot brain last decided.
	var controller := _solo()
	var other_before: float = controller.targets[1]
	var third_before: float = controller.targets[3]
	controller.set_target(2, PI)
	assert_almost_eq(absf(controller.targets[2]), PI, 0.001, "wrapf normalizes PI to -PI")
	assert_eq(controller.targets[1], other_before, "a human target must not move another seat")
	assert_eq(controller.targets[3], third_before)
	controller.set_target(1, 0.5)
	assert_eq(controller.targets[1], other_before, "bot seats ignore human input")


func test_shield_speed_is_limited() -> void:
	var controller := _solo()
	var seat := 2
	controller.set_target(seat, PI)
	var before: float = controller.rules.keeps[seat]["shield_angle"]
	controller.tick()
	var moved := absf(angle_difference(before, controller.rules.keeps[seat]["shield_angle"]))
	assert_true(moved <= RoundController.SHIELD_MAX_SPEED * RoundController.TICK + 0.001,
		"shields must slew at a limited rate, moved=%f" % moved)
