import std;
import math;
import os;
import reef_model;
import canvas_view;
import reef_fill;
import reef_color;
import reef_shapes;

fn add_circle(points: Point[>..]&, cx: f32, cy: f32, r: f32, gap_turns: f32, ink: u8[4]) {
    for i in 65 {
        let t = i / 64.0 * (1.0 - gap_turns);
        points.push(Point { cx + cos(t * 6.2831853) * r, cy + sin(t * 6.2831853) * r, 0.008, ink, i == 0 });
    }
}

fn fill_covers(points: const Point[:], x: f32, y: f32) -> bool {
    for i in 1..points.len {
        let p = points[i];
        if p.width == FILL_WIDTH && !p.start && abs(p.y - y) < 0.002 && x >= points[i - 1].x && x <= p.x { return true; }
    }
    return false;
}

fn check_fill() {
    assert(fill_row_height(FILL_WIDTH) > 0.0 && fill_row_height(LEGACY_FILL_WIDTH) > fill_row_height(FILL_WIDTH));
    assert(fill_row_height(2.0 / 16384.0) == 0.0);
    let document = Bounds { 0.0, 0.0, 1.0, 0.7 };
    let red: u8[4] = [255, 0, 0, 255];
    let blue: u8[4] = [0, 0, 255, 255];
    var points: Point[>..] = [];
    var ranges: FillRange[>..] = [];
    add_circle(points, 0.3, 0.3, 0.1, 0.0, red);
    var visible = points.len;
    let outline = visible;

    // Outside a closed circle, or on its ink, nothing is added.
    assert(fill_region(points, visible, ranges, document, 0.7, 0.3, blue) == FillResult.OpenShape);
    assert(fill_region(points, visible, ranges, document, 0.4, 0.3, blue) == FillResult.OnInk);
    assert(visible == outline && points.len == outline && ranges.len == 0);

    // Inside: the fill reaches the outline, stays inside it, and passes the save validator.
    assert(fill_region(points, visible, ranges, document, 0.3, 0.3, blue) == FillResult.Filled);
    assert(visible == points.len && visible > outline && ranges.len == 1 && valid_points(points));
    var top: f32 = 1.0;
    var bottom: f32 = 0.0;
    var left: f32 = 1.0;
    var right: f32 = 0.0;
    for i in outline..visible {
        let p = points[i];
        assert(p.color == blue);
        top = min(top, p.y); bottom = max(bottom, p.y); left = min(left, p.x); right = max(right, p.x);
    }
    assert(top > 0.19 && top < 0.215 && bottom < 0.41 && bottom > 0.385);
    assert(left > 0.19 && left < 0.215 && right < 0.41 && right > 0.385);

    // One Undo removes the whole fill, one Redo restores it, and the fill can be recoloured.
    let filled = visible;
    visible = undo_position(points, visible, ranges);
    assert(visible == outline);
    visible = redo_position(points, visible, ranges);
    assert(visible == filled);
    assert(fill_region(points, visible, ranges, document, 0.3, 0.3, red) == FillResult.Filled);
    assert(ranges.len == 2 && points[visible - 1].color == red);
    visible = undo_position(points, visible, ranges);
    assert(visible == filled);
    visible = undo_position(points, visible, ranges);
    assert(visible == outline);
    visible = undo_position(points, visible, ranges);
    assert(visible == 0);

    // Redo history is dropped once something new replaces it.
    visible = outline;
    assert(fill_region(points, visible, ranges, document, 0.3, 0.3, blue) == FillResult.Filled);
    assert(ranges.len == 1 && ranges[0].first == outline && visible == points.len);

    // A small gap in the outline is forgiven; a big one is not.
    var nearly: Point[>..] = [];
    var nearly_ranges: FillRange[>..] = [];
    add_circle(nearly, 0.3, 0.3, 0.1, 0.015, red);
    var nearly_visible = nearly.len;
    assert(fill_region(nearly, nearly_visible, nearly_ranges, document, 0.3, 0.3, blue) == FillResult.Filled);
    var open: Point[>..] = [];
    var open_ranges: FillRange[>..] = [];
    add_circle(open, 0.3, 0.3, 0.1, 0.2, red);
    var open_visible = open.len;
    assert(fill_region(open, open_visible, open_ranges, document, 0.3, 0.3, blue) == FillResult.OpenShape);
    assert(open.len == 65);

    // A narrow shape fills end to end, even when its outline is left slightly open.
    let thin: f32 = 2.0 / 1808.0;
    for open_end in [false, true] {
        var fin: Point[>..] = [];
        var fin_ranges: FillRange[>..] = [];
        let tips: f32[2][4] = [[0.20, 0.20], [0.40, 0.22], [0.40, 0.235], [0.20, 0.215]];
        for i in 4 { fin.push(Point { tips[i][0], tips[i][1], thin, red, i == 0 }); }
        // Closed, or stopping about 1% of the canvas short of where it began.
        fin.push(Point { 0.20, if open_end { 0.205 } else { 0.20 }, thin, red, false });
        var fin_visible = fin.len;
        assert(fill_region(fin, fin_visible, fin_ranges, document, 0.38, 0.228, blue) == FillResult.Filled);
        var far_left: f32 = 1.0;
        var far_right: f32 = 0.0;
        for i in 5..fin_visible {
            far_left = min(far_left, fin[i].x);
            far_right = max(far_right, fin[i].x);
        }
        assert(far_left < 0.215 && far_right > 0.395);
    }

    // Two strokes that nearly meet at both ends count as one closed shape.
    var parts: Point[>..] = [];
    var parts_ranges: FillRange[>..] = [];
    for i in 33 { let t: f32 = i * 3.1415927 / 32.0; parts.push(Point { 0.5 + cos(t) * 0.1, 0.3 - sin(t) * 0.1, 0.008, red, i == 0 }); }
    for i in 33 { let t: f32 = i * 3.1415927 / 32.0; parts.push(Point { 0.385 + cos(t * 0.0) * 0.015 + t * 0.0605, 0.315 + sin(t) * 0.1, 0.008, red, i == 0 }); }
    var parts_visible = parts.len;
    assert(fill_region(parts, parts_visible, parts_ranges, document, 0.5, 0.3, blue) == FillResult.Filled);

    // A dot inside the shape gets fill underneath it, but a large hole like a donut's stays empty.
    var eyed: Point[>..] = [];
    var eyed_ranges: FillRange[>..] = [];
    add_circle(eyed, 0.3, 0.3, 0.1, 0.0, red);
    eyed.push(Point { 0.3, 0.3, 0.02, blue, true });
    var eyed_visible = eyed.len;
    assert(fill_region(eyed, eyed_visible, eyed_ranges, document, 0.25, 0.3, red) == FillResult.Filled);
    assert(fill_covers(eyed[..eyed_visible], 0.3, 0.3));
    var donut: Point[>..] = [];
    var donut_ranges: FillRange[>..] = [];
    add_circle(donut, 0.3, 0.3, 0.2, 0.0, red);
    add_circle(donut, 0.3, 0.3, 0.08, 0.0, red);
    var donut_visible = donut.len;
    assert(fill_region(donut, donut_visible, donut_ranges, document, 0.15, 0.3, blue) == FillResult.Filled);
    assert(fill_covers(donut[..donut_visible], 0.15, 0.3) && !fill_covers(donut[..donut_visible], 0.3, 0.3));

    // A tiny closed shape can still be filled by itself, on top of the fill around it.
    var tiny: Point[>..] = [];
    var tiny_ranges: FillRange[>..] = [];
    for i in 17 { let t: f32 = i * 6.2831853 / 16.0; tiny.push(Point { 0.3 + cos(t) * 0.008, 0.3 + sin(t) * 0.008, 0.0015, red, i == 0 }); }
    var tiny_visible = tiny.len;
    assert(fill_region(tiny, tiny_visible, tiny_ranges, document, 0.3, 0.3, blue) == FillResult.Filled);
    assert(fill_covers(tiny[..tiny_visible], 0.3, 0.3) && !fill_covers(tiny[..tiny_visible], 0.32, 0.3));

    // A filled canvas that cannot fit the new points is left untouched.
    var full: Point[>..] = [];
    var full_ranges: FillRange[>..] = [];
    add_circle(full, 0.3, 0.3, 0.2, 0.0, red);
    while full.len < MAX_POINTS { full.push(Point { 0.9, 0.6, 0.002, red, true }); }
    var full_visible = full.len;
    assert(fill_region(full, full_visible, full_ranges, document, 0.3, 0.3, blue) == FillResult.NoRoom);
    assert(full.len == MAX_POINTS && full_visible == MAX_POINTS && full_ranges.len == 0);
}

fn check_color() {
    let samples: u8[4][8] = [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [81, 30, 147, 255],
                             [224, 135, 190, 255], [18, 200, 77, 255], [255, 255, 0, 255], [1, 2, 3, 255]];
    for c in samples {
        assert(hsv_to_rgb(rgb_to_hsv(c, 0.0)) == c);
        let parsed, ok = parse_hex(color_hex(c));
        assert(ok && parsed == c);
    }
    let hex = color_hex([81, 30, 147, 255]);
    assert(hex[0..6] == "511E93");
    let lower, lower_ok = parse_hex("e087be");
    assert(lower_ok && lower[0] == 224 && lower[1] == 135 && lower[2] == 190);
    let a0, bad_short = parse_hex("12345");
    let a1, bad_digit = parse_hex("12345G");
    assert(!bad_short && !bad_digit);
    // Greys keep the picker's hue, and hue 1.0 wraps round to red.
    assert(rgb_to_hsv([128, 128, 128, 255], 0.6).h == 0.6);
    let wrapped: u8[4] = [255, 0, 0, 255];
    assert(hsv_to_rgb(Hsv { 1.0, 1.0, 1.0 }) == wrapped);
}

fn check_shapes() {
    let document = Bounds { 0.0, 0.0, 1.0, 0.7 };
    let red: u8[4] = [255, 0, 0, 255];
    let blue: u8[4] = [0, 0, 255, 255];
    let kinds: Tool[7] = [Tool.Rectangle, Tool.Circle, Tool.Triangle, Tool.Diamond, Tool.Hexagon, Tool.Star, Tool.Heart];
    for kind in kinds {
        var points: Point[>..] = [];
        var ranges: FillRange[>..] = [];
        var visible = 0;
        // Dragged backwards on purpose: shapes must come out the same either way.
        assert(add_shape(points, visible, ranges, kind, 0.6, 0.5, 0.2, 0.1, 0.005, red));
        assert(visible == points.len && visible > 8 && valid_points(points));
        assert(points[0].x == points[visible - 1].x && points[0].y == points[visible - 1].y);
        var left: f32 = 1.0;
        var right: f32 = 0.0;
        var top: f32 = 1.0;
        var bottom: f32 = 0.0;
        var starts = 0;
        for p in points {
            left = min(left, p.x); right = max(right, p.x); top = min(top, p.y); bottom = max(bottom, p.y);
            if p.start { starts++; }
        }
        assert(starts == 1);
        assert(abs(left - 0.2) < 0.001 && abs(right - 0.6) < 0.001 && abs(top - 0.1) < 0.001 && abs(bottom - 0.5) < 0.001);
        // Every shape is really closed: its centre fills, and outside it doesn't.
        assert(fill_region(points, visible, ranges, document, 0.4, 0.3, blue) == FillResult.Filled);
        assert(fill_region(points, visible, ranges, document, 0.8, 0.6, blue) == FillResult.OpenShape);
        assert(undo_position(points, visible, ranges) > 0);
        var undone = undo_position(points, visible, ranges);
        undone = undo_position(points, undone, ranges);
        assert(undone == 0);
    }
    var line: Point[>..] = [];
    var line_ranges: FillRange[>..] = [];
    var line_visible = 0;
    assert(add_shape(line, line_visible, line_ranges, Tool.Line, 0.5, 0.5, 0.2, 0.1, 0.005, red));
    assert(line[0].x == 0.5 && line[0].y == 0.5 && abs(line[line_visible - 1].x - 0.2) < 0.001 && abs(line[line_visible - 1].y - 0.1) < 0.001);
    // A click without a drag adds nothing, and a full canvas refuses without changing anything.
    var empty: Point[>..] = [];
    var empty_ranges: FillRange[>..] = [];
    var empty_visible = 0;
    assert(add_shape(empty, empty_visible, empty_ranges, Tool.Star, 0.5, 0.5, 0.5, 0.5, 0.005, red) && empty.len == 0);
    while empty.len < MAX_POINTS { empty.push(Point { 0.9, 0.6, 0.002, red, true }); }
    empty_visible = empty.len;
    assert(!add_shape(empty, empty_visible, empty_ranges, Tool.Star, 0.1, 0.1, 0.3, 0.3, 0.005, red));
    assert(empty.len == MAX_POINTS);
    // Shift: equal sides in any drag direction, shrinking to stay on the canvas.
    let sx, sy = constrain_square(0.5, 0.3, 0.6, 0.35, document);
    assert(abs(sx - 0.6) < 0.001 && abs(sy - 0.4) < 0.001);
    let bx, by = constrain_square(0.5, 0.3, 0.2, 0.25, document);
    assert(abs(bx - 0.2) < 0.001 && abs(by - 0.0) < 0.001);
    let ex, ey = constrain_square(0.9, 0.6, 1.0, 0.7, document);
    assert(ex <= 1.0 && ey <= 0.7 + 0.0001 && abs((ex - 0.9) - (ey - 0.6)) < 0.001);
    // The eyedropper sees lines first, then fills, and nothing outside the drawing.
    var pick: Point[>..] = [];
    var pick_ranges: FillRange[>..] = [];
    var pick_visible = 0;
    assert(add_shape(pick, pick_visible, pick_ranges, Tool.Rectangle, 0.2, 0.1, 0.6, 0.5, 0.01, red));
    assert(fill_region(pick, pick_visible, pick_ranges, document, 0.4, 0.3, blue) == FillResult.Filled);
    let on_fill, fill_found = color_at(pick[..pick_visible], 0.4, 0.3);
    let on_line, line_found = color_at(pick[..pick_visible], 0.2, 0.3);
    let outside, outside_found = color_at(pick[..pick_visible], 0.8, 0.6);
    assert(fill_found && on_fill == blue && line_found && on_line == red && !outside_found);
}

fn main() {
    check_color();
    check_shapes();
    check_fill();
    var specimens: Creature[>..] = [];
    let fish .= specimens.push(Creature { x: 0.95, y: 0.5, speed: 0.1, phase: 0.0, points: [] });
    update(fish, 1.0, 1.0);
    assert(abs(fish.x - 0.05) < 0.001 && fish.speed == 0.1);
    fish.x = 1.0;
    assert(creature_area(fish, 1100.0, 760.0).x >= 1100.0);
    fish.x = 0.05;
    fish.speed = -0.1;
    update(fish, 1.0, -1.0);
    assert(abs(fish.x - 0.95) < 0.001 && fish.speed == -0.1);
    fish.x = 0.0;
    let gone_left = creature_area(fish, 1100.0, 760.0);
    assert(gone_left.x + gone_left.w <= 0.0);
    fish.x = 0.5;
    for index in 12 {
        var swimmer = Creature { x: 0.5, y: 0.5, speed: 0.1, phase: 0.0, points: [] };
        var turns = 0;
        var back_to_back = 0;
        var last_turn: f32 = 0.0;
        var clock_now: f32 = 0.0;
        while clock_now < 3600.0 {
            let speed_before = swimmer.speed;
            maybe_turn(swimmer, index, clock_now, clock_now + 0.1);
            clock_now += 0.1;
            if swimmer.speed != speed_before {
                assert(clock_now - last_turn >= 9.9); // Never twice in quick succession, nor right at startup.
                if clock_now - last_turn < 16.0 { back_to_back++; }
                last_turn = clock_now;
                turns++;
            }
        }
        assert(turns >= 40 && turns <= 200); // Roughly one turn every 20-90 seconds.
        assert(back_to_back * 2 < turns); // Evenly scattered, not bursts of turning then long straight runs.
    }
    assert(turn_facing(0.0) == -1.0 && turn_facing(1.0) == 1.0 && abs(turn_facing(0.5)) < 0.001);
    // Told to go left while heading right: carries on, slows to a stop, then swims back without ever jumping.
    var turner = Creature { x: 0.5, y: 0.5, speed: -0.1, phase: 0.0, points: [] };
    var heading: f32 = 1.0;
    var furthest = turner.x;
    var turn_time: f32 = 0.0;
    while heading > 0.0 {
        let from = turner.x;
        heading = step_heading(heading, turner.speed, 0.05);
        update(turner, 0.05, turn_facing(heading));
        turn_time += 0.05;
        assert(abs(turner.x - from) <= 0.1 * 0.05 + 0.00001);
        furthest = max(furthest, turner.x);
    }
    assert(abs(turn_time - TURN_SECONDS) < 0.06);
    assert(furthest > 0.5 && turner.x < furthest);
    assert(step_heading(1.0, 0.1, 0.05) == 1.0 && step_heading(0.0, -0.1, 0.05) == 0.0);
    // Swimming normally there's no perspective at all, so creatures keep their fixed size.
    let rests: f32[2] = [0.0, 1.0];
    for rest in rests {
        let flat = turn_view(rest, 136.0);
        assert(abs(turn_nearness(flat, 68.0) - 1.0) < 0.0001 && abs(turn_nearness(flat, -68.0) - 1.0) < 0.0001);
    }
    assert(turn_view(1.0, 136.0).across == 1.0 && turn_view(0.0, 136.0).across == -1.0);
    // Facing into the screen: smaller overall, with the head further away than the tail.
    let apex = turn_view(0.5, 136.0);
    assert(turn_nearness(apex, 0.0) < 0.8);
    assert(turn_nearness(apex, 68.0) < turn_nearness(apex, 0.0) && turn_nearness(apex, 0.0) < turn_nearness(apex, -68.0));
    assert(abs(apex.across) == 0.15);
    var at_edge = Creature { x: 0.1, y: 0.5, speed: 0.1, phase: 0.0, points: [] };
    var edge_clock: f32 = 0.0;
    while edge_clock < 600.0 { maybe_turn(at_edge, 0, edge_clock, edge_clock + 0.1); edge_clock += 0.1; }
    assert(at_edge.speed == 0.1);
    let a .= specimens.push(Creature { x: 0.4, y: 0.5, speed: 0.1, phase: 0.0, points: [] });
    let b .= specimens.push(a);
    update(a, 0.1, 1.0);
    for i in 10 { update(b, 0.01, 1.0); }
    assert(abs(a.x - b.x) < 0.00001);
    let speed = a.speed;
    let phase = a.phase;
    move_creature(a, 700.0, 450.0, 1100.0, 760.0);
    let placed = creature_area(a, 1100.0, 760.0);
    assert(abs(placed.x + placed.w * 0.5 - 700.0) < 0.001);
    assert(abs(placed.y + placed.h * 0.5 - 450.0) < 0.001);
    move_creature(a, -1000.0, 5000.0, 1100.0, 760.0);
    assert(abs(creature_area(a, 1100.0, 760.0).x) < 0.001);
    assert(a.y == 0.9 && a.speed == speed && a.phase == phase);
    move_creature(a, 5000.0, -1000.0, 20.0, 20.0);
    let dropped = creature_area(a, 20.0, 20.0);
    assert(abs(dropped.x + dropped.w - 20.0) < 0.001 && a.y == 0.1);
    let small .= specimens.push(Creature { x: 0.5, y: 0.5, speed: 0.05, phase: 0.0, size: 0.1, points: [] });
    let large .= specimens.push(Creature { x: 0.5, y: 0.5, speed: 0.05, phase: 0.0, size: 0.7, points: [] });
    assert(creature_area(large, 1100.0, 760.0).w == creature_area(small, 1100.0, 760.0).w);
    move_creature(large, 100000.0, 100000.0, 1100.0, 760.0);
    let large_area = creature_area(large, 1100.0, 760.0);
    assert(large_area.x >= 0.0 && large_area.x + large_area.w <= 1100.0);
    assert(large_area.y >= 82.0 && large_area.y + large_area.h <= 682.0);
    move_creature(small, 650.0, 400.0, 1100.0, 760.0);
    let moved_small = creature_area(small, 1100.0, 760.0);
    assert(abs(moved_small.x + moved_small.w * 0.5 - 650.0) < 0.001);
    assert(abs(moved_small.y + moved_small.h * 0.5 - 400.0) < 0.001);

    let viewport = Bounds { 20.0, 98.0, 800.0, 550.0 };
    let document = canvas_document(1100.0 / 760.0);
    var view = CanvasView {};
    let fitted = canvas_area(view, viewport, document);
    assert(fitted.x == viewport.x && fitted.y == viewport.y);
    assert(fitted.w <= viewport.w + 0.001 && fitted.h <= viewport.h + 0.001);
    assert(abs(fitted.w / fitted.h - 1100.0 / 760.0) < 0.001);
    let pivot_x = viewport.x + fitted.w * 0.5;
    let pivot_y = viewport.y + fitted.h * 0.5;
    zoom_canvas(view, viewport, document, pivot_x, pivot_y, 2.0);
    let zoomed = canvas_area(view, viewport, document);
    assert(abs((pivot_x - zoomed.x) / zoomed.w - 0.5) < 0.001);
    assert(abs((pivot_y - zoomed.y) / zoomed.h - 0.5) < 0.001);
    pan_canvas(view, viewport, document, -100000.0, -100000.0);
    let panned = canvas_area(view, viewport, document);
    assert(panned.x + panned.w >= viewport.x + viewport.w - 0.001);
    assert(panned.y + panned.h >= viewport.y + viewport.h - 0.001);
    zoom_canvas(view, viewport, document, pivot_x, pivot_y, 100000.0);
    assert(view.zoom == 16.0);
    zoom_canvas(view, viewport, document, pivot_x, pivot_y, 0.000001);
    assert(view.zoom == 0.25);
    let x0, y0, x1, y1, crosses = clip_line(-100000.0, 25.0, 100000.0, 25.0, Bounds { 0.0, 0.0, 100.0, 50.0 }, 0.0);
    assert(crosses && abs(x0) < 0.01 && abs(x1 - 100.0) < 0.01 && y0 == 25.0 && y1 == 25.0);
    let ax, ay, bx, by, outside = clip_line(-100.0, -10.0, 100.0, -10.0, Bounds { 0.0, 0.0, 100.0, 50.0 }, 0.0);
    assert(!outside);

    let ink: u8[4] = [255, 180, 80, 255];
    var stroke: Point[>..] = [];
    var visible = 0;
    var drawing = false;
    sample_stroke(stroke, visible, drawing, true, true, true, 0.2, 0.3, 0.02, ink);
    sample_stroke(stroke, visible, drawing, true, false, false, 1.2, 0.4, 0.02, ink);
    sample_stroke(stroke, visible, drawing, true, false, true, 0.8, 0.6, 0.02, ink);
    assert(visible == 2 && stroke[0].start && !stroke[1].start);
    assert(valid_points(stroke));
    sample_stroke(stroke, visible, drawing, false, false, false, 1.2, 0.5, 0.02, ink);
    sample_stroke(stroke, visible, drawing, true, false, true, 0.4, 0.4, 0.02, ink);
    assert(visible == 2 && !drawing);
    sample_stroke(stroke, visible, drawing, true, true, true, 0.4, 0.4, 0.02, ink);
    assert(visible == 3 && stroke[2].start);
    let points: Point[2] = [Point { 0.2, 0.3, 0.02, ink, true },
                            Point { 0.8, 0.6, 0.02, ink, false }];
    let bounds = drawing_bounds(points);
    assert(bounds.x < 0.2 && bounds.y < 0.3);
    assert(bounds.x + bounds.w > 0.8 && bounds.y + bounds.h > 0.6);
    assert(bounds.w >= bounds.h);
    let tiny_ink: Point[2] = [Point { 0.50, 0.5, 0.002, ink, true }, Point { 0.52, 0.5, 0.002, ink, false }];
    let big_ink: Point[2] = [Point { 0.10, 0.5, 0.02, ink, true }, Point { 0.30, 0.5, 0.02, ink, false }];
    assert(abs(drawing_bounds(big_ink).w - drawing_bounds(tiny_ink).w * 10.0) < 0.0001);
    assert(valid_points(points));
    var bad = points;
    bad[0].x = 2.0;
    assert(!valid_points(bad));

    var reef: Creature[>..] = [];
    fish.points.append(points);
    var legacy: LegacyCreature[>..] = [];
    legacy.push(LegacyCreature { x: fish.x, y: fish.y, speed: fish.speed, phase: fish.phase, points: points });
    var old_image: u8[>..] = [];
    old_image.append(LEGACY_SAVE_HEADER); old_image.append(to_bytes(legacy));
    let migrated, migration_ok = decode_reef(old_image);
    assert(migration_ok && migrated.len == 1 && migrated[0].size == 0.0);
    assert(migrated[0].points.len == 2 && migrated[0].points[1].x == points[1].x);
    assert(creature_area(migrated[0], 1100.0, 760.0).w == creature_area(fish, 1100.0, 760.0).w);
    small.points.append(points);
    var sized: Creature[>..] = [];
    sized.push(small);
    let restored_size, size_ok = decode_reef(encode_reef(sized));
    assert(size_ok && restored_size[0].size == small.size);
    for i in 3 { reef.push(fish); }
    let image = encode_reef(reef);
    let restored, ok = decode_reef(image);
    assert(ok && restored.len == 3);
    assert(restored[0].points.len == 2 && restored[0].points[1].color == ink);
    assert(restored[0].points[1].x == points[1].x);
    var corrupt = copy(image);
    corrupt[0] = 0;
    let rejected, accepted = decode_reef(corrupt);
    assert(!accepted && rejected.len == 0);
    let truncated, truncated_ok = decode_reef(image[..8]);
    assert(!truncated_ok && truncated.len == 0);
    let test_dir = str(resource_dir(), ".test-data");
    let test_path = str(test_dir, "/round-trip.reef");
    assert(make_dir(test_dir));
    assert(write_file_atomic(test_path, image));
    var disk: u8[>..] = [];
    assert(read_file(test_path, disk));
    let from_disk, disk_ok = decode_reef(disk);
    assert(disk_ok && from_disk.len == 3 && from_disk[2].points[1].color == ink);
    let original .= specimens.push(reef[0]);
    assert(!flip_creature(reef, -1, test_path));
    assert(!flip_creature(reef, reef.len, test_path));
    assert(!flip_creature(reef, 0, test_dir));
    assert(reef[0].points == original.points);
    assert(flip_creature(reef, 0, test_path));
    assert(reef[0].points[0].x == 1.0 - original.points[0].x);
    assert(reef[0].points[1].color == original.points[1].color);
    assert(reef[0].points[0].start && !reef[0].points[1].start);
    assert(reef[0].speed == original.speed && reef[0].phase == original.phase);
    disk.clear();
    assert(read_file(test_path, disk));
    let flipped, flip_ok = decode_reef(disk);
    assert(flip_ok && flipped.len == 3 && flipped[0].points == reef[0].points);
    assert(flip_creature(reef, 0, test_path));
    assert(abs(reef[0].points[0].x - original.points[0].x) < 0.00001);
    let area = creature_area(reef[0], 1100.0, 760.0);
    assert(pick_creature(reef, area.x + area.w * 0.5, area.y + area.h * 0.5, 1100.0, 760.0) == 2);
    assert(pick_creature(reef, 0.0, 0.0, 1100.0, 760.0) == -1);
    let resized = creature_area(reef[0], 640.0, 480.0);
    assert(pick_creature(reef, resized.x + resized.w * 0.5, resized.y + resized.h * 0.5, 640.0, 480.0) == 2);
    for i in reef.len { reef[i].x = 0.2 + i * 0.2; }
    assert(!delete_creature(reef, 0, test_dir) && reef.len == 3);
    assert(!delete_creature(reef, -1, test_path) && reef.len == 3);
    assert(!delete_creature(reef, reef.len, test_path) && reef.len == 3);
    assert(delete_creature(reef, 1, test_path) && reef.len == 2);
    assert(abs(reef[0].x - 0.2) < 0.0001 && abs(reef[1].x - 0.6) < 0.0001);
    disk.clear();
    assert(read_file(test_path, disk));
    let after_delete, delete_ok = decode_reef(disk);
    assert(delete_ok && after_delete.len == 2 && after_delete[1].x == reef[1].x);
    assert(delete_creature(reef, 0, test_path));
    assert(delete_creature(reef, 0, test_path) && reef.len == 0);
    disk.clear();
    assert(read_file(test_path, disk));
    let empty, empty_ok = decode_reef(disk);
    assert(empty_ok && empty.len == 0);
    assert(delete_file(test_path));
    print("PASS: movement, canvas zoom/pan, clipping, creature sizes, legacy saves, strokes, colors, shapes, fills, flips, persistence and deletion");
}
