# Developer entry points. Run `make help` for the list.

PROJECT  := Boaz.xcodeproj
ARCHIVES := build/archives
DERIVED  := build/DerivedData
RESULTS  := build/UITestResults.xcresult
# CI and local builds skip signing; archives are signed with the team in project.yml.
UNSIGNED := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
# BoazUITests runs the app it builds (or BOAZ_UITEST_APP's), so both it and the Boaz-macOS host need a real
# signature to launch; ad hoc here only, project.yml's Automatic/team release signing is untouched. The CloudKit/
# aps-environment entitlements need a real provisioning profile, which a CI runner doesn't have and the app never
# uses in `-BoazUITest` mode anyway, so test runs sign against a trimmed, sandbox-only entitlements file instead.
# A distinct bundle id is essential, not cosmetic: a sandboxed app's container (Application Support, defaults,
# Keychain) is keyed by bundle identifier, so a test build sharing com.chenkahana.boaz would share the real,
# already-installed Boaz's container and preferences domain instead of getting its own.
ADHOC    := CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES \
            DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= CODE_SIGN_ENTITLEMENTS=$(CURDIR)/Apps/macOS/BoazUITest.entitlements \
            BOAZ_BUNDLE_ID=com.chenkahana.boaz.uitest
XCB      := xcodebuild -project $(PROJECT) -derivedDataPath $(DERIVED) -quiet

.DEFAULT_GOAL := help
.PHONY: help bootstrap project kit kit-test ios mac mac-dmg mac-webkit-dmg build device archive dmg uitest acceptance-uitest clean

help: ## List the available targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

bootstrap: ## Check the toolchain, install XcodeGen if missing, generate the project
	@xcodebuild -version | head -1
	@command -v xcodegen >/dev/null || brew install xcodegen
	@$(MAKE) --no-print-directory project

project: ## Generate Boaz.xcodeproj from project.yml
	xcodegen generate --quiet

kit: ## Build the BoazKit package
	swift build --package-path Packages/BoazKit

kit-test: ## Run the BoazKit unit tests
	swift test --package-path Packages/BoazKit

# Unsigned, so it builds the AutoFill extension too, whose App ID doesn't exist yet (autofill.yml).
ios: export BOAZ_AUTOFILL := YES
ios: project ## Build the iPhone app and extensions (unsigned)
	$(XCB) -scheme Boaz-iOS -configuration Debug -destination 'generic/platform=iOS' $(UNSIGNED) build

mac: project ## Build the Mac app (unsigned)
	$(XCB) -scheme Boaz-macOS -configuration Debug -destination 'generic/platform=macOS' $(UNSIGNED) build

mac-dmg: ## Build Chromium host and matching Release Boaz UI for DMG assembly
	/opt/homebrew/bin/python3.12 Tools/chromium/build.py --build
	/opt/homebrew/bin/python3.12 Tools/chromium/build-application.py --build

mac-webkit-dmg: ## Build the preserved WebKit DMG configuration (unsigned)
	Tools/generate-webkit-project.sh dmg
	xcodebuild -project build/webkit-dmg/Boaz.xcodeproj -scheme Boaz-macOS -configuration Release \
		-destination 'generic/platform=macOS' -derivedDataPath build/webkit-dmg/DerivedData $(UNSIGNED) build

build: kit ios mac ## Build BoazKit and both apps (what CI runs)

device: project ## Install a signed Release build on a connected iPhone, syncing with the Mac DMG: make device DEVICE=<udid>
	@test -n "$(DEVICE)" || { echo "Usage: make device DEVICE=<udid> (xcrun devicectl list devices)"; exit 1; }
	$(XCB) -scheme Boaz-iOS -configuration Release -destination 'generic/platform=iOS' -allowProvisioningUpdates build
	xcrun devicectl device install app --device $(DEVICE) $(DERIVED)/Build/Products/Release-iphoneos/Boaz.app

archive: project ## Signed Release archives for App Store Connect, in build/archives
	xcodebuild archive -project $(PROJECT) -scheme Boaz-iOS -configuration Release \
		-destination 'generic/platform=iOS' -archivePath $(ARCHIVES)/Boaz-iOS.xcarchive -allowProvisioningUpdates
	xcodebuild archive -project $(PROJECT) -scheme Boaz-macOS -configuration Release \
		-destination 'generic/platform=macOS' -archivePath $(ARCHIVES)/Boaz-macOS.xcarchive -allowProvisioningUpdates

dmg: ## Prepare an unpublished Chromium DMG: VERSION and RELEASE_ARGS required (docs/release.md)
	Tools/release-mac.sh $(VERSION) $(RELEASE_ARGS)

uitest: project ## Run the BoazUITests suite (set BOAZ_UITEST_APP=<path to .app> to target another build)
	rm -rf $(RESULTS)
	$(XCB) -scheme Boaz-macOS -destination 'platform=macOS' -resultBundlePath $(RESULTS) $(ADHOC) \
		-test-timeouts-enabled YES -default-test-execution-time-allowance 300 test

acceptance-uitest: project ## One BoazAcceptanceUITests step (TEST=name) against BOAZ_ACCEPTANCE_APP (required; BUILD_ONLY=1 only builds)
	@[ -n "$(TEST)" ] || { echo "TEST is required" >&2; exit 2; }
	@[ -n "$(BUILD_ONLY)$(BOAZ_ACCEPTANCE_APP)" ] || { echo "BOAZ_ACCEPTANCE_APP is required" >&2; exit 2; }
	@[ "$(CI)" = true ] || [ -n "$(BUILD_ONLY)" ] || [ "$$(cd "$(BOAZ_ACCEPTANCE_APP)" 2>/dev/null && pwd -P)" != /Applications/Boaz.app ] || \
		{ echo "Refusing to drive /Applications/Boaz.app outside CI: it is your real Boaz." >&2; exit 2; }
	rm -rf build/Acceptance-$(TEST).xcresult
	TEST_RUNNER_CI=$(CI) TEST_RUNNER_BOAZ_ACCEPTANCE_EXTENSIONS=$(BOAZ_ACCEPTANCE_EXTENSIONS) \
		TEST_RUNNER_BOAZ_ACCEPTANCE_URLS=$(BOAZ_ACCEPTANCE_URLS) TEST_RUNNER_BOAZ_ACCEPTANCE_SPACE="$(BOAZ_ACCEPTANCE_SPACE)" \
		TEST_RUNNER_BOAZ_ACCEPTANCE_UNPACKED=$(BOAZ_ACCEPTANCE_UNPACKED) TEST_RUNNER_BOAZ_ACCEPTANCE_FIXTURE=$(BOAZ_ACCEPTANCE_FIXTURE) \
		TEST_RUNNER_BOAZ_ACCEPTANCE_LOGIN=$(BOAZ_ACCEPTANCE_LOGIN) TEST_RUNNER_BOAZ_ACCEPTANCE_EXPECT_PROMPT=$(BOAZ_ACCEPTANCE_EXPECT_PROMPT) \
		TEST_RUNNER_BOAZ_ACCEPTANCE_APP=$(if $(BUILD_ONLY),,$(BOAZ_ACCEPTANCE_APP)) $(XCB) -scheme Boaz-macOS -destination 'platform=macOS' \
		-resultBundlePath build/Acceptance-$(TEST).xcresult $(ADHOC) \
		-only-testing:BoazUITests/BoazAcceptanceUITests/$(TEST) test

clean: ## Remove build output (keeps release archives)
	rm -rf "$(DERIVED)" Packages/BoazKit/.build
