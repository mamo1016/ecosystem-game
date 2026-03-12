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

# --- COLOURS ---
const COLOR_EMPTY    = Color(0.74, 0.60, 0.38)
const COLOR_DESERT_VARIANTS = [
	Color(0.85, 0.71, 0.44),  # pale sand
	Color(0.74, 0.58, 0.32),  # mid sand
	Color(0.68, 0.50, 0.26),  # dry ochre
	Color(0.80, 0.65, 0.38),  # warm sand
	Color(0.90, 0.76, 0.48),  # bright dune
	Color(0.65, 0.48, 0.24),  # dark earth
]
const COLOR_GRASS    = Color(0.25, 0.78, 0.18)
const COLOR_PREDATOR = Color(0.90, 0.10, 0.10)
const COLOR_SUPER    = Color(1.00, 0.88, 0.00)
const COLOR_APEX     = Color(0.15, 0.35, 0.95)
const COLOR_MATURE   = Color(0.04, 0.50, 0.12)
const COLOR_MATURE_VARIANTS = [
	Color(0.04, 0.50, 0.12),  # dark green
	Color(0.12, 0.68, 0.22),  # medium green
	Color(0.18, 0.38, 0.09),  # olive green
	Color(0.06, 0.55, 0.32),  # teal green
]

# --- MAP ---
var MAP_WIDTH  = 640
var MAP_HEIGHT = 360
const TILE_SIZE  = 4
const MAP_OFFSET = Vector2(0, 40)
const PLANT_ZONE_MARGIN = 0.22  # 22% margin on each side — center 56% is plantable

const COLOR_ARID_VARIANTS = [
	Color(0.52, 0.43, 0.36),  # gray-brown
	Color(0.47, 0.38, 0.30),  # dark rust
	Color(0.58, 0.44, 0.33),  # rusty tan
	Color(0.44, 0.37, 0.32),  # cool gray
	Color(0.55, 0.41, 0.28),  # rust ochre
	Color(0.42, 0.35, 0.28),  # deep rust
]

# --- COSTS ---
const COST_GRASS      = 3
const COST_SUPER      = 10
const COST_APEX_SPAWN = 30

# --- RED PREDATOR SETTINGS ---
const PLANTS_TO_REPRODUCE = 6
const BIRTH_SUCCESS_CHANCE = 0.6  # 60% chance to successfully give birth
const STARVATION_LIMIT    = 150
const EAT_TURNS           = 3
const MATURE_EAT_TURNS    = 4
const HERBIVORE_LIFESPAN  = 1000  # ticks before natural death

# --- APEX PREDATOR SETTINGS ---
const APEX_REPRODUCE  = 3
const APEX_STARVATION = 360
const APEX_EAT_TURNS  = 3
const APEX_LIFESPAN   = 2000  # ticks before natural death

# --- VISION ---
const VISION_RANGE    = 30
const APEX_SCAN_RANGE = 30

# --- THIRST ---
const THIRST_LIMIT  = 200  # ticks before dying of thirst (20s)
const THIRST_DANGER = 140  # ticks before animal seeks water (14s)

# --- PLANT SETTINGS ---
const SUPER_LIFESPAN   = 80
const SEED_CAP         = 30
const GROWTH_PER_TICK  = 4
var   update_interval  = 0.1

# --- WIN CONDITION ---
const GOAL_SIZE        = 10     # 10x10 goal area outside the plant zone
const GOAL_FILL_TARGET = 50     # need 50/100 tiles covered to win
var   goal_x: int = 0
var   goal_y: int = 0

# --- RIVER ---
const RIVER_WIDTH = 5
var   river_x: int = 0

# --- STATE ---
var grid: Array          = []
var available_seeds: int = 20
var current_seed_id: int = GRASS
var time_passed: float   = 0.0
var animal_time: float   = 0.0
var game_active: bool    = true

var predators: Array = []
var apexes: Array = []
var plant_ages: Dictionary = {}

const DIRS = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]

var predator_texture: Texture2D
var apex_texture: Texture2D
var plant_texture: Texture2D

# Cached plant zone bounds (computed once in _ready after MAP size is known)
var zone_x0: int = 0
var zone_y0: int = 0
var zone_x1: int = 0
var zone_y1: int = 0

func _ready() -> void:
	# Calculate map dimension based on the ACTUAL window size, not the whole monitor
	var win_size = get_viewport().get_visible_rect().size
	MAP_WIDTH  = int(win_size.x / TILE_SIZE)
	MAP_HEIGHT = int((win_size.y - 40) / TILE_SIZE) # 40px for top UI bar
	
	var canvas = get_node_or_null("CanvasLayer")
	if canvas != null:
		var hbox = canvas.get_node_or_null("HBoxContainer")
		if hbox != null:
			hbox.position = Vector2(win_size.x / 2 - 300, win_size.y - 50)
		var btn = canvas.get_node_or_null("RestartButton")
		if btn != null:
			btn.position = Vector2(win_size.x / 2 - 150, win_size.y / 2 - 25)
	
	zone_x0 = int(MAP_WIDTH  * PLANT_ZONE_MARGIN)
	zone_y0 = int(MAP_HEIGHT * PLANT_ZONE_MARGIN)
	zone_x1 = int(MAP_WIDTH  * (1.0 - PLANT_ZONE_MARGIN))
	zone_y1 = int(MAP_HEIGHT * (1.0 - PLANT_ZONE_MARGIN))
	# River: just outside the plant zone right edge
	river_x = zone_x1 + 2
	# Goal area: far right, past the river
	goal_x = MAP_WIDTH - GOAL_SIZE - 3
	goal_y = MAP_HEIGHT / 2 - GOAL_SIZE / 2

	_init_grid()
	update_button_visuals()
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
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:   plant_seed(current_seed_id)
			MOUSE_BUTTON_RIGHT:  _debug_spawn_predator()
			MOUSE_BUTTON_MIDDLE: _debug_spawn_apex()

func _debug_spawn_predator() -> void:
	var pos := _mouse_to_grid()
	pos.x = clampi(pos.x, 0, MAP_WIDTH - 1)
	pos.y = clampi(pos.y, 0, MAP_HEIGHT - 1)
	predators.append({ "pos": pos, "stomach": 0, "hunger": 0, "age": 0, "thirst": 0, "facing": DIRS.pick_random(), "size": 3 })
	queue_redraw()

func _debug_spawn_apex() -> void:
	var pos := _mouse_to_grid()
	pos.x = clampi(pos.x, 0, MAP_WIDTH - 1)
	pos.y = clampi(pos.y, 0, MAP_HEIGHT - 1)
	apexes.append({ "pos": pos, "stomach": 0, "hunger": 0, "age": 0, "thirst": 0, "facing": DIRS.pick_random(), "size": 3, "home": pos })
	queue_redraw()

func _draw() -> void:
	# Draw the "playground" background
	draw_rect(Rect2(MAP_OFFSET.x, MAP_OFFSET.y, MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE), Color(0.62, 0.48, 0.28)) # Desert background
	
	var sub_w: float = float(TILE_SIZE) / 10.0

	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var px: float = MAP_OFFSET.x + x * TILE_SIZE
			var py: float = MAP_OFFSET.y + y * TILE_SIZE
			var tile_id: int = grid[x][y]

			if tile_id == EMPTY:
				var hash_idx = (x * 7 + y * 11 + (x ^ y) * 3) % 6
				var empty_color: Color = COLOR_ARID_VARIANTS[hash_idx] if (x < zone_x0 or x >= zone_x1 or y < zone_y0 or y >= zone_y1) else COLOR_DESERT_VARIANTS[hash_idx]
				draw_rect(Rect2(px, py, TILE_SIZE, TILE_SIZE), empty_color)
			elif tile_id != EMPTY:
				if plant_texture:
					var fw: float = plant_texture.get_width() / 3.0
					var fh: float = plant_texture.get_height()
					var frame: int = 0
					match tile_id:
						GRASS:  frame = 0
						MATURE: frame = 1
						SUPER:  frame = 2
					var region := Rect2(frame * fw, 0, fw, fh)
					var bg_color := Color.WHITE
					if tile_id == MATURE:
						bg_color = COLOR_MATURE_VARIANTS[(x * 7 + y * 13) % 4]
					elif tile_id == SUPER:
						bg_color = COLOR_SUPER
					# Draw solid background first so transparent sprite pixels don't show the dark bg
					draw_rect(Rect2(px, py, TILE_SIZE, TILE_SIZE), bg_color)
					draw_texture_rect_region(plant_texture, Rect2(px, py, TILE_SIZE, TILE_SIZE), region)
				else:
					var col := _tile_colour(tile_id)
					if tile_id == MATURE:
						col = COLOR_MATURE_VARIANTS[(x * 7 + y * 13) % 4]
					draw_rect(Rect2(px, py, TILE_SIZE, TILE_SIZE), col)

	for p in predators: _draw_animal(p, COLOR_PREDATOR, predator_texture, STARVATION_LIMIT)
	for a in apexes:    _draw_animal(a, COLOR_APEX,     apex_texture,     APEX_STARVATION)

	draw_rect(Rect2(MAP_OFFSET.x, MAP_OFFSET.y, MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE), Color.YELLOW, false, 2.0)
	# Draw plant zone border
	draw_rect(
		Rect2(MAP_OFFSET.x + zone_x0 * TILE_SIZE, MAP_OFFSET.y + zone_y0 * TILE_SIZE,
			  (zone_x1 - zone_x0) * TILE_SIZE, (zone_y1 - zone_y0) * TILE_SIZE),
		Color(0.9, 0.8, 0.4, 0.5), false, 1.0)
	# Draw river (blue vertical strip between plant zone and goal zone)
	var rx := MAP_OFFSET.x + river_x * TILE_SIZE
	draw_rect(Rect2(rx, MAP_OFFSET.y, RIVER_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE), Color(0.1, 0.4, 0.9, 0.55))
	# River border lines
	draw_line(Vector2(rx, MAP_OFFSET.y), Vector2(rx, MAP_OFFSET.y + MAP_HEIGHT * TILE_SIZE), Color(0.2, 0.6, 1.0), 1.5)
	draw_line(Vector2(rx + RIVER_WIDTH * TILE_SIZE, MAP_OFFSET.y), Vector2(rx + RIVER_WIDTH * TILE_SIZE, MAP_OFFSET.y + MAP_HEIGHT * TILE_SIZE), Color(0.2, 0.6, 1.0), 1.5)
	# Draw goal zone (purple fill + bright border)
	var gx := MAP_OFFSET.x + goal_x * TILE_SIZE
	var gy := MAP_OFFSET.y + goal_y * TILE_SIZE
	var gs := GOAL_SIZE * TILE_SIZE
	draw_rect(Rect2(gx, gy, gs, gs), Color(0.7, 0.2, 0.9, 0.25))
	draw_rect(Rect2(gx, gy, gs, gs), Color(0.8, 0.3, 1.0), false, 2.0)

func _draw_animal(animal: Dictionary, color: Color, texture: Texture2D, starvation_limit: int) -> void:
	if animal.pos.x < 0 or animal.pos.y < 0 or animal.pos.x + animal.size > MAP_WIDTH or animal.pos.y + animal.size > MAP_HEIGHT:
		return
	var px: float = MAP_OFFSET.x + animal.pos.x * TILE_SIZE
	var py: float = MAP_OFFSET.y + animal.pos.y * TILE_SIZE
	var w: float = animal.size * TILE_SIZE
	var h: float = animal.size * TILE_SIZE
	if texture:
		var fw: float = texture.get_width()  / 4.0
		var fh: float = texture.get_height() / 4.0
		var col: int = _facing_col(animal.facing)
		var row: int = _hunger_row(animal.hunger, starvation_limit)
		var region := Rect2(col * fw, row * fh, fw, fh)
		draw_texture_rect_region(texture, Rect2(px, py, w, h), region)
	else:
		draw_rect(Rect2(px, py, w, h), color)

func _facing_col(facing: Vector2i) -> int:
	match facing:
		Vector2i(1,  0): return 0   # right
		Vector2i(-1, 0): return 1   # left
		Vector2i(0, -1): return 2   # up
		_:               return 3   # down

func _hunger_row(hunger: int, limit: int) -> int:
	var pct := float(hunger) / float(limit)
	if pct < 0.15: return 0   # full
	if pct < 0.40: return 1   # satisfied
	if pct < 0.70: return 2   # hungry
	return 3                   # starving

func _draw_facing_indicator(pos: Vector2i, facing: Vector2i, size: int) -> void:
	var cx: float = MAP_OFFSET.x + pos.x * TILE_SIZE + (size * TILE_SIZE) * 0.5
	var cy: float = MAP_OFFSET.y + pos.y * TILE_SIZE + (size * TILE_SIZE) * 0.5
	var s: float  = (size * TILE_SIZE) * 0.25
	var tip: Vector2
	var left_pt: Vector2
	var right_pt: Vector2
	match facing:
		Vector2i(0, -1):
			tip      = Vector2(cx, cy - s)
			left_pt  = Vector2(cx - s * 0.5, cy + s * 0.5)
			right_pt = Vector2(cx + s * 0.5, cy + s * 0.5)
		Vector2i(0, 1):
			tip      = Vector2(cx, cy + s)
			left_pt  = Vector2(cx - s * 0.5, cy - s * 0.5)
			right_pt = Vector2(cx + s * 0.5, cy - s * 0.5)
		Vector2i(-1, 0):
			tip      = Vector2(cx - s, cy)
			left_pt  = Vector2(cx + s * 0.5, cy - s * 0.5)
			right_pt = Vector2(cx + s * 0.5, cy + s * 0.5)
		_:
			tip      = Vector2(cx + s, cy)
			left_pt  = Vector2(cx - s * 0.5, cy - s * 0.5)
			right_pt = Vector2(cx - s * 0.5, cy + s * 0.5)
	draw_colored_polygon(PackedVector2Array([tip, left_pt, right_pt]), Color.WHITE)

func _tile_colour(id: int) -> Color:
	match id:
		GRASS:  return COLOR_GRASS
		SUPER:  return COLOR_SUPER
		MATURE: return COLOR_MATURE
		_:      return COLOR_EMPTY

func _init_grid() -> void:
	grid = []
	for x in range(MAP_WIDTH):
		var col := []
		col.resize(MAP_HEIGHT)
		col.fill(EMPTY)
		grid.append(col)

func get_tile(pos: Vector2i) -> int:
	if pos.x < 0 or pos.x >= MAP_WIDTH or pos.y < 0 or pos.y >= MAP_HEIGHT: return -1
	return grid[pos.x][pos.y]

func set_tile(pos: Vector2i, id: int) -> void:
	if pos.x < 0 or pos.x >= MAP_WIDTH or pos.y < 0 or pos.y >= MAP_HEIGHT: return
	grid[pos.x][pos.y] = id
	queue_redraw()

func tiles_of(id: int) -> Array:
	var out: Array = []
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			if grid[x][y] == id:
				out.append(Vector2i(x, y))
	return out

func _mouse_to_grid() -> Vector2i:
	var mp := get_global_mouse_position()
	return Vector2i(
		int((mp.x - MAP_OFFSET.x) / TILE_SIZE),
		int((mp.y - MAP_OFFSET.y) / TILE_SIZE)
	)

func _add_seeds(amount: int) -> void:
	available_seeds = mini(available_seeds + amount, SEED_CAP)

func _is_plant(id: int) -> bool:
	return id == GRASS or id == SUPER or id == MATURE

func _in_plant_zone(pos: Vector2i) -> bool:
	return pos.x >= zone_x0 and pos.x < zone_x1 and pos.y >= zone_y0 and pos.y < zone_y1

func _in_goal_zone(pos: Vector2i) -> bool:
	return pos.x >= goal_x and pos.x < goal_x + GOAL_SIZE and pos.y >= goal_y and pos.y < goal_y + GOAL_SIZE

func _in_river(pos: Vector2i) -> bool:
	return pos.x >= river_x and pos.x < river_x + RIVER_WIDTH

func _count_goal_plants() -> int:
	var count = 0
	for x in range(goal_x, goal_x + GOAL_SIZE):
		for y in range(goal_y, goal_y + GOAL_SIZE):
			if x >= 0 and x < MAP_WIDTH and y >= 0 and y < MAP_HEIGHT:
				if _is_plant(grid[x][y]): count += 1
	return count

func run_simulation_step() -> void:
	if predators.size() == 0 or randf() < 0.04: spawn_red_invader()
	if predators.size() > 5 and randf() < 0.02: spawn_apex_invader()

	run_plant_logic()
	update_ui()
	queue_redraw()

	var life := _count_life()
	if life == 0 and available_seeds == 0:
		score_label.text = "GAME OVER — Extinction!"
		game_active = false
		restart_button.show()

func _count_life() -> int:
	var count = 0
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			if _is_plant(grid[x][y]): count += 1
	return count

func plant_seed(tile_id: int) -> void:
	var cost: int
	match tile_id:
		GRASS: cost = COST_GRASS
		SUPER: cost = COST_SUPER
		SEED_APEX:  cost = COST_APEX_SPAWN
		_:     return
	if available_seeds < cost: return

	var center := _mouse_to_grid()

	if tile_id == SEED_APEX:
		var pos = center
		pos.x = clampi(pos.x, 0, MAP_WIDTH - 1)
		pos.y = clampi(pos.y, 0, MAP_HEIGHT - 1)
		apexes.append({ "pos": pos, "stomach": 0, "hunger": 0, "age": 0, "thirst": 0, "facing": DIRS.pick_random(), "size": 3, "home": pos })
		available_seeds -= cost
	elif tile_id == GRASS:
		if not _in_plant_zone(center): return
		var placed = false
		for dx in range(-5, 5):
			for dy in range(-5, 5):
				var pos = Vector2i(center.x + dx, center.y + dy)
				if get_tile(pos) == EMPTY and _in_plant_zone(pos):
					set_tile(pos, MATURE)
					placed = true
		if placed:
			available_seeds -= cost
	elif tile_id == SUPER:
		if not _in_plant_zone(center): return
		var placed = false
		for dx in range(-5, 5):
			for dy in range(-5, 5):
				var pos = Vector2i(center.x + dx, center.y + dy)
				if get_tile(pos) == EMPTY and _in_plant_zone(pos):
					set_tile(pos, SUPER)
					plant_ages[pos] = 0
					placed = true
		if placed:
			available_seeds -= cost
	update_ui()


func run_plant_logic() -> void:
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

	var mature_arr = tiles_of(MATURE)
	for pos in mature_arr:
		for d in DIRS:
			var neighbor: Vector2i = pos + d
			if get_tile(neighbor) == EMPTY and randf() < 0.05 and not _in_river(neighbor):
				set_tile(neighbor, MATURE)
				if randf() < 0.10: _add_seeds(1)

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
	predators.append({ "pos": _random_edge_pos(), "stomach": 0, "hunger": 0, "age": 0, "thirst": 0, "facing": DIRS.pick_random(), "size": 3 })

func spawn_apex_invader() -> void:
	var apex_pos := _random_edge_pos()
	apexes.append({ "pos": apex_pos, "stomach": 0, "hunger": 0, "age": 0, "thirst": 0, "facing": DIRS.pick_random(), "size": 3, "home": apex_pos })

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

func _try_move(animal: Dictionary, dir: Vector2i) -> bool:
	var new_pos = animal.pos + dir
	if new_pos.x < 0 or new_pos.y < 0 or new_pos.x + animal.size > MAP_WIDTH or new_pos.y + animal.size > MAP_HEIGHT:
		return false
	animal.pos = new_pos
	return true

func _try_spawn_offspring(parent_pos: Vector2i, list: Array, parent_size: int, home: Vector2i = Vector2i(-1, -1)) -> void:
	var dirs = DIRS.duplicate()
	dirs.shuffle()
	for d in dirs:
		var new_pos = parent_pos + d * parent_size
		if new_pos.x >= 0 and new_pos.y >= 0 and new_pos.x + 15 <= MAP_WIDTH and new_pos.y + 15 <= MAP_HEIGHT:
			var entry = { "pos": new_pos, "stomach": 0, "hunger": 0, "age": 0, "thirst": 0, "facing": d, "size": 3 }
			if home != Vector2i(-1, -1):
				entry["home"] = new_pos  # offspring claims spawn point as its own territory
			list.append(entry)
			return
func run_predator_logic() -> void:
	var alive = []
	for p in predators:
		if p.hunger >= STARVATION_LIMIT: continue

		for i in range(1):
			# Instantly eat all plant tiles under body
			var plant_pos = _find_plant_in_rect(Rect2i(p.pos.x, p.pos.y, p.size, p.size))
			if plant_pos != Vector2i(-1, -1):
				_erase_plant_data(plant_pos)
				set_tile(plant_pos, EMPTY)
				p.stomach += 1
				p.hunger = 0
				var needed_food = p.size * 10
				while p.stomach >= needed_food:
					p.stomach -= needed_food
					if p.size < 5:
						p.size += 1
						needed_food = p.size * 10
					else:
						if randf() < BIRTH_SUCCESS_CHANCE:
							_try_spawn_offspring(p.pos, alive, p.size)
						else:
							p.stomach = 0  # failed birth, reset counter

			# Poop in goal zone if carrying food
			if _in_goal_zone(p.pos) and p.stomach > 0:
				p.stomach -= 1
				var poop := Vector2i(p.pos.x + randi_range(0, p.size - 1), p.pos.y + randi_range(0, p.size - 1))
				if get_tile(poop) == EMPTY:
					set_tile(poop, MATURE)

			var moved = false
			# River slows movement: 60% chance to skip move when in river
			if _in_river(p.pos):
				p.thirst = 0  # drinking
			if not moved and _in_river(p.pos) and randf() < 0.6:
				moved = true
			# Thirsty: rush to river
			if not moved and p.thirst >= THIRST_DANGER:
				var river_diff_x: int = river_x + RIVER_WIDTH / 2 - p.pos.x
				if river_diff_x != 0:
					var step := Vector2i(signi(river_diff_x), 0)
					if _try_move(p, step):
						p.facing = step
						moved = true
			if not moved:
				# Avoid other herbivores within 3 tiles
				var repulse := Vector2i(0, 0)
				for other in predators:
					if other == p: continue
					var dx: int = p.pos.x - other.pos.x
					var dy: int = p.pos.y - other.pos.y
					if abs(dx) <= 3 and abs(dy) <= 3:
						repulse += Vector2i(signi(dx), signi(dy))
				if repulse != Vector2i(0, 0):
					var step := Vector2i(signi(repulse.x), 0) if abs(repulse.x) >= abs(repulse.y) else Vector2i(0, signi(repulse.y))
					if _try_move(p, step):
						p.facing = step
						moved = true

			if not moved:
				# Scan all directions within VISION_RANGE for nearest plant
				var scan_rect = Rect2i(p.pos.x - VISION_RANGE, p.pos.y - VISION_RANGE, p.size + VISION_RANGE * 2, p.size + VISION_RANGE * 2)
				var best_plant = Vector2i(-1, -1)
				var best_dist = 9999
				var sx = max(0, scan_rect.position.x)
				var sy = max(0, scan_rect.position.y)
				var ex = min(MAP_WIDTH, scan_rect.position.x + scan_rect.size.x)
				var ey = min(MAP_HEIGHT, scan_rect.position.y + scan_rect.size.y)
				for bx in range(sx, ex):
					for by in range(sy, ey):
						if _is_plant(grid[bx][by]):
							var d = abs(bx - p.pos.x) + abs(by - p.pos.y)
							if d < best_dist:
								best_dist = d
								best_plant = Vector2i(bx, by)
				if best_plant != Vector2i(-1, -1):
					var diff = best_plant - p.pos
					var step: Vector2i = Vector2i(signi(diff.x), 0) if abs(diff.x) >= abs(diff.y) else Vector2i(0, signi(diff.y))
					if _try_move(p, step):
						p.facing = step
						moved = true

			if not moved:
				# 5% chance to turn randomly
				if randf() < 0.05:
					p.facing = DIRS.pick_random()
				# Try to keep current direction first
				if _try_move(p, p.facing):
					moved = true
				else:
					# Only change direction when actually blocked
					var wander = DIRS.duplicate()
					wander.shuffle()
					for d in wander:
						if _try_move(p, d):
							p.facing = d
							moved = true
							break
			
			p.hunger += 1
			p.age += 1
			p.thirst += 1
			if p.hunger >= STARVATION_LIMIT or p.age >= HERBIVORE_LIFESPAN or p.thirst >= THIRST_LIMIT: break

		if p.hunger < STARVATION_LIMIT and p.age < HERBIVORE_LIFESPAN and p.thirst < THIRST_LIMIT:
			alive.append(p)
	predators = alive
func run_apex_logic() -> void:
	var alive = []
	for a in apexes:
		if a.hunger >= APEX_STARVATION: continue

		# 4x movement loop
		for i in range(1):
			var my_rect = Rect2i(a.pos.x, a.pos.y, a.size, a.size)
			for j in range(predators.size() - 1, -1, -1):
				var p_rect = Rect2i(predators[j].pos.x, predators[j].pos.y, predators[j].size, predators[j].size)
				if my_rect.intersects(p_rect):
					predators.remove_at(j)
					a.stomach += 1
					a.hunger = 0
					var needed_food = a.size
					while a.stomach >= needed_food:
						a.stomach -= needed_food
						if a.size < 5:
							a.size += 1
							needed_food = a.size
						else:
							_try_spawn_offspring(a.pos, alive, a.size, a.home)
					break

			var view_rect = Rect2i(a.pos.x - APEX_SCAN_RANGE, a.pos.y - APEX_SCAN_RANGE, a.size + APEX_SCAN_RANGE * 2, a.size + APEX_SCAN_RANGE * 2)
			var best_p = null
			var best_dist = 9999
			for p in predators:
				var p_rect = Rect2i(p.pos.x, p.pos.y, p.size, p.size)
				if view_rect.intersects(p_rect):
					var dist = abs(p.pos.x - a.pos.x) + abs(p.pos.y - a.pos.y)
					if dist < best_dist:
						best_dist = dist
						best_p = p

			if best_p == null and randf() < 0.05:
				a.facing = DIRS.pick_random()

			var moved = false
			if _in_river(a.pos):
				a.thirst = 0  # drinking
			# Thirsty: rush to river (overrides prey-chasing)
			if not moved and a.thirst >= THIRST_DANGER:
				var river_diff_x: int = river_x + RIVER_WIDTH / 2 - a.pos.x
				if river_diff_x != 0:
					var step := Vector2i(signi(river_diff_x), 0)
					if _try_move(a, step):
						a.facing = step
						moved = true
			# River slows movement: 60% chance to skip move when in river
			if _in_river(a.pos) and randf() < 0.6:
				moved = true
			if not moved and best_p != null:
				var diff = best_p.pos - a.pos
				var step = Vector2i()
				if abs(diff.x) >= abs(diff.y): step = Vector2i(signi(diff.x), 0)
				else:                          step = Vector2i(0, signi(diff.y))
				
				if _try_move(a, step):
					a.facing = step
					moved = true

			if not moved:
				# Return to territory when no prey visible and outside 30x30 home zone
				if best_p == null and a.has('home'):
					var territory = Rect2i(a.home.x - 15, a.home.y - 15, 30, 30)
					if not territory.has_point(a.pos):
						var home_center = a.home + Vector2i(15, 15)
						var diff = home_center - a.pos
						var step = Vector2i(signi(diff.x), 0) if abs(diff.x) >= abs(diff.y) else Vector2i(0, signi(diff.y))
						if _try_move(a, step):
							a.facing = step
							moved = true
				if not moved:
					# Try to keep current direction first
					if _try_move(a, a.facing):
						moved = true
					else:
						# Only change direction when actually blocked
						var wander = DIRS.duplicate()
						wander.shuffle()
						for d in wander:
							if _try_move(a, d):
								a.facing = d
								moved = true
								break

			a.hunger += 1
			a.age += 1
			a.thirst += 1
			if a.hunger >= APEX_STARVATION or a.age >= APEX_LIFESPAN or a.thirst >= THIRST_LIMIT: break

		if a.hunger < APEX_STARVATION and a.age < APEX_LIFESPAN and a.thirst < THIRST_LIMIT:
			alive.append(a)
	apexes = alive

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
	_init_grid()
	update_ui()
	score_label.text = "Goal: 0 / %d" % GOAL_FILL_TARGET
	restart_button.hide()
	queue_redraw()

func _on_btn_grass_pressed() -> void:
	current_seed_id = GRASS
	update_button_visuals()

func _on_btn_super_pressed() -> void:
	current_seed_id = SUPER
	update_button_visuals()

func _on_btn_predator_pressed() -> void:
	current_seed_id = SEED_APEX
	update_button_visuals()

func update_button_visuals() -> void:
	var btn_grass:    Button = $CanvasLayer/HBoxContainer/BtnGrass
	var btn_super:    Button = $CanvasLayer/HBoxContainer/BtnSuper
	var btn_predator: Button = $CanvasLayer/HBoxContainer/BtnPredator
	btn_grass.disabled    = (current_seed_id == GRASS)
	btn_super.disabled    = (current_seed_id == SUPER)
	btn_predator.disabled = (current_seed_id == SEED_APEX)
