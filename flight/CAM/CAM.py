# code file for camera captures
#!/usr/bin/env python3
import time
import signal
from pathlib import Path
from datetime import datetime, timezone
import numpy as np
from PIL import Image
import os
import zwoasi

EXPOSURE_US = 1000000 # microseconds (1000000 = 1 s)
GAIN = 100                 
IMAGE_TYPE = "RAW8" # or "RAW16"
BANDWIDTH = 40              
SLEEP_POLL = 0.01       


#zwoasi.init('/usr/local/lib/zwo/libASICamera2.so')
zwoasi.init()

RUN = True
def _stop(*_):
    global RUN
    RUN = False
signal.signal(signal.SIGINT, _stop)
signal.signal(signal.SIGTERM, _stop)

def now_str():
    return int(datetime.now(timezone.utc).timestamp())

def main():
    cams = zwoasi.list_cameras()
    if not cams:
        raise RuntimeError("No ZWO ASI cameras detected.")
    cam = zwoasi.Camera(0)  # should be ASI178MM
    info = cam.get_camera_property()
    w, h = info["MaxWidth"], info["MaxHeight"]
    print(f"Opened camera: {info['Name']} ({w}x{h})")

    # save to data/camera/cam_YYYYMMDD_HHMMSS
    repo_root = Path(__file__).resolve().parents[2]
    run_dir = repo_root / "data" / "camera" / f"cam_{now_str()}"
    run_dir.mkdir(parents=True, exist_ok=True)
    print(f"Saving images to: {run_dir}")

    # configure image type
    if IMAGE_TYPE.upper() == "RAW16":
        img_type = zwoasi.ASI_IMG_RAW16
        dtype = np.uint16
        ext = ".tiff"   
    else:
        img_type = zwoasi.ASI_IMG_RAW8
        dtype = np.uint8
        ext = ".png"    
    cam.set_image_type(img_type)
    cam.set_roi_format(w, h, 1, img_type)
    cam.set_control_value(zwoasi.ASI_EXPOSURE, int(EXPOSURE_US))
    cam.set_control_value(zwoasi.ASI_GAIN, int(GAIN))
    cam.set_control_value(zwoasi.ASI_BANDWIDTHOVERLOAD, int(BANDWIDTH))

    # start of file saving
    (run_dir / "RUN_OPEN.txt").write_text(f"started_utc={now_str()}\n", encoding="utf-8")

    frame_idx = 0
    try:
        while RUN:
            cam.start_exposure()
            while True:
                st = cam.get_exposure_status()
                if st == zwoasi.ASI_EXP_SUCCESS:
                    break
                elif st == zwoasi.ASI_EXP_FAILED:
                    raise RuntimeError("Exposure failed")
                time.sleep(SLEEP_POLL)

            buf = cam.get_data_after_exposure()
            frame = np.frombuffer(buf, dtype=dtype).reshape(h, w)
            ts = now_str()
            fname = f"asi178_{ts}_f{frame_idx:06d}{ext}"
            fpath = run_dir / fname

            if dtype == np.uint8:
                Image.fromarray(frame).save(fpath)
            else:
                Image.fromarray(frame).save(fpath, format="TIFF")

            print(f"[{ts}] saved {fname}")
            frame_idx += 1
    finally:
        try:
            cam.stop_exposure()
        except Exception:
            pass
        cam.close()
        (run_dir / "RUN_CLOSE.txt").write_text(f"ended_utc={now_str()}\n", encoding="utf-8")
        print("Camera closed.")

if __name__ == "__main__":
    main()
