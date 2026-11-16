PORT ?= 9997

.PHONY: install generate test ci remove-generated java8-check

install:
	true

remove-generated:
	rm -rf client-app/src/main/java/dev/graphlink/server/generated

generate: remove-generated
	dart run ../../generate.dart

test:
	cd client-app && SERVER_PORT=$(PORT) mvn -q test

# Generated code must compile on Java 8 (the java11 transports excepted), whatever JDK runs the tests.
java8-check:
	cd client-app && mvn -q dependency:build-classpath -Dmdep.outputFile=target/java8.classpath
	cd client-app && ../../../scripts/java8_check.sh src/main/java src/main/java/dev/graphlink/server/generated target/java8.classpath

ci: install generate test
