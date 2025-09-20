# How to use the polarimeter RPI
work in progress...

## Connecting to the Raspberry Pi
1. Either use on-grounds wifi, or VPN into the UVA network
2. Connect via terminal using command $ ssh declan@172.27.183.186, enter password

## Motor instructions
Motor files are found in 'RPI/motor/scripts'

1. Identify the encoder hat (should be the top of the stack with colored wires coming out of the green pin housing)
2. Flip the hat switch to ON 
3. Make sure the encoder (big black USB stick with colored wires)  is plugged into the blue USB 3.0 port of the RPI
4. From home directory, run $ cd RPI/motor/scripts
5. Enable motor: $ python3 motor_control.py enable
6. Spin motor: $ python3 motor_control.py [forward/backward] [speed]

Troubleshooting steps for stepper motor:
1. Run test script ($ python3 motor_test.py)
2. Check if pigpiod is enabled (should automatically be enabled by motor_control.py)

## Camera instructions

1. Connect camera
	1. Open KStars from applications list
	2. Ctrl + K in Kstars to open Ekos
	3. Select profile associated with camera (named ZWO...)
	4. Press play button to start Ekos to show camera controls
2. Click on camera icon in Ekos top bar to navigate to capture settings
3. Click play button on right side to start capture
