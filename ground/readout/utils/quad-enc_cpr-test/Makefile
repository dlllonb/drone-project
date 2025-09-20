CC = gcc
CFLAGS = -Wall -Wextra -O2
TARGET = cpr-test.out
SRC = cpr-test.c

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC)

clean:
	rm -f $(TARGET)
