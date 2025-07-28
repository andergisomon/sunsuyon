const std = @import("std");
const iox2_root = "/home/ander/SIIP_project/iiot_gateway/sunsuyon/tgbot/c_deps/iceoryx2/target/ffi/install";

pub fn build(b: *std.Build) void {

    const target = b.resolveTargetQuery(.{
            .cpu_arch = .aarch64,
            .os_tag = .linux,
            .abi = .gnu,
    });

    const optimize = b.standardOptimizeOption(.{});

    // Add zigtgshka dependency
    const telegram_dependency = b.dependency("zigtgshka", .{
        .target = target,
        .optimize = optimize,
    });

    // Create your executable
    const exe = b.addExecutable(.{
        .name = "gipop_tgbot",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.addIncludePath(
        b.path("../tgbot/c_deps/iceoryx2/target/ffi/install/include/iceoryx2/v0.6.1/iox2/")
    );
    // This line exe.linkSystemLibrary("gcc_s"); is needed for Rust unwind
    exe.linkSystemLibrary("gcc_s"); // Link to target shared glibc
    exe.addObjectFile(b.path("../tgbot/c_deps/iceoryx2/target/ffi/install/lib/libiceoryx2_ffi.a"));

    // Import the telegram module
    exe.root_module.addImport("telegram", telegram_dependency.module("telegram"));
    exe.linkLibC(); // Required for HTTP client
    
    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run bot");
    run_step.dependOn(&run_cmd.step);
    b.installArtifact(exe);
}