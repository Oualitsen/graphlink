BLOCKING_PORT = 9994
SUSPEND_PORT  = 9995

.PHONY: generate build start-server stop-server test ci

generate:
	$(MAKE) -C kotlin_server_blocking generate
	$(MAKE) -C kotlin_server_suspend generate

build:
	$(MAKE) -C kotlin_server_blocking build
	$(MAKE) -C kotlin_server_suspend build

start-server:
	$(MAKE) -C kotlin_server_blocking start-server
	$(MAKE) -C kotlin_server_suspend start-server

stop-server:
	$(MAKE) -C kotlin_server_blocking stop-server
	$(MAKE) -C kotlin_server_suspend stop-server

test:
	$(MAKE) -C ../dart_client test PORT=$(BLOCKING_PORT)
	$(MAKE) -C ../dart_client test PORT=$(SUSPEND_PORT)

ci: generate build start-server
	$(MAKE) test || ($(MAKE) stop-server && exit 1)
	$(MAKE) stop-server
