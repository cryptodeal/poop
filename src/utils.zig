const builtin = @import("builtin");
const std = @import("std");

pub fn isLp64() bool {
    return builtin.target.cTypeBitSize(.long) == 64 and
        builtin.target.cTypeBitSize(.int) == 32 and
        builtin.target.ptrBitWidth() == 64;
}
