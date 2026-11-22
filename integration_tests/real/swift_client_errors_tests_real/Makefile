ERRORS_PORT = 9930
XCODE_DEVELOPER_DIR = /Applications/Xcode.app/Contents/Developer

.PHONY: generate test clean ci ci-no-generate run

clean:
	rm -rf Sources/GraphLinkGenerated

generate: clean
	dart pub get
	dart run ../../generate.dart

test:
	DEVELOPER_DIR=$(XCODE_DEVELOPER_DIR) swift test

run: generate test

ci: start-errors-server
	status=0; $(MAKE) run || status=$$?; $(MAKE) stop-errors-server; exit $$status

ci-no-generate: start-errors-server
	status=0; $(MAKE) test || status=$$?; $(MAKE) stop-errors-server; exit $$status

include ../errors_server/errors.mk
