package dev.graphlink.kotlinserversuspend

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

@SpringBootApplication
class KotlinServerSuspendApplication

fun main(args: Array<String>) {
    runApplication<KotlinServerSuspendApplication>(*args)
}
