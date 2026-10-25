# Particle Scene Compositor runtime

Unmodified standalone `GPUSyncNode3D` component from Particle Scene Compositor by
ChiprChopr / tvenclovas96. The editor panel and unused CPU/2D/C# variants are not installed.

- Source: https://github.com/tvenclovas96/particle-scene-compositor
- Pinned commit: `7454d1e3816af69d4c6a16a88df978760a1b4da0`
- Godot Asset Library: https://godotengine.org/asset-library/asset/3352
- License: MIT; complete upstream notice in `LICENSE`.
- Retrieved: 2026-10-06.

`scripts/atmosphere_particles.gd` instantiates this controller for every dust, mist,
drifting-seed and moth group. Its `restart`, `stop`, and synchronized completion
behavior run in the game. Continuous atmosphere groups use `one_shot = false`
and `free_on_finish = false`. Zone re-entry uses `restart()` so existing signal
connections are reused. The game owns their lifetime through the scene tree.
