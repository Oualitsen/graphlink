JAVA_PORT = 9996

.PHONY: generate build start-server stop-server test ci

generate:
	$(MAKE) -C java_server generate

build:
	$(MAKE) -C java_server build

start-server:
	$(MAKE) -C java_server start-server

stop-server:
	$(MAKE) -C java_server stop-server

test:
	$(MAKE) -C ../dart_client test PORT=$(JAVA_PORT)

ci: generate build start-server
	$(MAKE) test || ($(MAKE) stop-server && exit 1)
	$(MAKE) stop-server
