.PHONY: all build debug run test clean icon

all: build

build:
	./build.sh

debug:
	CONFIG=debug ./build.sh

run:
	./build.sh --run

test:
	swift test

clean:
	rm -rf .build Slate.app

icon:
	rm -f Resources/AppIcon.icns
	./build.sh
