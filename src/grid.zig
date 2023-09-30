const std = @import("std");
const Size = @import("./common.zig").Size;
const NDSlice = @import("./ndslice.zig").NDSlice;

pub const Grid = struct {
    allocator: std.mem.Allocator,
    size: Size,
    cells: Cells,
    buffer: []Grid.Cell,

    pub const Cell = struct {
        rune: ?[]const u8,
    };
    pub const Cells = NDSlice(Cell, 2, .row_major);

    pub fn init(allocator: std.mem.Allocator, size: Size) !Grid {
        var buffer = try allocator.alloc(Grid.Cell, size.width * size.height);
        errdefer allocator.free(buffer);
        for (buffer) |*cell| {
            cell.rune = null;
        }
        return .{
            .allocator = allocator,
            .size = size,
            .cells = try Grid.Cells.init(.{ size.height, size.width }, buffer),
            .buffer = buffer,
        };
    }

    pub fn initFromGrid(allocator: std.mem.Allocator, grid: Grid, size: Size, grid_x: usize, grid_y: usize) !Grid {
        // TODO: for now this is just copying from the source grid.
        // we really should just be getting a view into it, but i'm too lazy right now.
        var buffer = try allocator.alloc(Grid.Cell, size.width * size.height);
        errdefer allocator.free(buffer);
        for (buffer) |*cell| {
            cell.rune = null;
        }
        var cells = try Grid.Cells.init(.{ size.height, size.width }, buffer);
        var dest_y: usize = 0;
        for (grid_y..grid_y + size.height) |source_y| {
            var dest_x: usize = 0;
            for (grid_x..grid_x + size.width) |source_x| {
                if (cells.at(.{ dest_y, dest_x })) |dest_index| {
                    if (grid.cells.at(.{ source_y, source_x })) |source_index| {
                        cells.items[dest_index].rune = grid.cells.items[source_index].rune;
                    } else |_| {
                        break;
                    }
                } else |_| {
                    break;
                }
                dest_x += 1;
            }
            dest_y += 1;
        }
        return .{
            .allocator = allocator,
            .size = size,
            .cells = cells,
            .buffer = buffer,
        };
    }

    pub fn deinit(self: *Grid) void {
        self.allocator.free(self.buffer);
    }
};

pub fn expectEqual(expected: anytype, actual: anytype) !void {
    try std.testing.expectEqual(@as(@TypeOf(actual), expected), actual);
}

test {
    const allocator = std.testing.allocator;
    var grid = try Grid.init(allocator, .{ .width = 10, .height = 10 });
    defer grid.deinit();
    try expectEqual(null, grid.cells.items[try grid.cells.at(.{ 0, 0 })].rune);
}