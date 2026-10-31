"""Per log: rounds, kills per round, and the quiet gaps (seconds between kills) inside rounds, by how many stand."""
import re, sys
T = re.compile(r"^\[match\s+([\d.]+)\] (.*)$")
for p in sys.argv[1:]:
    start = None; prev = None; gaps = []; big = []; alive = 12
    for line in open(p, encoding="utf-8", errors="replace"):
        m = T.match(line.strip())
        if not m: continue
        t = float(m.group(1)); msg = m.group(2)
        if msg.startswith("deathmatch start") or re.match(r"round \d+ started", msg):
            start = t; prev = t; alive = 12
        elif "killed by" in msg and start is not None:
            g = t - prev; gaps.append(g)
            if g > 30: big.append((round(g), alive))
            prev = t; alive -= 1
        elif re.match(r"round \d+ over", msg) or msg.startswith("match over"):
            start = None
    n = len(gaps)
    print("%-32s kills %3d  gaps>30s %2d  sum of gaps>30s %4.0f  [(gap, standing)] %s" % (p.split("/")[-1], n, len(big), sum(g for g, _ in big), big[:12]))
