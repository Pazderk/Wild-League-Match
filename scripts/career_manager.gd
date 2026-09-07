extends Node

## Autoload: career-wide stats and achievements, independent of any single
## season — survives season resets and restarts (unlike season_save.json),
## and is separate from lightweight preferences (prefs.json) since this is
## data a player would genuinely be sad to lose.

const SAVE_PATH := "user://career_save.json"

## id -> {"name": String, "description": String}. Order here is display
## order in the Trophy Case.
const ACHIEVEMENTS := {
	"cycle_hitter": {"name": "Cycle Hitter", "description": "Hit a Double, a Triple, and a Home Run all in the same game."},
	"grand_slam": {"name": "Grand Slam", "description": "Fill the Big Play Gauge and trigger a Rally."},
	"walkoff_hero": {"name": "Walk-off Hero", "description": "Win a game with a Walk-off Win."},
	"sharpshooter": {"name": "Sharpshooter", "description": "Finish a game without a single whiffed swap."},
	"speedrun": {"name": "Speedrun", "description": "Win with a Walk-off while 20+ seconds are still on the clock."},
	"comeback_kid": {"name": "Comeback Kid", "description": "Win after trailing by a wide margin at the 7th Inning Stretch reveal."},
	"midas_touch": {"name": "Midas Touch", "description": "Catch the Golden Ball 5+ times in one game."},
	"error_free": {"name": "Error-Free", "description": "Finish 3 straight games without ever matching an Error Tile."},
	"bonus_time": {"name": "Bonus Time", "description": "Win a game using a banked Extra Innings."},
	"rainbow_connection": {"name": "Rainbow Connection", "description": "Trigger the Rainbow tile's color clear 3 times in one game."},
	"nothing_but_net": {"name": "Nothing But Net", "description": "Win a game without using any power-up."},
	"demolition_crew": {"name": "Demolition Crew", "description": "Use all 3 power-up types in a single game."},
	"hot_streak": {"name": "Hot Streak", "description": "Reach a 5-game win streak."},
	"perfect_hands": {"name": "Perfect Hands", "description": "Hold a x3 Hitting Streak for a continuous 30 seconds in one game."},
	"undefeated": {"name": "Undefeated", "description": "Finish a perfect regular season."},
	"champion": {"name": "Champion", "description": "Win the Finals."},
	"rivalry_won": {"name": "Rivalry Won", "description": "Beat the Vipers in a regular season game, then win the Finals that same season."},
	"cinderella_story": {"name": "Cinderella Story", "description": "Win the championship as the #4 seed."},
	"dynasty": {"name": "Dynasty", "description": "Win back-to-back championships."},
	"hall_of_famer": {"name": "Hall of Famer", "description": "Win a championship at Hall of Fame difficulty."},
}

var seasons_played := 0
var career_wins := 0
var career_losses := 0
var championships_won := 0
var championships_by_difficulty := {"rookie": 0, "pro": 0, "all_star": 0, "hall_of_fame": 0}
var longest_win_streak_ever := 0
var consecutive_championships := 0
# Rolls across the whole career, independent of season boundaries — an
# error-tile-free game increments it, a game with one matched resets it.
var error_free_streak := 0
var unlocked_achievements := {} # id -> true

# Achievements unlocked by the most recent call into this autoload, for
# callers to show a callout. Cleared at the start of each triggering call.
var newly_unlocked: Array = []


func _ready() -> void:
	_load()


func is_unlocked(id: String) -> bool:
	return unlocked_achievements.has(id)


## Idempotent — a no-op (returns false) if already unlocked or the id is
## unrecognized. Returns true if this call is what newly unlocked it.
func unlock(id: String) -> bool:
	if not ACHIEVEMENTS.has(id) or unlocked_achievements.has(id):
		return false
	unlocked_achievements[id] = true
	newly_unlocked.append(id)
	return true


## Called once per completed game (any outcome, any stage) — updates the
## career win/loss totals and the rolling Error-Free streak.
func record_game_result(did_win: bool, error_tile_matched: bool) -> void:
	newly_unlocked = []
	if did_win:
		career_wins += 1
	else:
		career_losses += 1

	if error_tile_matched:
		error_free_streak = 0
	else:
		error_free_streak += 1
		if error_free_streak >= 3:
			unlock("error_free")

	_save()


## Called whenever a win extends SeasonManager's win_streak.
func record_win_streak(streak: int) -> void:
	newly_unlocked = []
	if streak > longest_win_streak_ever:
		longest_win_streak_ever = streak
	if streak >= 5:
		unlock("hot_streak")
	_save()


## Called once, exactly when a season resolves to a terminal stage — i.e.
## the instant `stage` becomes "champion", "missed_playoffs",
## "eliminated_semis", or "eliminated_finals" — not later at reset time, so
## the record survives even if the player never explicitly starts a new
## season afterward.
func record_season_end(stage: String, difficulty: String, player_seed_index: int, regular_wins: int, regular_losses: int, beat_vipers_regular_season: bool) -> void:
	newly_unlocked = []
	seasons_played += 1

	if regular_losses == 0 and regular_wins > 0:
		unlock("undefeated")

	if stage == "champion":
		championships_won += 1
		championships_by_difficulty[difficulty] = championships_by_difficulty.get(difficulty, 0) + 1
		consecutive_championships += 1
		unlock("champion")
		if difficulty == "hall_of_fame":
			unlock("hall_of_famer")
		if player_seed_index == 3:
			unlock("cinderella_story")
		if beat_vipers_regular_season:
			unlock("rivalry_won")
		if consecutive_championships >= 2:
			unlock("dynasty")
	else:
		consecutive_championships = 0

	_save()


func _save() -> void:
	var data := {
		"seasons_played": seasons_played,
		"career_wins": career_wins,
		"career_losses": career_losses,
		"championships_won": championships_won,
		"championships_by_difficulty": championships_by_difficulty,
		"longest_win_streak_ever": longest_win_streak_ever,
		"consecutive_championships": consecutive_championships,
		"error_free_streak": error_free_streak,
		"unlocked_achievements": unlocked_achievements,
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
	seasons_played = parsed.get("seasons_played", 0)
	career_wins = parsed.get("career_wins", 0)
	career_losses = parsed.get("career_losses", 0)
	championships_won = parsed.get("championships_won", 0)
	championships_by_difficulty = parsed.get("championships_by_difficulty", {"rookie": 0, "pro": 0, "all_star": 0, "hall_of_fame": 0})
	longest_win_streak_ever = parsed.get("longest_win_streak_ever", 0)
	consecutive_championships = parsed.get("consecutive_championships", 0)
	error_free_streak = parsed.get("error_free_streak", 0)
	unlocked_achievements = parsed.get("unlocked_achievements", {})
