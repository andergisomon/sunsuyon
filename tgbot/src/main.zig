// Disclaimer: Spaghetti code🍝
// Refer to _main.zig for a blocking example that's easier to follow

const iox2_root = "/home/ander/SIIP_project/iiot_gateway/sunsuyon/tgbot/c_deps/iceoryx2/target/ffi/install";
const tgbot_root = "/home/ander/SIIP_project/iiot_gateway/sunsuyon/tgbot/src";

const std = @import("std");
const telegram = @import("telegram");
const dotenv = @import("dotenv.zig");

const iox2 = @cImport({
    @cInclude(iox2_root ++ "/include/iceoryx2/v0.6.1/iox2/iceoryx2.h");
});

const AppStateValues = struct {
    auth_ok: ?bool,
    start: ?bool,
    offset: ?i32,
    chat_id: ?i64,
    prev_msg: ?ErrCodes,
    msg: ?TgbotAlertFromPlc,
};

const AppState = struct {
    vals: AppStateValues,
    mutex: std.Thread.Mutex,

    const Self = @This();

    fn new() Self {
        return .{ .vals = .{ .auth_ok = false, .start = false, .offset = -1, .chat_id = -1, .prev_msg = ErrCodes.Uninit, .msg = TgbotAlertFromPlc{ .err_code = 255} }, .mutex = std.Thread.Mutex{} };
    }

    fn set(self: *Self, param: AppStateValues) void {
        if (self.mutex.tryLock()) {
            defer self.mutex.unlock();

            if (param.auth_ok != null) {
                self.vals.auth_ok = param.auth_ok;
            }
            if (param.start != null) {
                self.vals.start = param.start;
            }
            if (param.offset != null) {
                self.vals.offset = param.offset;
            }
            if (param.chat_id != null) {
                self.vals.chat_id = param.chat_id;
            }
            if (param.prev_msg != null) {
                self.vals.prev_msg = param.prev_msg;
            }
            if (param.msg != null) {
                self.vals.msg = param.msg;
            }
        }
        else {
            std.log.debug("set tryLock failed", .{});
        }
    }

    fn get(self: *Self) ?AppStateValues {
        if (self.mutex.tryLock()) {
            defer self.mutex.unlock();
            return self.vals;
        }
        else {
            return null;
        }
    }
};

const TgbotAlertFromPlc = extern struct { err_code: u32 };

const ErrCodes = enum(u32) {
    Uninit = 255,
    OllKorrect = 0,
    Part1ReportDown = 1,
    Part2ReportDown = 2,
    Part1Part2ReportDown = 3,
};

pub fn main() !void {
    // create new node
    const node_builder_handle: iox2.iox2_node_builder_h = iox2.iox2_node_builder_new(null);
    var node_handle: iox2.iox2_node_h = null;
    if (iox2.iox2_node_builder_create(node_builder_handle, null, iox2.iox2_service_type_e_IPC, &node_handle) != iox2.IOX2_OK) {
        std.log.err("Could not create node!\n", .{});
    }

    // create service name
    const service_name_value = "TgbotFromPlc";
    var service_name: iox2.iox2_service_name_h = null;
    if (iox2.iox2_service_name_new(null, service_name_value, service_name_value.len, &service_name) != iox2.IOX2_OK) {
        std.log.err("Unable to create service name!\n", .{});
        iox2.iox2_node_drop(node_handle);
    }

    // create service builder
    const service_name_ptr: iox2.iox2_service_name_ptr = iox2.iox2_cast_service_name_ptr(service_name);
    const service_builder: iox2.iox2_service_builder_h = iox2.iox2_node_service_builder(&node_handle, null, service_name_ptr);
    const service_builder_pub_sub: iox2.iox2_service_builder_pub_sub_h = iox2.iox2_service_builder_pub_sub(service_builder);

    // set pub sub payload type
    const payload_type_name = "TgbotAlertFromPlc";
    if (iox2.iox2_service_builder_pub_sub_set_payload_type_details(&service_builder_pub_sub, iox2.iox2_type_variant_e_FIXED_SIZE, payload_type_name, payload_type_name.len, @sizeOf(TgbotAlertFromPlc), @alignOf(TgbotAlertFromPlc)) != iox2.IOX2_OK) {
        std.log.err("Unable to set type details\n", .{});
        iox2.iox2_service_name_drop(service_name);
    }

    // create service
    var service: iox2.iox2_port_factory_pub_sub_h = null;
    if (iox2.iox2_service_builder_pub_sub_open_or_create(service_builder_pub_sub, null, &service) != iox2.IOX2_OK) {
        std.log.err("Unable to create service!\n", .{});
        iox2.iox2_service_name_drop(service_name);
    }

    // create subscriber
    const subscriber_builder: iox2.iox2_port_factory_subscriber_builder_h =
        iox2.iox2_port_factory_pub_sub_subscriber_builder(&service, null);
    var subscriber: iox2.iox2_subscriber_h = null;
    if (iox2.iox2_port_factory_subscriber_builder_create(subscriber_builder, null, &subscriber) != iox2.IOX2_OK) {
        std.log.err("Unable to create subscriber!\n", .{});
        iox2.iox2_service_name_drop(service_name);
    }

    var dbga = std.heap.DebugAllocator(.{ .safety = true }){};
    defer _ = dbga.deinit();
    const allocator = dbga.allocator();
    const dotenv_alloc = dbga.allocator();
    const app_state_allocator = dbga.allocator();

    const app_state_ptr = try app_state_allocator.create(AppState);
    defer app_state_allocator.destroy(app_state_ptr);

    app_state_ptr.* = AppState.new();

    var env = try dotenv.init(dotenv_alloc, ".env");
    defer env.deinit();

    const panalib = env.get("PASSPHRASE") orelse "Cannot find PASSPHRASE env var";
    const tgbot_token = env.get("TGBOT_TOKEN") orelse "Cannot find TGBOT_TOKEN env var";

    var client = try telegram.HTTPClient.init(allocator);
    defer client.deinit();

    var bot = try telegram.Bot.init(allocator, tgbot_token, &client);
    defer bot.deinit();

    var me = try telegram.methods.getMe(&bot);
    defer me.deinit(allocator);

    std.debug.print("🚀 Bot @{s} is online!\n", .{me.username orelse me.first_name});

    var offset: i32 = 0;
    var pass_fail_count: u8 = 0;
    var auth_ok: bool = false;

    while (pass_fail_count <= 3 and !auth_ok) {
        const updates = try telegram.methods.getUpdates(&bot, offset, 3, 30);
        defer {
            for (updates) |*update| update.deinit(allocator);
            allocator.free(updates);
        }

        for (updates) |update| {
            offset = update.update_id + 1;
            app_state_ptr.*.set(.{
                    .auth_ok = null,
                    .chat_id = null,
                    .offset = offset,
                    .prev_msg = null,
                    .start = null,
                    .msg = null
                }
            );

            if (update.message) |message| {
                if (message.text) |text| {
                    if (pass_fail_count == 5) {
                        var reply = try telegram.methods.sendMessage(&bot, message.chat.id, "Used up all 3 attempts to authenticate.");
                        defer reply.deinit(allocator);
                        std.log.err("Client failed to identify thrice", .{});
                    }

                    const pass = std.mem.eql(u8, text, panalib);
                    if (pass) {
                        auth_ok = true; // break loop
                        app_state_ptr.*.set(.{
                                .auth_ok = true,
                                .chat_id = null,
                                .offset = null,
                                .prev_msg = null,
                                .start = null,
                                .msg = null
                            }
                        );
                        std.log.info("Client identified successfully.", .{});
                        var reply = try telegram.methods.sendMessage(&bot, message.chat.id, "Identification successful. Send /start to trigger the update. To log out, send /bye");
                        defer reply.deinit(allocator);
                    } else {
                        var reply = try telegram.methods.sendMessage(&bot, message.chat.id, "Identity not recognized.");
                        defer reply.deinit(allocator);
                        pass_fail_count = pass_fail_count + 1;
                        std.log.info("Client failed to identify {} times", .{pass_fail_count});
                    }
                }
            }
        }
    }

    const tg_thread = try std.Thread.spawn(.{}, tg_worker, .{app_state_ptr, &bot, allocator});
    tg_thread.detach();

    while (true) {
        try ipc_worker(app_state_ptr, &subscriber, service_name);
        std.Thread.sleep(500_000_000);
    }
}

fn ipc_worker(app_state: *AppState, subscriber: *iox2.iox2_subscriber_h, service_name: iox2.iox2_service_name_h) !void {
    const state = app_state.get();
    var auth_ok: ?bool = null;

    if (state != null) {
        auth_ok = state.?.auth_ok orelse false;
    }

    if (auth_ok.?) {
        // receive sample
        var sample: iox2.iox2_sample_h = null;
        if (iox2.iox2_subscriber_receive(subscriber, null, &sample) != iox2.IOX2_OK) {
            std.log.err("Failed to receive sample\n", .{});
            iox2.iox2_service_name_drop(service_name);
        }

        if (sample != null) {
            var payload: ?*TgbotAlertFromPlc = null;
            const linopot: *?*const anyopaque = @ptrCast(&payload);
            iox2.iox2_sample_payload(&sample, linopot, null);

            if (payload) |msg| {
                std.log.info("received: {}", .{msg.err_code});
                app_state.set(.{
                        .auth_ok = null,
                        .chat_id = null,
                        .offset = null,
                        .prev_msg = null,
                        .start = null,
                        .msg = msg.*
                    }
                );
            }

            iox2.iox2_sample_drop(sample);
        }
    }
}

fn tg_worker(app_state: *AppState, bot: *telegram.Bot, allocator: std.mem.Allocator) !void {
    var auth_ok: ?bool = null;
    var start: ?bool = null;
    var new_offset: ?i32 = null;
    var chat_id: ?i64 = null;
    var prev_msg: ?ErrCodes = null;
    var msg: ?TgbotAlertFromPlc = null;

    while (true) {
        const state = app_state.get();
        if (state != null) {
            auth_ok = state.?.auth_ok;
            start = state.?.start orelse false;
            new_offset = state.?.offset;
            chat_id = state.?.chat_id;
            prev_msg = state.?.prev_msg;
            msg = state.?.msg;
        }

        const nullcheck = auth_ok != null and start != null and new_offset != null and chat_id != null and prev_msg != null and msg != null;
        if (nullcheck) {
            if (auth_ok.? and state != null) {
                const updates = try telegram.methods.getUpdates(bot, new_offset.?, 3, 0);
                defer {
                    for (updates) |*update| update.deinit(allocator);
                    allocator.free(updates);
                }

                for (updates) |update| {
                    const ofst = update.update_id + 1;
                    app_state.set(.{
                            .auth_ok = null,
                            .chat_id = chat_id,
                            .msg = null,
                            .offset = ofst,
                            .prev_msg = null,
                            .start = null
                        }
                    );

                    if (update.message) |message| {
                        chat_id = message.chat.id;
                        app_state.set(.{
                                .auth_ok = null,
                                .chat_id = chat_id,
                                .msg = null,
                                .offset = null,
                                .prev_msg = null,
                                .start = null
                            }
                        );

                        if (message.text) |text| {
                            if (std.mem.eql(u8, text, "/bye")) {
                                auth_ok = false;
                                app_state.set(.{
                                        .auth_ok = false,
                                        .chat_id = null,
                                        .msg = null,
                                        .offset = null,
                                        .prev_msg = null,
                                        .start = null
                                    }
                                );
                            }
                            if (std.mem.eql(u8, text, "/start")) {
                                start = true;
                                app_state.set(.{
                                        .auth_ok = null,
                                        .chat_id = null,
                                        .msg = null,
                                        .offset = null,
                                        .prev_msg = null,
                                        .start = true
                                    }
                                );
                            }
                        }
                    }
                }

                if (start.?) {
                    if (msg.?.err_code == @intFromEnum(ErrCodes.Uninit)) {
                        std.log.err("PLC logic error, ErrCode is uninitialized", .{});
                    }

                    if (msg.?.err_code == @intFromEnum(ErrCodes.OllKorrect) and msg.?.err_code != @intFromEnum(prev_msg.?)) {
                        var reply = try telegram.methods.sendMessage(bot, chat_id.?, "\xF0\x9F\x98\x8C Part 1 and Part 2 Report OK \xE2\x9C\x85");
                        prev_msg = @enumFromInt(msg.?.err_code);
                        defer reply.deinit(allocator);
                    }

                    if (msg.?.err_code == @intFromEnum(ErrCodes.Part1Part2ReportDown) and msg.?.err_code != @intFromEnum(prev_msg.?)) {
                        prev_msg = @enumFromInt(msg.?.err_code);
                        var reply = try telegram.methods.sendMessage(bot, chat_id.?, "\xF0\x9F\x98\xA8 Part 1 and Part 2 Report NOK\xF0\x9F\x9A\xA8 \n We need you at the floor now! \xF0\x9F\x98\x93");
                        defer reply.deinit(allocator);
                    }

                    if (msg.?.err_code == @intFromEnum(ErrCodes.Part2ReportDown) and msg.?.err_code != @intFromEnum(prev_msg.?)) {
                        prev_msg = @enumFromInt(msg.?.err_code);
                        var reply = try telegram.methods.sendMessage(bot, chat_id.?, "\xF0\x9F\x98\xA8 Part 2 Report NOK\xF0\x9F\x9A\xA8 \n We need you at the floor now! \xF0\x9F\x98\x93");
                        defer reply.deinit(allocator);
                    }

                    if (msg.?.err_code == @intFromEnum(ErrCodes.Part1ReportDown) and msg.?.err_code != @intFromEnum(prev_msg.?)) {
                        prev_msg = @enumFromInt(msg.?.err_code);
                        var reply = try telegram.methods.sendMessage(bot, chat_id.?, "\xF0\x9F\x98\xA8 Part 1 Report NOK\xF0\x9F\x9A\xA8 \n We need you at the floor now! \xF0\x9F\x98\x93");
                        defer reply.deinit(allocator);
                    }

                    app_state.set(.{
                            .auth_ok = null,
                            .chat_id = null,
                            .msg = null,
                            .offset = null,
                            .prev_msg = prev_msg,
                            .start = null
                        }
                    );
                }
            }

            if (!auth_ok.?) {
                var reply = try telegram.methods.sendMessage(bot, chat_id.?, "\xF0\x9F\x91\x8B Ba-bye");
                defer reply.deinit(allocator);
                std.log.info("User exited. Hit Ctrl+C to end program.", .{});
                break;
            }
        }
        else {
            try std.Thread.yield();
        }
    }
}
