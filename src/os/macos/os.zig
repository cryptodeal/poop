const builtin = @import("builtin");
const std = @import("std");

const isLp64 = @import("../../utils.zig").isLp64;

pub const KPERF = struct {
    /// Maximum number of kperf action ids.
    pub const ACTION_MAX = 32;

    /// Maximum number of kperf timer ids.
    pub const TIMER_MAX = 8;

    pub const SAMPLE = enum(u16) {
        TH_INFO = 1 << 0,
        TH_SNAPSHOT = 1 << 1,
        KSTACK = 1 << 2,
        USTACK = 1 << 3,
        PMC_THREAD = 1 << 4,
        PMC_CPU = 1 << 5,
        PMC_CONFIG = 1 << 6,
        MEMINFO = 1 << 7,
        TH_SCHEDULING = 1 << 8,
        TH_DISPATCH = 1 << 9,
        TK_SNAPSHOT = 1 << 10,
        SYS_MEM = 1 << 11,
        TH_INSCYC = 1 << 12,
        TK_INFO = 1 << 13,
    };

    pub const CFGWORD = enum(u32) {
        EL0A32EN_MASK = 0x10000,
        EL0A64EN_MASK = 0x20000,
        EL1EN_MASK = 0x40000,
        EL3EN_MASK = 0x80000,
        ALLMODES_MASK = 0xf0000,
    };

    pub const CPMU = enum(u32) {
        NONE = 0,
        CORE_CYCLE = 0x02,
        INST_A64 = 0x8c,
        INST_BRANCH = 0x8d,
        SYNC_DC_LOAD_MISS = 0xbf,
        SYNC_DC_STORE_MISS = 0xc0,
        SYNC_DTLB_MISS = 0xc1,
        SYNC_ST_HIT_YNGR_LD = 0xc4,
        SYNC_BR_ANY_MISP = 0xcb,
        FED_IC_MISS_DEM = 0xd3,
        FED_ITLB_MISS = 0xd4,
    };
};

pub const KPC = struct {
    /// The maximum number of counters we could read from every class in one go.
    /// ARMV7: FIXED: 1, CONFIGURABLE: 4
    /// ARM32: FIXED: 2, CONFIGURABLE: 6
    /// ARM64: FIXED: 2, CONFIGURABLE: CORE_NCTRS - FIXED (6 or 8)
    /// x86: 32
    pub const MAX_COUNTERS = 32;

    /// Cross-platform class constants.
    pub const CLASS = struct {
        pub const FIXED = 0;
        pub const CONFIGURABLE = 1;
        pub const POWER = 2;
        pub const RAWPMU = 3;

        /// Cross-platform class mask constants.
        pub const MASK = enum(u4) {
            FIXED = 1 << FIXED,
            CONFIGURABLE = 1 << CONFIGURABLE,
            POWER = 1 << POWER,
            RAWPMU = 1 << RAWPMU,
        };
    };

    /// PMU version constants.
    pub const PMU = enum(u32) {
        ERROR = 0,
        INTEL_V3 = 1,
        ARM_APPLE = 2,
        INTEL_V2 = 3,
        ARM_V2 = 4,
    };
};

pub const KDBG = struct {
    pub const CLASSTYPE = 0x10000;
    pub const SUBCLSTYPE = 0x20000;
    pub const RANGETYPE = 0x40000;
    pub const TYPENONE = 0x80000;
    pub const CKTYPES = 0xF0000;

    pub const VALCHECK = 0x00200000;
    pub const BufArgType = switch (builtin.arch) {
        .aarch64 => u64,
        else => usize,
    };

    const Buf32 = extern struct {
        timestamp: u64,
        arg1: BufArgType,
        arg2: BufArgType,
        arg3: BufArgType,
        arg4: BufArgType,
        arg5: BufArgType,
        debugid: u32,
    };

    const Buf64 = extern struct {
        timestamp: u64,
        arg1: BufArgType,
        arg2: BufArgType,
        arg3: BufArgType,
        arg4: BufArgType,
        arg5: BufArgType,
        debugid: u32,
        cpuid: u32,
        unused: BufArgType,
    };

    pub const Buf = if (isLp64() or builtin.arch == .aarch64) Buf64 else Buf32;
};

pub const KPEP = struct {
    /// KPEP CPU architecture constants.
    pub const ARCH = enum(u32) {
        I386,
        X86_64,
        ARM,
        AARCH64,
    };

    /// KPEP event (size: 48/28 bytes on 64/32 bit OS)
    pub const Event = extern struct {
        pub const NAME_MAX = 8;

        pub const Alias = extern struct {
            alias: [*c]const u8,
            names: [NAME_MAX][*c]const u8,

            pub fn init(alias: [*c]const u8, names: []const [*c]const u8) Alias {
                var self: Alias = .{
                    .alias = alias,
                    .names = undefined,
                };
                for (names, 0..) |n, i| self.names[i] = n;
                return self;
            }
        };

        name: [*c]const u8 = std.mem.zeroes([*c]const u8),
        description: [*c]const u8 = std.mem.zeroes([*c]const u8),
        errata: [*c]const u8 = std.mem.zeroes([*c]const u8),
        alias: [*c]const u8 = std.mem.zeroes([*c]const u8),
        fallback: [*c]const u8 = std.mem.zeroes([*c]const u8),
        mask: u32 = 0,
        number: u8 = 0,
        umask: u8 = 0,
        reserved: u8 = 0,
        is_fixed: u8 = 0,
    };

    /// KPEP database (size: 144/80 bytes on 64/32 bit OS)
    pub const Db = extern struct {
        name: [*c]const u8 = std.mem.zeroes([*c]const u8),
        cpu_id: [*c]const u8 = std.mem.zeroes([*c]const u8),
        marketing_name: [*c]const u8 = std.mem.zeroes([*c]const u8),
        plist_data: ?*anyopaque = null,
        event_map: ?*anyopaque = null,
        event_arr: [*c]Event = std.mem.zeroes([*c]Event),
        fixed_event_arr: [*c][*c]Event = std.mem.zeroes([*c][*c]Event),
        alias_map: ?*anyopaque = null,
        reserved_1: usize = 0,
        reserved_2: usize = 0,
        reserved_3: usize = 0,
        event_count: usize = 0,
        alias_count: usize = 0,
        fixed_counter_count: usize = 0,
        config_counter_count: usize = 0,
        power_counter_count: usize = 0,
        architecture: u32 = 0,
        fixed_counter_bits: u32 = 0,
        config_counter_bits: u32 = 0,
        power_counter_bits: u32 = 0,
    };

    /// KPEP config (size: 80/44 bytes on 64/32 bit OS)
    pub const Config = extern struct {
        pub const Error = enum(u32) {
            NONE = 0,
            INVALID_ARGUMENT = 1,
            OUT_OF_MEMORY = 2,
            IO = 3,
            BUFFER_TOO_SMALL = 4,
            CUR_SYSTEM_UNKNOWN = 5,
            DB_PATH_INVALID = 6,
            DB_NOT_FOUND = 7,
            DB_ARCH_UNSUPPORTED = 8,
            DB_VERSION_UNSUPPORTED = 9,
            DB_CORRUPT = 10,
            EVENT_NOT_FOUND = 11,
            CONFLICTING_EVENTS = 12,
            COUNTERS_NOT_FORCED = 13,
            EVENT_UNAVAILABLE = 14,
            ERRNO = 15,
            _,

            pub fn format(value: Error, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
                const err_str = switch (value) {
                    .INVALID_ARGUMENT => "invalid argument",
                    .OUT_OF_MEMORY => "out of memory",
                    .IO => "I/O",
                    .BUFFER_TOO_SMALL => "buffer too small",
                    .CUR_SYSTEM_UNKNOWN => "current system unknown",
                    .DB_PATH_INVALID => "database path invalid",
                    .DB_NOT_FOUND => "database not found",
                    .DB_ARCH_UNSUPPORTED => "database architecture unsupported",
                    .DB_VERSION_UNSUPPORTED => "database version unsupported",
                    .DB_CORRUPT => "database corrupt",
                    .EVENT_NOT_FOUND => "event not found",
                    .CONFLICTING_EVENTS => "conflicting events",
                    .COUNTERS_NOT_FORCED => "all counters must be forced",
                    .EVENT_UNAVAILABLE => "event unavailable",
                    .ERRNO => "check errno",
                    else => "unknown error",
                };
                return writer.print("{s}", .{err_str});
            }
        };

        kpep_db: [*c]Db = std.mem.zeroes([*c]Db),
        ev_arr: [*c][*c]Event = std.mem.zeroes([*c][*c]Event),
        ev_map: [*c]usize = std.mem.zeroes([*c]usize),
        ev_idx: [*]usize = std.mem.zeroes([*]usize),
        flags: [*c]u32 = std.mem.zeroes([*c]u32),
        kpc_periods: [*c]u64 = std.mem.zeroes([*c]u64),
        event_count: usize = 0,
        counter_count: usize = 0,
        classes: u32 = 0,
        config_counter: u32 = 0,
        power_counter: u32 = 0,
        reserved: u32 = 0,
    };
};
