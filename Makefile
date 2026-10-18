.PHONY: build app run preview clean icon

# Compile the Swift package (debug).
build:
	swift build

# Assemble dist/OpenCodeBar.app (release).
app:
	Scripts/build-app.sh

# Build and launch the menu bar app.
run: app
	open dist/OpenCodeBar.app

# Render the panel in a normal window (for design work / screenshots).
preview:
	swift build
	Scripts/build-app.sh
	open dist/OpenCodeBar.app --args --preview

# Regenerate the app icon.
icon:
	rm -f Assets/AppIcon.icns
	swift Scripts/make-icon.swift Assets/AppIcon.iconset
	iconutil -c icns Assets/AppIcon.iconset -o Assets/AppIcon.icns
	rm -rf Assets/AppIcon.iconset

clean:
	swift package clean
	rm -rf dist
