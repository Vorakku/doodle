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
    size: f32 = 0.0, // Drawn size. Zero for creatures drawn before the zoomable studio.
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
    // shortcut: every creature gets one fixed size and fish.size is saved but ignored, until the sizing feature.
    let size = min(136.0, min(w * 0.2, max(30.0, (h - 160.0) * 0.35)));
    // fish.x runs from fully off the left edge (0) to fully off the right edge (1).
    let left = fish.x * (w + size) - size;
    let y = 112.0 + fish.y * max(0.0, h - 240.0) + sin(fish.phase) * 7.0;
    return Bounds { left, y - size * 0.5, size, size };
}

fn move_creature(fish: Creature&, cx: f32, cy: f32, w: f32, h: f32) {
    let size = creature_area(fish, w, h).w;
    let span = max(1.0, w + size);
    // Dropped creatures stay fully on screen, where they can be grabbed again.
    fish.x = clamp((cx + size * 0.5) / span, size / span, w / span);
    fish.y = clamp((cy - 112.0 - sin(fish.phase) * 7.0) / max(1.0, h - 240.0), 0.1, 0.9);
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

// A creature's heading runs from 0 (facing left) to 1 (facing right). It lives only in memory, so saves are unchanged.
let TURN_SECONDS: f32 = 1.8;

fn step_heading(heading: f32, speed: f32, dt: f32) -> f32 {
    return clamp(heading + (if speed < 0.0 { -dt } else { dt }) / TURN_SECONDS, 0.0, 1.0);
}

// -1 is facing left and 1 is facing right. The cosine is how wide a body looks as it rotates, so turns ease in and out.
fn turn_facing(heading: f32) -> f32 { return -cos(heading * 3.14159265); }

// A turn rotates the flat drawing around the vertical axis, swinging back into the tank and returning.
struct TurnView { across: f32, away: f32, lens: f32, depth: f32 }

fn turn_view(heading: f32, size: f32) -> TurnView {
    let facing = turn_facing(heading);
    let away = sin(heading * 3.14159265); // 1 when facing straight into the screen.
    // Mid-turn a creature is seen nearly edge-on, but it should never vanish.
    return TurnView { across: if facing < 0.0 { min(facing, -0.15) } else { max(facing, 0.15) },
                      away: away, lens: max(1.0, size * 3.0), depth: size * 1.1 * away };
}

// Perspective at a spot `along` pixels ahead of the body's centre: further away is smaller.
fn turn_nearness(turn: TurnView, along: f32) -> f32 {
    return turn.lens / (turn.lens + turn.depth + along * turn.away);
}

// Moving with facing rather than speed makes a creature slow to a stop mid-turn, then set off the new way.
fn update(fish: Creature&, dt: f32, facing: f32) {
    fish.x += abs(fish.speed) * facing * dt;
    // Past one edge, back in from the other, still heading the same way.
    if fish.x > 1.0 { fish.x -= 1.0; }
    if fish.x < 0.0 { fish.x += 1.0; }
    fish.phase = (fish.phase + dt * 2.5) % 6.2831853;
}

// Each creature gets a chance to turn every 10-15 seconds, on its own rhythm, and takes about one chance in three.
// Worked out from the clock so nothing extra is saved, and it can't turn twice in quick succession.
fn turn_due(index: i64, before: f32, after: f32) -> bool {
    let every = 10.0 + (index % 5) as f32 * 1.3;
    let slot = floor(after / every);
    if slot == floor(before / every) { return false; }
    let noise = sin(slot * 12.9898 + index * 78.233) * 43758.547;
    return noise - floor(noise) < 0.33;
}

fn maybe_turn(fish: Creature&, index: i64, before: f32, after: f32) {
    // Near an edge it would be flipping half off screen, so let it finish leaving or arriving.
    if fish.x > 0.15 && fish.x < 0.85 && turn_due(index, before, after) { fish.speed = -fish.speed; }
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
    // Padding follows the ink, so tiny drawings fill their creature box as fully as big ones.
    let margin = max(right - left, bottom - top) * 0.03;
    return Bounds { left - margin, top - margin, right - left + margin * 2.0, bottom - top + margin * 2.0 };
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
        if !valid_points(fish.points) || !(fish.x >= 0.0 && fish.x <= 1.0 &&
            fish.y >= 0.1 && fish.y <= 0.9 && abs(fish.speed) <= 0.2 &&
            fish.phase >= 0.0 && fish.phase <= 6.284 && fish.size >= 0.0 && fish.size <= 1.0) { return [], false; }
    }
    return reef, true;
}
