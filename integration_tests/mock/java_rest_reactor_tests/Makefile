CLIENT_DIR = client-app
GENERATED_DIR = client-app/src/main/java/dev/graphlink/restmock/generated

.PHONY: generate test clean ci ci-no-generate

clean:
	rm -rf $(GENERATED_DIR)

generate: clean
	dart pub get
	dart run ../../generate.dart

test:
	cd $(CLIENT_DIR) && mvn -B -q test

ci: generate test

ci-no-generate: test
