/**
 * Development server using Bun.
 * 
 * This server serves static files from the current directory.
 * Crucially, it injects Cross-Origin-Opener-Policy (COOP) and 
 * Cross-Origin-Embedder-Policy (COEP) headers into every response.
 * 
 * These headers are required by modern web browsers to enable 
 * Cross-Origin Isolation, which in turn unlocks the use of `SharedArrayBuffer`.
 * `SharedArrayBuffer` is necessary for WebAssembly threads to function correctly.
 * alternative: see https://github.com/gzuidhof/coi-serviceworker
 */
import { serve } from "bun";
import { join } from "path";

const PORT = Bun.env.PORT || 3000;

Bun.serve({
  port: PORT,
  async fetch(req) {
    const url = new URL(req.url);
    let pathname = url.pathname;
    
    // Default to index.html for root path
    if (pathname === "/") {
      pathname = "/index.html";
    }

    // Construct the absolute path
    const absolutePath = join(process.cwd(), pathname);
    const file = Bun.file(absolutePath);

    // Check if file exists
    if (await file.exists()) {
      const response = new Response(file);
      
      // These headers are required for SharedArrayBuffer (WASI Threads) to work
      response.headers.set("Cross-Origin-Opener-Policy", "same-origin");
      response.headers.set("Cross-Origin-Embedder-Policy", "require-corp");
      
      return response;
    }

    return new Response("Not found", { status: 404 });
  },
});

console.log(`Serving at http://localhost:${PORT}`);
console.log("Cross-Origin Isolation is enabled.");
