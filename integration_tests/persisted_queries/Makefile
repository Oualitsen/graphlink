.PHONY: mock real all server generate-all clean-all \
	dart typescript java java-reactive kotlin swift \
	dart-real typescript-real java-real java-reactive-real kotlin-real swift-real python-real

clean-all:
	find . \( -path '*/node_modules' -o -path '*/build' -o -path '*/target' \
	          -o -path '*/.gradle' -o -path '*/.dart_tool' \) -prune \
	          -o -type d -name generated -print -exec rm -rf {} +

generate-all:
	dart run ../generate.dart

dart:
	$(MAKE) -C mock/dart_persisted_queries_tests ci

typescript:
	$(MAKE) -C mock/typescript_persisted_queries_tests install
	$(MAKE) -C mock/typescript_persisted_queries_tests ci

java:
	$(MAKE) -C mock/java_persisted_queries_tests ci

java-reactive:
	$(MAKE) -C mock/java_reactor_persisted_queries_tests ci
	$(MAKE) -C mock/java_rxjava3_persisted_queries_tests ci
	$(MAKE) -C mock/java_mutiny_persisted_queries_tests ci

kotlin:
	$(MAKE) -C mock/kotlin_persisted_queries_tests ci

swift:
	$(MAKE) -C mock/swift_persisted_queries_tests ci

python:
	$(MAKE) -C mock/python_persisted_queries_tests ci

server:
	$(MAKE) -C real/spring_persisted_queries_server build

dart-real:
	$(MAKE) -C real/dart_persisted_queries_tests_real ci

typescript-real:
	$(MAKE) -C real/typescript_persisted_queries_tests_real install
	$(MAKE) -C real/typescript_persisted_queries_tests_real ci

java-real:
	$(MAKE) -C real/java_persisted_queries_tests_real ci

java-reactive-real:
	$(MAKE) -C real/java_reactor_persisted_queries_tests_real ci
	$(MAKE) -C real/java_rxjava3_persisted_queries_tests_real ci
	$(MAKE) -C real/java_mutiny_persisted_queries_tests_real ci

kotlin-real:
	$(MAKE) -C real/kotlin_persisted_queries_tests_real ci

swift-real:
	$(MAKE) -C real/swift_persisted_queries_tests_real ci

python-real:
	$(MAKE) -C real/python_persisted_queries_tests_real ci

mock: dart typescript java java-reactive kotlin swift python

real: dart-real typescript-real java-real java-reactive-real kotlin-real swift-real python-real

all: mock real
