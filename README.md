# Ecosystem Game

A grid-based 2D ecosystem simulator built in [Godot Engine](https://godotengine.org/). In this game, your goal is to stabilize an ecosystem by planting different types of flora and managing predators to prevent extinction.

## 🎯 Objective
*   **Win Condition:** Cover **80% or more** of the map's area with plants and stabilize the ecosystem.
*   **Lose Condition:** **Extinction.** The map has zero plants left *and* you have 0 seeds remaining to plant more.

## 🛠️ Resources & Controls
Your primary resource is **Seeds**. You start with 20 seeds and can hold a maximum of 30. Seeds are spent to place plants or apex predators, and can naturally replenish (30% chance) whenever a grass tile fully matures.

### Controls:
*   **Left Mouse Button:** Deploys the currently selected seed (mature grass) from the UI.
*   **Right Mouse Button (Debug):** Directly spawns a Red Predator.
*   **Middle Mouse Button (Debug):** Directly spawns an Apex Predator.
*   **Shift + Left Click (Debug):** Place a cluster of **Water** tiles.
*   **Ctrl + Left Click (Debug):** Place a cluster of **Stone** tiles (Animals cannot walk through these).
*   **Alt + Left Click (Debug):** Define the **Plantable Zone**. 
    *   Click 1: Set Top-Left corner.
    *   Click 2: Set Bottom-Right corner.
    *   (The screen will refresh to show Arid vs Desert colors based on the new zone).

## 🌱 Entities & Mechanics

### Flora (Plants)
Plants spread across the map and are the primary source of life for the ecosystem.
*   **GRASS (Bright Green):** The growing phase of the plant.
*   **MATURE Grass (Dark Green):** Dark green tiles that spread to neighbors.
*   **POISON Plant (Purple):** Has a small chance to spawn. Herbivores that eat this die instantly.
*   **DUNG (Brown):** Left by herbivores. Slowly ripens into mature plants.

### Animals
*   **Red Predators (Red):** Herbivores. They eat plants and poop out dung. If they eat enough, they reproduce.
*   **Apex Predators (Blue):** Carnivores. They hunt Red Predators. They have a "Home" position they return to for rest.
*   **Thirst && Starvation:** Animals must find water and food. 
    *   **Thirst:** Animals will scan for blue **Water** tiles. If thirsty (100+) and no water is seen, they will walk in a straight line to find it.
    *   **Limits:** Herbivores starve at 300 ticks. Apex Predators starve at 500 ticks. Both die at 300 thirst.

## 🚀 How to Run
1. Open Godot Engine (Version 4.x recommended).
2. Import the `project.godot` file.
3. Use the **Debug Controls** to place water, stones, and define your forest zone before starting!
4. Run the project!