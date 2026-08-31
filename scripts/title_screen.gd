extends Node2D

@onready var start_button: Button = $StartButton


func _ready() -> void:
	var fresh_season: bool = SeasonManager.stage == "regular" and SeasonManager.regular_games_played == 0
	start_button.text = "Start Season" if fresh_season else "Continue Season"
	start_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/board.tscn"))
