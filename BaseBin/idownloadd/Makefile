XCODE_PROJECT = src/idownloadd.xcodeproj
XCODE_SCHEME = idownloadd
CS_FLAGS = CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
CONFIGURATION = Release

OUTPUT_NAME = idownloadd

build:
	xcodebuild -archivePath ./.build -project $(XCODE_PROJECT) -scheme $(XCODE_SCHEME) -configuration $(CONFIGURATION) -destination generic/platform=iOS archive $(CS_FLAGS)
	@if [ -f ./.build.xcarchive/Products/usr/local/bin/$(OUTPUT_NAME) ]; then \
		cp -f ./.build.xcarchive/Products/usr/local/bin/$(OUTPUT_NAME) .; \
	else \
		found=$$(find ./.build.xcarchive -name "$(OUTPUT_NAME)" -type f | head -n 1); \
		if [ -n "$$found" ]; then cp -f "$$found" .; fi \
	fi
	@rm -rf ./.build.xcarchive
	@if [ -f $(OUTPUT_NAME) ]; then ldid -Cadhoc -Sentitlements.plist $(OUTPUT_NAME); fi

clean:
	xcodebuild -project $(XCODE_PROJECT) -scheme $(XCODE_SCHEME) -configuration $(CONFIGURATION) -destination generic/platform=iOS clean
	@rm -rf $(OUTPUT_NAME)

default: build