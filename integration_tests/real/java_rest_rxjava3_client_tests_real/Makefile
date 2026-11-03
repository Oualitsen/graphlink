PORT = 9979
CLIENT_DIR = client-app
GENERATED_DIR = client-app/src/main/java/dev/graphlink/rest/generated

.PHONY: generate test clean ci ci-no-generate start-server stop-server

clean:
	rm -rf $(GENERATED_DIR)

generate: clean
	dart pub get
	dart run ../generate_reactor_tests.dart
	dart run ../../generate.dart

start-server:
	python3 ../rest_server/server.py --port $(PORT) > /tmp/rest-server-$(PORT).log 2>&1 &
	for i in $$(seq 1 60); do curl -sf http://127.0.0.1:$(PORT)/health > /dev/null && exit 0; sleep 0.25; done; echo "REST server did not start"; exit 1

stop-server:
	curl -s -X POST http://127.0.0.1:$(PORT)/_shutdown > /dev/null || true

test:
	cd $(CLIENT_DIR) && mvn -B -q test

ci: start-server generate test stop-server

ci-no-generate: start-server test stop-server
