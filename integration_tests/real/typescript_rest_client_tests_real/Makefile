PORT = 9993
AXIOS_PORT = 9989

.PHONY: install generate generate-axios typecheck test test-axios clean ci ci-no-generate start-server stop-server start-axios-server stop-axios-server

install:
	dart pub get
	npm install

generate: install
	dart run ../../generate.dart
	$(MAKE) generate-axios

generate-axios:
	cd axios && dart run ../../../generate.dart

start-server:
	python3 ../rest_server/server.py --port $(PORT) > /tmp/rest-server-$(PORT).log 2>&1 &
	for i in $$(seq 1 60); do curl -sf http://127.0.0.1:$(PORT)/health > /dev/null && exit 0; sleep 0.25; done; echo "REST server did not start"; exit 1

stop-server:
	curl -s -X POST http://127.0.0.1:$(PORT)/_shutdown > /dev/null || true

start-axios-server:
	python3 ../rest_server/server.py --port $(AXIOS_PORT) > /tmp/rest-server-$(AXIOS_PORT).log 2>&1 &
	for i in $$(seq 1 60); do curl -sf http://127.0.0.1:$(AXIOS_PORT)/health > /dev/null && exit 0; sleep 0.25; done; echo "REST server did not start"; exit 1

stop-axios-server:
	curl -s -X POST http://127.0.0.1:$(AXIOS_PORT)/_shutdown > /dev/null || true

typecheck:
	npx tsc --noEmit

test:
	npx vitest run

test-axios:
	REST_VARIANT=axios npx vitest run

clean:
	rm -rf lib/generated axios/lib/generated

ci: start-server start-axios-server generate typecheck test test-axios stop-server stop-axios-server

# Assumes code has already been generated (e.g. by a prior `make generate-all` job).
ci-no-generate: start-server start-axios-server install generate-axios typecheck test test-axios stop-server stop-axios-server
