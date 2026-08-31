extends Node

## Autoload: survives scene reloads (the "Play Again" button just reloads
## board.tscn), so season/playoff progress persists across games within a
## session, and to disk across closing/reopening the app.
##
## Regular season: a real 8-team round robin (you + 7 others), played
## incrementally. Each time you finish a game, the other 6 teams not facing
## you that week are randomly paired into 3 more games and simulated, so
## everyone's record evolves week by week instead of being pre-rolled once.
## You face all 7 other teams twice each over 14 games (cycling through
## them). No early exit — every game is played, and standings after all 14
## decide who's in.
##
## Playoffs: the top 4 of the full 8-team standings (you + 7 others) make
## it. Seed 1 plays seed 4, seed 2 plays seed 3 — whichever pairing you're
## seeded into is your real Semifinal opponent, so the Vipers could be a
## Semifinal foe, not always the Finals. The "other" semifinal (the pairing
## without you) is simulated once, favoring the higher seed but not
## certain, and its winner becomes your Finals opponent. Nothing carries
## over between seasons yet — a new season is a full reset.

const SAVE_PATH := "user://season_save.json"
const PREFS_PATH := "user://prefs.json"

const REGULAR_SEASON_GAMES := 14
const RIVAL_NAME := "Blackthorn Vipers"
const SEMIFINAL_WINS_NEEDED := 2 # best of 3
const FINALS_WINS_NEEDED := 3 # best of 5
const PLAYOFF_SCORE_BOOST := 1.18 # tougher score ranges once the postseason starts

var teams := [
	{"name": "Ironbark Bears", "min_score": 3500, "max_score": 4500, "rival": false},
	{"name": "Riverside Otters", "min_score": 3800, "max_score": 4800, "rival": false},
	{"name": "Graymoor Wolves", "min_score": 4200, "max_score": 5200, "rival": false},
	{"name": "Redbrush Foxes", "min_score": 4400, "max_score": 5400, "rival": false},
	{"name": "Highland Owls", "min_score": 4600, "max_score": 5600, "rival": false},
	{"name": "Summit Rams", "min_score": 4800, "max_score": 6000, "rival": false},
	{"name": RIVAL_NAME, "min_score": 7000, "max_score": 9000, "rival": true},
]

var records := {} # team_name -> {"wins": int, "losses": int}; regular season only
# Each of the 7 other teams' own overall record for the season (not the
# player's record against them). Starts at 0-0 each season and evolves
# incrementally: every time the player finishes a game, the 6 teams not
# facing the player that week are randomly paired up and simulated. The
# Vipers are weighted to usually finish with the best record among the
# other 6, with a guaranteed top-up at bracket time if they don't.
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

# Kept in a separate small file from season_save.json since these are
# standing preferences, not season progress — reset_season() must never
# touch them.
var tutorial_seen := false
var team_name := "YOU"


func _ready() -> void:
	_load()
	_load_prefs()
	if league_records.is_empty():
		_reset_league_records()


func mark_tutorial_seen() -> void:
	tutorial_seen = true
	_save_prefs()


## Blank (or whitespace-only) falls back to the "YOU" default rather than
## saving an empty label.
func set_team_name(new_name: String) -> void:
	var trimmed := new_name.strip_edges()
	team_name = trimmed if trimmed != "" else "YOU"
	_save_prefs()


func _save_prefs() -> void:
	var f := FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"tutorial_seen": tutorial_seen, "team_name": team_name}))
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
	team_name = parsed.get("team_name", "YOU")


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

	# Your head-to-head result is that team's result for the week too — a
	# loss for them if you won, a win for them if you didn't.
	if not league_records.has(team.name):
		league_records[team.name] = {"wins": 0, "losses": 0}
	if did_win:
		league_records[team.name].losses += 1
	else:
		league_records[team.name].wins += 1

	# The 6 teams not facing the player this week play each other too, so
	# the whole league's standings evolve together, week by week — all 7
	# other teams' records move by exactly 1 every week.
	_simulate_other_teams_week(team.name)

	current_team_index = (current_team_index + 1) % teams.size()

	# No early exit — every one of the 14 games matters for final standing,
	# so qualification is only ever decided once the season is complete.
	if regular_games_played >= REGULAR_SEASON_GAMES:
		_finish_regular_season()


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


## The full 8-team standings (the player + all 7 other teams) sorted by
## wins, best first. Used both for the standings screen and to decide who
## makes the playoffs.
func compute_standings() -> Array:
	var entries: Array = []
	for t in teams:
		var r: Dictionary = get_league_record(t.name)
		entries.append({"name": t.name, "wins": r.wins, "losses": r.losses, "rival": t.rival, "is_you": false})
	entries.append({"name": team_name, "wins": regular_wins, "losses": regular_losses, "rival": false, "is_you": true})
	entries.sort_custom(_compare_seed_entries)
	return entries


## Called once the 14th game is played. The top 4 of the full standings make
## the playoffs; everyone else's season ends here. Vipers supremacy among
## the other teams is guaranteed at this point (a rare top-up if their
## simulated results didn't already land them on top).
func _finish_regular_season() -> void:
	_enforce_vipers_supremacy()
	var standings: Array = compute_standings()
	var top4: Array = standings.slice(0, 4)

	var player_seed := -1
	for i in range(top4.size()):
		if top4[i].is_you:
			player_seed = i
			break

	if player_seed == -1:
		stage = "missed_playoffs"
		return

	_setup_playoff_bracket(top4, player_seed)
	stage = "semifinal"


## Seeds the 4-team bracket from the top 4 of the final standings. Seed 1
## plays seed 4, seed 2 plays seed 3 — whichever pairing includes the
## player determines their real Semifinal opponent (which may be the
## Vipers). The other pairing is simulated immediately so its winner is
## ready to serve as the player's Finals opponent in advance.
func _setup_playoff_bracket(entrants: Array, player_seed: int) -> void:
	bracket_seeds = entrants
	player_seed_index = player_seed

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


func _reset_league_records() -> void:
	league_records = {}
	for t in teams:
		league_records[t.name] = {"wins": 0, "losses": 0}


## Every week, the 6 other teams not facing the player are randomly paired
## into 3 games and simulated, so the standings evolve organically instead
## of being pre-rolled. Combined with the head-to-head result recorded just
## above for the 7th team (the one facing the player), all 7 other teams'
## records move by exactly 1 every week, totaling 14 games each by season's
## end.
func _simulate_other_teams_week(exclude_name: String) -> void:
	var others: Array = []
	for t in teams:
		if t.name != exclude_name:
			others.append(t.name)
	others.shuffle()
	var i := 0
	while i + 1 < others.size():
		_simulate_one_game(others[i], others[i + 1])
		i += 2


## Simulates a single game between two non-player teams, biased by each
## team's difficulty tier (their position in the roughly-ascending-difficulty
## team list) plus a small nudge from their current record, so tougher teams
## and hot streaks both tend to show up in the standings without being
## deterministic. The Vipers carry a strong, but not certain, edge.
func _simulate_one_game(name_a: String, name_b: String) -> void:
	if not league_records.has(name_a):
		league_records[name_a] = {"wins": 0, "losses": 0}
	if not league_records.has(name_b):
		league_records[name_b] = {"wins": 0, "losses": 0}

	var team_a := _find_team(name_a)
	var team_b := _find_team(name_b)

	var prob_a_wins: float
	if team_a.rival:
		prob_a_wins = 0.8
	elif team_b.rival:
		prob_a_wins = 0.2
	else:
		var strength_diff: float = _non_rival_strength(name_a) - _non_rival_strength(name_b)
		var record_diff: int = league_records[name_a].wins - league_records[name_b].wins
		prob_a_wins = clamp(0.5 + strength_diff + record_diff * 0.02, 0.15, 0.85)

	if randf() < prob_a_wins:
		league_records[name_a].wins += 1
		league_records[name_b].losses += 1
	else:
		league_records[name_b].wins += 1
		league_records[name_a].losses += 1


## A non-rival team's innate strength (0.35 weakest to 0.65 strongest) based
## on its position in the team list, which is itself roughly ascending
## difficulty.
func _non_rival_strength(team_name: String) -> float:
	var non_rival_names: Array = []
	for t in teams:
		if not t.rival:
			non_rival_names.append(t.name)
	var idx: int = non_rival_names.find(team_name)
	if idx == -1:
		return 0.5
	return lerp(0.35, 0.65, float(idx) / float(non_rival_names.size() - 1))


## Safety net at bracket time: if the Vipers' simulated results didn't
## already land them on top of the other 6 teams, top them up just enough,
## keeping their total games played unchanged.
func _enforce_vipers_supremacy() -> void:
	var vipers: Dictionary = get_league_record(RIVAL_NAME)
	var max_other := 0
	for t in teams:
		if t.rival:
			continue
		max_other = max(max_other, get_league_record(t.name).wins)

	if vipers.wins <= max_other:
		var total_games: int = vipers.wins + vipers.losses
		var boosted_wins: int = clamp(max_other + 1, 0, total_games)
		league_records[RIVAL_NAME] = {"wins": boosted_wins, "losses": total_games - boosted_wins}


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
	_reset_league_records()
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
