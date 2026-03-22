SERVER_JAR = spring-server/target/graphql-server-0.0.1-SNAPSHOT.jar

clean:
	rm -rf client-app/src/main/java/com/example/generated

generate: clean
	dart run lib/generate.dart

build-server:
	cd spring-server && mvn package -DskipTests -q

build-client:
	cd client-app && mvn compile -q

run-server:
	java -jar $(SERVER_JAR)

run-client:
	cd client-app && mvn exec:java -Dexec.mainClass="com.example.Main" -q
