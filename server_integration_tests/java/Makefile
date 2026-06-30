JAVA_PORT = 9996

.PHONY: generate build start-server stop-server test ci \
        generate-reactive build-reactive start-server-reactive stop-server-reactive ci-reactive

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

generate-reactive:
	$(MAKE) -C java_server_reactive generate

build-reactive:
	$(MAKE) -C java_server_reactive build

start-server-reactive:
	$(MAKE) -C java_server_reactive start-server

stop-server-reactive:
	$(MAKE) -C java_server_reactive stop-server

ci-reactive: generate-reactive build-reactive start-server-reactive
	$(MAKE) test || ($(MAKE) stop-server-reactive && exit 1)
	$(MAKE) stop-server-reactive
