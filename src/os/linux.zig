const std = @import("std");

const Sample = @import("../main.zig").Sample;

const assert = std.debug.assert;
const fd_t = std.posix.fd_t;
const PERF = std.os.linux.PERF;
const pid_t = std.os.pid_t;

pub const PerfMeasurement = struct {
    name: []const u8,
    config: PERF.COUNT.HW,
};

pub const perf_measurements = [_]PerfMeasurement{
    .{ .name = "cpu_cycles", .config = PERF.COUNT.HW.CPU_CYCLES },
    .{ .name = "instructions", .config = PERF.COUNT.HW.INSTRUCTIONS },
    .{ .name = "cache_references", .config = PERF.COUNT.HW.CACHE_REFERENCES },
    .{ .name = "cache_misses", .config = PERF.COUNT.HW.CACHE_MISSES },
    .{ .name = "branch_misses", .config = PERF.COUNT.HW.BRANCH_MISSES },
};

pub const Events = struct {
    perf_fds: [perf_measurements.len]fd_t = [_]fd_t{-1} ** perf_measurements.len,

    pub fn init() Events {
        var self: Events = .{};
        for (perf_measurements, &self.perf_fds) |measurement, *perf_fd| {
            var attr: std.os.linux.perf_event_attr = .{
                .type = PERF.TYPE.HARDWARE,
                .config = @intFromEnum(measurement.config),
                .flags = .{
                    .disabled = true,
                    .exclude_kernel = true,
                    .exclude_hv = true,
                    .inherit = true,
                    .enable_on_exec = true,
                },
            };
            perf_fd.* = std.posix.perf_event_open(&attr, 0, -1, self.perf_fds[0], PERF.FLAG.FD_CLOEXEC) catch |err| {
                std.debug.panic("unable to open perf event: {s}\n", .{@errorName(err)});
            };
        }

        _ = std.os.linux.ioctl(self.perf_fds[0], PERF.EVENT_IOC.DISABLE, PERF.IOC_FLAG_GROUP);
        _ = std.os.linux.ioctl(self.perf_fds[0], PERF.EVENT_IOC.RESET, PERF.IOC_FLAG_GROUP);
    }

    pub fn reset(self: *Events) void {
        for (&self.perf_fds) |*perf_fd| {
            std.posix.close(perf_fd.*);
            perf_fd.* = -1;
        }
    }

    fn readPerfFd(fd: fd_t) usize {
        var result: usize = 0;
        const n = std.posix.read(fd, std.mem.asBytes(&result)) catch |err| {
            std.debug.panic("unable to read perf fd: {s}\n", .{@errorName(err)});
        };
        assert(n == @sizeOf(usize));
        return result;
    }

    pub fn sample(self: *Events, wall_time: u64, peak_rss: u64) Sample {
        return .{
            .wall_time = wall_time,
            .peak_rss = peak_rss,
            .cpu_cycles = readPerfFd(self.perf_fds[0]),
            .instructions = readPerfFd(self.perf_fds[1]),
            .cache_references = readPerfFd(self.perf_fds[2]),
            .cache_misses = readPerfFd(self.perf_fds[3]),
            .branch_misses = readPerfFd(self.perf_fds[4]),
        };
    }
};
