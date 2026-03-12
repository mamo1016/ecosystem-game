# Eco-Sim — Claude Project Notes

## Project Overview
A grid-based ecosystem simulator built in Godot 4. The player places seeds to grow plants, manages a food chain of herbivores (red predators) and carnivores (apex predators), and wins by covering 80% of the map with plants.

## Architecture
- Single monolithic script: `world.gd` (~600 lines)
- No OOP — all state in flat arrays/dicts
- `grid[][]` — 2D tile array
- `predators[]` / `apexes[]` — arrays of dictionaries
- `plant_ages{}` / `plant_growth{}` — plant lifecycle tracking
- Simulation ticks every 0.1s; animals move 4 steps/tick

## Tile IDs
| Constant | ID | Description |
|---|---|---|
| EMPTY | 0 | Bare ground |
| GRASS | 1 | Growing grass (animated fill) |
| SUPER | 3 | Super plant (spreads spores far) |
| SEED_APEX | 4 | Used for apex spawn input |
| MATURE | 5 | Fully grown, spreads to neighbors |

## Rendering
- Sprites loaded from spritesheets at startup (`plant_spritesheet.png`, `predator_spritesheet.png`, `apex_spritesheet.png`)
- Plant sheet: 3 frames (grass=0, mature=1, super=2)
- Animal sheets: 4×4 grid (col=facing direction, row=hunger state)
- MATURE tiles use `COLOR_MATURE_VARIANTS[(x*7 + y*13) % 4]` for 4 green shades (deterministic, position-based, no extra state)
- Falls back to colored rectangles if textures unavailable

## Workflow Instructions
- After editing files, **commit and push** to git
- Keep this file updated as the project evolves
