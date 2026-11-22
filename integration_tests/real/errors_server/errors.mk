ERRORS_SERVER_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
ERRORS_PORT ?= 9930

.PHONY: start-errors-server stop-errors-server

start-errors-server:
	python3 $(ERRORS_SERVER_DIR)server.py --port $(ERRORS_PORT) > /tmp/errors-server-$(ERRORS_PORT).log 2>&1 &
	for i in $$(seq 1 60); do curl -sf http://127.0.0.1:$(ERRORS_PORT)/health > /dev/null && exit 0; sleep 0.25; done; echo "errors server did not start"; exit 1

stop-errors-server:
	curl -s -X POST http://127.0.0.1:$(ERRORS_PORT)/_shutdown > /dev/null || true
