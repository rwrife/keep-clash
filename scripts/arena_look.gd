class_name ArenaLook
extends RefCounted
## Pure resource builders for the Forward+ arena and asset-free impact feedback.
## Headless tests inspect configuration, not rendered pixels or GPU performance.

const SEAT_COLORS: Array[Color] = [Color("e05c5c"), Color("e0b35c"), Color("5ce0a8"), Color("5c9be0")]
const GLOW_LEVELS: Array[float] = [0.0, 0.55, 0.8, 0.35, 0.15, 0.0, 0.0]
const IMPACT_MIX_RATE := 22050
const IMPACT_SECONDS := 0.12
const IMPACT_PARTICLE_AMOUNT := 28
const IMPACT_PARTICLE_LIFETIME := 0.4


static func build_environment() -> Environment:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("08131d")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("536b86")
	environment.ambient_light_energy = 0.55
	environment.glow_enabled = true
	environment.glow_intensity = 0.85
	environment.glow_bloom = 0.12
	environment.glow_hdr_threshold = 1.1
	for level in range(GLOW_LEVELS.size()):
		var weight: float = GLOW_LEVELS[level]
		environment.set_glow_level(level, weight)
	environment.sdfgi_enabled = true
	environment.sdfgi_read_sky_light = false
	environment.sdfgi_energy = 1.15
	environment.sdfgi_bounce_feedback = 0.35
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.0
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.0
	environment.adjustment_contrast = 1.08
	environment.adjustment_saturation = 1.05
	return environment


static func floor_material() -> StandardMaterial3D:
	return _material(Color("273848"), 0.18, 0.82, 0.35)


static func keep_material(seat: int) -> StandardMaterial3D:
	var tint: Color = SEAT_COLORS[seat]
	return _material(tint.darkened(0.18), 0.5, 0.32, 0.55)


static func wall_material() -> StandardMaterial3D:
	return _material(Color("91a5b8"), 0.65, 0.38, 0.5)


static func shield_material(seat: int) -> StandardMaterial3D:
	var tint: Color = SEAT_COLORS[seat]
	var material := _material(tint.lightened(0.12), 0.75, 0.24, 0.6)
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 1.6
	material.rim_enabled = true
	material.rim = 0.8
	material.rim_tint = 1.0
	return material


static func ball_material() -> StandardMaterial3D:
	var material := _material(Color("ffd27c"), 0.45, 0.22, 0.6)
	material.emission_enabled = true
	material.emission = Color("ffb347")
	material.emission_energy_multiplier = 2.5
	return material


static func impact_particles() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.emitting = false
	particles.amount = IMPACT_PARTICLE_AMOUNT
	particles.lifetime = IMPACT_PARTICLE_LIFETIME
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.randomness = 0.15
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 6, 8))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 80.0
	process.gravity = Vector3(0, -9.8, 0)
	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 5.0
	process.scale_min = 0.6
	process.scale_max = 1.4
	particles.process_material = process
	var spark := SphereMesh.new()
	spark.radius = 0.045
	spark.height = 0.09
	spark.radial_segments = 8
	spark.rings = 4
	var material := ball_material()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark.material = material
	particles.draw_pass_1 = spark
	return particles


static func impact_tone_db() -> float:
	return -14.0


static func impact_pcm(kind: String) -> AudioStreamWAV:
	## Mono signed 16-bit PCM, with silent endpoints and a short attack/release.
	assert(kind == "wall" or kind == "core", "Unknown impact kind: %s" % kind)
	var sample_count := int(IMPACT_MIX_RATE * IMPACT_SECONDS)
	var frequency := 110.0 if kind == "core" else 330.0
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for index in range(sample_count):
		var time := float(index) / IMPACT_MIX_RATE
		var attack := minf(1.0, float(index) / (IMPACT_MIX_RATE * 0.004))
		var release := minf(1.0, float(sample_count - 1 - index) / (IMPACT_MIX_RATE * 0.025))
		var envelope := attack * release * exp(-24.0 * time)
		var phase := TAU * frequency * (time - 0.3 * time * time / IMPACT_SECONDS)
		var sample := roundi(sin(phase) * envelope * 0.55 * 32767.0)
		data.encode_s16(index * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = IMPACT_MIX_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream


static func _material(color: Color, metallic: float, roughness: float, specular: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	material.metallic_specular = specular
	return material
