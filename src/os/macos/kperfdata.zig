const os = @import("os.zig");
const std = @import("std");

var _instance: ?KPerfData = null;

pub const KPerfData = struct {
    handle: *anyopaque,
    symbols: Symbols,

    const lib_path_kperfdata = "/System/Library/PrivateFrameworks/kperfdata.framework/kperfdata";

    const Symbols = struct {
        kpep_config_create: *fn (db: [*c]os.KPEP.Db, cfg_ptr: [*c][*c]os.KPEP.Config) callconv(.C) c_int,
        kpep_config_free: *fn (cfg: [*c]os.KPEP.Config) callconv(.C) void,
        kpep_config_add_event: *fn (cfg: [*c]os.KPEP.Config, ev_ptr: [*c][*c]os.KPEP.Event, flag: u32, err: [*c]u32) callconv(.C) c_int,
        kpep_config_remove_event: *fn (cfg: [*c]os.KPEP.Config, idx: usize) callconv(.C) c_int,
        kpep_config_force_counters: *fn (cfg: [*c]os.KPEP.Config) callconv(.C) c_int,
        kpep_config_events_count: *fn (cfg: [*c]os.KPEP.Config, count_ptr: [*c]usize) callconv(.C) c_int,
        kpep_config_events: *fn (cfg: [*c]os.KPEP.Config, buf: [*c][*c]os.KPEP.Event, buf_size: usize) callconv(.C) c_int,
        kpep_config_kpc: *fn (cfg: [*c]os.KPEP.Config, buf: [*c]u64, buf_size: usize) callconv(.C) c_int,
        kpep_config_kpc_count: *fn (cfg: [*c]os.KPEP.Config, count_ptr: [*c]usize) callconv(.C) c_int,
        kpep_config_kpc_classes: *fn (cfg: [*c]os.KPEP.Config, classes_ptr: [*c]u32) callconv(.C) c_int,
        kpep_config_kpc_map: *fn (cfg: [*c]os.KPEP.Config, buf: [*c]usize, buf_size: usize) callconv(.C) c_int,
        kpep_db_create: *fn (name: [*c]const u8, db_ptr: [*c][*c]os.KPEP.Db) callconv(.C) c_int,
        kpep_db_free: *fn (db: [*c]os.KPEP.Db) callconv(.C) void,
        kpep_db_name: *fn (db: [*c]os.KPEP.Db, name: [*c][*c]const u8) callconv(.C) c_int,
        kpep_db_aliases_count: *fn (db: [*c]os.KPEP.Db, count: [*c]usize) callconv(.C) c_int,
        kpep_db_aliases: *fn (db: [*c]os.KPEP.Db, buf: [*c][*c]const u8, buf_size: usize) callconv(.C) c_int,
        kpep_db_counters_count: *fn (db: [*c]os.KPEP.Db, classes: u8, count: [*]usize) callconv(.C) c_int,
        kpep_db_events_count: *fn (db: [*c]os.KPEP.Db, count: [*c]usize) callconv(.C) c_int,
        kpep_db_events: *fn (db: [*c]os.KPEP.Db, buf: [*c][*c]os.KPEP.Event, buf_size: usize) callconv(.C) c_int,
        kpep_db_event: *fn (db: [*c]os.KPEP.Db, name: [*c]const u8, ev_ptr: [*c][*c]os.KPEP.Event) callconv(.C) c_int,
        kpep_event_name: *fn (ev: [*c]os.KPEP.Event, name_ptr: [*c][*c]const u8) callconv(.C) c_int,
        kpep_event_alias: *fn (ev: [*c]os.KPEP.Event, alias_ptr: [*c][*c]const u8) callconv(.C) c_int,
        kpep_event_description: *fn (ev: [*c]os.KPEP.Event, str_ptr: [*c][*c]const u8) callconv(.C) c_int,
    };

    pub fn init() !KPerfData {
        if (_instance) |instance| return instance;
        const handle: *anyopaque = std.c.dlopen(lib_path_kperfdata, .{ .LAZY = true }) orelse return error.FailedToLoadKPerfData;

        var symbols: Symbols = undefined;
        inline for (@typeInfo(Symbols).@"struct".fields) |f| {
            const sym: *anyopaque = std.c.dlsym(handle, f.name) orelse return error.FailedToLoadKPerf;
            @field(symbols, f.name) = @alignCast(@ptrCast(sym));
        }

        _instance = .{ .handle = handle, .symbols = symbols };
        return _instance.?;
    }

    pub fn deinit(self: *KPerfData) void {
        _ = std.c.dlclose(self.handle);
        _instance = null;
    }

    pub fn getEvent(self: *const KPerfData, db: *os.KPEP.Db, alias: *os.KPEP.Event.Alias) ?*os.KPEP.Event {
        for (0..os.KPEP.Event.NAME_MAX) |i| {
            const name = alias.names[i];
            if (name == null) break;
            var ev: ?*os.KPEP.Event = null;
            if (self.symbols.kpep_db_event(db, name, &ev) == 0) {
                return ev;
            }
        }
        return null;
    }
};
