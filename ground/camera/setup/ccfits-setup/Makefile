CXX := g++
CXXFLAGS := -I/home/declan/RPI/zwo/dependencies/CCfits-2.6/include \
            -Wall -Wextra -std=c++11
LDFLAGS := -L/home/declan/RPI/zwo/dependencies/CCfits-2.6/lib \
           -lCCfits -lcfitsio

TARGET := ccfits-setup
SRCS := ccfits-setup.cpp
OBJS := $(SRCS:.cpp=.o)

.PHONY: all clean

all: clean $(TARGET)

$(TARGET): $(OBJS)
	$(CXX) $(OBJS) -o $@ $(LDFLAGS)

%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGET) *.fit

clean-fits:
	rm -f *.fit