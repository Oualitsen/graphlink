CLIENT_DIR = client-app
UPLOAD_SERVER_JAR = ../spring_upload_server/build/libs/graphlink-upload-server-0.0.1.jar
UPLOAD_SERVER_URL = http://localhost:9998/graphql
GENERATED_DIR = client-app/src/main/java/dev/graphlink/upload/generated

.PHONY: install generate test clean ci ci-no-generate start-upload-server stop-upload-server

install:
	dart pub get
	cd webclient && dart pub get

clean:
	rm -rf $(GENERATED_DIR)

generate: clean install
	dart run ../generate_reactor_tests.dart
	dart run ../../generate.dart

start-upload-server:
	java -jar $(UPLOAD_SERVER_JAR) --server.port=9998 --management.server.port=9991 > /tmp/java-upload-server.log 2>&1 &
	for i in $$(seq 1 120); do curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -d '{"query":"{__typename}"}' $(UPLOAD_SERVER_URL) && exit 0; sleep 0.5; done; echo "upload server did not start"; exit 1

stop-upload-server:
	curl -s -X POST http://localhost:9991/actuator/shutdown > /dev/null || true

test:
	cd $(CLIENT_DIR) && UPLOAD_SERVER_URL=$(UPLOAD_SERVER_URL) mvn -B -q test && grep -h "Tests run" target/surefire-reports/*.txt

variants: install
	dart run ../generate_reactor_tests.dart
	$(MAKE) clean
	dart run ../../generate.dart
	$(MAKE) test
	$(MAKE) clean
	cd webclient && dart run ../../../generate.dart
	$(MAKE) test

# Runs the same tests against the default adapter and the webclient adapter.
ci:
	$(MAKE) start-upload-server
	status=0; $(MAKE) variants || status=$$?; $(MAKE) stop-upload-server; exit $$status

ci-no-generate: ci
