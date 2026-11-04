class_name ArenaCatalog
extends RefCounted

const IDS := ["courtyard", "diamond", "narrows"]
const SKINS := {
	"shield": {"classic": 0, "aurora": 3},
	"keep": {"classic": 0, "gilded": 6},
}
const ARENAS := {
	"courtyard": {"name": "Courtyard", "stars": 0, "description": "Classic cross; 90 second rounds.",
		"positions": [Vector2(0, -12), Vector2(12, 0), Vector2(0, 12), Vector2(-12, 0)],
		"bounds": Vector2(16, 16), "speed": 14.0, "gain": 1.05, "seconds": 90.0,
		"floor": Color("273848")},
	"diamond": {"name": "Diamond Rush", "stars": 3, "description": "Diagonal keeps; faster serves and acceleration; 75 seconds.",
		"positions": [Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)],
		"bounds": Vector2(16, 16), "speed": 16.0, "gain": 1.07, "seconds": 75.0,
		"floor": Color("392b49")},
	"narrows": {"name": "The Narrows", "stars": 8, "description": "Wide keeps, shallow rails; slower serves; 105 seconds.",
		"positions": [Vector2(0, -9), Vector2(12, 0), Vector2(0, 9), Vector2(-12, 0)],
		"bounds": Vector2(16, 12), "speed": 12.0, "gain": 1.03, "seconds": 105.0,
		"floor": Color("21423e")},
}


static func arena_unlocked(id: String, stars: int) -> bool:
	return ARENAS.has(id) and stars >= int(ARENAS[id]["stars"])


static func skin_unlocked(kind: String, id: String, stars: int) -> bool:
	return SKINS.has(kind) and SKINS[kind].has(id) and stars >= int(SKINS[kind][id])
