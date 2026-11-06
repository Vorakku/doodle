import std;
import math;
import reef_model;

// shortcut: a fixed grid can't resolve shapes under about 3 cells across (tiny drawings made at
// high zoom report "not enclosed"); upgrade by sizing the grid to the current view if that comes up.
let FILL_CELLS_PER_UNIT: i64 = 768;
// How far apart, as a share of the canvas, two lines can stop and still count as connected.
let FILL_SNAP: f32 = 0.02;
// Holes up to this many cells (an eye, a dot) get filled too, since fills are drawn under the lines.
let FILL_MAX_HOLE_CELLS: i64 = 2500;
// This width marks a saved point as a fill row, drawn as a solid bar rather than a round line.
// Brushes can't produce it: the thinnest is 2 pixels on the largest possible canvas, about 0.0001.
let FILL_WIDTH: f32 = 0.00003;
let FILL_ROW_HEIGHT: f32 = 1.0 / FILL_CELLS_PER_UNIT;
// Marks the taller fill rows saved by the first version of this tool.
let LEGACY_FILL_WIDTH: f32 = 0.00002;
let LEGACY_FILL_ROW_HEIGHT: f32 = 1.0 / 256.0;

fn fill_row_height(width: f32) -> f32 {
    if width == FILL_WIDTH { return FILL_ROW_HEIGHT; }
    if width == LEGACY_FILL_WIDTH { return LEGACY_FILL_ROW_HEIGHT; }
    return 0.0;
}

enum FillResult { Filled, OpenShape, OnInk, NoRoom }
struct FillRange { first: i64, end: i64 }

struct Grid { w: i64, h: i64, cells: u8[>..] }

fn stamp_disc(grid: Grid&, cx: f32, cy: f32, radius: f32) {
    let x0 = max(0, floor(cx - radius) as! i64);
    let x1 = min(grid.w - 1, ceil(cx + radius) as! i64);
    let y0 = max(0, floor(cy - radius) as! i64);
    let y1 = min(grid.h - 1, ceil(cy + radius) as! i64);
    var y = y0;
    while y <= y1 {
        var x = x0;
        while x <= x1 {
            let dx = x + 0.5 - cx;
            let dy = y + 0.5 - cy;
            if dx * dx + dy * dy <= radius * radius { grid.cells[y * grid.w + x] = 1; }
            x++;
        }
        y++;
    }
}

// In document units. A radius under one cell could let the flood slip between diagonal cells.
fn stamp_line(grid: Grid&, ax: f32, ay: f32, bx: f32, by: f32, width: f32) {
    let cells: f32 = FILL_CELLS_PER_UNIT;
    let radius = max(1.0, width * 0.5 * cells);
    let steps = max(1, ceil((abs(bx - ax) + abs(by - ay)) * cells) as! i64);
    var step = 0;
    while step <= steps {
        let t = step as f32 / steps;
        stamp_disc(grid, (ax + (bx - ax) * t) * cells, (ay + (by - ay) * t) * cells, radius);
        step++;
    }
}

fn distance_to_segment(x: f32, y: f32, a: Point, b: Point) -> f32, f32, f32 {
    let dx = b.x - a.x;
    let dy = b.y - a.y;
    let length = dx * dx + dy * dy;
    let t = if length > 0.0 { clamp(((x - a.x) * dx + (y - a.y) * dy) / length, 0.0, 1.0) } else { 0.0 };
    let near_x = a.x + dx * t;
    let near_y = a.y + dy * t;
    return sqrt((x - near_x) * (x - near_x) + (y - near_y) * (y - near_y)), near_x, near_y;
}

// Walls off the gap between a loose stroke end and the closest other line, if one is near enough.
// Parts of the end's own stroke only count once they're well along it, or it would bridge to itself.
fn bridge_stroke_end(walls: Grid&, points: const Point[:], first: i64, last: i64, from_start: bool) {
    let end = points[if from_start { first } else { last }];
    var best = FILL_SNAP;
    var best_x: f32 = 0.0;
    var best_y: f32 = 0.0;
    var found = false;
    var along: f32 = 0.0;
    var travelled: f32 = 0.0;
    if !from_start {
        var i = first + 1;
        while i <= last { travelled += abs(points[i].x - points[i - 1].x) + abs(points[i].y - points[i - 1].y); i++; }
    }
    for i in 1..points.len {
        let p = points[i];
        if p.start || p.width == FILL_WIDTH { continue; }
        let own = i > first && i <= last;
        if own {
            along += abs(p.x - points[i - 1].x) + abs(p.y - points[i - 1].y);
            if abs(along - travelled) < FILL_SNAP * 4.0 { continue; }
        }
        let distance, x, y = distance_to_segment(end.x, end.y, points[i - 1], p);
        let gap = distance - (end.width + p.width) * 0.5;
        if gap < best { best = gap; best_x = x; best_y = y; found = true; }
    }
    if found { stamp_line(walls, end.x, end.y, best_x, best_y, end.width); }
}

fn bridge_gaps(walls: Grid&, points: const Point[:]) {
    var first = 0;
    while first < points.len {
        var last = first;
        while last + 1 < points.len && !points[last + 1].start { last++; }
        if last > first && points[first].width != FILL_WIDTH {
            bridge_stroke_end(walls, points, first, last, true);
            bridge_stroke_end(walls, points, first, last, false);
        }
        first = last + 1;
    }
}

// Returns the flooded cells, or false if the flood reached the canvas edge and so isn't enclosed.
fn flood(walls: const Grid&, start: i64, region: Grid&, queue: i32[>..]&) -> bool {
    region.cells.resize(0);
    region.cells.resize(walls.w * walls.h, 0);
    queue.clear();
    queue.push(start as! i32);
    region.cells[start] = 1;
    var head = 0;
    while head < queue.len {
        let cell = queue[head] as i64;
        head++;
        let x = cell % walls.w;
        let y = cell / walls.w;
        if x == 0 || y == 0 || x == walls.w - 1 || y == walls.h - 1 { return false; }
        let neighbours: i64[4] = [cell - 1, cell + 1, cell - walls.w, cell + walls.w];
        for next in neighbours {
            if walls.cells[next] == 0 && region.cells[next] == 0 {
                region.cells[next] = 1;
                queue.push(next as! i32);
            }
        }
    }
    return true;
}

fn fill_small_holes(grid: Grid&) {
    var seen = Grid { grid.w, grid.h, [] };
    seen.cells.append(grid.cells);
    var queue: i32[>..] = [];
    for start in grid.cells.len {
        if seen.cells[start] != 0 { continue; }
        queue.clear();
        queue.push(start as! i32);
        seen.cells[start] = 1;
        var enclosed = true;
        var head = 0;
        while head < queue.len {
            let cell = queue[head] as i64;
            head++;
            let x = cell % grid.w;
            let y = cell / grid.w;
            if x == 0 || y == 0 || x == grid.w - 1 || y == grid.h - 1 { enclosed = false; continue; }
            let neighbours: i64[4] = [cell - 1, cell + 1, cell - grid.w, cell + grid.w];
            for next in neighbours {
                if seen.cells[next] == 0 { seen.cells[next] = 1; queue.push(next as! i32); }
            }
        }
        if enclosed && queue.len <= FILL_MAX_HOLE_CELLS {
            for cell in queue { grid.cells[cell as i64] = 1; }
        }
    }
}

fn fill_region(points: Point[>..]&, visible: i64&, ranges: FillRange[>..]&, document: Bounds,
               x: f32, y: f32, ink: u8[4]) -> FillResult {
    let cells: f32 = FILL_CELLS_PER_UNIT;
    let gw = max(1, ceil(document.w * cells) as! i64);
    let gh = max(1, ceil(document.h * cells) as! i64);
    var walls = Grid { gw, gh, [] };
    walls.cells.resize(gw * gh, 0);
    // Earlier fills are not walls, so a filled shape can be filled again in a new colour.
    for i in visible {
        let p = points[i];
        if p.width == FILL_WIDTH { continue; }
        if p.start { stamp_line(walls, p.x, p.y, p.x, p.y, p.width); }
        else { stamp_line(walls, points[i - 1].x, points[i - 1].y, p.x, p.y, p.width); }
    }
    let start = clamp(floor(y * cells) as! i64, 0, gh - 1) * gw + clamp(floor(x * cells) as! i64, 0, gw - 1);
    if walls.cells[start] != 0 { return FillResult.OnInk; }

    var region = Grid { gw, gh, [] };
    var queue: i32[>..] = [];
    // Try the lines exactly as drawn first, so bridging can never cut a closed shape in two.
    if !flood(walls, start, region, queue) {
        bridge_gaps(walls, points[..visible]);
        if walls.cells[start] != 0 { return FillResult.OnInk; }
        if !flood(walls, start, region, queue) { return FillResult.OpenShape; }
    }

    // Grow one cell, so the fill tucks under the outline instead of leaving a hairline beside it.
    var grown = Grid { gw, gh, [] };
    grown.cells.append(region.cells);
    for cell in queue {
        let c = cell as i64;
        if region.cells[c - 1] == 0 || region.cells[c + 1] == 0 || region.cells[c - gw] == 0 || region.cells[c + gw] == 0 {
            stamp_disc(grown, (c % gw) + 0.5, (c / gw) + 0.5, 1.5);
        }
    }

    fill_small_holes(grown);

    var added: Point[>..] = [];
    for row in gh {
        let py = row / cells;
        var cx = 0;
        while cx < gw {
            if grown.cells[row * gw + cx] == 0 { cx++; continue; }
            let run = cx;
            while cx < gw && grown.cells[row * gw + cx] != 0 { cx++; }
            added.push(Point { run / cells, py, FILL_WIDTH, ink, true });
            added.push(Point { cx / cells, py, FILL_WIDTH, ink, false });
        }
    }
    if added.len == 0 { return FillResult.OnInk; }
    if visible + added.len > MAX_POINTS { return FillResult.NoRoom; }
    points.resize(visible);
    drop_undone_fills(ranges, visible);
    ranges.push(FillRange { visible, visible + added.len });
    points.append(added);
    visible = points.len;
    return FillResult.Filled;
}

// The colour on screen at a canvas position: lines are drawn over fills, and newer over older.
fn color_at(points: const Point[:], x: f32, y: f32) -> u8[4], bool {
    var i = points.len;
    while i > 0 {
        i--;
        let p = points[i];
        if fill_row_height(p.width) > 0.0 { continue; }
        let distance, near_x, near_y = distance_to_segment(x, y, if p.start { p } else { points[i - 1] }, p);
        if distance <= max(p.width * 0.5, 0.004) { return p.color, true; }
    }
    i = points.len;
    while i > 0 {
        i--;
        let p = points[i];
        let row_height = fill_row_height(p.width);
        if row_height == 0.0 || p.start { continue; }
        let last = points[i - 1];
        if y >= p.y && y < p.y + row_height && x >= min(last.x, p.x) && x <= max(last.x, p.x) { return p.color, true; }
    }
    return [0, 0, 0, 255], false;
}

fn drop_undone_fills(ranges: FillRange[>..]&, visible: i64) {
    while ranges.len > 0 && ranges[ranges.len - 1].end > visible { ranges.resize(ranges.len - 1); }
}

// A fill is many strokes on disk, but one step for Undo and Redo.
fn undo_position(points: const Point[:], visible: i64, ranges: const FillRange[:]) -> i64 {
    var v = visible - 1;
    while v > 0 && !points[v].start { v--; }
    for r in ranges { if v > r.first && v < r.end { return r.first; } }
    return v;
}

fn redo_position(points: const Point[:], visible: i64, ranges: const FillRange[:]) -> i64 {
    var v = visible + 1;
    while v < points.len && !points[v].start { v++; }
    for r in ranges { if v > r.first && v < r.end { return r.end; } }
    return v;
}
