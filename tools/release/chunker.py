"""Content-defined chunking for game updates (docs/HOSTING.md).

A file is cut where a rolling gear hash of the last bytes has its low CUT_BITS bits all zero, so a cut depends only on
the bytes just before it: inserting or changing data moves the cuts near the change and nowhere else, and an update
only downloads the chunks that are new. Chunks are between MIN_SIZE and MAX_SIZE (about 2 MiB on average).

The gear table and the parameters must never change: chunks already published and installed are found by these cuts.
The launchers never chunk anything; they only read the manifest. Pure numpy, about 30-60 s per GiB.
"""
import hashlib

import numpy as np

CUT_BITS = 21
MIN_SIZE = 512 * 1024
MAX_SIZE = 8 * 1024 * 1024
BLOCK = 64 * 1024 * 1024
_MASK = (1 << CUT_BITS) - 1
_GEAR = np.array([int.from_bytes(hashlib.sha256(b"aetherion-gear-%d" % i).digest()[:4], "little") for i in range(256)],
                 dtype=np.uint32)


def _candidates(path: str):
    """Offsets just after every byte where the rolling hash cuts, in order."""
    out = []
    tail = np.zeros(0, dtype=np.uint8)
    base = 0  # file offset of tail[0]
    with open(path, "rb") as f:
        while True:
            raw = f.read(BLOCK)
            if not raw:
                break
            data = np.concatenate([tail, np.frombuffer(raw, dtype=np.uint8)])
            g = _GEAR[data]
            h = g.copy()
            for k in range(1, CUT_BITS):
                h[k:] += g[:-k] << np.uint32(k)
            h &= np.uint32(_MASK)
            hits = np.flatnonzero(h == 0)
            # The first len(tail) positions were already scanned with their full history last block.
            hits = hits[hits >= len(tail)]
            out.extend((hits + base + 1).tolist())
            keep = CUT_BITS - 1
            tail = data[-keep:] if len(data) >= keep else data
            base += len(data) - len(tail)
    return out


def cuts(path: str, size: int):
    """Chunk end offsets for a file of this size (the last one is the size)."""
    ends = []
    pos = 0
    for c in _candidates(path):
        while c - pos > MAX_SIZE:
            pos += MAX_SIZE
            ends.append(pos)
        if c - pos >= MIN_SIZE and c < size:
            ends.append(c)
            pos = c
    while size - pos > MAX_SIZE:
        pos += MAX_SIZE
        ends.append(pos)
    if size > pos or size == 0:
        ends.append(size)
    return ends


def chunk_file(path: str):
    """[(offset, size, sha256 hex)] covering the file, plus the whole file's sha256."""
    import os
    size = os.path.getsize(path)
    ends = cuts(path, size)
    out = []
    whole = hashlib.sha256()
    with open(path, "rb") as f:
        pos = 0
        for e in ends:
            data = f.read(e - pos)
            whole.update(data)
            out.append((pos, e - pos, hashlib.sha256(data).hexdigest()))
            pos = e
    return out, whole.hexdigest()


if __name__ == "__main__":
    import sys
    import time
    t = time.time()
    ch, digest = chunk_file(sys.argv[1])
    sizes = [c[1] for c in ch]
    print("%d chunks, mean %.2f MiB, min %d, max %d, %s, %.1f s" % (len(ch), sum(sizes) / max(len(ch), 1) / 2**20,
                                                                    min(sizes), max(sizes), digest, time.time() - t))
