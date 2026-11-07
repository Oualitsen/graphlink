PORT = 9981
COMMA_PORT = 9982
FAULT_PORT = 9962
COMMA_FAULT_PORT = 9963

include ../fault_server/fault.mk

.PHONY: generate generate-comma test test-comma clean ci ci-no-generate start-server stop-server start-comma-server stop-comma-server

clean:
	rm -rf generated comma/generated

generate: clean
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

start-comma-fault-server:
	$(MAKE) start-fault-server FAULT_PORT=$(COMMA_FAULT_PORT)

stop-comma-fault-server:
	$(MAKE) stop-fault-server FAULT_PORT=$(COMMA_FAULT_PORT)

test:
	go test -count=1 ./tests/...

test-comma:
	cd comma && REST_VARIANT=comma go test -count=1 ./tests/...

ci: start-server start-comma-server start-fault-server start-comma-fault-server generate test test-comma stop-server stop-comma-server stop-fault-server stop-comma-fault-server

ci-no-generate: start-server start-comma-server start-fault-server start-comma-fault-server generate-comma test test-comma stop-server stop-comma-server stop-fault-server stop-comma-fault-server
