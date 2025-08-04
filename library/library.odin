package library

import "core:fmt"
import "base:runtime"

@(export)
some_function :: proc "c" () -> int {
	return 1 + 1
}
