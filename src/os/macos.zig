const os = @import("macos/os.zig");
const std = @import("std");

const Sample = @import("../main.zig").Sample;

const KPerfData = @import("macos/kperfdata.zig").KPerfData;
const KPerf = @import("macos/kperf.zig").KPerf;

const assert = std.debug.assert;
const fd_t = std.posix.fd_t;
const pid_t = std.os.pid_t;

pub const PerfCounters = struct {
    cpu_cycles: u64,
    instructions: u64,
    branches: u64,
    branch_misses: u64,
};

var profile_events = [_]os.KPEP.Event.Alias{
    os.KPEP.Event.Alias.init(
        "cycles",
        &.{
            "FIXED_CYCLES", // Apple A7-A15
            "CPU_CLK_UNHALTED.THREAD", // Intel Core 1th-10th
            "CPU_CLK_UNHALTED.CORE", // Intel Yonah, Merom
        },
    ),
    os.KPEP.Event.Alias.init(
        "instructions",
        &.{
            "FIXED_INSTRUCTIONS", // Apple A7-A15
            "INST_RETIRED.ANY", // Intel Yonah, Merom, Core 1th-10th
        },
    ),
    os.KPEP.Event.Alias.init(
        "branches",
        &.{
            "INST_BRANCH", // Apple A7-A15
            "BR_INST_RETIRED.ALL_BRANCHES", // Intel Core 1th-10th
            "INST_RETIRED.ANY", // Intel Yonah, Merom
        },
    ),
    os.KPEP.Event.Alias.init(
        "branch_misses",
        &.{
            "BRANCH_MISPRED_NONSPEC", // Apple A7-A15, since iOS 15, macOS 12
            "BRANCH_MISPREDICT", // Apple A7-A14
            "BR_MISP_RETIRED.ALL_BRANCHES", // Intel Core 2th-10th
            "BR_INST_RETIRED.MISPRED", // Intel Yonah, Merom
        },
    ),
    os.KPEP.Event.Alias.init("cache_references", &.{
        "L1D_TLB_ACCESS", // Apple A7-A15
        // TODO: track down flags for older CPU versions
    }),
    os.KPEP.Event.Alias.init("cache_misses", &.{
        "L1D_TLB_MISS", // Apple A7-A15
        // TODO: track down flags for older CPU versions
    }),
};

var _instance: ?Events = null;

pub const Events = struct {
    regs: [os.KPC.MAX_COUNTERS]u64 = [_]u64{0} ** os.KPC.MAX_COUNTERS,
    counter_map: [os.KPC.MAX_COUNTERS]usize = [_]usize{0} ** os.KPC.MAX_COUNTERS,
    counters_0: [os.KPC.MAX_COUNTERS]u64 = [_]u64{0} ** os.KPC.MAX_COUNTERS,
    counters_1: [os.KPC.MAX_COUNTERS]u64 = [_]u64{0} ** os.KPC.MAX_COUNTERS,

    kperf: KPerf,
    kperfdata: KPerfData,

    pub fn init() Events {
        if (_instance) |instance| return instance;
        // load dylib(s)
        _instance = .{
            .kperf = KPerf.init() catch @panic("Failed to load kperf.\n"),
            .kperfdata = KPerfData.init() catch @panic("Failed to load kperfdata.\n"),
        };
        _instance.?.setup();
        return _instance.?;
    }

    pub fn setup(self: *Events) void {
        // check permission
        var force_ctrs: c_int = 0;
        if (self.kperf.symbols.kpc_force_all_ctrs_get(&force_ctrs) != 0) @panic("Permission denied, xnu/kpc requires root privileges.\n");

        var ret: c_int = undefined;
        // load pmc db
        var db: [*c]os.KPEP.Db = null;
        ret = self.kperfdata.symbols.kpep_db_create(null, &db);
        if (ret != 0) std.debug.panic("Error: cannot load pmc database: {d}.\n", .{ret});

        // std.log.info("loaded db: {s} ({s})\n", .{ std.mem.span(db.name), std.mem.span(db.marketing_name) });

        // create a config
        var cfg: [*c]os.KPEP.Config = null;
        ret = self.kperfdata.symbols.kpep_config_create(db, &cfg);
        if (ret != 0) std.debug.panic("Failed to create kpep config: {d} ({s}).\n", .{ ret, @as(os.KPEP.Config.Error, @enumFromInt(ret)) });
        ret = self.kperfdata.symbols.kpep_config_force_counters(cfg);
        if (ret != 0) std.debug.panic("Failed to force counters: {d} ({s}).\n", .{ ret, @as(os.KPEP.Config.Error, @enumFromInt(ret)) });

        // get events
        var ev_arr: [profile_events.len]?*os.KPEP.Event = undefined;
        for (&profile_events, 0..) |*alias, i| {
            if (self.kperfdata.getEvent(@ptrCast(@alignCast(db)), alias)) |ev| {
                ev_arr[i] = ev;
            } else std.debug.panic("Cannot find event: {s}.\n", .{alias.alias});
        }

        // add event to config
        for (&ev_arr) |*ev| {
            ret = self.kperfdata.symbols.kpep_config_add_event(cfg, @ptrCast(@alignCast(ev)), 0, null);
            if (ret != 0) std.debug.panic("Failed to add event: {d} ({s}).\n", .{ ret, @as(os.KPEP.Config.Error, @enumFromInt(ret)) });
        }

        // prepare buffer and config
        var classes: u32 = 0;
        var reg_count: usize = 0;
        ret = self.kperfdata.symbols.kpep_config_kpc_classes(cfg, &classes);
        if (ret != 0) std.debug.panic("Failed get kpc classes: {d} ({s}).\n", .{ ret, @as(os.KPEP.Config.Error, @enumFromInt(ret)) });

        ret = self.kperfdata.symbols.kpep_config_kpc_count(cfg, &reg_count);
        if (ret != 0) std.debug.panic("Failed get kpc count: {d} ({s}).\n", .{ ret, @as(os.KPEP.Config.Error, @enumFromInt(ret)) });

        ret = self.kperfdata.symbols.kpep_config_kpc_map(cfg, (&self.counter_map).ptr, @sizeOf(@TypeOf(self.counter_map)));
        if (ret != 0) std.debug.panic("Failed get kpc map: {d} ({s}).\n", .{ ret, @as(os.KPEP.Config.Error, @enumFromInt(ret)) });

        ret = self.kperfdata.symbols.kpep_config_kpc(cfg, (&self.regs).ptr, @sizeOf(@TypeOf(self.regs)));
        if (ret != 0) std.debug.panic("Failed get kpc registers: {d} ({s}).\n", .{ ret, @as(os.KPEP.Config.Error, @enumFromInt(ret)) });

        // set config to kernel
        ret = self.kperf.symbols.kpc_force_all_ctrs_set(1);
        if (ret != 0) std.debug.panic("Failed to force all ctrs: {d}.\n", .{ret});

        if ((classes & @intFromEnum(os.KPC.CLASS.MASK.CONFIGURABLE)) != 0 and reg_count != 0) {
            ret = self.kperf.symbols.kpc_set_config(classes, (&self.regs).ptr);
            if (ret != 0) std.debug.panic("Failed set kpc config: {d}.\n", .{ret});
        }

        // start counting
        ret = self.kperf.symbols.kpc_set_counting(classes);
        if (ret != 0) std.debug.panic("Failed set counting: {d}.\n", .{ret});

        ret = self.kperf.symbols.kpc_set_thread_counting(classes);
        if (ret != 0) std.debug.panic("Failed set thread counting: {d}.\n", .{ret});
    }

    pub fn sample(self: *Events, wall_time: u64, peak_rss: u64) Sample {
        // get counters before
        const ret = self.kperf.symbols.kpc_get_thread_counters(0, os.KPC.MAX_COUNTERS, (&self.counters_0).ptr);
        if (ret != 0) std.debug.panic("Failed get thread counters before: {d}.\n", .{ret});
        return .{
            .wall_time = wall_time,
            .peak_rss = peak_rss,
            .cpu_cycles = self.counters_0[self.counter_map[0]],
            .instructions = self.counters_0[self.counter_map[1]],
            .branch_misses = self.counters_0[self.counter_map[3]],
            .cache_references = self.counters_0[self.counter_map[4]],
            .cache_misses = self.counters_0[self.counter_map[5]],
        };
    }

    pub fn reset(_: *const Events) void {} // stub

};

test "Events - run as sudo" {
    var ev = Events.init();
    std.debug.print("{any}\n", .{ev.getCounters()});
}
