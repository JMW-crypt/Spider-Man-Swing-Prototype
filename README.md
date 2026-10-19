# Spider-Man Swing Prototype

A Godot-based web swinging prototype inspired by Spider-Man 2.

## Features
- Physics-based swinging
- Custom city generation
- Character movement
- Experimental traversal mechanics

## Controls
- **WASD:** Ground movement, airborne and swing steering, and wall movement.
- **Space:** Jump/double jump, climb an attached web, or wall jump.
- **Left mouse:** Hold to attach a web; release to detach.
- **Q + left mouse:** Prefer a visible building target behind the player.
- **Automatic wall grab:** Airborne near a valid building wall or moving into
  one to attach and settle at a stable distance. WASD crawls up, down, and
  sideways; Space wall-jumps.
- **F:** Tap to deliberately detach from a wall. While web-attached, F releases the
  web and transitions to a nearby valid wall.
- **Mouse wheel:** Orbit the camera.
- **Right mouse:** Emergency web release.
- **R / F3:** Reset the player / toggle traversal telemetry.
- **E / Left Shift:** Unassigned; reserved for future controls.

## Roadmap
- Better web physics
- Momentum system
- Building collision improvements
- Larger city
