# Ecosystem Game

A grid-based 2D ecosystem simulator built in [Godot Engine](https://godotengine.org/). In this game, your goal is to stabilize an ecosystem by planting different types of flora and managing predators to prevent extinction.

## 🎯 Objective
*   **Win Condition:** Cover **80% or more** of the map's area with plants and stabilize the ecosystem.
*   **Lose Condition:** **Extinction.** The map has zero plants left *and* you have 0 seeds remaining to plant more.

## 🛠️ Resources & Controls
Your primary resource is **Seeds**. You start with 20 seeds and can hold a maximum of 30. Seeds are spent to place plants or apex predators, and can naturally replenish (30% chance) whenever a grass tile fully matures.

### Controls:
*   **Left Mouse Button:** Deploys the currently selected seed (Grass, Super Plant, or Apex Predator) from the UI.
*   **Right Mouse Button (Debug):** Directly spawns a Red Predator.
*   **Middle Mouse Button (Debug):** Directly spawns an Apex Predator.

## 🌱 Entities & Mechanics

### Flora (Plants)
Plants spread across the map and are the primary source of life for the ecosystem.
*   **GRASS (Bright Green):** The growing phase of the plant. It takes 50 ticks to fully grow into Mature grass, visually filling up columns as it grows.
*   **MATURE Grass (Dark Green):** Player-placed grass starts instantly as Mature (costs 3 seeds). Mature grass aggressively spreads outwards by spawning growing "GRASS" in all 4 adjacent empty tiles.
*   **SUPER Plant (Yellow):** Costs 10 seeds. A special plant that survives as a "Super" for 20 ticks. During this lifespan, it has a small chance (2.5%) each tick to aggressively launch a spore and grow grass at a distant tile (up to 5 blocks away). After 20 ticks, it transforms into regular Mature grass.

### Red Predators (Red)
These are herbivores/invaders that threaten the ecosystem by eating your plants.
*   **Spawning:** Naturally spawn along the very edges of the map.
*   **Diet:** They eat any plant. They take 3 turns to finish eating normal/super plants, but 4 turns to chew through Mature grass.
*   **Starvation && Reproduction:** If they go 8 turns without finding food, they die of starvation. If a single Red Predator manages to eat 6 plants, it will spawn an offspring in an adjacent tile.

### Apex Predators (Blue)
These are carnivores that help control the Red Predator population.
*   **Spawning:** You can spawn them using the "Predator" seed option for a hefty 30 seeds. Otherwise, they have a small chance to spawn naturally on the map edges *only* if the Red Predator count is greater than 3.
*   **Diet:** They exclusively eat Red Predators and take 3 turns to eat one. They calmly walk *over* plants without destroying them.
*   **Starvation && Reproduction:** Because they are apex predators, they can survive much longer without food—up to 50 turns until they starve. If an Apex Predator eats 3 Red Predators, it reproduces.

## 🚀 How to Run
1. Open Godot Engine (Version 4.x recommended).
2. Import the `project.godot` file.
3. Run the project!