# Lunar Breach

An original third-person sci-fi shooter for **Godot 4.7.2** (GDScript, no C# or .NET needed).
You fight waves of armored machines on a lunar relay station. Your shoulder drone does two kinds of hacking:

- **Breach.** A grid-hacking puzzle you solve *while combat keeps going*. If you finish it, the target's armor goes offline.
- **Quickhacks.** Cyberpunk-style remote hacks paid for with a regenerating **Bandwidth** pool. They have upload times, and a **Scan mode** slows time while you pick targets.

## Running it

1. Open Godot 4.7.2 and choose **Import**, then select `lunar_breach/project.godot`.
2. Press **F5**.

Everything is built in code from `scenes/main.tscn`, so there are no asset files to import. The input map is also created in code (`main.gd` → `_setup_input()`). To rebind keys, edit that function.

## Controls

| Action | Key |
|---|---|
| Move / sprint / jump | WASD / Shift / Space |
| Fire / aim | LMB / RMB |
| Reload | R |
| Breach target under crosshair | Q or middle mouse (press again to abort) |
| Scan mode (time slows to 25%) | Tab |
| Quickhacks | 1–4 |
| Free mouse | Esc (click to recapture) |
| Restart after death | Enter |

## How the systems fit together

```text
             aim at enemy
                  │
     ┌────────────┴─────────────┐
     ▼                          ▼
  Q: BREACH                  1-4: QUICKHACK  (costs Bandwidth, has upload time)
  grid puzzle, 7 s           ├─ ARC SURGE      3 BW  45 dmg, ignores armor
  WASD traces IN → CORE      ├─ THERMAL SPIKE  4 BW  12 dmg/s for 5 s
  optional nodes:            ├─ BLINDSIGHT     2 BW  loses track of you for 6 s
   AMP   +4 s armor-off      └─ TURNCOAT       6 BW  attacks its allies for 8 s
   LEECH +3 Bandwidth
     │                               ▲
     ▼                               │
  ARMOR OFFLINE (8 s+)  ─────────────┘  quickhacks cost half on breached targets
  bullets do full damage (armored targets take 25%)
```

- **Armor.** Every enemy starts armored (blue bubble), and bullets only do 25% damage to it. Breaching drops the armor and staggers the enemy.
- **Breach grid.** Trace a path from `IN` to `CORE` without crossing blocked cells or reusing a cell. Stepping back onto the previous cell undoes the move. You can't move or shoot while you're tracing, so pick your moment.
- **Bandwidth.** You have 12 max and regain 0.6 per second. The LEECH node refunds some.
- **Enemies.** *HOUND* walkers chase you along the navmesh and use a telegraphed melee attack (their eye flashes white). *WARDEN* drones strafe and fire energy bolts.
- **Waves.** Each wave adds enemies and gives them more HP. Clearing a wave restores 35 integrity.

## Files

| File | Purpose |
|---|---|
| `scripts/main.gd` | Input map, environment, arena and navmesh bake, wave spawning |
| `scripts/player.gd` | Movement, third-person camera, rifle, targeting, scan mode, breach and quickhack logic |
| `scripts/enemy.gd` | `Enemy` class: armor, status effects, upload timers, walker and drone AI |
| `scripts/hack_grid.gd` | The breach grid minigame (generation, input, drawing) |
| `scripts/hud.gd` | HUD, quickhack panel, scan overlay, game-over screen |
| `scripts/projectile.gd` | Enemy energy bolts |
