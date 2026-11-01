GENERATED_DIR = Sources/GraphLinkGenerated
SERVER_JAR = ../spring_persisted_queries_server/build/libs/graphlink-persisted-queries-server-0.0.1.jar

# XCTest isn't available under a CommandLineTools-only toolchain — DEVELOPER_DIR
# must point at a full Xcode install for `swift test` to resolve `import XCTest`.
XCODE_DEVELOPER_DIR = /Applications/Xcode.app/Contents/Developer

.PHONY: generate test clean ci ci-no-generate start-server stop-server

clean:
	rm -rf $(GENERATED_DIR)

generate: clean
	dart pub get
	dart run ../../../generate.dart

start-server:
	curl -s -X POST http://localhost:9992/actuator/shutdown || true
	sleep 2
	java -jar $(SERVER_JAR) &
	sleep 6

stop-server:
	curl -s -X POST http://localhost:9992/actuator/shutdown || true

test:
	DEVELOPER_DIR=$(XCODE_DEVELOPER_DIR) swift test

ci: start-server generate test stop-server

ci-no-generate: start-server test stop-server
