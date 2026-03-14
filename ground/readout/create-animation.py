"""
create-animation.py
===================

Purpose
-------
This script creates an animated GIF from a directory of images.

It is primarily used to visualize processed exposures or debugging outputs
such as ROI tracking overlays.

The script simply loads all image files in a directory, sorts them by name,
and stitches them into an animation.

Supported image formats:
    .png
    .jpg
    .jpeg

Default Behavior
----------------
If an exposure directory is provided, the script automatically searches for:

    processed/color/
    processed/green/

inside that exposure directory.

Examples:

Create animation from processed color frames:

    python3 create-animation.py exposures-20250312-183201

Output:

    exposures-.../exposures-..._color_animation.gif


Create animation from processed green frames:

    python3 create-animation.py exposures-... --green

Output:

    exposures-.../exposures-..._green_animation.gif


Creating ROI Tracking Animations
--------------------------------
If ROI overlay frames were generated using create-plot.py:

    python3 create-plot.py --save-roi-overlays exposures-... encoder_data.pkl

the overlays will be located in:

    exposures-.../plots/roi_overlays/

You can create an animation from these frames using:

    python3 create-animation.py \
        --input-dir exposures-.../plots/roi_overlays \
        --output exposures-.../roi_tracking.gif


Options
-------
--green
    Use processed/green images instead of processed/color.

--input-dir
    Specify an arbitrary directory of images.

--output
    Output GIF path when using --input-dir.


Typical Workflow
----------------
1) Run analysis with ROI overlays

    python3 create-plot.py --save-roi-overlays exposures-... encoder_data.pkl

2) Create animation

    python3 create-animation.py \
        --input-dir exposures-.../plots/roi_overlays \
        --output exposures-.../roi_tracking.gif


Notes
-----
Image files are sorted by filename before animation is generated.
Frame duration defaults to ~0.25 seconds per frame.
"""

import os
import sys
from pathlib import Path
import imageio.v2 as imageio


def create_animation_from_dir(image_dir, output_path, duration=0.25):
    image_dir = Path(image_dir).resolve()

    if not image_dir.exists():
        print(f"Error: {image_dir} does not exist.")
        return

    image_files = sorted(
        [f for f in image_dir.iterdir() if f.suffix.lower() in [".png", ".jpg", ".jpeg"]],
        key=lambda f: f.name
    )

    if not image_files:
        print(f"No images found in {image_dir}")
        return

    images = []
    for file in image_files:
        try:
            images.append(imageio.imread(file))
        except Exception as e:
            print(f"Skipping {file.name}: {e}")

    if not images:
        print("No valid images to create animation.")
        return

    imageio.mimsave(output_path, images, duration=duration)
    print(f"✓ Animation saved: {output_path}")


def create_animation(exposure_dir, use_green=False):
    exposure_path = Path(exposure_dir).resolve()
    subdir = "green" if use_green else "color"
    image_dir = exposure_path / "processed" / subdir

    suffix = "_green_animation.gif" if use_green else "_color_animation.gif"
    output_path = exposure_path / (exposure_path.name + suffix)

    create_animation_from_dir(image_dir, output_path, duration=0.25)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python3 create-animation.py /path/to/exposure-directory [--green]")
        print("  python3 create-animation.py --input-dir /path/to/image-folder --output /path/to/out.gif")
        sys.exit(1)

    if "--input-dir" in sys.argv:
        try:
            input_dir = sys.argv[sys.argv.index("--input-dir") + 1]
            output_path = sys.argv[sys.argv.index("--output") + 1]
        except (ValueError, IndexError):
            print("Error: --input-dir and --output both require values.")
            sys.exit(1)

        create_animation_from_dir(input_dir, output_path)
        sys.exit(0)

    use_green = "--green" in sys.argv
    path_arg = next((arg for arg in sys.argv[1:] if not arg.startswith("--")), None)

    if not path_arg:
        print("Error: No exposure directory provided.")
        sys.exit(1)

    create_animation(path_arg, use_green=use_green)