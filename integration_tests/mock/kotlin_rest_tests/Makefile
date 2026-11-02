CLIENT_DIR = client-app
GENERATED_DIR = client-app/src/main/kotlin/dev/graphlink/restmock/generated

.PHONY: install generate test clean ci ci-no-generate

install:
	dart pub get

clean:
	rm -rf $(GENERATED_DIR)

generate: clean install
	dart run ../../generate.dart

test:
	cd $(CLIENT_DIR) && ./gradlew test

ci: generate test

# Assumes code has already been generated (e.g. by a prior `make generate-all` job).
ci-no-generate: test
