GRAPHLINK = dart run main.dart

# ── Generate ──────────────────────────────────────────────────────────────────

dart-dio:
	$(MAKE) -C dart_dio_app generate

dart-http:
	$(MAKE) -C dart_http_app generate

java-okhttp: clean-java-okhttp
	$(GRAPHLINK) --config java_okhttp_app/config.json

java-java11: clean-java-java11
	$(GRAPHLINK) --config java_java11_client_app/config.json

spring: clean-spring
	$(GRAPHLINK) --config spring_app/config.json

all: dart-dio dart-http java-okhttp java-java11 spring

# ── Clean ─────────────────────────────────────────────────────────────────────

clean-dart-dio:
	$(MAKE) -C dart_dio_app clean

clean-dart-http:
	$(MAKE) -C dart_http_app clean

clean-java-okhttp:
	rm -rf java_okhttp_app/src/main/java/com/example/generated

clean-java-java11:
	rm -rf java_java11_client_app/src/main/java/com/example/generated

clean-spring:
	rm -rf spring_app/src/main/java/dev/graphlink/demo/generated

clean: clean-dart-dio clean-dart-http clean-java-okhttp clean-java-java11 clean-spring

.PHONY: all dart-dio dart-http java-okhttp java-java11 spring \
        clean clean-dart-dio clean-dart-http clean-java-okhttp clean-java-java11 clean-spring
