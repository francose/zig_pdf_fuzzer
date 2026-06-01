# zig_fuzzer_pdf

A research project: learn Zig by building a structure-aware fuzzer for PDF
parsers. Day one is a stub parser with deliberate out-of-bounds reads so the
harness, build system, and fuzzer feedback loop can be wired up against
something that actually crashes. After that the stub gets swapped for
`@cImport` bindings to poppler / MuPDF / pdfium and we start chasing real bugs.

## Run

```sh
# Build everything
zig build

# Replay a single input through the parser
zig build run -- corpus/seed01.bin

# Run the fuzzer
zig build test --fuzz
```

The fuzzer prints crash traces with file + line. To minimise a crash to a
single reproducible input, save the bytes the fuzzer reports and feed them
back through `zig build run --`.

## Layout

- `src/parser.zig` — stub parser. Replace with poppler/MuPDF bindings.
- `src/root.zig` — fuzz harness, public API.
- `src/main.zig` — CLI replayer for corpus + crash samples.
- `corpus/` — seed inputs.

## Learning goals

The point of this project is to exercise the parts of Zig that don't exist
in other languages:

- **allocator passing** — every function that allocates takes one
- **error unions** — parsers are almost all error paths
- **comptime** — generate input schemas at compile time
- **C ABI interop** — `@cImport("poppler.h")` and link via `build.zig`
- **packed structs** — for binary header layouts
- **the build system** — `zig build` is the entire toolchain
