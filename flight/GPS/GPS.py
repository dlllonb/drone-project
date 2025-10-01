#!/usr/bin/env python3
import json, os, time, signal
from datetime import datetime, timezone
from gps import gps, WATCH_ENABLE, WATCH_JSON

RUN = True
def _stop(*_):
    global RUN
    RUN = False
signal.signal(signal.SIGINT, _stop)
signal.signal(signal.SIGTERM, _stop)

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LOG_DIR = os.path.join(BASE_DIR, "data", "gps")

timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
log_path = os.path.join(LOG_DIR, f"gps_{timestamp}.jsonl")

def main():
    session = gps(mode=WATCH_ENABLE | WATCH_JSON)  
    print("Initialized GPS sensor")
    with open(log_path, "w", buffering=1) as fp:   
        fp.write(json.dumps({
            "type":"gps_status",
            "event":"open",
            "path":log_path,
            "ts":time.time()
        }) + "\n")
        try:
            print("Starting GPS data logging")
            while RUN:
                rep = session.next()
                if rep.get("class") != "TPV":
                    continue
                rec = {
                    "type": "gps",
                    "sys_time": time.time(),
                    "gps_time": rep.get("time"),
                    "mode": rep.get("mode"),
                    "lat": rep.get("lat"),
                    "lon": rep.get("lon"),
                    "alt_m": rep.get("alt"),
                    "speed_mps": rep.get("speed"),
                }
                fp.write(json.dumps(rec) + "\n")
        finally:
            fp.write(json.dumps({"type":"gps_status","event":"close","ts":time.time()}) + "\n")
            print("Wrote end of GPS log file")
            fp.flush(); os.fsync(fp.fileno())

if __name__ == "__main__":
    main()
