.PHONY: build clean generate test ci ci-no-generate

GENERATED_DIR = Sources/GraphLinkGenerated

# XCTest/swift-testing aren't available under a CommandLineTools-only
# toolchain — DEVELOPER_DIR must point at a full Xcode install for `swift
# test` to resolve `import XCTest`. No global `xcode-select -s` needed, this
# is scoped per-invocation.
XCODE_DEVELOPER_DIR = /Applications/Xcode.app/Contents/Developer

build:
	swift build

clean:
	rm -rf $(GENERATED_DIR)

generate: clean
	dart pub get
	dart run ../generate.dart

test:
	DEVELOPER_DIR=$(XCODE_DEVELOPER_DIR) swift test

ci: generate test

ci-no-generate: test
