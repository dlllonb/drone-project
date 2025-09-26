CXX := g++
CXXFLAGS := -I/home/declan/RPI/zwo/dependencies/zwo-asi-sdk/1.36/linux_sdk/include \
            -I/usr/include/opencv4 \
            -Wall -Wextra -std=c++14
LDFLAGS := -L/home/declan/RPI/zwo/dependencies/zwo-asi-sdk/1.36/linux_sdk/lib \
           -lASICamera2 `pkg-config --libs opencv4`

TARGET := capture-exposure.out
SRCS := capture-exposure.cpp
OBJS := $(SRCS:.cpp=.o)

.PHONY: all clean clean-img

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CXX) $(OBJS) -o $@ $(LDFLAGS)

%.o: %.cpp
	$(CXX) $(CXXFLAGS) `pkg-config --cflags opencv4` -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGET)

clean-img:
	rm -f *.bin *.fits *.png