extends Resource

@export var joystick_deadzone := 0.10
@export var input_buffer := 0.15
@export var acceleration := 85.0
@export var braking := 140.0
@export var turn_response := 24.0
@export var reverse_acceleration := 180.0
@export var auto_attack_move_alignment := 0.25
@export var dodge_duration := 0.28
@export var dodge_distance := 3.0
@export var camera_response := 14.0
@export var camera_lookahead := 0.3
@export var level_camera_height := 9.5
@export var level_camera_fov := 35.0
@export var level_player_screen_y := 0.58
# Only these boss actions may steer after their warning appears (degrees/second).
@export var telegraph_tracking_actions: Dictionary = {
	"23001": {"attack4": 30.0},
	"53001": {"attack5": 25.0}
}
@export var hit_pause_min := 0.018
@export var hit_pause_max := 0.065
@export var shake_strength := 0.075
@export var effect_budget := 72
@export var low_effect_budget := 32
@export var particle_budget := 2048
@export var low_particle_budget := 768
@export var emitter_budget := 128
@export var low_emitter_budget := 48
@export var effect_template_budget := 128
@export var combat_prepare_usec := 2000
@export var audio_budget := 16
@export var skill_light_gain := 0.8
@export var sword_light_gain := 0.6
# Keep presentation overrides separate from the recovered effect catalog.
@export var effect_emitter_suppressions: Dictionary = {
	"24080201_fx_sword_satk_drawknife": ["24080201_drawknife_ring"],
	"24080201_fx_sword_satk_drawknifestrengthen": ["24080201_drawknifestrengthen_airwave"],
	"23102601_fx_wand_atk_move": ["23102601_move_ripple", "23102601_move_wave"],
	"23081901_fx_skill_firesword_niyanzhiren_accumulation": ["23081901_accumulation_floorglow"],
	"23081901_fx_skill_firesword_niyanzhiren_fireslash": [
		"23081901_fireslash_airwave", "23081901_fireslash_crack",
		"23081901_fireslash_crackdark", "23081901_fireslash_floorglow"
	]
}
@export var impact_enabled := true
@export var hit_stop_limit := 0.1
@export var hit_stop_interval := 0.12
@export var camera_impact_limit := 0.16
@export var player_stagger_limit := 0.08
@export var player_stagger_grace := 0.2
@export var impact_profiles: Dictionary = {
	"light": {"stop": 0.04, "shake": 0.08, "amplitude": 0.025, "distance": 0.15, "travel": 0.12, "stagger": 0.09, "flash": 0.045, "scale": 1.0, "gain": 0.85},
	"heavy": {"stop": 0.08, "shake": 0.16, "amplitude": 0.09, "distance": 0.75, "travel": 0.22, "stagger": 0.18, "flash": 0.075, "scale": 1.5, "gain": 1.0},
	"explosion": {"stop": 0.09, "shake": 0.22, "amplitude": 0.14, "distance": 1.2, "travel": 0.28, "stagger": 0.22, "flash": 0.08, "scale": 1.8, "gain": 1.0},
	"continuous": {"stop": 0.0, "shake": 0.0, "amplitude": 0.0, "distance": 0.0, "travel": 0.12, "stagger": 0.0, "flash": 0.025, "scale": 0.6, "gain": 0.35},
	"shield": {"stop": 0.02, "shake": 0.06, "amplitude": 0.015, "distance": 0.0, "travel": 0.12, "stagger": 0.0, "flash": 0.0, "scale": 0.85, "gain": 0.6}
}
@export var action_overrides: Dictionary = {
	"axe_atk1": {"category": "heavy"}, "axe_atk2": {"category": "heavy"},
	"axe_atk3": {"category": "heavy"}, "axe_satk_loop": {"category": "continuous"},
	"orb_satk_loop_1": {"category": "continuous", "distance": 0.08, "travel": 0.12},
	"skill_wand_jiliupao": {"category": "continuous"},
	"skill_bow_jianyu": {"category": "continuous"}
}
# Explicit impact payloads; ordinary water shots and persistent fields stay light.
@export var summon_overrides: Dictionary = {
	"4001021": {"category": "explosion"},
	"6000111": {"category": "explosion"}, "6000112": {"category": "explosion"},
	"6000113": {"category": "explosion"}, "25120901": {"category": "explosion"}
}
