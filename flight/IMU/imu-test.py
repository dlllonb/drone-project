from yostlabs.tss3.api import ThreespaceSensor
s = ThreespaceSensor()
try:
    s.tareWithCurrentOrientation()  # ok if this fails; leave it in
    # comment out streaming while testing
    # s.startStreaming()
    res = s.getTaredOrientationAsEulerAngles()
    print("Euler (tared):", res)
    print(res.data)
    print(res.data[1])
finally:
    s.cleanup()