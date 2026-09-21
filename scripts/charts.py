# docs/img/*.svg 를 다시 만든다. 수치는 docs/02-collector-compare.md 와 같아야 한다.
#   python3 scripts/charts.py   (matplotlib, Noto Sans CJK 필요)
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

C = ["g1", "shenandoah", "zgc", "zgc-gen"]
BLUE, ORANGE = "#2a78d6", "#eb6834"
BLUE_D, ORANGE_D = "#3987e5", "#d95926"

def theme(dark):
    txt = "#ffffff" if dark else "#0b0b0b"
    sec = "#c3c2b7" if dark else "#52514e"
    grid = "#3a3a38" if dark else "#e4e3df"
    plt.rcParams.update({
        "font.family": "Noto Sans CJK JP", "font.size": 11,
        "text.color": txt, "axes.labelcolor": sec, "xtick.color": sec, "ytick.color": sec,
        "axes.edgecolor": grid, "axes.facecolor": "none", "figure.facecolor": "none", "savefig.facecolor": "none",
        "axes.grid": True, "grid.color": grid, "grid.linewidth": 0.8, "axes.axisbelow": True,
        "axes.spines.top": False, "axes.spines.right": False, "axes.spines.left": False, "svg.fonttype": "path",
    })
    return (BLUE_D, ORANGE_D) if dark else (BLUE, ORANGE), txt, sec

def bar_labels(ax, bars, fmt, sec, log=False):
    for b in bars:
        v = b.get_height()
        if v == 0: continue
        ax.annotate(fmt(v), (b.get_x() + b.get_width() / 2, v), ha="center", va="bottom",
                    xytext=(0, 3), textcoords="offset points", fontsize=9.5, color=sec)

def chart_pause(dark):
    (c1, c2), txt, sec = theme(dark)
    default = [4.805, 0.212, 0.035, 0.012]
    leak = [5.529, 0.313, 0.034, 0.011]
    x = np.arange(4); w = 0.36
    fig, ax = plt.subplots(figsize=(8, 4.2), dpi=100)
    b1 = ax.bar(x - w/2 - 0.01, default, w, color=c1, label="default")
    b2 = ax.bar(x + w/2 + 0.01, leak, w, color=c2, label="leak-static")
    ax.set_yscale("log"); ax.set_ylim(0.005, 20)
    ax.set_xticks(x); ax.set_xticklabels(C)
    ax.set_ylabel("평균 GC 정지 (ms, 로그 눈금)")
    ax.set_title("GC Pause 평균 — 컬렉터별, default vs leak-static", loc="left", fontsize=12.5, color=txt, pad=12)
    bar_labels(ax, b1, lambda v: f"{v:.3g}", sec); bar_labels(ax, b2, lambda v: f"{v:.3g}", sec)
    ax.legend(frameon=False, loc="upper right", labelcolor=txt)
    ax.grid(axis="x", visible=False)
    fig.tight_layout()
    return fig

def chart_cost(dark):
    (c1, c2), txt, sec = theme(dark)
    pause = [4.70, 0.72, 0.07, 0.03]
    reach = [7.5, 8.2, 7.4, 17.1]
    alloc = [0, 988, 1835, 158]
    fig, axes = plt.subplots(1, 3, figsize=(11, 3.9), dpi=100)
    for ax, data, title, unit in zip(axes,
            [pause, reach, alloc],
            ["GC Pause 합계", "safepoint 도달 대기 합계", "할당 대기 합계\n(Pacing / Allocation Stall, 스레드·초)"],
            ["초", "초", "초"]):
        bars = ax.bar(C, data, 0.55, color=c1)
        ax.set_title(title, loc="left", fontsize=11.5, color=txt)
        ax.set_ylabel(unit); ax.grid(axis="x", visible=False)
        ax.set_ylim(0, max(data) * 1.22 if max(data) > 0 else 1)
        bar_labels(ax, bars, lambda v: ("0" if v == 0 else f"{v:,.3g}" if v < 100 else f"{v:,.0f}"), sec)
        ax.tick_params(axis="x", labelsize=9.5)
    fig.suptitle("3분 부하 동안 시간이 어디로 갔나 — default 프로필, 2코어/2GB", x=0.01, ha="left", fontsize=12.5, color=txt)
    fig.tight_layout(rect=(0, 0, 1, 0.93))
    return fig

def chart_leak(dark):
    (c1, c2), txt, sec = theme(dark)
    default = [0, 988, 1835, 158]
    leak = [0, 1364, 2422, 307]
    x = np.arange(4); w = 0.36
    fig, ax = plt.subplots(figsize=(8, 4.2), dpi=100)
    b1 = ax.bar(x - w/2 - 0.01, default, w, color=c1, label="default")
    b2 = ax.bar(x + w/2 + 0.01, leak, w, color=c2, label="leak-static")
    ax.set_xticks(x); ax.set_xticklabels(C)
    ax.set_ylabel("할당 대기 합계 (스레드·초)"); ax.set_ylim(0, 2900)
    ax.set_title("누수가 생기면 저지연 컬렉터는 '멈추는' 대신 '할당을 재운다'", loc="left", fontsize=12.5, color=txt, pad=12)
    bar_labels(ax, b1, lambda v: "0" if v == 0 else f"{v:,.0f}", sec); bar_labels(ax, b2, lambda v: "0" if v == 0 else f"{v:,.0f}", sec)
    ax.annotate("할당 대기 0\n(대신 Mixed GC 정지가\n5.4 → 8.5ms 로 늘어남)", (0, 60), ha="center", fontsize=9.5, color=sec)
    ax.legend(frameon=False, loc="upper right", labelcolor=txt); ax.grid(axis="x", visible=False)
    fig.tight_layout()
    return fig

for name, fn in [("pause", chart_pause), ("time-budget", chart_cost), ("leak-alloc-wait", chart_leak)]:
    for dark in (False, True):
        fig = fn(dark)
        fig.savefig(f"docs/img/{name}-{'dark' if dark else 'light'}.svg", format="svg")
        plt.close(fig)
print("ok")
