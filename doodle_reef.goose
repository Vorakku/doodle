import std;
import math;
import vec;
import os;
import gfx;
import ui;
import reef_model;
import wallpaper_platform;
import canvas_view;

let FONT: const u8[:] = embed_file("assets/Roboto-Regular.ttf");
let PALETTE: u8[4][6] = [[255, 190, 108, 255], [255, 126, 140, 255],
    [129, 218, 195, 255], [143, 187, 255, 255], [207, 162, 243, 255], [242, 245, 232, 255]];

fn color(c: u8[4]) -> ui::Color { ui::Color { c[0], c[1], c[2], c[3] } }

fn text(ctx: ui::Context, x: f32, y: f32, w: f32, message: const u8[:], c: ui::Color) {
    ui::draw_text(ctx, ui::rect(x, y, w, 24.0), message, ui::font(ctx),
                  ui::rgba(0, 0, 0, 0), c);
}

fn draw_points(ctx: ui::Context, points: const Point[:], area: ui::Rect,
               phase: f32, swim: bool, flip: bool,
               document: Bounds = Bounds { 0.0, 0.0, 1.0, 1.0 },
               clip: Bounds = Bounds { 0.0, 0.0, 16384.0, 16384.0 }) {
    let b = if swim { drawing_bounds(points) } else { document };
    let scale = min(area.w / b.w, area.h / b.h);
    let ox = area.x + (area.w - b.w * scale) * 0.5;
    let oy = area.y + (area.h - b.h * scale) * 0.5;
    var last = float2 { 0.0, 0.0 };
    for p in points {
        let x = ox + (if flip { b.x + b.w - p.x } else { p.x - b.x }) * scale;
        let y = oy + (p.y - b.y) * scale +
            (if swim { sin(phase + (p.x - b.x) / b.w * 3.0) * 3.0 } else { 0.0 });
        let width = max(1.0, p.width * scale);
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

fn scene(ctx: ui::Context, w: f32, h: f32, time: f32, reef: const Creature[:], selected_fish: i64,
         wallpaper: bool = false) {
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
        for i in reef.len {
            let fish .= reef[i];
            let area = creature_area(fish, w, h);
            let box = ui::rect(area.x, area.y, area.w, area.h);
            if i == selected_fish { ui::stroke_rect(ctx, box, 10.0, 2.0, ui::rgb(129, 218, 195)); }
            draw_points(ctx, fish.points, box, fish.phase, true, fish.speed < 0.0);
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
    var save_ok = !wallpaper && make_dir(directory);
    if file_exists(save_path) {
        var raw: u8[>..] = [];
        if read_file(save_path, raw) {
            known_image.append(raw);
            let loaded, ok = decode_reef(raw);
            if ok {
                reef.append(loaded);
                let backup = str(save_path, ".v1.bak");
                if !wallpaper && raw.len >= 8 && raw[..8] == LEGACY_SAVE_HEADER && !file_exists(backup) {
                    if !write_file_atomic(backup, raw) {
                        save_ok = false;
                        status.append("Could not back up the older save. Saving disabled to protect your drawings.");
                    }
                }
            }
            else { save_ok = false; status.append("Save could not be read. Original file preserved; saving disabled."); }
        } else { save_ok = false; status.append("Cannot read save. Saving disabled to protect your drawings."); }
    }
    if !wallpaper && !save_ok && status.len == 0 { status.append("Cannot create data folder. Saving is unavailable."); }
    if wallpaper && status.len > 0 { write_stderr(str(status, "\n")); }
    if reef.len == 0 && !file_exists(save_path) { reef.push(demo()); }
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
    ui::style_from_table(ctx, colors);

    var points: Point[>..] = [];
    var visible = 0;
    var selected = 0;
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
    var time: f32 = 0.0;
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
        if !wallpaper {
            ui::input_from_gfx(ctx);
            if gfx::key_pressed("Escape") {
                studio = false; drawing = false;
                if selected_fish >= 0 && save_ok { status.clear(); }
                selected_fish = -1; dragging_fish = -1;
            }
            if gfx::key_pressed("Space") && !studio { paused = !paused; }
            let toolbar = ui::rect(20.0, 18.0, max(260.0, w - 40.0), 64.0);
            ui::window_set_bounds(ctx, "Controls", toolbar);
            if ui::begin(ctx, "Controls", toolbar, ui::WINDOW_NO_SCROLLBAR) {
                let ratios: f32[4] = [0.4, 0.27, 0.16, 0.17];
                ui::layout_row(ctx, ui::DYNAMIC, 42.0, ratios);
                if background_button {
                    if ui::button_label(ctx, "Set as desktop background") {
                        status.clear();
                        if !save_ok { status.append("Fix the save-folder error before setting the desktop background."); }
                        else if !write_file_atomic(save_path, encode_reef(reef)) {
                            status.append("Could not save the aquarium. Your desktop background was not changed.");
                        } else if reef_set_background(directory) {
                            status.append("Opening Lively to apply your aquarium. Complete setup there if prompted.");
                        } else { status.append("Could not start wallpaper setup. Rebuild the app and try again."); }
                    }
                } else { ui::label(ctx, "DOODLE REEF", ui::TEXT_LEFT); }
                if ui::button_label(ctx, if studio { "Back to aquarium" } else { "Draw a creature" }) { studio = !studio; drawing = false; }
                if ui::button_label(ctx, if paused { "Resume" } else { "Pause" }) { paused = !paused; }
                if ui::button_label(ctx, "Reset swim") {
                    for i in reef.len { reef[i].x = 0.2 + (i % 5) * 0.14; reef[i].phase = 0.0; }
                }
            }
            ui::end(ctx);

            if studio {
                if canvas_aspect == 0.0 {
                    canvas_aspect = max(1.0, w) / max(1.0, h);
                    canvas_extent = max(w, h);
                }
                let document = canvas_document(canvas_aspect);
                let canvas_panel = ui::rect(20.0, 98.0, max(120.0, w - 300.0), max(96.0, h - 194.0));
                var viewport = Bounds { canvas_panel.x, canvas_panel.y, canvas_panel.w, canvas_panel.h };
                ui::window_set_bounds(ctx, "Drawing canvas", canvas_panel);
                if ui::begin(ctx, "Drawing canvas", canvas_panel, ui::WINDOW_NO_SCROLLBAR) {
                    let region = ui::window_get_content_region(ctx);
                    ui::layout_row_dynamic(ctx, max(32.0, region.h - 8.0), 1);
                    let state, slot = ui::widget(ctx);
                    viewport = Bounds { slot.x, slot.y, slot.w, slot.h };
                    let mouse = ui::input_mouse(ctx);
                    let over_view = mouse.pos.x >= viewport.x && mouse.pos.x <= viewport.x + viewport.w &&
                                    mouse.pos.y >= viewport.y && mouse.pos.y <= viewport.y + viewport.h;
                    let down = ui::input_is_mouse_down(ctx, ui::BUTTON_LEFT);
                    let pressed = ui::input_is_mouse_pressed(ctx, ui::BUTTON_LEFT);
                    let middle = ui::input_is_mouse_down(ctx, ui::BUTTON_MIDDLE);
                    let pan_down = middle || (gfx::key_down("Space") && down);
                    if !pan_down { panning = false; }
                    if over_view && state == ui::WIDGET_VALID &&
                       (ui::input_is_mouse_pressed(ctx, ui::BUTTON_MIDDLE) || (pressed && gfx::key_down("Space"))) {
                        panning = true; drawing = false;
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
                    if !panning {
                        sample_stroke(points, visible, drawing, down, pressed, inside && state == ui::WIDGET_VALID,
                            (mouse.pos.x - canvas.x) / canvas.w * document.w,
                            (mouse.pos.y - canvas.y) / canvas.h * document.h,
                            clamp(brush / canvas_extent, 0.00001, 0.1), PALETTE[selected]);
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
                    draw_points(ctx, points[..visible], ui::rect(canvas.x, canvas.y, canvas.w, canvas.h),
                                0.0, false, false, document, ink_clip);
                }
                ui::end(ctx);

                let tools = ui::rect(max(20.0, w - 260.0), 98.0, 240.0, max(96.0, h - 194.0));
                ui::window_set_bounds(ctx, "Studio tools", tools);
                if ui::begin(ctx, "Studio tools", tools, 0) {
                    ui::layout_row_dynamic(ctx, 28.0, 1);
                    ui::label(ctx, "DRAWING STUDIO", ui::TEXT_LEFT);
                    ui::layout_row_dynamic(ctx, 22.0, 1);
                    ui::label(ctx, "Aquarium-sized canvas", ui::TEXT_LEFT);
                    ui::layout_row_dynamic(ctx, 26.0, 6);
                    for i in 6 { if ui::button_color(ctx, color(PALETTE[i])) { selected = i; } }
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
                    if ui::button_label(ctx, "Undo") && visible > 0 {
                        visible--;
                        while visible > 0 && !points[visible].start { visible--; }
                    }
                    if ui::button_label(ctx, "Redo") && visible < points.len {
                        visible++;
                        while visible < points.len && !points[visible].start { visible++; }
                    }
                    if ui::button_label(ctx, "Clear") {
                        points.resize(0); visible = 0; canvas_aspect = 0.0; canvas_view = CanvasView {}; drawing = false;
                    }
                    ui::layout_row_dynamic(ctx, 38.0, 1);
                    if visible == 0 || reef.len >= MAX_CREATURES || !save_ok { ui::widget_disable_begin(ctx); }
                    let release = ui::button_label(ctx, "Bring to Life");
                    if visible == 0 || reef.len >= MAX_CREATURES || !save_ok { ui::widget_disable_end(ctx); }
                    if release && visible > 0 && reef.len < MAX_CREATURES && save_ok {
                        var fish = Creature { x: 0.3, y: 0.25 + (reef.len % 4) * 0.15,
                            speed: 0.035 + (reef.len % 5) * 0.009, phase: 0.0, points: [] };
                        fish.points.append(points[..visible]);
                        let ink_bounds = drawing_bounds(fish.points);
                        fish.size = min(1.0, max(ink_bounds.w, ink_bounds.h));
                        reef.push(fish);
                        if write_file_atomic(save_path, encode_reef(reef)) {
                            points.resize(0); visible = 0; studio = false; paused = false;
                            canvas_aspect = 0.0; canvas_view = CanvasView {}; drawing = false; panning = false;
                            status.clear(); status.append("Your doodle is swimming. Saved on this computer.");
                        } else {
                            reef.resize(reef.len - 1);
                            status.clear(); status.append("Could not save. Your drawing is still on the canvas; try again.");
                        }
                    }
                    ui::layout_row_dynamic(ctx, 24.0, 1);
                    let canvas_status: u8[>..] = if reef.len >= MAX_CREATURES { "Reef is full (12 creatures)." }
                        else if visible == MAX_POINTS { "Canvas is full. Undo, clear, or Bring to Life." }
                        else { str(visible, " / ", MAX_POINTS, " drawing points") };
                    ui::label(ctx, canvas_status, ui::TEXT_LEFT);
                    ui::layout_row_dynamic(ctx, 22.0, 1);
                    ui::label(ctx, "Bigger drawing, bigger creature.", ui::TEXT_LEFT);
                }
                ui::end(ctx);
            }

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
                let footer_text: u8[>..] = if status.len > 0 { copy(status) } else {
                    str(reef.len, " creatures / Click a creature to select / Space to pause") };
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
                    if selected_fish >= 0 { status.append(str("Creature ", selected_fish + 1, " selected. Drag, flip, or delete.")); }
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
                if flip_creature(reef, selected_fish, save_path) { status.append("Creature flipped and saved. It will keep turning at the walls."); }
                else { status.append("Could not save the flip. Your creature has been kept unchanged; try again."); }
            }
        }
        if !paused {
            time += dt;
            for i in reef.len { if i != dragging_fish { update(reef[i], dt); } }
        }
        scene(ctx, w, h, time, reef, if studio || wallpaper { -1 } else { selected_fish }, wallpaper);
        gfx::begin_screen(float4 { 0.03, 0.1, 0.14, 1.0 });
        gfx::end_pass();
        ui::render(ctx);
        if wallpaper { ui::clear(ctx); }
        drawn++;
        if drawn == frames {
            assert(gfx::screenshot(str(resource_dir(), "preview.png")));
            break;
        }
        sleep(max(0.0, 1.0 / fps - (clock() - started)));
    }
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
