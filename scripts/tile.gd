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
const SPECIAL_SYMBOLS := {"area": "A", "row": "H", "col": "V", "color_bomb": "M"}
const COLOR_BOMB_COLOR := Color(0.12, 0.12, 0.14)

var gem_type: int = 0
var special_type: String = ""
var grid_pos: Vector2i = Vector2i.ZERO

@onready var special_mark: Label = $SpecialMark


func _ready() -> void:
	pivot_offset = size / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP


## Setting a plain gem type always clears any special marker — a tile only
## carries special status when explicitly given one via set_special().
func set_type(type: int) -> void:
	gem_type = type
	color = GEM_COLORS[type]
	set_special("")


func set_special(type: String) -> void:
	special_type = type
	special_mark.visible = type != ""
	if type != "":
		special_mark.text = SPECIAL_SYMBOLS[type]

	if type == "color_bomb":
		color = COLOR_BOMB_COLOR
	elif type == "":
		color = GEM_COLORS[gem_type]


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
