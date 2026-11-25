"""Make the README images from the testbench outputs.

Run the simulations first (vivado -mode batch -source sim/run_sim.tcl), then:

    python sim/make_media.py

Reads build/sim/*.csv and build/sim/frame.ppm, writes media/*.png and media/*.gif.
Needs numpy, matplotlib and Pillow.
"""
import csv
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from PIL import Image

ROOT  = Path(__file__).resolve().parent.parent
SIM   = ROOT / "build" / "sim"
MEDIA = ROOT / "media"

INK, ACCENT, ACCENT2, GRID = "#1f2328", "#0969da", "#cf222e", "#d0d7de"
plt.rcParams.update({
    "font.size": 10, "axes.edgecolor": GRID, "axes.labelcolor": INK, "xtick.color": INK,
    "ytick.color": INK, "axes.spines.top": False, "axes.spines.right": False,
    "figure.dpi": 110, "savefig.bbox": "tight", "savefig.facecolor": "white",
})


def read_csv(name):
    with open(SIM / name, newline="") as f:
        return list(csv.DictReader(f))


# ---------------------------------------------------------------------------
# Screen drawing: the same shapes as rtl/pong_renderer.sv
# ---------------------------------------------------------------------------
FONT = {  # 3x5, top row first
    0: "### #.# #.# #.# ###", 1: ".#. ##. .#. .#. ###", 2: "### ..# ### #.. ###",
    3: "### ..# ### ..# ###", 4: "#.# #.# ### ..# ..#", 5: "### #.. ### ..# ###",
    6: "### #.. ### #.# ###", 7: "### ..# ..# ..# ..#", 8: "### #.# ### #.# ###",
    9: "### #.# ### ..# ###",
}
WHITE, GREY = 255, 0x60


def draw_screen(ball_x, ball_y, lpad_y, rpad_y, score_l, score_r):
    img = np.zeros((480, 640), np.uint8)
    rows = np.arange(480)
    img[(rows >> 4) & 1 == 1, 318:322] = GREY                    # dashed net
    for score, ox in ((score_l, 256), (score_r, 360)):
        for r, line in enumerate(FONT[score].split()):
            for c, ch in enumerate(line):
                if ch == "#":
                    img[24 + 8 * r: 32 + 8 * r, ox + 8 * c: ox + 8 * c + 8] = WHITE
    img[lpad_y:lpad_y + 64, 24:34]   = WHITE
    img[rpad_y:rpad_y + 64, 606:616] = WHITE
    img[ball_y:ball_y + 8, ball_x:ball_x + 8] = WHITE
    return img


def read_ppm(path):
    tokens = path.read_text().split()
    assert tokens[0] == "P3"
    w, h = int(tokens[1]), int(tokens[2])
    return np.array(tokens[4:], np.uint8).reshape(h, w, 3)


def make_frame():
    frame = read_ppm(SIM / "frame.ppm")
    Image.fromarray(frame).save(MEDIA / "sim_frame.png", optimize=True)

    # The animation below is drawn in Python from the game state the RTL produced.
    # Make sure that drawing is pixel-exact with what the RTL renderer drew.
    mine = draw_screen(420, 300, 120, 260, 3, 7)
    assert (frame[:, :, 0] == mine).all(), "Python drawing differs from the RTL frame"
    print("sim_frame.png       (Python screen drawing matches the RTL pixel for pixel)")


def make_gameplay_gif():
    rows  = read_csv("game.csv")
    rally = [r for r in rows if r["test"] == "rally"][:1200]
    miss  = [r for r in rows if r["test"] == "miss"]
    clip  = rally[::2] + miss[::2]
    lut = np.zeros(256, np.uint8)            # grey level -> palette index
    lut[GREY], lut[WHITE] = 1, 2
    frames = []
    for r in clip:
        v = {k: int(r[k]) for k in r if k != "test"}
        screen = draw_screen(v["ball_x"], v["ball_y"], v["lpad_y"], v["rpad_y"], v["score_l"], v["score_r"])
        im = Image.fromarray(lut[screen], "P")
        im.putpalette([0, 0, 0, GREY, GREY, GREY, WHITE, WHITE, WHITE])
        frames.append(im)
    frames[0].save(MEDIA / "sim_gameplay.gif", save_all=True, append_images=frames[1:],
                   duration=33, loop=0, optimize=True)
    print(f"sim_gameplay.gif    ({len(frames)} frames)")


# ---------------------------------------------------------------------------
# Waveforms
# ---------------------------------------------------------------------------
def digital(ax, x, y, level, label, color=ACCENT):
    y = np.asarray(y, float)
    ax.step(x, level + 0.7 * y, where="post", color=color, lw=1.6)
    ax.text(x[0] - (x[-1] - x[0]) * 0.01, level + 0.35, label, ha="right", va="center",
            color=INK, fontsize=10, family="monospace")


def strip_axes(ax):
    ax.set_yticks([])
    ax.spines["left"].set_visible(False)


def make_debounce():
    rows = read_csv("debounce.csv")
    cyc  = np.array([int(r["cycle"]) for r in rows])
    din  = np.array([int(r["in"]) for r in rows])
    dout = np.array([int(r["out"]) for r in rows])

    fig, ax = plt.subplots(figsize=(11, 2.4))
    digital(ax, cyc, din,  1.2, "btn in ")
    digital(ax, cyc, dout, 0.0, "btn out", ACCENT2)
    strip_axes(ax)
    ax.set_xlim(cyc[0], cyc[-1])
    ax.set_xlabel("clock cycle  (testbench uses CYCLES = 16)")

    # Label the phases of the test where the input changes
    edges = np.flatnonzero(np.diff(din)) + 1
    press   = next(e for e in edges if din[e] == 1 and np.all(din[e:e + 20] == 1))
    rise    = np.flatnonzero(np.diff(dout) == 1)[0] + 1
    fall    = np.flatnonzero(np.diff(dout) == -1)[0] + 1
    drop = next(e for e in edges if e > rise and din[e] == 0)
    back = next(e for e in edges if e > drop and din[e] == 1)
    rel  = next(e for e in edges if e > back and din[e] == 0)
    spans = ((edges[0], press - 1, "bouncing: ignored"),
             (press, rise, f"press: {rise - press} cycles\n(16 stable + 2 sync)"),
             (drop, back, "dropout:\nignored"),
             (rel, fall, f"release: {fall - rel} cycles"))
    for x0, x1, text in spans:
        ax.annotate("", (cyc[x1], 2.15), (cyc[x0], 2.15), arrowprops=dict(arrowstyle="<->", color=INK, lw=0.8))
        ax.text((cyc[x0] + cyc[x1]) / 2, 2.25, text, ha="center", va="bottom", fontsize=9)
    ax.set_ylim(-0.2, 2.9)
    ax.set_title("tb_debounce: button 0", loc="left", color=INK)
    fig.savefig(MEDIA / "wave_debounce.png")
    plt.close(fig)
    print("wave_debounce.png")


def make_video_timing():
    line  = read_csv("video_line.csv")
    frame = read_csv("video_frame.csv")
    fig, (a1, a2) = plt.subplots(2, 1, figsize=(11, 5.4), gridspec_kw={"hspace": 0.75, "height_ratios": [1, 1.4]})

    def col(rows, key):                  # repeat the last value so the final step is drawn
        v = [int(r[key]) for r in rows]
        return v + v[-1:]

    x = np.arange(len(line) + 1)
    digital(a1, x, col(line, "de"),    1.2, "de    ")
    digital(a1, x, col(line, "hsync"), 0.0, "hsync ", ACCENT2)
    for x0, x1, name in ((0, 640, "visible: 640"), (640, 656, "FP\n16"), (656, 752, "sync: 96"), (752, 800, "BP: 48")):
        a1.axvline(x0, color=GRID, lw=0.8, zorder=0)
        a1.text((x0 + x1) / 2, 2.05, name, ha="center", va="bottom", fontsize=9)
    strip_axes(a1); a1.set_xlim(0, 800); a1.set_ylim(-0.2, 2.6)
    a1.set_xlabel("x (pixel clocks, 39.7 ns each)")
    a1.set_title("tb_video_sync: one line (800 pixels, 31.8 µs)", loc="left", pad=18)

    y = np.arange(len(frame) + 1)
    digital(a2, y, col(frame, "de"),         2.4, "de         ")
    digital(a2, y, col(frame, "vsync"),      1.2, "vsync      ", ACCENT2)
    digital(a2, y, col(frame, "frame_tick"), 0.0, "frame_tick ", INK)
    tick = next(int(r["y"]) for r in frame if r["frame_tick"] == "1")
    a2.annotate("frame_tick at y = 480:\nthe game updates here", (tick + 1, 0.5), (400, 0.35), fontsize=9,
                va="center", ha="right", arrowprops=dict(arrowstyle="->", color=INK, lw=0.8))
    a2.annotate("vsync: 2 lines", (491, 1.5), (400, 1.55), fontsize=9, va="center", ha="right",
                arrowprops=dict(arrowstyle="->", color=INK, lw=0.8))
    for y0, y1, name in ((0, 480, "visible: 480"), (480, 525, "blanking\n45")):
        a2.axvline(y0, color=GRID, lw=0.8, zorder=0)
        a2.text((y0 + y1) / 2, 3.25, name, ha="center", va="bottom", fontsize=9)
    strip_axes(a2); a2.set_xlim(0, 525); a2.set_ylim(-0.2, 3.8)
    a2.set_xlabel("y (lines)")
    a2.set_title("tb_video_sync: one frame (525 lines, 16.7 ms)", loc="left")
    fig.savefig(MEDIA / "wave_video_timing.png")
    plt.close(fig)
    print("wave_video_timing.png")


def make_tmds_balance():
    rows = read_csv("tmds.csv")
    sel  = [r for r in rows if r["section"] in ("00", "FF", "55", "10")]
    sel += [r for r in rows if r["section"] == "random"][:2000]
    data = np.array([int(r["data"]) for r in sel])
    raw  = np.cumsum([2 * bin(d).count("1") - 8 for d in data])   # if bytes were sent as-is
    tmds = np.array([int(r["disparity"]) for r in sel])
    n    = np.arange(len(sel))

    fig, (a1, a2) = plt.subplots(2, 1, figsize=(11, 4.4), sharex=True, gridspec_kw={"hspace": 0.35})
    a1.plot(n, raw, color=INK, lw=1.2)
    a1.set_ylabel("#1s − #0s")
    a1.set_title("Without TMDS: sending the 8-bit bytes as they are drifts without limit", loc="left")
    a2.plot(n, tmds, color=ACCENT, lw=0.9)
    a2.axhspan(-10, 10, color=ACCENT, alpha=0.08, lw=0)
    a2.set_ylim(-14, 14); a2.set_ylabel("#1s − #0s")
    a2.set_title(f"tb_tmds_encoder: the encoder keeps the line balanced (worst seen ±{abs(tmds).max()})", loc="left")
    starts = {}
    for i, r in enumerate(sel):
        starts.setdefault(r["section"], i)
    for name, i in starts.items():
        for a in (a1, a2):
            a.axvline(i, color=GRID, lw=0.8, zorder=0)
        a1.text(i + 15, a1.get_ylim()[1], f"0x{name}" if name != "random" else "random bytes",
                va="top", fontsize=9)
    a2.set_xlabel("data symbol")
    fig.savefig(MEDIA / "tmds_dc_balance.png")
    plt.close(fig)
    print("tmds_dc_balance.png")


def make_hdmi_line():
    rows = read_csv("hdmi_line.csv")
    kinds = [r["kind"] for r in rows]
    lum   = np.array([int(r["rgb"][:2], 16) if r["kind"] == "DATA" else 0 for r in rows])

    fig = plt.figure(figsize=(11, 5.6))
    gs  = fig.add_gridspec(2, 1, height_ratios=[1, 2.6], hspace=0.55)

    # Whole line: what each symbol period carried, and the decoded brightness
    a1 = fig.add_subplot(gs[0])
    colors = {"SYNC": ACCENT2, "IDLE": "#8c959f", "DATA": ACCENT}
    start = 0
    for i in range(1, len(kinds) + 1):
        if i == len(kinds) or kinds[i] != kinds[start]:
            a1.axvspan(start, i, ymin=0, ymax=0.18, color=colors[kinds[start]], lw=0)
            label = {"SYNC": "hsync", "IDLE": "porch", "DATA": "640 pixels"}[kinds[start]]
            a1.text((start + i) / 2, -0.05, label, ha="center", va="top", fontsize=8.5,
                    transform=a1.get_xaxis_transform())
            start = i
    a1.step(np.arange(len(lum)), 0.25 + lum / 255 * 0.7, where="post", color=INK, lw=1,
            transform=a1.get_xaxis_transform())
    a1.set_xlim(0, len(kinds)); a1.set_ylim(0, 1); strip_axes(a1); a1.set_xticks([])
    a1.set_title("tb_pong_top: line 24 decoded from the HDMI pins (score digits and net are the white/grey parts)",
                 loc="left")

    # Zoom: the serial bits of 8 pixels around x = 256, where the left "0" begins
    a2 = fig.add_subplot(gs[1])
    first = next(i for i, r in enumerate(rows) if r["x"] == "252")
    zoom  = rows[first:first + 8]
    lanes = [("clock", "clock", INK), ("red", "red", ACCENT2), ("green", "green", "#1a7f37"), ("blue", "blue", ACCENT)]
    for li, (key, name, color) in enumerate(lanes):
        bits = [int(b) for r in zoom for b in reversed(r[key])]   # LSB is sent first
        t = np.arange(len(bits) + 1)
        digital(a2, t, bits + [bits[-1]], (3 - li) * 1.25, f"{name:5} ", color)
    for k, r in enumerate(zoom):
        a2.axvline(10 * k, color=GRID, lw=0.8, zorder=0)
        px = int(r["rgb"], 16)
        a2.text(10 * k + 5, 5.15, f"x={r['x']}\n#{px:06X}", ha="center", va="bottom", fontsize=8.5,
                family="monospace")
    a2.axvline(80, color=GRID, lw=0.8, zorder=0)
    a2.set_xlim(0, 80); a2.set_ylim(-0.2, 6.0); strip_axes(a2)
    a2.set_xticks(np.arange(0, 81, 10))
    a2.set_xlabel("bit (3.97 ns each; one pixel = 10 bits, LSB first)")
    a2.set_title("Serial TMDS bits for x = 252..259: black, then the white top row of the digit",
                 loc="left")
    fig.savefig(MEDIA / "wave_hdmi_tmds.png")
    plt.close(fig)
    print("wave_hdmi_tmds.png")


if __name__ == "__main__":
    MEDIA.mkdir(exist_ok=True)
    make_frame()
    make_gameplay_gif()
    make_debounce()
    make_video_timing()
    make_tmds_balance()
    make_hdmi_line()
    print(f"written to {MEDIA}")
