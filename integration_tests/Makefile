.PHONY: dart typescript java kotlin all

dart:
	$(MAKE) -C dart_client_tests ci

typescript:
	$(MAKE) -C typescript_client_tests install
	$(MAKE) -C typescript_client_tests ci

java:
	$(MAKE) -C java_client_tests ci

kotlin:
	$(MAKE) -C kotlin_client_tests ci

all: dart typescript java kotlin
