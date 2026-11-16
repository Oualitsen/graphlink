NAME = java_server
START_CMD = env FIXTURES_PATH=$(FIXTURES) ./gradlew bootRun
PORT = 9996
MANAGEMENT_PORT = 9990
PID_FILE = .server.pid
FIXTURES := $(abspath ../../fixtures.json)

.PHONY: generate build start-server start-server-sync stop-server

generate: remove-generated
	dart run ../../generate.dart

build:
	./gradlew build -x test


start-server-sync:
	-lsof -ti :$(PORT) | xargs kill -9 2>/dev/null || true
	-lsof -ti :$(MANAGEMENT_PORT) | xargs kill -9 2>/dev/null || true
	FIXTURES_PATH=$(FIXTURES) ./gradlew bootRun


ci: generate build

remove-generated:
	rm -rf src/main/java/dev/graphlink/javaserver/generated

include ../../scripts/server.mk
