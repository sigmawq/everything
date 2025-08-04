package library

foreign import lib "../library.lib"

foreign lib {
	some_function :: proc "c" () -> int ---
}
