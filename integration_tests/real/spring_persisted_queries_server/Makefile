.PHONY: build start stop ci

build:
	./gradlew build -x test

start:
	./gradlew bootRun &

stop:
	curl -s -X POST http://localhost:9990/actuator/shutdown || true

ci: build
	./gradlew bootRun &
	sleep 8
	echo "Server started"
