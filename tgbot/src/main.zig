const std = @import("std");
const telegram = @import("telegram");
const dotenv = @import("dotenv.zig");

pub fn main() !void {
    var dbga = std.heap.DebugAllocator(.{.safety = true}){};
    defer _ = dbga.deinit();
    const allocator = dbga.allocator();
    const dotenv_alloc = dbga.allocator();

    var env = try dotenv.init(dotenv_alloc, ".env");
    defer env.deinit();

    const tgbot_token = env.get("TGBOT_TOKEN") orelse "Cannot find TGBOT_TOKEN env var";
    std.debug.print("\n@{s}", .{tgbot_token});

    var client = try telegram.HTTPClient.init(allocator);
    defer client.deinit();

    var bot = try telegram.Bot.init(allocator, tgbot_token, &client);
    defer bot.deinit();

    var me = try telegram.methods.getMe(&bot);
    defer me.deinit(allocator);
    
    std.debug.print("🚀 Bot @{s} is online!\n", .{me.username orelse me.first_name});

    var offset: i32 = 0;
    while (true) {
        const updates = try telegram.methods.getUpdates(&bot, offset, 100, 30);
        defer {
            for (updates) |*update| update.deinit(allocator);
            allocator.free(updates);
        }

        for (updates) |update| {
            offset = update.update_id + 1;
            
            if (update.message) |message| {
                if (message.text) |text| {
                    var reply = try telegram.methods.sendMessage(&bot, message.chat.id, text);
                    defer reply.deinit(allocator);
                    
                    std.debug.print("📨 Echoed: {s}\n", .{text});
                }
            }
        }
    }
}