import zwoasi
zwoasi.init()

cameras = zwoasi.list_cameras()
if not cameras:
    raise RuntimeError("No ASI cameras detected")
print("Detected cameras:", cameras)

cam = zwoasi.Camera(0)
print("Camera name:", cam.get_camera_property()['Name'])
cam.close()
