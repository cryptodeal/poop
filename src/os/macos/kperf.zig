const os = @import("os.zig");
const std = @import("std");

var _instance: ?KPerf = null;

pub const KPerf = struct {
    handle: *anyopaque,
    symbols: Symbols,

    const lib_path_kperf = "/System/Library/PrivateFrameworks/kperf.framework/kperf";
    const COUNTERS_COUNT = 10;
    const CONFIG_COUNT = 8;
    const KPC_MASK: u32 = @intFromEnum(os.KPC.CLASS.MASK.CONFIGURABLE) | @intFromEnum(os.KPC.CLASS.MASK.FIXED);

    const Symbols = struct {
        /// Get the version of KPC that's being run.
        kpc_pmu_version: *fn () callconv(.C) u32,
        /// Prints the current CPU id string to the buffer. This string
        /// can be used to locate the PMC database in /usr/share/kpep.
        /// Returns string's length, or negative value if error occurs.
        kpc_cpu_string: *fn (buf: [*c]u8, buf_size: usize) callconv(.C) c_int,
        /// Set PMC classes to enable counting.
        kpc_set_counting: *fn (classes: u32) callconv(.C) c_int,
        kpc_get_counting: *fn () callconv(.C) u32,
        kpc_set_thread_counting: *fn (classes: u32) callconv(.C) c_int,
        kpc_get_thread_counting: *fn () callconv(.C) u32,
        kpc_get_config_count: *fn (classes: u32) callconv(.C) u32,
        kpc_get_counter_count: *fn (classes: u32) callconv(.C) u32,
        kpc_set_config: *fn (classes: u32, config: [*c]u64) callconv(.C) c_int,
        kpc_get_config: *fn (classes: u32, congif: [*c]u64) callconv(.C) c_int,
        kpc_get_cpu_counters: *fn (all_cpus: bool, classes: u32, curcpu: [*c]c_int, buf: [*c]u64) callconv(.C) c_int,
        kpc_get_thread_counters: *fn (tid: u32, buf_count: u32, buf: [*]u64) callconv(.C) c_int,
        kpc_force_all_ctrs_set: *fn (val: c_int) callconv(.C) c_int,
        kpc_force_all_ctrs_get: *fn (val_out: [*c]c_int) callconv(.C) c_int,
        kperf_action_count_set: *fn (count: u32) callconv(.C) c_int,
        kperf_action_count_get: *fn (count: [*]u32) callconv(.C) c_int,
        kperf_action_samplers_set: *fn (actionid: u32, sample: u32) callconv(.C) c_int,
        kperf_action_samplers_get: *fn (actionid: u32, sample: [*c]u32) callconv(.C) c_int,
        kperf_action_filter_set_by_task: *fn (actionid: u32, port: i32) callconv(.C) c_int,
        kperf_action_filter_set_by_pid: *fn (actionid: u32, pid: i32) callconv(.C) c_int,
        kperf_timer_count_set: *fn (count: u32) callconv(.C) c_int,
        kperf_timer_count_get: *fn (count: [*c]u32) callconv(.C) c_int,
        kperf_timer_period_set: *fn (actionid: u32, tick: u64) callconv(.C) c_int,
        kperf_timer_period_get: *fn (actionid: u32, tick: [*c]u64) callconv(.C) c_int,
        kperf_timer_action_set: *fn (actionid: u32, timerid: u32) callconv(.C) c_int,
        kperf_timer_action_get: *fn (actionid: u32, timerid: [*c]u32) callconv(.C) c_int,
        kperf_sample_set: *fn (enabled: u32) callconv(.C) c_int,
        kperf_sample_get: *fn (enabled: [*c]u32) callconv(.C) c_int,
        kperf_reset: *fn () callconv(.C) c_int,
        kperf_timer_pet_set: *fn (timerid: u32) callconv(.C) c_int,
        kperf_timer_pet_get: *fn (timerid: [*c]u32) callconv(.C) c_int,
        kperf_ns_to_ticks: *fn (ns: u64) callconv(.C) u64,
        kperf_ticks_to_ns: *fn (ticks: u64) callconv(.C) u64,
        kperf_tick_frequency: *fn () callconv(.C) u64,
    };

    pub fn init() !KPerf {
        if (_instance) |instance| return instance;
        const handle: *anyopaque = std.c.dlopen(lib_path_kperf, .{ .LAZY = true }) orelse return error.FailedToLoadKPerf;

        var symbols: Symbols = undefined;

        inline for (@typeInfo(Symbols).@"struct".fields) |f| {
            const sym: *anyopaque = std.c.dlsym(handle, f.name) orelse return error.FailedToLoadKPerf;
            @field(symbols, f.name) = @alignCast(@ptrCast(sym));
        }

        _instance = .{ .handle = handle, .symbols = symbols };
        return _instance.?;
    }

    pub fn deinit(self: *KPerf) void {
        _ = std.c.dlclose(self.handle);
        _instance = null;
    }
};
