CLIENT_DIR = client-app
GENERATED_DIR = client-app/src/main/java/dev/graphlink/mappermock/generated
SERVER_DIR = client-app/src/main/java/dev/graphlink/mappermock/generatedserver

.PHONY: generate generate-server test clean ci ci-no-generate

clean:
	rm -rf $(GENERATED_DIR) $(SERVER_DIR)

generate: clean
	dart pub get
	dart run ../../generate.dart
	$(MAKE) generate-server

generate-server:
	rm -rf $(SERVER_DIR)
	dart pub get
	dart run ../../../lib/src/main.dart -c config.server.json

test:
	cd $(CLIENT_DIR) && mvn -B -q test

ci: generate test

ci-no-generate: generate-server test
