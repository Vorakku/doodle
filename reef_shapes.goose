import std;
import math;
import vec;
import reef_model;
import reef_fill;

enum Tool { Draw, Fill, Line, Rectangle, Circle, Triangle, Diamond, Hexagon, Star, Heart }

let EDGE_PIECES: i64 = 8;
let CURVE_PIECES: i64 = 64;
// A click without a real drag shouldn't drop a speck on the canvas.
let MIN_SHAPE_DRAG: f32 = 0.004;

fn is_shape(tool: Tool) -> bool { tool != Tool.Draw && tool != Tool.Fill }

fn corners_of(tool: Tool) -> float2[>..] {
    var c: float2[>..] = [];
    if tool == Tool.Line { c.push(float2 { 0.0, 0.0 }); c.push(float2 { 1.0, 1.0 }); }
    else if tool == Tool.Rectangle {
        c.push(float2 { 0.0, 0.0 }); c.push(float2 { 1.0, 0.0 }); c.push(float2 { 1.0, 1.0 }); c.push(float2 { 0.0, 1.0 });
    } else if tool == Tool.Triangle {
        c.push(float2 { 0.5, 0.0 }); c.push(float2 { 1.0, 1.0 }); c.push(float2 { 0.0, 1.0 });
    } else if tool == Tool.Diamond {
        c.push(float2 { 0.5, 0.0 }); c.push(float2 { 1.0, 0.5 }); c.push(float2 { 0.5, 1.0 }); c.push(float2 { 0.0, 0.5 });
    } else if tool == Tool.Hexagon {
        c.push(float2 { 0.25, 0.0 }); c.push(float2 { 0.75, 0.0 }); c.push(float2 { 1.0, 0.5 });
        c.push(float2 { 0.75, 1.0 }); c.push(float2 { 0.25, 1.0 }); c.push(float2 { 0.0, 0.5 });
    } else if tool == Tool.Star {
        for i in 10 {
            let angle: f32 = i * 3.1415927 / 5.0 - 1.5707964;
            let radius: f32 = if i % 2 == 0 { 1.0 } else { 0.4 };
            c.push(float2 { cos(angle) * radius, sin(angle) * radius });
        }
    } else if tool == Tool.Circle {
        for i in CURVE_PIECES {
            let angle: f32 = i * 6.2831853 / CURVE_PIECES;
            c.push(float2 { cos(angle), sin(angle) });
        }
    } else if tool == Tool.Heart {
        for i in CURVE_PIECES {
            let t: f32 = i * 6.2831853 / CURVE_PIECES;
            let s = sin(t);
            c.push(float2 { 16.0 * s * s * s, -(13.0 * cos(t) - 5.0 * cos(t * 2.0) - 2.0 * cos(t * 3.0) - cos(t * 4.0)) });
        }
    }
    return c;
}

// The outline inside a unit box. Corners are subdivided so straight edges bend with the swim wave too.
fn shape_outline(tool: Tool) -> float2[>..] {
    let corners = corners_of(tool);
    var left: f32 = 1.0e9;
    var top: f32 = 1.0e9;
    var right: f32 = -1.0e9;
    var bottom: f32 = -1.0e9;
    for c in corners { left = min(left, c.x); top = min(top, c.y); right = max(right, c.x); bottom = max(bottom, c.y); }
    let curved = tool == Tool.Circle || tool == Tool.Heart;
    let pieces = if curved { 1 } else { EDGE_PIECES };
    let edges = if tool == Tool.Line { 1 } else { corners.len };
    var out: float2[>..] = [];
    for e in edges {
        let a = corners[e];
        let b = corners[(e + 1) % corners.len];
        for p in pieces {
            let t: f32 = p as f32 / pieces;
            out.push(float2 { (a.x + (b.x - a.x) * t - left) / (right - left), (a.y + (b.y - a.y) * t - top) / (bottom - top) });
        }
    }
    // Finish exactly where it began, or exactly on the far end for a line.
    if tool == Tool.Line { out.push(float2 { 1.0, 1.0 }); } else { out.push(out[0]); }
    return out;
}

fn shape_points(tool: Tool, x0: f32, y0: f32, x1: f32, y1: f32, width: f32, ink: u8[4]) -> Point[>..] {
    // A line keeps its drag direction; every other shape stays upright whichever way it's dragged.
    let left = if tool == Tool.Line { x0 } else { min(x0, x1) };
    let top = if tool == Tool.Line { y0 } else { min(y0, y1) };
    let w = if tool == Tool.Line { x1 - x0 } else { abs(x1 - x0) };
    let h = if tool == Tool.Line { y1 - y0 } else { abs(y1 - y0) };
    let outline = shape_outline(tool);
    var out: Point[>..] = [];
    for i in outline.len {
        out.push(Point { clamp(left + outline[i].x * w, 0.0, 1.0), clamp(top + outline[i].y * h, 0.0, 1.0), width, ink, i == 0 });
    }
    return out;
}

// Holding Shift makes both sides equal, shrinking if needed to stay on the canvas. Lines stay free.
fn constrain_square(x0: f32, y0: f32, x1: f32, y1: f32, document: Bounds) -> f32, f32 {
    let room_x = if x1 >= x0 { document.w - x0 } else { x0 };
    let room_y = if y1 >= y0 { document.h - y0 } else { y0 };
    let size = min(max(abs(x1 - x0), abs(y1 - y0)), min(room_x, room_y));
    return x0 + (if x1 >= x0 { size } else { -size }), y0 + (if y1 >= y0 { size } else { -size });
}

fn add_shape(points: Point[>..]&, visible: i64&, ranges: FillRange[>..]&, tool: Tool,
             x0: f32, y0: f32, x1: f32, y1: f32, width: f32, ink: u8[4]) -> bool {
    if abs(x1 - x0) + abs(y1 - y0) < MIN_SHAPE_DRAG { return true; }
    let shape = shape_points(tool, x0, y0, x1, y1, width, ink);
    if visible + shape.len > MAX_POINTS { return false; }
    drop_undone_fills(ranges, visible);
    points.resize(visible);
    points.append(shape);
    visible = points.len;
    return true;
}

fn tool_name(tool: Tool) -> const u8[:] {
    if tool == Tool.Draw { return "Draw"; }
    if tool == Tool.Fill { return "Fill"; }
    if tool == Tool.Line { return "Line"; }
    if tool == Tool.Rectangle { return "Rectangle"; }
    if tool == Tool.Circle { return "Circle"; }
    if tool == Tool.Triangle { return "Triangle"; }
    if tool == Tool.Diamond { return "Diamond"; }
    if tool == Tool.Hexagon { return "Hexagon"; }
    if tool == Tool.Star { return "Star"; }
    return "Heart";
}
