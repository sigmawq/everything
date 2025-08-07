package main

import packer "../reflect_packer"
import "core:math/rand"
import "core:fmt"
import "core:time"
import "core:mem"
import "core:encoding/json"

Foo :: struct {
	a: i32 `id:"1"`,
	b: i32 `id:"2"`,
	c: f32 `id:"3"`,
	d: i32 `id:"4"`,
	e: i128 `id:"5"`,
}

basic_example :: proc() {
	buffer := packer.buffer_make(5 * 1024 * 1024)
	foo1 := Foo{0xcdcdcd, 255, 3.14, 600, 650}
	ok := packer.pack(foo1, &buffer)
	if !ok {	
		panic("failed to pack")
	}
	for i := 0; i < buffer.i; i += 1 {
		v := buffer.buf[i]
		fmt.printf("0x%x, ", v)
	}
	fmt.println("\n")
	packer.buffer_reset_cursor(&buffer)
	
	foo2 := Foo{}
	if !packer.unpack(foo2, &buffer) {
		panic("failed to unpack")
	}
	assert(foo1 == foo2)
	
	fmt.printf("unpacked struct: %#v\n", foo2)
	ratio := f64(buffer.i) / f64(size_of(foo2))
	fmt.printf("len(buffer) / sizeof(Foo): %f\n", ratio)
}

benchmark :: proc() {
	foos := make([dynamic]Foo, 100000)
	for &foo in foos {
		foo.a = auto_cast rand.int63_max(1_000_000)
		foo.b = auto_cast rand.int63_max(1_000_000)
		foo.c = auto_cast rand.int63_max(1_000_000)
		foo.d = auto_cast rand.int63_max(1_000_000)
		foo.e = auto_cast rand.int63_max(1_000_000)
	}
	
	out := packer.buffer_make(1 * 1024 * 1024 * 1024)
	{
		now := time.now()	
		
		for foo in foos {
			packer.pack(foo, &out)
		}
		
		then := time.now()
		took := time.duration_milliseconds(time.diff(now, then))
		fmt.printf("reflect serializer (serialize):\n    time_total: %.2fms\n    foos/sec: %.1f\n", 
			took, 
			f64(len(foos))/(took/1000),
		)
	}
	
	{
		buffer := make([]u8, 1 * 1024 * 1024 * 1024)
		arena: mem.Arena
		mem.arena_init(&arena, buffer)
		
		context.allocator = mem.arena_allocator(&arena)
		now := time.now()
		
		for foo in foos {
			json.marshal(foo)
		}
		
		then := time.now()
		took := time.duration_milliseconds(time.diff(now, then))
		fmt.printf("json serializer (serialize):\n    time_total: %.2fms\n    foos/sec: %.1f", 
			took, 
			f64(len(foos))/(took/1000),
		)
	}
}

main :: proc() {
	packer.prepare_struct(Foo)
	basic_example()
	benchmark()
}