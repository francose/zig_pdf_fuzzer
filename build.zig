const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Opt-in build flag: -Dasan=true enables AddressSanitizer on the C shim
    // and the resulting binary. Slower at runtime but catches OOB reads
    // inside MuPDF/poppler that would otherwise corrupt memory silently.
    const asan = b.option(bool, "asan", "build with AddressSanitizer (default: false)") orelse false;
    const c_flags: []const []const u8 = if (asan)
        &.{ "-fsanitize=address", "-fno-omit-frame-pointer", "-g" }
    else
        &.{};
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule("zig_fuzzer_pdf", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .link_libc = true,
    });

    // MuPDF binding: compile the C shim and link against the static MuPDF
    // libs plus their runtime dependencies (the Debian package doesn't ship
    // a pkg-config file, so the link line is hand-maintained).
    mod.addCSourceFile(.{ .file = b.path("src/mupdf_shim.c"), .flags = c_flags });
    mod.addIncludePath(b.path("src"));
    const mupdf_libs = [_][]const u8{
        "mupdf", "mupdf-third", "jbig2dec",  "openjp2",
        "gumbo", "mujs",        "harfbuzz",  "freetype",
        "jpeg",  "z",           "m",         "pthread",
    };
    for (mupdf_libs) |name| {
        mod.linkSystemLibrary(name, .{});
    }
    if (asan) {
        // GCC ships libasan under its own runtime dir; Zig doesn't look there
        // by default. Linking it dynamically satisfies the __asan_init etc
        // symbols the C shim's instrumentation needs. The init-order
        // requirement ("runtime does not come first") is handled separately
        // via LD_PRELOAD on the test run steps below.
        mod.addLibraryPath(.{ .cwd_relative = "/usr/lib/gcc/x86_64-linux-gnu/11" });
        mod.linkSystemLibrary("asan", .{});
    }

    // Crash containment shim: SIGSEGV/SIGBUS/SIGABRT handler + sigsetjmp
    // wrapper so a parser crash unwinds back into the harness loop instead
    // of killing the whole process.
    mod.addCSourceFile(.{ .file = b.path("src/crash_shim.c"), .flags = c_flags });

    // poppler-glib binding: second PDF parser for differential fuzzing.
    // poppler uses GError instead of setjmp so the shim is thin, but it
    // still helps to keep glib types out of the @cImport graph.
    mod.addCSourceFile(.{ .file = b.path("src/poppler_shim.c"), .flags = c_flags });
    mod.addIncludePath(.{ .cwd_relative = "/usr/include/poppler/glib" });
    mod.addIncludePath(.{ .cwd_relative = "/usr/include/poppler" });
    mod.addIncludePath(.{ .cwd_relative = "/usr/include/glib-2.0" });
    mod.addIncludePath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu/glib-2.0/include" });
    const poppler_libs = [_][]const u8{ "poppler-glib", "glib-2.0", "gobject-2.0" };
    for (poppler_libs) |name| {
        mod.linkSystemLibrary(name, .{});
    }

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe = b.addExecutable(.{
        .name = "zig_fuzzer_pdf",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "zig_fuzzer_pdf" is the name you will use in your source code to
                // import this module (e.g. `@import("zig_fuzzer_pdf")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "zig_fuzzer_pdf", .module = mod },
            },
        }),
    });

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    if (asan) {
        // Preload libasan so its runtime initializes first. Static-link
        // would require the asan preinit object as the very first object on
        // the link line, which Zig's build system doesn't expose cleanly.
        const asan_so = "/usr/lib/x86_64-linux-gnu/libasan.so.6";
        run_mod_tests.setEnvironmentVariable("LD_PRELOAD", asan_so);
        run_exe_tests.setEnvironmentVariable("LD_PRELOAD", asan_so);
        run_cmd.setEnvironmentVariable("LD_PRELOAD", asan_so);
        // MuPDF context allocations leak by design when fz_throw aborts mid-init.
        // Tell ASan to ignore those so real bugs aren't drowned out.
        const asan_opts = "detect_leaks=0";
        run_mod_tests.setEnvironmentVariable("ASAN_OPTIONS", asan_opts);
        run_exe_tests.setEnvironmentVariable("ASAN_OPTIONS", asan_opts);
        run_cmd.setEnvironmentVariable("ASAN_OPTIONS", asan_opts);
    }

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
