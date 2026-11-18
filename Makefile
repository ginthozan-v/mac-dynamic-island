APP := build/DynamicIsland.app
BIN := .build/release/DynamicIsland

.PHONY: build run install test clean

build:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/DynamicIsland
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --sign - $(APP)

run: build
	-pkill -x DynamicIsland
	open $(APP)

install: build
	-pkill -x DynamicIsland
	mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/DynamicIsland.app
	cp -R $(APP) $(HOME)/Applications/
	open $(HOME)/Applications/DynamicIsland.app

test:
	swift test

clean:
	rm -rf .build build
