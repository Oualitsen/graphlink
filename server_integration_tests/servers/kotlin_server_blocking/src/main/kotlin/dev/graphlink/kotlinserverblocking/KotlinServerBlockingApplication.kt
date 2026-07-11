package dev.graphlink.kotlinserverblocking

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

@SpringBootApplication
class KotlinServerBlockingApplication

fun main(args: Array<String>) {
    runApplication<KotlinServerBlockingApplication>(*args)
}
