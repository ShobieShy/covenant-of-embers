class_name PlayerTuning
extends Resource
## Movement/look numbers for scripts/player/player.gd (BUILD_PLAN step 3).
## Port of the archived C++ PlayerTuning + CharacterSettings (old step 14), which
## reinterpret Magewar's cogito_player scene overrides.

@export_group("Speeds")
@export var walk_speed := 4.0             ## Magewar WALKING_SPEED (player scene override)
@export var crouch_speed := 3.0           ## CROUCHING_SPEED
@export var lerp_speed := 10.0            ## LERP_SPEED: direction/speed/eye easing on the ground
@export var air_lerp_speed := 6.0         ## AIR_LERP_SPEED (air control only while a move key is held)
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
