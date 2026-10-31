"""r22 acceptance: round lengths and bot behaviour counts from headless Deathmatch match logs (--matchlog).

    python -I work/r22/round_stats.py work/r22/base_freight.log [more.log ...]

Prints, per log: each round's length (start -> "round N over" / "match over"), the round still running when the log
ends (and for how long), and counts of the r22 lines ([hold], [sweep], [endgame], last [botskill]).
"""
import re
import sys

T = re.compile(r"^\[match\s+([\d.]+)\] (.*)$")


def stats(path):
    rounds = []
    start = None
    last_t = 0.0
    counts = {"[hold]": 0, "[sweep]": 0, "[endgame]": 0}
    skill = ""
    over = False
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            for k in counts:
                if k in line:
                    counts[k] += 1
            if "[botskill]" in line:
                skill = line.strip()
            m = T.match(line.strip())
            if not m:
                continue
            t = float(m.group(1))
            msg = m.group(2)
            last_t = t
            if msg.startswith("deathmatch start") or re.match(r"round \d+ started", msg):
                start = t
            elif re.match(r"round \d+ over", msg) or msg.startswith("match over"):
                if start is not None:
                    rounds.append(round(t - start, 1))
                start = None
                over = over or msg.startswith("match over")
    running = round(last_t - start, 1) if start is not None and not over else None
    return rounds, running, counts, skill, last_t


def main():
    for p in sys.argv[1:]:
        rounds, running, counts, skill, last_t = stats(p)
        longest = max(rounds + ([running] if running else [])) if (rounds or running) else 0
        print("%s: %.0f s logged, %d rounds ended %s; still running: %s; longest %.0f s" % (
            p, last_t, len(rounds), rounds, ("%.0f s" % running) if running else "no", longest))
        print("   holds %d, sweeps %d, endgame entries %d" % (counts["[hold]"], counts["[sweep]"], counts["[endgame]"]))
        if skill:
            print("   " + skill)


if __name__ == "__main__":
    main()
