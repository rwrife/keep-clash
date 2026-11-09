class_name MatchRules
extends RefCounted
## Pure match state. Coordinates are XY metres; one call to step() is one fixed tick.
## Call step(1.0 / 120.0) from the scene; do not pass variable frame delta.

const SEAT_POSITIONS := [Vector2(0, -12), Vector2(12, 0), Vector2(0, 12), Vector2(-12, 0)]
const SHIELD_RADIUS := 2.3
const WALL_RADIUS := 1.2
const CORE_RADIUS := 0.45
const SHIELD_HALF_ARC := PI / 4.0
const CONTACT_EPSILON := 0.0001
const MAX_IMPACTS := 32
const BUMP_WINDOW := 0.18
const BUMP_COOLDOWN := 1.2
const BOOST_SECONDS := 3.0
const BOOST_MULTIPLIER := 2.2
const MAX_BOOST_SPEED := 52.0
const MAX_NORMAL_SPEED := 26.0
const MAX_BALLS := 3
const SPLIT_SECONDS := 12.0
const SHRINK_SECONDS := 8.0
const SHRINK_SCALE := 0.55
const ITEM_RADIUS := 0.85
const ITEM_RESPAWN := 10.0

var keeps: Array[Dictionary] = []
var balls: Array[Dictionary] = [_new_ball(Vector2.ZERO, Vector2(0, -14))]
# Keep the single-ball interface for serves, existing tools and callers.
var ball_position: Vector2:
	get:
		return balls[0]["position"]
	set(value):
		balls[0]["position"] = value
var ball_velocity: Vector2:
	get:
		return balls[0]["velocity"]
	set(value):
		balls[0]["velocity"] = value
var items: Array[Dictionary] = []
var bump_windows: Array[float] = [0.0, 0.0, 0.0, 0.0]
var bump_cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var shrink_remaining := 0.0
var speed_gain := 1.0
var winner := -1
var over := false
var ticks := 0
var _rng := RandomNumberGenerator.new()
var arena_id := "courtyard"
var positions: Array
var serve_speed := 14.0


func _init(seed_value: int = 1, arena: String = "courtyard") -> void:
	assert(ArenaCatalog.ARENAS.has(arena))
	arena_id = arena
	positions = ArenaCatalog.ARENAS[arena]["positions"].duplicate()
	serve_speed = ArenaCatalog.ARENAS[arena]["speed"]
	_rng.seed = seed_value
	for i in range(4):
		var center: Vector2 = positions[i]
		keeps.append({"alive": true, "walls": [true, true, true],
			"shield_angle": (Vector2.ZERO - center).angle(), "deflections": 0})


func serve(angle: float) -> void:
	## The scene owns serve timing; the model only resets the ball onto a path.
	if over:
		return
	balls = [_new_ball(Vector2.ZERO, Vector2.RIGHT.rotated(angle) * serve_speed)]


static func _new_ball(position: Vector2, velocity: Vector2, life: float = -1.0) -> Dictionary:
	return {"position": position, "velocity": velocity, "boost": 0.0,
		"normal_speed": velocity.length(), "life": life, "last_seat": -1}


func enable_items() -> void:
	items = [
		{"kind": "split", "position": Vector2(-5, -3), "cooldown": 0.0},
		{"kind": "speed", "position": Vector2(5, -3), "cooldown": 0.0},
		{"kind": "shrink", "position": Vector2(0, 5), "cooldown": 0.0},
	]


func arm_bump(seat: int) -> bool:
	if over or seat < 0 or seat >= keeps.size() or not keeps[seat]["alive"] or bump_cooldowns[seat] > 0.0:
		return false
	bump_windows[seat] = BUMP_WINDOW
	bump_cooldowns[seat] = BUMP_COOLDOWN
	return true


func shield_half_arc() -> float:
	return SHIELD_HALF_ARC * (SHRINK_SCALE if shrink_remaining > 0.0 else 1.0)


func has_moving_ball() -> bool:
	return _moving_ball_count() > 0


func _moving_ball_count() -> int:
	var count := 0
	for ball in balls:
		if not Vector2(ball["velocity"]).is_zero_approx():
			count += 1
	return count


func stop_balls() -> void:
	for ball in balls:
		ball["velocity"] = Vector2.ZERO


func _boost(ball: Dictionary) -> void:
	if ball["boost"] <= 0.0:
		ball["normal_speed"] = minf(Vector2(ball["velocity"]).length(), MAX_NORMAL_SPEED)
	ball["boost"] = BOOST_SECONDS
	ball["velocity"] = Vector2(ball["velocity"]).normalized() * minf(ball["normal_speed"] * BOOST_MULTIPLIER, MAX_BOOST_SPEED)


func set_shield_angle(seat: int, angle: float) -> void:
	if seat >= 0 and seat < keeps.size() and keeps[seat]["alive"]:
		keeps[seat]["shield_angle"] = wrapf(angle, -PI, PI)


func bot_target(seat: int, difficulty: int) -> float:
	## 0 novice, 1 steady, 2 expert. Angle of the shield center on the arc around keep[seat].
	if seat < 0 or seat >= keeps.size() or difficulty < 0 or difficulty > 2:
		return 0.0
	var center: Vector2 = positions[seat]
	var lead: float = [0.0, 0.15, 0.35][difficulty]
	var jitter: float = [0.6, 0.22, 0.04][difficulty]
	var threat: Dictionary = balls[0]
	var nearest := INF
	for ball in balls:
		if Vector2(ball["velocity"]).is_zero_approx():
			continue
		var distance := Vector2(ball["position"]).distance_squared_to(center)
		if distance < nearest:
			nearest = distance
			threat = ball
	var predicted: Vector2 = threat["position"] + threat["velocity"] * lead
	return (predicted - center).angle() + _rng.randf_range(-jitter, jitter)


func step(dt: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if dt <= 0.0 or over:
		return events
	ticks += 1
	# Snapshot so newly split balls begin moving on the next fixed tick.
	for ball in balls.duplicate():
		if over:
			break
		if ball["boost"] > 0.0:
			ball["boost"] = maxf(0.0, ball["boost"] - dt)
			if ball["boost"] == 0.0:
				ball["velocity"] = Vector2(ball["velocity"]).normalized() * ball["normal_speed"]
		if ball["life"] >= 0.0:
			ball["life"] -= dt
			if ball["life"] <= 0.0 and _moving_ball_count() > 1:
				balls.erase(ball)
				continue
		events.append_array(_step_ball(ball, dt))
	for seat in range(4):
		bump_windows[seat] = maxf(0.0, bump_windows[seat] - dt)
		bump_cooldowns[seat] = maxf(0.0, bump_cooldowns[seat] - dt)
	shrink_remaining = maxf(0.0, shrink_remaining - dt)
	for item in items:
		item["cooldown"] = maxf(0.0, item["cooldown"] - dt)
	if balls.size() > 1:
		for index in range(balls.size() - 1, -1, -1):
			if balls.size() > 1 and Vector2(balls[index]["velocity"]).is_zero_approx():
				balls.remove_at(index)
	if balls.size() == 1:
		balls[0]["life"] = -1.0
	return events


func _step_ball(ball: Dictionary, dt: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var position: Vector2 = ball["position"]
	var velocity: Vector2 = ball["velocity"]
	if velocity.is_zero_approx():
		return events
	var remaining := dt
	for _impact in range(MAX_IMPACTS):
		if remaining <= 0.0:
			break
		var first := remaining + 1.0
		var hit_seat := -1
		var hit_kind := ""
		var hit_wall := -1
		var hit_item := -1
		for seat in range(keeps.size()):
			if not keeps[seat]["alive"]:
				continue
			var center: Vector2 = positions[seat]
			var shield_t := sweep_circle(position, velocity, remaining, center, SHIELD_RADIUS)
			if shield_t >= 0.0 and shield_t < first:
				var shield_angle := (position + velocity * shield_t - center).angle()
				if absf(angle_difference(shield_angle, keeps[seat]["shield_angle"])) <= shield_half_arc():
					first = shield_t
					hit_seat = seat
					hit_kind = "shield"
			var wall_t := sweep_circle(position, velocity, remaining, center, WALL_RADIUS)
			if wall_t >= 0.0 and wall_t < first:
				var wall_angle := (position + velocity * wall_t - center).angle()
				var sector := wall_sector(wall_angle)
				if keeps[seat]["walls"][sector]:
					first = wall_t
					hit_seat = seat
					hit_kind = "wall"
					hit_wall = sector
			var core_t := sweep_circle(position, velocity, remaining, center, CORE_RADIUS)
			if core_t >= 0.0 and core_t < first:
				first = core_t
				hit_seat = seat
				hit_kind = "core"
		for index in range(items.size()):
			if items[index]["cooldown"] > 0.0:
				continue
			var item_t := sweep_circle(position, velocity, remaining, items[index]["position"], ITEM_RADIUS)
			if item_t >= 0.0 and item_t < first:
				first = item_t
				hit_item = index
		if hit_item >= 0:
			position += velocity * first
			remaining -= first
			var item: Dictionary = items[hit_item]
			item["cooldown"] = ITEM_RESPAWN
			ball["velocity"] = velocity
			_apply_item(item, ball, position)
			velocity = ball["velocity"]
			events.append({"kind": "item", "seat": ball["last_seat"],
				"item": item["kind"], "position": position})
			continue
		if hit_seat < 0:
			position += velocity * remaining
			break
		position += velocity * first
		remaining -= first
		var center: Vector2 = positions[hit_seat]
		var normal: Vector2 = (position - center).normalized()
		if hit_kind == "shield":
			keeps[hit_seat]["deflections"] += 1
			ball["last_seat"] = hit_seat
		elif hit_kind == "wall":
			keeps[hit_seat]["walls"][hit_wall] = false
		else:
			keeps[hit_seat]["alive"] = false
		events.append({"kind": hit_kind, "seat": hit_seat, "wall": hit_wall, "position": position})
		if hit_kind == "core":
			var survivors: Array[int] = []
			for other in range(keeps.size()):
				if keeps[other]["alive"]:
					survivors.append(other)
			if survivors.size() <= 1:
				over = true
				winner = survivors[0] if survivors.size() == 1 else -1
				events.append({"kind": "win", "seat": winner})
			# Serve timing belongs to the round scene; the model just parks the ball.
			velocity = Vector2.ZERO
			remaining = 0.0
			if over:
				stop_balls()
		else:
			velocity = velocity.bounce(normal)
			if hit_kind == "shield":
				var normal_speed := minf((ball["normal_speed"] if ball["boost"] > 0.0 else velocity.length()) * speed_gain, MAX_NORMAL_SPEED)
				ball["normal_speed"] = normal_speed
				velocity = velocity.normalized() * (minf(normal_speed * BOOST_MULTIPLIER, MAX_BOOST_SPEED) if ball["boost"] > 0.0 else normal_speed)
				if bump_windows[hit_seat] > dt - remaining:
					bump_windows[hit_seat] = 0.0
					ball["velocity"] = velocity
					_boost(ball)
					velocity = ball["velocity"]
					events.append({"kind": "bump", "seat": hit_seat, "position": position})
			position += normal * CONTACT_EPSILON
	ball["position"] = position
	ball["velocity"] = velocity
	return events


func _apply_item(item: Dictionary, ball: Dictionary, position: Vector2) -> void:
	match item["kind"]:
		"speed":
			_boost(ball)
		"shrink":
			shrink_remaining = SHRINK_SECONDS
		"split":
			for angle in [-0.38, 0.38]:
				if balls.size() >= MAX_BALLS:
					break
				var copy := _new_ball(position, Vector2(ball["velocity"]).rotated(angle), SPLIT_SECONDS)
				copy["boost"] = ball["boost"]
				copy["normal_speed"] = ball["normal_speed"] if ball["boost"] > 0.0 else Vector2(ball["velocity"]).length()
				copy["last_seat"] = ball["last_seat"]
				balls.append(copy)


static func wall_sector(angle: float) -> int:
	return clampi(int(floor((wrapf(angle, -PI, PI) + PI) * 3.0 / TAU)), 0, 2)


static func sweep_circle(start: Vector2, velocity: Vector2, duration: float, center: Vector2, radius: float) -> float:
	## Analytic entry time, not an endpoint overlap: fast balls cannot tunnel.
	var relative := start - center
	var speed_squared := velocity.length_squared()
	if speed_squared <= 0.0 or relative.length_squared() <= radius * radius:
		return -1.0
	var toward := relative.dot(velocity)
	if toward >= 0.0:
		return -1.0
	var discriminant := toward * toward - speed_squared * (relative.length_squared() - radius * radius)
	if discriminant < 0.0:
		return -1.0
	var time := (-toward - sqrt(discriminant)) / speed_squared
	if time >= 0.0 and time <= duration:
		return time
	return -1.0


func stars_for(seat: int) -> int:
	if seat != winner or seat < 0 or seat >= keeps.size():
		return 0
	var stars := 1
	if keeps[seat]["walls"].count(true) == 3:
		stars += 1
	if keeps[seat]["deflections"] >= 3:
		stars += 1
	return stars
