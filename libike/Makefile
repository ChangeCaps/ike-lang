SOURCES = $(wildcard src/*.c)
OBJECTS = $(SOURCES:src/%.c=out/%.o)
DEPENDS = $(OBJECTS:.o=.d)

CFLAGS = -std=c99 -Wall -Iinclude -O3

.PHONY: all

all: out/libike.o

clean:
	rm -rf out

out:
	mkdir -p out

out/libike.o: $(OBJECTS)
	$(LD) -r $(OBJECTS) -o $@

out/%.o: src/%.c | out
	$(CC) $(CFLAGS) -MMD -MP -c $< -o $@

-include $(DEPENDS)
