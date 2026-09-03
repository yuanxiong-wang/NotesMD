APP_NAME = NotesMD
BUNDLE_ID = app.notesmd.companion
DIST = dist
APP = $(DIST)/$(APP_NAME).app
CONTENTS = $(APP)/Contents
MACOS = $(CONTENTS)/MacOS
RESOURCES = $(CONTENTS)/Resources
BIN = $(shell swift build -c release --show-bin-path)/$(APP_NAME)

.PHONY: all build test app run clean icon

all: app

build:
	swift build -c release --product $(APP_NAME)

test:
	swift run --configuration debug notesmd-check

app: build
	mkdir -p $(MACOS) $(RESOURCES)
	cp "$(BIN)" $(MACOS)/$(APP_NAME)
	cp Info.plist $(CONTENTS)/Info.plist
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(RESOURCES)/AppIcon.icns; fi
	@if [ -f Resources/AppIcon.png ]; then cp Resources/AppIcon.png $(RESOURCES)/AppIcon.png; fi
	@if [ -f Resources/notesmd-watch.sh ]; then cp Resources/notesmd-watch.sh $(RESOURCES)/notesmd-watch.sh; chmod +x $(RESOURCES)/notesmd-watch.sh; fi
	codesign --force --deep --sign - $(APP)
	@echo "Built $(APP)"

icon:
	@test -f Resources/AppIcon.png
	rm -rf Resources/AppIcon.iconset
	mkdir -p Resources/AppIcon.iconset
	sips -z 16 16 Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_16x16.png >/dev/null
	sips -z 32 32 Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_16x16@2x.png >/dev/null
	sips -z 32 32 Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_32x32.png >/dev/null
	sips -z 64 64 Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_32x32@2x.png >/dev/null
	sips -z 128 128 Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_128x128.png >/dev/null
	sips -z 256 256 Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_128x128@2x.png >/dev/null
	sips -z 256 256 Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_256x256.png >/dev/null
	sips -z 512 512 Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_256x256@2x.png >/dev/null
	sips -z 512 512 Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_512x512.png >/dev/null
	sips -z 1024 1024 Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_512x512@2x.png >/dev/null
	iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns

run: app
	open $(APP)

clean:
	rm -rf .build dist
