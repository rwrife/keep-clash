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

var keeps: Array[Dictionary] = []
var ball_position := Vector2.ZERO
var ball_velocity := Vector2(0, -14)
var winner := -1
var over := false
var ticks := 0
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 1) -> void:
	_rng.seed = seed_value
	for i in range(4):
		var center: Vector2 = SEAT_POSITIONS[i]
		keeps.append({"alive": true, "walls": [true, true, true],
			"shield_angle": (Vector2.ZERO - center).angle(), "deflections": 0})


func serve(angle: float) -> void:
	## The scene owns serve timing; the model only resets the ball onto a path.
	if over:
		return
	ball_position = Vector2.ZERO
	ball_velocity = Vector2.RIGHT.rotated(angle) * 14.0


func set_shield_angle(seat: int, angle: float) -> void:
	if seat >= 0 and seat < keeps.size() and keeps[seat]["alive"]:
		keeps[seat]["shield_angle"] = wrapf(angle, -PI, PI)


func bot_target(seat: int, difficulty: int) -> float:
	## 0 novice, 1 steady, 2 expert. Angle of the shield center on the arc around keep[seat].
	if seat < 0 or seat >= keeps.size() or difficulty < 0 or difficulty > 2:
		return 0.0
	var center: Vector2 = SEAT_POSITIONS[seat]
	var lead: float = [0.0, 0.15, 0.35][difficulty]
	var jitter: float = [0.6, 0.22, 0.04][difficulty]
	var predicted := ball_position + ball_velocity * lead
	return (predicted - center).angle() + _rng.randf_range(-jitter, jitter)


func step(dt: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if dt <= 0.0 or over or ball_velocity.is_zero_approx():
		return events
	ticks += 1
	var remaining := dt
	for _impact in range(MAX_IMPACTS):
		if remaining <= 0.0:
			break
		var first := remaining + 1.0
		var hit_seat := -1
		var hit_kind := ""
		var hit_wall := -1
		for seat in range(keeps.size()):
			if not keeps[seat]["alive"]:
				continue
			var center: Vector2 = SEAT_POSITIONS[seat]
			var shield_t := sweep_circle(ball_position, ball_velocity, remaining, center, SHIELD_RADIUS)
			if shield_t >= 0.0 and shield_t < first:
				var shield_angle := (ball_position + ball_velocity * shield_t - center).angle()
				if absf(angle_difference(shield_angle, keeps[seat]["shield_angle"])) <= SHIELD_HALF_ARC:
					first = shield_t
					hit_seat = seat
					hit_kind = "shield"
			var wall_t := sweep_circle(ball_position, ball_velocity, remaining, center, WALL_RADIUS)
			if wall_t >= 0.0 and wall_t < first:
				var wall_angle := (ball_position + ball_velocity * wall_t - center).angle()
				var sector := wall_sector(wall_angle)
				if keeps[seat]["walls"][sector]:
					first = wall_t
					hit_seat = seat
					hit_kind = "wall"
					hit_wall = sector
			var core_t := sweep_circle(ball_position, ball_velocity, remaining, center, CORE_RADIUS)
			if core_t >= 0.0 and core_t < first:
				first = core_t
				hit_seat = seat
				hit_kind = "core"
		if hit_seat < 0:
			ball_position += ball_velocity * remaining
			break
		ball_position += ball_velocity * first
		remaining -= first
		var center: Vector2 = SEAT_POSITIONS[hit_seat]
		var normal: Vector2 = (ball_position - center).normalized()
		if hit_kind == "shield":
			keeps[hit_seat]["deflections"] += 1
		elif hit_kind == "wall":
			keeps[hit_seat]["walls"][hit_wall] = false
		else:
			keeps[hit_seat]["alive"] = false
		events.append({"kind": hit_kind, "seat": hit_seat, "wall": hit_wall})
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
			ball_velocity = Vector2.ZERO
			remaining = 0.0
		else:
			ball_velocity = ball_velocity.bounce(normal)
			ball_position += normal * CONTACT_EPSILON
	return events


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
