#!/usr/bin/env python3
import json, os, time, signal
from datetime import datetime, timezone
from yostlabs.tss3.api import ThreespaceSensor

RUN = True
def _stop(*_):
    global RUN
    RUN = False
signal.signal(signal.SIGINT, _stop)
signal.signal(signal.SIGTERM, _stop)

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LOG_DIR = os.path.join(BASE_DIR, "data", "imu")
os.makedirs(LOG_DIR, exist_ok=True)

timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
log_path = os.path.join(LOG_DIR, f"imu_{timestamp}.jsonl")

def main():
    sensor = ThreespaceSensor()  
    try:
        sensor.tareWithCurrentOrientation()
    except Exception:
        pass
    try:
        sensor.startStreaming()
        streaming = True
    except Exception:
        streaming = False

    with open(log_path, "w", buffering=1) as fp:
        fp.write(json.dumps({
            "type": "imu_status",
            "event": "open",
            "path": log_path,
            "ts": time.time(),
            "streaming": streaming
        }) + "\n")

        try:
            while RUN:
                try:
                    ea = sensor.getTaredOrientationAsEulerAngles()  # radians
                    r, p, y = ea[0], ea[1], ea[2]
                    print(r,p,y)
                except Exception:
                    r = p = y = None
                try:
                    quat = sensor.getTaredOrientation()  # quaternion 
                    quat = list(quat) if quat is not None else None
                except Exception:
                    quat = None
                try:
                    acc = sensor.getPrimaryCorrectedAccelVec()  # m/s^2
                    acc = list(acc) if acc is not None else None
                except Exception:
                    acc = None
                try:
                    gyro = sensor.getCorrectedGyroVec()  # rad/s
                    gyro = list(gyro) if gyro is not None else None
                except Exception:
                    gyro = None

                rec = {
                    "type": "imu",
                    "sys_time": time.time(),
                    # orientation
                    "roll_rad": r,
                    "pitch_rad": p,
                    "yaw_rad": y,
                    "quat": quat,               # [w, x, y, z] (as provided by API)
                    # vectors
                    "acc_mps2": acc,            # [ax, ay, az]
                    "gyro_rps": gyro            # [gx, gy, gz]
                }
                fp.write(json.dumps(rec) + "\n")
                time.sleep(0.01) # controls time sampling speed
        finally:
            fp.write(json.dumps({
                "type": "imu_status",
                "event": "close",
                "ts": time.time()
            }) + "\n")
    try:
        sensor.stopStreaming()
    except Exception:
        pass
    sensor.cleanup()

if __name__ == "__main__":
    main()

