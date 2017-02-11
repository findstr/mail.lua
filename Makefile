.PHONY: all linux macosx

PLAT:=linux
linux: PLAT:=linux
macosx: PLAT=macosx

linux macosx: all

all:
	git submodule update --init
	make -C silly TARGET=../smtp $(PLAT)

