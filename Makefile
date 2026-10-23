APP      := Ledge
BUNDLE   := com.dedemahendra.ledge
IDENTITY := Ledge Dev
CONF     ?= debug
BUILDDIR := .build/$(CONF)
DIST     := dist
APPDIR   := $(DIST)/$(APP).app
VERSION  := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist.in)
DMG      := $(DIST)/$(APP)-$(VERSION).dmg
DMGSTAGE := .build/dmg

# swift-testing's macro plugin ships in a `plugins/testing/` SUBdirectory that is
# not on the compiler's default plugin search path, so `swift test` fails
# intermittently with "external macro implementation type
# 'TestingMacros.TestDeclarationMacro' could not be found". Measured on this
# machine: 5/12 runs passed without this flag, 12/12 with it. Computed from the
# active toolchain rather than hardcoded, and omitted if the directory is absent.
TESTING_PLUGIN := $(shell d="$$(dirname "$$(dirname "$$(xcrun -f swift)")")/lib/swift/host/plugins/testing"; [ -d "$$d" ] && echo "$$d")
TESTFLAGS := $(if $(TESTING_PLUGIN),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGIN),)

.PHONY: all dev release test build bundle sign install dmg run stop cert cert-allow clean

all: release

cert:
	@bash scripts/make-cert.sh "$(IDENTITY)"

# For an identity that already exists but prompts on every build: the
# partition-list step from scripts/make-cert.sh on its own. Asks for the
# login keychain password on the terminal.
cert-allow:
	security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
	    "$$HOME/Library/Keychains/login.keychain-db"

# `make test` runs everything; `make test FILTER=SomeTests` narrows it.
test:
	swift test $(TESTFLAGS) $(if $(FILTER),--filter $(FILTER),)

build:
	swift build -c $(CONF)

bundle: build
	rm -rf "$(APPDIR)"
	mkdir -p "$(APPDIR)/Contents/MacOS" "$(APPDIR)/Contents/Resources"
	cp "$(BUILDDIR)/$(APP)" "$(APPDIR)/Contents/MacOS/$(APP)"
	cp "$(BUILDDIR)/LedgeAgentHook" "$(APPDIR)/Contents/MacOS/ledge-agent-hook"
	cp -R Resources/mediaremote-adapter "$(APPDIR)/Contents/Resources/"
	cp Resources/Ledge.icns "$(APPDIR)/Contents/Resources/Ledge.icns"
	chmod +x "$(APPDIR)/Contents/Resources/mediaremote-adapter/MediaRemoteAdapterTestClient"
	sed -e 's/@APP_NAME@/$(APP)/g' -e 's/@BUNDLE_ID@/$(BUNDLE)/g' \
	    Info.plist.in > "$(APPDIR)/Contents/Info.plist"
	printf 'APPL????' > "$(APPDIR)/Contents/PkgInfo"

# Regenerates the app icon from scripts/make-icon.swift (2026-09-30).
icon:
	mkdir -p .build/icon/Ledge.iconset
	swiftc -O -o .build/icon/make-icon scripts/make-icon.swift
	.build/icon/make-icon .build/icon/icon-1024.png
	for s in 16 32 128 256 512; do \
	  sips -z $$s $$s .build/icon/icon-1024.png --out .build/icon/Ledge.iconset/icon_$${s}x$${s}.png >/dev/null; \
	  sips -z $$((s*2)) $$((s*2)) .build/icon/icon-1024.png --out .build/icon/Ledge.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns .build/icon/Ledge.iconset -o Resources/Ledge.icns

sign: bundle
	codesign --force --sign "$(IDENTITY)" "$(APPDIR)/Contents/MacOS/ledge-agent-hook"
	codesign --force --sign "$(IDENTITY)" "$(APPDIR)"
	@codesign -dv --verbose=2 "$(APPDIR)" 2>&1 | grep -E 'Identifier|Authority' || true

stop:
	-@pkill -x $(APP) 2>/dev/null || true

run: stop
	open "$(APPDIR)"

dev:
	$(MAKE) CONF=debug sign
	$(MAKE) run

release:
	$(MAKE) CONF=release sign

install: release
	rm -rf "/Applications/$(APP).app"
	cp -R "$(APPDIR)" /Applications/

# A disk image for a GitHub release (2026-10-22): the release app, signed as
# `install` signs it, beside an Applications shortcut to drag it onto. Then
# mounted and checked, so a broken image is never uploaded.
dmg: release
	$(if $(VERSION),,$(error could not read the version from Info.plist.in))
	rm -rf "$(DMGSTAGE)" "$(DMG)"
	mkdir -p "$(DMGSTAGE)"
	ditto "$(APPDIR)" "$(DMGSTAGE)/$(APP).app"
	ln -s /Applications "$(DMGSTAGE)/Applications"
	hdiutil create -volname "$(APP)" -srcfolder "$(DMGSTAGE)" -format UDZO "$(DMG)"
	@m=$$(mktemp -d); hdiutil attach -nobrowse -readonly -mountpoint "$$m" "$(DMG)" >/dev/null && \
	  codesign --verify --strict "$$m/$(APP).app" && \
	  codesign -dvv "$$m/$(APP).app" 2>&1 | grep -q "Authority=$(IDENTITY)" && test -L "$$m/Applications"; s=$$?; \
	  hdiutil detach "$$m" >/dev/null 2>&1 || hdiutil detach -force "$$m" >/dev/null 2>&1; rmdir "$$m"; \
	  if [ $$s -ne 0 ]; then echo "the image did not check out"; exit $$s; fi
	@shasum -a 256 "$(DMG)"

clean:
	rm -rf .build "$(DIST)"
