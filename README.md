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
byte. The harness on `main` does ~15,000 inputs per second on my machine
and runs three bias tiers in parallel so each parser branch gets real
coverage:

- 25% of inputs: `%PDF-` prefix + valid version digits, so the obj_count
  loop actually runs.
- 25% of inputs: `%PDF-` prefix only, so the version-digit check gets hit.
- 50% of inputs: pure random, as the control + BadMagic coverage.

Compared to pure random fuzzing, this is 165x more iterations reaching the
length-prefixed record loop per run, which is the part where the real bugs
live.

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
elapsed:    63.95s (15638 it/s)
ok:         0
BadMagic:   500812
BadVersion: 248924
Truncated:  250264
saved:      64
```

How to read it:

- `BadMagic` is ~50%, matching the unbiased control half plus any biased
  input too short to take the prefix. Boring inputs.
- `BadVersion` is ~25%, matching the tier that has magic but random version
  digits. Exercises the digit-range check.
- `Truncated` is ~25%, matching the tier with magic + valid version. These
  inputs run all the way into the obj_count loop, read a length, and die
  on the bounds check. These are the interesting ones for finding real
  off-by-ones.
- Up to 64 interesting inputs per run get saved to `crashes/` as
  `<wyhash>.bin`, dedup'd by content. They become the corpus for the next
  run, and any of them can be replayed individually with `zig build run`.

`ok: 0` is expected for now: random `u32` obj_count is almost always huge,
so the loop trips Truncated long before it finishes. Biasing obj_count to
small values is the next move if I want successful parses too.

Seed is fixed at `0xC0FFEE` so a run is reproducible. Iteration count and
seed are constants at the top of `src/root.zig`. Change them and rerun.

## Layout

- `src/parser.zig` - the parser under test
- `src/root.zig` - fuzz harness, stats, save-on-near-miss
- `src/main.zig` - replayer for crashes and corpus samples
- `corpus/` - hand-built seed inputs
- `crashes/` - auto-saved interesting inputs (gitignored)
