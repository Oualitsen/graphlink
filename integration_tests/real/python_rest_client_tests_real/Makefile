PORT = 9985
COMMA_PORT = 9986
PY := .venv/bin/python

.PHONY: install generate generate-comma test test-comma clean ci ci-no-generate start-server stop-server start-comma-server stop-comma-server

.venv:
	python3 -m venv .venv

install: .venv
	$(PY) -m pip install -q -r requirements.txt

generate:
	dart run ../../generate.dart
	cd comma && dart run ../../../generate.dart

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
	$(PY) -m unittest discover -s tests -t .

test-comma:
	REST_VARIANT=comma $(PY) -m unittest discover -s tests -t .

clean:
	rm -rf generated comma/generated

ci: install start-server start-comma-server generate test test-comma stop-server stop-comma-server

ci-no-generate: install start-server start-comma-server generate-comma test test-comma stop-server stop-comma-server
