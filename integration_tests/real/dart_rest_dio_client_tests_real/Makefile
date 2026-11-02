PORT = 9996

.PHONY: install generate test clean ci ci-no-generate start-server stop-server

install:
	dart pub get

generate: install
	dart run ../../generate.dart

start-server:
	python3 ../rest_server/server.py --port $(PORT) > /tmp/rest-server-$(PORT).log 2>&1 &
	for i in $$(seq 1 60); do curl -sf http://127.0.0.1:$(PORT)/health > /dev/null && exit 0; sleep 0.25; done; echo "REST server did not start"; exit 1

stop-server:
	curl -s -X POST http://127.0.0.1:$(PORT)/_shutdown > /dev/null || true

test:
	REST_VARIANT=dio dart test test/all_test.dart

clean:
	rm -rf lib/generated

ci: start-server generate test stop-server

# Assumes code has already been generated (e.g. by a prior `make generate-all` job).
ci-no-generate: start-server install test stop-server
