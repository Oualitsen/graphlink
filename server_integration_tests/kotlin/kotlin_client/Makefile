PORT ?= 9994

.PHONY: generate test

generate:
	dart run ../../../lib/src/main.dart -c config.json

test:
	cd client-app && ./gradlew test -DserverPort=$(PORT)
