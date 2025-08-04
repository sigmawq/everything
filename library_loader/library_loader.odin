package main

import "library_header"
import "core:fmt"
import "core:mem"

tracking_plus_library_loading :: proc() {	
	tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(
		&tracking_allocator,
		context.allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)
	// tracking_allocator.bad_free_callback = nil
	
	array := make([dynamic]int, 10000)
	for i in 0..<5 {
		a := new(int)
		fmt.println(a)
	}
	
	// bad_pointer := 0xFFFF
	// free(transmute(rawptr)bad_pointer)
	
	// delete(array)
	
	fmt.printf("%#v", tracking_allocator)
	
	fmt.println(library_header.some_function())
}

wasm_entry :: proc() {
	fmt.print("hello wasm")
}

main :: proc() {
	wasm_entry
}