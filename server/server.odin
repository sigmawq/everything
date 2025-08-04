package main

import "core:fmt"
import "core:mem"
import "core:log"
import "core:net"
import http "dependencies:odin-http"

get_wasm :: proc(request: ^http.Request, response: ^http.Response) {
	http.respond_file(response, "wasm/index.wasm")
}

get_index :: proc(request: ^http.Request, response: ^http.Response) {
	http.respond_file(response, "wasm/index.html")
}

get_index_js :: proc(request: ^http.Request, response: ^http.Response) {
	http.respond_file(response, "wasm/index.js")
}

get_odin_js :: proc(request: ^http.Request, response: ^http.Response) {
	http.respond_file(response, "wasm/odin.js")
}

main :: proc() {
	context.logger = log.create_console_logger(.Info)
	
	s: http.Server
	// Register a graceful shutdown when the program receives a SIGINT signal.
	http.server_shutdown_on_interrupt(&s)
	
	// Set up routing
	router: http.Router
	http.router_init(&router)
	http.route_get(&router, "/", http.handler(get_index))
	http.route_get(&router, "/index.js", http.handler(get_index_js))
	http.route_get(&router, "/odin.js", http.handler(get_odin_js))
	http.route_get(&router, "/index.wasm", http.handler(get_wasm))
	
	routed := http.router_handler(&router)
	
	log.infof("Begin listen on 7000")
	err := http.listen_and_serve(&s, routed, net.Endpoint{
		address = net.IP4_Loopback, 
		port = 7000,
	}, http.Server_Opts {
		thread_count = 8,
		limit_request_line = 8000,
		limit_headers = 8000,
		auto_expect_continue = true,
	})
	if err != nil {
		log.errorf("Failed to listen!\nError:%v", err)
	}
}