import subprocess
import signal

file_path = "/home/declan/drone-project/ground/"
spin_rate = "250"

def stop():
    try:
        subprocess.run([file_path + "motor/scripts/motor_control.sh", "stop"], check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error stopping motor: {e}")

try:
    # Enable motor
    subprocess.run([file_path + "motor/scripts/motor_control.sh", "enable"], check=True)

    # Set direction to backward
    subprocess.run([file_path + "motor/scripts/motor_control.sh", "backward"], check=True)

    # Spin motor at specified rate
    subprocess.run([file_path + "motor/scripts/motor_control.sh", "spin", spin_rate], check=True)

    # Run encoder readout
    readout = subprocess.Popen([file_path + "motor/quad_enc/record-encoder-data.out"])

    # Wait for user to press Enter
    input("Motor running. Press Enter to stop...\n")

    # Send SIGINT (like pressing Ctrl+C)
    readout.send_signal(signal.SIGINT)
    readout.wait()  # Wait for graceful shutdown

    # Stop motor
    stop()

except (subprocess.CalledProcessError, KeyboardInterrupt) as e:
    print(f"Error during execution: {e}")
    try:
        readout.send_signal(signal.SIGINT)
        readout.wait()
    except Exception:
        pass
    stop()