.PHONY: all camera encoder clean camera-clean encoder-clean

all: camera encoder

camera:
	$(MAKE) -C camera

encoder:
	$(MAKE) -C motor/quad_enc

clean: camera-clean encoder-clean

camera-clean:
	$(MAKE) -C camera clean

encoder-clean:
	$(MAKE) -C motor/quad_enc clean