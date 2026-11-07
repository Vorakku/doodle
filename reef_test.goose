import std;
import math;
import os;
import reef_model;
import canvas_view;
import reef_fill;
import reef_color;
import reef_shapes;
import reef_growth;
import reef_image_data;

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

fn check_vertical_swimming() {
    var vertical_only = Creature { x: 0.4, y: 0.5, speed: 0.055, phase: 0.0, points: [] };
    var vertical_motion = SwimMotion {};
    for frame in 600 { swim(vertical_only, vertical_motion, 1.0 / 60.0, 0.0, 0); }
    assert(vertical_only.x == 0.4 && abs(vertical_only.y - 0.5) > 0.1);
    let speeds: f32[2] = [0.055, -0.055];
    let heights: f32[3] = [0.1, 0.5, 0.9];
    for speed in speeds {
        for start_y in heights {
            var fish = Creature { x: 0.4, y: start_y, speed: speed, phase: 0.0, points: [] };
            var motion = SwimMotion {};
            var highest = start_y;
            var lowest = start_y;
            var rose = false;
            var dipped = false;
            for frame in 7200 {
                let before = fish.y;
                let velocity = motion.vertical_speed;
                swim(fish, motion, 1.0 / 60.0, if speed < 0.0 { -1.0 } else { 1.0 }, 0);
                update_pitch(fish, motion, 1.0 / 60.0, 1100.0, 760.0);
                assert(abs(motion.pitch) <= 1.221731);
                assert(fish.y >= 0.1 && fish.y <= 0.9);
                assert(abs(fish.y - before) < 0.005);
                assert(abs(motion.vertical_speed - velocity) < 0.004);
                rose = rose || fish.y < before;
                dipped = dipped || fish.y > before;
                highest = min(highest, fish.y);
                lowest = max(lowest, fish.y);
            }
            assert(rose && dipped && lowest - highest > 0.25);
        }
    }
    var slow = Creature { x: 0.4, y: 0.5, speed: 0.055, phase: 0.0, points: [] };
    var fast = slow;
    var slow_motion = SwimMotion {};
    var fast_motion = SwimMotion {};
    for frame in 1800 { swim(slow, slow_motion, 1.0 / 30.0, 1.0, 0); }
    for frame in 7200 { swim(fast, fast_motion, 1.0 / 120.0, 1.0, 0); }
    assert(abs(slow.y - fast.y) < 0.002);
    let x_gap = abs(slow.x - fast.x);
    let phase_gap = abs(slow.phase - fast.phase);
    assert(min(x_gap, 1.0 - x_gap) < 0.003);
    assert(min(phase_gap, 6.2831853 - phase_gap) < 0.15);
    assert(abs(slow_motion.pace - fast_motion.pace) < 0.1);
    let height = slow.y;
    swim(slow, slow_motion, 0.0, 1.0, 0);
    assert(slow.y == height);
    var a = Creature { x: 0.2, y: 0.5, speed: 0.055, phase: 0.0, points: [] };
    var b = Creature { x: 0.8, y: 0.5, speed: -0.1, phase: 0.0, points: [] };
    var c = a;
    var ma = SwimMotion {};
    var mb = SwimMotion {};
    var mc = SwimMotion {};
    for frame in 600 {
        swim(a, ma, 1.0 / 60.0, 1.0, 0);
        swim(b, mb, 1.0 / 60.0, -1.0, 0);
        swim(c, mc, 1.0 / 60.0, 1.0, 1);
        if frame == 119 { assert(abs(a.x - 0.2) < 0.055 * 2.0 * 0.5); }
    }
    assert(a.y == b.y && abs(a.y - c.y) > 0.2);
}

fn check_pitch() {
    var fish = Creature { x: 0.5, y: 0.5, speed: 0.055, phase: 0.0, points: [] };
    var low_fps = SwimMotion { vertical_speed: -0.04 };
    var high_fps = low_fps;
    for frame in 60 { update_pitch(fish, low_fps, 1.0 / 30.0, 1100.0, 760.0); }
    for frame in 240 { update_pitch(fish, high_fps, 1.0 / 120.0, 1100.0, 760.0); }
    assert(low_fps.pitch < -0.4 && abs(low_fps.pitch - high_fps.pitch) < 0.00001);
    let held_pitch = low_fps.pitch;
    let held_speed = low_fps.pitch_speed;
    update_pitch(fish, low_fps, 0.0, 1100.0, 760.0);
    assert(low_fps.pitch == held_pitch && low_fps.pitch_speed == held_speed);
    low_fps.vertical_speed = 0.04;
    for frame in 180 {
        let before = low_fps.pitch;
        update_pitch(fish, low_fps, 1.0 / 60.0, 1100.0, 760.0);
        assert(abs(low_fps.pitch - before) < 0.06 && abs(low_fps.pitch) <= 1.221731);
    }
    assert(low_fps.pitch > 0.4);
    low_fps.vertical_speed = 0.0;
    for frame in 180 { update_pitch(fish, low_fps, 1.0 / 60.0, 1100.0, 760.0); }
    assert(abs(low_fps.pitch) < 0.001 && abs(low_fps.pitch_speed) < 0.001);
    var right = SwimMotion { vertical_speed: -0.04 };
    var left = right;
    var tall = right;
    for frame in 120 {
        fish.speed = 0.055;
        update_pitch(fish, right, 1.0 / 60.0, 1100.0, 760.0);
        update_pitch(fish, tall, 1.0 / 60.0, 760.0, 1100.0);
        fish.speed = -0.055; fish.phase = 3.0;
        update_pitch(fish, left, 1.0 / 60.0, 1100.0, 760.0);
    }
    assert(right.pitch == left.pitch && tall.pitch < right.pitch);
    let pitches: f32[2] = [-0.7, 0.7];
    for pitch in pitches {
        let rx, ry, rn = body_point(turn_view(1.0, 136.0, pitch), 40.0, 0.0);
        let lx, ly, ln = body_point(turn_view(0.0, 136.0, pitch), 40.0, 0.0);
        assert(rx > 0.0 && lx < 0.0 && abs(rx + lx) < 0.0001);
        assert(abs(ry - ly) < 0.0001 && ry * pitch > 0.0);
    }
}

fn check_pacing() {
    var fish = Creature { x: 0.5, y: 0.5, speed: 0.055, phase: 0.0, points: [] };
    var motion = SwimMotion {};
    var resting = 0;
    var longest_rest = 0;
    var burst = false;
    var glide = false;
    var resumed = false;
    for frame in 7200 {
        let x = fish.x;
        let y = fish.y;
        let phase = fish.phase;
        let pace = motion.pace;
        swim(fish, motion, 1.0 / 60.0, 1.0, 0);
        assert(motion.pace >= 0.0 && motion.pace <= 1.25 && abs(motion.pace - pace) < 0.05);
        burst = burst || motion.pace > 1.05;
        glide = glide || (motion.pace > 0.2 && motion.pace < 0.65);
        resumed = resumed || (longest_rest >= 30 && motion.pace > 0.5);
        if fish.x == x && fish.y == y && fish.phase == phase { resting++; }
        else { resting = 0; }
        longest_rest = max(longest_rest, resting);
    }
    assert(longest_rest >= 30 && burst && glide && resumed && fish.speed == 0.055);
    let held_pace = motion.pace;
    let held_clock = motion.elapsed;
    swim(fish, motion, 0.0, 1.0, 0);
    assert(motion.pace == held_pace && motion.elapsed == held_clock);
    for index in 12 {
        var pushes = 0;
        var coasts = 0;
        var rests = 0;
        var different = 0;
        for second in 300 {
            let pace = pace_target(second, index);
            assert(pace >= 0.0 && pace <= 1.25);
            if pace > 1.0 { pushes++; }
            else if pace > 0.0 { coasts++; }
            else { rests++; }
            if pace != pace_target(second, index + 1) { different++; }
        }
        assert(pushes > 0 && coasts > 0 && rests > 0 && different > 100);
    }
    var settled = SwimMotion { vertical_speed: 0.04, pitch: 0.7, pace: 0.0 };
    for frame in 180 { update_pitch(fish, settled, 1.0 / 60.0, 1100.0, 760.0); }
    assert(abs(settled.pitch) < 0.001 && abs(settled.pitch_speed) < 0.001);
}

fn check_growth() {
    let odds: i64[6] = [40, 28, 18, 9, 4, 1];
    var counts: i64[6] = [0, 0, 0, 0, 0, 0];
    for roll in 100 { counts[tier_from_roll(roll)]++; }
    assert(counts == odds);
    for tier in 6 {
        let born: f64 = 1000.0;
        assert(growth_width(tier, born, born) == 19.2);
        assert(growth_progress(tier, born, born - 100.0) == 0.0);
        assert(growth_progress(tier, born, born + GROWTH_SECONDS[tier] * 0.5) == 0.5);
        assert(abs(growth_width(tier, born, born + GROWTH_SECONDS[tier] * 0.5) -
                   (19.2 + (ADULT_WIDTHS[tier] - 19.2) * 0.75)) < 0.001);
        assert(growth_width(tier, born, born + GROWTH_SECONDS[tier]) == ADULT_WIDTHS[tier]);
        assert(growth_width(tier, born, born + GROWTH_SECONDS[tier] * 100.0) == ADULT_WIDTHS[tier]);
    }
    assert(growth_width(-1, 0.0, 1000000000.0) == 19.2);
}

fn check_growth_saves() {
    let ink: u8[4] = [255, 190, 108, 255];
    let points: Point[2] = [Point { 0.2, 0.5, 0.01, ink, true }, Point { 0.8, 0.5, 0.01, ink, false }];
    var previous: V2Creature[>..] = [];
    previous.push(V2Creature { x: 0.5, y: 0.5, speed: 0.055, phase: 0.0, size: 0.2, points: points });
    var raw: u8[>..] = [];
    raw.append(V2_SAVE_HEADER); raw.append(to_bytes(previous));
    var reef, ok = decode_reef(raw);
    assert(ok && reef.len == 1 && reef[0].tier == -1 && reef[0].born == 0.0 && reef[0].points == points);
    let directory = str(resource_dir(), ".test-data");
    let path = str(directory, "/growth-v2.reef");
    assert(make_dir(directory) && write_file_atomic(path, raw));
    var random = rng { 42 };
    let unwritable = str(directory, "/growth-directory-target");
    assert(make_dir(unwritable));
    assert(!upgrade_growth(reef, unwritable, raw, 1000.0, random));
    assert(reef[0].tier == -1 && reef[0].born == 0.0);
    let blocked = str(directory, "/growth-blocked.reef");
    assert(write_file_atomic(blocked, raw) && make_dir(str(blocked, ".v2.bak")));
    assert(!upgrade_growth(reef, blocked, raw, 1000.0, random));
    var preserved: u8[>..] = [];
    assert(read_file(blocked, preserved) && preserved == raw && reef[0].tier == -1);
    let mismatch = str(directory, "/growth-mismatched.reef");
    assert(write_file_atomic(mismatch, raw) && write_file_atomic(str(mismatch, ".v2.bak"), "keep this backup"));
    assert(!upgrade_growth(reef, mismatch, raw, 1000.0, random));
    preserved.clear(); assert(read_file(mismatch, preserved) && preserved == raw && reef[0].tier == -1);
    preserved.clear(); assert(read_file(str(mismatch, ".v2.bak"), preserved) && preserved == "keep this backup");
    assert(upgrade_growth(reef, path, raw, 1000.0, random));
    var backup: u8[>..] = [];
    assert(read_file(str(path, ".v2.bak"), backup) && backup == raw);
    var saved: u8[>..] = [];
    assert(read_file(path, saved));
    let restored, restored_ok = decode_reef(saved);
    assert(restored_ok && restored[0].tier == reef[0].tier && restored[0].born == 1000.0);
    assert(restored[0].points == points && restored[0].size == 0.2);
    let tier = reef[0].tier;
    assert(upgrade_growth(reef, path, saved, 2000.0, random));
    assert(reef[0].tier == tier && reef[0].born == 1000.0);
    reef[0].tier = 6;
    let bad_tier, tier_ok = decode_reef(encode_reef(reef));
    assert(!tier_ok && bad_tier.len == 0);
    reef[0].tier = tier; reef[0].born = -1.0;
    let bad_born, born_ok = decode_reef(encode_reef(reef));
    assert(!born_ok && bad_born.len == 0);
    var oldest: LegacyCreature[>..] = [];
    oldest.push(LegacyCreature { x: 0.5, y: 0.5, speed: 0.055, phase: 0.0, points: points });
    var v1: u8[>..] = [];
    v1.append(LEGACY_SAVE_HEADER); v1.append(to_bytes(oldest));
    var old_reef, old_ok = decode_reef(v1);
    let v1_path = str(directory, "/growth-v1.reef");
    assert(old_ok && write_file_atomic(v1_path, v1));
    assert(upgrade_growth(old_reef, v1_path, v1, 1000.0, random));
    backup.clear(); assert(read_file(str(v1_path, ".v1.bak"), backup) && backup == v1);
    assert(old_reef[0].born == 1000.0 && old_reef[0].points == points);
    previous.clear(); raw.clear(); raw.append(V2_SAVE_HEADER); raw.append(to_bytes(previous));
    var empty, empty_ok = decode_reef(raw);
    assert(empty_ok && empty.len == 0);
    let empty_path = str(directory, "/growth-empty-v2.reef");
    assert(write_file_atomic(empty_path, raw) && upgrade_growth(empty, empty_path, raw, 1000.0, random));
    saved.clear(); assert(read_file(empty_path, saved));
    let reopened, reopened_ok = decode_reef(saved);
    assert(reopened_ok && reopened.len == 0 && saved[..8] == SAVE_HEADER);
}

fn check_growth_geometry() {
    var fish = Creature { x: 0.5, y: 0.5, speed: 0.055, phase: 1.5, points: [], tier: 5, born: 1000.0 };
    assert(creature_area(fish, 1100.0, 760.0).w == 320.0);
    let windows: f32[2][3] = [[1100.0, 760.0], [640.0, 480.0], [320.0, 300.0]];
    let heights: f32[3] = [0.1, 0.5, 0.9];
    for window in windows {
        for y in heights {
            fish.y = y;
            let area = creature_area(fish, window[0], window[1]);
            assert(area.w <= window[0] && area.y >= 82.0 && area.y + area.h <= window[1] - 78.0);
        }
        let cx = window[0] * 0.5;
        let cy = window[1] * 0.5 + 2.0;
        move_creature(fish, cx, cy, window[0], window[1]);
        let placed = creature_area(fish, window[0], window[1]);
        assert(abs(placed.x + placed.w * 0.5 - cx) < 0.01 && abs(placed.y + placed.h * 0.5 - cy) < 0.01);
        assert(fish.tier == 5 && fish.born == 1000.0);
    }
}

fn check_names() {
    assert(valid_name("Nemo") && valid_name("  Baby fish  ") && valid_name("ត្រី"));
    assert(!valid_name("") && !valid_name(" \t\r\n ") && !valid_name("fish\nname"));
    assert(clean_name("  Nemo  ") == "Nemo");
    assert(valid_name("12345678901234567890123456789012"));
    assert(!valid_name("123456789012345678901234567890123"));
    let invalid: u8[2] = [0xC0, 0x80];
    assert(!valid_name(invalid));
    let blank_unicode: u8[3] = [0xE3, 0x80, 0x80]; // Ideographic space.
    assert(!valid_name(blank_unicode));
    let broken: u8[3] = [0xE2, 0x28, 0xA1];
    let truncated: u8[3] = [0xF0, 0x9F, 0x90];
    assert(!valid_name(broken) && !valid_name(truncated));
    var unicode_limit: u8[>..] = [];
    for i in 32 { push_utf8(unicode_limit, 0x1F41F); }
    assert(unicode_limit.len == 128 && valid_name(unicode_limit));
    let points: Point[2] = [Point { 0.2, 0.5, 0.01, [255, 190, 108, 255], true },
                            Point { 0.8, 0.5, 0.01, [255, 190, 108, 255], false }];
    var fish = Creature { x: 0.5, y: 0.5, speed: 0.055, phase: 0.0, points: points,
                          tier: 3, born: 1000.0, name: "Mochi" };
    var reef: Creature[>..] = []; reef.push(fish);
    let restored, ok = decode_reef(encode_reef(reef));
    assert(ok && restored[0].name == "Mochi" && restored[0].tier == 3 && restored[0].born == 1000.0);
    reef[0].name.clear(); reef[0].name.append(unicode_limit);
    let unicode_saved, unicode_ok = decode_reef(encode_reef(reef));
    assert(unicode_ok && unicode_saved[0].name == unicode_limit);
    reef[0].name.clear();
    let blank, blank_ok = decode_reef(encode_reef(reef));
    assert(!blank_ok && blank.len == 0);
    var old: V3Creature[>..] = [];
    old.push(V3Creature { x: fish.x, y: fish.y, speed: fish.speed, phase: fish.phase, size: fish.size,
                         points: points, tier: fish.tier, born: fish.born });
    var raw: u8[>..] = []; raw.append(V3_SAVE_HEADER); raw.append(to_bytes(old));
    var migrated, migrated_ok = decode_reef(raw);
    assert(migrated_ok && migrated[0].name.len == 0 && migrated[0].tier == 3 && migrated[0].born == 1000.0);
    let path = str(resource_dir(), ".test-data/named-v3.reef");
    assert(write_file_atomic(path, raw));
    var random = rng { 42 };
    assert(upgrade_growth(migrated, path, raw, 2000.0, random));
    assert(migrated[0].name == "Fish 1" && migrated[0].tier == 3 && migrated[0].born == 1000.0);
    var backup: u8[>..] = [];
    assert(read_file(str(path, ".v3.bak"), backup) && backup == raw);
    let named, named_ok = decode_reef(encode_reef(migrated));
    assert(named_ok && named[0].name == "Fish 1" && named[0].points == points);
}

fn image_test_png(width: i64, height: i64) -> u8[>..] {
    var png: u8[>..] = [];
    png.append([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13]);
    png.append("IHDR");
    for value in [width, height] {
        for shift in [24, 16, 8, 0] { png.push(((value >> shift) & 255) as! u8); }
    }
    png.append([8, 6, 0, 0, 0, 0, 0, 0, 0]);
    png.append([0, 0, 0, 0]); png.append("IDAT"); png.append([0, 0, 0, 0]);
    png.append([0, 0, 0, 0]); png.append("IEND"); png.append([0, 0, 0, 0]);
    return png;
}

fn check_image_data() {
    let png = image_test_png(4, 4);
    let w, h, ok = png_dimensions(png);
    assert(ok && w == 4 && h == 4);
    let bw, bh, too_big = png_dimensions(image_test_png(4097, 4));
    let tw, th, truncated = png_dimensions(png[..20]);
    assert(!too_big && !truncated);
    var pixels: u8[>..] = []; pixels.resize(4 * 4 * 4, 0);
    for y in 1..3 {
        for x in 1..3 { let i = (y * 4 + x) * 4; pixels[i] = 255; pixels[i + 3] = 128; }
    }
    let image, error = normalize_image(pixels, 4, 4);
    assert(error.len == 0 && image.width == 2 && image.height == 2 && image.rgba[0] == 255 && image.rgba[3] == 128);
    let restored, restored_ok = decode_image(encode_image(image));
    assert(restored_ok && restored.rgba == image.rgba && restored.width == 2);
    let bad, bad_ok = decode_image(encode_image(image)[..17]);
    assert(!bad_ok);
    pixels.resize(0); pixels.resize(64, 0);
    let invisible, invisible_error = normalize_image(pixels, 4, 4);
    assert(invisible_error.len > 0);
    for i in 16 { pixels[i * 4 + 3] = 255; }
    let opaque, opaque_error = normalize_image(pixels, 4, 4);
    assert(opaque_error.len > 0);
    pixels.resize(1024 * 512 * 4, 128);
    for i in 1024 * 512 { pixels[i * 4] = 255; pixels[i * 4 + 3] = 128; }
    let resized, resize_error = normalize_image(pixels, 1024, 512);
    assert(resize_error.len == 0 && resized.width == 512 && resized.height == 256);
    let directory = str(resource_dir(), ".test-data/image-data");
    assert(make_dir(directory));
    let path = str(directory, "/ត្រី.png");
    assert(write_file_atomic(path, png));
    let bounded, bounded_ok = read_image_file(path, 128);
    let overflow, overflow_ok = read_image_file(path, 16);
    assert(bounded_ok && bounded == png && !overflow_ok);
    var random = rng { 42 };
    let id, saved = save_image(directory, image, png, random);
    assert(saved && id != 0);
    var original: u8[>..] = [];
    assert(read_file(image_path(directory, id, ".png"), original) && original == png);
    discard_new_image(directory, id);
    assert(!file_exists(image_path(directory, id)));
}

fn check_image_records() {
    var reef: Creature[>..] = [];
    reef.push(Creature { x: 0.5, y: 0.5, speed: 0.05, phase: 0.0, points: [], tier: 1, born: 1000.0,
                         name: "PNG fish", image_id: 123 });
    let loaded, ok = decode_reef(encode_reef(reef));
    assert(ok && loaded[0].image_id == 123 && loaded[0].points.len == 0);
    let directory = str(resource_dir(), ".test-data");
    let path = str(directory, "/image-record.reef");
    assert(flip_creature(reef, 0, path) && reef[0].image_flip);
    assert(!flip_creature(reef, 0, directory) && reef[0].image_flip);
    var saved: u8[>..] = []; assert(read_file(path, saved));
    let flipped, flipped_ok = decode_reef(saved);
    assert(flipped_ok && flipped[0].image_flip && flipped[0].name == "PNG fish");
    reef[0].points.push(Point { 0.5, 0.5, 0.01, [255, 0, 0, 255], true });
    let mixed, mixed_ok = decode_reef(encode_reef(reef));
    assert(!mixed_ok && mixed.len == 0);
    var previous: V4Creature[>..] = [];
    previous.push(V4Creature { x: 0.5, y: 0.5, speed: 0.05, phase: 0.0, size: 0.2,
        points: reef[0].points, tier: 4, born: 1000.0, name: "Kept name" });
    var raw: u8[>..] = []; raw.append(V4_SAVE_HEADER); raw.append(to_bytes(previous));
    var old, old_ok = decode_reef(raw);
    assert(old_ok && old[0].image_id == 0 && old[0].name == "Kept name");
    let old_path = str(directory, "/image-v4.reef");
    assert(write_file_atomic(old_path, raw));
    var random = rng { 42 };
    assert(upgrade_growth(old, old_path, raw, 2000.0, random));
    assert(old[0].tier == 4 && old[0].born == 1000.0 && old[0].name == "Kept name");
    var backup: u8[>..] = []; assert(read_file(str(old_path, ".v4.bak"), backup) && backup == raw);
}

fn main() {
    check_image_records();
    check_image_data();
    check_names();
    check_growth();
    check_growth_saves();
    check_growth_geometry();
    check_color();
    check_shapes();
    check_fill();
    check_vertical_swimming();
    check_pitch();
    check_pacing();
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
    assert(creature_area(large, 1100.0, 760.0).w == 19.2);
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
    fish.tier = 0; fish.born = time() + 86400.0;
    small.tier = 0; small.born = fish.born;
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
    print("PASS: passive growth tiers, offline age, metadata and migration safety, mature-S bounds, movement, vertical swimming, damped pitch and pacing, canvas zoom/pan, clipping, legacy saves, strokes, colors, shapes, fills, flips, persistence and deletion");
}
