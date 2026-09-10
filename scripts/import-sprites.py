#!/usr/bin/env python3
"""Turn a downloaded sprite sheet into a species pets.nvim can draw.

The plugin expects one PNG per frame, numbered, in
`<root>/<species>/<style>/<action>/<n>.png`, on the same 128x88 canvas the
downloaded pack uses, with the sprite sitting on the bottom edge. Art from
itch.io arrives as a packed sheet instead, so this slices it up.

Provenance is not optional: --author, --license and --source are required and
are written to `<species>/CREDITS.txt`. Art keeps the licence it came with, and
the licence is no use to anyone if nobody recorded it.

    ./scripts/import-sprites.py --sheet cat_walk.png --frame-size 32x32 \
        --species cat --style tabby --action walk \
        --author 'Zeenaz' --license 'CC0 1.0' \
        --source 'https://zeenaz.itch.io/free-pixel-animation-cat-6-loops'

Requires Pillow (`pip install pillow`).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("this needs Pillow: pip install pillow")

# The canvas every frame in the downloaded pack uses. Matching it means the
# terminal scales our art and the pack's art by exactly the same factor, so a
# cat and a dog end up the same size on screen.
CANVAS = (128, 88)

# Action folder names the plugin looks for. Anything else is still written, but
# no pet state will ever ask for it, so warn rather than silently do nothing.
KNOWN_ACTIONS = {
    "idle", "sit", "walk", "walk_left", "run", "run_left",
    "walk_fast", "walk_fast_left", "liedown", "swipe", "pee",
}


def parse_size(text: str) -> tuple[int, int]:
    try:
        w, h = text.lower().split("x")
        return int(w), int(h)
    except ValueError:
        raise argparse.ArgumentTypeError(f"expected WxH, got {text!r}")


def slice_sheet(sheet: Image.Image, cell: tuple[int, int]) -> list[Image.Image]:
    """Cut a sheet into cells, row-major, skipping fully transparent ones."""
    cw, ch = cell
    if sheet.width % cw or sheet.height % ch:
        print(
            f"warning: {sheet.width}x{sheet.height} sheet does not divide evenly "
            f"into {cw}x{ch} cells; trailing pixels ignored",
            file=sys.stderr,
        )
    frames = []
    for top in range(0, sheet.height - ch + 1, ch):
        for left in range(0, sheet.width - cw + 1, cw):
            cell_img = sheet.crop((left, top, left + cw, top + ch))
            if cell_img.getbbox() is not None:
                frames.append(cell_img)
    return frames


def to_canvas(frames: list[Image.Image]) -> list[Image.Image]:
    """Scale and pad frames onto the pack canvas, sprite on the bottom edge.

    The crop box is the union across every frame rather than each frame's own
    bounds, so a sprite that leans or lifts a paw keeps that motion instead of
    being re-centred into stillness.
    """
    boxes = [f.getbbox() for f in frames]
    union = (
        min(b[0] for b in boxes),
        min(b[1] for b in boxes),
        max(b[2] for b in boxes),
        max(b[3] for b in boxes),
    )
    cropped = [f.crop(union) for f in frames]
    src_w, src_h = cropped[0].size

    # Integer factor only: pixel art survives 5x nearest-neighbour and dies
    # under 5.5x, which resamples one source pixel into uneven blocks.
    factor = min(CANVAS[0] // src_w, CANVAS[1] // src_h)
    if factor < 1:
        sys.exit(
            f"a {src_w}x{src_h} frame is larger than the {CANVAS[0]}x{CANVAS[1]} "
            "canvas; downscaling pixel art is not worth doing automatically"
        )

    out = []
    for frame in cropped:
        scaled = frame.resize((src_w * factor, src_h * factor), Image.NEAREST)
        canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        canvas.paste(
            scaled,
            ((CANVAS[0] - scaled.width) // 2, CANVAS[1] - scaled.height),
            scaled,
        )
        out.append(canvas)
    return out


def write_credits(species_dir: Path, args: argparse.Namespace) -> None:
    """Record provenance next to the art, appending one line per import."""
    credits = species_dir / "CREDITS.txt"
    entry = (
        f"{args.style}/{args.action}\n"
        f"  author:  {args.author}\n"
        f"  licence: {args.license}\n"
        f"  source:  {args.source}\n"
    )
    header = (
        f"Art for the `{args.species}` species, kept under the licence it was\n"
        "published with. Not covered by the pets.nvim licence.\n\n"
    )
    existing = credits.read_text() if credits.exists() else header
    if entry in existing:
        return
    credits.write_text(existing + entry)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sheet", required=True, type=Path, help="sprite sheet PNG")
    ap.add_argument("--frame-size", required=True, type=parse_size, metavar="WxH", help="cell size in the sheet")
    ap.add_argument("--species", default="cat")
    ap.add_argument("--style", default="default", help="colour variant folder")
    ap.add_argument("--action", required=True, help=f"one of: {', '.join(sorted(KNOWN_ACTIONS))}")
    ap.add_argument("--author", required=True, help="who made the art")
    ap.add_argument("--license", required=True, help="exact licence, e.g. 'CC0 1.0'")
    ap.add_argument("--source", required=True, help="URL the art came from")
    ap.add_argument(
        "--root",
        type=Path,
        default=Path.home() / ".local/share/nvim/pets.nvim/custom",
        help="art root (default: the stdpath('data') custom root)",
    )
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if args.action not in KNOWN_ACTIONS:
        print(f"warning: {args.action!r} is not an action the plugin asks for", file=sys.stderr)

    sheet = Image.open(args.sheet).convert("RGBA")
    frames = slice_sheet(sheet, args.frame_size)
    if not frames:
        sys.exit("no non-empty frames found — is --frame-size right?")

    canvassed = to_canvas(frames)
    out_dir = args.root / args.species / args.style / args.action

    if args.dry_run:
        print(f"{len(canvassed)} frames -> {out_dir}/{{0..{len(canvassed) - 1}}}.png")
        return

    out_dir.mkdir(parents=True, exist_ok=True)
    for i, frame in enumerate(canvassed):
        frame.save(out_dir / f"{i}.png")
    write_credits(args.root / args.species, args)

    print(f"wrote {len(canvassed)} frames to {out_dir}")
    print(f"provenance recorded in {args.root / args.species / 'CREDITS.txt'}")


if __name__ == "__main__":
    main()
