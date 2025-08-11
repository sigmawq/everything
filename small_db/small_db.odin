package main

import "core:fmt"

MAX_ENTITIES :: 8192

Context :: struct {
	entities: [MAX_ENTITIES]Entity_Header,
}

Entity_Header :: struct #packed {
	id: i16,
}

// Block :: struct ($T, $Count) {
// 	elements: [Count]T,
// 	first_free: i16,
// }

initialize :: proc(path: string, entity_ids: []i16) {
	for entity_id in entity_ids {
		if entity_id > MAX_ENTITIES || entity_id < 0 {
			fmt.panicf("initialize(): invalid range to entity_id %v", entity_id)
		}
		
	}
}