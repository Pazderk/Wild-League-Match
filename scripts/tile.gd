extends ColorRect

## Placeholder tile: a flat-colored square standing in for an animal/sport gem
## until real art is ready. Each gem_type maps to a mascot below.

signal tile_clicked(grid_pos: Vector2i)

const GEM_COLORS := [
	Color(0.85, 0.25, 0.25), # 0 - Bear / Baseball
	Color(0.95, 0.55, 0.15), # 1 - Fox / Soccer
	Color(0.65, 0.45, 0.25), # 2 - Owl / Basketball
	Color(0.35, 0.55, 0.85), # 3 - Wolf / Hockey
	Color(0.35, 0.75, 0.35), # 4 - Otter / Tennis
	Color(0.85, 0.85, 0.25), # 5 - Eagle / Football
]

# "" = plain gem. "area"/"row"/"col"/"color_bomb" = an All-Star tile: swap it
# into any adjacent tile (even with no ordinary match) to detonate its blast,
# or let it get caught in a normal match / another special's blast to
# chain-fire it. color_bomb ("MVP Ball") instead clears every tile matching
# whichever gem it's swapped into.
#
# All four are drawn directly (a horizontal arrow, a vertical arrow, a
# bomb, a spinning rainbow wheel) rather than as a letter — a font's
# rendering of a given Unicode symbol isn't guaranteed consistent across
# browsers in a web export, while a drawn shape always looks the same.
const COLOR_BOMB_COLOR := Color(0.1, 0.1, 0.12)
const SPECIAL_SHAPE_COLOR := Color(1, 1, 1, 1)
const BOMB_BODY_COLOR := Color(0.08, 0.08, 0.1, 1)
const BOMB_OUTLINE_COLOR := Color(1, 1, 1, 0.85)
const BOMB_FUSE_COLOR := Color(0.6, 0.4, 0.2, 1)
const BOMB_SPARK_COLOR := Color(1, 0.8, 0.2, 1)
const RAINBOW_COLORS := [
	Color(0.9, 0.15, 0.15), Color(0.95, 0.55, 0.1), Color(0.95, 0.85, 0.15),
	Color(0.25, 0.75, 0.35), Color(0.25, 0.55, 0.9), Color(0.55, 0.25, 0.75),
]
const RAINBOW_SPIN_SPEED := 1.2 # radians/sec

# Board-event overlays: a temporary marker on top of an ordinary gem, matched
# via normal color-match rules like any other tile, independent of the
# All-Star special_type above. "" = none. "golden" = worth bonus points and
# relocates instead of clearing when matched. "error" = penalizes the player
# when matched. "extra_innings" = adds time when matched.
#
# "error" and "golden" are drawn directly (an X, a circle) rather than as a
# text glyph — this is a web export, and a font's rendering of a given
# Unicode symbol isn't guaranteed consistent across browsers, while a drawn
# shape always looks the same. "extra_innings" keeps the small corner-badge
# treatment since it wasn't reported as hard to see.
const EVENT_BADGE_COLORS := {"extra_innings": Color(0.25, 0.6, 1, 1)}
const EVENT_SYMBOLS := {"extra_innings": "+10"}
const ERROR_SHAPE_COLOR := Color(0.85, 0.1, 0.1, 1)
const GOLDEN_SHAPE_FILL := Color(1, 0.84, 0, 0.9)
const GOLDEN_SHAPE_OUTLINE := Color(0.55, 0.4, 0, 1)

var gem_type: int = 0
var special_type: String = ""
var event_type: String = ""
var grid_pos: Vector2i = Vector2i.ZERO
var rainbow_rotation := 0.0

@onready var special_mark: Label = $SpecialMark
@onready var event_badge: ColorRect = $EventBadge
@onready var event_mark: Label = $EventBadge/EventMark


func _ready() -> void:
	pivot_offset = size / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(delta: float) -> void:
	if special_type == "color_bomb":
		rainbow_rotation += delta * RAINBOW_SPIN_SPEED
		queue_redraw()


## Setting a plain gem type always clears any special marker or board-event
## badge — a tile only carries either when explicitly given one afterward.
func set_type(type: int) -> void:
	gem_type = type
	color = GEM_COLORS[type]
	set_special("")
	set_event("")


func set_special(type: String) -> void:
	special_type = type
	special_mark.visible = false

	if type == "color_bomb":
		color = COLOR_BOMB_COLOR
		rainbow_rotation = 0.0
	elif type == "":
		color = GEM_COLORS[gem_type]
	queue_redraw()


func set_event(type: String) -> void:
	event_type = type
	event_badge.visible = type == "extra_innings"
	if type == "extra_innings":
		event_badge.color = EVENT_BADGE_COLORS[type]
		event_mark.text = EVENT_SYMBOLS[type]
	queue_redraw()


func _draw() -> void:
	match special_type:
		"row":
			_draw_double_arrow(true)
		"col":
			_draw_double_arrow(false)
		"area":
			_draw_bomb()
		"color_bomb":
			_draw_rainbow_wheel()

	match event_type:
		"error":
			var margin := 14.0
			draw_line(Vector2(margin, margin), Vector2(size.x - margin, size.y - margin), ERROR_SHAPE_COLOR, 7.0, true)
			draw_line(Vector2(size.x - margin, margin), Vector2(margin, size.y - margin), ERROR_SHAPE_COLOR, 7.0, true)
		"golden":
			var center := size / 2.0
			var radius: float = min(size.x, size.y) / 2.0 - 10.0
			draw_circle(center, radius, GOLDEN_SHAPE_FILL)
			draw_arc(center, radius, 0, TAU, 32, GOLDEN_SHAPE_OUTLINE, 3.0, true)


## A double-headed arrow — horizontal for the row-clear All-Star tile,
## vertical for the column-clear one — pointing along the line it clears.
func _draw_double_arrow(horizontal: bool) -> void:
	var cx := size.x / 2.0
	var cy := size.y / 2.0
	var half_len: float = (size.x if horizontal else size.y) * 0.30
	var head_len := 14.0
	var head_width := 9.0

	if horizontal:
		draw_line(Vector2(cx - half_len, cy), Vector2(cx + half_len, cy), SPECIAL_SHAPE_COLOR, 6.0, true)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - half_len - head_len * 0.5, cy),
			Vector2(cx - half_len + head_len * 0.5, cy - head_width),
			Vector2(cx - half_len + head_len * 0.5, cy + head_width),
		]), SPECIAL_SHAPE_COLOR)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx + half_len + head_len * 0.5, cy),
			Vector2(cx + half_len - head_len * 0.5, cy - head_width),
			Vector2(cx + half_len - head_len * 0.5, cy + head_width),
		]), SPECIAL_SHAPE_COLOR)
	else:
		draw_line(Vector2(cx, cy - half_len), Vector2(cx, cy + half_len), SPECIAL_SHAPE_COLOR, 6.0, true)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx, cy - half_len - head_len * 0.5),
			Vector2(cx - head_width, cy - half_len + head_len * 0.5),
			Vector2(cx + head_width, cy - half_len + head_len * 0.5),
		]), SPECIAL_SHAPE_COLOR)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx, cy + half_len + head_len * 0.5),
			Vector2(cx - head_width, cy + half_len - head_len * 0.5),
			Vector2(cx + head_width, cy + half_len - head_len * 0.5),
		]), SPECIAL_SHAPE_COLOR)


## A classic round bomb with a curled fuse and spark, for the area-clear
## All-Star tile.
func _draw_bomb() -> void:
	var center := Vector2(size.x / 2.0, size.y / 2.0 + 5.0)
	var radius: float = size.x * 0.26
	draw_circle(center, radius, BOMB_BODY_COLOR)
	draw_arc(center, radius, 0, TAU, 24, BOMB_OUTLINE_COLOR, 2.0, true)

	var fuse_base := center + Vector2(radius * 0.55, -radius * 0.8)
	var fuse_tip := fuse_base + Vector2(8, -12)
	draw_line(fuse_base, fuse_tip, BOMB_FUSE_COLOR, 3.0, true)
	draw_circle(fuse_tip + Vector2(1, -1), 4.0, BOMB_SPARK_COLOR)


## A slowly spinning color wheel for the color bomb ("MVP Ball") — the
## rotation itself is what reads as "rainbow" at a glance, not just the
## color spread.
func _draw_rainbow_wheel() -> void:
	var center := size / 2.0
	var radius: float = min(size.x, size.y) / 2.0 - 8.0
	var slice_count := RAINBOW_COLORS.size()
	var slice_angle := TAU / slice_count
	var arc_steps := 8

	for i in range(slice_count):
		var start_angle: float = rainbow_rotation + i * slice_angle
		var points := PackedVector2Array()
		points.append(center)
		for s in range(arc_steps + 1):
			var a: float = start_angle + slice_angle * (float(s) / arc_steps)
			points.append(center + Vector2(cos(a), sin(a)) * radius)
		draw_colored_polygon(points, RAINBOW_COLORS[i])

	draw_arc(center, radius, 0, TAU, 32, Color(1, 1, 1, 0.6), 2.0, true)


func set_selected(is_selected: bool) -> void:
	var target_scale := Vector2(0.85, 0.85) if is_selected else Vector2.ONE
	create_tween().tween_property(self, "scale", target_scale, 0.1)


func play_clear_effect() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.tween_callback(func(): modulate.a = 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tile_clicked.emit(grid_pos)
