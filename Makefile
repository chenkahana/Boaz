# Developer entry points. Run `make help` for the list.

PROJECT  := Boaz.xcodeproj
ARCHIVES := build/archives
DERIVED  := build/DerivedData
# CI and local builds skip signing; archives are signed with the team in project.yml.
UNSIGNED := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
XCB      := xcodebuild -project $(PROJECT) -derivedDataPath $(DERIVED) -quiet

.DEFAULT_GOAL := help
.PHONY: help bootstrap project kit ios mac build archive dmg clean

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

ios: project ## Build the iPhone app and extensions (unsigned)
	$(XCB) -scheme Boaz-iOS -configuration Debug -destination 'generic/platform=iOS' $(UNSIGNED) build

mac: project ## Build the Mac app (unsigned)
	$(XCB) -scheme Boaz-macOS -configuration Debug -destination 'generic/platform=macOS' $(UNSIGNED) build

build: kit ios mac ## Build BoazKit and both apps (what CI runs)

archive: project ## Signed Release archives for App Store Connect, in build/archives
	xcodebuild archive -project $(PROJECT) -scheme Boaz-iOS -configuration Release \
		-destination 'generic/platform=iOS' -archivePath $(ARCHIVES)/Boaz-iOS.xcarchive -allowProvisioningUpdates
	xcodebuild archive -project $(PROJECT) -scheme Boaz-macOS -configuration Release \
		-destination 'generic/platform=macOS' -archivePath $(ARCHIVES)/Boaz-macOS.xcarchive -allowProvisioningUpdates

dmg: ## Developer ID DMG for download outside the App Store: make dmg VERSION=1.2.0 (docs/release.md)
	Tools/release-mac.sh $(VERSION)

clean: ## Remove build output (keeps release archives)
	rm -rf "$(DERIVED)" Packages/BoazKit/.build
