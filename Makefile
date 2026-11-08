# Developer entry points. Run `make help` for the list.

PROJECT  := Folio.xcodeproj
ARCHIVES := build/archives
DERIVED  := build/DerivedData
# CI and local builds skip signing; archives are signed with the team in project.yml.
UNSIGNED := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
XCB      := xcodebuild -project $(PROJECT) -derivedDataPath $(DERIVED) -quiet

.DEFAULT_GOAL := help
.PHONY: help bootstrap project kit ios mac build archive clean

help: ## List the available targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

bootstrap: ## Check the toolchain, install XcodeGen if missing, generate the project
	@xcodebuild -version | head -1
	@command -v xcodegen >/dev/null || brew install xcodegen
	@$(MAKE) --no-print-directory project

project: ## Generate Folio.xcodeproj from project.yml
	xcodegen generate --quiet

kit: ## Build the FolioKit package
	swift build --package-path Packages/FolioKit

ios: project ## Build the iPhone app and extensions (unsigned)
	$(XCB) -scheme Folio-iOS -configuration Debug -destination 'generic/platform=iOS' $(UNSIGNED) build

mac: project ## Build the Mac app (unsigned)
	$(XCB) -scheme Folio-macOS -configuration Debug -destination 'generic/platform=macOS' $(UNSIGNED) build

build: kit ios mac ## Build FolioKit and both apps (what CI runs)

archive: project ## Signed Release archives for App Store Connect, in build/archives
	xcodebuild archive -project $(PROJECT) -scheme Folio-iOS -configuration Release \
		-destination 'generic/platform=iOS' -archivePath $(ARCHIVES)/Folio-iOS.xcarchive -allowProvisioningUpdates
	xcodebuild archive -project $(PROJECT) -scheme Folio-macOS -configuration Release \
		-destination 'generic/platform=macOS' -archivePath $(ARCHIVES)/Folio-macOS.xcarchive -allowProvisioningUpdates

clean: ## Remove build output (keeps release archives)
	rm -rf "$(DERIVED)" Packages/FolioKit/.build
