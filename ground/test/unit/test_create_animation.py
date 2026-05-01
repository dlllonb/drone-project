import subprocess
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ANIMATION_SCRIPT = ROOT / "readout" / "create-animation.py"


def test_create_animation_outputs_gif(tmp_path):
    frames_dir = tmp_path / "frames"
    frames_dir.mkdir()

    for i in range(5):
        img = Image.new("RGB", (64, 64), color=(i * 30, i * 30, i * 30))
        img.save(frames_dir / f"frame_{i:03d}.png")

    output_gif = tmp_path / "animation.gif"

    subprocess.run(
        [
            "python3",
            str(ANIMATION_SCRIPT),
            "--input-dir",
            str(frames_dir),
            "--output",
            str(output_gif),
        ],
        cwd=ROOT,
        check=True,
    )

    assert output_gif.exists()
    assert output_gif.stat().st_size > 0