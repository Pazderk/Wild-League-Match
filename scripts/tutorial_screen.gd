extends Node2D

@onready var back_button: Button = $BackButton
@onready var start_button: Button = $StartPlayingButton


func _ready() -> void:
	SeasonManager.mark_tutorial_seen()
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/title_screen.tscn"))
	start_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/board.tscn"))
