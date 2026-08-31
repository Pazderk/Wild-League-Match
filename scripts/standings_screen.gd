extends Node2D

@onready var status_label: Label = $StatusLabel
@onready var teams_label: Label = $TeamsLabel
@onready var back_button: Button = $BackButton


func _ready() -> void:
	status_label.text = _build_status_text()
	teams_label.text = _build_teams_text()
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/title_screen.tscn"))


func _build_status_text() -> String:
	match SeasonManager.stage:
		"regular":
			var next_team: String = SeasonManager.get_current_opponent().name
			return "Regular Season: Game %d of %d\nSeason Record: %d-%d\nNext: %s" % [
				SeasonManager.regular_games_played + 1, SeasonManager.REGULAR_SEASON_GAMES,
				SeasonManager.regular_wins, SeasonManager.regular_losses, next_team
			]
		"semifinal":
			return "SEMIFINAL vs %s\nSeries: You %d - %d" % [
				SeasonManager.SEMIFINAL_OPPONENT_NAME, SeasonManager.series_player_wins, SeasonManager.series_opponent_wins
			]
		"finals":
			return "FINALS vs %s\nSeries: You %d - %d" % [
				SeasonManager.RIVAL_NAME, SeasonManager.series_player_wins, SeasonManager.series_opponent_wins
			]
		"champion":
			return "SEASON COMPLETE\nYou're the Champion!"
		"eliminated_semis":
			return "SEASON COMPLETE\nEliminated in the Semifinals"
		"eliminated_finals":
			return "SEASON COMPLETE\nEliminated in the Finals"
		"missed_playoffs":
			return "SEASON COMPLETE\nMissed the playoffs at %d-%d" % [SeasonManager.regular_wins, SeasonManager.regular_losses]
		_:
			return ""


func _build_teams_text() -> String:
	var lines: Array = []
	for t in SeasonManager.teams:
		var record: Dictionary = SeasonManager.get_record(t.name)
		var marker := "  (RIVAL)" if t.rival else ""
		lines.append("%s: %d-%d%s" % [t.name, record.wins, record.losses, marker])
	return "\n".join(lines)
