.PHONY: build test app install uninstall run desktop restart watch preview shots site docs docs-build docs-serve openapi clean icon icon-classic web-icons hub hub-dev hub-test hub-tunnel remote-host vz-helper mobile-project mobile-build mobile-run mobile-device mobile-variants mobile-icon bench

# Compile the Swift package (debug).
build:
	swift build

# Run the unit tests.
test:
	swift test

# Run the shared-code performance microbenchmarks.
bench:
	Scripts/perf-benchmark.sh

# Assemble dist/OpenCodeBar.app (release).
app:
	Scripts/build-app.sh

# Build and launch the menu bar app.
run: app
	open dist/OpenCodeBar.app

# Build and install into ~/Applications so Spotlight and Raycast can find it.
# Re-run after source changes to refresh the installed copy.
install:
	Scripts/install.sh

# Remove the installed copy and its Launch Services registration.
uninstall:
	Scripts/install.sh --uninstall

# Build and launch with the desktop window open.
desktop: app
	open dist/OpenCodeBar.app --args --desktop

# Rebuild and restart the running app in one step.
restart:
	Scripts/restart.sh

# Rebuild and restart the app whenever Sources/ or Package.swift change.
# Live reload, not state-preserving: the app restarts on every change.
watch:
	Scripts/watch.sh

# Render the panel in a normal window (for design work / screenshots).
preview:
	swift build
	Scripts/build-app.sh
	open dist/OpenCodeBar.app --args --preview

# Regenerate the docs/screenshots used by the website and README (2x).
# Stats and Changes hydrate history on their first request, so open those tabs
# once (or keep the hub cache warm) if either shot captures the loading state.
shots:
	swift build
	.build/debug/OpenCodeBar --screenshot docs/screenshots/live.png --scale 2
	.build/debug/OpenCodeBar --screenshot docs/screenshots/session.png --scale 2 --detail
	.build/debug/OpenCodeBar --screenshot docs/screenshots/stats.png --scale 2 --detail --detail-mode stats
	.build/debug/OpenCodeBar --screenshot docs/screenshots/changes.png --scale 2 --detail --detail-mode changes
	.build/debug/OpenCodeBar --screenshot docs/screenshots/prompts.png --scale 2 --detail --detail-mode prompts
	.build/debug/OpenCodeBar --screenshot docs/screenshots/projects.png --scale 2 --tab projects
	.build/debug/OpenCodeBar --screenshot docs/screenshots/project-detail.png --scale 2 --tab projects --project-detail
	.build/debug/OpenCodeBar --screenshot docs/screenshots/usage.png --scale 2 --tab usage
	cp docs/screenshots/*.png website/static/img/screenshots/

# Open the static website locally.
site:
	open docs/index.html

# Run the Docusaurus documentation site (hot reload).
docs:
	cd website && npm install && npm run start

# Build the documentation site for production. `prebuild` regenerates the
# Swagger explorer from server/src/openapi/ (requires Bun).
docs-build:
	cd website && npm ci && npm run build

# Regenerate the static API explorer used by the docs site and the live hub.
openapi:
	cd server && bun run scripts/export-openapi.ts ../website/static/api

# Build and serve the production documentation locally.
docs-serve: docs-build
	cd website && npm run serve

# Regenerate the app icon (the terminal fills the canvas).
icon:
	rm -f Assets/AppIcon.icns
	swift Scripts/make-icon.swift Assets/AppIcon.iconset
	iconutil -c icns Assets/AppIcon.iconset -o Assets/AppIcon.icns
	rm -rf Assets/AppIcon.iconset

# Regenerate the previous floating-terminal icon for comparison.
icon-classic:
	rm -rf Assets/AppIconClassic.iconset
	swift Scripts/make-icon.swift --floating Assets/AppIconClassic.iconset
	iconutil -c icns Assets/AppIconClassic.iconset -o Assets/AppIconClassic.icns
	rm -rf Assets/AppIconClassic.iconset

# Regenerate the website logo, favicon and touch icons from the app icon.
web-icons:
	rm -rf .build/web-icon.iconset
	swift Scripts/make-icon.swift .build/web-icon.iconset
	cp .build/web-icon.iconset/icon_128x128@2x.png docs/assets/logo.png
	cp .build/web-icon.iconset/icon_128x128@2x.png website/static/img/logo.png
	cp .build/web-icon.iconset/icon_32x32@2x.png website/static/img/favicon.png
	sips -z 192 192 .build/web-icon.iconset/icon_512x512@2x.png --out docs/assets/icon-192.png >/dev/null
	cp .build/web-icon.iconset/icon_512x512.png docs/assets/icon-512.png
	cp .build/web-icon.iconset/icon_512x512.png website/static/img/icon-history/website-icon-v3.png
	rm -rf .build/web-icon.iconset

# Build the ScreenCaptureKit helper used by the Remote tab. `make hub` builds
# it too; the hub spawns it on demand and speaks a framed protocol over stdio.
remote-host:
	swift build --product OpenCodeBarRemoteHost

# Build the Virtualization.framework helper used by the VMs tab. The hub finds
# it under .build/{debug,release} or dist/, or via OPENCODEBAR_VZ_HELPER.
# Ad-hoc signing with com.apple.security.virtualization is required even though
# the helper is a plain CLI: VZ refuses to configure a machine without it.
vz-helper:
	swift build --product OpenCodeBarVZ
	codesign --force --sign - \
		--entitlements Sources/OpenCodeBarVZ/OpenCodeBarVZ.entitlements \
		"$$(swift build --show-bin-path)/OpenCodeBarVZ"

# Run the SQLite sync hub that both apps talk to (foreground).
hub: remote-host vz-helper
	cd server && bun install && bun run start

# Hub with auto-reload while developing.
hub-dev: remote-host vz-helper
	cd server && bun run dev

# Hub unit tests (Bun).
hub-test:
	cd server && bun install && bun test

# Expose the running hub through a Cloudflare quick tunnel. Needed when the
# phone is on cellular, or when USB tethering does not route back to the Mac.
# Keep it running alongside `make hub`; `make mobile-device` reuses the URL.
hub-tunnel:
	Scripts/hub-tunnel.sh

# Generate the iOS Xcode project from project.yml.
mobile-project:
	xcodegen generate

# Regenerate the iOS app icon from the same glyph as the Mac app.
mobile-icon:
	rm -rf .build/ios-icon.iconset
	swift Scripts/make-icon.swift --full-bleed .build/ios-icon.iconset
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

# Build, sign, install, and launch one app variant per git worktree so several
# versions can be reviewed side by side on one phone. Every variant gets its own
# bundle id and home-screen name. Pass worktree paths or branch names in ARGS to
# build only some of them, or DEVICE=… to pick among several devices.
mobile-variants:
	DEVICE="$(DEVICE)" Scripts/run-mobile-variants.sh $(ARGS)

clean:
	swift package clean
	rm -rf dist server/node_modules
	rm -rf website/node_modules website/build website/.docusaurus website/static/api
	rm -rf OpenCodeBarMobile.xcodeproj
