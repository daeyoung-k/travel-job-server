package com.traveljob

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

@SpringBootApplication
class TravelJobServerApplication

fun main(args: Array<String>) {
    runApplication<TravelJobServerApplication>(*args)
}
