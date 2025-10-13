CXX := g++
CXXFLAGS := -I/home/declan/drone-project/ground/camera/dependencies/zwo-asi-sdk/1.36/linux_sdk/include \
            -I/usr/include/opencv4 \
            -Wall -Wextra -std=c++17
LDFLAGS := -L/home/declan/drone-project/ground/camera/dependencies/zwo-asi-sdk/1.36/linux_sdk/lib \
           -lASICamera2 `pkg-config --libs opencv4`

TARGETS := capture-exposure.out capture-continuous.out
OBJS := $(TARGETS:.out=.o)

.PHONY: all clean clean-img

all: $(TARGETS)

capture-exposure.out: capture-exposure.o
	$(CXX) $< -o $@ $(LDFLAGS)

capture-continuous.out: capture-continuous.o
	$(CXX) $< -o $@ $(LDFLAGS)

%.o: %.cpp
	$(CXX) $(CXXFLAGS) `pkg-config --cflags opencv4` -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGETS)

clean-img:
	rm -f *.bin *.fits *.png