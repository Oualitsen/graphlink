SPRING_JAR = ../cache_tests/spring-server/target/graphql-server-0.0.1-SNAPSHOT.jar
CLIENT_DIR = client-app

clean:
	rm -rf client-app/src/main/java/com/example/generated

generate: clean
	dart run lib/generate.dart

build-server:
	cd ../cache_tests/spring-server && mvn package -DskipTests -q

run-server:
	java -jar $(SPRING_JAR)

build-tests:
	cd $(CLIENT_DIR) && mvn test-compile -q

test:
	cd $(CLIENT_DIR) && mvn test -Dspring.jar.path=../$(SPRING_JAR)
