APP      := Ledge
BUNDLE   := com.dedemahendra.ledge
IDENTITY := Ledge Dev
CONF     ?= debug
BUILDDIR := .build/$(CONF)
DIST     := dist
APPDIR   := $(DIST)/$(APP).app

# swift-testing's macro plugin ships in a `plugins/testing/` SUBdirectory that is
# not on the compiler's default plugin search path, so `swift test` fails
# intermittently with "external macro implementation type
# 'TestingMacros.TestDeclarationMacro' could not be found". Measured on this
# machine: 5/12 runs passed without this flag, 12/12 with it. Computed from the
# active toolchain rather than hardcoded, and omitted if the directory is absent.
TESTING_PLUGIN := $(shell d="$$(dirname "$$(dirname "$$(xcrun -f swift)")")/lib/swift/host/plugins/testing"; [ -d "$$d" ] && echo "$$d")
TESTFLAGS := $(if $(TESTING_PLUGIN),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGIN),)

.PHONY: all dev release test build bundle sign install run stop cert clean

all: release

cert:
	@bash scripts/make-cert.sh "$(IDENTITY)"

# `make test` runs everything; `make test FILTER=SomeTests` narrows it.
test:
	swift test $(TESTFLAGS) $(if $(FILTER),--filter $(FILTER),)

build:
	swift build -c $(CONF)

bundle: build
	rm -rf "$(APPDIR)"
	mkdir -p "$(APPDIR)/Contents/MacOS" "$(APPDIR)/Contents/Resources"
	cp "$(BUILDDIR)/$(APP)" "$(APPDIR)/Contents/MacOS/$(APP)"
	sed -e 's/@APP_NAME@/$(APP)/g' -e 's/@BUNDLE_ID@/$(BUNDLE)/g' \
	    Info.plist.in > "$(APPDIR)/Contents/Info.plist"
	printf 'APPL????' > "$(APPDIR)/Contents/PkgInfo"

sign: bundle
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

clean:
	rm -rf .build "$(DIST)"
