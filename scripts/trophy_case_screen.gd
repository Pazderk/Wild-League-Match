extends Node2D

@onready var stats_label: Label = $StatsLabel
@onready var achievements_list: RichTextLabel = $AchievementsList
@onready var back_button: Button = $BackButton


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	stats_label.text = _build_stats_text()
	achievements_list.text = _build_achievements_bbcode()


func _build_stats_text() -> String:
	var total_games := CareerManager.career_wins + CareerManager.career_losses
	var win_pct := 0.0
	if total_games > 0:
		win_pct = (float(CareerManager.career_wins) / float(total_games)) * 100.0
	var unlocked_count := CareerManager.unlocked_achievements.size()
	var total_count := CareerManager.ACHIEVEMENTS.size()
	return "Seasons Played: %d   Championships: %d\nRecord: %d-%d (%.0f%%)   Longest Win Streak: %d\nAchievements: %d / %d" % [
		CareerManager.seasons_played,
		CareerManager.championships_won,
		CareerManager.career_wins,
		CareerManager.career_losses,
		win_pct,
		CareerManager.longest_win_streak_ever,
		unlocked_count,
		total_count,
	]


func _build_achievements_bbcode() -> String:
	var lines: Array[String] = []
	for id in CareerManager.ACHIEVEMENTS.keys():
		var info: Dictionary = CareerManager.ACHIEVEMENTS[id]
		if CareerManager.is_unlocked(id):
			lines.append("[color=#FFD700]★ %s[/color]\n[color=#EAF5EA]%s[/color]" % [info["name"], info["description"]])
		else:
			lines.append("[color=#777777]☆ %s\n%s[/color]" % [info["name"], info["description"]])
	return "\n\n".join(lines)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
