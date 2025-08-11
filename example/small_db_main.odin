package main

import "core:fmt"
import 

User :: struct {
	name: [32]u8,
	age: i16,
}

Entity_ID :: enum {
	USER = 0,
}

main :: proc() {
	ctx: 

	path := "db.sdb"
	register_entity(path, []{
		.USER,
	})
}