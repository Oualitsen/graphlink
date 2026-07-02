GENERATED_DIR = client-app/src/main/kotlin/dev/graphlink/github/generated

.PHONY: clean generate compile compile-only kill-daemon

clean:
	rm -rf $(GENERATED_DIR)

generate: clean
	fvm dart run ../../../lib/src/main.dart -c config.json

compile: generate
	cd client-app && ./gradlew compileKotlin

compile-only:
	cd client-app && ./gradlew compileKotlin

kill-daemon:
	cd client-app && ./gradlew --stop
	pkill -f KotlinCompileDaemon || true
	rm -f "$(HOME)/Library/Application Support/kotlin/daemon/"*.tmp
