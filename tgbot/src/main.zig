const iox2_root = "/home/ander/SIIP_project/iiot_gateway/sunsuyon/tgbot/c_deps/iceoryx2/target/ffi/install";
const tgbot_root = "/home/ander/SIIP_project/iiot_gateway/sunsuyon/tgbot/src";

const std = @import("std");
const telegram = @import("telegram");
const dotenv = @import("dotenv.zig");

const iox2 = @cImport({
    @cInclude(iox2_root ++ "/include/iceoryx2/v0.6.1/iox2/iceoryx2.h");
    // @cInclude("iox2/iceoryx2.h");
    // @cInclude("transmission_data.h");
    @cInclude(tgbot_root ++ "/transmission_data.h");
});

pub fn main() !void {
    // create new node
    const node_builder_handle: iox2.iox2_node_builder_h = iox2.iox2_node_builder_new(null);
    var node_handle: iox2.iox2_node_h = null;
    if (iox2.iox2_node_builder_create(node_builder_handle, null, iox2.iox2_service_type_e_IPC, &node_handle) != iox2.IOX2_OK) {
        std.log.err("Could not create node!\n", .{});
    }

    // create service name
    const service_name_value = "My/Funk/ServiceName";
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
    const payload_type_name = "16TransmissionData";
    if (iox2.iox2_service_builder_pub_sub_set_payload_type_details(&service_builder_pub_sub, iox2.iox2_type_variant_e_FIXED_SIZE, payload_type_name, payload_type_name.len, @sizeOf(iox2.TransmissionData), @alignOf(iox2.TransmissionData)) != iox2.IOX2_OK) {
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

    while (iox2.iox2_node_wait(&node_handle, 1, 0) == iox2.IOX2_OK) {
        // receive sample
        var sample: iox2.iox2_sample_h = null;
        if (iox2.iox2_subscriber_receive(&subscriber, null, &sample) != iox2.IOX2_OK) {
            std.log.err("Failed to receive sample\n", .{});
            iox2.iox2_service_name_drop(service_name);
        }

        if (sample != null) {
            var payload: ?*iox2.TransmissionData = null;
            const pootodon: *?*const anyopaque = @ptrCast(&payload);
            iox2.iox2_sample_payload(&sample, pootodon, null);

            if (payload) |msg| {
                std.log.info("received: TransmissionData .x: {}, .y: {}, .funky: {:.2}\n", .{ msg.x, msg.y, msg.funky });
            }
            iox2.iox2_sample_drop(sample);
        }
    }











    // var dbga = std.heap.DebugAllocator(.{.safety = true}){};
    // defer _ = dbga.deinit();
    // const allocator = dbga.allocator();
    // const dotenv_alloc = dbga.allocator();

    // var env = try dotenv.init(dotenv_alloc, ".env");
    // defer env.deinit();

    // const tgbot_token = env.get("TGBOT_TOKEN") orelse "Cannot find TGBOT_TOKEN env var";
    // std.debug.print("\n@{s}", .{tgbot_token});

    // var client = try telegram.HTTPClient.init(allocator);
    // defer client.deinit();

    // var bot = try telegram.Bot.init(allocator, tgbot_token, &client);
    // defer bot.deinit();

    // var me = try telegram.methods.getMe(&bot);
    // defer me.deinit(allocator);

    // std.debug.print("🚀 Bot @{s} is online!\n", .{me.username orelse me.first_name});

    // var offset: i32 = 0;
    // while (true) {
    //     const updates = try telegram.methods.getUpdates(&bot, offset, 100, 30);
    //     defer {
    //         for (updates) |*update| update.deinit(allocator);
    //         allocator.free(updates);
    //     }

    //     for (updates) |update| {
    //         offset = update.update_id + 1;

    //         if (update.message) |message| {
    //             if (message.text) |text| {
    //                 var reply = try telegram.methods.sendMessage(&bot, message.chat.id, text);
    //                 defer reply.deinit(allocator);

    //                 std.debug.print("📨 Echoed: {s}\n", .{text});
    //             }
    //         }
    //     }
    // }





}
