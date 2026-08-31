extends Node

## Autoload: survives scene reloads (the "Play Again" button just reloads
## board.tscn), so the season schedule and win/loss records persist across
## games within a session, and to disk across closing/reopening the app.
##
## 8 teams played in order, looping back to game 1 after the season ends.
## The Vipers are the rival: a notably higher score range than the rest.

const SAVE_PATH := "user://season_save.json"

var teams := [
	{"name": "Ironbark Bears", "min_score": 3500, "max_score": 4500, "rival": false},
	{"name": "Riverside Otters", "min_score": 3800, "max_score": 4800, "rival": false},
	{"name": "Copper Hawks", "min_score": 4000, "max_score": 5000, "rival": false},
	{"name": "Frostpaw Wolves", "min_score": 4200, "max_score": 5200, "rival": false},
	{"name": "Sundown Foxes", "min_score": 4400, "max_score": 5400, "rival": false},
	{"name": "Highland Owls", "min_score": 4600, "max_score": 5600, "rival": false},
	{"name": "Summit Eagles", "min_score": 4800, "max_score": 6000, "rival": false},
	{"name": "Vipers", "min_score": 7000, "max_score": 9000, "rival": true},
]

var records := {} # team_name -> {"wins": int, "losses": int}
var current_team_index := 0


func _ready() -> void:
	_load()


func get_current_team() -> Dictionary:
	return teams[current_team_index]


func roll_target_score() -> int:
	var team := get_current_team()
	return randi_range(team.min_score, team.max_score)


func report_result(did_win: bool) -> void:
	var team := get_current_team()
	if not records.has(team.name):
		records[team.name] = {"wins": 0, "losses": 0}
	if did_win:
		records[team.name].wins += 1
	else:
		records[team.name].losses += 1
	current_team_index = (current_team_index + 1) % teams.size()
	_save()


func get_record(team_name: String) -> Dictionary:
	return records.get(team_name, {"wins": 0, "losses": 0})


func get_season_totals() -> Dictionary:
	var wins := 0
	var losses := 0
	for r in records.values():
		wins += r.wins
		losses += r.losses
	return {"wins": wins, "losses": losses}


func _save() -> void:
	var data := {"current_team_index": current_team_index, "records": records}
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
