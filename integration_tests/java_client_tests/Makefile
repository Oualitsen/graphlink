CLIENT_DIR = client-app
GENERATED_DIR = client-app/src/main/java/dev/graphlink/test/generated

.PHONY: generate test clean ci ci-no-generate

clean:
	rm -rf $(GENERATED_DIR)

generate: clean
	dart pub get
	dart run ../generate.dart

test:
	cd $(CLIENT_DIR) && mvn test

ci: generate test

# Assumes code has already been generated (e.g. by a prior `make generate-all` job).
ci-no-generate: test
