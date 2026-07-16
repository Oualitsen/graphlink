PORT ?= 9997

# XCTest isn't available under a CommandLineTools-only toolchain — DEVELOPER_DIR
# must point at a full Xcode install for `swift test` to resolve `import XCTest`.
XCODE_DEVELOPER_DIR = /Applications/Xcode.app/Contents/Developer

.PHONY: install generate test ci remove-generated

install:
	true

remove-generated:
	rm -rf Sources/GraphLinkGenerated

generate: remove-generated
	dart run ../../generate.dart

test:
	SERVER_PORT=$(PORT) DEVELOPER_DIR=$(XCODE_DEVELOPER_DIR) swift test

ci: install generate test
