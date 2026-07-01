# Voidle - Legacy Simulation Concept GDD

*This document archives the original "Simulation & Logistics" design of Voidle before the pivot to a Global/Idle incremental model.*

## 1. Core Concept
Voidle (Legacy) was designed as a deep space-exploration and empire-management simulation. The core loop involved exploring procedurally generated star systems, colonizing planets, and managing **highly localized economies**. Players had to physically transport resources between planets and orbital stations using a fleet of ships to build up their galactic empire.

## 2. World Architecture
The universe is hierarchically generated using a seeded procedural generation system:
*   **Galaxy:** Contains multiple Star Systems.
*   **Solar System:** Contains a central Star, Planets (Terran, Ice, Lava, Gas Giant), and Asteroid Belts.
*   **Planets & Moons:** Each celestial body has its own unique orbit, rotation, and procedurally generated resource deposits.

## 3. Resource System (Dynamic & Procedural)
Resources are not hardcoded. They are generated based on a **Tier (T)** and **Rarity (R)** matrix.
*   **Rarity (1 to 15):** Determines how hard the mineral is to find (e.g., R1 is common on home planets, R15 is found only in deep space anomalies).
*   **Tier (1 to 5):** Determines the processing level (T1 = Raw Ore, T2 = Ingot, T3 = Alloy, etc.).
*   **Naming & Visuals:** Names (e.g., "Veltrium") and colors (hues based on rarity, brightness based on tier) are procedurally seeded so that "R1" is consistently the same mineral across the entire universe.

## 4. Localized Economy & Planetary Development
Every planet operates as a completely independent economic zone.
*   **Local Inventory:** Minerals mined on a planet stay on that planet's `stored_resources` dictionary.
*   **Local Energy:** Energy is produced locally by Generator districts and consumed by other districts on the same planet. If energy is negative, production halts.
*   **Districts:**
    *   **Mining Facility:** Extracts raw minerals from the planet's deposits.
    *   **Generator:** Provides local energy.
    *   **Refinery:** Converts T1 Raw Minerals into T2 Refined Minerals.
    *   **City:** Generates **Credits** (the only global currency).
    *   **SpacePort:** Allows the construction of ships and unlocks the Orbital logistics layer.
*   **Leveling Up:** Planets require specific local resources (e.g., Any T1 Mineral) to level up, which increases the max district limit.

## 5. Logistics & Fleet Management (The Micro-Management Layer)
Because inventories are local, empire expansion requires logistics.
*   **Ships:** Built at SpacePorts, ships have cargo capacities and specific roles (e.g., Freighters, Mining Ships, Stations).
*   **Orbit & Travel:** Ships physically travel between planets. Travel time is calculated based on orbital distances and ship speed.
*   **Mission System (State Machine):**
    *   *Mine:* Ships travel to asteroid belts to extract resources.
    *   *Transfer/Deliver:* Ships load cargo from Planet A, travel to Planet B, and unload cargo to allow Planet B to build advanced structures.
    *   *Deploy:* Deploying orbital stations for deep-space logistics hubs.

## 6. UI & Aesthetic
*   **Style:** Premium, dark-blue background with neon accents, glassmorphism, and dynamic micro-animations.
*   **Typography:** Orbitron for headers and numbers, providing a futuristic sci-fi feel.
*   **Camera:** Seamless zooming and panning from a Solar System macro-view down to a specific Planet's micro-view.

## 7. Reason for Pivot
While this design offered deep Factorio-like simulation, it introduced heavy micro-management. The necessity to manually move resources (e.g., Iron) from a mining colony to a developing colony interrupted the "number go up" satisfaction loop. The game is pivoting to a Global Inventory (Idle/Incremental) model to prioritize seamless expansion and visual spectacle over logistical chores.
