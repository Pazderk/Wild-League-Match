extends Node2D

## Themed suggestions for the "🎲" button — same naming style as the league
## roster (place name + animal), so a randomized name still fits the world.
const NAME_SUGGESTIONS := [
	"Stonecrest Falcons", "Duskwood Badgers", "Emberfield Lynxes",
	"Frostpine Elk", "Cinderpath Ravens", "Thistledown Hares",
	"Saltmarsh Herons", "Brackenridge Boars", "Windmere Stallions",
	"Copperfen Jackals", "Mosswick Panthers", "Hollowgate Bison",
]

@onready var start_button: Button = $StartButton
@onready var standings_button: Button = $StandingsButton
@onready var how_to_play_button: Button = $HowToPlayButton
@onready var restart_button: Button = $RestartSeasonButton
@onready var team_name_edit: LineEdit = $TeamNameEdit
@onready var randomize_button: Button = $RandomizeButton
@onready var restart_overlay: Control = $RestartConfirmOverlay
@onready var restart_yes_button: Button = $RestartConfirmOverlay/RestartYesButton
@onready var restart_no_button: Button = $RestartConfirmOverlay/RestartNoButton
@onready var difficulty_buttons := {
	"rookie": $RookieButton,
	"pro": $ProButton,
	"all_star": $AllStarButton,
	"hall_of_fame": $HallOfFameButton,
}

var fresh_season := false
var selected_difficulty := "pro"


func _ready() -> void:
	fresh_season = SeasonManager.stage == "regular" and SeasonManager.regular_games_played == 0
	start_button.text = "Start Season" if fresh_season else "Continue Season"
	start_button.pressed.connect(_on_start_pressed)
	standings_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/standings_screen.tscn"))
	how_to_play_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/tutorial_screen.tscn"))

	team_name_edit.text = "" if SeasonManager.team_name == "YOU" else SeasonManager.team_name
	randomize_button.pressed.connect(func(): team_name_edit.text = NAME_SUGGESTIONS[randi() % NAME_SUGGESTIONS.size()])

	# Locked in for a season already in progress — shown (highlighted) but
	# not changeable until it ends or is restarted. A fresh season starts
	# from whatever was last chosen, for convenience.
	selected_difficulty = SeasonManager.difficulty if not fresh_season else SeasonManager.preferred_difficulty
	for kind in difficulty_buttons:
		var button: Button = difficulty_buttons[kind]
		button.disabled = not fresh_season
		button.pressed.connect(func(): _on_difficulty_pressed(kind))
	_update_difficulty_buttons()

	restart_overlay.visible = false
	restart_button.visible = not fresh_season
	restart_button.pressed.connect(func(): restart_overlay.visible = true)
	restart_yes_button.pressed.connect(_on_restart_confirmed)
	restart_no_button.pressed.connect(func(): restart_overlay.visible = false)


func _on_difficulty_pressed(kind: String) -> void:
	selected_difficulty = kind
	_update_difficulty_buttons()


func _update_difficulty_buttons() -> void:
	for kind in difficulty_buttons:
		var button: Button = difficulty_buttons[kind]
		button.modulate = Color(1, 0.85, 0.2, 1) if kind == selected_difficulty else Color(1, 1, 1, 1)


func _on_restart_confirmed() -> void:
	SeasonManager.reset_season(selected_difficulty)
	restart_overlay.visible = false
	restart_button.visible = false
	start_button.text = "Start Season"
	fresh_season = true
	for kind in difficulty_buttons:
		difficulty_buttons[kind].disabled = false


func _on_start_pressed() -> void:
	SeasonManager.set_team_name(team_name_edit.text)
	if fresh_season:
		SeasonManager.set_preferred_difficulty(selected_difficulty)
		SeasonManager.reset_season(selected_difficulty)
	if not SeasonManager.tutorial_seen:
		get_tree().change_scene_to_file("res://scenes/tutorial_screen.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/board.tscn")
