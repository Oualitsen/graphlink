CLIENT_DIR    = client-app
GENERATED_DIR = client-app/src/main/kotlin/dev/graphlink/test/generated

.PHONY: generate test clean ci

clean:
	rm -rf $(GENERATED_DIR)

generate: clean
	dart pub get
	dart run lib/generate.dart

test:
	cd $(CLIENT_DIR) && ./gradlew test

ci: generate test
