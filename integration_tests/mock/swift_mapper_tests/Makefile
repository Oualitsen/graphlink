XCODE_DEVELOPER_DIR = /Applications/Xcode.app/Contents/Developer

.PHONY: generate test clean ci ci-no-generate

clean:
	rm -rf Sources/GraphLinkGenerated

generate: clean
	dart pub get
	dart run ../../generate.dart

test:
	DEVELOPER_DIR=$(XCODE_DEVELOPER_DIR) swift test

ci: generate test

ci-no-generate: test
