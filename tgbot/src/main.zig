const iox2_root = "/home/ander/SIIP_project/iiot_gateway/sunsuyon/tgbot/c_deps/iceoryx2/target/ffi/install";
const tgbot_root = "/home/ander/SIIP_project/iiot_gateway/sunsuyon/tgbot/src";

const std = @import("std");
const telegram = @import("telegram");
const dotenv = @import("dotenv.zig");

const iox2 = @cImport({
    @cInclude(iox2_root ++ "/include/iceoryx2/v0.6.1/iox2/iceoryx2.h");
});

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
        const updates = try telegram.methods.getUpdates(&bot, offset, 100, 30);
        defer {
            for (updates) |*update| update.deinit(allocator);
            allocator.free(updates);
        }

        for (updates) |update| {
            offset = update.update_id + 1;
            if (update.message) |message| {
                if (message.text) |text| {
                    if (pass_fail_count == 3) {
                        var reply = try telegram.methods.sendMessage(&bot, message.chat.id, "Used up all 3 attempts to authenticate.");
                        defer reply.deinit(allocator);
                        std.log.err("Client failed to identify thrice", .{});
                    }

                    const pass = std.mem.eql(u8, text, panalib);
                    if (pass) {
                        auth_ok = true; // break loop
                        std.log.info("Client identified successfully.", .{});
                        var reply = try telegram.methods.sendMessage(&bot, message.chat.id, "Identification successful. Please send at least one message to trigger the update. To log out, send /bye");
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

    var new_offset = offset;
    var chat_id: i64 = -1;
    while (auth_ok) {
        const updates = try telegram.methods.getUpdates(&bot, new_offset, 3, 5);
        defer {
            for (updates) |*update| update.deinit(allocator);
            allocator.free(updates);
        }

        // receive sample
        var sample: iox2.iox2_sample_h = null;
        if (iox2.iox2_subscriber_receive(&subscriber, null, &sample) != iox2.IOX2_OK) {
            std.log.err("Failed to receive sample\n", .{});
            iox2.iox2_service_name_drop(service_name);
        }

        if (sample != null) {
            var payload: ?*TgbotAlertFromPlc = null;
            const linopot: *?*const anyopaque = @ptrCast(&payload);
            iox2.iox2_sample_payload(&sample, linopot, null);

            if (payload) |msg| {
                std.log.info("received: {}", .{msg.err_code});

                for (updates) |update| {
                    new_offset = update.update_id + 1;
                    if (update.message) |message| {
                        chat_id = message.chat.id;

                        if (message.text) |text| {
                            if (std.mem.eql(u8, text, "/bye")) {
                                auth_ok = false;
                                break;
                            }
                        }
                    }
                }

                if (msg.err_code == @intFromEnum(ErrCodes.Uninit)) {
                    std.log.err("PLC logic error, ErrCode is uninitialized", .{});
                }

                // if (msg.err_code == @intFromEnum(ErrCodes.OllKorrect)) {
                //     var reply = try telegram.methods.sendMessage(&bot, chat_id, "Part 1 and Part 2 Report OK");
                //     defer reply.deinit(allocator);
                //     std.log.info("sendMessage returned: {}", .{reply});
                // }

                if (msg.err_code == @intFromEnum(ErrCodes.Part1Part2ReportDown)) {
                    var reply = try telegram.methods.sendMessage(&bot, chat_id, "\xF0\x9F\x98\xA8 Part 1 and Part 2 Report NOK\xF0\x9F\x9A\xA8 \n We need you at the floor now! \xF0\x9F\x98\x93");
                    defer reply.deinit(allocator);
                }

                if (msg.err_code == @intFromEnum(ErrCodes.Part2ReportDown)) {
                    var reply = try telegram.methods.sendMessage(&bot, chat_id, "\xF0\x9F\x98\xA8 Part 2 Report NOK\xF0\x9F\x9A\xA8 \n We need you at the floor now! \xF0\x9F\x98\x93");
                    defer reply.deinit(allocator);
                }

                if (msg.err_code == @intFromEnum(ErrCodes.Part1ReportDown)) {
                    var reply = try telegram.methods.sendMessage(&bot, chat_id, "\xF0\x9F\x98\xA8 Part 1 Report NOK\xF0\x9F\x9A\xA8 \n We need you at the floor now! \xF0\x9F\x98\x93");
                    defer reply.deinit(allocator);
                }
            }

            iox2.iox2_sample_drop(sample);
        }
    }
    std.Thread.sleep(1_000_000_000);
}
