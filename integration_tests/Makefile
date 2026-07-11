.PHONY: dart typescript java kotlin dart-real typescript-real java-real kotlin-real server upload-server all all-real kill-servers kill-ports start-server start-upload-server start-main-server start-servers generate-all clean-all

# Delete every previously generated output dir across all client projects.
# Prune node_modules/build/target/.gradle/.dart_tool so we only ever touch
# glink's own output, never dependency or compiler build artifacts.
clean-all:
	find . \( -path '*/node_modules' -o -path '*/build' -o -path '*/target' \
	          -o -path '*/.gradle' -o -path '*/.dart_tool' \) -prune \
	          -o -type d -name generated -print -exec rm -rf {} +

# Regenerate every client in a single `dart run` process — generate.dart
# discovers every */config.json under integration_tests/ itself.
generate-all:
	dart run generate.dart

dart:
	$(MAKE) -C dart_client_tests ci

typescript:
	$(MAKE) -C typescript_client_tests install
	$(MAKE) -C typescript_client_tests ci

java:
	$(MAKE) -C java_client_tests ci

kotlin:
	$(MAKE) -C kotlin_client_tests ci

server:
	$(MAKE) -C spring_server build

upload-server:
	$(MAKE) -C spring_upload_server build

dart-real:
	$(MAKE) -C dart_client_tests_real ci

typescript-real:
	$(MAKE) -C typescript_client_tests_real install
	$(MAKE) -C typescript_client_tests_real ci

java-real:
	$(MAKE) -C java_client_tests_real ci

kotlin-real:
	$(MAKE) -C kotlin_client_tests_real ci

all: dart typescript java kotlin

all-real: dart-real typescript-real java-real kotlin-real

start-server:
	curl -s -X POST http://localhost:9990/actuator/shutdown || true
	lsof -ti :9999 | xargs kill -9 2>/dev/null || true
	sleep 1
	java -jar spring_server/build/libs/graphlink-test-server-0.0.1.jar &
	sleep 6
	@echo "Test server running on http://localhost:9999/graphql"

start-upload-server:
	curl -s -X POST http://localhost:9991/actuator/shutdown || true
	lsof -ti :9998 | xargs kill -9 2>/dev/null || true
	sleep 1
	java -jar spring_upload_server/build/libs/graphlink-upload-server-0.0.1.jar &
	sleep 6
	@echo "Upload server running on http://localhost:9998/graphql"

start-main-server:
	$(eval _PORT := $(word 2,$(MAKECMDGOALS)))
	@if [ -z "$(_PORT)" ]; then echo "Usage: make start-main-server <port>"; exit 1; fi
	curl -s -X POST http://localhost:9990/actuator/shutdown || true
	lsof -ti :$(_PORT) | xargs kill -9 2>/dev/null || true
	sleep 1
	java -Dserver.port=$(_PORT) -jar spring_server/build/libs/graphlink-test-server-0.0.1.jar &
	sleep 6
	@echo "Test server running on http://localhost:$(_PORT)/graphql"

start-servers: start-server start-upload-server

kill-servers:
	curl -s -X POST http://localhost:9990/actuator/shutdown || true
	curl -s -X POST http://localhost:9991/actuator/shutdown || true
	lsof -ti :9999 | xargs kill -9 2>/dev/null || true
	lsof -ti :9998 | xargs kill -9 2>/dev/null || true

%:
	@:

kill-ports:
	for port in $$(seq 9900 9999); do \
		pids=$$(lsof -ti :$$port 2>/dev/null); \
		if [ -n "$$pids" ]; then \
			echo "$$pids" | xargs kill -9 2>/dev/null && echo "Killed process(es) on port $$port: $$pids" || echo "Failed to kill process(es) on port $$port: $$pids"; \
		else \
			echo "No process on port $$port"; \
		fi; \
	done
