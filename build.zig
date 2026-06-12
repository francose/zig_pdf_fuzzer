const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // -Dasan=true wires AddressSanitizer into the C shims. slower but
    // catches OOB reads inside mupdf/poppler that wouldnt segfault hard.
    const asan = b.option(bool, "asan", "build with AddressSanitizer (default: false)") orelse false;
    const c_flags: []const []const u8 = if (asan)
        &.{ "-fsanitize=address", "-fno-omit-frame-pointer", "-g" }
    else
        &.{};

    const mod = b.addModule("zig_fuzzer_pdf", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .link_libc = true,
    });

    // mupdf static libs live in /usr/lib, no pkg-config file, so the link
    // line is hand maintained.
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
        // gcc ships libasan under its own runtime dir, zig doesnt look there.
        // linking satisfies the __asan_init symbols. init order is fixed by
        // the LD_PRELOAD on the test run steps below.
        mod.addLibraryPath(.{ .cwd_relative = "/usr/lib/gcc/x86_64-linux-gnu/11" });
        mod.linkSystemLibrary("asan", .{});
    }

    // SIGSEGV/SIGBUS/SIGABRT handler + sigsetjmp wrapper.
    mod.addCSourceFile(.{ .file = b.path("src/crash_shim.c"), .flags = c_flags });

    // poppler-glib for the differential.
    mod.addCSourceFile(.{ .file = b.path("src/poppler_shim.c"), .flags = c_flags });
    mod.addIncludePath(.{ .cwd_relative = "/usr/include/poppler/glib" });
    mod.addIncludePath(.{ .cwd_relative = "/usr/include/poppler" });
    mod.addIncludePath(.{ .cwd_relative = "/usr/include/glib-2.0" });
    mod.addIncludePath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu/glib-2.0/include" });
    const poppler_libs = [_][]const u8{ "poppler-glib", "glib-2.0", "gobject-2.0" };
    for (poppler_libs) |name| {
        mod.linkSystemLibrary(name, .{});
    }

    const exe = b.addExecutable(.{
        .name = "zig_fuzzer_pdf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_fuzzer_pdf", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    if (asan) {
        // preload libasan so it inits first. static link would need the
        // preinit object as object #1 on the link line and zig doesnt
        // expose that cleanly.
        const asan_so = "/usr/lib/x86_64-linux-gnu/libasan.so.6";
        run_mod_tests.setEnvironmentVariable("LD_PRELOAD", asan_so);
        run_exe_tests.setEnvironmentVariable("LD_PRELOAD", asan_so);
        run_cmd.setEnvironmentVariable("LD_PRELOAD", asan_so);
        // mupdf ctx allocs leak on fz_throw mid-init by design. ignore
        // those so real bugs arent drowned.
        const asan_opts = "detect_leaks=0";
        run_mod_tests.setEnvironmentVariable("ASAN_OPTIONS", asan_opts);
        run_exe_tests.setEnvironmentVariable("ASAN_OPTIONS", asan_opts);
        run_cmd.setEnvironmentVariable("ASAN_OPTIONS", asan_opts);
    }

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
