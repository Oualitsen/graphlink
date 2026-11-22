CLIENT_DIR = client-app
GENERATED_DIR = client-app/src/main/kotlin/dev/graphlink/mappermock/generated
SERVER_DIR = client-app/src/main/kotlin/dev/graphlink/mappermock/generatedserver

.PHONY: install generate generate-server test clean ci ci-no-generate

install:
	dart pub get

clean:
	rm -rf $(GENERATED_DIR) $(SERVER_DIR)

generate: clean install
	dart run ../../generate.dart
	$(MAKE) generate-server

generate-server:
	rm -rf $(SERVER_DIR)
	dart run ../../../lib/src/main.dart -c config.server.json

test:
	cd $(CLIENT_DIR) && ./gradlew test

ci: generate test

ci-no-generate: install generate-server test
