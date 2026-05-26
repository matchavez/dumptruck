# Dumptruck — Makefile
#
# Wraps the xcodebuild commands so day-to-day work is one short command.
# Requires Xcode installed (xcodebuild on the PATH). Use from the project root.
#
#   make build       Debug build of Dumptruck.app
#   make release     Release build of Dumptruck.app
#   make test        Run all unit tests with ⌘U-equivalent CLI
#   make clean       Wipe build artifacts
#   make run         Build + open the resulting .app (note: it's menubar-only,
#                    so the icon appears in the menubar — no Dock entry)
#   make install     Copy the Release build to /Applications/
#   make archive     Make an .xcarchive (useful for future signed distribution)
#   make dmg         Build a release DMG for distribution (outputs SHA256)
#   make resolve     Force-resolve SwiftPM packages (KeyboardShortcuts)

PROJECT       := Dumptruck.xcodeproj
SCHEME        := Dumptruck
TEST_SCHEME   := Dumptruck
CONFIGURATION := Debug
DERIVED_DATA  := ./build
APP_NAME      := Dumptruck.app
VERSION       := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Dumptruck/Info.plist)
DMG_NAME      := Dumptruck-$(VERSION).dmg
DMG_STAGING   := /tmp/Dumptruck-dmg-staging

XCB := xcodebuild \
	-project $(PROJECT) \
	-scheme $(SCHEME) \
	-derivedDataPath $(DERIVED_DATA) \
	-destination 'platform=macOS'

.PHONY: build release test clean run install archive dmg resolve help

help:
	@echo "Dumptruck — make targets:"
	@grep -E '^# {2}make ' Makefile | sed 's/^# */  /'

build:
	$(XCB) -configuration Debug build

release:
	$(XCB) -configuration Release build

test:
	$(XCB) -scheme $(TEST_SCHEME) -configuration Debug test

clean:
	$(XCB) clean
	rm -rf $(DERIVED_DATA)

run: build
	open $(DERIVED_DATA)/Build/Products/Debug/$(APP_NAME)

install: release
	@APP="$(DERIVED_DATA)/Build/Products/Release/$(APP_NAME)"; \
	if [ ! -d "$$APP" ]; then echo "Build artifact missing: $$APP"; exit 1; fi; \
	echo "Copying $$APP to /Applications/"; \
	cp -R "$$APP" /Applications/

archive:
	$(XCB) -configuration Release archive \
		-archivePath $(DERIVED_DATA)/Dumptruck.xcarchive

dmg: release
	@echo "Building DMG for Dumptruck $(VERSION)..."
	@rm -rf "$(DMG_STAGING)"
	@mkdir -p "$(DMG_STAGING)"
	@cp -R "$(DERIVED_DATA)/Build/Products/Release/$(APP_NAME)" "$(DMG_STAGING)/"
	@ln -sf /Applications "$(DMG_STAGING)/Applications"
	@hdiutil create \
		-volname "Dumptruck $(VERSION)" \
		-srcfolder "$(DMG_STAGING)" \
		-ov \
		-format UDZO \
		"$(DERIVED_DATA)/$(DMG_NAME)"
	@rm -rf "$(DMG_STAGING)"
	@echo ""
	@echo "Created: $(DERIVED_DATA)/$(DMG_NAME)"
	@echo ""
	@echo "SHA256 (paste into Homebrew cask):"
	@shasum -a 256 "$(DERIVED_DATA)/$(DMG_NAME)" | awk '{print $$1}'

resolve:
	xcodebuild -project $(PROJECT) -resolvePackageDependencies
