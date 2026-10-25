extends "res://scripts/presentation/player_lifecycle.gd"

const HEIGHT := 3.8
var arriving := false

func begin(actor: DungeonActor, arrival: bool, media: Dictionary, textures: Dictionary, low_quality := false) -> bool:
	if active or not is_instance_valid(actor) or actor.dead: return false
	arriving = arrival
	return begin_action(actor, "enterroom" if arrival else "leftroom", media, textures, low_quality)

func _apply_motion() -> void:
	var offset := 0.0
	if arriving:
		var fall := clampf((elapsed - 0.167) / 0.5, 0.0, 1.0)
		offset = HEIGHT * (1.0 - fall * fall)
		if elapsed > 0.667:
			var settle := clampf((elapsed - 0.667) / 0.333, 0.0, 1.0)
			offset = sin(settle * PI) * 0.12 * (1.0 - settle)
	else:
		# The source hides the model at .33 seconds; finish the visible rise before it.
		var rise := clampf(elapsed / 0.33, 0.0, 1.0)
		offset = HEIGHT * rise * rise
	_actor.visual.position = _visual_transform.origin + Vector3.UP * offset
	super._apply_motion()
