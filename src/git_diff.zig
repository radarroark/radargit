const std = @import("std");
const xitui = @import("xitui");
const term = xitui.terminal;
const wgt = xitui.widget;
const layout = xitui.layout;
const inp = xitui.input;
const Grid = xitui.grid.Grid;
const Focus = xitui.focus.Focus;

const c = @cImport({
    @cInclude("git2.h");
});

pub fn GitDiff(comptime Widget: type) type {
    return struct {
        box: wgt.Box(Widget),
        allocator: std.mem.Allocator,
        repo: ?*c.git_repository,
        patches: std.ArrayList(?*c.git_patch),
        bufs: std.ArrayList(c.git_buf),

        pub fn init(allocator: std.mem.Allocator, repo: ?*c.git_repository) !GitDiff(Widget) {
            var inner_box = try wgt.Box(Widget).init(allocator, null, .vert);
            errdefer inner_box.deinit();

            var scroll = try wgt.Scroll(Widget).init(allocator, .{ .box = inner_box }, .both);
            errdefer scroll.deinit();

            var outer_box = try wgt.Box(Widget).init(allocator, .single, .vert);
            errdefer outer_box.deinit();
            try outer_box.children.put(scroll.getFocus().id, .{ .widget = .{ .scroll = scroll }, .rect = null, .min_size = null });

            return .{
                .box = outer_box,
                .allocator = allocator,
                .repo = repo,
                .patches = std.ArrayList(?*c.git_patch).init(allocator),
                .bufs = std.ArrayList(c.git_buf).init(allocator),
            };
        }

        pub fn deinit(self: *GitDiff(Widget)) void {
            for (self.bufs.items) |*buf| {
                c.git_buf_dispose(buf);
            }
            self.bufs.deinit();

            for (self.patches.items) |patch| {
                c.git_patch_free(patch);
            }
            self.patches.deinit();

            self.box.deinit();
        }

        pub fn build(self: *GitDiff(Widget), constraint: layout.Constraint, root_focus: *Focus) !void {
            self.clearGrid();
            self.box.border_style = if (root_focus.grandchild_id == self.getFocus().id) .double else .single;
            try self.box.build(constraint, root_focus);

            // add another diff if necessary
            if (self.box.grid) |outer_box_grid| {
                const outer_box_height = outer_box_grid.size.height - 2;
                const scroll_y = self.box.children.values()[0].widget.scroll.y;
                const u_scroll_y: usize = if (scroll_y >= 0) @intCast(scroll_y) else 0;
                if (self.box.children.values()[0].widget.scroll.child.box.grid) |inner_box_grid| {
                    const inner_box_height = inner_box_grid.size.height;
                    const min_scroll_remaining = 5;
                    if (inner_box_height -| (outer_box_height + u_scroll_y) <= min_scroll_remaining) {
                        if (self.bufs.items.len < self.patches.items.len) {
                            try self.addDiff(self.patches.items[self.bufs.items.len]);
                        }
                    }
                }
            }
        }

        pub fn input(self: *GitDiff(Widget), key: inp.Key, root_focus: *Focus) !void {
            _ = root_focus;
            switch (key) {
                .arrow_up => {
                    if (self.box.children.values()[0].widget.scroll.y > 0) {
                        self.box.children.values()[0].widget.scroll.y -= 1;
                    }
                },
                .arrow_down => {
                    if (self.box.grid) |outer_box_grid| {
                        const outer_box_height = outer_box_grid.size.height - 2;
                        const scroll_y = self.box.children.values()[0].widget.scroll.y;
                        const u_scroll_y: usize = if (scroll_y >= 0) @intCast(scroll_y) else 0;
                        if (self.box.children.values()[0].widget.scroll.child.box.grid) |inner_box_grid| {
                            const inner_box_height = inner_box_grid.size.height;
                            if (outer_box_height + u_scroll_y < inner_box_height) {
                                self.box.children.values()[0].widget.scroll.y += 1;
                            }
                        }
                    }
                },
                .arrow_left => {
                    if (self.box.children.values()[0].widget.scroll.x > 0) {
                        self.box.children.values()[0].widget.scroll.x -= 1;
                    }
                },
                .arrow_right => {
                    if (self.box.grid) |outer_box_grid| {
                        const outer_box_width = outer_box_grid.size.width - 2;
                        const scroll_x = self.box.children.values()[0].widget.scroll.x;
                        const u_scroll_x: usize = if (scroll_x >= 0) @intCast(scroll_x) else 0;
                        if (self.box.children.values()[0].widget.scroll.child.box.grid) |inner_box_grid| {
                            const inner_box_width = inner_box_grid.size.width;
                            if (outer_box_width + u_scroll_x < inner_box_width) {
                                self.box.children.values()[0].widget.scroll.x += 1;
                            }
                        }
                    }
                },
                .home => {
                    self.box.children.values()[0].widget.scroll.y = 0;
                },
                .end => {
                    if (self.box.grid) |outer_box_grid| {
                        if (self.box.children.values()[0].widget.scroll.child.box.grid) |inner_box_grid| {
                            const outer_box_height = outer_box_grid.size.height - 2;
                            const inner_box_height = inner_box_grid.size.height;
                            const max_scroll: isize = if (inner_box_height > outer_box_height) @intCast(inner_box_height - outer_box_height) else 0;
                            self.box.children.values()[0].widget.scroll.y = max_scroll;
                        }
                    }
                },
                .page_up => {
                    if (self.box.grid) |outer_box_grid| {
                        const outer_box_height = outer_box_grid.size.height - 2;
                        const scroll_y = self.box.children.values()[0].widget.scroll.y;
                        const scroll_change: isize = @intCast(outer_box_height / 2);
                        self.box.children.values()[0].widget.scroll.y = @max(0, scroll_y - scroll_change);
                    }
                },
                .page_down => {
                    if (self.box.grid) |outer_box_grid| {
                        if (self.box.children.values()[0].widget.scroll.child.box.grid) |inner_box_grid| {
                            const outer_box_height = outer_box_grid.size.height - 2;
                            const inner_box_height = inner_box_grid.size.height;
                            const max_scroll: isize = if (inner_box_height > outer_box_height) @intCast(inner_box_height - outer_box_height) else 0;
                            const scroll_y = self.box.children.values()[0].widget.scroll.y;
                            const scroll_change: isize = @intCast(outer_box_height / 2);
                            self.box.children.values()[0].widget.scroll.y = @min(scroll_y + scroll_change, max_scroll);
                        }
                    }
                },
                else => {},
            }
        }

        pub fn clearGrid(self: *GitDiff(Widget)) void {
            self.box.clearGrid();
        }

        pub fn getGrid(self: GitDiff(Widget)) ?Grid {
            return self.box.getGrid();
        }

        pub fn getFocus(self: *GitDiff(Widget)) *Focus {
            return self.box.getFocus();
        }

        pub fn clearDiffs(self: *GitDiff(Widget)) !void {
            // clear buffers
            for (self.bufs.items) |*buf| {
                c.git_buf_dispose(buf);
            }
            self.bufs.clearAndFree();

            // clear patches
            for (self.patches.items) |patch| {
                c.git_patch_free(patch);
            }
            self.patches.clearAndFree();

            // remove old diff widgets
            for (self.box.children.values()[0].widget.scroll.child.box.children.values()) |*child| {
                child.widget.deinit();
            }
            self.box.children.values()[0].widget.scroll.child.box.children.clearAndFree();

            // reset scroll position
            const widget = &self.box.children.values()[0].widget;
            widget.scroll.x = 0;
            widget.scroll.y = 0;
        }

        pub fn addDiff(self: *GitDiff(Widget), patch: ?*c.git_patch) !void {
            // add new buffer
            var buf: c.git_buf = std.mem.zeroes(c.git_buf);
            std.debug.assert(0 == c.git_patch_to_buf(&buf, patch));
            const content = std.mem.sliceTo(buf.ptr, 0);

            // add to bufs
            {
                errdefer c.git_buf_dispose(&buf);
                try self.bufs.append(buf);
            }

            if (!std.unicode.utf8ValidateSlice(content)) {
                // dont' display diffs with invalid unicode
                var text_box = try wgt.TextBox(Widget).init(self.allocator, "Diff omitted due to invalid unicode", .hidden);
                errdefer text_box.deinit();
                try self.box.children.values()[0].widget.scroll.child.box.children.put(text_box.getFocus().id, .{ .widget = .{ .text_box = text_box }, .rect = null, .min_size = null });
            } else {
                // add new diff widget
                var text_box = try wgt.TextBox(Widget).init(self.allocator, content, .hidden);
                errdefer text_box.deinit();
                try self.box.children.values()[0].widget.scroll.child.box.children.put(text_box.getFocus().id, .{ .widget = .{ .text_box = text_box }, .rect = null, .min_size = null });
            }
        }

        pub fn getScrollX(self: GitDiff(Widget)) isize {
            return self.box.children.values()[0].widget.scroll.x;
        }

        pub fn getScrollY(self: GitDiff(Widget)) isize {
            return self.box.children.values()[0].widget.scroll.y;
        }

        pub fn isEmpty(self: GitDiff(Widget)) bool {
            return self.box.children.count() == 0;
        }
    };
}
