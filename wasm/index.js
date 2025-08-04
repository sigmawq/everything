"use strict";

(async () => {
	// Create our memory interface. While we don't specify any specific memory
	// configuration, we'll use the interface to reference our exported Odin function.
	const memInterface = new odin.WasmMemoryInterface();
	await odin.runWasm("index.wasm", null, null, memInterface);
	// Now after the WASM module is loaded, we can access our exported functions.
	const exports = memInterface.exports;

	const button = document.getElementById("add");
	const number1 = document.getElementById("number1");
	const number2 = document.getElementById("number2");
	const result = document.getElementById("result");

	let i = 1;
	button.addEventListener("click", () => {
		// Call our exported function and show the result!
		exports.tick();
		i++;
		result.innerText = i;
	});
})();