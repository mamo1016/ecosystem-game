extends Node2D

# --- UI REFERENCES ---
@onready var seed_label     = $CanvasLayer/SeedLabel
@onready var score_label    = $CanvasLayer/ScoreLabel
@onready var restart_button = $CanvasLayer/RestartButton

# --- TILE IDs ---
const EMPTY    = 0
const GRASS    = 1   # growing grass — fills in 10 columns gradually
const PREDATOR = 2   # red — eats plants
const SUPER    = 3   # yellow — spreads grass at distance, becomes mature after 20 ticks
const APEX     = 4   # blue — eats red predators, walks over plants harmlessly
const MATURE   = 5   # dark green — fully grown grass, harder to eat (4 turns)

# --- COLOURS ---
const COLOR_EMPTY    = Color(0.20, 0.14, 0.08)
const COLOR_GRASS    = Color(0.25, 0.78, 0.18)
const COLOR_PREDATOR = Color(0.90, 0.10, 0.10)
const COLOR_SUPER    = Color(1.00, 0.88, 0.00)
const COLOR_APEX     = Color(0.15, 0.35, 0.95)
const COLOR_MATURE   = Color(0.04, 0.50, 0.12)

# --- MAP ---
const MAP_WIDTH  = 50
const MAP_HEIGHT = 30
const TILE_SIZE  = 22
const MAP_OFFSET = Vector2(0, 8)

# --- COSTS ---
const COST_GRASS      = 3
const COST_SUPER      = 10
const COST_APEX_SPAWN = 30

# --- RED PREDATOR SETTINGS ---
const PLANTS_TO_REPRODUCE = 6
const STARVATION_LIMIT    = 8
const EAT_TURNS           = 3    # turns to eat GRASS or SUPER
const MATURE_EAT_TURNS    = 4    # turns to eat MATURE

# --- APEX PREDATOR SETTINGS ---
const APEX_REPRODUCE  = 3
const APEX_STARVATION = 50
const APEX_EAT_TURNS  = 3

# --- VISION ---
const VISION_RANGE    = 2
const APEX_SCAN_RANGE = 2

# --- PLANT SETTINGS ---
const SUPER_LIFESPAN   = 20
const SEED_CAP         = 30
const GROWTH_PER_TICK  = 2    # sub-cells filled per tick (100 total = 50 ticks to mature)
var   update_interval  = 0.4

# --- STATE ---
var grid: Array          = []
var available_seeds: int = 20
var current_seed_id: int = GRASS
var time_passed: float   = 0.0
var game_active: bool    = true

# --- RED PREDATOR TRACKERS ---
var predator_stomachs: Dictionary = {}
var predator_hunger:   Dictionary = {}
var predator_eating:   Dictionary = {}
var predator_facing:   Dictionary = {}

# --- APEX PREDATOR TRACKERS ---
var apex_stomachs:      Dictionary = {}
var apex_hunger:        Dictionary = {}
var apex_eating:        Dictionary = {}
var apex_facing:        Dictionary = {}
var apex_hidden_plant:  Dictionary = {}   # Vector2i -> tile_id (GRASS, MATURE, SUPER)

# --- PLANT TRACKERS ---
var plant_ages:   Dictionary = {}   # SUPER age tracking
var plant_growth: Dictionary = {}   # GRASS growth 0-100

# --- CARDINAL DIRECTIONS ---
const DIRS = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]

# ============================================================
#  ENGINE CALLBACKS
# ============================================================

func _ready() -> void:
	_init_grid()
	update_button_visuals()
	update_ui()

func _process(delta: float) -> void:
	if not game_active:
		return
	time_passed += delta
	if time_passed >= update_interval:
		time_passed = 0.0
		run_simulation_step()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:   plant_seed(current_seed_id)
			MOUSE_BUTTON_RIGHT:  _debug_spawn(PREDATOR)
			MOUSE_BUTTON_MIDDLE: _debug_spawn(APEX)

func _debug_spawn(tile_id: int) -> void:
	var pos := _mouse_to_grid()
	if get_tile(pos) != EMPTY:
		return
	set_tile(pos, tile_id)
	var face: Vector2i = DIRS.pick_random()
	if tile_id == PREDATOR:
		predator_stomachs[pos] = 0
		predator_hunger[pos]   = 0
		predator_facing[pos]   = face
	elif tile_id == APEX:
		apex_stomachs[pos] = 0
		apex_hunger[pos]   = 0
		apex_facing[pos]   = face

# ============================================================
#  DRAWING
# ============================================================

func _draw() -> void:
	var sub_w: float = (TILE_SIZE - 1) / 10.0

	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var px: float = MAP_OFFSET.x + x * TILE_SIZE
			var py: float = MAP_OFFSET.y + y * TILE_SIZE
			var tile_id: int = grid[x][y]

			if tile_id == GRASS:
				# Draw dirt background, then partial green fill
				var tw: float = TILE_SIZE - 1
				var th: float = TILE_SIZE - 1
				draw_rect(Rect2(px, py, tw, th), COLOR_EMPTY)
				var pos := Vector2i(x, y)
				var growth_val: int = plant_growth.get(pos, 0)
				var total_cols: int = mini(growth_val / 10, 10)
				# Find primary direction from first MATURE neighbor
				var primary_dir: Vector2i = Vector2i(-1, 0)  # default: left
				for d in DIRS:
					var n: Vector2i = pos + d
					var nt: int = get_tile(n)
					if nt == MATURE or (apex_hidden_plant.has(n) and apex_hidden_plant.get(n, EMPTY) == MATURE):
						primary_dir = d
						break
				# Fill columns from the primary direction
				for c in range(total_cols):
					match primary_dir:
						Vector2i(-1, 0):  # mature on left → fill from left
							draw_rect(Rect2(px + c * sub_w, py, sub_w, th), COLOR_GRASS)
						Vector2i(1, 0):   # mature on right → fill from right
							draw_rect(Rect2(px + (9 - c) * sub_w, py, sub_w, th), COLOR_GRASS)
						Vector2i(0, -1):  # mature above → fill from top
							draw_rect(Rect2(px, py + c * sub_w, tw, sub_w), COLOR_GRASS)
						_:                # mature below → fill from bottom
							draw_rect(Rect2(px, py + (9 - c) * sub_w, tw, sub_w), COLOR_GRASS)
			else:
				draw_rect(Rect2(px, py, TILE_SIZE - 1, TILE_SIZE - 1), _tile_colour(tile_id))

	# Facing indicators
	for pos in predator_facing:
		if get_tile(pos) == PREDATOR:
			_draw_facing_indicator(pos, predator_facing[pos])
	for pos in apex_facing:
		if get_tile(pos) == APEX:
			_draw_facing_indicator(pos, apex_facing[pos])

	# Border
	draw_rect(
		Rect2(MAP_OFFSET.x, MAP_OFFSET.y, MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE),
		Color.YELLOW, false, 2.0
	)

func _draw_facing_indicator(pos: Vector2i, facing: Vector2i) -> void:
	var cx: float = MAP_OFFSET.x + pos.x * TILE_SIZE + (TILE_SIZE - 1) * 0.5
	var cy: float = MAP_OFFSET.y + pos.y * TILE_SIZE + (TILE_SIZE - 1) * 0.5
	var s: float  = (TILE_SIZE - 1) * 0.5
	var tip: Vector2
	var left_pt: Vector2
	var right_pt: Vector2
	match facing:
		Vector2i(0, -1):
			tip      = Vector2(cx, cy - s)
			left_pt  = Vector2(cx - s * 0.4, cy - s * 0.2)
			right_pt = Vector2(cx + s * 0.4, cy - s * 0.2)
		Vector2i(0, 1):
			tip      = Vector2(cx, cy + s)
			left_pt  = Vector2(cx - s * 0.4, cy + s * 0.2)
			right_pt = Vector2(cx + s * 0.4, cy + s * 0.2)
		Vector2i(-1, 0):
			tip      = Vector2(cx - s, cy)
			left_pt  = Vector2(cx - s * 0.2, cy - s * 0.4)
			right_pt = Vector2(cx - s * 0.2, cy + s * 0.4)
		_:
			tip      = Vector2(cx + s, cy)
			left_pt  = Vector2(cx + s * 0.2, cy - s * 0.4)
			right_pt = Vector2(cx + s * 0.2, cy + s * 0.4)
	draw_colored_polygon(PackedVector2Array([tip, left_pt, right_pt]), Color.WHITE)

func _tile_colour(id: int) -> Color:
	match id:
		GRASS:    return COLOR_GRASS
		PREDATOR: return COLOR_PREDATOR
		SUPER:    return COLOR_SUPER
		APEX:     return COLOR_APEX
		MATURE:   return COLOR_MATURE
		_:        return COLOR_EMPTY

# ============================================================
#  GRID HELPERS
# ============================================================

func _init_grid() -> void:
	grid = []
	for x in range(MAP_WIDTH):
		var col := []
		col.resize(MAP_HEIGHT)
		col.fill(EMPTY)
		grid.append(col)

func get_tile(pos: Vector2i) -> int:
	if pos.x < 0 or pos.x >= MAP_WIDTH or pos.y < 0 or pos.y >= MAP_HEIGHT:
		return -1
	return grid[pos.x][pos.y]

func set_tile(pos: Vector2i, id: int) -> void:
	if pos.x < 0 or pos.x >= MAP_WIDTH or pos.y < 0 or pos.y >= MAP_HEIGHT:
		return
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

func _facing_for_edge(pos: Vector2i) -> Vector2i:
	if pos.y == 0:              return Vector2i(0, 1)
	if pos.y == MAP_HEIGHT - 1: return Vector2i(0, -1)
	if pos.x == 0:              return Vector2i(1, 0)
	return Vector2i(-1, 0)

func _is_plant(id: int) -> bool:
	return id == GRASS or id == SUPER or id == MATURE

# ============================================================
#  MAIN SIMULATION STEP
# ============================================================

func run_simulation_step() -> void:
	if tiles_of(PREDATOR).size() == 0 or randf() < 0.08:
		spawn_red_invader()
	if tiles_of(PREDATOR).size() > 3 and randf() < 0.03:
		spawn_apex_invader()

	run_plant_logic()
	run_predator_logic()
	run_apex_logic()
	update_ui()

	var life := _count_life()
	if life == 0 and available_seeds == 0:
		score_label.text = "GAME OVER — Extinction!"
		game_active = false
		restart_button.show()

func _count_life() -> int:
	var count: int = tiles_of(GRASS).size() + tiles_of(SUPER).size() + tiles_of(MATURE).size()
	# Also count plants hidden under apex
	count += apex_hidden_plant.size()
	return count

# ============================================================
#  PLANT LOGIC
# ============================================================

func plant_seed(tile_id: int) -> void:
	var cost: int
	match tile_id:
		GRASS: cost = COST_GRASS
		SUPER: cost = COST_SUPER
		APEX:  cost = COST_APEX_SPAWN
		_:     return
	if available_seeds < cost:
		return
	var pos := _mouse_to_grid()
	var current_tile := get_tile(pos)

	if tile_id == APEX:
		if current_tile != EMPTY and not _is_plant(current_tile):
			return
		if _is_plant(current_tile):
			apex_hidden_plant[pos] = current_tile
		set_tile(pos, APEX)
		available_seeds -= cost
		apex_stomachs[pos] = 0
		apex_hunger[pos]   = 0
		var rand_face: Vector2i = DIRS.pick_random()
		apex_facing[pos]   = rand_face
	elif tile_id == GRASS:
		# Player-placed grass is immediately MATURE
		if current_tile != EMPTY:
			return
		set_tile(pos, MATURE)
		available_seeds -= cost
	elif tile_id == SUPER:
		if current_tile != EMPTY:
			return
		set_tile(pos, SUPER)
		available_seeds -= cost
		plant_ages[pos] = 0
	update_ui()

func run_plant_logic() -> void:
	# --- SUPER seeds: age tracking, spread at distance ---
	for pos in plant_ages.keys().duplicate():
		if apex_hidden_plant.has(pos):
			continue
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

	# --- Phase 1: Convert fully grown GRASS (already at 100) to MATURE ---
	for pos in plant_growth.keys().duplicate():
		if plant_growth[pos] >= 100 and get_tile(pos) == GRASS:
			set_tile(pos, MATURE)
			plant_growth.erase(pos)
			if randf() < 0.30:
				_add_seeds(1)

	# --- Phase 2: MATURE spreads GRASS to all 4 adjacent empty tiles ---
	for pos in tiles_of(MATURE):
		for d in DIRS:
			var neighbor: Vector2i = pos + d
			if get_tile(neighbor) == EMPTY:
				set_tile(neighbor, GRASS)
				plant_growth[neighbor] = 0

	# --- Phase 3: Grow existing GRASS, cap at 100 (shown fully green for 1 tick) ---
	for pos in plant_growth.keys().duplicate():
		if apex_hidden_plant.has(pos):
			continue
		if get_tile(pos) != GRASS:
			plant_growth.erase(pos)
			continue
		plant_growth[pos] = mini(plant_growth[pos] + GROWTH_PER_TICK, 100)

func _spread_from_super(parent: Vector2i) -> void:
	var jump := Vector2i(randi_range(-5, 5), randi_range(-5, 5))
	if jump == Vector2i.ZERO:
		return
	var new_pos: Vector2i = parent + jump
	if get_tile(new_pos) != EMPTY:
		return
	set_tile(new_pos, GRASS)
	plant_growth[new_pos] = 0

func _erase_plant_data(pos: Vector2i) -> void:
	plant_ages.erase(pos)
	plant_growth.erase(pos)

# ============================================================
#  RED PREDATOR LOGIC  (vision: looks 2 blocks ahead for plants)
# ============================================================

func spawn_red_invader() -> void:
	var pos := _random_edge_pos()
	if get_tile(pos) == PREDATOR:
		return
	set_tile(pos, PREDATOR)
	predator_stomachs[pos] = 0
	predator_hunger[pos]   = 0
	predator_facing[pos]   = _facing_for_edge(pos)

func run_predator_logic() -> void:
	var predators := tiles_of(PREDATOR)
	predators.shuffle()
	for pos in predators:
		move_predator(pos)

func move_predator(cur: Vector2i) -> void:
	var starving: int = predator_hunger.get(cur, 0)

	# Eating countdown
	if predator_eating.has(cur):
		predator_eating[cur] -= 1
		if predator_eating[cur] <= 0:
			predator_eating.erase(cur)
			var energy: int = predator_stomachs.get(cur, 0) + 1
			if energy >= PLANTS_TO_REPRODUCE:
				predator_stomachs[cur] = 0
				predator_hunger[cur]   = 0
				_try_spawn_red_offspring(cur)
			else:
				predator_stomachs[cur] = energy
				predator_hunger[cur]   = 0
		return

	if starving >= STARVATION_LIMIT:
		_kill_predator(cur)
		return

	var facing: Vector2i = predator_facing.get(cur, DIRS.pick_random())
	var energy: int = predator_stomachs.get(cur, 0)

	# --- VISION: scan all 4 adjacent tiles for plants ---
	var food_dirs: Array = []
	for d in DIRS:
		var n: Vector2i = cur + d
		if _is_plant(get_tile(n)):
			food_dirs.append(d)

	# Plant found adjacent → pick one randomly and eat it
	if not food_dirs.is_empty():
		var pick: Vector2i = food_dirs.pick_random()
		var tgt: Vector2i = cur + pick
		var t: int = get_tile(tgt)
		var eat_time: int = MATURE_EAT_TURNS if t == MATURE else EAT_TURNS
		_erase_plant_data(tgt)
		set_tile(tgt, PREDATOR)
		predator_stomachs[tgt] = energy
		predator_hunger[tgt]   = 0
		predator_eating[tgt]   = eat_time
		predator_facing[tgt]   = pick
		_red_vacate(cur)
		predator_stomachs.erase(cur)
		predator_hunger.erase(cur)
		predator_facing.erase(cur)
		return

	# --- No adjacent plant: look 2 blocks ahead in facing direction ---
	var ahead1: Vector2i = cur + facing
	var t1 := get_tile(ahead1)
	var ahead2: Vector2i = cur + facing * 2
	var t2 := get_tile(ahead2)
	if _is_plant(t2) and t1 == EMPTY:
		set_tile(ahead1, PREDATOR)
		predator_stomachs[ahead1] = energy
		predator_hunger[ahead1]   = starving
		predator_facing[ahead1]   = facing
		_red_vacate(cur)
		predator_stomachs.erase(cur)
		predator_hunger.erase(cur)
		predator_facing.erase(cur)
		return

	# --- Wander randomly ---
	var wander_dirs: Array = DIRS.duplicate()
	wander_dirs.shuffle()
	for d in wander_dirs:
		var tgt: Vector2i = cur + d
		if get_tile(tgt) != EMPTY:
			continue
		set_tile(tgt, PREDATOR)
		predator_stomachs[tgt] = energy
		predator_hunger[tgt]   = starving + 1
		predator_facing[tgt]   = d
		_red_vacate(cur)
		predator_stomachs.erase(cur)
		predator_hunger.erase(cur)
		predator_facing.erase(cur)
		return

	predator_hunger[cur] = starving + 1

func _try_spawn_red_offspring(parent: Vector2i) -> void:
	var dirs: Array = DIRS.duplicate()
	dirs.shuffle()
	for d in dirs:
		var tgt: Vector2i = parent + d
		if get_tile(tgt) == EMPTY:
			set_tile(tgt, PREDATOR)
			predator_stomachs[tgt] = 0
			predator_hunger[tgt]   = 0
			predator_facing[tgt]   = d
			return

func _red_vacate(pos: Vector2i) -> void:
	set_tile(pos, EMPTY)

func _kill_predator(pos: Vector2i) -> void:
	predator_stomachs.erase(pos)
	predator_hunger.erase(pos)
	predator_eating.erase(pos)
	predator_facing.erase(pos)
	set_tile(pos, EMPTY)

# ============================================================
#  APEX PREDATOR LOGIC  (vision: 5x5 area scan, survives 50 turns)
# ============================================================

func spawn_apex_invader() -> void:
	var pos := _random_edge_pos()
	if get_tile(pos) != EMPTY:
		return
	set_tile(pos, APEX)
	apex_stomachs[pos] = 0
	apex_hunger[pos]   = 0
	apex_facing[pos]   = _facing_for_edge(pos)

func run_apex_logic() -> void:
	var apexes := tiles_of(APEX)
	apexes.shuffle()
	for pos in apexes:
		move_apex(pos)

func move_apex(cur: Vector2i) -> void:
	var starving: int = apex_hunger.get(cur, 0)

	if apex_eating.has(cur):
		apex_eating[cur] -= 1
		if apex_eating[cur] <= 0:
			apex_eating.erase(cur)
			var energy: int = apex_stomachs.get(cur, 0) + 1
			if energy >= APEX_REPRODUCE:
				apex_stomachs[cur] = 0
				apex_hunger[cur]   = 0
				_try_spawn_apex_offspring(cur)
			else:
				apex_stomachs[cur] = energy
				apex_hunger[cur]   = 0
		return

	if starving >= APEX_STARVATION:
		_kill_apex(cur)
		return

	var energy: int = apex_stomachs.get(cur, 0)

	# --- VISION: scan 5x5 area for closest red predator ---
	var best_target: Vector2i = Vector2i(-1, -1)
	var best_dist: int = 999
	for dx in range(-APEX_SCAN_RANGE, APEX_SCAN_RANGE + 1):
		for dy in range(-APEX_SCAN_RANGE, APEX_SCAN_RANGE + 1):
			if dx == 0 and dy == 0:
				continue
			var check: Vector2i = cur + Vector2i(dx, dy)
			if get_tile(check) == PREDATOR:
				var dist: int = absi(dx) + absi(dy)
				if dist < best_dist:
					best_dist = dist
					best_target = check

	if best_target != Vector2i(-1, -1):
		var diff: Vector2i = best_target - cur
		var step: Vector2i
		if absi(diff.x) >= absi(diff.y):
			step = Vector2i(signi(diff.x), 0)
		else:
			step = Vector2i(0, signi(diff.y))
		var tgt: Vector2i = cur + step
		var t := get_tile(tgt)

		if t == PREDATOR:
			predator_stomachs.erase(tgt)
			predator_hunger.erase(tgt)
			predator_eating.erase(tgt)
			predator_facing.erase(tgt)
			set_tile(tgt, APEX)
			apex_stomachs[tgt] = energy
			apex_hunger[tgt]   = 0
			apex_eating[tgt]   = APEX_EAT_TURNS
			apex_facing[tgt]   = step
			_apex_vacate(cur)
			apex_stomachs.erase(cur)
			apex_hunger.erase(cur)
			apex_facing.erase(cur)
			return

		if t == EMPTY or _is_plant(t):
			if _is_plant(t):
				apex_hidden_plant[tgt] = t
			set_tile(tgt, APEX)
			apex_stomachs[tgt] = energy
			apex_hunger[tgt]   = starving
			apex_facing[tgt]   = step
			_apex_vacate(cur)
			apex_stomachs.erase(cur)
			apex_hunger.erase(cur)
			apex_facing.erase(cur)
			return

	# --- Wander on EMPTY or any plant ---
	var wander_dirs: Array = DIRS.duplicate()
	wander_dirs.shuffle()
	for d in wander_dirs:
		var tgt: Vector2i = cur + d
		var t := get_tile(tgt)
		if t != EMPTY and not _is_plant(t):
			continue
		if _is_plant(t):
			apex_hidden_plant[tgt] = t
		set_tile(tgt, APEX)
		apex_stomachs[tgt] = energy
		apex_hunger[tgt]   = starving + 1
		apex_facing[tgt]   = d
		_apex_vacate(cur)
		apex_stomachs.erase(cur)
		apex_hunger.erase(cur)
		apex_facing.erase(cur)
		return

	apex_hunger[cur] = starving + 1

func _try_spawn_apex_offspring(parent: Vector2i) -> void:
	var dirs: Array = DIRS.duplicate()
	dirs.shuffle()
	for d in dirs:
		var tgt: Vector2i = parent + d
		if get_tile(tgt) == EMPTY:
			set_tile(tgt, APEX)
			apex_stomachs[tgt] = 0
			apex_hunger[tgt]   = 0
			apex_facing[tgt]   = d
			return

func _apex_vacate(pos: Vector2i) -> void:
	if apex_hidden_plant.has(pos):
		set_tile(pos, apex_hidden_plant[pos])
		apex_hidden_plant.erase(pos)
	else:
		set_tile(pos, EMPTY)

func _kill_apex(pos: Vector2i) -> void:
	apex_stomachs.erase(pos)
	apex_hunger.erase(pos)
	apex_eating.erase(pos)
	apex_facing.erase(pos)
	_apex_vacate(pos)

# ============================================================
#  SHARED HELPERS
# ============================================================

func _random_edge_pos() -> Vector2i:
	match randi_range(0, 3):
		0: return Vector2i(randi_range(0, MAP_WIDTH - 1), 0)
		1: return Vector2i(randi_range(0, MAP_WIDTH - 1), MAP_HEIGHT - 1)
		2: return Vector2i(0, randi_range(0, MAP_HEIGHT - 1))
		_: return Vector2i(MAP_WIDTH - 1, randi_range(0, MAP_HEIGHT - 1))

# ============================================================
#  UI & GAME STATE
# ============================================================

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
	predator_stomachs.clear()
	predator_hunger.clear()
	predator_eating.clear()
	predator_facing.clear()
	apex_stomachs.clear()
	apex_hunger.clear()
	apex_eating.clear()
	apex_facing.clear()
	apex_hidden_plant.clear()
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
	current_seed_id = APEX
	update_button_visuals()

func update_button_visuals() -> void:
	var btn_grass:    Button = $CanvasLayer/HBoxContainer/BtnGrass
	var btn_super:    Button = $CanvasLayer/HBoxContainer/BtnSuper
	var btn_predator: Button = $CanvasLayer/HBoxContainer/BtnPredator
	btn_grass.disabled    = (current_seed_id == GRASS)
	btn_super.disabled    = (current_seed_id == SUPER)
	btn_predator.disabled = (current_seed_id == APEX)
