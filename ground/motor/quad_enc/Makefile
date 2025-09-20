CC = gcc
CFLAGS = -I/usr/include/python3.10
LIBS = -lpython3.10
SRC = record-encoder-data.c
OUT = record-encoder-data.out

all: $(OUT)

$(OUT): $(SRC)
	$(CC) -o $(OUT) $(SRC) $(CFLAGS) $(LIBS)

clean:
	rm -f $(OUT)