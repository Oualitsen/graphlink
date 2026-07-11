PORT ?= 9997

.PHONY: install generate test ci remove-generated

install:
	true

remove-generated:
	rm -rf client-app/src/main/kotlin/dev/graphlink/server/generated

generate: remove-generated
	dart run ../../../lib/src/main.dart -c config.json

test:
	cd client-app && SERVER_PORT=$(PORT) ./gradlew test

ci: install generate test
