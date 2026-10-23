class_name PlayerTuning
extends Resource
## Movement/look numbers for scripts/player/player.gd (BUILD_PLAN steps 3-5, mana step 8).
## Port of the archived C++ PlayerTuning + CharacterSettings (old step 14), which
## reinterpret Magewar's cogito_player scene overrides.

@export_group("Speeds")
@export var walk_speed := 4.0             ## Magewar WALKING_SPEED (player scene override)
@export var crouch_speed := 3.0           ## CROUCHING_SPEED
@export var sprint_speed := 7.0           ## SPRINTING_SPEED (cogito_player.tscn override; script 8)
@export var lerp_speed := 10.0            ## LERP_SPEED: direction/speed/eye easing on the ground
@export var air_lerp_speed := 6.0         ## AIR_LERP_SPEED (air control only while a move key is held)
@export_group("Slide")
@export var slide_speed := 5.0            ## SLIDING_SPEED: speed = (time_left / duration + 0.5) x 5
@export var slide_duration := 1.5         ## SlidingTimer wait_time
@export var slide_jump_mod := 1.3         ## SLIDE_JUMP_MOD (tscn override; script 1.5)
@export_group("Breath")
@export var breath_max := 100.0           ## PLAN §30.8 (kept decision; Magewar stamina 30)
@export var breath_drain_per_sec := 20.0  ## while sprinting (Magewar 3/s)
@export var breath_regen_per_sec := 30.0  ## (Magewar 2/s)
@export var breath_regen_delay := 1.0     ## s since the last drain/spend (Magewar 2 s)
@export var breath_resume_at := 20.0      ## an emptied pool allows sprint again at 20
@export_group("Mana")
@export var mana_max := 100.0             ## PLAN §30.1 = Magewar ManaAttribute value_max
@export var mana_regen_per_sec := 3.0     ## Magewar mana_regen_speed
@export var mana_regen_delay := 1.5       ## Magewar regen_delay: s since the last cast
@export var mana_auto_regenerate := true  ## Magewar auto_regenerate
@export_group("Dash")
@export var dash_distance := 6.0          ## m (PLAN §30.8; Magewar has no dash: our own verb)
@export var dash_duration := 0.15         ## s (speed 40 m/s)
@export var dash_charges := 2
@export var dash_breath_cost := 25.0
@export var dash_invulnerability := 0.1   ## i-frames from the dash start, s
@export var dash_recharge := 1.5          ## per charge, one at a time (build step 16 choice)
@export var dash_air_dashes := 1          ## per airborne stretch
@export_group("Camera feel")
@export var bob_walk_intensity := 0.03    ## Cogito WIGGLE_ON_WALKING_INTENSITY (m)
@export var bob_walk_rate := 12.0         ## WIGGLE_ON_WALKING_SPEED (rad/s)
@export var bob_sprint_intensity := 0.05  ## WIGGLE_ON_SPRINTING_*
@export var bob_sprint_rate := 16.0
@export var bob_crouch_intensity := 0.08  ## WIGGLE_ON_CROUCHING_*
@export var bob_crouch_rate := 8.0
@export var land_min_speed := 2.0         ## Cogito landing_threshold / min_landing_velocity (m/s)
@export var land_max_speed := 8.0         ## max_landing_velocity
@export var land_max_dip := 0.12          ## m at land_max_speed
@export var land_dip_down_time := 0.1     ## "landing" animation keys (s)
@export var land_dip_total_time := 0.3
@export var step_camera_lerp := 2.5       ## Cogito step_height_camera_lerp (1/s)
@export_group("Jump")
@export var jump_velocity := 4.5          ## JUMP_VELOCITY
@export var crouch_jump_velocity := 3.0   ## CROUCH_JUMP_VELOCITY
@export var gravity := 9.8                ## m/s^2
@export_group("Body")
@export var radius := 0.3                 ## capsule radius (Magewar collider 0.6 m wide)
@export var standing_height := 1.7        ## feet to top of head
@export var crouching_height := 0.7       ## Magewar crouch collider
@export var standing_eye := 1.5           ## body origin 0.8 + Neck 0.7
@export var crouching_eye := 0.6          ## + CROUCHING_DEPTH -0.9
@export var step_height := 0.35           ## Magewar STEP_HEIGHT (scene override)
@export var floor_snap := 0.5             ## max snap down off steps / down slopes
@export var max_slope_deg := 45.0         ## CharacterBody3D floor_max_angle
@export_group("Look")
@export var look_deg_per_count := 0.25    ## Magewar MOUSE_SENS
@export var max_pitch_deg := 89.0
