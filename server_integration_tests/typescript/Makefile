.PHONY: install generate start-server stop-server test ci

install:
	$(MAKE) -C typescript_server install
	$(MAKE) -C dart_client install
	$(MAKE) -C typescript_upload_server install
	$(MAKE) -C dart_upload_client install

generate:
	$(MAKE) -C typescript_server generate
	$(MAKE) -C dart_client generate
	$(MAKE) -C typescript_upload_server generate
	$(MAKE) -C dart_upload_client generate

start-server:
	$(MAKE) -C typescript_server start-server
	$(MAKE) -C typescript_upload_server start-server

stop-server:
	$(MAKE) -C typescript_server stop-server
	$(MAKE) -C typescript_upload_server stop-server

test:
	$(MAKE) -C dart_client test
	$(MAKE) -C dart_upload_client test

ci: install generate start-server
	$(MAKE) test || ($(MAKE) stop-server && exit 1)
	$(MAKE) stop-server
