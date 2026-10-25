class_name RoundController
extends RefCounted
## Round state machine on top of the pure MatchRules model: countdown, serving,
## bot decisions, shield motion limits, arena rails, speed escalation, time limit,
## pause and rematch. Node-free so the full round-to-round loop runs headless.
## The scene feeds real frame time via advance(); tests may call tick() directly.

signal event_emitted(event: Dictionary)
signal state_changed(new_state: int)

enum State { COUNTDOWN, PLAYING, ROUND_OVER }

const TICK := 1.0 / 120.0
const MAX_FRAME := 0.25
const COUNTDOWN_SECONDS := 1.5
const RESERVE_DELAY := 1.0
const ROUND_TIME_LIMIT := 90.0
const SHIELD_MAX_SPEED := 7.0
const BOT_SHIELD_SPEED: Array[float] = [1.6, 3.2, 6.0]
const BOT_BIAS_REROLL: Array[float] = [0.9, 0.2, 0.03]
const BOT_BIAS_RANGE := 1.0
const BOT_DECISION_TICKS := 6
const SPEED_GAIN := 1.05
const MAX_BALL_SPEED := 26.0
const ARENA_HALF := 16.0
## Tests may lower this to exercise the timeout path without simulating 90s.
var time_limit := ROUND_TIME_LIMIT
## Sign that makes "right"/"clockwise" input move each seat's shield toward
## screen-right (top/bottom seats) or screen-up (right seat) / screen-down
## (left seat) with the top-down camera used by the round scene.
const INPUT_SIGN: Array[float] = [-1.0, 1.0, 1.0, -1.0]

var rules: MatchRules
var seats: Array[Dictionary]
var seed_value := 1
var state: int = State.COUNTDOWN
var paused := false
var timer := 0.0
var elapsed := 0.0
var round_index := 0
var timed_out := false
var targets: Array[float] = [0.0, 0.0, 0.0, 0.0]
var result: Dictionary = {}

var _accum := 0.0
var _tick_count := 0
var _serve_rng := RandomNumberGenerator.new()
var _aim_rng := RandomNumberGenerator.new()
var _aim_bias: Array[float] = [0.0, 0.0, 0.0, 0.0]


func _init(seat_config: Array[Dictionary], seed_in: int = 1) -> void:
	seats = SeatRouting.duplicate_seats(seat_config)
	SeatRouting.fill_open_with_bots(seats, 0)
	seed_value = seed_in
	_start_round()


func _start_round() -> void:
	rules = MatchRules.new(seed_value + round_index)
	_serve_rng.seed = seed_value + round_index * 7919
	_aim_rng.seed = seed_value + round_index * 104729
	for i in range(4):
		_aim_bias[i] = 0.0
	for i in range(4):
		targets[i] = rules.keeps[i]["shield_angle"]
	timer = COUNTDOWN_SECONDS
	elapsed = 0.0
	timed_out = false
	result = {}
	_tick_count = 0
	paused = false
	_accum = 0.0
	_set_state(State.COUNTDOWN)


func restart() -> void:
	## Pause-menu restart: abandon the current round, replay with fresh seed.
	round_index += 1
	_start_round()


func rematch() -> void:
	round_index += 1
	_start_round()


func set_paused(value: bool) -> void:
	if state == State.ROUND_OVER:
		paused = false
		return
	paused = value


func advance(seconds: float) -> int:
	## Returns the number of fixed ticks executed.
	if paused or seconds <= 0.0:
		return 0
	_accum += minf(seconds, MAX_FRAME)
	var count := 0
	while _accum >= TICK:
		_accum -= TICK
		tick()
		count += 1
	return count


func set_target(seat: int, angle: float) -> void:
	if _human_alive(seat):
		targets[seat] = wrapf(angle, -PI, PI)


func nudge_target(seat: int, radians: float) -> void:
	if _human_alive(seat):
		targets[seat] = wrapf(targets[seat] + radians, -PI, PI)


func rotate_target(seat: int, direction: float, dt: float) -> void:
	if _human_alive(seat):
		targets[seat] = wrapf(targets[seat] + clampf(direction, -1.0, 1.0) * SHIELD_MAX_SPEED * dt, -PI, PI)


func tick() -> void:
	if state == State.ROUND_OVER or paused:
		return
	_tick_count += 1
	_run_bots()
	_move_shields()
	if state == State.COUNTDOWN:
		timer -= TICK
		if timer <= 0.0:
			_serve()
			_set_state(State.PLAYING)
		return
	if rules.ball_velocity.is_zero_approx():
		timer -= TICK
		if timer <= 0.0 and not rules.over:
			_serve()
	else:
		var events: Array[Dictionary] = rules.step(TICK)
		for event in events:
			if event["kind"] == "shield":
				var speed := minf(rules.ball_velocity.length() * SPEED_GAIN, MAX_BALL_SPEED)
				rules.ball_velocity = rules.ball_velocity.normalized() * speed
			elif event["kind"] == "core" and not rules.over:
				timer = RESERVE_DELAY
			event_emitted.emit(event)
		_apply_rails()
	elapsed += TICK
	if rules.over:
		_finish()
	elif elapsed >= time_limit:
		_time_out()


func run_to_end(max_seconds: float = 200.0) -> void:
	## Test/smoke helper: simulate until the round ends or max_seconds elapse.
	var ticks_left := int(max_seconds / TICK)
	while state != State.ROUND_OVER and ticks_left > 0:
		tick()
		ticks_left -= 1


func _human_alive(seat: int) -> bool:
	return seat >= 0 and seat < 4 and seats[seat]["kind"] == "human" and rules.keeps[seat]["alive"]


func _run_bots() -> void:
	if _tick_count % BOT_DECISION_TICKS != 0:
		return
	for seat in range(4):
		if seats[seat]["kind"] == "bot" and rules.keeps[seat]["alive"]:
			var difficulty: int = clampi(seats[seat]["difficulty"], 0, 2)
			# A re-rolled aim bias makes lower difficulties genuinely leaky:
			# without it a tracking bot covers every approach and walls never die.
			if _aim_rng.randf() < BOT_BIAS_REROLL[difficulty]:
				_aim_bias[seat] = _aim_rng.randf_range(-BOT_BIAS_RANGE, BOT_BIAS_RANGE)
			targets[seat] = wrapf(rules.bot_target(seat, difficulty) + _aim_bias[seat], -PI, PI)


func _move_shields() -> void:
	for seat in range(4):
		if not rules.keeps[seat]["alive"]:
			continue
		var current: float = rules.keeps[seat]["shield_angle"]
		var diff := angle_difference(current, targets[seat])
		var limit := _shield_speed(seat) * TICK
		rules.set_shield_angle(seat, current + clampf(diff, -limit, limit))


func _shield_speed(seat: int) -> float:
	## Humans get full speed; bots are slower on lower difficulties so a novice
	## bot can actually be beaten and rounds end by walls instead of the clock.
	if seats[seat]["kind"] == "bot":
		return BOT_SHIELD_SPEED[clampi(seats[seat]["difficulty"], 0, 2)]
	return SHIELD_MAX_SPEED


func _serve() -> void:
	rules.serve(_serve_rng.randf() * TAU)
	event_emitted.emit({"kind": "serve", "seat": -1})


func _apply_rails() -> void:
	var pos := rules.ball_position
	var vel := rules.ball_velocity
	var bounced := false
	if absf(pos.x) > ARENA_HALF:
		pos.x = signf(pos.x) * ARENA_HALF
		vel.x = -signf(pos.x) * absf(vel.x)
		bounced = true
	if absf(pos.y) > ARENA_HALF:
		pos.y = signf(pos.y) * ARENA_HALF
		vel.y = -signf(pos.y) * absf(vel.y)
		bounced = true
	if bounced:
		rules.ball_position = pos
		rules.ball_velocity = vel
		event_emitted.emit({"kind": "rail", "seat": -1})


func _time_out() -> void:
	timed_out = true
	var best := -1
	var best_key := -1
	var tie := false
	for seat in range(4):
		if not rules.keeps[seat]["alive"]:
			continue
		var walls: int = rules.keeps[seat]["walls"].count(true)
		var deflections: int = rules.keeps[seat]["deflections"]
		var key := walls * 1000 + deflections
		if key > best_key:
			best_key = key
			best = seat
			tie = false
		elif key == best_key:
			tie = true
	rules.over = true
	rules.winner = -1 if tie else best
	rules.ball_velocity = Vector2.ZERO
	_finish()


func _finish() -> void:
	if state == State.ROUND_OVER:
		return
	var stars: Array[int] = []
	for seat in range(4):
		stars.append(rules.stars_for(seat))
	result = {"winner": rules.winner, "stars": stars, "timed_out": timed_out, "elapsed": elapsed}
	paused = false
	_set_state(State.ROUND_OVER)
	event_emitted.emit({"kind": "round_over", "seat": rules.winner})


func _set_state(new_state: int) -> void:
	state = new_state
	state_changed.emit(new_state)
