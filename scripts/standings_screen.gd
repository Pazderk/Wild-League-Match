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
		lines.append("#%d %s (%d-%d)" % [i + 1, e.name, e.wins, SeasonManager.REGULAR_SEASON_GAMES - e.wins])
	return "\n".join(lines)


## A full league table: each team's own overall record this season (not
## your record against them), plus your own record, sorted by wins with
## RIVAL/PLAYOFFS tags — the Vipers always carry a qualifying record.
## While the regular season is still in progress, other teams' displayed
## records scale down to roughly match how many games you've played, so
## the table reads as in-progress rather than showing everyone else's
## fully decided season from game one. The PLAYOFFS/RIVAL tags always
## reflect each team's true final record, not the scaled snapshot, since
## "makes the playoffs" is a season-long outcome, not a moving target.
func _build_teams_text() -> String:
	var entries: Array = []
	for t in SeasonManager.teams:
		var full_record: Dictionary = SeasonManager.get_league_record(t.name)
		var shown: Dictionary = _scaled_record(full_record.wins)
		entries.append({
			"name": t.name, "wins": shown.wins, "losses": shown.losses,
			"final_wins": full_record.wins, "rival": t.rival,
		})
	entries.append({
		"name": "YOU", "wins": SeasonManager.regular_wins, "losses": SeasonManager.regular_losses,
		"final_wins": SeasonManager.regular_wins, "rival": false,
	})

	entries.sort_custom(func(a, b): return a.wins > b.wins)

	var lines: Array = ["LEAGUE STANDINGS"]
	for e in entries:
		var tags: Array = []
		if e.rival:
			tags.append("RIVAL")
		if e.final_wins >= SeasonManager.WINS_NEEDED_TO_QUALIFY:
			tags.append("PLAYOFFS")
		var tag_str := ("  (%s)" % ", ".join(tags)) if not tags.is_empty() else ""
		lines.append("%s: %d-%d%s" % [e.name, e.wins, e.losses, tag_str])
	return "\n".join(lines)


## Scales a team's full-season win total down to the number of games you've
## personally played so far, preserving their win rate. Once you've either
## finished the regular season or moved past it (playoffs or a terminal
## outcome), shows the true final record instead.
func _scaled_record(full_wins: int) -> Dictionary:
	var total_games: int = SeasonManager.REGULAR_SEASON_GAMES
	var played: int = SeasonManager.regular_games_played
	if SeasonManager.stage != "regular" or played >= total_games:
		return {"wins": full_wins, "losses": total_games - full_wins}
	var shown_wins: int = clamp(int(round(float(full_wins) / total_games * played)), 0, played)
	return {"wins": shown_wins, "losses": played - shown_wins}
