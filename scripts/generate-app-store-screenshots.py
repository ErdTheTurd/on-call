#!/usr/bin/env python3
"""Generate App Store Connect–valid screenshots.

iPhone 6.5": 1284 × 2778 (optional 1242 × 2688)
iPad 13":    2064 × 2752 (optional 2048 × 2732)

Usage:
  python3 scripts/generate-app-store-screenshots.py --ipad
  python3 scripts/generate-app-store-screenshots.py --also-1242 --ipad
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 1284, 2778
W_ALT, H_ALT = 1242, 2688
IPAD_W, IPAD_H = 2064, 2752
IPAD_ALT_W, IPAD_ALT_H = 2048, 2732
SCALE = 1.0

BG = (7, 11, 23)
SURFACE = (22, 28, 44)
SURFACE_HI = (32, 40, 60)
BORDER = (48, 56, 78)
ACCENT = (79, 142, 247)
SUCCESS = (52, 211, 153)
WARNING = (251, 191, 36)
DANGER = (248, 113, 113)
TEXT = (255, 255, 255)
TEXT2 = (170, 180, 200)
TEXT3 = (110, 120, 145)

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "AppStoreScreenshots"


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    size = max(18, int(round(size * SCALE)))
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size=size, index=0)
        except OSError:
            continue
    return ImageFont.load_default()


def round_rect(draw: ImageDraw.ImageDraw, xy, radius: int, fill, outline=None, width: int = 1):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def status_bar(draw: ImageDraw.ImageDraw, y: int = 54):
    draw.text((72, y), "9:41", font=font(42, True), fill=TEXT)
    draw.text((W - 220, y), "•••• 100%", font=font(36, True), fill=TEXT)


def brand_header(draw: ImageDraw.ImageDraw, title: str, subtitle: str):
    status_bar(draw)
    draw.text((72, 140), "MD Shift", font=font(36, True), fill=ACCENT)
    draw.text((72, 200), title, font=font(64, True), fill=TEXT)
    draw.text((72, 280), subtitle, font=font(34), fill=TEXT2)


def card(draw: ImageDraw.ImageDraw, x0, y0, x1, y1):
    round_rect(draw, (x0, y0, x1, y1), 28, SURFACE, outline=BORDER, width=2)


def pill(draw: ImageDraw.ImageDraw, x, y, text: str, fill, fg=TEXT):
    f = font(28, True)
    bbox = draw.textbbox((0, 0), text, font=f)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    pad_x, pad_y = 22, 14
    round_rect(draw, (x, y, x + tw + pad_x * 2, y + th + pad_y * 2), 999, fill)
    draw.text((x + pad_x, y + pad_y - 2), text, font=f, fill=fg)
    return tw + pad_x * 2


def metric(draw: ImageDraw.ImageDraw, x, y, w, label: str, value: str, color):
    round_rect(draw, (x, y, x + w, y + 150), 24, SURFACE_HI, outline=BORDER, width=2)
    draw.text((x + 28, y + 28), value, font=font(48, True), fill=color)
    draw.text((x + 28, y + 92), label, font=font(28), fill=TEXT2)


def save(img: Image.Image, name: str, sizes: list[tuple[int, int]]):
    OUT.mkdir(parents=True, exist_ok=True)
    for width, height in sizes:
        out = img if (width, height) == (W, H) else img.resize((width, height), Image.Resampling.LANCZOS)
        path = OUT / f"{name}-{width}x{height}.png"
        out.save(path, format="PNG", optimize=True)
        assert out.size == (width, height), out.size
        print(f"wrote {path} ({out.size[0]}×{out.size[1]})")


def shot_doctor_home(sizes):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    brand_header(d, "Doctor Home", "Assigned coverage at a glance")

    card(d, 56, 380, W - 56, 720)
    d.text((88, 420), "Good evening, Dr. Dunn", font=font(42, True), fill=TEXT)
    d.text((88, 480), "2 shifts this week · Orthopedics", font=font(30), fill=TEXT2)
    gap = 18
    mw = (W - 112 - gap * 2) // 3
    metric(d, 88, 540, mw, "Tokens", "3", ACCENT)
    metric(d, 88 + mw + gap, 540, mw, "Assigned", "2", SUCCESS)
    metric(d, 88 + 2 * (mw + gap), 540, mw, "Trades", "1", WARNING)

    card(d, 56, 760, W - 56, 1480)
    d.text((88, 800), "Upcoming", font=font(36, True), fill=TEXT)
    rows = [
        ("Fri", "Average Hospital", "$1,450", "Confirmed", SUCCESS),
        ("Sun", "Riverside General", "$1,650", "Confirmed", SUCCESS),
        ("Wed", "Average Hospital", "$1,450", "Trade pending", WARNING),
    ]
    y = 880
    for day, place, rate, status, color in rows:
        round_rect(d, (88, y, 168, y + 80), 18, (25, 45, 85))
        d.text((108, y + 22), day, font=font(30, True), fill=ACCENT)
        d.text((196, y + 10), place, font=font(34, True), fill=TEXT)
        d.text((196, y + 52), rate, font=font(28), fill=TEXT2)
        bg = (20, 55, 45) if color == SUCCESS else (55, 45, 18)
        pill(d, W - 390, y + 18, status, bg, color)
        y += 140

    card(d, 56, 1540, W - 56, 2100)
    d.text((88, 1580), "Availability", font=font(36, True), fill=TEXT)
    days = ["M", "T", "W", "T", "F", "S", "S"]
    open_idx = {1, 4, 5}
    cell_w = (W - 176 - 6 * 12) // 7
    for i, label in enumerate(days):
        x = 88 + i * (cell_w + 12)
        fill = (30, 55, 100) if i in open_idx else SURFACE_HI
        round_rect(d, (x, 1660, x + cell_w, 1780), 16, fill)
        d.text((x + cell_w // 2 - 12, 1695), label, font=font(32, True), fill=TEXT)
    d.text((88, 1840), "Highlighted days are open for call.", font=font(28), fill=TEXT3)

    save(img, "01-doctor-home", sizes)


def shot_open_shifts(sizes):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    brand_header(d, "Open Shifts", "Claim open call with locked rates")

    cards = [
        ("Orthopedics · Locked rate", "Average Hospital", "Sat Sep 5 · 24h call", "$1,850 / day", SUCCESS),
        ("Emergency · Smart Algo", "Riverside General", "Mon Sep 7 · 24h call", "$1,620 / day", WARNING),
        ("Orthopedics", "St. Anne's Medical Center", "Thu Sep 10 · 24h call", "$1,450 / day", ACCENT),
    ]
    y = 380
    for kicker, title, sub, rate, tone in cards:
        card(d, 56, y, W - 56, y + 320)
        d.text((88, y + 36), kicker, font=font(28, True), fill=tone)
        d.text((88, y + 90), title, font=font(44, True), fill=TEXT)
        d.text((88, y + 155), sub, font=font(30), fill=TEXT2)
        d.text((88, y + 220), rate, font=font(44, True), fill=TEXT)
        pill(d, W - 260, y + 220, "Claim", ACCENT, TEXT)
        y += 360

    save(img, "02-open-shifts", sizes)


def shot_hospital(sizes):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    brand_header(d, "Hospital Dashboard", "Fill rate and gaps under control")

    gap = 18
    mw = (W - 112 - gap * 2) // 3
    metric(d, 56, 380, mw, "Fill rate", "94%", SUCCESS)
    metric(d, 56 + mw + gap, 380, mw, "Open", "3", WARNING)
    metric(d, 56 + 2 * (mw + gap), 380, mw, "Pending", "5", ACCENT)

    card(d, 56, 580, W - 56, 1180)
    d.text((88, 620), "Tonight", font=font(36, True), fill=TEXT)
    rows = [
        ("Orthopedics", "Dr. Dunn", "Filled", SUCCESS),
        ("Emergency", "Dr. Ellison", "Filled", SUCCESS),
        ("Anesthesiology", "Unfilled", "Needs cover", WARNING),
    ]
    y = 700
    for spec, who, status, color in rows:
        d.text((88, y), spec, font=font(34, True), fill=TEXT)
        d.text((88, y + 48), who, font=font(28), fill=TEXT2)
        bg = (20, 55, 45) if color == SUCCESS else (55, 45, 18)
        pill(d, W - 360, y + 10, status, bg, color)
        y += 130

    card(d, 56, 1240, W - 56, 2100)
    d.text((88, 1280), "This week", font=font(36, True), fill=TEXT)
    y = 1360
    for day in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]:
        open_day = day in ("Wed", "Sat")
        d.text((88, y), day, font=font(30, True), fill=TEXT2)
        bar_color = WARNING if open_day else SUCCESS
        round_rect(d, (180, y + 12, W - 220, y + 36), 8, bar_color)
        d.text((W - 200, y), "1 open" if open_day else "Covered", font=font(26), fill=TEXT3)
        y += 90

    save(img, "03-hospital-dashboard", sizes)


def shot_alter(sizes):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    brand_header(d, "Alter Rates", "Smart Algo or locked hospital rates")

    card(d, 56, 380, W - 56, 820)
    d.text((88, 430), "Saturday · Orthopedics", font=font(42, True), fill=TEXT)
    d.text((88, 510), "Smart Algo", font=font(30, True), fill=ACCENT)
    d.text((88, 570), "$1,450 → $1,850", font=font(48, True), fill=TEXT)
    round_rect(d, (88, 660, W - 88, 692), 10, SURFACE_HI)
    round_rect(d, (88, 660, 88 + int((W - 176) * 0.72), 692), 10, ACCENT)
    d.text((88, 720), "Escalating as the shift approaches. Floor locked.", font=font(28), fill=TEXT2)

    card(d, 56, 860, W - 56, 1220)
    d.text((88, 910), "Monday · Emergency", font=font(42, True), fill=TEXT)
    d.text((88, 990), "Locked rate", font=font(30, True), fill=SUCCESS)
    d.text((88, 1050), "$1,600 / day", font=font(52, True), fill=TEXT)
    d.text((88, 1130), "Hospital proprietary rate — no ambiguous ranges.", font=font(28), fill=TEXT2)

    card(d, 56, 1280, W - 56, 1680)
    d.text((88, 1330), "Apply to all Mondays", font=font(36, True), fill=TEXT)
    d.text((88, 1400), "One tap pushes this rate pattern across the month.", font=font(28), fill=TEXT2)
    round_rect(d, (88, 1500, W - 88, 1600), 22, ACCENT)
    d.text((220, 1528), "Apply Smart Algo to Mondays", font=font(34, True), fill=TEXT)

    save(img, "04-alter-rates", sizes)


def shot_approvals(sizes):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    brand_header(d, "Approvals", "Verify doctors before they cover")

    x = 56
    for label, on in [("Needs review", True), ("Approved", False), ("Waitlisted", False)]:
        fill = ACCENT if on else SURFACE_HI
        fg = TEXT if on else TEXT2
        w = pill(d, x, 380, label, fill, fg)
        x += w + 16

    rows = [
        ("Maya Ellison, MD", "Emergency Medicine · NPI 1487290365", "Waiting 2 days"),
        ("Carlos Rivera, DO", "Orthopedics · NPI 1678934210", "Applied today"),
        ("Riverside General", "Hospital · NPI 1902847365", "Waiting 1 day"),
    ]
    y = 500
    for name, detail, wait in rows:
        card(d, 56, y, W - 56, y + 340)
        d.text((88, y + 40), name, font=font(38, True), fill=TEXT)
        d.text((88, y + 100), detail, font=font(28), fill=TEXT2)
        pill(d, W - 360, y + 40, wait, (55, 45, 18), WARNING)
        pill(d, 88, y + 180, "Approve", (20, 90, 70), SUCCESS)
        pill(d, 300, y + 180, "Waitlist", (30, 50, 90), ACCENT)
        pill(d, 520, y + 180, "Reject", (70, 30, 40), DANGER)
        y += 380

    save(img, "05-approvals", sizes)


def shot_analytics(sizes):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    brand_header(d, "Analytics", "Savings you can audit")

    gap = 18
    mw = (W - 112 - gap) // 2
    metric(d, 56, 380, mw, "Saved this month", "$48,200", SUCCESS)
    metric(d, 56 + mw + gap, 380, mw, "Per day avg", "$1,606", ACCENT)

    card(d, 56, 580, W - 56, 1180)
    d.text((88, 630), "Where it came from", font=font(36, True), fill=TEXT)
    lines = [
        ("Early fills vs escalation", "$31,400", SUCCESS),
        ("Late cancel penalties", "$9,800", WARNING),
        ("Trade settlements", "$7,000", ACCENT),
    ]
    y = 720
    for label, value, color in lines:
        d.text((88, y), label, font=font(32), fill=TEXT2)
        d.text((W - 320, y), value, font=font(34, True), fill=color)
        y += 100
    d.text((88, 1050), "Every dollar is an auditable event.", font=font(28), fill=TEXT3)

    card(d, 56, 1240, W - 56, 1980)
    d.text((88, 1290), "Fill performance", font=font(36, True), fill=TEXT)
    heights = [0.55, 0.7, 0.82, 0.76, 0.91, 0.88, 0.94]
    bar_w = 96
    gap_b = 28
    total = 7 * bar_w + 6 * gap_b
    x0 = (W - total) // 2
    base = 1880
    for i, h in enumerate(heights):
        x = x0 + i * (bar_w + gap_b)
        bh = int(420 * h)
        round_rect(d, (x, base - bh, x + bar_w, base), 12, ACCENT)
    d.text((88, 1920), "Last 7 days · higher is healthier coverage", font=font(26), fill=TEXT3)

    save(img, "06-analytics", sizes)


def render_all(sizes: list[tuple[int, int]]) -> None:
    shot_doctor_home(sizes)
    shot_open_shifts(sizes)
    shot_hospital(sizes)
    shot_alter(sizes)
    shot_approvals(sizes)
    shot_analytics(sizes)


def main():
    global W, H, SCALE
    parser = argparse.ArgumentParser()
    parser.add_argument("--also-1242", action="store_true", help="Also write iPhone 1242×2688")
    parser.add_argument("--iphone", action="store_true", help="Write iPhone sizes (default if --ipad omitted)")
    parser.add_argument("--ipad", action="store_true", help="Write iPad 13\" 2064×2752 (and 2048×2732)")
    args = parser.parse_args()
    do_iphone = args.iphone or not args.ipad
    if args.ipad and not args.iphone:
        do_iphone = False
    if not args.ipad and not args.iphone:
        do_iphone = True

    if do_iphone:
        W, H, SCALE = 1284, 2778, 1.0
        sizes = [(W, H)]
        if args.also_1242:
            sizes.append((W_ALT, H_ALT))
        render_all(sizes)
        print(f"iPhone 6.5\": upload *-{W}x{H}.png")

    if args.ipad:
        W, H, SCALE = IPAD_W, IPAD_H, 1.35
        render_all([(IPAD_W, IPAD_H), (IPAD_ALT_W, IPAD_ALT_H)])
        print(f"iPad 13\": upload *-{IPAD_W}x{IPAD_H}.png (required if the app runs on iPad)")
        print(f"iPad 12.9\" optional: *-{IPAD_ALT_W}x{IPAD_ALT_H}.png")

    print(f"Folder: {OUT}")


if __name__ == "__main__":
    main()
