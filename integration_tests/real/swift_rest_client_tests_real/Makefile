PORT = 9983
COMMA_PORT = 9984
XCODE_DEVELOPER_DIR = /Applications/Xcode.app/Contents/Developer

.PHONY: generate generate-comma test test-comma clean ci ci-no-generate start-server stop-server start-comma-server stop-comma-server

clean:
	rm -rf Sources/GraphLinkGenerated comma/Sources/GraphLinkGenerated

generate: clean
	dart pub get
	dart run ../../generate.dart
	$(MAKE) generate-comma

generate-comma:
	cd comma && dart run ../../../generate.dart

start-server:
	python3 ../rest_server/server.py --port $(PORT) > /tmp/rest-server-$(PORT).log 2>&1 &
	for i in $$(seq 1 60); do curl -sf http://127.0.0.1:$(PORT)/health > /dev/null && exit 0; sleep 0.25; done; echo "REST server did not start"; exit 1

stop-server:
	curl -s -X POST http://127.0.0.1:$(PORT)/_shutdown > /dev/null || true

start-comma-server:
	python3 ../rest_server/server.py --port $(COMMA_PORT) > /tmp/rest-server-$(COMMA_PORT).log 2>&1 &
	for i in $$(seq 1 60); do curl -sf http://127.0.0.1:$(COMMA_PORT)/health > /dev/null && exit 0; sleep 0.25; done; echo "REST server did not start"; exit 1

stop-comma-server:
	curl -s -X POST http://127.0.0.1:$(COMMA_PORT)/_shutdown > /dev/null || true

test:
	DEVELOPER_DIR=$(XCODE_DEVELOPER_DIR) swift test

test-comma:
	cd comma && REST_VARIANT=comma DEVELOPER_DIR=$(XCODE_DEVELOPER_DIR) swift test

ci: start-server start-comma-server generate test test-comma stop-server stop-comma-server

ci-no-generate: start-server start-comma-server generate-comma test test-comma stop-server stop-comma-server
