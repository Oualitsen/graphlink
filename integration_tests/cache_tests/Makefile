JAR = spring-server/target/graphql-server-0.0.1-SNAPSHOT.jar

clean:
	rm -rf lib/generated

generate: clean
	dart run lib/generate.dart

build-server:
	cd spring-server && mvn package -DskipTests -q

run-server:
	java -jar $(JAR)

test:
	dart test cache_integration_test.dart
