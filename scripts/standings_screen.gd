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
			return "SEMIFINAL vs %s\nSeries: You %d - %d\n\n%s" % [
				SeasonManager.semifinal_opponent_name, SeasonManager.series_player_wins,
				SeasonManager.series_opponent_wins, _build_bracket_text()
			]
		"finals":
			return "FINALS vs %s\nSeries: You %d - %d\n\n%s" % [
				SeasonManager.finals_opponent_name, SeasonManager.series_player_wins,
				SeasonManager.series_opponent_wins, _build_bracket_text()
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


func _build_bracket_text() -> String:
	if SeasonManager.bracket_seeds.is_empty():
		return ""
	var lines: Array = ["BRACKET"]
	for i in range(SeasonManager.bracket_seeds.size()):
		var e: Dictionary = SeasonManager.bracket_seeds[i]
		lines.append("#%d %s (%d-%d)" % [i + 1, e.name, e.wins, e.losses])
	return "\n".join(lines)


## A full league table: each team's own overall record this season (not
## your record against them), plus your own record, sorted by wins — all
## genuinely live, since the other teams' records now evolve incrementally
## week by week right alongside yours, rather than being a fixed season
## rolled up front. RIVAL/PLAYOFFS tags reflect the current standings: the
## Vipers are tagged RIVAL, and the current top 4 of the 8 teams are tagged
## PLAYOFFS (a moving target until the season is over).
func _build_teams_text() -> String:
	var entries: Array = SeasonManager.compute_standings()

	var lines: Array = ["LEAGUE STANDINGS"]
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var tags: Array = []
		if e.rival:
			tags.append("RIVAL")
		if i < 4:
			tags.append("PLAYOFFS")
		var tag_str := ("  (%s)" % ", ".join(tags)) if not tags.is_empty() else ""
		lines.append("%d. %s: %d-%d%s" % [i + 1, e.name, e.wins, e.losses, tag_str])
	return "\n".join(lines)
