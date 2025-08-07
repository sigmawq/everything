package main

import packer "../reflect_packer"
import "core:fmt"

Foo :: struct {
	a: i32 `id:"1"`,
	b: i32 `id:"2"`,
	c: f32 `id:"3"`,
	d: i32 `id:"4"`,
	e: i128 `id:"5"`,
}

main :: proc() {
	packer.prepare_struct(Foo)
	buffer := packer.buffer_make(5 * 1024 * 1024)
	ok := packer.pack(Foo{0xcdcdcd, 255, 3.14, 600, 650}, &buffer)
	if !ok {	
		panic("failed to pack")
	}
	for i := 0; i < buffer.i; i += 1 {
		v := buffer.buf[i]
		fmt.printf("0x%x, ", v)
	}
	fmt.println("\n")
	packer.buffer_reset_cursor(&buffer)
	
	unpacked := Foo{}
	if !packer.unpack(unpacked, &buffer) {
		panic("failed to unpack")
	}
	
	fmt.printf("unpacked struct: %#v\n", unpacked)
	ratio := f64(buffer.i) / f64(size_of(unpacked))
	fmt.printf("len(buffer) / sizeof(Foo): %f\n", ratio)
}