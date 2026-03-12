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
const COLOR_EMPTY    = Color(0.20, 0.14, 0.08)
const COLOR_GRASS    = Color(0.25, 0.78, 0.18)
const COLOR_PREDATOR = Color(0.90, 0.10, 0.10)
const COLOR_SUPER    = Color(1.00, 0.88, 0.00)
const COLOR_APEX     = Color(0.15, 0.35, 0.95)
const COLOR_MATURE   = Color(0.04, 0.50, 0.12)

# --- MAP ---
const MAP_WIDTH  = 150
const MAP_HEIGHT = 130
const TILE_SIZE  = 1
const MAP_OFFSET = Vector2(0, 8)

# --- COSTS ---
const COST_GRASS      = 3
const COST_SUPER      = 10
const COST_APEX_SPAWN = 30

# --- RED PREDATOR SETTINGS ---
const PLANTS_TO_REPRODUCE = 6
const STARVATION_LIMIT    = 50
const EAT_TURNS           = 3
const MATURE_EAT_TURNS    = 4

# --- APEX PREDATOR SETTINGS ---
const APEX_REPRODUCE  = 3
const APEX_STARVATION = 120
const APEX_EAT_TURNS  = 3

# --- VISION ---
const VISION_RANGE    = 2
const APEX_SCAN_RANGE = 20

# --- PLANT SETTINGS ---
const SUPER_LIFESPAN   = 80
const SEED_CAP         = 30
const GROWTH_PER_TICK  = 2
var   update_interval  = 0.1

# --- STATE ---
var grid: Array          = []
var available_seeds: int = 20
var current_seed_id: int = GRASS
var time_passed: float   = 0.0
var game_active: bool    = true

var predators: Array = []
var apexes: Array = []
var plant_ages:   Dictionary = {}
var plant_growth: Dictionary = {}

const DIRS = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]

var predator_texture: Texture2D
var apex_texture: Texture2D

func _ready() -> void:
	var canvas = get_node_or_null("CanvasLayer")
	if canvas != null:
		var hbox = canvas.get_node_or_null("HBoxContainer")
		if hbox != null:
			hbox.position = Vector2(120, 800)
		var btn = canvas.get_node_or_null("RestartButton")
		if btn != null:
			btn.position = Vector2(400, 390)
	_init_grid()
	update_button_visuals()
	update_ui()
	predator_texture = load("res://predator_spritesheet.png")
	apex_texture     = load("res://apex_spritesheet.png")

func _process(delta: float) -> void:
	if not game_active: return
	time_passed += delta
	if time_passed >= update_interval:
		time_passed -= update_interval
		if time_passed > update_interval: time_passed = 0.0
		run_simulation_step()

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
	predators.append({ "pos": pos, "stomach": 0, "hunger": 0, "eating": 0, "facing": DIRS.pick_random(), "size": 3 })
	queue_redraw()

func _debug_spawn_apex() -> void:
	var pos := _mouse_to_grid()
	pos.x = clampi(pos.x, 0, MAP_WIDTH - 1)
	pos.y = clampi(pos.y, 0, MAP_HEIGHT - 1)
	apexes.append({ "pos": pos, "stomach": 0, "hunger": 0, "eating": 0, "facing": DIRS.pick_random(), "size": 3 })
	queue_redraw()

func _draw() -> void:
	var sub_w: float = float(TILE_SIZE) / 10.0

	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var px: float = MAP_OFFSET.x + x * TILE_SIZE
			var py: float = MAP_OFFSET.y + y * TILE_SIZE
			var tile_id: int = grid[x][y]

			if tile_id == GRASS:
				draw_rect(Rect2(px, py, TILE_SIZE, TILE_SIZE), COLOR_EMPTY)
				var pos := Vector2i(x, y)
				var growth_val: int = plant_growth.get(pos, 0)
				var total_cols: int = mini(growth_val / 10, 10)
				var primary_dir: Vector2i = Vector2i(-1, 0)
				for d in DIRS:
					var n: Vector2i = pos + d
					if get_tile(n) == MATURE:
						primary_dir = d
						break
				for c in range(total_cols):
					match primary_dir:
						Vector2i(-1, 0): draw_rect(Rect2(px + c * sub_w, py, sub_w, TILE_SIZE), COLOR_GRASS)
						Vector2i(1, 0):  draw_rect(Rect2(px + (9 - c) * sub_w, py, sub_w, TILE_SIZE), COLOR_GRASS)
						Vector2i(0, -1): draw_rect(Rect2(px, py + c * sub_w, TILE_SIZE, sub_w), COLOR_GRASS)
						_:               draw_rect(Rect2(px, py + (9 - c) * sub_w, TILE_SIZE, sub_w), COLOR_GRASS)
			elif tile_id != EMPTY:
				draw_rect(Rect2(px, py, TILE_SIZE, TILE_SIZE), _tile_colour(tile_id))

	for p in predators: _draw_animal(p, COLOR_PREDATOR, predator_texture, STARVATION_LIMIT)
	for a in apexes:    _draw_animal(a, COLOR_APEX,     apex_texture,     APEX_STARVATION)

	draw_rect(Rect2(MAP_OFFSET.x, MAP_OFFSET.y, MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE), Color.YELLOW, false, 2.0)

func _draw_animal(animal: Dictionary, color: Color, texture: Texture2D, starvation_limit: int) -> void:
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

func run_simulation_step() -> void:
	if predators.size() == 0 or randf() < 0.04: spawn_red_invader()
	if predators.size() > 5 and randf() < 0.02: spawn_apex_invader()

	run_plant_logic()
	run_predator_logic()
	run_apex_logic()
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
	
	var pos := _mouse_to_grid()
	pos.x = clampi(pos.x, 0, MAP_WIDTH - 1)
	pos.y = clampi(pos.y, 0, MAP_HEIGHT - 1)
	
	if tile_id == SEED_APEX:
		apexes.append({ "pos": pos, "stomach": 0, "hunger": 0, "eating": 0, "facing": DIRS.pick_random(), "size": 3 })
		available_seeds -= cost
	elif tile_id == GRASS:
		if get_tile(pos) != EMPTY: return
		set_tile(pos, MATURE)
		available_seeds -= cost
	elif tile_id == SUPER:
		if get_tile(pos) != EMPTY: return
		set_tile(pos, SUPER)
		available_seeds -= cost
		plant_ages[pos] = 0
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

	for pos in plant_growth.keys().duplicate():
		if plant_growth[pos] >= 100 and get_tile(pos) == GRASS:
			set_tile(pos, MATURE)
			plant_growth.erase(pos)
			if randf() < 0.10: _add_seeds(1)

	var mature_arr = tiles_of(MATURE)
	for pos in mature_arr:
		for d in DIRS:
			var neighbor: Vector2i = pos + d
			if get_tile(neighbor) == EMPTY and randf() < 0.01:
				set_tile(neighbor, GRASS)
				plant_growth[neighbor] = 0

	for pos in plant_growth.keys().duplicate():
		if get_tile(pos) != GRASS:
			plant_growth.erase(pos)
			continue
		plant_growth[pos] = mini(plant_growth[pos] + GROWTH_PER_TICK, 100)

func _spread_from_super(parent: Vector2i) -> void:
	var jump := Vector2i(randi_range(-8, 8), randi_range(-8, 8))
	if jump == Vector2i.ZERO: return
	var new_pos: Vector2i = parent + jump
	if get_tile(new_pos) != EMPTY: return
	set_tile(new_pos, GRASS)
	plant_growth[new_pos] = 0

func _erase_plant_data(pos: Vector2i) -> void:
	plant_ages.erase(pos)
	plant_growth.erase(pos)

func _random_edge_pos() -> Vector2i:
	match randi_range(0, 3):
		0: return Vector2i(randi_range(0, MAP_WIDTH - 1), 0)
		1: return Vector2i(randi_range(0, MAP_WIDTH - 1), MAP_HEIGHT - 1)
		2: return Vector2i(0, randi_range(0, MAP_HEIGHT - 1))
		_: return Vector2i(MAP_WIDTH - 1, randi_range(0, MAP_HEIGHT - 1))

func spawn_red_invader() -> void:
	predators.append({ "pos": _random_edge_pos(), "stomach": 0, "hunger": 0, "eating": 0, "facing": DIRS.pick_random(), "size": 3 })

func spawn_apex_invader() -> void:
	apexes.append({ "pos": _random_edge_pos(), "stomach": 0, "hunger": 0, "eating": 0, "facing": DIRS.pick_random(), "size": 3 })

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

func _try_spawn_offspring(parent_pos: Vector2i, list: Array, parent_size: int) -> void:
	var dirs = DIRS.duplicate()
	dirs.shuffle()
	for d in dirs:
		var new_pos = parent_pos + d * parent_size
		if new_pos.x >= 0 and new_pos.y >= 0 and new_pos.x + 3 <= MAP_WIDTH and new_pos.y + 3 <= MAP_HEIGHT:
			list.append({ "pos": new_pos, "stomach": 0, "hunger": 0, "eating": 0, "facing": d, "size": 3 })
			return

func run_predator_logic() -> void:
	var alive = []
	for p in predators:
		if p.hunger >= STARVATION_LIMIT: continue

		var move_timer = p.get("move_cooldown", 0)
		if move_timer > 0:
			p.move_cooldown = move_timer - 1
			p.hunger += 1
			alive.append(p)
			continue

		var eaten_count = _eat_all_plants_in_rect(Rect2i(p.pos.x, p.pos.y, p.size, p.size))
		if eaten_count > 0:
			p.stomach += eaten_count
			p.hunger = 0
			var needed_food = p.size * 10
			while p.stomach >= needed_food:
				p.stomach -= needed_food
				if p.size < 7:
					p.size += 2
					needed_food = p.size * 10
				else:
					_try_spawn_offspring(p.pos, alive, p.size)

		var moved = false
		var front_rect = Rect2i(p.pos.x, p.pos.y, p.size, p.size)
		if p.facing == Vector2i(1, 0): front_rect = Rect2i(p.pos.x + p.size, p.pos.y, VISION_RANGE, p.size)
		elif p.facing == Vector2i(-1, 0): front_rect = Rect2i(p.pos.x - VISION_RANGE, p.pos.y, VISION_RANGE, p.size)
		elif p.facing == Vector2i(0, 1): front_rect = Rect2i(p.pos.x, p.pos.y + p.size, p.size, VISION_RANGE)
		elif p.facing == Vector2i(0, -1): front_rect = Rect2i(p.pos.x, p.pos.y - VISION_RANGE, p.size, VISION_RANGE)

		if _find_plant_in_rect(front_rect) != Vector2i(-1, -1):
			if _try_move(p, p.facing): moved = true

		if not moved:
			var wander = DIRS.duplicate()
			wander.shuffle()
			for d in wander:
				if _try_move(p, d):
					p.facing = d
					moved = true
					break

		if moved:
			p.move_cooldown = 2

		p.hunger += 1
		alive.append(p)
	predators = alive

func run_apex_logic() -> void:
	var alive = []
	for a in apexes:
		if a.hunger >= APEX_STARVATION: continue

		var move_timer = a.get("move_cooldown", 0)
		if move_timer > 0:
			a.move_cooldown = move_timer - 1
			a.hunger += 1
			alive.append(a)
			continue

		var my_rect = Rect2i(a.pos.x, a.pos.y, a.size, a.size)
		for i in range(predators.size() - 1, -1, -1):
			var p_rect = Rect2i(predators[i].pos.x, predators[i].pos.y, predators[i].size, predators[i].size)
			if my_rect.intersects(p_rect):
				predators.remove_at(i)
				a.stomach += 1
				a.hunger = 0
				var needed_food = a.size
				while a.stomach >= needed_food:
					a.stomach -= needed_food
					if a.size < 7:
						a.size += 2
						needed_food = a.size
					else:
						_try_spawn_offspring(a.pos, alive, a.size)
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

		var moved = false
		if best_p != null:
			var diff = best_p.pos - a.pos
			var step = Vector2i()
			if abs(diff.x) >= abs(diff.y): step = Vector2i(signi(diff.x), 0)
			else:                          step = Vector2i(0, signi(diff.y))
			
			if _try_move(a, step):
				a.facing = step
				moved = true

		if not moved:
			var wander = DIRS.duplicate()
			wander.shuffle()
			for d in wander:
				if _try_move(a, d):
					a.facing = d
					moved = true
					break

		if moved:
			a.move_cooldown = 2

		a.hunger += 1
		alive.append(a)
	apexes = alive

func update_ui() -> void:
	var life := _count_life()
	var pct  := (float(life) / float(MAP_WIDTH * MAP_HEIGHT)) * 100.0
	score_label.text = "Map Covered: %.1f%%" % pct
	seed_label.text  = "Seeds: %d / %d" % [available_seeds, SEED_CAP]
	if pct >= 80.0 and game_active:
		score_label.text = "VICTORY!  Ecosystem Stabilised."
		game_active = false
		restart_button.show()

func _on_restart_button_pressed() -> void:
	available_seeds = 20
	time_passed     = 0.0
	game_active     = true
	predators.clear()
	apexes.clear()
	plant_ages.clear()
	plant_growth.clear()
	_init_grid()
	update_ui()
	score_label.text = "Map Covered: 0.0%"
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
