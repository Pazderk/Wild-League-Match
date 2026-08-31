extends Node

## Autoload: survives scene reloads (the "Play Again" button just reloads
## board.tscn), so season/playoff progress persists across games within a
## session, and to disk across closing/reopening the app.
##
## Regular season: 8 teams played in order, 5+/8 wins needed to qualify.
## Elimination (more than 3 losses, mathematically hopeless) ends the season
## immediately — but qualifying does not, since your final win total (up to
## all 8 games) determines your playoff seed, so games after your 5th win
## still matter.
##
## Playoffs: a real seeded 4-team bracket. The player + the top 3 of the
## other 7 teams (by their own rolled season record) are seeded 1-4 by
## wins; the Vipers are always the best of those other 3. Semifinal is
## seed 1 vs 4 and 2 vs 3 — the player plays whichever pairing they're
## seeded into, so the Vipers could be a Semifinal opponent, not always
## the Finals. The "other" semifinal (the pairing without the player) is
## simulated once, favoring the higher seed but not certain, and its
## winner becomes the player's actual Finals opponent. Nothing carries
## over between seasons yet — a new season is a full reset.

const SAVE_PATH := "user://season_save.json"
const PREFS_PATH := "user://prefs.json"

const REGULAR_SEASON_GAMES := 8
const WINS_NEEDED_TO_QUALIFY := 5
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
# Each of the 8 teams' own overall record for the season (not the player's
# record against them) — rolled once at the start of the season and fixed
# for its duration. The Vipers always roll (and are guaranteed to keep) the
# single best record among the other 7 teams, so they're always a top seed.
var league_records := {} # team_name -> {"wins": int, "losses": int}
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

# Set once by _setup_playoff_bracket() the moment the player qualifies.
# bracket_seeds[0] is the #1 seed (most wins) through [3] the #4 seed.
var bracket_seeds := [] # [{"name": String, "wins": int}, ...] size 4
var player_seed_index := -1
var semifinal_opponent_name := ""
var finals_opponent_name := ""

# Kept in a separate small file from season_save.json since it's a one-time
# preference, not season progress — reset_season() must never touch it.
var tutorial_seen := false


func _ready() -> void:
	_load()
	_load_prefs()
	if league_records.is_empty():
		_roll_league_records()


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


## The opponent for whatever stage the season is currently in. Semifinal
## and Finals opponents are whichever teams the seeded bracket produced,
## not fixed identities.
func get_current_opponent() -> Dictionary:
	match stage:
		"semifinal":
			return _find_team(semifinal_opponent_name)
		"finals":
			return _find_team(finals_opponent_name)
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

	# Elimination still ends the season immediately once it's mathematically
	# hopeless — no number of remaining wins could reach 5. But qualifying no
	# longer ends it early: with a real seeded bracket, your final win total
	# (up to all 8 games) decides your seed, so games after your 5th win are
	# no longer meaningless — winning more of them earns a better matchup
	# instead of getting bumped into a worse one.
	if regular_losses > REGULAR_SEASON_GAMES - WINS_NEEDED_TO_QUALIFY:
		stage = "missed_playoffs"
	elif regular_games_played >= REGULAR_SEASON_GAMES:
		if regular_wins >= WINS_NEEDED_TO_QUALIFY:
			_setup_playoff_bracket()
			stage = "semifinal"
		else:
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


## Seeds the 4-team bracket the instant the player qualifies: the player +
## the top 3 of the other 7 teams by their rolled season record. Seed 1
## plays seed 4, seed 2 plays seed 3 — whichever pairing includes the
## player determines their real Semifinal opponent (which may be the
## Vipers). The other pairing is simulated immediately so its winner is
## ready to serve as the player's Finals opponent in advance.
func _setup_playoff_bracket() -> void:
	var others: Array = []
	for t in teams:
		var r: Dictionary = get_league_record(t.name)
		others.append({"name": t.name, "wins": r.wins})
	others.sort_custom(_compare_seed_entries)

	var entrants: Array = others.slice(0, 3)
	entrants.append({"name": "YOU", "wins": regular_wins})
	entrants.sort_custom(_compare_seed_entries)

	bracket_seeds = entrants
	player_seed_index = 0
	for i in range(entrants.size()):
		if entrants[i].name == "YOU":
			player_seed_index = i
			break

	var opponent_index: int = 3 - player_seed_index # seed1<->seed4 (0,3), seed2<->seed3 (1,2)
	semifinal_opponent_name = entrants[opponent_index].name

	var other_indices: Array = []
	for i in range(4):
		if i != player_seed_index and i != opponent_index:
			other_indices.append(i)
	_simulate_other_semifinal(entrants[other_indices[0]], entrants[other_indices[1]])


## Vipers break ties in their own favor so they're always the single best
## non-player team even in the rare case another team also rolls a
## perfect record.
func _compare_seed_entries(a: Dictionary, b: Dictionary) -> bool:
	if a.wins != b.wins:
		return a.wins > b.wins
	if a.name == RIVAL_NAME:
		return true
	if b.name == RIVAL_NAME:
		return false
	return false


## Simulates the semifinal pairing that doesn't include the player, so its
## winner can be lined up as the player's Finals opponent ahead of time.
## The higher seed is favored but not certain.
func _simulate_other_semifinal(a: Dictionary, b: Dictionary) -> void:
	var higher: Dictionary = a if a.wins >= b.wins else b
	var lower: Dictionary = b if a.wins >= b.wins else a
	var diff: int = higher.wins - lower.wins
	var prob_higher_wins: float = clamp(0.5 + diff * 0.08, 0.55, 0.9)
	var winner: Dictionary = higher if randf() < prob_higher_wins else lower
	var loser: Dictionary = lower if winner.name == higher.name else higher

	finals_opponent_name = winner.name
	var series_scores := ["2-0", "2-1"]
	other_semifinal_result = "In the other semifinal, the %s defeated the %s %s." % [
		winner.name, loser.name, series_scores[randi() % series_scores.size()]
	]


## Each team's own overall record for the season (standings-table flavor,
## not the player's record against them). The Vipers are always guaranteed
## the single best record among the other 7 teams.
func _roll_league_records() -> void:
	league_records = {}
	var non_rival_count := 0
	for t in teams:
		if not t.rival:
			non_rival_count += 1

	var non_rival_index := 0
	var max_non_rival_wins := 0
	for t in teams:
		if t.rival:
			continue
		# Biased toward the team's difficulty tier (its position in the
		# roughly-ascending-difficulty team list) so tougher opponents also
		# tend to sit higher in the standings, not pure noise — still with
		# enough spread for an occasional upset either way.
		var expected: float = lerp(3.0, 6.0, float(non_rival_index) / float(non_rival_count - 1))
		var wins: int = clamp(int(round(expected)) + randi_range(-2, 2), 0, REGULAR_SEASON_GAMES)
		league_records[t.name] = {"wins": wins, "losses": REGULAR_SEASON_GAMES - wins}
		max_non_rival_wins = max(max_non_rival_wins, wins)
		non_rival_index += 1

	var vipers_wins: int = clamp(max_non_rival_wins + 1, WINS_NEEDED_TO_QUALIFY, REGULAR_SEASON_GAMES)
	league_records[RIVAL_NAME] = {"wins": vipers_wins, "losses": REGULAR_SEASON_GAMES - vipers_wins}


func get_league_record(team_name: String) -> Dictionary:
	return league_records.get(team_name, {"wins": 0, "losses": 0})


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
	bracket_seeds = []
	player_seed_index = -1
	semifinal_opponent_name = ""
	finals_opponent_name = ""
	_roll_league_records()
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
		"league_records": league_records,
		"bracket_seeds": bracket_seeds,
		"player_seed_index": player_seed_index,
		"semifinal_opponent_name": semifinal_opponent_name,
		"finals_opponent_name": finals_opponent_name,
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
	league_records = parsed.get("league_records", {})
	bracket_seeds = parsed.get("bracket_seeds", [])
	player_seed_index = parsed.get("player_seed_index", -1)
	semifinal_opponent_name = parsed.get("semifinal_opponent_name", "")
	finals_opponent_name = parsed.get("finals_opponent_name", "")

	# A terminal stage is saved the instant it's computed, not when the
	# player clicks "New Season" — if the app closed before that click, the
	# season is still genuinely over, so start fresh rather than loading
	# back into a dead stage no result screen will ever show again.
	if is_season_over():
		reset_season()
