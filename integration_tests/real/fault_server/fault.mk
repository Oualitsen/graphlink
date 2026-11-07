FAULT_SERVER_DIR := $(dir $(lastword $(MAKEFILE_LIST)))

.PHONY: start-fault-server stop-fault-server

start-fault-server:
	python3 $(FAULT_SERVER_DIR)server.py --port $(FAULT_PORT) > /tmp/fault-server-$(FAULT_PORT).log 2>&1 &
	for i in $$(seq 1 60); do curl -sf http://127.0.0.1:$(FAULT_PORT)/health > /dev/null && exit 0; sleep 0.25; done; echo "fault server did not start"; exit 1

stop-fault-server:
	curl -s -X POST http://127.0.0.1:$(FAULT_PORT)/_shutdown > /dev/null || true
