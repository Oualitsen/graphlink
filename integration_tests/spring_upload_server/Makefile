.PHONY: build start stop ci

build:
	./gradlew build -x test

start:
	./gradlew bootRun &

stop:
	curl -s -X POST http://localhost:9991/actuator/shutdown || true

ci: build
	./gradlew bootRun &
	sleep 8
	echo "Upload server started on port 9998"
