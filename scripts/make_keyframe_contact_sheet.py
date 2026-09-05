from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: make_keyframe_contact_sheet.py <frame-dir> <output.jpg>")
    frame_dir = Path(sys.argv[1])
    output = Path(sys.argv[2])
    files = sorted(frame_dir.glob("*.jpg"))
    if not files:
        raise SystemExit("no jpg frames found")
    cols = 4
    tile_w, tile_h = 480, 270
    rows = (len(files) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tile_w, rows * tile_h), "black")
    font = ImageFont.load_default(size=24)
    for index, file in enumerate(files):
        image = Image.open(file).convert("RGB").resize((tile_w, tile_h), Image.Resampling.LANCZOS)
        x = (index % cols) * tile_w
        y = (index // cols) * tile_h
        sheet.paste(image, (x, y))
        draw = ImageDraw.Draw(sheet)
        label = file.stem.replace("_", ".")
        draw.text((x + 10, y + 8), label, font=font, fill=(255, 240, 0), stroke_width=2, stroke_fill=(0, 0, 0))
    sheet.save(output, quality=92)


if __name__ == "__main__":
    main()
