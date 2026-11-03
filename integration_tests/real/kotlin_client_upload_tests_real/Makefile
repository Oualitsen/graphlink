CLIENT_DIR = client-app
GENERATED_DIR = client-app/src/main/kotlin/dev/graphlink/upload/generated
UPLOAD_SERVER_JAR = ../spring_upload_server/build/libs/graphlink-upload-server-0.0.1.jar
UPLOAD_SERVER_URL = http://localhost:9998/graphql

.PHONY: install generate test clean ci ci-no-generate start-upload-server stop-upload-server

install:
	dart pub get

clean:
	rm -rf $(GENERATED_DIR)

generate: clean install
	dart run ../../generate.dart

start-upload-server:
	java -jar $(UPLOAD_SERVER_JAR) --server.port=9998 --management.server.port=9991 > /tmp/kotlin-upload-server.log 2>&1 &
	for i in $$(seq 1 120); do curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -d '{"query":"{__typename}"}' $(UPLOAD_SERVER_URL) && exit 0; sleep 0.5; done; echo "upload server did not start"; exit 1

stop-upload-server:
	curl -s -X POST http://localhost:9991/actuator/shutdown > /dev/null || true

test:
	cd $(CLIENT_DIR) && UPLOAD_SERVER_URL=$(UPLOAD_SERVER_URL) ./gradlew test

run: generate test

ci:
	$(MAKE) start-upload-server
	status=0; $(MAKE) run || status=$$?; $(MAKE) stop-upload-server; exit $$status

# Assumes code has already been generated (e.g. by a prior `make generate-all` job).
ci-no-generate:
	$(MAKE) start-upload-server
	status=0; $(MAKE) test || status=$$?; $(MAKE) stop-upload-server; exit $$status
