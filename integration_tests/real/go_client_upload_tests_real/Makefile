UPLOAD_SERVER_JAR = ../spring_upload_server/build/libs/graphlink-upload-server-0.0.1.jar
UPLOAD_SERVER_URL = http://localhost:9998/graphql

.PHONY: generate test clean ci ci-no-generate start-upload-server stop-upload-server run

generate:
	rm -rf generated
	dart pub get 2>/dev/null || true
	dart run ../../generate.dart

clean:
	rm -rf generated

start-upload-server:
	java -jar $(UPLOAD_SERVER_JAR) --server.port=9998 --management.server.port=9991 > /tmp/go-upload-server.log 2>&1 &
	for i in $$(seq 1 120); do curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -d '{"query":"{__typename}"}' $(UPLOAD_SERVER_URL) && exit 0; sleep 0.5; done; echo "upload server did not start"; exit 1

stop-upload-server:
	curl -s -X POST http://localhost:9991/actuator/shutdown > /dev/null || true

test:
	UPLOAD_SERVER_URL=$(UPLOAD_SERVER_URL) go test -count=1 -p 1 ./tests/...

run: generate test

ci:
	$(MAKE) start-upload-server
	status=0; $(MAKE) run || status=$$?; $(MAKE) stop-upload-server; exit $$status

# Assumes code has already been generated (e.g. by a prior `make generate-all` job).
ci-no-generate:
	$(MAKE) start-upload-server
	status=0; $(MAKE) test || status=$$?; $(MAKE) stop-upload-server; exit $$status
