extends Node2D

## One "game": an 8x8 swap-3 board played against a running clock, racing a
## hidden opponent score that's revealed with 15 seconds left. Beat it when
## time runs out (or hit a Walk-off Win in that final stretch) to win.
##
## Tiles never move as nodes — we swap/shift the `gem_type`/`special_type`
## values stored on each fixed-position tile, which keeps match/gravity logic
## simple (no node reparenting or fall tweens yet).

const COLUMNS := 8
const ROWS := 8
const TILE_SIZE := 80
const GEM_TYPES := 6
const BASE_POINTS := 10
const SESSION_SECONDS := 60.0

const CASCADE_EVENTS := ["STOLEN BASE!", "STRUCK 'EM OUT!", "DIVING CATCH!"]

# Big Play Gauge: fills from match points (paused while a Rally is active so
# it reads as a build-up/payoff rhythm rather than a permanent state). Full
# gauge triggers a "Grand Slam!" Rally window with a flat score multiplier.
const RALLY_METER_MAX := 1500.0
const RALLY_DURATION := 10.0
const RALLY_MULTIPLIER := 2

# Cascade chains multiply points per step, but uncapped this compounds with
# tier and Rally multipliers into runaway swings on a lucky multi-step
# cascade — capping keeps chains exciting without blowing up the scoreboard.
const MAX_CHAIN_MULTIPLIER := 3

# How long the Rally announcement freezes the game before play (and the
# 10s Rally window itself) resumes.
const RALLY_ANNOUNCE_DURATION := 2.0

# The opponent's score is rolled (from the current team's range) and fixed
# at game start, but stays hidden on the HUD until this many seconds remain —
# a Walk-off Win can't happen before the reveal, so the earliest one can ever
# fire is right at this mark.
const OPPONENT_REVEAL_TIME_LEFT := 15.0

# Consecutive successful swaps build a small bonus on top of everything else;
# a whiffed swap or a few idle seconds resets it.
const HOT_HAND_DECAY_IDLE_SECONDS := 4.0
const HOT_HAND_MAX_STREAK := 5
const HOT_HAND_BONUS_PER_STACK := 0.1

# Walk-off celebration: real-world seconds the slow-motion beat lasts,
# regardless of the slow-mo time scale itself.
const WALKOFF_SLOWMO_SCALE := 0.4
const WALKOFF_CELEBRATION_SECONDS := 4.0

const TileScene := preload("res://scenes/tile.tscn")

@onready var score_label: Label = $ScoreLabel
@onready var opponent_label: Label = $TargetLabel
@onready var time_label: Label = $TimeLabel
@onready var big_play_label: Label = $BigPlayLabel
@onready var hot_hand_label: Label = $HotHandLabel
@onready var tiles_container: Node2D = $TilesContainer
@onready var rally_bar: ProgressBar = $RallyBar
@onready var rally_status_label: Label = $RallyStatusLabel
@onready var rally_announcement: Control = $RallyAnnouncement
@onready var rally_announce_label: Label = $RallyAnnouncement/AnnounceLabel
@onready var walkoff_label: Label = $RallyAnnouncement/WalkoffLabel
@onready var fireworks_layer: Node2D = $RallyAnnouncement/FireworksLayer
@onready var rally_audio: AudioStreamPlayer = $RallyAnnouncement/RallyAudio
@onready var end_panel: Panel = $EndPanel
@onready var end_title_label: Label = $EndPanel/EndTitleLabel
@onready var final_score_label: Label = $EndPanel/FinalScoreLabel
@onready var stats_label: Label = $EndPanel/StatsLabel
@onready var play_again_button: Button = $EndPanel/PlayAgainButton

var grid: Array = [] # grid[x][y] -> Tile node
var selected_tile: Vector2i = Vector2i(-1, -1)
var is_busy := false
var is_paused := false
var game_over := false
var score := 0

# Rolled from the current SeasonManager team's range at _ready(); this game's
# fixed (but initially hidden) score to beat.
var target_score := 0
var current_team_name := ""

var time_left := SESSION_SECONDS
var rally_meter := 0.0
var rally_time_left := 0.0
var time_up_handled := false
var final_move_active := false

var opponent_score := 0
var opponent_revealed := false

var hot_hand_streak := 0
var hot_hand_idle_timer := 0.0

var stat_doubles := 0
var stat_triples := 0
var stat_home_runs := 0
var stat_grand_slams := 0
var stat_mvp_blasts := 0
var stat_longest_cascade := 0


func _ready() -> void:
	randomize()
	_build_board()

	var team: Dictionary = SeasonManager.get_current_team()
	current_team_name = team.name
	target_score = SeasonManager.roll_target_score()
	opponent_score = target_score
	opponent_label.text = "%s: ??" % current_team_name

	_update_time_label()
	rally_bar.max_value = RALLY_METER_MAX
	rally_bar.value = 0.0
	rally_status_label.visible = false
	rally_announcement.visible = false
	hot_hand_label.visible = false

	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 44100.0
	generator.buffer_length = 3.0
	rally_audio.stream = generator

	play_again_button.pressed.connect(func(): get_tree().reload_current_scene())

	if not _has_valid_move():
		await _reshuffle_board()


func _process(delta: float) -> void:
	if game_over or is_paused:
		return

	if time_left > 0.0:
		time_left = max(time_left - delta, 0.0)
		_update_time_label()

		if not opponent_revealed and time_left <= OPPONENT_REVEAL_TIME_LEFT:
			opponent_revealed = true
			opponent_label.text = "%s: %d" % [current_team_name, opponent_score]
			_show_big_play("FINAL STRETCH!")

		hot_hand_idle_timer += delta
		if hot_hand_idle_timer >= HOT_HAND_DECAY_IDLE_SECONDS and hot_hand_streak > 0:
			hot_hand_streak = 0
			_update_hot_hand_label()

	if time_left <= 0.0 and not is_busy and not time_up_handled:
		time_up_handled = true
		_handle_time_up()

	if rally_time_left > 0.0:
		rally_time_left = max(rally_time_left - delta, 0.0)
		rally_status_label.text = "RALLY! x%d (%ds)" % [RALLY_MULTIPLIER, ceil(rally_time_left)]
		if rally_time_left <= 0.0:
			rally_status_label.visible = false


func _update_time_label() -> void:
	var total := int(ceil(time_left))
	time_label.text = "Time: %d:%02d" % [total / 60, total % 60]


## When the clock hits zero: an already-winning score ends the game normally.
## A losing score instead gets one bonus, untimed swap — "one last chance" —
## rather than ending immediately or auto-detonating leftover specials.
## Bungled/no-match swap attempts during this window just revert as usual and
## don't burn the chance; only a swap that actually resolves ends the game.
func _handle_time_up() -> void:
	if score >= opponent_score:
		_end_game()
		return

	is_paused = true
	rally_announce_label.visible = true
	walkoff_label.visible = false
	rally_announce_label.text = "FINAL CHANCE!\nOne swap to win it!"
	rally_announcement.visible = true
	await get_tree().create_timer(2.0).timeout
	rally_announcement.visible = false
	is_paused = false

	if not _has_valid_move():
		await _reshuffle_board()
	final_move_active = true


func _end_game() -> void:
	game_over = true
	var did_win := score >= opponent_score
	end_title_label.text = "YOU WIN!" if did_win else "GAME OVER"
	final_score_label.text = "Final Score: %d   %s: %d" % [score, current_team_name, opponent_score]

	SeasonManager.report_result(did_win)
	var record: Dictionary = SeasonManager.get_record(current_team_name)
	var totals: Dictionary = SeasonManager.get_season_totals()
	stats_label.text = ("Doubles: %d   Triples: %d   Home Runs: %d\n" +
		"Grand Slams: %d   MVP Blasts: %d   Longest Cascade: %d\n\n" +
		"vs %s: %d-%d      Season: %d-%d") % [
		stat_doubles, stat_triples, stat_home_runs,
		stat_grand_slams, stat_mvp_blasts, stat_longest_cascade,
		current_team_name, record.wins, record.losses, totals.wins, totals.losses
	]
	end_panel.visible = true


func _build_board() -> void:
	grid.resize(COLUMNS)
	for x in COLUMNS:
		grid[x] = []
		grid[x].resize(ROWS)
		for y in ROWS:
			var type := _random_type_without_match(x, y)
			grid[x][y] = _spawn_tile(x, y, type)


func _spawn_tile(x: int, y: int, type: int) -> Control:
	var tile := TileScene.instantiate()
	tile.position = Vector2(x * TILE_SIZE, y * TILE_SIZE)
	tile.grid_pos = Vector2i(x, y)
	tiles_container.add_child(tile)
	tile.set_type(type)
	tile.tile_clicked.connect(_on_tile_clicked)
	return tile


func _random_type_without_match(x: int, y: int) -> int:
	var forbidden := []
	if x >= 2 and grid[x - 1][y].gem_type == grid[x - 2][y].gem_type:
		forbidden.append(grid[x - 1][y].gem_type)
	if y >= 2 and grid[x][y - 1].gem_type == grid[x][y - 2].gem_type:
		forbidden.append(grid[x][y - 1].gem_type)
	var type := randi() % GEM_TYPES
	while type in forbidden:
		type = randi() % GEM_TYPES
	return type


func _on_tile_clicked(grid_pos: Vector2i) -> void:
	if game_over or is_busy or is_paused:
		return

	if selected_tile == Vector2i(-1, -1):
		selected_tile = grid_pos
		grid[grid_pos.x][grid_pos.y].set_selected(true)
		return

	if selected_tile == grid_pos:
		grid[grid_pos.x][grid_pos.y].set_selected(false)
		selected_tile = Vector2i(-1, -1)
		return

	if _is_adjacent(selected_tile, grid_pos):
		grid[selected_tile.x][selected_tile.y].set_selected(false)
		_try_swap(selected_tile, grid_pos)
		selected_tile = Vector2i(-1, -1)
	else:
		grid[selected_tile.x][selected_tile.y].set_selected(false)
		selected_tile = grid_pos
		grid[grid_pos.x][grid_pos.y].set_selected(true)


func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return abs(a.x - b.x) + abs(a.y - b.y) == 1


## Swapping either tile into (or out of) an All-Star tile's position always
## counts as a valid move — it activates the special immediately even with
## no ordinary color-match, which is what makes these feel deliberate rather
## than incidental. An MVP Ball (color bomb) additionally targets whichever
## gem color it's swapped into (or clears the whole board if swapped with
## another MVP Ball). A successful swap builds the Hot Hand streak; a whiff
## resets it.
func _try_swap(a: Vector2i, b: Vector2i) -> void:
	is_busy = true
	_swap_tiles(a, b)

	var match_data := _find_matches()
	var forced_label := ""

	for pair in [[a, b], [b, a]]:
		if grid[pair[0].x][pair[0].y].special_type == "color_bomb":
			_trigger_color_bomb(pair[0], pair[1], match_data.positions)
			forced_label = "MVP BLAST!"

	for p in [a, b]:
		if grid[p.x][p.y].special_type != "":
			match_data.positions[p] = true

	if match_data.positions.is_empty():
		await get_tree().create_timer(0.15).timeout
		_swap_tiles(a, b) # no match and no special activated, revert
		hot_hand_streak = 0
		_update_hot_hand_label()
		is_busy = false
	else:
		hot_hand_streak = min(hot_hand_streak + 1, HOT_HAND_MAX_STREAK)
		hot_hand_idle_timer = 0.0
		_update_hot_hand_label()
		var hot_hand_multiplier: float = 1.0 + HOT_HAND_BONUS_PER_STACK * hot_hand_streak

		await _resolve_matches(match_data, forced_label, hot_hand_multiplier)
		is_busy = false

		if final_move_active and not game_over:
			final_move_active = false
			_end_game()
		elif not game_over and not _has_valid_move():
			await _reshuffle_board()


func _update_hot_hand_label() -> void:
	hot_hand_label.visible = hot_hand_streak >= 2
	if hot_hand_streak >= 2:
		hot_hand_label.text = "HOT HAND x%d" % hot_hand_streak


func _trigger_color_bomb(bomb_pos: Vector2i, partner_pos: Vector2i, positions: Dictionary) -> void:
	positions[bomb_pos] = true
	if grid[partner_pos.x][partner_pos.y].special_type == "color_bomb":
		for x in range(COLUMNS):
			for y in range(ROWS):
				positions[Vector2i(x, y)] = true
		return

	var target_color: int = grid[partner_pos.x][partner_pos.y].gem_type
	for x in range(COLUMNS):
		for y in range(ROWS):
			if grid[x][y].gem_type == target_color:
				positions[Vector2i(x, y)] = true


func _swap_tiles(a: Vector2i, b: Vector2i) -> void:
	var tile_a: Control = grid[a.x][a.y]
	var tile_b: Control = grid[b.x][b.y]
	var temp_type: int = tile_a.gem_type
	var temp_special: String = tile_a.special_type
	tile_a.set_type(tile_b.gem_type)
	tile_a.set_special(tile_b.special_type)
	tile_b.set_type(temp_type)
	tile_b.set_special(temp_special)


## Returns {"positions": {Vector2i: true}, "runs": [{"length", "orientation",
## "cells"}, ...]}. positions is every unique tile to clear this step; runs
## keeps each straight segment's shape so a Double (4-run) knows which
## orientation of All-Star tile to spawn, and a Triple (two 3-runs landing at
## once — an L/T-shaped match, or two unrelated 3-runs clearing together) can
## find where they cross for the area-blast spawn point.
func _find_matches() -> Dictionary:
	var positions := {}
	var runs: Array = []

	for y in ROWS:
		var run_len := 1
		for x in range(1, COLUMNS):
			if grid[x][y].gem_type == grid[x - 1][y].gem_type:
				run_len += 1
			else:
				if run_len >= 3:
					runs.append(_make_run(run_len, "h", x - run_len, y, positions, true))
				run_len = 1
		if run_len >= 3:
			runs.append(_make_run(run_len, "h", COLUMNS - run_len, y, positions, true))

	for x in COLUMNS:
		var run_len := 1
		for y in range(1, ROWS):
			if grid[x][y].gem_type == grid[x][y - 1].gem_type:
				run_len += 1
			else:
				if run_len >= 3:
					runs.append(_make_run(run_len, "v", x, y - run_len, positions, false))
				run_len = 1
		if run_len >= 3:
			runs.append(_make_run(run_len, "v", x, ROWS - run_len, positions, false))

	return {"positions": positions, "runs": runs}


func _make_run(run_len: int, orientation: String, start_x: int, start_y: int, positions: Dictionary, horizontal: bool) -> Dictionary:
	var cells: Array = []
	for k in range(run_len):
		var cell := Vector2i(start_x + k, start_y) if horizontal else Vector2i(start_x, start_y + k)
		cells.append(cell)
		positions[cell] = true
	return {"length": run_len, "orientation": orientation, "cells": cells}


## Resolves one move's full cascade. Each step's event tier (Double/Triple/
## Home Run) is decided from the run segments found, not per-tile count, so
## a Triple specifically means "two 3-runs landed at once". A Double spawns
## a line-blast All-Star tile (oriented like the match); a Triple spawns an
## area-blast one at the runs' crossing point; a Home Run (5+) spawns an MVP
## Ball (color bomb). Any All-Star tile caught in `positions` (from a normal
## match, direct swap-activation, or another special's blast) detonates and
## expands the clear area before scoring, so the existing score formula
## scales automatically with the bigger clear. `forced_label` overrides the
## first step's callout — used for a color bomb's own activation, which is
## a bigger event than whatever ordinary tier it happens to coincide with.
## If a Home Run, Grand Slam Rally, or MVP Blast is what newly pushes the
## score past the opponent's current live score, that's a Walk-off Win and
## ends the game immediately instead of continuing to chain further.
func _resolve_matches(match_data: Dictionary, forced_label: String = "", hot_hand_multiplier: float = 1.0) -> void:
	var chain_count := 1

	while not match_data.positions.is_empty():
		var positions: Dictionary = match_data.positions
		var runs: Array = match_data.runs

		var detonated := _expand_special_detonations(positions)

		var max_run := 0
		var home_run_run = null
		var double_run = null
		var triple_runs: Array = []
		for run in runs:
			max_run = max(max_run, run.length)
			if run.length >= 5 and home_run_run == null:
				home_run_run = run
			elif run.length == 4 and double_run == null:
				double_run = run
			elif run.length == 3:
				triple_runs.append(run)

		var tier_multiplier := 1
		var event_label := ""
		var spawn_pos = null
		var spawn_special := ""

		if max_run >= 5:
			tier_multiplier = 4
			event_label = "HOME RUN!"
			if home_run_run != null:
				spawn_pos = home_run_run.cells[home_run_run.cells.size() / 2]
				spawn_special = "color_bomb"
		elif double_run != null:
			tier_multiplier = 2
			event_label = "DOUBLE!"
			spawn_pos = double_run.cells[double_run.cells.size() / 2]
			spawn_special = "row" if double_run.orientation == "h" else "col"
		elif triple_runs.size() >= 2:
			tier_multiplier = 3
			event_label = "TRIPLE!"
			spawn_pos = _pick_triple_spawn(triple_runs[0], triple_runs[1])
			spawn_special = "area"
		elif chain_count >= 2:
			event_label = CASCADE_EVENTS[randi() % CASCADE_EVENTS.size()]

		if event_label == "" and detonated:
			event_label = "BLAST!"

		if chain_count == 1 and forced_label != "":
			event_label = forced_label

		match event_label:
			"DOUBLE!": stat_doubles += 1
			"TRIPLE!": stat_triples += 1
			"HOME RUN!": stat_home_runs += 1
			"MVP BLAST!": stat_mvp_blasts += 1
		stat_longest_cascade = max(stat_longest_cascade, chain_count)

		if spawn_pos != null:
			positions.erase(spawn_pos)

		var chain_multiplier: int = min(chain_count, MAX_CHAIN_MULTIPLIER)
		var base_points: int = int(BASE_POINTS * positions.size() * tier_multiplier * chain_multiplier * hot_hand_multiplier)
		var rally_active := rally_time_left > 0.0
		var score_before_step := score
		score += base_points * (RALLY_MULTIPLIER if rally_active else 1)
		score_label.text = "Score: %d" % score

		if not rally_active:
			rally_meter = min(rally_meter + base_points, RALLY_METER_MAX)
			rally_bar.value = rally_meter

		if event_label != "":
			_show_big_play(event_label)

		var rally_just_started := false
		if not rally_active and rally_meter >= RALLY_METER_MAX:
			rally_just_started = true
			stat_grand_slams += 1
			await _start_rally()

		for pos in positions:
			grid[pos.x][pos.y].play_clear_effect()
		await get_tree().create_timer(0.15).timeout

		if spawn_pos != null:
			grid[spawn_pos.x][spawn_pos.y].set_special(spawn_special)

		_apply_gravity(positions)
		await get_tree().create_timer(0.1).timeout

		var is_walkoff_event := event_label == "HOME RUN!" or event_label == "MVP BLAST!" or rally_just_started
		if is_walkoff_event and opponent_revealed and score_before_step < opponent_score and score >= opponent_score:
			await _trigger_walkoff()
			return

		match_data = _find_matches()
		chain_count += 1


func _pick_triple_spawn(run_a: Dictionary, run_b: Dictionary) -> Vector2i:
	var cells_a := {}
	for cell in run_a.cells:
		cells_a[cell] = true
	for cell in run_b.cells:
		if cells_a.has(cell):
			return cell
	return run_a.cells[run_a.cells.size() / 2]


## Expands `positions` in place to include every tile hit by any All-Star
## tile already inside it (an area/row/col blast), chaining into any further
## specials that blast catches. Returns true if anything detonated, so a
## plain activation (no shape tier, no cascade) still gets a callout.
func _expand_special_detonations(positions: Dictionary) -> bool:
	var detonated := false
	var to_process: Array = positions.keys()
	var processed := {}

	while not to_process.is_empty():
		var pos: Vector2i = to_process.pop_back()
		if processed.has(pos):
			continue
		processed[pos] = true

		var special: String = grid[pos.x][pos.y].special_type
		if special == "":
			continue
		detonated = true

		var extra: Array = []
		match special:
			"area":
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						var p := pos + Vector2i(dx, dy)
						if p.x >= 0 and p.x < COLUMNS and p.y >= 0 and p.y < ROWS:
							extra.append(p)
			"row":
				for x in range(COLUMNS):
					extra.append(Vector2i(x, pos.y))
			"col":
				for y in range(ROWS):
					extra.append(Vector2i(pos.x, y))

		for p in extra:
			positions[p] = true
			if not processed.has(p):
				to_process.append(p)

	return detonated


## Freezes the game (clock + input) for a short celebratory beat when the Big
## Play Gauge fills, then resumes and starts the Rally window fresh — the
## announcement itself doesn't eat into the 10s multiplier window.
func _start_rally() -> void:
	is_paused = true
	walkoff_label.visible = false
	rally_announce_label.visible = true
	rally_announce_label.text = "GRAND SLAM!\nRALLY TIME!"
	rally_announcement.visible = true
	_spawn_fireworks()
	_play_rally_fanfare()

	await get_tree().create_timer(RALLY_ANNOUNCE_DURATION).timeout

	rally_announcement.visible = false
	is_paused = false

	rally_meter = 0.0
	rally_bar.value = 0.0
	rally_time_left = RALLY_DURATION
	rally_status_label.visible = true
	rally_status_label.text = "RALLY! x%d (%ds)" % [RALLY_MULTIPLIER, int(RALLY_DURATION)]


## A Home Run, Grand Slam Rally, or MVP Blast that newly pushes the score
## past the opponent's live score ends the game on the spot — a real walk-off
## doesn't wait out the rest of the clock. Bigger, slower spectacle than a
## regular Rally announcement: a couple of fireworks bursts play out in slow
## motion (global time_scale dropped for a fixed real-world duration) before
## handing off to the normal end-game screen.
func _trigger_walkoff() -> void:
	is_paused = true
	game_over = true

	rally_announce_label.visible = false
	walkoff_label.visible = true
	walkoff_label.text = "WALK-OFF WIN!"
	rally_announcement.visible = true

	Engine.time_scale = WALKOFF_SLOWMO_SCALE
	_spawn_fireworks()
	_spawn_fireworks()
	_play_rally_fanfare()

	await get_tree().create_timer(WALKOFF_CELEBRATION_SECONDS, true, false, true).timeout

	Engine.time_scale = 1.0
	rally_announcement.visible = false
	walkoff_label.visible = false
	is_paused = false
	_end_game()


func _spawn_fireworks() -> void:
	for i in range(4):
		var origin := Vector2(randf_range(100.0, 620.0), randf_range(150.0, 550.0))
		get_tree().create_timer(i * 0.18).timeout.connect(_burst_at.bind(origin))


func _burst_at(origin: Vector2) -> void:
	var burst_colors := [
		Color(1.0, 0.3, 0.3), Color(1.0, 0.85, 0.2), Color(0.3, 0.7, 1.0),
		Color(0.4, 1.0, 0.4), Color(1.0, 0.5, 1.0),
	]
	for i in range(14):
		var spark := ColorRect.new()
		spark.size = Vector2(8, 8)
		spark.color = burst_colors[randi() % burst_colors.size()]
		spark.position = origin
		fireworks_layer.add_child(spark)

		var angle := randf() * TAU
		var dist := randf_range(90.0, 220.0)
		var target := origin + Vector2(cos(angle), sin(angle)) * dist

		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(spark, "position", target, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(spark, "modulate:a", 0.0, 0.6)
		tween.finished.connect(spark.queue_free)


## Synthesizes a short original ascending-fanfare motif at runtime — a
## placeholder "crowd hype" cue, not a reproduction of any existing
## recorded "Charge!" sound. Swap in a licensed SFX later for the real thing.
func _play_rally_fanfare() -> void:
	rally_audio.play()
	var playback: AudioStreamGeneratorPlayback = rally_audio.get_stream_playback()
	playback.push_buffer(_build_fanfare_samples())


func _build_fanfare_samples() -> PackedVector2Array:
	const MIX_RATE := 44100.0
	var notes := [
		{"freq": 523.25, "dur": 0.12}, # C5
		{"freq": 659.25, "dur": 0.12}, # E5
		{"freq": 783.99, "dur": 0.12}, # G5
		{"freq": 1046.50, "dur": 0.30}, # C6
		{"freq": 0.0, "dur": 0.08}, # rest
		{"freq": 783.99, "dur": 0.12}, # G5
		{"freq": 1046.50, "dur": 0.50}, # C6, held
	]

	var samples := PackedVector2Array()
	for note in notes:
		var freq: float = note.freq
		var frame_count := int(MIX_RATE * note.dur)
		for i in range(frame_count):
			var value := 0.0
			if freq > 0.0:
				var t := i / MIX_RATE
				value = 0.55 * sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.0 * t) + 0.15 * sin(TAU * freq * 3.0 * t)
				var attack: float = min(1.0, i / (MIX_RATE * 0.005))
				var release: float = min(1.0, (frame_count - i) / (MIX_RATE * 0.02))
				value *= min(attack, release) * 0.5
			samples.append(Vector2(value, value))
	return samples


func _show_big_play(text: String) -> void:
	big_play_label.text = text
	big_play_label.modulate.a = 1.0
	big_play_label.scale = Vector2(0.7, 0.7)
	big_play_label.visible = true

	var tween := create_tween()
	tween.tween_property(big_play_label, "scale", Vector2(1.1, 1.1), 0.15)
	tween.tween_property(big_play_label, "scale", Vector2.ONE, 0.1)
	tween.tween_interval(0.5)
	tween.tween_property(big_play_label, "modulate:a", 0.0, 0.3)


## Any All-Star tile on the board is always a valid "move" (it can be
## activated with any neighbor), so this only needs to brute-force ordinary
## swaps once no special tile is present.
func _has_valid_move() -> bool:
	for x in range(COLUMNS):
		for y in range(ROWS):
			if grid[x][y].special_type != "":
				return true
			if x + 1 < COLUMNS and _would_create_match(Vector2i(x, y), Vector2i(x + 1, y)):
				return true
			if y + 1 < ROWS and _would_create_match(Vector2i(x, y), Vector2i(x, y + 1)):
				return true
	return false


func _would_create_match(a: Vector2i, b: Vector2i) -> bool:
	_swap_tiles(a, b)
	var has_match: bool = not _find_matches().positions.is_empty()
	_swap_tiles(a, b)
	return has_match


## Safety net for a dead board (no valid swap anywhere): re-randomizes every
## tile (clearing any leftover All-Star tiles in the process) and, in the
## astronomically unlikely case that still leaves no valid move, tries again.
func _reshuffle_board() -> void:
	is_paused = true
	_show_big_play("RESHUFFLE!")
	for x in range(COLUMNS):
		for y in range(ROWS):
			grid[x][y].set_type(_random_type_without_match(x, y))
	await get_tree().create_timer(0.5).timeout
	is_paused = false

	if not _has_valid_move():
		await _reshuffle_board()


func _apply_gravity(cleared: Dictionary) -> void:
	for x in COLUMNS:
		var write_y := ROWS - 1
		for y in range(ROWS - 1, -1, -1):
			if not cleared.has(Vector2i(x, y)):
				if write_y != y:
					var src: Control = grid[x][y]
					var dst: Control = grid[x][write_y]
					dst.set_type(src.gem_type)
					dst.set_special(src.special_type)
				write_y -= 1
		for y in range(write_y, -1, -1):
			grid[x][y].set_type(randi() % GEM_TYPES)
