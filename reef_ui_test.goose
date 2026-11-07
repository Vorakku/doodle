import std;
import os;
import math;
import gfx;
import ui;
import reef_fill;
import reef_model;
import reef_growth;
import reef_images;
import reef_image_data;
extern fn reef_import_test_path(path: const u8[:]);
import doodle_reef;

fn pixel_red(x: i64, y: i64) -> u8 {
    return gfx::read_pixels(gfx::screen())[(y * 1100 + x) * 4];
}

fn pixel_green(x: i64, y: i64) -> u8 {
    return gfx::read_pixels(gfx::screen())[(y * 1100 + x) * 4 + 1];
}

fn eye_offset(fish: const Creature&) -> f32, f32 {
    let area = creature_area(fish, 1100.0, 760.0);
    let pixels = gfx::read_pixels(gfx::screen());
    var sum_x: f32 = 0.0;
    var sum_y: f32 = 0.0;
    var count = 0;
    for y in (floor(area.y) as! i64)..(ceil(area.y + area.h) as! i64) {
        for x in (floor(area.x) as! i64)..(ceil(area.x + area.w) as! i64) {
            let offset = (y * 1100 + x) * 4;
            if pixels[offset] > 145 && pixels[offset + 1] > 145 && pixels[offset + 2] > 145 {
                sum_x += x; sum_y += y; count++;
            }
        }
    }
    assert(count > 0);
    return sum_x / count - area.x - area.w * 0.5,
           sum_y / count - area.y - area.h * 0.5;
}

// Hover, press and release on consecutive frames, the way a real click arrives.
fn click_at(frame: i64, start: i64, x: f32, y: f32) {
    if frame == start { gfx::inject_mouse(x, y, 0, false); }
    if frame == start + 1 { gfx::inject_mouse(x, y, 1, true); }
    if frame == start + 2 { gfx::inject_mouse(x, y, 1, false); }
}

fn check_pitch_render() {
    var fish = demo();
    var points: Point[>..] = [];
    points.append(fish.points);
    var visible = points.len;
    var ranges: FillRange[>..] = [];
    assert(fill_region(points, visible, ranges, Bounds { 0.0, 0.0, 1.0, 1.0 }, 0.5, 0.5, PALETTE[1]) == FillResult.Filled);
    fish.points.clear(); fish.points.append(points);
    var reef: Creature[>..] = [];
    var motions: SwimMotion[>..] = [];
    let headings: f32[4] = [1.0, 0.0, 1.0, 0.0];
    for i in 4 {
        fish.x = if i % 2 == 0 { 0.3 } else { 0.7 };
        fish.y = if i < 2 { 0.3 } else { 0.7 };
        reef.push(fish);
        motions.push(SwimMotion { pitch: if i < 2 { -0.7 } else { 0.7 } });
    }
    assert(gfx::open("DOODLE REEF tilt check", 1100, 760));
    let ctx = ui::create_from_memory(FONT, 17.0);
    assert(ctx.id != 0 && gfx::frame());
    ui::input_from_gfx(ctx);
    var images = ImageRenderer {};
    scene(ctx, 1100.0, 760.0, 0.0, reef, headings, motions, -1, images);
    gfx::begin_screen(float4 { 0.03, 0.1, 0.14, 1.0 });
    gfx::end_pass();
    ui::render(ctx);
    assert(gfx::screenshot(str(resource_dir(), "tilt-preview.png")));
    for i in 4 {
        let ex, ey = eye_offset(reef[i]);
        let area = creature_area(reef[i], 1100.0, 760.0);
        assert(if i % 2 == 0 { ex > area.w * 0.07 } else { ex < -area.w * 0.07 });
        assert(if i < 2 { ey < -area.h * 0.1 } else { ey > area.h * 0.05 });
        let cx = (area.x + area.w * 0.5) as! i64;
        let cy = (area.y + area.h * 0.5) as! i64;
        var fill_pixels = 0;
        for y in (cy - 2)..(cy + 3) {
            for x in (cx - 2)..(cx + 3) {
                if pixel_red(x, y) == 255 && pixel_green(x, y) == 126 { fill_pixels++; }
            }
        }
        assert(fill_pixels > 0);
    }
    release_image_renderer(images);
    ui::destroy(ctx);
    gfx::close();
}

fn check_named_release() {
    let directory = str(resource_dir(), "naming-ui-test");
    let path = str(directory, "/creatures.reef");
    var empty: Creature[>..] = [];
    if is_dir(path) { assert(delete_dir(path)); }
    assert(make_dir(directory) && write_file_atomic(path, encode_reef(empty)));
    let named = run(directory, 35, true) { frame, reef, selected =>
        if frame == 1 { gfx::inject_mouse(400.0, 300.0, 0, false); }
        if frame == 2 { gfx::inject_mouse(400.0, 300.0, 1, true); }
        if frame == 3 { gfx::inject_mouse(450.0, 300.0, 0, false); }
        if frame == 4 { gfx::inject_mouse(450.0, 300.0, 1, false); }
        click_at(frame, 6, 933.0, 583.0);
        if frame == 10 {
            assert(reef.len == 0);
            assert(gfx::screenshot(str(resource_dir(), "name-prompt.png")));
            assert(gfx::inject_key("Return", true));
        }
        if frame == 11 { assert(gfx::inject_key("Return", false)); }
        if frame == 12 { assert(reef.len == 0); assert(gfx::inject_key("Escape", true)); }
        if frame == 13 { assert(gfx::inject_key("Escape", false)); }
        click_at(frame, 15, 933.0, 583.0);
        if frame == 19 { assert(gfx::inject_text("  Bubbles  ")); }
        if frame == 20 {
            assert(gfx::screenshot(str(resource_dir(), "name-prompt-filled.png")));
            assert(delete_file(path) && make_dir(path));
            assert(gfx::inject_key("Return", true));
        }
        if frame == 21 { assert(gfx::inject_key("Return", false)); }
        if frame == 23 {
            assert(reef.len == 0);
            assert(gfx::screenshot(str(resource_dir(), "name-save-failed.png")));
            assert(delete_dir(path) && write_file_atomic(path, encode_reef(empty)));
        }
        if frame == 25 { assert(gfx::inject_key("Return", true)); }
        if frame == 26 { assert(gfx::inject_key("Return", false)); }
    };
    assert(named.len == 1 && named[0].name == "Bubbles" && named[0].points.len >= 2);
    let reopened = run(directory, 2, false) { frame, reef, selected => };
    assert(reopened.len == 1 && reopened[0].name == "Bubbles" && reopened[0].tier == named[0].tier && reopened[0].born == named[0].born);
    let clicked = run(directory, 32, true) { frame, reef, selected =>
        if frame == 1 { gfx::inject_mouse(400.0, 300.0, 0, false); }
        if frame == 2 { gfx::inject_mouse(400.0, 300.0, 1, true); }
        if frame == 3 { gfx::inject_mouse(450.0, 300.0, 0, false); }
        if frame == 4 { gfx::inject_mouse(450.0, 300.0, 1, false); }
        click_at(frame, 6, 933.0, 583.0);
        click_at(frame, 11, 460.0, 420.0); // Cancel the naming prompt with the mouse.
        if frame == 15 { assert(reef.len == 1 && pixel_red(420, 300) == 255); }
        click_at(frame, 16, 933.0, 583.0);
        if frame == 20 { assert(gfx::inject_text("Finn")); }
        click_at(frame, 22, 645.0, 420.0); // Confirm the named fish with the mouse.
    };
    assert(clicked.len == 2 && clicked[0].name == "Bubbles" && clicked[1].name == "Finn");
}

fn check_image_graphics() {
    assert(gfx::open("PNG checks", 128, 128));
    assert(gfx::frame());
    var pixels: u8[>..] = []; pixels.resize(8 * 8 * 4, 0);
    for y in 2..6 {
        for x in 2..6 {
            let i = (y * 8 + x) * 4;
            pixels[i + (if x < 4 { 0 } else { 2 })] = 255;
            pixels[i + 3] = if y == 2 { 128 } else { 255 };
        }
    }
    let source = gfx::texture2d(8, 8);
    assert(source.id != 0 && gfx::update_texture(source, pixels));
    let directory = str(resource_dir(), "image-ui-test");
    assert(make_dir(directory));
    let path = str(directory, "/source.png");
    assert(gfx::save_png(source, path)); gfx::release(source);
    let image, png, error = load_png_image(path, directory);
    assert(error.len == 0 && image.width == 4 && image.height == 4);
    var slot = ImageSlot {};
    assert(prepare_image_slot(slot, image));
    var renderer = ImageRenderer {};
    let target = render_image_pose(renderer, slot, 64.0, 64.0, 0.0, false, 1.0, 0.0, false);
    assert(target.id != 0);
    let bytes = gfx::read_pixels(target);
    let left = (40 * slot.output_width + 24) * 4;
    let right = (40 * slot.output_width + 56) * 4;
    assert(bytes[left] > 240 && bytes[left + 2] < 10 && bytes[right + 2] > 240 && bytes[3] == 0);
    let flipped = render_image_pose(renderer, slot, 64.0, 64.0, 0.0, false, 1.0, 0.0, true);
    let mirrored = gfx::read_pixels(flipped);
    assert(mirrored[left + 2] > 240 && mirrored[right] > 240);
    let swimming_left = gfx::read_pixels(render_image_pose(renderer, slot, 64.0, 64.0, 0.0, false, 0.0, 0.0, false));
    assert(swimming_left[left + 2] > 240 && swimming_left[right] > 240);
    release_image_slot(slot); release_image_renderer(renderer);
    gfx::close();
}

fn check_import_flow() {
    let directory = str(resource_dir(), "image-import-ui-test");
    let path = str(directory, "/creatures.reef");
    let source = str(resource_dir(), "image-ui-test/source.png");
    var empty: Creature[>..] = [];
    assert(make_dir(directory) && make_dir(str(directory, "/images")));
    if is_dir(path) { assert(delete_dir(path)); }
    assert(write_file_atomic(path, encode_reef(empty)));
    var assets_before: u8[>..] = []; assert(list_dir(str(directory, "/images"), assets_before));
    let imported = run(directory, 32, true) { frame, reef, selected =>
        if frame == 1 { reef_import_test_path(source); }
        click_at(frame, 2, 1030.0, 583.0);
        if frame == 6 {
            assert(reef.len == 0 && pixel_red(300, 300) > 200);
            assert(gfx::screenshot(str(resource_dir(), "image-import-preview.png")));
        }
        click_at(frame, 7, 933.0, 583.0);
        if frame == 11 { assert(gfx::inject_key("Escape", true)); }
        if frame == 12 { assert(gfx::inject_key("Escape", false)); }
        click_at(frame, 14, 933.0, 583.0);
        if frame == 18 { assert(gfx::inject_text("Sticker")); }
        if frame == 19 { assert(delete_file(path) && make_dir(path)); assert(gfx::inject_key("Return", true)); }
        if frame == 20 { assert(gfx::inject_key("Return", false)); }
        if frame == 22 {
            var assets: u8[>..] = []; assert(list_dir(str(directory, "/images"), assets));
            assert(reef.len == 0 && assets == assets_before);
            assert(delete_dir(path) && write_file_atomic(path, encode_reef(empty)));
        }
        if frame == 24 { assert(gfx::inject_key("Return", true)); }
        if frame == 25 { assert(gfx::inject_key("Return", false)); }
    };
    assert(imported.len == 1 && imported[0].name == "Sticker" && imported[0].image_id != 0 && imported[0].points.len == 0);
    var original: u8[>..] = []; var copied: u8[>..] = [];
    assert(read_file(source, original) && read_file(image_path(directory, imported[0].image_id, ".png"), copied) && original == copied);
    assert(delete_file(source));
    let reopened = run(directory, 3, false) { frame, reef, selected =>
        if frame == 2 {
            let area = creature_area(reef[0], 1100.0, 760.0);
            let pixels = gfx::read_pixels(gfx::screen());
            var blue = 0;
            for y in (floor(area.y) as! i64)..(ceil(area.y + area.h) as! i64) {
                for x in (floor(area.x) as! i64)..(ceil(area.x + area.w) as! i64) {
                    let i = (y * 1100 + x) * 4;
                    if pixels[i] < 80 && pixels[i + 1] < 100 && pixels[i + 2] > 150 { blue++; }
                }
            }
            assert(blue > 0);
        }
    };
    assert(reopened[0].image_id == imported[0].image_id && reopened[0].born == imported[0].born);
}

// Label-coloured pixels on one text line under a fish: line 0 is the name, line 1 the tier.
fn label_pixels(fish: const Creature&, line: i64) -> i64 {
    let area = creature_area(fish, 1100.0, 760.0);
    let top = floor(min(area.y + area.h + 2.0, 646.0)) as! i64 + line * 18;
    let left = floor(area.x + area.w * 0.5) as! i64 - 60;
    let pixels = gfx::read_pixels(gfx::screen());
    var count = 0;
    for y in top..top + 18 {
        for x in left..left + 120 {
            let i = (y * 1100 + x) * 4;
            if pixels[i + 1] > 180 && pixels[i + 2] > 150 { count++; }
        }
    }
    return count;
}

fn check_fish_labels() {
    let directory = str(resource_dir(), "label-ui-test");
    assert(make_dir(directory));
    var reef: Creature[>..] = [];
    reef.push(demo());
    reef[0].name.clear(); reef[0].name.append("Bubbles");
    reef[0].tier = 2; reef[0].born = time() - GROWTH_SECONDS[2] - 1.0;
    assert(write_file_atomic(str(directory, "/creatures.reef"), encode_reef(reef)));
    run(directory, 10, false) { frame, fish, selected =>
        let a = creature_area(fish[0], 1100.0, 760.0);
        if frame == 2 { assert(selected == -1 && label_pixels(fish[0], 0) > 0 && label_pixels(fish[0], 1) == 0); }
        if frame == 3 { gfx::inject_mouse(a.x + a.w * 0.5, a.y + a.h * 0.5, 1, true); }
        if frame == 4 { gfx::inject_mouse(a.x + a.w * 0.5, a.y + a.h * 0.5, 1, false); }
        if frame == 7 {
            assert(selected == 0 && label_pixels(fish[0], 0) > 0 && label_pixels(fish[0], 1) > 0);
            assert(gfx::screenshot(str(resource_dir(), "fish-label.png")));
        }
    };
}

fn main() {
    var headless: u8[>..] = [];
    assert(env("GOOSE_GFX_HEADLESS", headless) && headless == "1");
    check_fish_labels();
    check_image_graphics();
    check_import_flow();
    check_named_release();
    check_pitch_render();
    let starter_dir = str(resource_dir(), "growth-starter-ui-test");
    let starter_path = str(starter_dir, "/creatures.reef");
    assert(make_dir(starter_dir));
    if file_exists(starter_path) { assert(delete_file(starter_path)); }
    let starter = run(starter_dir, 2, false) { frame, reef, selected => };
    assert(starter.len == 1 && starter[0].tier >= 0 && starter[0].tier < 6 && starter[0].born > 0.0);
    let starter_again = run(starter_dir, 2, false) { frame, reef, selected => };
    assert(starter_again[0].tier == starter[0].tier && starter_again[0].born == starter[0].born);
    let directory = str(resource_dir(), "delete-ui-test");
    let save_path = str(directory, "/creatures.reef");
    assert(make_dir(directory));
    var initial: Creature[>..] = [];
    initial.push(demo());
    initial[0].tier = 0; initial[0].born = time() + 86400.0;
    var legacy: V2Creature[>..] = [];
    legacy.push(V2Creature { x: initial[0].x, y: initial[0].y, speed: initial[0].speed,
        phase: initial[0].phase, size: initial[0].size, points: initial[0].points });
    var legacy_bytes: u8[>..] = [];
    legacy_bytes.append(V2_SAVE_HEADER); legacy_bytes.append(to_bytes(legacy));
    let migration_dir = str(resource_dir(), "growth-ui-test");
    let migration_path = str(migration_dir, "/creatures.reef");
    assert(make_dir(migration_dir) && write_file_atomic(migration_path, legacy_bytes));
    let upgraded = run(migration_dir, 2, false) { frame, reef, selected => };
    assert(upgraded.len == 1 && upgraded[0].tier >= 0 && upgraded[0].tier < 6 && upgraded[0].born > 0.0);
    let reopened = run(migration_dir, 2, false) { frame, reef, selected => };
    assert(reopened[0].tier == upgraded[0].tier && reopened[0].born == upgraded[0].born);
    var backup: u8[>..] = [];
    assert(read_file(str(migration_path, ".v2.bak"), backup) && backup == legacy_bytes);
    var grown: Creature[>..] = [];
    grown.append(initial);
    grown[0].tier = 5; grown[0].born = time() - GROWTH_SECONDS[5] - 1.0;
    let renderer_dir = str(resource_dir(), "growth-renderer-test");
    assert(make_dir(renderer_dir) && write_file_atomic(str(renderer_dir, "/creatures.reef"), encode_reef(grown)));
    assert(write_file_atomic(save_path, encode_reef(grown)));
    run(directory, 10, false) { frame, reef, selected =>
        let area = creature_area(reef[0], 1100.0, 760.0);
        assert(area.w == 320.0 && area.y >= 82.0 && area.y + area.h <= 682.0);
        if frame == 1 { gfx::inject_mouse(area.x + area.w * 0.5, area.y + area.h * 0.5, 1, true); }
        if frame == 2 { gfx::inject_mouse(area.x + area.w * 0.5, area.y + area.h * 0.5, 1, false); }
        if frame == 8 { assert(selected == 0); assert(gfx::screenshot(str(resource_dir(), "growth-preview.png"))); }
    };
    grown[0].tier = 0;
    assert(write_file_atomic(str(renderer_dir, "/reload.reef"), encode_reef(grown)));
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
                let x = floor(a.x + a.w * 0.67);
                let y = floor(a.y + a.h * 0.38);
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
                if paused { assert(reef[0].x == drop_x && reef[0].y == drop_y && reef[0].phase == held_phase); }
                else { assert(reef[0].x > drop_x && reef[0].y != drop_y && reef[0].phase > held_phase); }
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
    initial[0].x = 0.5;
    initial[0].y = 0.5;
    assert(write_file_atomic(save_path, encode_reef(initial)));
    var paused_eye_x: f32 = 0.0;
    var paused_eye_y: f32 = 0.0;
    run(directory, 100, false) { frame, reef, selected =>
        if frame == 90 {
            let eye_x, eye_y = eye_offset(reef[0]);
            assert(eye_x > 0.0 && eye_y < -creature_area(reef[0], 1100.0, 760.0).h * 0.1);
            assert(gfx::inject_key("Space", true));
        }
        if frame == 91 {
            assert(gfx::inject_key("Space", false));
            let ex, ey = eye_offset(reef[0]);
            paused_eye_x = ex; paused_eye_y = ey;
        }
        if frame == 98 {
            let ex, ey = eye_offset(reef[0]);
            assert(ex == paused_eye_x && ey == paused_eye_y);
        }
    };
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
                    if pixels[offset] > 145 && pixels[offset + 1] > 145 && pixels[offset + 2] > 145 { total += x as f32; count++; }
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
    assert(abs(eye_now) > eye_start * 0.7); // broadside again, allowing for the climb's pitch,
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
                        if pixels[offset] > 145 && pixels[offset + 1] > 145 && pixels[offset + 2] > 145 {
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
    let filled = run(directory, 90, false) { frame, reef, selected =>
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
        if frame == 77 { assert(gfx::inject_text("Bubbles")); }
        if frame == 78 { assert(gfx::inject_key("Return", true)); }
        if frame == 79 { assert(gfx::inject_key("Return", false)); }
    };
    assert(filled.len == 1 && filled[0].name == "Bubbles" && valid_points(filled[0].points));
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
        if frame == 89 { assert(gfx::inject_text("Coral")); }
        if frame == 90 { assert(gfx::inject_key("Return", true)); }
        if frame == 91 { assert(gfx::inject_key("Return", false)); }
    };
    assert(shaped.len == 1 && shaped[0].name == "Coral" && valid_points(shaped[0].points));
    assert(delete_file(save_path));
    print("PASS: growth migration and restart, mature-S selection, real Delete button and key, empty restart, dragging, pause, saved positions, filled pitch in both directions, paused pitch, the animated turn, and studio Fill / Undo / Redo / Ctrl+Z / Ctrl+Y / shapes / hex / swatches / eyedropper / save");
}
