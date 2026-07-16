GENERATED_DIR     = Sources/GraphLinkGenerated
SERVER_JAR        = ../spring_server/build/libs/graphlink-test-server-0.0.1.jar
UPLOAD_SERVER_JAR = ../spring_upload_server/build/libs/graphlink-upload-server-0.0.1.jar

# XCTest isn't available under a CommandLineTools-only toolchain — DEVELOPER_DIR
# must point at a full Xcode install for `swift test` to resolve `import XCTest`.
XCODE_DEVELOPER_DIR = /Applications/Xcode.app/Contents/Developer

.PHONY: generate test clean ci ci-no-generate start-server stop-server start-upload-server stop-upload-server

clean:
	rm -rf $(GENERATED_DIR)

generate: clean
	dart pub get
	dart run ../generate.dart

start-server:
	curl -s -X POST http://localhost:9990/actuator/shutdown || true
	sleep 2
	java -jar $(SERVER_JAR) --server.port=9999 --management.server.port=9990 &
	sleep 6

stop-server:
	curl -s -X POST http://localhost:9990/actuator/shutdown || true

start-upload-server:
	curl -s -X POST http://localhost:9991/actuator/shutdown || true
	sleep 2
	java -jar $(UPLOAD_SERVER_JAR) --server.port=9998 --management.server.port=9991 &
	sleep 6

stop-upload-server:
	curl -s -X POST http://localhost:9991/actuator/shutdown || true

test:
	DEVELOPER_DIR=$(XCODE_DEVELOPER_DIR) swift test

ci: start-server start-upload-server generate test stop-server stop-upload-server

ci-no-generate: start-server start-upload-server test stop-server stop-upload-server
