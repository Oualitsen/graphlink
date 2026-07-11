PORT = 9996
MANAGEMENT_PORT = 9990
PID_FILE = .server.pid
FIXTURES := $(abspath ../../fixtures.json)

.PHONY: generate build start-server start-server-sync stop-server

generate: remove-generated
	dart run ../../generate.dart

build:
	./gradlew build -x test

start-server:
	-lsof -ti :$(PORT) | xargs kill -9 2>/dev/null || true
	-lsof -ti :$(MANAGEMENT_PORT) | xargs kill -9 2>/dev/null || true
	FIXTURES_PATH=$(FIXTURES) ./gradlew bootRun > /tmp/java-server.log 2>&1 & echo $$! > $(PID_FILE)
	@echo "Waiting for java_server on port $(PORT)..."
	@tail -f /tmp/java-server.log & echo $$! > $(PID_FILE).tail; \
	while ! curl -s -o /dev/null http://localhost:$(PORT)/graphql; do \
		if ! kill -0 $$(cat $(PID_FILE)) 2>/dev/null; then \
			kill $$(cat $(PID_FILE).tail) 2>/dev/null; rm -f $(PID_FILE).tail; \
			echo "java_server exited before coming up (see /tmp/java-server.log)"; exit 1; \
		fi; \
		sleep 1; \
	done; \
	kill $$(cat $(PID_FILE).tail) 2>/dev/null; rm -f $(PID_FILE).tail
	@echo "java_server is up on port $(PORT)"

start-server-sync:
	-lsof -ti :$(PORT) | xargs kill -9 2>/dev/null || true
	-lsof -ti :$(MANAGEMENT_PORT) | xargs kill -9 2>/dev/null || true
	FIXTURES_PATH=$(FIXTURES) ./gradlew bootRun

stop-server:
	-curl -s -X POST http://localhost:$(MANAGEMENT_PORT)/actuator/shutdown 2>/dev/null || true
	-kill $$(cat $(PID_FILE) 2>/dev/null) 2>/dev/null || true
	-lsof -ti :$(PORT) | xargs kill -9 2>/dev/null || true
	-lsof -ti :$(MANAGEMENT_PORT) | xargs kill -9 2>/dev/null || true
	rm -f $(PID_FILE)

ci: generate build

remove-generated:
	rm -rf src/main/java/dev/graphlink/javaserver/generated
