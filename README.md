# zig_pdf_fuzzer

## Why

I wanted to learn Zig and get deeper into parser security at the same time.
Reading about a CVE in MuPDF doesn't teach me how the bug got there. Writing
a parser, breaking it, and watching a million random inputs hit it does.

Zig is the right language for the job because it makes you handle bounds and
bytes yourself. No slice safety net at compile time, no garbage collector.
Same shape of code as what ships in real document parsers, which is exactly
the code I want to understand.

## What I'm testing

The PDF header, two targets in the same repo:

- `src/parser.zig` is a small stub I wrote by hand. It checks the `%PDF-`
  magic, two version digits, an object count, and a loop of length-prefixed
  object records. Tiny surface, easy to mess up, perfect for practicing the
  bug class.
- `src/mupdf.zig` is the @cImport binding into real MuPDF via a small C
  shim (`src/mupdf_shim.c`). The shim wraps MuPDF's setjmp/longjmp-based
  `fz_try` / `fz_catch` error path behind a plain C function the Zig side
  can call without worrying about non-local control flow.

The fuzz harness currently exercises the stub. Wiring the harness to send
bytes at MuPDF is the next step and needs AddressSanitizer + crash
catching, because real C parsers segfault instead of returning errors.

Stack:

- Zig 0.15.1, no external runtime deps
- WSL2 on Linux as the host
- MuPDF 1.19 from `libmupdf-dev` (static libs at `/usr/lib/libmupdf.a` +
  `/usr/lib/libmupdf-third.a`, no pkg-config file so the link line is
  hand-maintained in `build.zig`).
- No external fuzzing engine. Zig's own `--fuzz` mode is broken in 0.15.1
  and 0.16, so the loop is hand-rolled in `src/root.zig`.

## The problem I'm trying to solve

Most parser bugs come from one of two mistakes: trusting a length field, or
skipping a bounds check on a slice. PDF readers eat the most CVEs in document
handling because even the header has magic comparison, version digit checks,
and a loop over length-prefixed records. Every one of those is a place an
off-by-one or an unchecked read can become RCE.

I want a harness that exercises those checks fast enough to actually catch
bugs, and that doesn't waste 99% of its inputs failing at the very first
byte. The harness on `main` does ~15,000 inputs per second on my machine
and runs three bias tiers in parallel so each parser branch gets real
coverage:

- 25% of inputs: `%PDF-` prefix + valid version digits + small obj_count
  in [0, 16), so the loop body runs and sometimes a parse fully succeeds.
- 25% of inputs: `%PDF-` prefix only, so the version-digit check gets hit.
- 50% of inputs: pure random, as the control + BadMagic coverage.

Compared to pure random fuzzing this is ~165x more iterations reaching the
length-prefixed record loop, which is the part where the real bugs live.

## How I run the analysis

```sh
# one million random inputs through the parser
zig build test

# replay a saved interesting input
zig build run -- crashes/<hash>.bin
```

A run prints a stats block at the end:

```
--- fuzz stats ---
iterations: 1000000
elapsed:    62.72s (15945 it/s)
ok:         15951
BadMagic:   500998
BadVersion: 248992
Truncated:  234059
saved:      64
```

How to read it:

- `ok` is ~16k successful parses, all from tier 0 inputs where obj_count
  came out as 0 so the loop body never had to run. That's the ~1-in-16
  hit rate from the [0, 16) bias on obj_count.
- `BadMagic` is ~50%, matching the unbiased control half plus any biased
  input too short to take the prefix. Boring inputs.
- `BadVersion` is ~25%, matching the tier that has magic but random version
  digits. Exercises the digit-range check.
- `Truncated` is ~23%, matching the tier with magic + valid version + small
  obj_count that ran into the loop, read a length field, and died on the
  bounds check. The interesting ones for finding real off-by-ones.
- Up to 64 interesting inputs per run get saved to `crashes/` as
  `<wyhash>.bin`, dedup'd by content. They become the corpus for the next
  run, and any of them can be replayed individually with `zig build run`.

Seed is fixed at `0xC0FFEE` so a run is reproducible. Iteration count and
seed are constants at the top of `src/root.zig`. Change them and rerun.

## Layout

- `src/parser.zig` - the hand-rolled stub parser (the fuzz target today)
- `src/root.zig` - fuzz harness, stats, save-on-near-miss
- `src/main.zig` - replayer for crashes and corpus samples
- `src/mupdf_shim.h` / `src/mupdf_shim.c` - C shim wrapping MuPDF's
  `fz_try` / `fz_catch` behind a plain function the Zig side can call
- `src/mupdf.zig` - the @cImport binding for the shim
- `corpus/` - hand-built seed inputs
- `crashes/` - auto-saved interesting inputs (gitignored)
