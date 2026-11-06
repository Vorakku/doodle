import std;
import os;
import math;
import gfx;
import reef_model;
import doodle_reef;

fn pixel_red(x: i64, y: i64) -> u8 {
    return gfx::read_pixels(gfx::screen())[(y * 1100 + x) * 4];
}

fn pixel_green(x: i64, y: i64) -> u8 {
    return gfx::read_pixels(gfx::screen())[(y * 1100 + x) * 4 + 1];
}

// Hover, press and release on consecutive frames, the way a real click arrives.
fn click_at(frame: i64, start: i64, x: f32, y: f32) {
    if frame == start { gfx::inject_mouse(x, y, 0, false); }
    if frame == start + 1 { gfx::inject_mouse(x, y, 1, true); }
    if frame == start + 2 { gfx::inject_mouse(x, y, 1, false); }
}

fn main() {
    var headless: u8[>..] = [];
    assert(env("GOOSE_GFX_HEADLESS", headless) && headless == "1");
    let directory = str(resource_dir(), "delete-ui-test");
    let save_path = str(directory, "/creatures.reef");
    assert(make_dir(directory));
    var initial: Creature[>..] = [];
    initial.push(demo());
    assert(write_file_atomic(save_path, encode_reef(initial)));
    let result = run(directory, 12, false) { frame, reef, selected =>
        if frame == 1 { gfx::inject_mouse(810.0, 43.0, 1, true); }
        if frame == 2 { gfx::inject_mouse(810.0, 43.0, 1, false); }
        if frame == 3 {
            let a = creature_area(reef[0], 1100.0, 760.0);
            gfx::inject_mouse(a.x + a.w * 0.5, a.y + a.h * 0.5, 1, true);
        }
        if frame == 4 { gfx::inject_mouse(453.0, 351.0, 1, false); }
        if frame == 5 { assert(selected == 0); gfx::inject_mouse(965.0, 699.0, 0, false); }
        if frame == 6 { gfx::inject_mouse(965.0, 699.0, 1, true); }
        if frame == 7 { gfx::inject_mouse(965.0, 699.0, 1, false); }
    };
    assert(result.len == 0);
    var disk: u8[>..] = [];
    assert(read_file(save_path, disk));
    let saved, ok = decode_reef(disk);
    assert(ok && saved.len == 0);
    let reopened = run(directory, 2, false) { frame, reef, selected => };
    assert(reopened.len == 0);
    for paused in [false, true] {
        assert(write_file_atomic(save_path, encode_reef(initial)));
        var held_phase: f32 = 0.0;
        var drop_x: f32 = 0.0;
        var drop_y: f32 = 0.0;
        var offset_x: f32 = 0.0;
        var offset_y: f32 = 0.0;
        let moved = run(directory, 11, false) { frame, reef, selected =>
            if paused && frame == 1 { gfx::inject_mouse(810.0, 43.0, 1, true); }
            if paused && frame == 2 { gfx::inject_mouse(810.0, 43.0, 1, false); }
            if frame == 3 {
                let a = creature_area(reef[0], 1100.0, 760.0);
                let x = floor(a.x + a.w * 0.5 + 23.0);
                let y = floor(a.y + a.h * 0.5 - 9.0);
                offset_x = x - (a.x + a.w * 0.5);
                offset_y = y - (a.y + a.h * 0.5);
                gfx::inject_mouse(x, y, 1, true);
            }
            if frame == 4 {
                assert(selected == 0);
                held_phase = reef[0].phase;
                gfx::inject_mouse(723.0, 441.0, 0, false);
            }
            if frame == 5 {
                let a = creature_area(reef[0], 1100.0, 760.0);
                assert(abs(a.x + a.w * 0.5 - (723.0 - offset_x)) < 0.1);
                assert(abs(a.y + a.h * 0.5 - (441.0 - offset_y)) < 0.1);
                assert(reef[0].phase == held_phase);
                gfx::inject_mouse(783.0, 491.0, 0, false);
            }
            if frame == 6 {
                let a = creature_area(reef[0], 1100.0, 760.0);
                assert(abs(a.x + a.w * 0.5 - (783.0 - offset_x)) < 0.1);
                assert(abs(a.y + a.h * 0.5 - (491.0 - offset_y)) < 0.1);
                assert(reef[0].phase == held_phase);
                drop_x = reef[0].x; drop_y = reef[0].y;
            }
            if frame == 7 {
                assert(reef[0].x == drop_x && reef[0].y == drop_y && reef[0].phase == held_phase);
                gfx::inject_mouse(783.0, 491.0, 1, false);
            }
            if frame == 9 {
                if paused { assert(reef[0].x == drop_x && reef[0].phase == held_phase); }
                else { assert(reef[0].x > drop_x && reef[0].phase > held_phase); }
            }
        };
        assert(moved.len == 1 && moved[0].speed == initial[0].speed);
        disk.clear();
        assert(read_file(save_path, disk));
        let saved_move, move_ok = decode_reef(disk);
        assert(move_ok && saved_move.len == 1);
        assert(saved_move[0].x == drop_x && saved_move[0].y == drop_y);
    }
    assert(write_file_atomic(save_path, encode_reef(initial)));
    let key_deleted = run(directory, 7, false) { frame, reef, selected =>
        if frame == 1 {
            let a = creature_area(reef[0], 1100.0, 760.0);
            gfx::inject_mouse(a.x + a.w * 0.5, a.y + a.h * 0.5, 1, true);
        }
        if frame == 2 { gfx::inject_mouse(453.0, 351.0, 1, false); }
        if frame == 3 { assert(selected == 0); assert(gfx::inject_key("Delete", true)); }
        if frame == 4 { assert(gfx::inject_key("Delete", false)); }
    };
    assert(key_deleted.len == 0);
    // Tell a creature to turn, then follow its eye across real frames: it must sweep over, not jump.
    initial[0].x = 0.5;
    initial[0].speed = 0.1;
    assert(write_file_atomic(save_path, encode_reef(initial)));
    var eye_start: f32 = 0.0;
    var eye_now: f32 = 0.0;
    var eye_closest: f32 = 1000.0;
    var eye_biggest_jump: f32 = 0.0;
    run(directory, 150, false) { frame, reef, selected =>
        if frame >= 1 {
            let area = creature_area(reef[0], 1100.0, 760.0);
            let pixels = gfx::read_pixels(gfx::screen());
            var total: f32 = 0.0;
            var count = 0;
            for y in (floor(area.y) as! i64)..(ceil(area.y + area.h) as! i64) {
                for x in (floor(area.x) as! i64)..(ceil(area.x + area.w) as! i64) {
                    let offset = (y * 1100 + x) * 4;
                    if pixels[offset] > 220 && pixels[offset + 1] > 220 && pixels[offset + 2] > 210 { total += x as f32; count++; }
                }
            }
            if count > 0 {
                let eye = total / count as f32 - (area.x + area.w * 0.5);
                if frame == 1 { eye_start = eye; reef[0].speed = -0.1; }
                else { eye_biggest_jump = max(eye_biggest_jump, abs(eye - eye_now)); }
                eye_now = eye;
                eye_closest = min(eye_closest, abs(eye));
            }
        }
    };
    assert(eye_start > 0.0 && eye_now < 0.0); // Ended up facing the other way,
    assert(abs(abs(eye_now) - eye_start) < 3.0); // at full width again,
    assert(eye_closest < eye_start * 0.4); // having narrowed along the way,
    assert(eye_biggest_jump < eye_start * 0.5); // a little at a time.
    for wall in [0, 1] {
        initial[0].x = 0.5;
        initial[0].speed = if wall == 0 { -0.1 } else { 0.1 };
        assert(write_file_atomic(save_path, encode_reef(initial)));
        run(directory, 2, false) { frame, reef, selected =>
            if frame == 1 {
                assert(if wall == 0 { reef[0].speed < 0.0 } else { reef[0].speed > 0.0 });
                let area = creature_area(reef[0], 1100.0, 760.0);
                let pixels = gfx::read_pixels(gfx::screen());
                var left_eye = 0;
                var right_eye = 0;
                for y in (floor(area.y) as! i64)..(ceil(area.y + area.h) as! i64) {
                    for x in (floor(area.x) as! i64)..(ceil(area.x + area.w) as! i64) {
                        let offset = (y * 1100 + x) * 4;
                        if pixels[offset] > 220 && pixels[offset + 1] > 220 && pixels[offset + 2] > 210 {
                            if x < area.x + area.w * 0.5 { left_eye++; } else { right_eye++; }
                        }
                    }
                }
                if wall == 0 { assert(left_eye > 0 && right_eye == 0); }
                else { assert(right_eye > 0 && left_eye == 0); }
            }
        };
    }
    assert(delete_file(save_path));

    // Draw a real circle, then Fill / Undo / Redo / Bring to Life through the actual studio controls.
    let cx: f32 = 400.0;
    let cy: f32 = 300.0;
    var drawn_points = 0;
    var no_creatures: Creature[>..] = [];
    assert(write_file_atomic(save_path, encode_reef(no_creatures)));
    let filled = run(directory, 80, false) { frame, reef, selected =>
        if frame == 1 { gfx::inject_mouse(590.0, 43.0, 1, true); }
        if frame == 2 { gfx::inject_mouse(590.0, 43.0, 1, false); }
        if frame >= 3 && frame < 44 {
            let angle: f32 = (frame - 3) * 6.2831853 / 40.0;
            let x = cx + cos(angle) * 100.0;
            let y = cy + sin(angle) * 100.0;
            if frame == 3 { gfx::inject_mouse(x, y, 0, false); }
            else if frame == 4 { gfx::inject_mouse(x, y, 1, true); }
            else { gfx::inject_mouse(x, y, 0, false); }
        }
        if frame == 44 { gfx::inject_mouse(cx + 100.0, cy, 1, false); }
        click_at(frame, 46, 50.0, 163.0); // Fill tool
        click_at(frame, 50, cx, cy);
        if frame == 54 { assert(pixel_red(400, 300) == 255); }
        click_at(frame, 54, 845.0, 545.0); // Undo
        if frame == 58 { assert(pixel_red(400, 300) < 100); }
        click_at(frame, 58, 933.0, 545.0); // Redo
        if frame == 62 { assert(pixel_red(400, 300) == 255); assert(gfx::inject_key("Left Ctrl", true)); }
        if frame == 63 { assert(gfx::inject_key("Z", true)); }
        if frame == 64 { assert(gfx::inject_key("Z", false)); }
        if frame == 66 { assert(pixel_red(400, 300) < 100); assert(gfx::inject_key("Y", true)); }
        if frame == 67 { assert(gfx::inject_key("Y", false)); }
        if frame == 69 { assert(pixel_red(400, 300) == 255); assert(gfx::inject_key("Left Ctrl", false)); }
        // Without Ctrl the same keys must do nothing.
        if frame == 70 { assert(gfx::inject_key("Z", true)); }
        if frame == 71 { assert(gfx::inject_key("Z", false)); }
        if frame == 73 { assert(pixel_red(400, 300) == 255); }
        click_at(frame, 73, 933.0, 583.0); // Bring to Life
    };
    assert(filled.len == 1 && valid_points(filled[0].points));
    for p in filled[0].points { if p.start { drawn_points++; } }
    // One outline stroke plus many fill rows.
    assert(drawn_points > 20);
    disk.clear();
    assert(read_file(save_path, disk));
    let saved_fill, fill_ok = decode_reef(disk);
    assert(fill_ok && saved_fill.len == 1 && saved_fill[0].points == filled[0].points);

    // A dragged rectangle, Fill, a typed hex colour, a swatch, and the eyedropper, all through the real controls.
    assert(write_file_atomic(save_path, encode_reef(no_creatures)));
    let shaped = run(directory, 100, false) { frame, reef, selected =>
        click_at(frame, 1, 590.0, 43.0); // Draw a creature
        click_at(frame, 4, 50.0, 257.0); // Rectangle tool
        if frame == 7 { gfx::inject_mouse(250.0, 200.0, 0, false); }
        if frame == 8 { gfx::inject_mouse(250.0, 200.0, 1, true); }
        if frame == 9 { gfx::inject_mouse(350.0, 300.0, 0, false); }
        if frame == 10 { gfx::inject_mouse(450.0, 400.0, 0, false); }
        if frame == 11 { gfx::inject_mouse(450.0, 400.0, 1, false); }
        click_at(frame, 13, 50.0, 163.0); // Fill tool
        click_at(frame, 16, 950.0, 311.0); // Hex box
        for i in 6 {
            if frame == 19 + i * 2 { assert(gfx::inject_key("Backspace", true)); }
            if frame == 20 + i * 2 { assert(gfx::inject_key("Backspace", false)); }
        }
        if frame == 32 { assert(gfx::inject_text("00FF00")); }
        if frame == 34 { assert(gfx::inject_key("Return", true)); }
        if frame == 35 { assert(gfx::inject_key("Return", false)); }
        click_at(frame, 37, 350.0, 300.0); // Fill in green
        if frame == 41 { assert(pixel_green(350, 300) == 255 && pixel_red(350, 300) == 0); }
        click_at(frame, 41, 851.0, 343.0); // Second swatch
        click_at(frame, 45, 350.0, 300.0); // Recolor with it
        if frame == 49 { assert(pixel_red(350, 300) == 255 && pixel_green(350, 300) == 126); }
        click_at(frame, 49, 824.0, 279.0); // Eyedropper
        click_at(frame, 53, 250.0, 300.0); // Pick the orange outline
        click_at(frame, 57, 350.0, 300.0); // Fill tool is back, so this fills in orange
        if frame == 61 { assert(pixel_red(350, 300) == 255 && pixel_green(350, 300) == 190); }
        click_at(frame, 61, 1050.0, 110.0); // Saturation and brightness square: near-pure hue
        if frame == 65 { assert(gfx::inject_key("Left Ctrl", true)); }
        if frame == 66 { assert(gfx::inject_key("Z", true)); }
        if frame == 67 { assert(gfx::inject_key("Z", false)); }
        if frame == 68 { assert(gfx::inject_key("Left Ctrl", false)); }
        if frame == 70 { assert(pixel_green(350, 300) == 126); }
        // Drag the hue bar a third of the way along to green, then take full color from the square.
        if frame == 72 { gfx::inject_mouse(860.0, 279.0, 0, false); }
        if frame == 73 { gfx::inject_mouse(860.0, 279.0, 1, true); }
        if frame == 74 { gfx::inject_mouse(921.0, 279.0, 0, false); }
        if frame == 75 { gfx::inject_mouse(921.0, 279.0, 1, false); }
        click_at(frame, 77, 1063.0, 104.0);
        click_at(frame, 81, 350.0, 300.0);
        if frame == 85 { assert(pixel_green(350, 300) > 220 && pixel_red(350, 300) < 60); }
        click_at(frame, 85, 933.0, 583.0); // Bring to Life
    };
    assert(shaped.len == 1 && valid_points(shaped[0].points));
    assert(delete_file(save_path));
    print("PASS: real Delete button and key, empty restart, dragging, pause, saved positions, rendered facing in both directions, the animated turn, and studio Fill / Undo / Redo / Ctrl+Z / Ctrl+Y / shapes / hex / swatches / eyedropper / save");
}
