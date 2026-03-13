extends Node2D

# --- UI REFERENCES ---
@onready var seed_label     = $CanvasLayer/SeedLabel
@onready var score_label    = $CanvasLayer/ScoreLabel
@onready var restart_button = $CanvasLayer/RestartButton

# --- TILE IDs ---
const EMPTY    = 0
const GRASS    = 1
const SUPER    = 3
const SEED_APEX= 4
const MATURE   = 5
const DUNG     = 6
const POISON_PLANT = 7
const WATER = 8
const STONE = 9
const FAR_MATURE = 10

# --- COLOURS ---
const COLOR_EMPTY    = Color(0.74, 0.60, 0.38)
const COLOR_DESERT_VARIANTS = [
	Color(0.85, 0.71, 0.44),
	Color(0.74, 0.58, 0.32),
	Color(0.68, 0.50, 0.26),
	Color(0.80, 0.65, 0.38),
	Color(0.90, 0.76, 0.48),
	Color(0.65, 0.48, 0.24),
]
const COLOR_GRASS    = Color(0.25, 0.78, 0.18)
const COLOR_PREDATOR = Color(0.90, 0.10, 0.10)
const COLOR_SUPER    = Color(1.00, 0.88, 0.00)
const COLOR_APEX     = Color(0.15, 0.35, 0.95)
const COLOR_MATURE   = Color(0.04, 0.45, 0.12)
const COLOR_FAR_MATURE = Color(0.3, 0.9, 0.3)
const COLOR_DUNG     = Color(0.45, 0.28, 0.10)
const COLOR_POISON   = Color(0.6, 0.1, 0.8)
const COLOR_WATER    = Color(0.1, 0.4, 0.9)
const COLOR_STONE    = Color(0.5, 0.5, 0.5)

# --- MAP ---
var MAP_WIDTH  = 640
var MAP_HEIGHT = 360
const TILE_SIZE  = 4
const MAP_OFFSET = Vector2(0, 40)
const PLANT_ZONE_MARGIN = 0.22

const COLOR_ARID_VARIANTS = [
	Color(0.52, 0.43, 0.36),
	Color(0.47, 0.38, 0.30),
	Color(0.58, 0.44, 0.33),
	Color(0.44, 0.37, 0.32),
	Color(0.55, 0.41, 0.28),
	Color(0.42, 0.35, 0.28),
]

# --- COSTS ---
const COST_GRASS      = 3
const COST_APEX_SPAWN = 30

# --- ANIMAL SIZE ---
const ANIMAL_SIZE    = 5

# --- HERBIVORE SETTINGS ---
const BIRTH_SUCCESS_CHANCE  = 0.50
const HERB_STOMACH_CAP      = 60
const HERB_FOOD_TO_BREED    = 200
const FULL_DURATION         = 300
const STARVE_LIMIT          = 300

# --- APEX PREDATOR SETTINGS ---
const APEX_FOOD_TO_BREED    = 3
const POOP_MIN_DIST         = 5
const DUNG_RIPEN_TICKS      = 200
const APEX_FULL_DURATION    = 500
const APEX_STARVE_LIMIT     = 500

const THIRST_DANGER = 500
const THIRST_LIMIT  = 1000

# --- VISION ---
const VISION_RANGE    = 60
const APEX_SCAN_RANGE = 40
const SCAN_INTERVAL   = 10
const MAX_HERBIVORES  = 100
const MAX_APEXES      = 20

# --- PLANT SETTINGS ---
const SUPER_LIFESPAN      = 80
const SEED_CAP            = 300
const MAX_SPREAD_PER_TICK = 600
const GROWTH_PER_TICK     = 4
var   update_interval     = 0.5

# --- WIN CONDITION ---
const GOAL_SIZE        = 10
const GOAL_FILL_TARGET = 50
var   goal_x: int = 0
var   goal_y: int = 0

# --- RIVER ---
const RIVER_WIDTH = 5
var   river_x: int = 0

# --- GENOME SYSTEM ---
const GENOME_IDS     = ["speed", "range", "poison"]
const GENOME_SLOT_H  = 30
const GENOME_SLOT_W  = 180
const GENOME_TITLE_H = 22
const GENOME_GAP     = 3
const GENOME_PANEL_X = 8

var genomes: Dictionary = {
	"speed":  {"name": "Speed x2",   "cost": 20, "unlocked": false, "color": Color(0.3, 0.95, 0.4)},
	"range":  {"name": "Far Spread", "cost": 35, "unlocked": false, "color": Color(0.3, 0.7,  1.0)},
	"poison": {"name": "Poison",     "cost": 60, "unlocked": false, "color": Color(0.8, 0.2,  0.9)},
}

# Extended directions when "range" genome is active (8 neighbors + 4 two-step cardinals)
const DIRS_EXTENDED = [
	Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0),
	Vector2i(-1,-1), Vector2i(-1,1), Vector2i(1,-1), Vector2i(1,1),
	Vector2i(0,-2), Vector2i(0,2), Vector2i(-2,0), Vector2i(2,0),
]

# --- STATE ---
var grid: Array          = []
var available_seeds: int = 20
var time_passed: float   = 0.0
var animal_time: float   = 0.0
var game_active: bool    = true
var herbivore_auto_spawn: bool = false

var predators: Array = []
var apexes: Array = []
var plant_ages: Dictionary = {}
var dung_ages:  Dictionary = {}
var mature_set: Dictionary = {}
var edge_list:  Array[Vector2i] = []
var edge_set:   Dictionary = {}
var edge_idx:   Dictionary = {}
var plants_this_tick: int = 0

# --- GRAPHING ---
const GRAPH_MAX_SAMPLES = 100
const GRAPH_W = 200
const GRAPH_H = 80
var graph_history: Array = [] # Stores [herb_count, apex_count, plant_count]

const DIRS = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]

class Animal:
	var pos:           Vector2i = Vector2i.ZERO
	var stomach:       int      = 0
	var is_full:       bool     = false
	var poop_target:   Vector2i = Vector2i(-1, -1)
	var full_timer:    int      = 0
	var starve_timer:  int      = 0
	var age:           int      = 0
	var eat_cd:        int      = 0
	var scan_cd:       int      = 0
	var target:        Vector2i = Vector2i(-1, -1)
	var facing:        Vector2i = Vector2i.ZERO
	var home:          Vector2i = Vector2i(-1, -1)
	var thirst:        int      = 0
	var wander_target: Vector2i = Vector2i(-1, -1)
	var wander_cd:     int      = 0
	var rest_timer:    int      = 0
	var water_target:  Vector2i = Vector2i(-1, -1)
	var move_wait:     int      = 0

var predator_texture: Texture2D
var apex_texture: Texture2D
var plant_texture: Texture2D
var bg_image: Image = null
var bg_texture: ImageTexture = null
var bg_dirty: bool = false

var zone_x0: int = 0
var zone_y0: int = 0
var zone_x1: int = 0
var zone_y1: int = 0
var setting_zone_tl: bool = true

func _ready() -> void:
	var win_size = get_viewport().get_visible_rect().size
	MAP_WIDTH  = int(win_size.x / TILE_SIZE)
	MAP_HEIGHT = int((win_size.y - 40) / TILE_SIZE)

	var canvas = get_node_or_null("CanvasLayer")
	if canvas != null:
		var hbox = canvas.get_node_or_null("HBoxContainer")
		if hbox != null:
			hbox.visible = false
		var btn = canvas.get_node_or_null("RestartButton")
		if btn != null:
			btn.position = Vector2(win_size.x / 2 - 150, win_size.y / 2 - 25)

	zone_x0 = int(MAP_WIDTH  * PLANT_ZONE_MARGIN)
	zone_y0 = int(MAP_HEIGHT * PLANT_ZONE_MARGIN)
	zone_x1 = int(MAP_WIDTH  * (1.0 - PLANT_ZONE_MARGIN))
	zone_y1 = int(MAP_HEIGHT * (1.0 - PLANT_ZONE_MARGIN))
	goal_x   = MAP_WIDTH - GOAL_SIZE - 3
	goal_y   = MAP_HEIGHT / 2 - GOAL_SIZE / 2

	_init_grid()
	bg_image = Image.create(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE, false, Image.FORMAT_RGB8)
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			_paint_tile(x, y, _tile_pixel_color(x, y, EMPTY))
	bg_texture = ImageTexture.create_from_image(bg_image)
	update_ui()
	predator_texture = load("res://predator_spritesheet.png")
	apex_texture     = load("res://apex_spritesheet.png")
	plant_texture    = load("res://plant_spritesheet.png")

func _process(delta: float) -> void:
	if not game_active: return
	time_passed += delta
	animal_time  += delta

	if time_passed >= update_interval:
		time_passed -= update_interval
		if time_passed > update_interval: time_passed = 0.0
		run_simulation_step()
	if animal_time >= 0.1:
		animal_time -= 0.1
		run_predator_logic()
		run_apex_logic()
	if bg_dirty:
		bg_texture.update(bg_image)
		bg_dirty = false
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mp := get_global_mouse_position()
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				var gid := _get_clicked_genome(mp)
				if gid != "":
					_buy_genome(gid)
				elif Input.is_key_pressed(KEY_SHIFT):
					_debug_place_water()
				elif Input.is_key_pressed(KEY_CTRL):
					_debug_place_stone()
				elif Input.is_key_pressed(KEY_ALT):
					_debug_set_plant_zone()
				else:
					plant_seed()
			MOUSE_BUTTON_RIGHT:  _debug_spawn_predator()
			MOUSE_BUTTON_MIDDLE: _debug_spawn_apex()

func _debug_spawn_predator() -> void:
	var pos := _mouse_to_grid()
	pos.x = clampi(pos.x, 0, MAP_WIDTH - 1)
	pos.y = clampi(pos.y, 0, MAP_HEIGHT - 1)
	var _a := Animal.new()
	_a.pos = pos
	_a.facing = DIRS.pick_random()
	predators.append(_a)
	queue_redraw()

func _debug_spawn_apex() -> void:
	var pos := _mouse_to_grid()
	pos.x = clampi(pos.x, 0, MAP_WIDTH - 1)
	pos.y = clampi(pos.y, 0, MAP_HEIGHT - 1)
	var _a := Animal.new()
	_a.pos = pos
	_a.facing = DIRS.pick_random()
	_a.home = pos
	apexes.append(_a)
	queue_redraw()

# ---- DRAWING ----

func _debug_place_water() -> void:
	var center := _mouse_to_grid()
	for dx in range(-3, 3):
		for dy in range(-3, 3):
			var pos := Vector2i(center.x + dx, center.y + dy)
			if pos.x >= 0 and pos.x < MAP_WIDTH and pos.y >= 0 and pos.y < MAP_HEIGHT:
				grid[pos.x][pos.y] = WATER
				if bg_image:
					_paint_tile(pos.x, pos.y, COLOR_WATER)
					bg_dirty = true
	queue_redraw()

func _debug_place_stone() -> void:
	var center := _mouse_to_grid()
	for dx in range(-2, 2):
		for dy in range(-2, 2):
			var pos := Vector2i(center.x + dx, center.y + dy)
			if pos.x >= 0 and pos.x < MAP_WIDTH and pos.y >= 0 and pos.y < MAP_HEIGHT:
				grid[pos.x][pos.y] = STONE
				if bg_image:
					_paint_tile(pos.x, pos.y, COLOR_STONE)
					bg_dirty = true
	queue_redraw()

func _debug_set_plant_zone() -> void:
	var pos := _mouse_to_grid()
	if setting_zone_tl:
		zone_x0 = pos.x
		zone_y0 = pos.y
		print("Plant zone TOP-LEFT set to ", pos)
	else:
		zone_x1 = pos.x
		zone_y1 = pos.y
		print("Plant zone BOTTOM-RIGHT set to ", pos)
	
	# Update background colors to reflect new zone
	if bg_image:
		for x in range(MAP_WIDTH):
			for y in range(MAP_HEIGHT):
				_paint_tile(x, y, _tile_pixel_color(x, y, grid[x][y]))
		bg_dirty = true
	
	setting_zone_tl = !setting_zone_tl
	queue_redraw()

func _draw() -> void:
	if bg_texture:
		draw_texture(bg_texture, MAP_OFFSET)
	else:
		draw_rect(Rect2(MAP_OFFSET.x, MAP_OFFSET.y, MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE), Color(0.62, 0.48, 0.28))

	if plant_texture:
		var fw: float = plant_texture.get_width() / 3.0
		var fh: float = plant_texture.get_height()
		for pos in plant_ages:
			var px: float = MAP_OFFSET.x + pos.x * TILE_SIZE
			var py: float = MAP_OFFSET.y + pos.y * TILE_SIZE
			var region := Rect2(fw * 2, 0, fw, fh)
			draw_texture_rect_region(plant_texture, Rect2(px, py, TILE_SIZE, TILE_SIZE), region)

	for p in predators: _draw_animal(p, COLOR_PREDATOR, predator_texture)
	for a in apexes:    _draw_animal(a, COLOR_APEX,     apex_texture)

	draw_rect(Rect2(MAP_OFFSET.x, MAP_OFFSET.y, MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE), Color.YELLOW, false, 2.0)
	draw_rect(
		Rect2(MAP_OFFSET.x + zone_x0 * TILE_SIZE, MAP_OFFSET.y + zone_y0 * TILE_SIZE,
			  (zone_x1 - zone_x0) * TILE_SIZE, (zone_y1 - zone_y0) * TILE_SIZE),
		Color(0.9, 0.8, 0.4, 0.5), false, 1.0)
	var gx := MAP_OFFSET.x + goal_x * TILE_SIZE
	var gy := MAP_OFFSET.y + goal_y * TILE_SIZE
	var gs := GOAL_SIZE * TILE_SIZE
	draw_rect(Rect2(gx, gy, gs, gs), Color(0.7, 0.2, 0.9, 0.25))
	draw_rect(Rect2(gx, gy, gs, gs), Color(0.8, 0.3, 1.0), false, 2.0)

	_draw_genome_panel()
	_draw_population_graph()

func _draw_animal(animal: Animal, color: Color, texture: Texture2D) -> void:
	if animal.pos.x < 0 or animal.pos.y < 0 or animal.pos.x + ANIMAL_SIZE > MAP_WIDTH or animal.pos.y + ANIMAL_SIZE > MAP_HEIGHT:
		return
	var px: float = MAP_OFFSET.x + animal.pos.x * TILE_SIZE
	var py: float = MAP_OFFSET.y + animal.pos.y * TILE_SIZE
	var w: float = ANIMAL_SIZE * TILE_SIZE
	var h: float = ANIMAL_SIZE * TILE_SIZE
	if texture:
		var fw: float = texture.get_width()  / 4.0
		var fh: float = texture.get_height() / 4.0
		var col: int = _facing_col(animal.facing)
		var row: int = 0 if animal.is_full else 1
		var region := Rect2(col * fw, row * fh, fw, fh)
		draw_texture_rect_region(texture, Rect2(px, py, w, h), region)
	else:
		draw_rect(Rect2(px, py, w, h), color)

func _facing_col(facing: Vector2i) -> int:
	match facing:
		Vector2i(1,  0): return 0
		Vector2i(-1, 0): return 1
		Vector2i(0, -1): return 2
		_:               return 3

# ---- GENOME PANEL ----

func _draw_genome_panel() -> void:
	var font := ThemeDB.fallback_font
	var n := GENOME_IDS.size()
	var panel_h: int = GENOME_TITLE_H + n * (GENOME_SLOT_H + GENOME_GAP) + 8
	var screen_bot: int = int(MAP_OFFSET.y) + MAP_HEIGHT * TILE_SIZE
	var px: int = GENOME_PANEL_X
	var py: int = screen_bot - panel_h - 8

	draw_rect(Rect2(px - 4, py - 4, GENOME_SLOT_W + 12, panel_h + 8), Color(0, 0, 0, 0.80))
	draw_rect(Rect2(px - 4, py - 4, GENOME_SLOT_W + 12, panel_h + 8), Color(0.5, 0.5, 0.5), false, 1.5)
	draw_string(font, Vector2(px + 2, py + 15), "PLANT GENOME", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.9, 0.9))

	for i in range(n):
		var gid: String = GENOME_IDS[i]
		var g: Dictionary = genomes[gid]
		var sy: int = py + GENOME_TITLE_H + i * (GENOME_SLOT_H + GENOME_GAP)
		var sr := Rect2(px, sy, GENOME_SLOT_W, GENOME_SLOT_H)

		var bg_col: Color = Color(0.06, 0.22, 0.06) if g["unlocked"] else Color(0.10, 0.10, 0.10)
		draw_rect(sr, bg_col)
		var border_col: Color = Color(0.25, 0.85, 0.3) if g["unlocked"] else Color(0.32, 0.32, 0.32)
		draw_rect(sr, border_col, false, 1.0)
		draw_rect(Rect2(px + 3, sy + 5, 8, GENOME_SLOT_H - 10), g["color"])
		draw_string(font, Vector2(px + 16, sy + 20), g["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)

		if g["unlocked"]:
			draw_string(font, Vector2(px + GENOME_SLOT_W - 58, sy + 20), "ACTIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 1.0, 0.4))
		else:
			var can_afford: bool = available_seeds >= g["cost"]
			var cost_col: Color = Color(1.0, 0.85, 0.3) if can_afford else Color(0.6, 0.5, 0.2)
			draw_string(font, Vector2(px + GENOME_SLOT_W - 76, sy + 20), "%d seeds" % g["cost"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, cost_col)

func _get_clicked_genome(mp: Vector2) -> String:
	var n := GENOME_IDS.size()
	var panel_h: int = GENOME_TITLE_H + n * (GENOME_SLOT_H + GENOME_GAP) + 8
	var screen_bot: int = int(MAP_OFFSET.y) + MAP_HEIGHT * TILE_SIZE
	var py: int = screen_bot - panel_h - 8
	for i in range(n):
		var sy: int = py + GENOME_TITLE_H + i * (GENOME_SLOT_H + GENOME_GAP)
		if Rect2(GENOME_PANEL_X, sy, GENOME_SLOT_W, GENOME_SLOT_H).has_point(mp):
			return GENOME_IDS[i]
	return ""

func _buy_genome(gid: String) -> void:
	var g: Dictionary = genomes[gid]
	if g["unlocked"]: return
	if available_seeds < g["cost"]: return
	available_seeds -= g["cost"]
	g["unlocked"] = true
	update_ui()
	queue_redraw()

# ---- TILE HELPERS ----

func _tile_pixel_color(x: int, y: int, tile_id: int) -> Color:
	match tile_id:
		MATURE: return COLOR_MATURE
		FAR_MATURE: return COLOR_FAR_MATURE
		SUPER:  return COLOR_SUPER
		DUNG:   return COLOR_DUNG
		POISON_PLANT: return COLOR_POISON
		WATER:  return COLOR_WATER
		STONE:  return COLOR_STONE
		_:
			var hash_idx: int = (x * 7 + y * 11 + (x ^ y) * 3) % 6
			if x < zone_x0 or x >= zone_x1 or y < zone_y0 or y >= zone_y1:
				return COLOR_ARID_VARIANTS[hash_idx]
			else:
				return COLOR_DESERT_VARIANTS[hash_idx]

func _paint_tile(x: int, y: int, color: Color) -> void:
	var px: int = x * TILE_SIZE
	var py: int = y * TILE_SIZE
	for tx in range(TILE_SIZE):
		for ty in range(TILE_SIZE):
			bg_image.set_pixel(px + tx, py + ty, color)

func _tile_colour(id: int) -> Color:
	match id:
		GRASS:  return COLOR_GRASS
		SUPER:  return COLOR_SUPER
		MATURE: return COLOR_MATURE
		DUNG:   return COLOR_DUNG
		_:      return COLOR_EMPTY

func _init_grid() -> void:
	grid = []
	mature_set.clear()
	edge_list.clear()
	edge_set.clear()
	edge_idx.clear()
	for x in range(MAP_WIDTH):
		var col := []
		col.resize(MAP_HEIGHT)
		col.fill(EMPTY)
		grid.append(col)
	if bg_image:
		for x in range(MAP_WIDTH):
			for y in range(MAP_HEIGHT):
				_paint_tile(x, y, _tile_pixel_color(x, y, grid[x][y]))
		bg_dirty = true

func get_tile(pos: Vector2i) -> int:
	if pos.x < 0 or pos.x >= MAP_WIDTH or pos.y < 0 or pos.y >= MAP_HEIGHT: return -1
	return grid[pos.x][pos.y]

func set_tile(pos: Vector2i, id: int) -> void:
	if pos.x < 0 or pos.x >= MAP_WIDTH or pos.y < 0 or pos.y >= MAP_HEIGHT: return
	if grid[pos.x][pos.y] == WATER or grid[pos.x][pos.y] == STONE: return 
	grid[pos.x][pos.y] = id
	if id == MATURE or id == FAR_MATURE:
		plants_this_tick += 1
		mature_set[pos] = true
	else:
		mature_set.erase(pos)
	
	_update_edge_status(pos)
	for d in DIRS:
		_update_edge_status(pos + d)
		
	if bg_image:
		_paint_tile(pos.x, pos.y, _tile_pixel_color(pos.x, pos.y, id))
		bg_dirty = true

func _is_on_edge(pos: Vector2i) -> bool:
	if not mature_set.has(pos): return false
	for d in DIRS:
		var n: Vector2i = pos + d
		if get_tile(n) == EMPTY and not _in_river(n):
			return true
	return false

func _update_edge_status(pos: Vector2i) -> void:
	if _is_on_edge(pos):
		if not edge_set.has(pos):
			edge_idx[pos] = edge_list.size()
			edge_list.append(pos)
			edge_set[pos] = true
	else:
		if edge_set.has(pos):
			var idx: int = edge_idx[pos]
			var last: Vector2i = edge_list[edge_list.size() - 1]
			edge_list[idx] = last
			edge_idx[last] = idx
			edge_list.resize(edge_list.size() - 1)
			edge_idx.erase(pos)
			edge_set.erase(pos)

func _draw_population_graph() -> void:
	if graph_history.is_empty(): return
	var font := ThemeDB.fallback_font
	var view_size := get_viewport_rect().size
	var px: int = int(view_size.x) - GRAPH_W - 12
	var py: int = int(view_size.y) - GRAPH_H - 28 # Moved up to fit legend
	
	# Background
	draw_rect(Rect2(px - 4, py - 4, GRAPH_W + 8, GRAPH_H + 24), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(px - 4, py - 4, GRAPH_W + 8, GRAPH_H + 24), Color.GRAY, false, 1.0)
	draw_string(font, Vector2(px, py - 8), "POPULATION HISTORY", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

	# Find max for scaling
	var max_val: float = 1.0
	for sample in graph_history:
		max_val = max(max_val, sample[0], sample[1], sample[2] * 0.05) # Scale plant down for graph

	# Draw lines
	var step: float = float(GRAPH_W) / GRAPH_MAX_SAMPLES
	for i in range(1, graph_history.size()):
		var s0 = graph_history[i-1]
		var s1 = graph_history[i]
		var x0 = px + (i-1) * step
		var x1 = px + i * step
		
		# Herbivores (Red)
		draw_line(Vector2(x0, py + GRAPH_H - (s0[0]/max_val)*GRAPH_H), Vector2(x1, py + GRAPH_H - (s1[0]/max_val)*GRAPH_H), COLOR_PREDATOR, 1.5)
		# Apexes (Blue)
		draw_line(Vector2(x0, py + GRAPH_H - (s0[1]/max_val)*GRAPH_H), Vector2(x1, py + GRAPH_H - (s1[1]/max_val)*GRAPH_H), COLOR_APEX, 1.5)
		# Plants (Green - scaled)
		draw_line(Vector2(x0, py + GRAPH_H - (s0[2]*0.05/max_val)*GRAPH_H), Vector2(x1, py + GRAPH_H - (s1[2]*0.05/max_val)*GRAPH_H), COLOR_MATURE, 1.0)

	# Legend
	var cur = graph_history.back()
	var lx = px
	var ly = py + GRAPH_H + 12
	draw_string(font, Vector2(lx, ly), "H:%d" % cur[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COLOR_PREDATOR)
	draw_string(font, Vector2(lx + 40, ly), "A:%d" % cur[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COLOR_APEX)
	draw_string(font, Vector2(lx + 80, ly), "P:%d" % cur[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COLOR_MATURE)

func _mouse_to_grid() -> Vector2i:
	var mp := get_global_mouse_position()
	return Vector2i(
		int((mp.x - MAP_OFFSET.x) / TILE_SIZE),
		int((mp.y - MAP_OFFSET.y) / TILE_SIZE)
	)

func _add_seeds(amount: int) -> void:
	available_seeds = mini(available_seeds + amount, SEED_CAP)

func _is_plant(id: int) -> bool:
	return id == GRASS or id == SUPER or id == MATURE or id == FAR_MATURE or id == POISON_PLANT

func _in_plant_zone(pos: Vector2i) -> bool:
	return pos.x >= zone_x0 and pos.x < zone_x1 and pos.y >= zone_y0 and pos.y < zone_y1

func _in_goal_zone(pos: Vector2i) -> bool:
	return pos.x >= goal_x and pos.x < goal_x + GOAL_SIZE and pos.y >= goal_y and pos.y < goal_y + GOAL_SIZE

func _in_river(pos: Vector2i) -> bool:
	return get_tile(pos) == WATER

func _find_poop_target(from: Vector2i) -> Vector2i:
	for _i in range(30):
		var tx: int = clampi(from.x + randi_range(-10, 10), 0, MAP_WIDTH - 1)
		var ty: int = clampi(from.y + randi_range(-10, 10), 0, MAP_HEIGHT - 1)
		var t := Vector2i(tx, ty)
		var tt: int = get_tile(t)
		if abs(tx - from.x) + abs(ty - from.y) >= POOP_MIN_DIST and (tt == EMPTY or tt == GRASS) and not _in_river(t):
			return t
	return Vector2i(-1, -1)

func _count_goal_plants() -> int:
	var count = 0
	for x in range(goal_x, goal_x + GOAL_SIZE):
		for y in range(goal_y, goal_y + GOAL_SIZE):
			if x >= 0 and x < MAP_WIDTH and y >= 0 and y < MAP_HEIGHT:
				if _is_plant(grid[x][y]): count += 1
	return count

# ---- SIMULATION ----

func run_simulation_step() -> void:
	plants_this_tick = 0
	if predators.size() < 5 or (herbivore_auto_spawn and (predators.size() == 0 or randf() < 0.04)):
		spawn_red_invader()
	run_plant_logic()
	#print("Plants spawned: %d | Active Edges: %d" % [plants_this_tick, edge_list.size()])
	
	graph_history.append([predators.size(), apexes.size(), mature_set.size()])
	if graph_history.size() > GRAPH_MAX_SAMPLES:
		graph_history.pop_front()
		
	update_ui()
	queue_redraw()
	var life := _count_life()
	if life == 0 and available_seeds == 0:
		score_label.text = "GAME OVER — Extinction!"
		game_active = false
		restart_button.show()

func _count_life() -> int:
	return mature_set.size() + plant_ages.size()

func plant_seed() -> void:
	if available_seeds < COST_GRASS: return
	var center := _mouse_to_grid()
	if not _in_plant_zone(center): return
	var placed := false
	for dx in range(-5, 5):
		for dy in range(-5, 5):
			var pos := Vector2i(center.x + dx, center.y + dy)
			if get_tile(pos) == EMPTY and _in_plant_zone(pos):
				set_tile(pos, MATURE)
				placed = true
	if placed:
		available_seeds -= COST_GRASS
	update_ui()

func run_plant_logic() -> void:
	# Ripen dung into plants
	for pos in dung_ages.keys().duplicate():
		if get_tile(pos) != DUNG:
			dung_ages.erase(pos)
			continue
		dung_ages[pos] += 1
		if dung_ages[pos] >= DUNG_RIPEN_TICKS:
			set_tile(pos, MATURE)
			dung_ages.erase(pos)

	for pos in plant_ages.keys().duplicate():
		if get_tile(pos) != SUPER:
			plant_ages.erase(pos)
			continue
		var age: int = plant_ages[pos] + 1
		plant_ages[pos] = age
		if age >= SUPER_LIFESPAN:
			set_tile(pos, MATURE)
			plant_ages.erase(pos)
		elif randf() < 0.025:
			_spread_from_super(pos)

	# Apply genome effects to spread
	var spread_prob: float = 0.10 if genomes["speed"]["unlocked"] else 0.05

	var n := edge_list.size()
	if n > 0:
		var count := mini(MAX_SPREAD_PER_TICK, n)
		for i in range(count):
			var pos: Vector2i = edge_list.pick_random()
			var current_tile = get_tile(pos)
			
			for d in DIRS:
				var neighbor: Vector2i = pos + d
				if get_tile(neighbor) == EMPTY and randf() < spread_prob and not _in_river(neighbor):
					var next_id = MATURE
					if genomes["poison"]["unlocked"] and randf() < 0.001:
						next_id = POISON_PLANT
					elif genomes["range"]["unlocked"] and randf() < 0.05:
						next_id = FAR_MATURE
					set_tile(neighbor, next_id)
					if randf() < 0.10: _add_seeds(1)
			
			# Far Spread genome: Only FAR_MATURE can spread 10-15 blocks away (5% chance per tick)
			if current_tile == FAR_MATURE and randf() < 0.05:
				var fly_angle: float = randf() * TAU
				var fly_dist: float = randf_range(10.0, 15.0)
				var fly_pos := Vector2i(
					clampi(pos.x + int(cos(fly_angle) * fly_dist), 0, MAP_WIDTH - 1),
					clampi(pos.y + int(sin(fly_angle) * fly_dist), 0, MAP_HEIGHT - 1)
				)
				if get_tile(fly_pos) == EMPTY and not _in_river(fly_pos):
					set_tile(fly_pos, MATURE)

func _spread_from_super(parent: Vector2i) -> void:
	var jump := Vector2i(randi_range(-8, 8), randi_range(-8, 8))
	if jump == Vector2i.ZERO: return
	var new_pos: Vector2i = parent + jump
	if get_tile(new_pos) != EMPTY or _in_river(new_pos): return
	set_tile(new_pos, MATURE)

func _erase_plant_data(pos: Vector2i) -> void:
	plant_ages.erase(pos)

func _random_edge_pos() -> Vector2i:
	match randi_range(0, 3):
		0: return Vector2i(randi_range(0, MAP_WIDTH - 1), 0)
		1: return Vector2i(randi_range(0, MAP_WIDTH - 1), MAP_HEIGHT - 1)
		2: return Vector2i(0, randi_range(0, MAP_HEIGHT - 1))
		_: return Vector2i(MAP_WIDTH - 1, randi_range(0, MAP_HEIGHT - 1))

func spawn_red_invader() -> void:
	var _a := Animal.new()
	_a.pos = _random_edge_pos()
	_a.facing = DIRS.pick_random()
	predators.append(_a)

func spawn_apex_invader() -> void:
	var apex_pos := _random_edge_pos()
	var _a := Animal.new()
	_a.pos = apex_pos
	_a.facing = DIRS.pick_random()
	_a.home = apex_pos
	apexes.append(_a)

func _find_plant_in_rect(rect: Rect2i) -> Vector2i:
	var start_x = max(0, rect.position.x)
	var start_y = max(0, rect.position.y)
	var end_x = min(MAP_WIDTH, rect.position.x + rect.size.x)
	var end_y = min(MAP_HEIGHT, rect.position.y + rect.size.y)
	var found = []
	for x in range(start_x, end_x):
		for y in range(start_y, end_y):
			if _is_plant(grid[x][y]):
				found.append(Vector2i(x, y))
	if found.is_empty():
		return Vector2i(-1, -1)
	return found.pick_random()

func _eat_all_plants_in_rect(rect: Rect2i) -> int:
	var start_x = max(0, rect.position.x)
	var start_y = max(0, rect.position.y)
	var end_x = min(MAP_WIDTH, rect.position.x + rect.size.x)
	var end_y = min(MAP_HEIGHT, rect.position.y + rect.size.y)
	var eaten_count = 0
	for x in range(start_x, end_x):
		for y in range(start_y, end_y):
			var pos = Vector2i(x, y)
			if _is_plant(grid[x][y]):
				_erase_plant_data(pos)
				set_tile(pos, EMPTY)
				eaten_count += 1
	return eaten_count

func _try_move(animal: Animal, dir: Vector2i) -> bool:
	var new_pos = animal.pos + dir
	if new_pos.x < 0 or new_pos.y < 0 or new_pos.x + ANIMAL_SIZE > MAP_WIDTH or new_pos.y + ANIMAL_SIZE > MAP_HEIGHT:
		return false
	
	var on_stone := false
	for x in range(new_pos.x, new_pos.x + ANIMAL_SIZE):
		for y in range(new_pos.y, new_pos.y + ANIMAL_SIZE):
			if grid[x][y] == STONE:
				on_stone = true
				break
		if on_stone: break
	
	if on_stone:
		animal.move_wait = 4 # Substantial delay = very slow movement
		
	animal.pos = new_pos
	return true

func _try_spawn_offspring(parent_pos: Vector2i, list: Array, home: Vector2i = Vector2i(-1, -1)) -> void:
	var dirs = DIRS.duplicate()
	dirs.shuffle()
	for d in dirs:
		var new_pos = parent_pos + d * ANIMAL_SIZE
		if new_pos.x >= 0 and new_pos.y >= 0 and new_pos.x + ANIMAL_SIZE <= MAP_WIDTH and new_pos.y + ANIMAL_SIZE <= MAP_HEIGHT:
			var _a := Animal.new()
			_a.pos = new_pos
			_a.facing = d
			if home != Vector2i(-1, -1):
				_a.home = new_pos
			list.append(_a)
			return

# ---- HERBIVORE LOGIC ----

func run_predator_logic() -> void:
	var alive = []
	for p in predators:
		if alive.size() >= MAX_HERBIVORES: break
		
		if p.move_wait > 0:
			p.move_wait -= 1
			alive.append(p)
			continue

		for i in range(1):
			if not p.is_full:
				var plant_pos = _find_plant_in_rect(Rect2i(p.pos.x, p.pos.y, ANIMAL_SIZE, ANIMAL_SIZE))
				if plant_pos != Vector2i(-1, -1):
					var tile_type = get_tile(plant_pos)
					_erase_plant_data(plant_pos)
					set_tile(plant_pos, EMPTY)
					
					if tile_type == POISON_PLANT:
						print("[DEATH] Herbivore: Poison at ", p.pos)
						p.starve_timer = STARVE_LIMIT + 1 # Instant death
						continue
						
					p.stomach += 1
					p.full_timer = 0
					p.starve_timer = 0
					# Poison genome: eating may hurt the herbivore
					if genomes["poison"]["unlocked"] and randf() < 0.3:
						p.thirst += 60
					if p.stomach >= HERB_STOMACH_CAP:
						if randf() < BIRTH_SUCCESS_CHANCE:
							_try_spawn_offspring(p.pos, alive)
							p.stomach = 0
						else:
							var pt: Vector2i = _find_poop_target(p.pos)
							if pt != Vector2i(-1, -1):
								p.is_full = true
								p.poop_target = pt
							else:
								p.stomach = 0

			if p.is_full and p.poop_target != Vector2i(-1, -1):
				var poop_tile: int = get_tile(p.poop_target)
				if poop_tile != EMPTY and poop_tile != GRASS:
					p.poop_target = _find_poop_target(p.pos)
				elif p.pos == p.poop_target or (abs(p.pos.x - p.poop_target.x) <= 1 and abs(p.pos.y - p.poop_target.y) <= 1):
					set_tile(p.poop_target, DUNG)
					dung_ages[p.poop_target] = 0
					p.stomach = 0
					p.is_full = false
					p.poop_target = Vector2i(-1, -1)
					# Migration: Force move away from the poop so the plant can actually grow
					var angle: float = randf() * TAU
					var dist: int = randi_range(30, 45)
					p.wander_target = Vector2i(
						clampi(p.pos.x + int(cos(angle) * dist), 0, MAP_WIDTH - 1),
						clampi(p.pos.y + int(sin(angle) * dist), 0, MAP_HEIGHT - 1)
					)
					p.wander_cd = 400
					p.target = Vector2i(-1, -1)

			var moved := false
			if randf() < 0.2:
				moved = true
			# Flee from nearest apex until 35 tiles away
			if not moved:
				for a in apexes:
					var dx: int = p.pos.x - a.pos.x
					var dy: int = p.pos.y - a.pos.y
					if abs(dx) <= 35 and abs(dy) <= 35:
						var flee_step := Vector2i(signi(dx), 0) if abs(dx) >= abs(dy) else Vector2i(0, signi(dy))
						if _try_move(p, flee_step):
							p.facing = flee_step
							moved = true
						break
			# Drink when in river
			if _in_river(p.pos): p.thirst = 0
			# Seek water when thirsty (Higher priority than food)
			if not moved and p.thirst >= THIRST_DANGER:
				if p.water_target != Vector2i(-1, -1):
					var w_diff: Vector2i = p.water_target - p.pos
					var w_step: Vector2i = Vector2i(signi(w_diff.x), 0) if abs(w_diff.x) >= abs(w_diff.y) else Vector2i(0, signi(w_diff.y))
					if _try_move(p, w_step):
						p.facing = w_step
						moved = true
				else:
					# Blind search: walk 10 ticks in same direction, then scan (using scan_cd logic)
					if not _try_move(p, p.facing):
						p.facing = DIRS.pick_random()
						_try_move(p, p.facing)
					moved = true
			if not moved and _in_river(p.pos) and randf() < 0.6:
				moved = true
			if not moved:
				for other in predators:
					if other == p: continue
					var dx: int = p.pos.x - other.pos.x
					var dy: int = p.pos.y - other.pos.y
					if abs(dx) <= 3 and abs(dy) <= 3:
						var flee_step := Vector2i(signi(dx), 0) if abs(dx) >= abs(dy) else Vector2i(0, signi(dy))
						if _try_move(p, flee_step):
							p.facing = flee_step
							moved = true
						break

			if not moved and p.is_full and p.poop_target != Vector2i(-1, -1):
				var poop_diff: Vector2i = p.poop_target - p.pos
				var poop_step: Vector2i = Vector2i(signi(poop_diff.x), 0) if abs(poop_diff.x) >= abs(poop_diff.y) else Vector2i(0, signi(poop_diff.y))
				if _try_move(p, poop_step):
					p.facing = poop_step
					moved = true

			if p.scan_cd <= 0:
				p.scan_cd = SCAN_INTERVAL
				var ppos: Vector2i = p.pos
				var sx: int = max(0, ppos.x - VISION_RANGE)
				var sy: int = max(0, ppos.y - VISION_RANGE)
				var ex: int = min(MAP_WIDTH,  ppos.x + VISION_RANGE)
				var ey: int = min(MAP_HEIGHT, ppos.y + VISION_RANGE)
				
				# Scan for plants if hungry
				if not p.is_full:
					var best_plant := Vector2i(-1, -1)
					var best_dist := 9999
					for bx in range(sx, ex):
						for by in range(sy, ey):
							if _is_plant(grid[bx][by]):
								var d: int = abs(bx - ppos.x) + abs(by - ppos.y)
								if d < best_dist:
									best_dist = d
									best_plant = Vector2i(bx, by)
					p.target = best_plant
				else:
					p.target = Vector2i(-1, -1)

				# Scan for water
				var best_water := Vector2i(-1, -1)
				var best_w_dist := 9999
				for bx in range(sx, ex):
					for by in range(sy, ey):
						if grid[bx][by] == WATER:
							var d: int = abs(bx - ppos.x) + abs(by - ppos.y)
							if d < best_w_dist:
								best_w_dist = d
								best_water = Vector2i(bx, by)
				p.water_target = best_water
			else:
				p.scan_cd -= 1

			if not moved and p.target != Vector2i(-1, -1):
				if _is_plant(get_tile(p.target)):
					var target_diff: Vector2i = p.target - p.pos
					var target_step: Vector2i = Vector2i(signi(target_diff.x), 0) if abs(target_diff.x) >= abs(target_diff.y) else Vector2i(0, signi(target_diff.y))
					if _try_move(p, target_step):
						p.facing = target_step
						moved = true
				else:
					p.target = Vector2i(-1, -1)

			p.wander_cd -= 1
			if p.wander_cd <= 0:
				p.wander_cd = 400
				var angle: float = randf() * TAU
				var wx: int = clampi(p.pos.x + int(cos(angle) * 20), 0, MAP_WIDTH - 1)
				var wy: int = clampi(p.pos.y + int(sin(angle) * 20), 0, MAP_HEIGHT - 1)
				p.wander_target = Vector2i(wx, wy)
			if not moved and p.wander_target != Vector2i(-1, -1):
				var wander_diff: Vector2i = p.wander_target - p.pos
				if abs(wander_diff.x) + abs(wander_diff.y) <= 2:
					p.wander_target = Vector2i(-1, -1)
					p.wander_cd = 0
				else:
					var wander_step: Vector2i = Vector2i(signi(wander_diff.x), 0) if abs(wander_diff.x) >= abs(wander_diff.y) else Vector2i(0, signi(wander_diff.y))
					if _try_move(p, wander_step):
						p.facing = wander_step
						moved = true
					else:
						var wander_dirs = DIRS.duplicate()
						wander_dirs.shuffle()
						for d in wander_dirs:
							if _try_move(p, d):
								p.facing = d
								moved = true
								break

			p.full_timer += 1
			if p.full_timer >= FULL_DURATION:
				p.is_full = false
			if not p.is_full:
				p.starve_timer += 1
			p.thirst += 1
			if p.starve_timer >= STARVE_LIMIT:
				print("[DEATH] Herbivore: Starvation at ", p.pos)
				break
			if p.thirst >= THIRST_LIMIT:
				print("[DEATH] Herbivore: Thirst at ", p.pos)
				break

		if p.starve_timer < STARVE_LIMIT and p.thirst < THIRST_LIMIT:
			alive.append(p)
	predators = alive

# ---- APEX LOGIC ----

func run_apex_logic() -> void:
	var alive = []
	for a in apexes:
		if alive.size() >= MAX_APEXES: break
		
		if a.move_wait > 0:
			a.move_wait -= 1
			alive.append(a)
			continue

		for i in range(1):
			if a.eat_cd > 0:
				a.eat_cd -= 1
			var my_rect = Rect2i(a.pos.x, a.pos.y, ANIMAL_SIZE, ANIMAL_SIZE)
			if a.eat_cd == 0:
				for j in range(predators.size() - 1, -1, -1):
					if j >= predators.size(): continue
					var eat_rect = Rect2i(predators[j].pos.x, predators[j].pos.y, ANIMAL_SIZE, ANIMAL_SIZE)
					if my_rect.intersects(eat_rect):
						predators.remove_at(j)
						a.stomach += 1
						a.eat_cd = 50
						a.rest_timer = 100
						a.starve_timer = 0
						while a.stomach >= APEX_FOOD_TO_BREED:
							a.stomach -= APEX_FOOD_TO_BREED
							_try_spawn_offspring(a.pos, alive, a.home)
						break

			if a.rest_timer > 0 and a.home != Vector2i(-1, -1):
				var rest_home_dist: int = abs(a.pos.x - a.home.x) + abs(a.pos.y - a.home.y)
				if rest_home_dist <= 3:
					a.rest_timer -= 1
			var best_p = null
			if a.rest_timer == 0:
				var view_rect = Rect2i(a.pos.x - APEX_SCAN_RANGE, a.pos.y - APEX_SCAN_RANGE, ANIMAL_SIZE + APEX_SCAN_RANGE * 2, ANIMAL_SIZE + APEX_SCAN_RANGE * 2)
				var best_dist = 9999
				for p in predators:
					var scan_rect = Rect2i(p.pos.x, p.pos.y, ANIMAL_SIZE, ANIMAL_SIZE)
					if view_rect.intersects(scan_rect):
						var dist = abs(p.pos.x - a.pos.x) + abs(p.pos.y - a.pos.y)
						if dist < best_dist:
							best_dist = dist
							best_p = p

			if a.scan_cd <= 0:
				a.scan_cd = SCAN_INTERVAL
				var ppos: Vector2i = a.pos
				var sx: int = max(0, ppos.x - VISION_RANGE)
				var sy: int = max(0, ppos.y - VISION_RANGE)
				var ex: int = min(MAP_WIDTH,  ppos.x + VISION_RANGE)
				var ey: int = min(MAP_HEIGHT, ppos.y + VISION_RANGE)
				var best_water := Vector2i(-1, -1)
				var best_w_dist := 9999
				for bx in range(sx, ex):
					for by in range(sy, ey):
						if grid[bx][by] == WATER:
							var d: int = abs(bx - ppos.x) + abs(by - ppos.y)
							if d < best_w_dist:
								best_w_dist = d
								best_water = Vector2i(bx, by)
				a.water_target = best_water
			else:
				a.scan_cd -= 1

			if best_p == null and a.rest_timer == 0 and randf() < 0.05:
				a.facing = DIRS.pick_random()

			var moved: bool = a.eat_cd > 0
			if _in_river(a.pos): a.thirst = 0
			# Seek water when thirsty (Higher priority than food/hunt)
			if not moved and a.thirst >= THIRST_DANGER:
				if a.water_target != Vector2i(-1, -1):
					var w_diff: Vector2i = a.water_target - a.pos
					var w_step: Vector2i = Vector2i(signi(w_diff.x), 0) if abs(w_diff.x) >= abs(w_diff.y) else Vector2i(0, signi(w_diff.y))
					if _try_move(a, w_step):
						a.facing = w_step
						moved = true
				else:
					# Blind search: walk in same direction to find water
					if not _try_move(a, a.facing):
						a.facing = DIRS.pick_random()
						_try_move(a, a.facing)
					moved = true
			if _in_river(a.pos) and randf() < 0.6:
				moved = true
			if not moved and best_p != null:
				var chase_diff: Vector2i = best_p.pos - a.pos
				var chase_step: Vector2i = Vector2i(signi(chase_diff.x), 0) if abs(chase_diff.x) >= abs(chase_diff.y) else Vector2i(0, signi(chase_diff.y))
				if _try_move(a, chase_step):
					a.facing = chase_step
					moved = true

			if a.rest_timer > 0 and a.home != Vector2i(-1, -1):
				var rest_home_dist: int = abs(a.pos.x - a.home.x) + abs(a.pos.y - a.home.y)
				if not moved and rest_home_dist > 3:
					var rest_diff: Vector2i = a.home - a.pos
					var rest_step: Vector2i = Vector2i(signi(rest_diff.x), 0) if abs(rest_diff.x) >= abs(rest_diff.y) else Vector2i(0, signi(rest_diff.y))
					if _try_move(a, rest_step):
						a.facing = rest_step
						moved = true
				moved = true
			elif not moved and best_p == null and a.home != Vector2i(-1, -1):
				var return_home_dist: int = abs(a.pos.x - a.home.x) + abs(a.pos.y - a.home.y)
				if return_home_dist > 3:
					var return_diff: Vector2i = a.home - a.pos
					var return_step: Vector2i = Vector2i(signi(return_diff.x), 0) if abs(return_diff.x) >= abs(return_diff.y) else Vector2i(0, signi(return_diff.y))
					if _try_move(a, return_step):
						a.facing = return_step
						moved = true
			if not moved:
				if _try_move(a, a.facing):
					moved = true
				else:
					var wander_dirs = DIRS.duplicate()
					wander_dirs.shuffle()
					for d in wander_dirs:
						if _try_move(a, d):
							a.facing = d
							moved = true
							break

			if randf() < 0.4 and a.eat_cd == 0 and a.rest_timer == 0:
				_try_move(a, a.facing)

			a.starve_timer += 1
			a.thirst += 1
			if a.starve_timer >= APEX_STARVE_LIMIT:
				print("[DEATH] Apex: Starvation at ", a.pos)
				break
			if a.thirst >= THIRST_LIMIT:
				print("[DEATH] Apex: Thirst at ", a.pos)
				break

		if a.starve_timer < APEX_STARVE_LIMIT and a.thirst < THIRST_LIMIT:
			alive.append(a)
	apexes = alive

# ---- UI ----

func update_ui() -> void:
	seed_label.text = "Seeds: %d / %d" % [available_seeds, SEED_CAP]
	var goal_plants := _count_goal_plants()
	score_label.text = "Goal: %d / %d" % [goal_plants, GOAL_FILL_TARGET]
	if goal_plants >= GOAL_FILL_TARGET and game_active:
		score_label.text = "VICTORY! Goal area covered!"
		game_active = false
		restart_button.show()

func _on_restart_button_pressed() -> void:
	available_seeds  = 20
	time_passed      = 0.0
	animal_time      = 0.0
	game_active      = true
	predators.clear()
	apexes.clear()
	plant_ages.clear()
	dung_ages.clear()
	mature_set.clear()
	edge_list.clear()
	edge_set.clear()
	edge_idx.clear()
	for gid in GENOME_IDS:
		genomes[gid]["unlocked"] = false
	graph_history.clear()
	_init_grid()
	update_ui()
	score_label.text = "Goal: 0 / %d" % GOAL_FILL_TARGET
	restart_button.hide()
	queue_redraw()

# Stubs kept for scene signal compatibility
func _on_btn_grass_pressed() -> void: pass
func _on_btn_super_pressed() -> void: pass
func _on_btn_predator_pressed() -> void: pass
