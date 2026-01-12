TARGET = odin_gl
ifeq ($(OS),Windows_NT)
	SHELL := cmd.exe
	RM = del
else
	RM = rm
endif

.PHONY: build build_sdl clean

build:
	odin build . -debug -collection:odinlib=../odinlib

build_sdl:
	odin build . -debug -collection:odinlib=../odinlib -define:BACKEND=sdl

clean:
	$(RM) $(TARGET)*
