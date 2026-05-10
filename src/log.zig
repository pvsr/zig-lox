const std = @import("std");

pub var LOG = true;

pub fn scoped(comptime scope: @EnumLiteral()) type {
    const log = std.log.scoped(scope);
    return struct {
        pub fn err(comptime format: []const u8, args: anytype) void {
            if (LOG) log.err(format, args);
        }

        pub fn warn(comptime format: []const u8, args: anytype) void {
            if (LOG) log.warn(format, args);
        }

        pub fn info(comptime format: []const u8, args: anytype) void {
            if (LOG) log.info(format, args);
        }

        pub fn debug(comptime format: []const u8, args: anytype) void {
            if (LOG) log.debug(format, args);
        }
    };
}
