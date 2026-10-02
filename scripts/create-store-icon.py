"""Render our original fortress/forge badge; no downloaded assets or fonts."""
from pathlib import Path
from xml.sax.saxutils import escape
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "publishing"
OUT.mkdir(parents=True, exist_ok=True)
shapes = []

def rect(box, fill):
    shapes.append(("rect", box, fill))

def poly(points, fill):
    shapes.append(("polygon", points, fill))

def oval(box, fill):
    shapes.append(("ellipse", box, fill))

ink, stone, light, roof = "#142c30", "#aaa991", "#dccaa0", "#42606d"
rect((0, 0, 512, 512), ink)
oval((44, 58, 468, 482), "#203c3c")
oval((70, 384, 442, 448), "#102729")
poly([(76, 386), (256, 344), (436, 386), (256, 438)], "#4c6359")
poly([(76, 386), (256, 438), (256, 452), (76, 400)], "#314944")
poly([(256, 438), (436, 386), (436, 400), (256, 452)], "#283e3c")
rect((166, 217, 348, 378), light)
rect((309, 217, 348, 378), stone)
poly([(144, 221), (256, 139), (368, 221)], roof)
poly([(256, 139), (368, 221), (347, 221)], "#314d59")
poly([(145, 221), (256, 139), (263, 145), (157, 228)], "#6b8c93")
rect((250, 85, 257, 143), stone)
poly([(257, 85), (309, 99), (257, 119)], "#519ec7")
poly([(257, 85), (309, 99), (286, 108), (257, 100)], "#72bdd8")

for x in (110, 322):
    rect((x, 231, x + 80, 390), stone)
    rect((x, 231, x + 17, 390), light)
    rect((x - 8, 231, x + 88, 250), light)
    for bx in (x - 8, x + 30, x + 68):
        rect((bx, 211, bx + 20, 234), stone)
        rect((bx, 211, bx + 5, 234), light)
    rect((x + 34, 278, x + 46, 318), ink)
    rect((x + 32, 333, x + 48, 339), "#878977")

rect((190, 272, 322, 396), light)
rect((190, 375, 322, 396), stone)
poly([(213, 392), (213, 314), (219, 292), (235, 276), (256, 270),
      (277, 276), (293, 292), (299, 314), (299, 392)], ink)
poly([(222, 389), (222, 315), (229, 297), (242, 284), (256, 280),
      (270, 284), (283, 297), (290, 315), (290, 389)], "#263f3d")
poly([(232, 374), (223, 352), (233, 327), (243, 345), (257, 300),
      (276, 330), (273, 352), (284, 340), (281, 369), (258, 387)], "#e89647")
poly([(243, 372), (242, 353), (253, 333), (257, 352), (268, 343),
      (272, 368), (259, 383)], "#f5d183")
rect((198, 396, 314, 404), "#b9b39a")
rect((184, 405, 328, 414), stone)

image = Image.new("RGB", (2048, 2048))
draw = ImageDraw.Draw(image)
svg = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">',
       '<title>帝國鍛造坊：原創堡壘鍛火徽記</title>',
       '<desc>發布審查用遊戲圖示。此徽記不是遊戲畫面。</desc>']
for kind, coords, fill in shapes:
    if kind == "polygon":
        draw.polygon([(x * 4, y * 4) for x, y in coords], fill=fill)
        points = " ".join(f"{x},{y}" for x, y in coords)
        svg.append(f'<polygon points="{points}" fill="{escape(fill)}"/>')
    else:
        box = tuple(c * 4 for c in coords)
        getattr(draw, "rectangle" if kind == "rect" else "ellipse")(box, fill=fill)
        x1, y1, x2, y2 = coords
        if kind == "rect":
            svg.append(f'<rect x="{x1}" y="{y1}" width="{x2-x1}" height="{y2-y1}" fill="{fill}"/>')
        else:
            svg.append(f'<ellipse cx="{(x1+x2)/2}" cy="{(y1+y2)/2}" rx="{(x2-x1)/2}" ry="{(y2-y1)/2}" fill="{fill}"/>')
svg.append("</svg>")
(OUT / "forge-badge.svg").write_text("\n".join(svg) + "\n", encoding="utf-8")
for size in (512, 128):
    image.resize((size, size), Image.Resampling.LANCZOS).save(OUT / f"forge-badge-{size}.png")
print(f"Original badge SVG and PNG previews saved to {OUT}")
