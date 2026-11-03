PORT = 9970
UPLOAD_SERVER_JAR = ../spring_upload_server/build/libs/graphlink-upload-server-0.0.1.jar
UPLOAD_SERVER_URL = http://localhost:9998/graphql
XCODE_DEVELOPER_DIR = /Applications/Xcode.app/Contents/Developer

.PHONY: generate test clean ci ci-no-generate start-servers stop-servers run

clean:
	rm -rf Sources/GraphLinkGenerated

generate: clean
	dart pub get
	dart run ../../generate.dart

start-servers:
	python3 recording_server.py --port $(PORT) > /tmp/swift-recording-server.log 2>&1 &
	for i in $$(seq 1 60); do curl -sf http://127.0.0.1:$(PORT)/health > /dev/null && break; sleep 0.25; done
	java -jar $(UPLOAD_SERVER_JAR) --server.port=9998 --management.server.port=9991 > /tmp/swift-upload-server.log 2>&1 &
	for i in $$(seq 1 120); do curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -d '{"query":"{__typename}"}' $(UPLOAD_SERVER_URL) && exit 0; sleep 0.5; done; echo "upload server did not start"; exit 1

stop-servers:
	curl -s -X POST http://127.0.0.1:$(PORT)/_shutdown > /dev/null || true
	curl -s -X POST http://localhost:9991/actuator/shutdown > /dev/null || true

test:
	RECORDING_PORT=$(PORT) UPLOAD_SERVER_URL=$(UPLOAD_SERVER_URL) DEVELOPER_DIR=$(XCODE_DEVELOPER_DIR) swift test

run: generate test

ci:
	$(MAKE) start-servers
	status=0; $(MAKE) run || status=$$?; $(MAKE) stop-servers; exit $$status

# Assumes code has already been generated (e.g. by a prior `make generate-all` job).
ci-no-generate:
	$(MAKE) start-servers
	status=0; $(MAKE) test || status=$$?; $(MAKE) stop-servers; exit $$status
