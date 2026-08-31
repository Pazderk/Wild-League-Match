extends Node

## Autoload: survives scene reloads (the "Play Again" button just reloads
## board.tscn), so season/playoff progress persists across games within a
## session, and to disk across closing/reopening the app.
##
## Regular season: 8 teams played in order. 5+/8 wins qualifies for the
## playoffs; the moment a losing record becomes mathematical (more than 3
## losses), the season is over right there rather than playing out games
## that no longer matter.
##
## Playoffs: a best-of-3 Semifinal vs the toughest non-rival team, then a
## best-of-5 Finals vs the Blackthorn Vipers (rival) — guaranteed, not simulated, since
## a real showdown with the rival is the point. No actual 4-team bracket is
## simulated; the "other" semifinal is just flavor text once you reach the
## Finals. Nothing carries over between seasons yet — a new season is a
## full reset.

const SAVE_PATH := "user://season_save.json"
const PREFS_PATH := "user://prefs.json"

const REGULAR_SEASON_GAMES := 8
const WINS_NEEDED_TO_QUALIFY := 5
const SEMIFINAL_OPPONENT_NAME := "Summit Rams"
const RIVAL_NAME := "Blackthorn Vipers"
const SEMIFINAL_WINS_NEEDED := 2 # best of 3
const FINALS_WINS_NEEDED := 3 # best of 5
const PLAYOFF_SCORE_BOOST := 1.18 # tougher score ranges once the postseason starts

var teams := [
	{"name": "Ironbark Bears", "min_score": 3500, "max_score": 4500, "rival": false},
	{"name": "Riverside Otters", "min_score": 3800, "max_score": 4800, "rival": false},
	{"name": "Copper City Hawks", "min_score": 4000, "max_score": 5000, "rival": false},
	{"name": "Graymoor Wolves", "min_score": 4200, "max_score": 5200, "rival": false},
	{"name": "Redbrush Foxes", "min_score": 4400, "max_score": 5400, "rival": false},
	{"name": "Highland Owls", "min_score": 4600, "max_score": 5600, "rival": false},
	{"name": "Summit Rams", "min_score": 4800, "max_score": 6000, "rival": false},
	{"name": RIVAL_NAME, "min_score": 7000, "max_score": 9000, "rival": true},
]

var records := {} # team_name -> {"wins": int, "losses": int}; regular season only
var current_team_index := 0
var regular_games_played := 0
var regular_wins := 0
var regular_losses := 0

# "regular", "semifinal", "finals", "champion", "eliminated_semis",
# "eliminated_finals", "missed_playoffs"
var stage := "regular"
var series_player_wins := 0
var series_opponent_wins := 0
var other_semifinal_result := ""

# Kept in a separate small file from season_save.json since it's a one-time
# preference, not season progress — reset_season() must never touch it.
var tutorial_seen := false


func _ready() -> void:
	_load()
	_load_prefs()


func mark_tutorial_seen() -> void:
	tutorial_seen = true
	_save_prefs()


func _save_prefs() -> void:
	var f := FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"tutorial_seen": tutorial_seen}))
		f.close()


func _load_prefs() -> void:
	if not FileAccess.file_exists(PREFS_PATH):
		return
	var f := FileAccess.open(PREFS_PATH, FileAccess.READ)
	if not f:
		return
	var text := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	tutorial_seen = parsed.get("tutorial_seen", false)


func is_playoff_stage() -> bool:
	return stage == "semifinal" or stage == "finals"


func is_season_over() -> bool:
	return stage in ["champion", "eliminated_semis", "eliminated_finals", "missed_playoffs"]


func get_current_team() -> Dictionary:
	return teams[current_team_index]


## The opponent for whatever stage the season is currently in.
func get_current_opponent() -> Dictionary:
	match stage:
		"semifinal":
			return _find_team(SEMIFINAL_OPPONENT_NAME)
		"finals":
			return _find_team(RIVAL_NAME)
		_:
			return get_current_team()


func _find_team(team_name: String) -> Dictionary:
	for t in teams:
		if t.name == team_name:
			return t
	return teams[0]


func roll_target_score() -> int:
	var team := get_current_opponent()
	var lo: int = team.min_score
	var hi: int = team.max_score
	if is_playoff_stage():
		lo = int(lo * PLAYOFF_SCORE_BOOST)
		hi = int(hi * PLAYOFF_SCORE_BOOST)
	return randi_range(lo, hi)


func report_result(did_win: bool) -> void:
	match stage:
		"regular":
			_report_regular_result(did_win)
		"semifinal":
			_report_series_result(did_win, SEMIFINAL_WINS_NEEDED, "finals", "eliminated_semis")
			if stage == "finals":
				_roll_other_semifinal_flavor()
		"finals":
			_report_series_result(did_win, FINALS_WINS_NEEDED, "champion", "eliminated_finals")
	_save()


func _report_regular_result(did_win: bool) -> void:
	var team := get_current_team()
	if not records.has(team.name):
		records[team.name] = {"wins": 0, "losses": 0}
	if did_win:
		records[team.name].wins += 1
		regular_wins += 1
	else:
		records[team.name].losses += 1
		regular_losses += 1
	regular_games_played += 1
	current_team_index = (current_team_index + 1) % teams.size()

	# Qualify (or get eliminated) the instant it's mathematically decided,
	# rather than playing out remaining regular-season games that no longer
	# change anything.
	if regular_wins >= WINS_NEEDED_TO_QUALIFY:
		stage = "semifinal"
	elif regular_losses > REGULAR_SEASON_GAMES - WINS_NEEDED_TO_QUALIFY:
		stage = "missed_playoffs"


func _report_series_result(did_win: bool, wins_needed: int, advance_stage: String, eliminate_stage: String) -> void:
	if did_win:
		series_player_wins += 1
	else:
		series_opponent_wins += 1

	if series_player_wins >= wins_needed:
		stage = advance_stage
		# Only reset for a series that's actually about to start (Semifinal ->
		# Finals) — advancing to "champion" is terminal, so the final series
		# score stays intact for the champion screen to display.
		if advance_stage != "champion":
			series_player_wins = 0
			series_opponent_wins = 0
	elif series_opponent_wins >= wins_needed:
		stage = eliminate_stage


func _roll_other_semifinal_flavor() -> void:
	var candidates := []
	for t in teams:
		if t.name != SEMIFINAL_OPPONENT_NAME and t.name != RIVAL_NAME:
			candidates.append(t.name)
	var loser: String = candidates[randi() % candidates.size()]
	var series_scores := ["2-0", "2-1"]
	other_semifinal_result = "In the other semifinal, the %s defeated the %s %s." % [
		RIVAL_NAME, loser, series_scores[randi() % series_scores.size()]
	]


func get_record(team_name: String) -> Dictionary:
	return records.get(team_name, {"wins": 0, "losses": 0})


func get_season_totals() -> Dictionary:
	var wins := 0
	var losses := 0
	for r in records.values():
		wins += r.wins
		losses += r.losses
	return {"wins": wins, "losses": losses}


func reset_season() -> void:
	records = {}
	current_team_index = 0
	regular_games_played = 0
	regular_wins = 0
	regular_losses = 0
	stage = "regular"
	series_player_wins = 0
	series_opponent_wins = 0
	other_semifinal_result = ""
	_save()


func _save() -> void:
	var data := {
		"current_team_index": current_team_index,
		"records": records,
		"regular_games_played": regular_games_played,
		"regular_wins": regular_wins,
		"regular_losses": regular_losses,
		"stage": stage,
		"series_player_wins": series_player_wins,
		"series_opponent_wins": series_opponent_wins,
		"other_semifinal_result": other_semifinal_result,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var text := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	current_team_index = parsed.get("current_team_index", 0)
	records = parsed.get("records", {})
	regular_games_played = parsed.get("regular_games_played", 0)
	regular_wins = parsed.get("regular_wins", 0)
	regular_losses = parsed.get("regular_losses", 0)
	stage = parsed.get("stage", "regular")
	series_player_wins = parsed.get("series_player_wins", 0)
	series_opponent_wins = parsed.get("series_opponent_wins", 0)
	other_semifinal_result = parsed.get("other_semifinal_result", "")

	# A terminal stage is saved the instant it's computed, not when the
	# player clicks "New Season" — if the app closed before that click, the
	# season is still genuinely over, so start fresh rather than loading
	# back into a dead stage no result screen will ever show again.
	if is_season_over():
		reset_season()
