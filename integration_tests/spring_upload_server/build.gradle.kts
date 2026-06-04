plugins {
    java
    id("org.springframework.boot") version "3.4.1"
    id("io.spring.dependency-management") version "1.1.7"
}

group = "dev.graphlink"
version = "0.0.1"

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

repositories {
    mavenCentral()
}

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-graphql")
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.boot:spring-boot-starter-actuator")
    // Adds multipart/form-data support to Spring for GraphQL (registers the Upload scalar)
    implementation("name.nkonev.multipart-spring-graphql:multipart-spring-graphql:1.5.3")
    testImplementation("org.springframework.boot:spring-boot-starter-test")
}
