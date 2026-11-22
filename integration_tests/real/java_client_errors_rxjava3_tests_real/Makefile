CLIENT_DIR = client-app
ERRORS_PORT = 9930
GENERATED_DIR = client-app/src/main/java/dev/graphlink/errors/generated

.PHONY: install generate test clean ci ci-no-generate run

install:
	dart pub get

clean:
	rm -rf $(GENERATED_DIR)

generate: clean install
	dart run ../../generate.dart

test:
	cd $(CLIENT_DIR) && mvn -B -q test && grep -h "Tests run" target/surefire-reports/*.txt

run: generate test

ci: start-errors-server
	status=0; $(MAKE) run || status=$$?; $(MAKE) stop-errors-server; exit $$status

ci-no-generate: start-errors-server
	status=0; $(MAKE) test || status=$$?; $(MAKE) stop-errors-server; exit $$status

include ../errors_server/errors.mk
