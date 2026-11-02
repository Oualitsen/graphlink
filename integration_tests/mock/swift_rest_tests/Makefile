XCODE_DEVELOPER_DIR = /Applications/Xcode.app/Contents/Developer

.PHONY: generate generate-rest-only test clean ci ci-no-generate

clean:
	rm -rf Sources/GraphLinkGenerated rest_only/Sources/GraphLinkGenerated

generate: clean
	dart pub get
	dart run ../../generate.dart
	$(MAKE) generate-rest-only

generate-rest-only:
	cd rest_only && dart run ../../../generate.dart

test:
	DEVELOPER_DIR=$(XCODE_DEVELOPER_DIR) swift test
	cd rest_only && DEVELOPER_DIR=$(XCODE_DEVELOPER_DIR) swift test

ci: generate test

ci-no-generate: generate-rest-only test
