"""Bakes the procedural noise the world shaders used to compute per pixel into one tileable RGBA texture.

    python -I tools/make_noise.py

game/assets/fx/noise_rgba.png, 512 x 512, one lattice period = 32 cells (16 px per cell):
  r = fbm (4 octaves, lacunarity 2, gain 0.5; same range as the shaders' fbm: 0 .. 0.9375)
  g = value noise (1 octave, 0 .. 1)
  b = fbm, second seed
  a = value noise, second seed
Shaders sample it at uv = p / 32.0 where they used fbm(p) / vnoise(p).
"""
from pathlib import Path

import numpy as np
from PIL import Image

SIZE = 512
PERIOD = 32
OUT = Path(__file__).resolve().parent.parent / "game" / "assets" / "fx" / "noise_rgba.png"


def value_noise(freq_cells: int, rng: np.random.Generator) -> np.ndarray:
    """Tileable smoothstep value noise with freq_cells lattice cells across the texture."""
    lattice = rng.random((freq_cells, freq_cells))
    t = np.arange(SIZE) * freq_cells / SIZE
    i0 = np.floor(t).astype(int) % freq_cells
    i1 = (i0 + 1) % freq_cells
    f = t - np.floor(t)
    u = f * f * (3.0 - 2.0 * f)
    a = lattice[np.ix_(i0, i0)]
    b = lattice[np.ix_(i0, i1)]
    c = lattice[np.ix_(i1, i0)]
    d = lattice[np.ix_(i1, i1)]
    ux = u[None, :]
    uy = u[:, None]
    return (a * (1 - ux) + b * ux) * (1 - uy) + (c * (1 - ux) + d * ux) * uy


def fbm(rng: np.random.Generator) -> np.ndarray:
    v = np.zeros((SIZE, SIZE))
    amp = 0.5
    cells = PERIOD
    for _ in range(4):
        v += amp * value_noise(cells, rng)
        cells *= 2
        amp *= 0.5
    return v


def main() -> None:
    rng = np.random.default_rng(1729)
    ch = [fbm(rng), value_noise(PERIOD, rng), fbm(rng), value_noise(PERIOD, rng)]
    img = np.stack([np.clip(c, 0.0, 1.0) for c in ch], axis=-1)
    Image.fromarray((img * 255.0 + 0.5).astype(np.uint8), "RGBA").save(OUT)
    print("wrote", OUT, [round(float(c.min()), 3) for c in ch], [round(float(c.max()), 3) for c in ch])


if __name__ == "__main__":
    main()
