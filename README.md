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

The PDF header. `src/parser.zig` is a small stub I wrote by hand. It checks
the `%PDF-` magic, two version digits, an object count, and a loop of
length-prefixed object records. Tiny surface, easy to mess up, perfect for
practicing the bug class.

Next step is to swap the stub for `@cImport` bindings into MuPDF or poppler
and aim the same harness at the real parser. The harness API doesn't change,
only the function it calls.

Stack:

- Zig 0.15.1, no external runtime deps
- WSL2 on Linux as the host
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
byte. The harness on `main` does ~15,000 inputs per second on my machine and
biases half the inputs to get past the magic check so deeper code paths
actually get hit.

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
elapsed:    64.36s (15537 it/s)
ok:         0
BadMagic:   500597
BadVersion: 497884
Truncated:  1519
saved:      64
```

How to read it:

- `BadMagic` is the unbiased half plus any biased input that was too short
  to take the `%PDF-` prefix. Boring inputs.
- `BadVersion` and `Truncated` are biased inputs that got past the magic
  check and then died deeper. Interesting inputs.
- Up to 64 interesting inputs per run get saved to `crashes/` as
  `<wyhash>.bin`, dedup'd by content. They become the corpus for the next
  run, and any of them can be replayed individually with `zig build run`.

Seed is fixed at `0xC0FFEE` so a run is reproducible. Iteration count and
seed are constants at the top of `src/root.zig`. Change them and rerun.

## Layout

- `src/parser.zig` - the parser under test
- `src/root.zig` - fuzz harness, stats, save-on-near-miss
- `src/main.zig` - replayer for crashes and corpus samples
- `corpus/` - hand-built seed inputs
- `crashes/` - auto-saved interesting inputs (gitignored)
