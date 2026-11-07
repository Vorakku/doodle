import std;
import math;
import vec;
import os;
import gfx;
import ui;
import reef_model;
import wallpaper_platform;
import canvas_view;
import reef_fill;
import reef_color;
import reef_shapes;
import reef_growth;
import reef_image_data;
import reef_images;

let FONT: const u8[:] = embed_file("assets/Roboto-Regular.ttf");
let PALETTE: u8[4][6] = [[255, 190, 108, 255], [255, 126, 140, 255],
    [129, 218, 195, 255], [143, 187, 255, 255], [207, 162, 243, 255], [242, 245, 232, 255]];

let SWATCHES: u8[4][8] = [[255, 190, 108, 255], [255, 126, 140, 255], [129, 218, 195, 255], [143, 187, 255, 255],
    [207, 162, 243, 255], [242, 245, 232, 255], [255, 228, 92, 255], [18, 26, 34, 255]];
let RAIL_TOOLS: Tool[10] = [Tool.Draw, Tool.Fill, Tool.Line, Tool.Rectangle, Tool.Circle,
    Tool.Triangle, Tool.Diamond, Tool.Hexagon, Tool.Star, Tool.Heart];

fn color(c: u8[4]) -> ui::Color { ui::Color { c[0], c[1], c[2], c[3] } }

fn text(ctx: ui::Context, x: f32, y: f32, w: f32, message: const u8[:], c: ui::Color) {
    ui::draw_text(ctx, ui::rect(x, y, w, 24.0), message, ui::font(ctx),
                  ui::rgba(0, 0, 0, 0), c);
}

fn fish_label(ctx: ui::Context, center: f32, y: f32, message: const u8[:], c: ui::Color) {
    let width = ceil(ui::text_width(ui::font(ctx), message)) + 4.0;
    let x = center - width * 0.5;
    text(ctx, x + 1.0, y + 1.0, width, message, ui::rgb(4, 20, 26));
    text(ctx, x, y, width, message, c);
}

// Pieces share fixed positions along the drawing, so every row bends with the swim wave identically and no seam opens.
fn draw_fill_row(ctx: ui::Context, x0: f32, x1: f32, y: f32, height: f32, b: Bounds, scale: f32, ox: f32, oy: f32,
                 phase: f32, swim: bool, turn: TurnView, clip: Bounds, c: ui::Color) {
    let left = min(x0, x1);
    let right = max(x0, x1);
    let step = if swim { b.w / 6.0 } else { max(1.0, right - left + 1.0) };
    var piece = if swim { floor((left - b.x) / step) as! i64 } else { 0 };
    var start = left;
    while start < right {
        let end = if swim { min(right, b.x + (piece + 1) * step) } else { right };
        let wave = if swim { sin(phase + (piece + 0.5) * step / b.w * 3.0) * wave_height(turn.across) } else { 0.0 };
        let along0 = (start - b.x - b.w * 0.5) * scale;
        let along1 = (end - b.x - b.w * 0.5) * scale;
        let middle = ox + b.w * scale * 0.5;
        if swim {
            let down = (y - b.y - b.h * 0.5) * scale;
            let wave0 = sin(phase + (start - b.x) / b.w * 3.0) * wave_height(turn.across);
            let wave1 = sin(phase + (end - b.x) / b.w * 3.0) * wave_height(turn.across);
            let ax, ay, an = body_point(turn, along0, down + wave0);
            let bx, by, bn = body_point(turn, along1, down + wave1);
            let cx, cy, cn = body_point(turn, along1, down + wave1 + height);
            let dx, dy, dn = body_point(turn, along0, down + wave0 + height);
            let middle_y = oy + b.h * scale * 0.5;
            var quad: float2[4] = [float2 { middle + ax, middle_y + ay }, float2 { middle + bx, middle_y + by },
                                   float2 { middle + cx, middle_y + cy }, float2 { middle + dx, middle_y + dy }];
            // Nuklear's anti-aliasing needs the same winding after the left/right mirror.
            if turn.across > 0.0 {
                quad[1] = float2 { middle + dx, middle_y + dy };
                quad[3] = float2 { middle + bx, middle_y + by };
            }
            ui::fill_polygon(ctx, quad, c);
            start = end;
            piece++;
            continue;
        }
        let edge0 = middle + along0 * turn.across * turn_nearness(turn, along0);
        let edge1 = middle + along1 * turn.across * turn_nearness(turn, along1);
        let sx0 = floor(min(edge0, edge1));
        let sx1 = ceil(max(edge0, edge1));
        let near = turn_nearness(turn, (along0 + along1) * 0.5);
        let sy = oy + b.h * scale * 0.5 + ((y - b.y - b.h * 0.5) * scale + wave) * near;
        let bar = intersect_area(Bounds { sx0, floor(sy), sx1 - sx0, ceil(height * near) }, clip);
        if bar.w > 0.0 && bar.h > 0.0 { ui::fill_rect(ctx, ui::rect(bar.x, bar.y, bar.w, bar.h), 0.0, c); }
        start = end;
        piece++;
    }
}

// Fills go underneath all the lines, so outlines stay crisp and hide the fill's stepped edge.
fn draw_fills(ctx: ui::Context, points: const Point[:], b: Bounds, scale: f32, ox: f32, oy: f32,
              phase: f32, swim: bool, turn: TurnView, clip: Bounds) {
    // Small swimming fish have several rows per pixel, and skipping the extras keeps the wallpaper cheap.
    let min_step: f32 = if swim { 1.0 } else { 0.0 };
    var row_start: f32 = 0.0;
    var row_y: f32 = -1.0;
    var kept: f32 = -1.0e9;
    var draw_row = true;
    for p in points {
        let row_height = fill_row_height(p.width);
        if row_height == 0.0 { continue; }
        if !p.start {
            let height = ceil(max(row_height * scale, min_step + 1.0));
            if draw_row { draw_fill_row(ctx, row_start, p.x, p.y, height, b, scale, ox, oy, phase, swim, turn, clip, color(p.color)); }
            continue;
        }
        row_start = p.x;
        if p.y != row_y {
            row_y = p.y;
            let px = p.y * scale;
            draw_row = px < kept || px >= kept + min_step;
            if draw_row { kept = px; }
        }
    }
}

fn draw_points(ctx: ui::Context, points: const Point[:], area: ui::Rect,
               phase: f32, swim: bool, heading: f32,
               pitch: f32 = 0.0,
               document: Bounds = Bounds { 0.0, 0.0, 1.0, 1.0 },
               clip: Bounds = Bounds { 0.0, 0.0, 16384.0, 16384.0 }) {
    let b = if swim { drawing_bounds(points) } else { document };
    let turn = turn_view(heading, area.w, if swim { pitch } else { 0.0 });
    // Fit the rotated artwork inside its existing selection and drag area.
    let scale = min(area.w / (b.w * abs(turn.tilt_cos) + b.h * abs(turn.tilt_sin)),
                    area.h / (b.w * abs(turn.tilt_sin) + b.h * abs(turn.tilt_cos)));
    let ox = area.x + (area.w - b.w * scale) * 0.5;
    let oy = area.y + (area.h - b.h * scale) * 0.5;
    draw_fills(ctx, points, b, scale, ox, oy, phase, swim, turn, clip);
    var last = float2 { 0.0, 0.0 };
    for p in points {
        if fill_row_height(p.width) > 0.0 { continue; }
        let along = (p.x - b.x - b.w * 0.5) * scale;
        let down = (p.y - b.y - b.h * 0.5) * scale +
            (if swim { sin(phase + (p.x - b.x) / b.w * 3.0) * wave_height(turn.across) } else { 0.0 });
        let px, py, near = body_point(turn, along, down);
        let x = ox + b.w * scale * 0.5 + px;
        let y = oy + b.h * scale * 0.5 + py;
        // Whole pixels, because line widths get truncated and would come out thinner than the round joints.
        let width = max(1.0, round(p.width * scale * near));
        if !p.start {
            let ax, ay, bx, by, visible = clip_line(last.x, last.y, x, y, clip, width * 0.5);
            if visible { ui::stroke_line(ctx, ax, ay, bx, by, width, color(p.color)); }
        }
        if x + width * 0.5 >= clip.x && x - width * 0.5 <= clip.x + clip.w &&
           y + width * 0.5 >= clip.y && y - width * 0.5 <= clip.y + clip.h {
            ui::fill_circle(ctx, ui::rect(x - width * 0.5, y - width * 0.5, width, width), color(p.color));
        }
        last = float2 { x, y };
    }
}

fn demo() -> Creature {
    var fish = Creature { x: 0.4, y: 0.46, speed: 0.055, phase: 0.0, points: [] };
    for i in 49 {
        let angle = i as f32 / 48.0 * 6.2831853;
        fish.points.push(Point { 0.51 + cos(angle) * 0.27, 0.5 + sin(angle) * 0.18,
                                 0.018, PALETTE[0], i == 0 });
    }
    fish.points.push(Point { 0.25, 0.5, 0.018, PALETTE[0], true });
    fish.points.push(Point { 0.08, 0.33, 0.018, PALETTE[0], false });
    fish.points.push(Point { 0.08, 0.67, 0.018, PALETTE[0], false });
    fish.points.push(Point { 0.25, 0.5, 0.018, PALETTE[0], false });
    fish.points.push(Point { 0.65, 0.46, 0.035, PALETTE[5], true });
    return fish;
}

// Coordinates are 0..1 inside the box.
fn icon_path(ctx: ui::Context, box: ui::Rect, path: const f32[2][:], closed: bool, thickness: f32, c: ui::Color) {
    var mapped: float2[>..] = [];
    for p in path { mapped.push(float2 { box.x + p[0] * box.w, box.y + p[1] * box.h }); }
    if closed { ui::stroke_polygon(ctx, mapped, thickness, c); } else { ui::stroke_polyline(ctx, mapped, thickness, c); }
}

fn icon_box(slot: ui::Rect, margin: f32) -> ui::Rect {
    let size = max(4.0, min(slot.w, slot.h) - margin * 2.0);
    return ui::rect(slot.x + (slot.w - size) * 0.5, slot.y + (slot.h - size) * 0.5, size, size);
}

fn draw_pencil_icon(ctx: ui::Context, box: ui::Rect, c: ui::Color) {
    let body: f32[2][5] = [[0.72, 0.06], [0.94, 0.28], [0.32, 0.90], [0.06, 0.94], [0.10, 0.68]];
    let band: f32[2][2] = [[0.58, 0.20], [0.80, 0.42]];
    icon_path(ctx, box, body, true, 2.0, c);
    icon_path(ctx, box, band, false, 2.0, c);
}

fn draw_bucket_icon(ctx: ui::Context, box: ui::Rect, c: ui::Color) {
    let can: f32[2][4] = [[0.40, 0.14], [0.80, 0.54], [0.44, 0.90], [0.04, 0.50]];
    let handle: f32[2][2] = [[0.40, 0.14], [0.26, 0.00]];
    let level: f32[2][2] = [[0.08, 0.50], [0.76, 0.50]];
    icon_path(ctx, box, can, true, 2.0, c);
    icon_path(ctx, box, handle, false, 2.0, c);
    icon_path(ctx, box, level, false, 2.0, c);
    ui::fill_circle(ctx, ui::rect(box.x + box.w * 0.80, box.y + box.h * 0.70, box.w * 0.20, box.h * 0.24), c);
}

fn draw_dropper_icon(ctx: ui::Context, box: ui::Rect, c: ui::Color) {
    let tube: f32[2][5] = [[0.60, 0.26], [0.74, 0.40], [0.26, 0.88], [0.08, 0.92], [0.12, 0.74]];
    let collar: f32[2][2] = [[0.50, 0.16], [0.84, 0.50]];
    icon_path(ctx, box, tube, true, 2.0, c);
    icon_path(ctx, box, collar, false, 2.5, c);
    ui::fill_circle(ctx, ui::rect(box.x + box.w * 0.62, box.y + box.h * 0.04, box.w * 0.34, box.h * 0.34), c);
}

fn draw_tool_icon(ctx: ui::Context, tool: Tool, slot: ui::Rect, active: bool) {
    if active { ui::fill_rect(ctx, slot, 4.0, ui::rgb(129, 218, 195)); }
    let c = if active { ui::rgb(12, 38, 44) } else { ui::rgb(224, 238, 230) };
    let box = icon_box(slot, 9.0);
    if tool == Tool.Draw { draw_pencil_icon(ctx, box, c); }
    else if tool == Tool.Fill { draw_bucket_icon(ctx, box, c); }
    else {
        // Icon points snap to whole pixels, so curves look smoother with fewer of them.
        let stride = if tool == Tool.Circle || tool == Tool.Heart { 4 } else { 1 };
        let outline = shape_outline(tool);
        var mapped: float2[>..] = [];
        for i in outline.len {
            if i % stride == 0 { mapped.push(float2 { box.x + outline[i].x * box.w, box.y + outline[i].y * box.h }); }
        }
        ui::stroke_polyline(ctx, mapped, 2.0, c);
    }
}

// The saturation and brightness square, with the white ring from the picker it's modelled on.
fn color_square(ctx: ui::Context, picked: Hsv&, dragging: i64&) {
    ui::layout_row_dynamic(ctx, 160.0, 1);
    let state, slot = ui::widget(ctx);
    let mouse = ui::input_mouse(ctx).pos;
    if state == ui::WIDGET_VALID && ui::input_is_mouse_pressed(ctx, ui::BUTTON_LEFT) &&
       ui::input_is_mouse_hovering_rect(ctx, slot) { dragging = 1; }
    if dragging == 1 {
        picked.s = clamp((mouse.x - slot.x) / max(1.0, slot.w), 0.0, 1.0);
        picked.v = 1.0 - clamp((mouse.y - slot.y) / max(1.0, slot.h), 0.0, 1.0);
    }
    let hue = color(hsv_to_rgb(Hsv { picked.h, 1.0, 1.0 }));
    let white = ui::rgb(255, 255, 255);
    let clear = ui::rgba(0, 0, 0, 0);
    let black = ui::rgb(0, 0, 0);
    ui::fill_rect_multi_color(ctx, slot, white, hue, hue, white);
    ui::fill_rect_multi_color(ctx, slot, clear, clear, black, black);
    let x = slot.x + picked.s * slot.w;
    let y = slot.y + (1.0 - picked.v) * slot.h;
    ui::fill_circle(ctx, ui::rect(x - 8.0, y - 8.0, 16.0, 16.0), white);
    ui::fill_circle(ctx, ui::rect(x - 5.0, y - 5.0, 10.0, 10.0), color(hsv_to_rgb(picked)));
}

fn hue_slider(ctx: ui::Context, picked: Hsv&, dragging: i64&) {
    let state, slot = ui::widget(ctx);
    let mouse = ui::input_mouse(ctx).pos;
    if state == ui::WIDGET_VALID && ui::input_is_mouse_pressed(ctx, ui::BUTTON_LEFT) &&
       ui::input_is_mouse_hovering_rect(ctx, slot) { dragging = 2; }
    if dragging == 2 { picked.h = clamp((mouse.x - slot.x) / max(1.0, slot.w), 0.0, 1.0); }
    for i in 6 {
        let a = color(hsv_to_rgb(Hsv { i / 6.0, 1.0, 1.0 }));
        let b = color(hsv_to_rgb(Hsv { (i + 1) / 6.0, 1.0, 1.0 }));
        let bar = ui::rect(slot.x + slot.w * i / 6.0, slot.y + 4.0, slot.w / 6.0 + 1.0, max(1.0, slot.h - 8.0));
        ui::fill_rect_multi_color(ctx, bar, a, b, b, a);
    }
    let x = slot.x + picked.h * slot.w;
    let y = slot.y + slot.h * 0.5;
    ui::fill_circle(ctx, ui::rect(x - 9.0, y - 9.0, 18.0, 18.0), ui::rgb(255, 255, 255));
    ui::fill_circle(ctx, ui::rect(x - 6.0, y - 6.0, 12.0, 12.0), color(hsv_to_rgb(Hsv { picked.h, 1.0, 1.0 })));
}

// Colours already in the drawing, oldest first, so they're easy to reuse.
fn used_colors(points: const Point[:]) -> u8[4][>..] {
    var found: u8[4][>..] = [];
    for p in points {
        var known = false;
        for c in found { if c == p.color { known = true; } }
        if !known { found.push(p.color); }
        if found.len == 8 { break; }
    }
    return found;
}

fn scene(ctx: ui::Context, w: f32, h: f32, time: f32, reef: const Creature[:], headings: const f32[:], motions: const SwimMotion[:], selected_fish: i64, images: ImageRenderer&,
         wallpaper: bool = false, names: bool = false) {
    let bounds = ui::rect(0.0, 0.0, w, h);
    ui::window_set_bounds(ctx, "Water", bounds);
    if ui::begin(ctx, "Water", bounds, ui::WINDOW_BACKGROUND | ui::WINDOW_NO_INPUT | ui::WINDOW_NO_SCROLLBAR) {
        ui::push_scissor(ctx, bounds);
        for i in 48 {
            let t = i as f32 / 47.0;
            ui::fill_rect(ctx, ui::rect(0.0, h * i / 48.0, w, h / 48.0 + 1.0), 0.0,
                ui::rgb((14.0 - t * 6.0) as! i64, (66.0 - t * 37.0) as! i64, (79.0 - t * 35.0) as! i64));
        }
        for i in 5 {
            let x = w * (0.1 + i * 0.24) + sin(time * 0.15 + i) * 12.0;
            ui::fill_triangle(ctx, x, 0.0, x + 38.0, 0.0, x + 180.0, h * 0.88, ui::rgba(131, 223, 210, 7));
        }
        for i in 22 {
            let seed = i as f32;
            let x = (seed * 157.0 + 39.0) % max(w, 1.0) + sin(time * 0.5 + seed) * 8.0;
            let y = h - ((time * (10.0 + seed % 5.0 * 3.0) + seed * 71.0) % max(h, 1.0));
            let size = 3.0 + seed % 4.0 * 2.0;
            ui::stroke_circle(ctx, ui::rect(x, y, size, size), 1.0, ui::rgba(158, 224, 223, 65));
        }
        ui::fill_rect(ctx, ui::rect(0.0, h - 36.0, w, 36.0), 0.0, ui::rgb(157, 143, 110));
        ui::fill_triangle(ctx, 0.0, h - 36.0, w * 0.24, h - 62.0, w * 0.65, h - 36.0, ui::rgb(176, 160, 121));
        ui::fill_triangle(ctx, w * 0.46, h - 36.0, w * 0.82, h - 52.0, w, h - 36.0, ui::rgb(187, 170, 129));
        for plant in 11 {
            let x = (plant * 133.0 + 24.0) % max(w, 1.0);
            let height = 40.0 + (plant % 4) as f32 * 18.0;
            for stem in 3 {
                var last = float2 { x + stem * 7.0, h - 39.0 };
                for j in 1..12 {
                    let t = j as f32 / 11.0;
                    let next = float2 { x + stem * 7.0 + sin(time * 0.8 + t * 2.5 + plant) * t * 13.0,
                                         h - 39.0 - t * height };
                    ui::stroke_line(ctx, last.x, last.y, next.x, next.y, 4.0, ui::rgb(49, 127 + plant % 3 * 12, 111));
                    last = next;
                }
            }
        }
        // Turning creatures are further back, so they go behind the others.
        for pass in 2 {
            for i in reef.len {
                if (headings[i] > 0.0 && headings[i] < 1.0) != (pass == 0) { continue; }
                let fish .= reef[i];
                let area = creature_area(fish, w, h);
                let box = ui::rect(area.x, area.y, area.w, area.h);
                if i == selected_fish { ui::stroke_rect(ctx, box, 10.0, 2.0, ui::rgb(129, 218, 195)); }
                if fish.image_id == 0 { draw_points(ctx, fish.points, box, fish.phase, true, headings[i], motions[i].pitch); }
                else {
                    let pose = if i < images.slots.len {
                        render_image_pose(images, images.slots[i], box.w, box.h, fish.phase, true, headings[i], motions[i].pitch, fish.image_flip)
                    } else { gfx::Texture { 0 } };
                    if pose.id != 0 {
                        ui::draw_image(ctx, ui::rect(box.x - 8.0, box.y - 8.0, box.w + 16.0, box.h + 16.0),
                            ui::texture_image(pose), ui::rgb(255, 255, 255));
                    } else {
                        ui::stroke_rect(ctx, box, 2.0, 1.0, ui::rgb(129, 218, 195));
                        ui::stroke_line(ctx, box.x, box.y, box.x + box.w, box.y + box.h, 1.0, ui::rgb(129, 218, 195));
                    }
                }
            }
        }
        // After every fish, so no fish hides a label.
        if names {
            for i in reef.len {
                let fish .= reef[i];
                if fish.name.len == 0 { continue; }
                let area = creature_area(fish, w, h);
                let center = area.x + area.w * 0.5;
                // Always leaves room for the tier above the footer, so selecting never moves the name.
                let y = min(area.y + area.h + 2.0, h - 114.0);
                fish_label(ctx, center, y, fish.name, ui::rgb(232, 244, 240));
                if i == selected_fish && fish.tier >= 0 {
                    fish_label(ctx, center, y + 18.0, str("Tier ", TIER_NAMES[fish.tier]), ui::rgb(129, 218, 195));
                }
            }
        }
        if !wallpaper { text(ctx, 26.0, h - 32.0, w - 52.0, "A little ocean. Entirely yours.", ui::rgb(42, 61, 58)); }
    }
    ui::end(ctx);
}

fn run<FRAME>(directory: const u8[:], frames: i64, initial_studio: bool,
              wallpaper: bool = false, fps: i64 = 60, output: const u8[:] = "") -> Creature[>..] {
    assert(fps > 0 && fps <= 120);
    var studio = initial_studio;
    let background_button = !wallpaper && reef_background_button_available();
    let save_path = str(directory, "/creatures.reef");
    var reef: Creature[>..] = [];
    var status: u8[>..] = [];
    var known_image: u8[>..] = [];
    var growth_random = rng { random_seed() };
    var needs_growth = false;
    var save_ok = !wallpaper && make_dir(directory);
    if file_exists(save_path) {
        var raw: u8[>..] = [];
        if read_file(save_path, raw) {
            known_image.append(raw);
            let loaded, ok = decode_reef(raw);
            if ok {
                reef.append(loaded);
                needs_growth = raw[..8] != SAVE_HEADER;
            }
            else { save_ok = false; status.append("Save could not be read. Original file preserved; saving disabled."); }
        } else { save_ok = false; status.append("Cannot read save. Saving disabled to protect your drawings."); }
    }
    if !wallpaper && !save_ok && status.len == 0 { status.append("Cannot create data folder. Saving is unavailable."); }
    if wallpaper && status.len > 0 { write_stderr(str(status, "\n")); }
    if reef.len == 0 && !file_exists(save_path) { reef.push(demo()); needs_growth = true; }
    if needs_growth {
        if wallpaper { write_stderr("Open the updated editor once to upgrade this aquarium's saved metadata.\n"); }
        else if save_ok && !upgrade_growth(reef, save_path, known_image, time(), growth_random) {
            save_ok = false;
            status.clear(); status.append("Could not back up or upgrade saved fish. Original preserved; saving disabled.");
        }
    }
    if wallpaper && !reef_wallpaper_prepare(output) { exit(1); }
    guard gfx::open("DOODLE REEF", 1100, 760, gfx::WINDOW_RESIZABLE) else {
        if wallpaper { reef_wallpaper_stop(); }
        write_stderr(str("Cannot open aquarium: ", gfx::error(), "\n")); exit(1);
    }
    if wallpaper && !reef_wallpaper_ready() {
        reef_wallpaper_stop(); gfx::close();
        write_stderr("Wallpaper host setup failed. Linux requires build-linux.sh; Windows requires Lively.\n");
        exit(1);
    }
    let ctx = ui::create_from_memory(FONT, 17.0);
    guard ctx.id != 0 else {
        write_stderr(str("Cannot create interface: ", ui::error(), "\n"));
        if wallpaper { reef_wallpaper_stop(); }
        gfx::close(); exit(1);
    }
    var colors = ui::default_color_table();
    colors[ui::COLOR_WINDOW] = ui::rgb(18, 43, 52);
    colors[ui::COLOR_TEXT] = ui::rgb(224, 238, 230);
    colors[ui::COLOR_BORDER] = ui::rgb(46, 83, 88);
    colors[ui::COLOR_BUTTON] = ui::rgb(38, 89, 94);
    colors[ui::COLOR_BUTTON_HOVER] = ui::rgb(49, 117, 118);
    colors[ui::COLOR_BUTTON_ACTIVE] = ui::rgb(67, 137, 130);
    colors[ui::COLOR_TOGGLE_CURSOR] = ui::rgb(129, 218, 195);
    ui::style_from_table(ctx, colors);

    var points: Point[>..] = [];
    var fills: FillRange[>..] = [];
    var tool = Tool.Draw;
    var picked = rgb_to_hsv(SWATCHES[0], 0.0);
    var color_drag = 0;
    var picking_color = false;
    var hex_text: u8[..6] = [];
    var hex_editing = false;
    var naming = false;
    var naming_focus = false;
    var fish_name: u8[..128] = [];
    var name_error: u8[>..] = [];
    var imported = ImageData {};
    var imported_png: u8[>..] = [];
    var imported_slot = ImageSlot {};
    var images = ImageRenderer {};
    var import_pending = false;
    var clear_image_slot = false;
    var shape_active = false;
    var shape_x: f32 = 0.0;
    var shape_y: f32 = 0.0;
    var visible = 0;
    var selected_fish = -1;
    var dragging_fish = -1;
    var grab_x: f32 = 0.0;
    var grab_y: f32 = 0.0;
    var moved = false;
    var brush = 7;
    var paused = false;
    var drawing = false;
    var canvas_view = CanvasView {};
    var canvas_aspect: f32 = 0.0;
    var canvas_extent: f32 = 1100.0;
    var panning = false;
    var swim_time: f32 = 0.0;
    var headings: f32[>..] = [];
    var motions: SwimMotion[>..] = [];
    var drawn = 0;
    var next_reload = clock() + 1.0;
    loop {
        FRAME(drawn, reef[..], selected_fish);
        if !gfx::frame() { break; }
        let started = clock();
        let dt = min(gfx::delta_time(), 0.05) as! f32;
        if wallpaper && !reef_wallpaper_alive() { break; }
        if wallpaper && started >= next_reload {
            next_reload = started + 1.0;
            var raw: u8[>..] = [];
            if read_file(save_path, raw) && raw != known_image {
                known_image.clear(); known_image.append(raw);
                let loaded, ok = decode_reef(raw);
                if ok { reef.resize(0); reef.append(loaded); }
                else { write_stderr("Ignoring an unreadable creature save; keeping the current aquarium.\n"); }
            }
        }
        let screen = gfx::screen_size();
        let w = screen.x as f32;
        let h = screen.y as f32;
        if import_pending {
            var chosen_path: u8[4096] = [0; 4096];
            let chosen = reef_image_dialog_result(chosen_path);
            if chosen != 0 {
                import_pending = false;
                if chosen > 0 {
                    let image, png, error = load_png_image(chosen_path[..chosen], directory);
                    status.clear();
                    if error.len > 0 { status.append(error); }
                    else if !prepare_image_slot(imported_slot, image) { status.append("Cannot prepare the image for display."); }
                    else {
                        imported = copy(image); imported_png = copy(png);
                        canvas_view = CanvasView {}; canvas_aspect = 0.0;
                        drawing = false; shape_active = false; panning = false;
                        status.append("Image ready. Bring it to life to name and save it.");
                    }
                } else if chosen == -2 { status.clear(); status.append("The image picker could not open the selected path."); }
            }
        }
        var cancel_naming = false;
        if !wallpaper {
            ui::input_from_gfx(ctx);
            if gfx::key_pressed("Escape") {
                if naming { cancel_naming = true; }
                else {
                    studio = false; drawing = false;
                    if selected_fish >= 0 && save_ok { status.clear(); }
                    selected_fish = -1; dragging_fish = -1;
                }
            }
            if gfx::key_pressed("Space") && !studio { paused = !paused; }
            let toolbar = ui::rect(20.0, 18.0, max(260.0, w - 40.0), 64.0);
            ui::window_set_bounds(ctx, "Controls", toolbar);
            if ui::begin(ctx, "Controls", toolbar, ui::WINDOW_NO_SCROLLBAR) {
                if naming || import_pending { ui::widget_disable_begin(ctx); }
                let ratios: f32[4] = [0.4, 0.27, 0.16, 0.17];
                ui::layout_row(ctx, ui::DYNAMIC, 42.0, ratios);
                if background_button {
                    if ui::button_label(ctx, "Set as desktop background") {
                        status.clear();
                        if !save_ok { status.append("Fix the save-folder error before setting the desktop background."); }
                        else if !write_file_atomic(save_path, encode_reef(reef)) {
                            status.append("Could not save the aquarium. Your desktop background was not changed.");
                        } else if reef_set_background(directory) {
                            status.append(if reef_background_uses_lively() { "Opening Lively to apply your aquarium. Complete setup there if prompted." }
                                          else { "Your aquarium is now the desktop background." });
                        } else { status.append("Could not set the desktop background. Rebuild the app or check the terminal, then try again."); }
                    }
                } else { ui::label(ctx, "DOODLE REEF", ui::TEXT_LEFT); }
                if ui::button_label(ctx, if studio { "Back to aquarium" } else { "Draw a creature" }) { studio = !studio; drawing = false; }
                if ui::button_label(ctx, if paused { "Resume" } else { "Pause" }) { paused = !paused; }
                if ui::button_label(ctx, "Reset swim") {
                    for i in reef.len { reef[i].x = 0.2 + (i % 5) * 0.14; reef[i].phase = 0.0; }
                }
                if naming || import_pending { ui::widget_disable_end(ctx); }
            }
            ui::end(ctx);

            if studio {
                if canvas_aspect == 0.0 {
                    canvas_aspect = max(1.0, w) / max(1.0, h);
                    canvas_extent = max(w, h);
                }
                let document = canvas_document(canvas_aspect);
                let ink = hsv_to_rgb(picked);
                let brush_width = clamp(brush / canvas_extent, 0.00001, 0.1);

                let rail = ui::rect(20.0, 98.0, 60.0, max(96.0, h - 194.0));
                ui::window_set_bounds(ctx, "Tools", rail);
                if ui::begin(ctx, "Tools", rail, ui::WINDOW_SCROLL_AUTO_HIDE) {
                    for t in RAIL_TOOLS {
                        // A gap between painting tools and shapes.
                        if t == Tool.Line { ui::layout_row_dynamic(ctx, 6.0, 1); let gap_state, gap_slot = ui::widget(ctx); }
                        ui::layout_row_dynamic(ctx, 38.0, 1);
                        let slot = ui::widget_bounds(ctx);
                        if ui::button_label(ctx, "") {
                            tool = t; picking_color = false; shape_active = false; drawing = false;
                            if save_ok { status.clear(); }
                        }
                        draw_tool_icon(ctx, t, slot, tool == t && !picking_color);
                        if ui::input_is_mouse_hovering_rect(ctx, slot) { ui::tooltip(ctx, tool_name(t)); }
                    }
                }
                ui::end(ctx);

                let canvas_panel = ui::rect(92.0, 98.0, max(120.0, w - 404.0), max(96.0, h - 194.0));
                var viewport = Bounds { canvas_panel.x, canvas_panel.y, canvas_panel.w, canvas_panel.h };
                ui::window_set_bounds(ctx, "Drawing canvas", canvas_panel);
                if ui::begin(ctx, "Drawing canvas", canvas_panel, ui::WINDOW_NO_SCROLLBAR) {
                    let region = ui::window_get_content_region(ctx);
                    ui::layout_row_dynamic(ctx, max(32.0, region.h - 8.0), 1);
                    let state, slot = ui::widget(ctx);
                    viewport = Bounds { slot.x, slot.y, slot.w, slot.h };
                    let mouse = ui::input_mouse(ctx);
                    let over_view = !naming && !import_pending && mouse.pos.x >= viewport.x && mouse.pos.x <= viewport.x + viewport.w &&
                                    mouse.pos.y >= viewport.y && mouse.pos.y <= viewport.y + viewport.h;
                    let down = ui::input_is_mouse_down(ctx, ui::BUTTON_LEFT);
                    let pressed = ui::input_is_mouse_pressed(ctx, ui::BUTTON_LEFT);
                    let middle = ui::input_is_mouse_down(ctx, ui::BUTTON_MIDDLE);
                    let pan_down = middle || (gfx::key_down("Space") && down);
                    if !pan_down { panning = false; }
                    if over_view && state == ui::WIDGET_VALID &&
                       (ui::input_is_mouse_pressed(ctx, ui::BUTTON_MIDDLE) || (pressed && gfx::key_down("Space"))) {
                        panning = true; drawing = false; shape_active = false;
                    }
                    if over_view && mouse.scroll_delta.y != 0.0 {
                        let zoom_step: f32 = 1.2;
                        zoom_canvas(canvas_view, viewport, document, mouse.pos.x, mouse.pos.y, pow(zoom_step, mouse.scroll_delta.y));
                        drawing = false;
                    }
                    if panning { pan_canvas(canvas_view, viewport, document, mouse.delta.x, mouse.delta.y); }
                    else { pan_canvas(canvas_view, viewport, document, 0.0, 0.0); }
                    let canvas = canvas_area(canvas_view, viewport, document);
                    let inside = over_view && mouse.pos.x >= canvas.x && mouse.pos.x <= canvas.x + canvas.w &&
                                 mouse.pos.y >= canvas.y && mouse.pos.y <= canvas.y + canvas.h;
                    let doc_x = (mouse.pos.x - canvas.x) / canvas.w * document.w;
                    let doc_y = (mouse.pos.y - canvas.y) / canvas.h * document.h;
                    let can_use = inside && state == ui::WIDGET_VALID && imported.rgba.len == 0;
                    var shape_end_x = clamp(doc_x, 0.0, document.w);
                    var shape_end_y = clamp(doc_y, 0.0, document.h);
                    if tool != Tool.Line && (gfx::key_down("Left Shift") || gfx::key_down("Right Shift")) {
                        shape_end_x, shape_end_y = constrain_square(shape_x, shape_y, shape_end_x, shape_end_y, document);
                    }
                    if !panning && picking_color {
                        drawing = false;
                        if pressed && can_use {
                            let found_color, found = color_at(points[..visible], doc_x, doc_y);
                            if found { picked = rgb_to_hsv(found_color, picked.h); picking_color = false; }
                            if save_ok {
                                status.clear();
                                if !found { status.append("No color there. Click on part of your drawing."); }
                            }
                        }
                    } else if !panning && tool == Tool.Fill {
                        drawing = false;
                        if pressed && can_use {
                            let result = fill_region(points, visible, fills, document, doc_x, doc_y, ink);
                            if save_ok {
                                status.clear();
                                if result == FillResult.OpenShape { status.append("That spot isn't enclosed. Close the gap in your outline, then try again."); }
                                else if result == FillResult.OnInk { status.append("Click inside the shape, not on its outline."); }
                                else if result == FillResult.NoRoom { status.append("Not enough drawing points left for this fill. Undo something first."); }
                            }
                        }
                    } else if !panning && is_shape(tool) {
                        drawing = false;
                        if pressed && can_use {
                            shape_active = true; shape_x = doc_x; shape_y = doc_y;
                        } else if shape_active && !down {
                            shape_active = false;
                            let added = add_shape(points, visible, fills, tool, shape_x, shape_y, shape_end_x, shape_end_y, brush_width, ink);
                            if save_ok {
                                status.clear();
                                if !added { status.append("Not enough drawing points left for this shape. Undo something first."); }
                            }
                        }
                    } else if !panning {
                        if pressed && can_use { drop_undone_fills(fills, visible); }
                        sample_stroke(points, visible, drawing, down, pressed, can_use, doc_x, doc_y, brush_width, ink);
                    }
                    ui::push_scissor(ctx, ui::rect(viewport.x, viewport.y, viewport.w, viewport.h));
                    ui::fill_rect(ctx, ui::rect(viewport.x, viewport.y, viewport.w, viewport.h), 0.0, ui::rgb(10, 26, 34));
                    let rows = clamp(ceil(24.0 * document.h / document.w) as! i64, 1, 96);
                    for row in rows {
                        for col in 24 {
                            let cell = Bounds { canvas.x + col * canvas.w / 24.0, canvas.y + row * canvas.h / rows,
                                                canvas.w / 24.0 + 1.0, canvas.h / rows + 1.0 };
                            let tile = intersect_area(intersect_area(cell, canvas), viewport);
                            if tile.w > 0.0 && tile.h > 0.0 {
                                ui::fill_rect(ctx, ui::rect(tile.x, tile.y, tile.w, tile.h), 0.0,
                                    if (row + col) % 2 == 0 { ui::rgb(34, 65, 72) } else { ui::rgb(30, 59, 67) });
                            }
                        }
                    }
                    let ink_clip = intersect_area(canvas, viewport);
                    ui::push_scissor(ctx, ui::rect(ink_clip.x, ink_clip.y, ink_clip.w, ink_clip.h));
                    let canvas_box = ui::rect(canvas.x, canvas.y, canvas.w, canvas.h);
                    if imported.rgba.len > 0 {
                        let pose = render_image_pose(images, imported_slot, canvas_box.w, canvas_box.h, 0.0, false, 1.0, 0.0, false);
                        if pose.id != 0 { ui::draw_image(ctx, ui::rect(canvas_box.x - 8.0, canvas_box.y - 8.0,
                            canvas_box.w + 16.0, canvas_box.h + 16.0), ui::texture_image(pose), ui::rgb(255, 255, 255)); }
                    } else { draw_points(ctx, points[..visible], canvas_box, 0.0, false, 1.0, 0.0, document, ink_clip); }
                    if shape_active {
                        draw_points(ctx, shape_points(tool, shape_x, shape_y, shape_end_x, shape_end_y, brush_width, ink),
                                    canvas_box, 0.0, false, 1.0, 0.0, document, ink_clip);
                    }
                }
                ui::end(ctx);

                let tools = ui::rect(max(92.0, w - 300.0), 98.0, 280.0, max(96.0, h - 194.0));
                ui::window_set_bounds(ctx, "Studio tools", tools);
                if ui::begin(ctx, "Studio tools", tools, ui::WINDOW_SCROLL_AUTO_HIDE) {
                    if !ui::input_is_mouse_down(ctx, ui::BUTTON_LEFT) { color_drag = 0; }
                    color_square(ctx, picked, color_drag);

                    let hue_ratios: f32[2] = [0.16, 0.84];
                    ui::layout_row(ctx, ui::DYNAMIC, 26.0, hue_ratios);
                    let dropper_slot = ui::widget_bounds(ctx);
                    if ui::button_label(ctx, "") {
                        picking_color = !picking_color; shape_active = false; drawing = false;
                        if save_ok { status.clear(); if picking_color { status.append("Click on your drawing to pick up its color."); } }
                    }
                    if picking_color { ui::fill_rect(ctx, dropper_slot, 4.0, ui::rgb(129, 218, 195)); }
                    draw_dropper_icon(ctx, icon_box(dropper_slot, 4.0), if picking_color { ui::rgb(12, 38, 44) } else { ui::rgb(224, 238, 230) });
                    if ui::input_is_mouse_hovering_rect(ctx, dropper_slot) { ui::tooltip(ctx, "Pick a color from your drawing"); }
                    hue_slider(ctx, picked, color_drag);

                    let hex_ratios: f32[2] = [0.16, 0.84];
                    ui::layout_row(ctx, ui::DYNAMIC, 30.0, hex_ratios);
                    let preview = ui::widget_bounds(ctx);
                    ui::spacing(ctx, 1);
                    ui::fill_rect(ctx, preview, 4.0, color(hsv_to_rgb(picked)));
                    if !hex_editing { hex_text.clear(); hex_text.append(color_hex(hsv_to_rgb(picked))); }
                    let hex_state = ui::edit_string(ctx, ui::EDIT_FIELD | ui::EDIT_SIG_ENTER, hex_text, ui::FILTER_HEX);
                    hex_editing = (hex_state & ui::EDIT_ACTIVE) != 0;
                    if hex_editing {
                        let typed, typed_ok = parse_hex(hex_text);
                        if typed_ok { picked = rgb_to_hsv(typed, picked.h); }
                    }
                    if (hex_state & ui::EDIT_COMMITTED) != 0 { ui::edit_unfocus(ctx); }

                    ui::layout_row_dynamic(ctx, 26.0, 8);
                    for c in SWATCHES { if ui::button_color(ctx, color(c)) { picked = rgb_to_hsv(c, picked.h); } }
                    ui::layout_row_dynamic(ctx, 20.0, 1);
                    ui::label(ctx, "In this drawing", ui::TEXT_LEFT);
                    ui::layout_row_dynamic(ctx, 26.0, 8);
                    let used = used_colors(points[..visible]);
                    for c in used { if ui::button_color(ctx, color(c)) { picked = rgb_to_hsv(c, picked.h); } }
                    // An empty widget, because spacing here adds a phantom row and pushes the panel down.
                    for i in 8 - used.len { let empty_state, empty_slot = ui::widget(ctx); }

                    ui::layout_row_dynamic(ctx, 26.0, 1);
                    ui::property_int(ctx, "Brush size", 2, brush, 24, 1, 1.0);
                    ui::layout_row_dynamic(ctx, 30.0, 3);
                    if ui::button_label(ctx, "-") {
                        zoom_canvas(canvas_view, viewport, document, viewport.x + viewport.w * 0.5, viewport.y + viewport.h * 0.5, 1.0 / 1.2);
                        drawing = false;
                    }
                    if ui::button_label(ctx, "Fit") { canvas_view = CanvasView {}; drawing = false; }
                    if ui::button_label(ctx, "+") {
                        zoom_canvas(canvas_view, viewport, document, viewport.x + viewport.w * 0.5, viewport.y + viewport.h * 0.5, 1.2);
                        drawing = false;
                    }
                    ui::layout_row_dynamic(ctx, 22.0, 1);
                    ui::label(ctx, str(round(canvas_view.zoom * 100.0) as! i64, "% / Scroll to zoom"), ui::TEXT_LEFT);
                    ui::label(ctx, "Middle drag / Space + drag", ui::TEXT_LEFT);
                    ui::layout_row_dynamic(ctx, 30.0, 3);
                    // Not mid-stroke, where the next mouse sample would bring the undone points straight back.
                    let shortcuts = (gfx::key_down("Left Ctrl") || gfx::key_down("Right Ctrl")) && !drawing && !shape_active && !naming && !import_pending && imported.rgba.len == 0 && !ui::wants_keyboard(ctx);
                    if imported.rgba.len > 0 || import_pending { ui::widget_disable_begin(ctx); }
                    let undo_clicked = ui::button_label(ctx, "Undo");
                    let redo_clicked = ui::button_label(ctx, "Redo");
                    if imported.rgba.len > 0 || import_pending { ui::widget_disable_end(ctx); }
                    if (undo_clicked || (shortcuts && gfx::key_pressed("Z"))) && visible > 0 { visible = undo_position(points, visible, fills); }
                    if (redo_clicked || (shortcuts && gfx::key_pressed("Y"))) && visible < points.len { visible = redo_position(points, visible, fills); }
                    if ui::button_label(ctx, "Clear") {
                        points.resize(0); fills.clear(); visible = 0; canvas_aspect = 0.0; canvas_view = CanvasView {}; drawing = false; shape_active = false;
                        imported = ImageData {}; imported_png.clear(); clear_image_slot = true;
                    }
                    let release_ratios: f32[2] = [0.66, 0.34];
                    ui::layout_row(ctx, ui::DYNAMIC, 38.0, release_ratios);
                    let has_art = visible > 0 || imported.rgba.len > 0;
                    if !has_art || reef.len >= MAX_CREATURES || !save_ok || import_pending { ui::widget_disable_begin(ctx); }
                    let release = ui::button_label(ctx, "Bring to Life");
                    if !has_art || reef.len >= MAX_CREATURES || !save_ok || import_pending { ui::widget_disable_end(ctx); }
                    let can_import = points.len == 0 && imported.rgba.len == 0 && !naming && !import_pending && save_ok && reef.len < MAX_CREATURES;
                    let import_hover = ui::input_is_mouse_hovering_rect(ctx, ui::widget_bounds(ctx));
                    if !can_import { ui::widget_disable_begin(ctx); }
                    let import_clicked = ui::button_label(ctx, "Import");
                    if !can_import { ui::widget_disable_end(ctx); }
                    if import_clicked && can_import {
                        import_pending = reef_image_dialog_open();
                        if !import_pending { status.clear(); status.append("The image picker could not be opened."); }
                    }
                    if release && has_art && reef.len < MAX_CREATURES && save_ok {
                        naming = true; naming_focus = true; fish_name.clear(); name_error.clear();
                        drawing = false; shape_active = false; panning = false;
                    }
                    if naming {
                        let popup_w = min(380.0, w - 40.0);
                        let popup = ui::rect((w - popup_w) * 0.5 - tools.x, (h - 210.0) * 0.5 - tools.y, popup_w, 210.0);
                        if ui::popup_begin(ctx, ui::POPUP_STATIC, "Name your fish",
                                           ui::WINDOW_BORDER | ui::WINDOW_TITLE | ui::WINDOW_NO_SCROLLBAR, popup) {
                            ui::layout_row_dynamic(ctx, 24.0, 1);
                            ui::label(ctx, "Give your new fish a name", ui::TEXT_LEFT);
                            ui::layout_row_dynamic(ctx, 30.0, 1);
                            if naming_focus && !ui::input_is_mouse_down(ctx, ui::BUTTON_LEFT) &&
                               !ui::input_is_mouse_released(ctx, ui::BUTTON_LEFT) {
                                ui::edit_focus(ctx, ui::EDIT_FIELD); naming_focus = false;
                            }
                            let edit = ui::edit_string(ctx, ui::EDIT_FIELD | ui::EDIT_SIG_ENTER, fish_name, ui::FILTER_DEFAULT);
                            let named = valid_name(fish_name);
                            ui::layout_row_dynamic(ctx, 24.0, 1);
                            ui::label(ctx, if name_error.len > 0 { name_error } else { "1-32 characters. Cancel keeps your drawing." }, ui::TEXT_LEFT);
                            ui::layout_row_dynamic(ctx, 34.0, 2);
                            let cancel = ui::button_label(ctx, "Cancel") || cancel_naming;
                            if !named { ui::widget_disable_begin(ctx); }
                            let confirm = ui::button_label(ctx, "Bring to Life") || ((edit & ui::EDIT_COMMITTED) != 0 && named);
                            if !named { ui::widget_disable_end(ctx); }
                            if cancel {
                                naming = false; fish_name.clear(); name_error.clear();
                                ui::edit_unfocus(ctx); ui::popup_close(ctx);
                            } else if confirm && named && has_art && reef.len < MAX_CREATURES && save_ok {
                                var new_image_id: u64 = 0;
                                var asset_ok = true;
                                if imported.rgba.len > 0 {
                                    let id, ok = save_image(directory, imported, imported_png, growth_random);
                                    new_image_id = id; asset_ok = ok;
                                }
                                if !asset_ok {
                                    naming_focus = true; name_error.clear(); name_error.append("Could not save the image. Artwork kept; retry.");
                                } else {
                                var fish = Creature { x: 0.3, y: 0.25 + (reef.len % 4) * 0.15,
                                    speed: 0.035 + (reef.len % 5) * 0.009, phase: 0.0, points: [],
                                    tier: tier_from_roll(rand_int(growth_random, 100)), born: time(), name: [], image_id: new_image_id };
                                fish.name.append(clean_name(fish_name));
                                if new_image_id == 0 {
                                    fish.points.append(points[..visible]);
                                    let ink_bounds = drawing_bounds(fish.points);
                                    fish.size = min(1.0, max(ink_bounds.w, ink_bounds.h));
                                }
                                reef.push(fish);
                                if write_file_atomic(save_path, encode_reef(reef)) {
                                    points.resize(0); fills.clear(); visible = 0; studio = false; paused = false;
                                    imported = ImageData {}; imported_png.clear(); clear_image_slot = true;
                                    canvas_aspect = 0.0; canvas_view = CanvasView {}; drawing = false; panning = false;
                                    status.clear(); status.append(str(fish.name, " is swimming. Saved on this computer."));
                                    naming = false; fish_name.clear(); name_error.clear();
                                    ui::edit_unfocus(ctx); ui::popup_close(ctx);
                                } else {
                                    reef.resize(reef.len - 1);
                                    discard_new_image(directory, new_image_id);
                                    naming_focus = true;
                                    name_error.clear(); name_error.append("Could not save. Your artwork is kept; retry.");
                                }
                                }
                            }
                            ui::popup_end(ctx);
                        } else {
                            naming = false; ui::edit_unfocus(ctx);
                        }
                    }
                    ui::layout_row_dynamic(ctx, 24.0, 1);
                    let canvas_status: u8[>..] = if reef.len >= MAX_CREATURES { "Reef is full (12 creatures)." }
                        else if import_hover && (points.len > 0 || imported.rgba.len > 0) { "Clear the canvas to import a PNG." }
                        else if import_hover { "Import a transparent PNG." }
                        else if imported.rgba.len > 0 { "Image preview. Clear to draw instead." }
                        else if visible == MAX_POINTS { "Canvas is full. Undo, clear, or Bring to Life." }
                        else { str(visible, " / ", MAX_POINTS, " drawing points") };
                    ui::label(ctx, canvas_status, ui::TEXT_LEFT);
                    ui::layout_row_dynamic(ctx, 22.0, 1);
                    ui::label(ctx, "Tiny babies. Tier sets adult size.", ui::TEXT_LEFT);
                }
                ui::end(ctx);
            } else { shape_active = false; picking_color = false; }

            let has_selection = !studio && selected_fish >= 0 && selected_fish < reef.len;
            var want_delete = has_selection && save_ok && gfx::key_pressed("Delete") && !ui::wants_keyboard(ctx);
            var want_flip = false;
            let footer = ui::rect(20.0, h - 78.0, max(260.0, w - 40.0), 36.0);
            ui::window_set_bounds(ctx, "Status", footer);
            if ui::begin(ctx, "Status", footer, ui::WINDOW_NO_SCROLLBAR) {
                if has_selection {
                    let ratios: f32[3] = [0.56, 0.22, 0.22];
                    ui::layout_row(ctx, ui::DYNAMIC, 24.0, ratios);
                } else { ui::layout_row_dynamic(ctx, 24.0, 1); }
                let footer_text: u8[>..] = if status.len > 0 { copy(status) } else if has_selection && reef[selected_fish].tier >= 0 {
                    let fish .= reef[selected_fish];
                    let progress = growth_progress(fish.tier, fish.born, time());
                    str(fish.name, " / Tier ", TIER_NAMES[fish.tier], " / Growth ", floor(progress * 100.0) as! i64, "% / ",
                        if progress >= 1.0 { "Adult" } else { "Growing" })
                } else { str(reef.len, " creatures / Click a creature to select / Space to pause") };
                ui::label(ctx, footer_text, ui::TEXT_LEFT);
                if has_selection {
                    if !save_ok { ui::widget_disable_begin(ctx); }
                    if ui::button_label(ctx, "Flip fish") && save_ok { want_flip = true; }
                    if ui::button_label(ctx, "Delete fish (Del)") && save_ok { want_delete = true; }
                    if !save_ok { ui::widget_disable_end(ctx); }
                }
            }
            ui::end(ctx);
            // All UI windows must exist this frame before deciding a click belongs to the water.
            if !studio && ui::input_is_mouse_pressed(ctx, ui::BUTTON_LEFT) && !ui::wants_mouse(ctx) {
                let mouse = ui::input_mouse(ctx).pos;
                selected_fish = pick_creature(reef, mouse.x, mouse.y, w, h);
                dragging_fish = selected_fish;
                moved = false;
                if dragging_fish >= 0 {
                    let area = creature_area(reef[dragging_fish], w, h);
                    grab_x = mouse.x - (area.x + area.w * 0.5);
                    grab_y = mouse.y - (area.y + area.h * 0.5);
                }
                if save_ok {
                    status.clear();
                }
            }
            if dragging_fish >= 0 {
                if studio || !ui::input_is_mouse_down(ctx, ui::BUTTON_LEFT) {
                    if moved && save_ok {
                        status.clear();
                        if write_file_atomic(save_path, encode_reef(reef)) { status.append("Creature moved and saved."); }
                        else { status.append("Creature moved, but its new position could not be saved."); }
                    }
                    dragging_fish = -1;
                } else {
                    let mouse = ui::input_mouse(ctx).pos;
                    let fish .= reef[dragging_fish];
                    let old_x = fish.x;
                    let old_y = fish.y;
                    move_creature(fish, mouse.x - grab_x, mouse.y - grab_y, w, h);
                    moved = moved || abs(fish.x - old_x) + abs(fish.y - old_y) > 0.00001;
                }
            }
            if want_delete {
                status.clear();
                if delete_creature(reef, selected_fish, save_path) {
                    selected_fish = -1; dragging_fish = -1;
                    status.append("Creature deleted and saved.");
                } else { status.append("Could not save deletion. Your creature has been kept; try again."); }
            } else if want_flip {
                status.clear();
                if flip_creature(reef, selected_fish, save_path) { status.append("Creature flipped and saved. It will keep facing the way it swims."); }
                else { status.append("Could not save the flip. Your creature has been kept unchanged; try again."); }
            }
        }
        // Creatures were added or removed, so positions no longer line up: settle everyone straight away.
        if headings.len != reef.len {
            headings.resize(0);
            motions.resize(0);
            for fish in reef {
                headings.push(if fish.speed < 0.0 { 0.0 } else { 1.0 });
                motions.push(SwimMotion {});
            }
        }
        if !paused {
            let before = swim_time;
            swim_time += dt;
            for i in reef.len {
                headings[i] = step_heading(headings[i], reef[i].speed, dt);
                if i != dragging_fish {
                    swim(reef[i], motions[i], dt, turn_facing(headings[i]), i);
                    update_pitch(reef[i], motions[i], dt, w, h);
                    maybe_turn(reef[i], i, before, swim_time);
                }
            }
        }
        sync_image_slots(images, reef, directory);
        scene(ctx, w, h, swim_time, reef, headings, motions, if studio || wallpaper { -1 } else { selected_fish }, images, wallpaper, !studio && !wallpaper);
        gfx::begin_screen(float4 { 0.03, 0.1, 0.14, 1.0 });
        gfx::end_pass();
        ui::render(ctx);
        if clear_image_slot { release_image_slot(imported_slot); clear_image_slot = false; }
        if wallpaper { ui::clear(ctx); }
        drawn++;
        if drawn == frames {
            assert(gfx::screenshot(str(resource_dir(), "preview.png")));
            break;
        }
        sleep(max(0.0, 1.0 / fps - (clock() - started)));
    }
    release_image_slot(imported_slot);
    release_image_renderer(images);
    ui::destroy(ctx);
    if wallpaper { reef_wallpaper_stop(); }
    gfx::close();
    print("DOODLE REEF closed cleanly after ", drawn, " frames.");
    return reef;
}

fn main() {
    var frames = -1;
    var studio = false;
    var wallpaper = false;
    var fps: i64 = 0;
    var directory: u8[>..] = str(resource_dir(), "data");
    var output: u8[>..] = [];
    let argv = args();
    var i = 1;
    while i < argv.len {
        let option = argv[i];
        if option == "--studio" { studio = true; }
        else if option == "--wallpaper" { wallpaper = true; }
        else if option == "--frames" || option == "--fps" {
            if i + 1 >= argv.len { abort(str(option, " needs a positive integer")); }
            let n, ok = parse_int(argv[i + 1]);
            if !ok || n <= 0 || (option == "--fps" && n > 120) { abort(str("Invalid value for ", option)); }
            if option == "--frames" { frames = n; } else { fps = n; }
            i++;
        } else if option == "--data-dir" || option == "--output" {
            if i + 1 >= argv.len || argv[i + 1].len == 0 { abort(str(option, " needs a value")); }
            if option == "--data-dir" { directory.clear(); directory.append(argv[i + 1]); }
            else { output.clear(); output.append(argv[i + 1]); }
            i++;
        } else if option == "--help" {
            print("DOODLE REEF [--studio | --wallpaper] [--fps 1..120] [--data-dir PATH] [--output WAYLAND-MONITOR] [--frames N]");
            return;
        } else { abort(str("Unknown option: ", option)); }
        i++;
    }
    if wallpaper && studio { abort("Use --studio or --wallpaper, not both"); }
    if output.len > 0 && !wallpaper { abort("--output requires --wallpaper"); }
    if fps == 0 { fps = if wallpaper { 30 } else { 60 }; }
    run(directory, frames, studio, wallpaper, fps, output) { frame, reef, selected => };
}
