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

Three parsers in one repo, designed to be compared against each other:

- `src/parser.zig` is a small stub I wrote by hand. Magic check, two
  version digits, obj_count, length-prefixed record loop. Tiny surface,
  the harness exercises this at 16k inputs/sec.
- `src/mupdf.zig` is the @cImport binding into real MuPDF, via a C shim
  (`src/mupdf_shim.c`) that wraps MuPDF's setjmp/longjmp-based `fz_try` /
  `fz_catch` error path behind a plain C function.
- `src/poppler.zig` is the @cImport binding into poppler-glib via
  `src/poppler_shim.c`. Poppler uses GError so no setjmp wrapping needed,
  but the shim keeps glib types out of the Zig @cImport graph.

The MuPDF and poppler bindings feed a differential test: same input through
both parsers, save anything either parser crashes on or where the two
disagree on accept/reject.

Stack:

- Zig 0.15.1, no external runtime deps
- WSL2 on Linux as the host
- MuPDF 1.19 from `libmupdf-dev` (static libs in `/usr/lib`, no
  pkg-config, link line hand-maintained in `build.zig`).
- poppler-glib 22.02 from `libpoppler-glib-dev`.
- AddressSanitizer is optional via `-Dasan=true` (LD_PRELOAD'd at test
  time; the build wires both link and runtime).
- Crash containment via sigsetjmp/siglongjmp in `src/crash_shim.c`. A
  SIGSEGV / SIGBUS / SIGABRT inside a parser call unwinds back into the
  harness loop instead of killing the process.
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
# all five tests: stub fuzz, mupdf+poppler sanity, crash containment proof,
# and the differential mupdf-vs-poppler harness
zig build test

# same tests but with AddressSanitizer wired into the C side
zig build test -Dasan=true

# replay a saved interesting input through the stub parser
zig build run -- crashes/<hash>.bin
```

A run prints two stats blocks: the stub fuzz at the bottom, the
differential summary above it.

Stub fuzz:

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

Differential summary:

```
--- differential stats ---
iterations:      500
both accepted:   0
both rejected:   500
disagreed:       0
mupdf crashes:   0
poppler crashes: 0
context errors:  0
```

500/500 both rejected is expected for tiny random `%PDF-`-prefixed buffers:
neither parser will accept anything without a valid xref table. Real
disagreements need either grammar-aware input generation or corpus-based
mutation, which is the natural next step. Any input that one parser
accepts and the other rejects, or that crashes either parser under signal
protection, gets saved to `disagreements/<wyhash>.bin` for triage.

## Layout

- `src/parser.zig` - the hand-rolled stub parser
- `src/root.zig` - fuzz + differential harnesses, stats, save-on-disagreement
- `src/main.zig` - replayer for crashes and corpus samples
- `src/mupdf_shim.h` / `src/mupdf_shim.c` - MuPDF C shim (`fz_try`/`fz_catch`)
- `src/mupdf.zig` - MuPDF @cImport binding
- `src/poppler_shim.h` / `src/poppler_shim.c` - poppler-glib C shim
- `src/poppler.zig` - poppler @cImport binding
- `src/crash_shim.h` / `src/crash_shim.c` - SIGSEGV/SIGBUS/SIGABRT handler
  + sigsetjmp wrapper for crash containment
- `src/crash_containment.zig` - Zig-side protected-call wrappers
- `corpus/` - hand-built seed inputs
- `crashes/` - auto-saved near-miss inputs from the stub fuzz (gitignored)
- `disagreements/` - inputs the differential harness flagged (gitignored)
