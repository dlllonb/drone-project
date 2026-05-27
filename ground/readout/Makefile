CXX := g++
CXXFLAGS := -std=c++17 -O3 -Wall -Wextra -pthread
LDLIBS := -lcfitsio -lpng

TARGET := process-exposures-batch.out
SRC := process-exposures-batch.cpp

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(CXX) $(CXXFLAGS) $(SRC) -o $(TARGET) $(LDLIBS)

clean:
	rm -f $(TARGET)