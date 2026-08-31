extends Node2D

@onready var start_button: Button = $StartButton
@onready var standings_button: Button = $StandingsButton
@onready var how_to_play_button: Button = $HowToPlayButton


func _ready() -> void:
	var fresh_season: bool = SeasonManager.stage == "regular" and SeasonManager.regular_games_played == 0
	start_button.text = "Start Season" if fresh_season else "Continue Season"
	start_button.pressed.connect(_on_start_pressed)
	standings_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/standings_screen.tscn"))
	how_to_play_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/tutorial_screen.tscn"))


func _on_start_pressed() -> void:
	if not SeasonManager.tutorial_seen:
		get_tree().change_scene_to_file("res://scenes/tutorial_screen.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/board.tscn")
