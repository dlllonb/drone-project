import os
import sys
from pathlib import Path
import imageio.v2 as imageio  # avoid deprecation warning

def create_animation(exposure_dir, use_green=False):
    exposure_path = Path(exposure_dir).resolve()
    subdir = 'green' if use_green else 'color'
    image_dir = exposure_path / 'processed' / subdir

    if not image_dir.exists():
        print(f"Error: {image_dir} does not exist.")
        return

    image_files = sorted(
        [f for f in image_dir.iterdir() if f.suffix.lower() in ['.png', '.jpg', '.jpeg']],
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

    suffix = '_green_animation.gif' if use_green else '_color_animation.gif'
    output_path = exposure_path / (exposure_path.name + suffix)

    imageio.mimsave(output_path, images, duration=0.25)
    print(f"✓ Animation saved: {output_path}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 create-animation.py /path/to/exposure-directory [--green]")
        sys.exit(1)

    use_green = '--green' in sys.argv
    path_arg = next((arg for arg in sys.argv[1:] if not arg.startswith('--')), None)

    if not path_arg:
        print("Error: No exposure directory provided.")
        sys.exit(1)

    create_animation(path_arg, use_green=use_green)