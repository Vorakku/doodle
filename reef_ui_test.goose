import std;
import os;
import math;
import gfx;
import reef_model;
import doodle_reef;

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
    for wall in [0, 1] {
        initial[0].x = if wall == 0 { 0.95 } else { 0.05 };
        initial[0].speed = if wall == 0 { 0.1 } else { -0.1 };
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
    print("PASS: real Delete button and key, empty restart, dragging, pause, saved positions and rendered facing after both wall turns");
}
