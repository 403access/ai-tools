.PHONY: build test app run restart preview shots site clean icon hub hub-dev hub-test mobile-project mobile-build mobile-run mobile-device mobile-icon

# Compile the Swift package (debug).
build:
	swift build

# Run the unit tests.
test:
	swift test

# Assemble dist/OpenCodeBar.app (release).
app:
	Scripts/build-app.sh

# Build and launch the menu bar app.
run: app
	open dist/OpenCodeBar.app

# Rebuild and restart the running app in one step.
restart:
	Scripts/restart.sh

# Render the panel in a normal window (for design work / screenshots).
preview:
	swift build
	Scripts/build-app.sh
	open dist/OpenCodeBar.app --args --preview

# Regenerate the docs/screenshots used by the website and README (2x).
shots:
	swift build
	.build/debug/OpenCodeBar --screenshot docs/screenshots/live.png --scale 2
	.build/debug/OpenCodeBar --screenshot docs/screenshots/session.png --scale 2 --detail
	.build/debug/OpenCodeBar --screenshot docs/screenshots/prompts.png --scale 2 --detail --detail-mode prompts
	.build/debug/OpenCodeBar --screenshot docs/screenshots/projects.png --scale 2 --tab projects
	.build/debug/OpenCodeBar --screenshot docs/screenshots/project-detail.png --scale 2 --tab projects --project-detail
	.build/debug/OpenCodeBar --screenshot docs/screenshots/usage.png --scale 2 --tab usage

# Open the static website locally.
site:
	open docs/index.html

# Regenerate the app icon.
icon:
	rm -f Assets/AppIcon.icns
	swift Scripts/make-icon.swift Assets/AppIcon.iconset
	iconutil -c icns Assets/AppIcon.iconset -o Assets/AppIcon.icns
	rm -rf Assets/AppIcon.iconset

# Run the SQLite sync hub that both apps talk to (foreground).
hub:
	cd server && bun install && bun run start

# Hub with auto-reload while developing.
hub-dev:
	cd server && bun run dev

# Hub unit tests (Bun).
hub-test:
	cd server && bun install && bun test

# Generate the iOS Xcode project from project.yml.
mobile-project:
	xcodegen generate

# Regenerate the iOS app icon from the same glyph as the Mac app.
mobile-icon:
	rm -rf .build/ios-icon.iconset
	swift Scripts/make-icon.swift .build/ios-icon.iconset
	mkdir -p Mobile/Assets.xcassets/AppIcon.appiconset
	cp .build/ios-icon.iconset/icon_512x512@2x.png Mobile/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
	rm -rf .build/ios-icon.iconset

# Build the iOS app for the simulator.
mobile-build: mobile-project
	xcodebuild -project OpenCodeBarMobile.xcodeproj -scheme OpenCodeBarMobile \
		-sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
		-configuration Debug CODE_SIGNING_ALLOWED=NO build

# Build, install, and launch the iOS app in a booted simulator. Pairs with the
# running hub automatically when ~/.config/opencode/opencodebar-hub.json exists.
mobile-run: mobile-build
	Scripts/run-mobile.sh

# Build, sign, install, and launch the iOS app on a connected iPhone or iPad.
# Pairs over the Mac's LAN address when ~/.config/opencode/opencodebar-hub.json
# exists. Use DEVICE=… to pick among several devices; DEVELOPMENT_TEAM=… when
# the signing team cannot be auto-detected.
mobile-device: mobile-project
	DEVICE="$(DEVICE)" DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" Scripts/run-mobile-device.sh

clean:
	swift package clean
	rm -rf dist server/node_modules
	rm -rf OpenCodeBarMobile.xcodeproj
