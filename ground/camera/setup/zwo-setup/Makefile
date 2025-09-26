CC=g++ -O2 -Wall
CFLAGS=-I ../zwo-asi-sdk/1.36/linux_sdk/include/
LD=../zwo-asi-sdk/1.36/linux_sdk/lib/armv8/
LDIR=-L $(LD)
LIBS=-l ASICamera2

binaries=zwo-setup.out

all: clean $(binaries)

zwo-setup.out: zwo-setup.cpp
	$(CC) $< -o $@ $(CFLAGS) $(LIBS) $(LDIR)

run:
	./zwo-setup.out

.PHONY: clean
clean:
	rm -f $(binaries) *.o *.out
