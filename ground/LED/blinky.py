import time
import lgpio

LED = 23

# open the gpio chip and set the LED pin as output
h = lgpio.gpiochip_open(0)
lgpio.gpio_claim_output(h, LED)

try:
	while True:
		#turn on
		lgpio.gpio_write(h, LED, 1)
		#print("on")
		time.sleep(0.3)

		#turn off
		lgpio.gpio_write(h, LED, 0)
		#print("off")
		time.sleep(0.3)
except KeyboardInterrupt:
	lgpio.gpio_write(h, LED, 0)
	lgpio.gpiochip_close(h)
