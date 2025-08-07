package packer

import "core:fmt"
import "core:os"
import "core:time"
import "core:encoding/json"
import "core:mem"
import "core:reflect"
import "core:strings"
import "core:slice"
import "core:strconv"

/*
	1. Variable integer encoding
	2. Length for buffers (i.e strings, byte buffer and etc)
	3. Variable field length (1 or 2 bytes)
*/ 

OMIT_ZERO_VALUES :: #config(REFLECT_PACKER_OMIT_ZERO, false)

// Field IDs that are greater than 0 are valid. Field ID that is 0 is invalid. Field ID that is less than 0 can be a control token.
Control_Token_Or_Field_Id :: enum i8 {
    End = -1,
}

serializer_struct_mapping: map[typeid]map[Control_Token_Or_Field_Id]reflect.Struct_Field
prepare_struct :: proc(T: typeid) {
	_, already_mapped := serializer_struct_mapping[T]
	if already_mapped {
		return
	}

	typeinfo := type_info_of(T)
	if !reflect.is_struct(type_info_of(T)) {
		fmt.panicf("something different from a struct passed into prepare_struct(): ", T)
	}
	
	struct_fields := reflect.struct_fields_zipped(typeinfo.id)
	
	valid := true
	field_map: map[Control_Token_Or_Field_Id]reflect.Struct_Field
    for field in struct_fields {
		_id, id_found := reflect.struct_tag_lookup(field.tag, "id")
        if !id_found {
            continue
        }
        
        if reflect.is_struct(field.type) {
        	prepare_struct(field.type.id)
        }

        id := strconv.atoi(_id)
        if id == 0 {
            continue
        }
        
        if id > 127 || id < 0 {
        	fmt.printf("struct %v, field %v, id=%v is too big, maximum value of 127 is allowed\n", 
        		T, field.name, id)
        	valid = false
        }
        
        _, already_has_this_id := field_map[Control_Token_Or_Field_Id(id)]
        if already_has_this_id {
        	fmt.printf("struct %v, field %v (id %v) already in use\n", T, field.name, id)
        	valid = false
        }
        field_map[Control_Token_Or_Field_Id(id)] = field
	}
	
	if !valid {
		panic("struct is not invalid")
	}
	serializer_struct_mapping[T] = field_map
}

is_simple_type :: proc(typeinfo: ^reflect.Type_Info) -> bool {
	#partial switch v in reflect.type_info_core(typeinfo).variant {
		case reflect.Type_Info_Boolean, 
			reflect.Type_Info_Integer, 
			reflect.Type_Info_Float,
			reflect.Type_Info_Rune,      
			reflect.Type_Info_Complex,   	
			reflect.Type_Info_Quaternion,
			reflect.Type_Info_Enum,
			reflect.Type_Info_Bit_Set,
			reflect.Type_Info_Simd_Vector,
			reflect.Type_Info_Matrix: 
				return true
	}
	
	return false
}

pack :: proc(something: any, buffer: ^Buffer) -> bool {
	typeinfo := type_info_of(something.id)
	return _pack(typeinfo, something.data, buffer)
}

_pack :: proc(typeinfo: ^reflect.Type_Info, pointer: rawptr, buffer: ^Buffer) -> bool {
    #partial switch variant in reflect.type_info_core(typeinfo).variant {
    	case reflect.Type_Info_Integer, reflect.Type_Info_Rune, reflect.Type_Info_Float, reflect.Type_Info_Boolean, reflect.Type_Info_Enum, reflect.Type_Info_Bit_Set:
           data_size := reflect.size_of_typeid(typeinfo.id)
           buffer_write_ptr(buffer, pointer, data_size)
    	case reflect.Type_Info_Struct:
    		struct_fields := reflect.struct_fields_zipped(typeinfo.id)
		    
		    field_map, has_field_map := serializer_struct_mapping[typeinfo.id]
		    fmt.assertf(has_field_map, "No field map for type %v", typeinfo.id)
			
			for field_id, field_data in field_map {
				field_size := reflect.size_of_typeid(field_data.type.id)
				
				when OMIT_ZERO_VALUES {
					if mem.check_zero_ptr(pointer, field_size) {
						continue
					}
				}
				
				buffer_write(buffer, Control_Token_Or_Field_Id(field_id))
				pointer := rawptr(uintptr(pointer) + field_data.offset)
				if !_pack(field_data.type, pointer, buffer) {
					return false
				}
			}
			
			buffer_write(buffer, Control_Token_Or_Field_Id.End)
    	case reflect.Type_Info_Array:
    		if is_simple_type(variant.elem) {
    			element_size := variant.elem.size
    			element_count := variant.count
    			array_total_size_in_bytes := element_size * element_count
    			buffer_write_ptr(buffer, pointer, array_total_size_in_bytes)		
    		} else {
    			for i in 0..<variant.count {
	            	if !_pack(
	            		variant.elem, 
	            		rawptr(uintptr(pointer) + uintptr(i * variant.elem_size)), 
	            		buffer) {
	            			return false
	            		}
				}
    		}
    	case:
    	   fmt.panicf("Cannot serialize the following type: %v", variant)
    }
    
    return true
}

unpack :: proc(something: any, buffer: ^Buffer) -> bool {
	typeinfo := type_info_of(something.id)
	return _unpack(typeinfo, something.data, buffer)
}

_unpack :: proc(typeinfo: ^reflect.Type_Info, pointer: rawptr, buffer: ^Buffer) -> bool {
    #partial switch variant in reflect.type_info_core(typeinfo).variant {
    	case reflect.Type_Info_Integer, reflect.Type_Info_Rune, reflect.Type_Info_Float, reflect.Type_Info_Boolean, reflect.Type_Info_Enum, reflect.Type_Info_Bit_Set:
			data_size := reflect.size_of_typeid(typeinfo.id)
			if !buffer_read_ptr(buffer, pointer, data_size) {
				fmt.println("failed to read primitive type")	
				return false
			}
    	case reflect.Type_Info_Struct:
    		struct_fields := reflect.struct_fields_zipped(typeinfo.id)
    		
		    field_map, has_field_map := serializer_struct_mapping[typeinfo.id]
		    fmt.assertf(has_field_map, "No field map for type %v", typeinfo.id)
			
			for {
				id: Control_Token_Or_Field_Id
				current_offset := buffer.i
				if !buffer_read(buffer, &id) {
					return false
				}
				
				if id == .End {
					break
				}
				
				field, has_field := field_map[id]
				if !has_field {
					fmt.printf("(offset %v) failed to unpack: encountered a bad field with id=%v\n", current_offset, i16(id))
					return false
				}
				
				if !_unpack(field.type, rawptr(uintptr(pointer) + field.offset), buffer) {
					fmt.println("failed to unpack struct field")
					return false
				}
			}
    	case reflect.Type_Info_Array:
    		if is_simple_type(variant.elem) {
    			element_size := variant.elem.size
    			element_count := variant.count
    			array_total_size_in_bytes := element_size * element_count
    			buffer_read_ptr(buffer, pointer, array_total_size_in_bytes)
    		} else {
    			for i in 0..<variant.count {
	            	_unpack(
	            		variant.elem, 
	            		rawptr(uintptr(pointer) + uintptr(i * variant.elem_size)), 
	            		buffer)
				}
    		}
			
    	case:
    	   fmt.println(variant)
    	   panic("I don't know how to deserialize this type!")
    }
    
    return true
}

Buffer :: struct {
    buf: [dynamic]u8,
    i: int,
}

buffer_make :: proc(size: int, allocator := context.allocator) -> Buffer {
	return Buffer {
		buf = make([dynamic]u8, size, allocator)
	}
}

buffer_delete :: proc(buffer: ^Buffer) {
	delete(buffer.buf)
}

buffer_reset_cursor :: proc(buffer: ^Buffer) {
	buffer.i = 0
}

buffer_grow :: proc(buffer: ^Buffer) {
	new_size := len(buffer.buf) * 2
	if new_size < 16 {	
		new_size = 16
	}
    resize(&buffer.buf, new_size)
}

buffer_write :: proc(buffer: ^Buffer, thing: $T) {
    thing := thing
    if buffer.i + size_of(T) > len(buffer.buf) {
    	buffer_grow(buffer)
    }

    mem.copy(&buffer.buf[buffer.i], &thing, size_of(thing))
    buffer.i += size_of(thing)
}

buffer_allocate :: proc(buffer: ^Buffer, $T: typeid) -> ^T {
    if buffer.i + size_of(T) > len(buffer.buf) {
        panic("Buffer size exceeded")
    }

	ptr := &buffer.buf[buffer.i]
    buffer.i += size_of(T)
    
    return transmute(^T)ptr
}

buffer_write_ptr :: proc(buffer: ^Buffer, data_pointer: rawptr, data_size: int) {
    if buffer.i + data_size > len(buffer.buf) {
        panic("Buffer size exceeded")
    }

    mem.copy(&buffer.buf[buffer.i], data_pointer, data_size)
    buffer.i += data_size
}

buffer_read :: proc(buffer: ^Buffer, into: ^$T) -> bool {
	if buffer.i + size_of(T) > len(buffer.buf) {
		return false
	}
	
	data := transmute(^T)&buffer.buf[buffer.i]
	into^ = data^
	buffer.i += size_of(T)
	
	return true
}

buffer_read_ptr :: proc(buffer: ^Buffer, data_pointer: rawptr, data_size: int) -> bool {
	if buffer.i + data_size > len(buffer.buf) {
		return false
	}
	
	mem.copy(data_pointer, &buffer.buf[buffer.i], data_size)
    buffer.i += data_size
	return true
}