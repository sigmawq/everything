package main

import "core:fmt"

main :: proc() {}

counter := 0

@(export)
tick :: proc() {
	counter += 1
	fmt.println(counter)
}

