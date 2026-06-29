.PHONY: install generate start-server stop-server test ci typescript kotlin java

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

ci:
	$(MAKE) -C typescript ci

typescript:
	$(MAKE) -C typescript ci

kotlin:
	$(MAKE) -C kotlin ci

java:
	$(MAKE) -C java ci