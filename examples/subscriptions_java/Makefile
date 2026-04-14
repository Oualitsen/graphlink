generate-server: clean-server
	$(MAKE) -C subscription-server generate

generate-client-java11: clean-client-java11
	$(MAKE) -C subscriptions-client-java11 generate

generate-client-okhttp: clean-client-okhttp
	$(MAKE) -C subscriptions-client-okhttp generate

generate: generate-server generate-client-java11 generate-client-okhttp

clean-server:
	$(MAKE) -C subscription-server clean

clean-client-java11:
	$(MAKE) -C subscriptions-client-java11 clean

clean-client-okhttp:
	$(MAKE) -C subscriptions-client-okhttp clean

clean: clean-server clean-client-java11 clean-client-okhttp
