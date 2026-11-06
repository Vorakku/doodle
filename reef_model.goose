import std;
import math;
import os;

let MAX_POINTS = 8192;
let MAX_CREATURES = 12;
let SAVE_HEADER: const u8[:] = "DREEF002";
let LEGACY_SAVE_HEADER: const u8[:] = "DREEF001";

struct Point { x: f32, y: f32, width: f32, color: u8[4], start: bool }
struct Bounds { x: f32, y: f32, w: f32, h: f32 }
struct Creature {
    x: f32, y: f32, speed: f32, phase: f32,
    size: f32 = 0.0, // Zero preserves the size of creatures drawn before the zoomable studio.
    points: Point[..8192],
}
struct LegacyCreature {
    x: f32, y: f32, speed: f32, phase: f32,
    points: Point[..4096],
}

fn sample_stroke(points: Point[>..]&, visible: i64&, drawing: bool&, down: bool,
                 pressed: bool, inside: bool, x: f32, y: f32, width: f32, ink: u8[4]) {
    if !down { drawing = false; }
    if inside && down && (drawing || pressed) {
        if !drawing { points.resize(visible); }
        let p = Point { x, y, width, ink, !drawing };
        if points.len < MAX_POINTS {
            if !drawing || abs(p.x - points[points.len - 1].x) + abs(p.y - points[points.len - 1].y) > min(width * 0.1, 0.001) {
                points.push(p); visible = points.len;
            }
        }
        drawing = true;
    }
}

fn creature_area(fish: const Creature&, w: f32, h: f32) -> Bounds {
    let size = if fish.size > 0.0 {
        max(16.0, min(fish.size * max(w, h), min(max(16.0, w - 32.0), max(16.0, h - 220.0))))
    } else { min(136.0, min(w * 0.2, max(30.0, (h - 160.0) * 0.35))) };
    let x = size * 0.5 + fish.x * max(0.0, w - size);
    let top = if fish.size > 0.0 { 112.0 + size * 0.5 } else { 112.0 };
    let travel = if fish.size > 0.0 { max(0.0, h - 200.0 - size) } else { max(0.0, h - 240.0) };
    let y = top + fish.y * travel + sin(fish.phase) * 7.0;
    return Bounds { x - size * 0.5, y - size * 0.5, size, size };
}

fn move_creature(fish: Creature&, cx: f32, cy: f32, w: f32, h: f32) {
    let size = creature_area(fish, w, h).w;
    fish.x = clamp((cx - size * 0.5) / max(1.0, w - size), 0.05, 0.95);
    let top = if fish.size > 0.0 { 112.0 + size * 0.5 } else { 112.0 };
    let travel = if fish.size > 0.0 { max(1.0, h - 200.0 - size) } else { max(1.0, h - 240.0) };
    fish.y = clamp((cy - top - sin(fish.phase) * 7.0) / travel, 0.1, 0.9);
}

fn pick_creature(reef: const Creature[:], x: f32, y: f32, w: f32, h: f32) -> i64 {
    var i = reef.len;
    while i > 0 {
        i--;
        let area = creature_area(reef[i], w, h);
        if x >= area.x && x <= area.x + area.w && y >= area.y && y <= area.y + area.h { return i; }
    }
    return -1;
}

fn delete_creature(reef: Creature[>..]&, index: i64, save_path: const u8[:]) -> bool {
    if index < 0 || index >= reef.len { return false; }
    var remaining: Creature[>..] = [];
    for i in reef.len { if i != index { remaining.push(reef[i]); } }
    if !write_file_atomic(save_path, encode_reef(remaining)) { return false; }
    remove_at(reef, index);
    return true;
}

fn flip_creature(reef: Creature[>..]&, index: i64, save_path: const u8[:]) -> bool {
    if index < 0 || index >= reef.len { return false; }
    let fish .= reef[index];
    var original: Point[>..] = [];
    original.append(fish.points);
    for i in fish.points.len { fish.points[i].x = 1.0 - fish.points[i].x; }
    if !write_file_atomic(save_path, encode_reef(reef)) {
        fish.points.clear(); fish.points.append(original);
        return false;
    }
    return true;
}

fn update(fish: Creature&, dt: f32) {
    fish.x += fish.speed * dt;
    if fish.x >= 0.95 { fish.x = 0.95; fish.speed = -abs(fish.speed); }
    if fish.x <= 0.05 { fish.x = 0.05; fish.speed = abs(fish.speed); }
    fish.phase = (fish.phase + dt * 2.5) % 6.2831853;
}

fn drawing_bounds(points: const Point[:]) -> Bounds {
    var left: f32 = 1.0;
    var top: f32 = 1.0;
    var right: f32 = 0.0;
    var bottom: f32 = 0.0;
    for p in points {
        left = min(left, p.x - p.width * 0.5);
        top = min(top, p.y - p.width * 0.5);
        right = max(right, p.x + p.width * 0.5);
        bottom = max(bottom, p.y + p.width * 0.5);
    }
    if points.len == 0 { return Bounds { 0.0, 0.0, 1.0, 1.0 }; }
    return Bounds { left - 0.02, top - 0.02, right - left + 0.04, bottom - top + 0.04 };
}

fn valid_points(points: const Point[:]) -> bool {
    if points.len == 0 || points.len > MAX_POINTS || !points[0].start { return false; }
    for p in points {
        // These comparisons also reject NaN and infinity from malformed files.
        if !(p.x >= 0.0 && p.x <= 1.0 && p.y >= 0.0 && p.y <= 1.0 &&
             p.width >= 0.00001 && p.width <= 0.1) { return false; }
    }
    return true;
}

fn encode_reef(reef: const Creature[:]) -> u8[>..] {
    var copy: Creature[>..] = [];
    copy.append(reef);
    var out: u8[>..] = [];
    out.append(SAVE_HEADER);
    out.append(to_bytes(copy));
    return out;
}

fn decode_reef(image: const u8[:]) -> Creature[>..], bool {
    if image.len < 9 { return [], false; }
    var reef: Creature[>..] = [];
    if image[..8] == SAVE_HEADER {
        let loaded, ok = from_bytes<Creature[>..]>(image[8..]);
        if !ok || loaded.len > MAX_CREATURES { return [], false; }
        reef.append(loaded);
    } else if image[..8] == LEGACY_SAVE_HEADER {
        let loaded, ok = from_bytes<LegacyCreature[>..]>(image[8..]);
        if !ok || loaded.len > MAX_CREATURES { return [], false; }
        for old in loaded {
            reef.push(Creature { x: old.x, y: old.y, speed: old.speed, phase: old.phase, points: old.points });
        }
    } else { return [], false; }
    for fish in reef {
        if !valid_points(fish.points) || !(fish.x >= 0.05 && fish.x <= 0.95 &&
            fish.y >= 0.1 && fish.y <= 0.9 && abs(fish.speed) <= 0.2 &&
            fish.phase >= 0.0 && fish.phase <= 6.284 && fish.size >= 0.0 && fish.size <= 1.0) { return [], false; }
    }
    return reef, true;
}
