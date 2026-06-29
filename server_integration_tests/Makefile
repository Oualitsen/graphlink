.PHONY: install generate start-server stop-server test ci typescript kotlin java setup-client

setup-client:
	$(MAKE) -C dart_client install
	$(MAKE) -C dart_client generate

install:
	$(MAKE) -C dart_client install
	$(MAKE) -C typescript install

generate:
	$(MAKE) -C dart_client generate
	$(MAKE) -C typescript generate

start-server:
	$(MAKE) -C typescript start-server

stop-server:
	$(MAKE) -C typescript stop-server

test:
	$(MAKE) -C typescript test

ci: setup-client
	$(MAKE) -C typescript ci

typescript: setup-client
	$(MAKE) -C typescript ci

kotlin: setup-client
	$(MAKE) -C kotlin ci

java: setup-client
	$(MAKE) -C java ci