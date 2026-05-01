import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOAD_CONFIG = ROOT / "load-config.py"
CONFIG = ROOT / "config.yml"


def test_load_config_reads_config():
    result = subprocess.run(
        ["python3", str(LOAD_CONFIG), "--config", str(CONFIG)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )

    output = result.stdout

    assert "EXPOSURE_TIME=" in output
    assert "GAIN=" in output
    assert "INTERVAL=" in output