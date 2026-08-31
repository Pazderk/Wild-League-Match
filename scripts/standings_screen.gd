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


## A full league table: each team's own overall record this season (not
## your record against them), plus your own record, sorted by wins with
## RIVAL/PLAYOFFS tags — the Vipers always carry a qualifying record.
func _build_teams_text() -> String:
	var entries: Array = []
	for t in SeasonManager.teams:
		var record: Dictionary = SeasonManager.get_league_record(t.name)
		entries.append({"name": t.name, "wins": record.wins, "losses": record.losses, "rival": t.rival})
	entries.append({
		"name": "YOU", "wins": SeasonManager.regular_wins, "losses": SeasonManager.regular_losses, "rival": false
	})

	entries.sort_custom(func(a, b): return a.wins > b.wins)

	var lines: Array = ["LEAGUE STANDINGS"]
	for e in entries:
		var tags: Array = []
		if e.rival:
			tags.append("RIVAL")
		if e.wins >= SeasonManager.WINS_NEEDED_TO_QUALIFY:
			tags.append("PLAYOFFS")
		var tag_str := ("  (%s)" % ", ".join(tags)) if not tags.is_empty() else ""
		lines.append("%s: %d-%d%s" % [e.name, e.wins, e.losses, tag_str])
	return "\n".join(lines)
