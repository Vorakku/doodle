import std;
import math;
import os;
import reef_growth;

let MAX_POINTS = 8192;
let MAX_CREATURES = 12;
let SAVE_HEADER: const u8[:] = "DREEF005";
let V4_SAVE_HEADER: const u8[:] = "DREEF004";
let V3_SAVE_HEADER: const u8[:] = "DREEF003";
let V2_SAVE_HEADER: const u8[:] = "DREEF002";
let LEGACY_SAVE_HEADER: const u8[:] = "DREEF001";

struct Point { x: f32, y: f32, width: f32, color: u8[4], start: bool }
struct Bounds { x: f32, y: f32, w: f32, h: f32 }
struct Creature {
    x: f32, y: f32, speed: f32, phase: f32,
    size: f32 = 0.0, // Drawn size. Zero for creatures drawn before the zoomable studio.
    points: Point[..8192],
    tier: i64 = -1, born: f64 = 0.0,
    name: u8[..128] = "Fish",
    image_id: u64 = 0, image_flip: bool = false,
}
struct V4Creature {
    x: f32, y: f32, speed: f32, phase: f32, size: f32,
    points: Point[..8192], tier: i64, born: f64, name: u8[..128],
}
struct V3Creature {
    x: f32, y: f32, speed: f32, phase: f32, size: f32,
    points: Point[..8192], tier: i64, born: f64,
}
struct V2Creature {
    x: f32, y: f32, speed: f32, phase: f32, size: f32,
    points: Point[..8192],
}
struct LegacyCreature {
    x: f32, y: f32, speed: f32, phase: f32,
    points: Point[..4096],
}

fn clean_name(name: const u8[:]) -> const u8[:] {
    var first = 0;
    var last = name.len;
    while first < last && is_space(name[first]) { first++; }
    while last > first && is_space(name[last - 1]) { last--; }
    return name[first..last];
}

fn valid_name(name: const u8[:]) -> bool {
    let cleaned = clean_name(name);
    if cleaned.len == 0 || cleaned.len > 128 { return false; }
    var count = 0;
    var valid = true;
    var visible = false;
    var encoded: u8[>..] = [];
    each_utf8(cleaned) {
        if it < 32 || (it >= 127 && it <= 159) || (it >= 0xD800 && it <= 0xDFFF) || it > 0x10FFFF { valid = false; }
        if it > 32 && it != 0xA0 && it != 0x1680 && !(it >= 0x2000 && it <= 0x200F) &&
           !(it >= 0x2028 && it <= 0x202F) && !(it >= 0x205F && it <= 0x206F) && it != 0x3000 && it != 0xFEFF {
            visible = true;
        }
        push_utf8(encoded, it);
        count++;
    };
    return valid && visible && count <= 32 && encoded == cleaned;
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

fn swimming_heights(size: f32, h: f32) -> f32, f32 {
    let span = max(0.0, h - 240.0);
    let top = max(112.0 + span * 0.1, 82.0 + size * 0.5 + 8.0);
    let bottom = min(112.0 + span * 0.9, h - 78.0 - size * 0.5 - 8.0);
    if bottom < top { return h * 0.5, h * 0.5; }
    return top, bottom;
}

fn creature_area(fish: const Creature&, w: f32, h: f32) -> Bounds {
    let size = min(growth_width(fish.tier, fish.born, time()), min(w * 0.45, max(1.0, h - 176.0) * 0.75));
    // fish.x runs from fully off the left edge (0) to fully off the right edge (1).
    let left = fish.x * (w + size) - size;
    let top, bottom = swimming_heights(size, h);
    let y = top + (fish.y - 0.1) / 0.8 * (bottom - top) + sin(fish.phase) * 7.0;
    return Bounds { left, y - size * 0.5, size, size };
}

fn move_creature(fish: Creature&, cx: f32, cy: f32, w: f32, h: f32) {
    let size = creature_area(fish, w, h).w;
    let span = max(1.0, w + size);
    // Dropped creatures stay fully on screen, where they can be grabbed again.
    fish.x = clamp((cx + size * 0.5) / span, size / span, w / span);
    let top, bottom = swimming_heights(size, h);
    fish.y = clamp(0.1 + (cy - sin(fish.phase) * 7.0 - top) / max(1.0, bottom - top) * 0.8, 0.1, 0.9);
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
    let original_flip = fish.image_flip;
    if fish.image_id != 0 { fish.image_flip = !fish.image_flip; }
    else { for i in fish.points.len { fish.points[i].x = 1.0 - fish.points[i].x; } }
    if !write_file_atomic(save_path, encode_reef(reef)) {
        fish.points.clear(); fish.points.append(original);
        fish.image_flip = original_flip;
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
struct TurnView { across: f32, away: f32, lens: f32, depth: f32, tilt_cos: f32, tilt_sin: f32 }

fn turn_view(heading: f32, size: f32, pitch: f32 = 0.0) -> TurnView {
    let facing = turn_facing(heading);
    let away = sin(heading * 3.14159265); // 1 when facing straight into the screen.
    // Mid-turn a creature is seen nearly edge-on, but it should never vanish.
    return TurnView { across: if facing < 0.0 { min(facing, -0.15) } else { max(facing, 0.15) },
                      away: away, lens: max(1.0, size * 3.0), depth: size * 1.1 * away,
                      tilt_cos: cos(pitch), tilt_sin: sin(pitch) };
}

// Perspective at a spot `along` pixels ahead of the body's centre: further away is smaller.
fn turn_nearness(turn: TurnView, along: f32) -> f32 {
    return turn.lens / (turn.lens + turn.depth + along * turn.away);
}

// Pitch before mirroring, so a climbing nose points up in either swimming direction.
fn body_point(turn: TurnView, along: f32, down: f32) -> f32, f32, f32 {
    let x = along * turn.tilt_cos - down * turn.tilt_sin;
    let y = along * turn.tilt_sin + down * turn.tilt_cos;
    let near = turn_nearness(turn, x);
    return x * turn.across * near, y * near, near;
}

fn wave_height(facing: f32) -> f32 { return 3.0 + (1.0 - abs(facing)) * 5.0; }

// Moving with facing rather than speed makes a creature slow to a stop mid-turn, then set off the new way.
fn update(fish: Creature&, dt: f32, facing: f32) {
    fish.x += abs(fish.speed) * facing * dt;
    // Past one edge, back in from the other, still heading the same way.
    if fish.x > 1.0 { fish.x -= 1.0; }
    if fish.x < 0.0 { fish.x += 1.0; }
    fish.phase = (fish.phase + dt * 2.5) % 6.2831853;
}

// Runtime steering stays out of the saved creature format.
struct SwimMotion {
    elapsed: f32 = 0.0, vertical_speed: f32 = 0.0,
    pitch: f32 = 0.0, pitch_speed: f32 = 0.0,
    pace: f32 = 1.0,
}
let VERTICAL_SPEED: f32 = 0.055;

fn pace_target(elapsed: f32, index: i64) -> f32 {
    let every: f32 = 10.0 + (index % 5) * 1.7;
    let cycle = (elapsed + index * 2.137) / every;
    let slot = floor(cycle);
    let progress = cycle - slot;
    let noise = sin((slot + 1.0) * 12.9898 + index * 78.233) * 43758.547;
    let variety = noise - floor(noise);
    if progress < 0.25 { return 1.1 + variety * 0.15; }
    if progress >= 0.75 && variety < 0.33 { return 0.0; }
    return 0.35 + variety * 0.2;
}

fn swim(fish: Creature&, motion: SwimMotion&, dt: f32, facing: f32, index: i64) {
    if dt <= 0.0 { return; }
    motion.elapsed += dt;
    let pace = pace_target(motion.elapsed, index);
    motion.pace += (pace - motion.pace) * (1.0 - exp(-dt * 2.0));
    // Finish the eased stop, rather than creeping forever toward zero speed.
    if pace == 0.0 && motion.pace < 0.01 { motion.pace = 0.0; }
    let leg = floor(motion.elapsed / (14.0 + (index % 5) * 1.7));
    let noise = sin((leg + 1.0) * 12.9898 + index * 78.233) * 43758.547;
    let band = if ((leg as! i64 + index) % 2) == 0 { 0.18 } else { 0.68 };
    let target = band + (noise - floor(noise)) * 0.14;
    let desired = clamp((target - fish.y) * 0.35, -VERTICAL_SPEED, VERTICAL_SPEED);
    motion.vertical_speed += (desired - motion.vertical_speed) * (1.0 - exp(-dt * 2.0));
    fish.y = clamp(fish.y + motion.vertical_speed * motion.pace * dt, 0.1, 0.9);
    // Steep climbs and dives spend more of the motion on Y, rather than sliding sideways.
    let across = max(0.12, 1.0 - abs(motion.vertical_speed) / VERTICAL_SPEED);
    update(fish, dt * motion.pace, facing * across);
}

fn update_pitch(fish: const Creature&, motion: SwimMotion&, dt: f32, w: f32, h: f32) {
    if dt <= 0.0 { return; }
    let across = max(0.12, 1.0 - abs(motion.vertical_speed) / VERTICAL_SPEED);
    // A horizontal turn travels into the tank; its projected slowdown must not cause a sudden nose-up.
    let size = creature_area(fish, w, h).w;
    let top, bottom = swimming_heights(size, h);
    let forward = abs(fish.speed) * across * motion.pace * (w + size);
    let vertical = motion.vertical_speed * motion.pace * (bottom - top) / 0.8;
    let limit: f32 = 1.2217305; // 70 degrees keeps the drawing readable during steep travel.
    let target = if forward + abs(vertical) < 0.001 { 0.0 } else {
        clamp(atan2(vertical, forward), -limit, limit) * min(1.0, (forward + abs(vertical)) / 8.0)
    };
    // Exact critically damped spring: angular inertia without frame-rate-dependent wobble.
    let omega: f32 = 4.5;
    let error = motion.pitch - target;
    let carry = motion.pitch_speed + omega * error;
    let decay = exp(-omega * dt);
    motion.pitch = target + (error + carry * dt) * decay;
    motion.pitch_speed = (motion.pitch_speed - omega * carry * dt) * decay;
    if abs(motion.pitch) > limit { motion.pitch = clamp(motion.pitch, -limit, limit); motion.pitch_speed = 0.0; }
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
    } else if image[..8] == V4_SAVE_HEADER {
        let loaded, ok = from_bytes<V4Creature[>..]>(image[8..]);
        if !ok || loaded.len > MAX_CREATURES { return [], false; }
        for old in loaded {
            reef.push(Creature { x: old.x, y: old.y, speed: old.speed, phase: old.phase, size: old.size,
                points: old.points, tier: old.tier, born: old.born, name: old.name });
        }
    } else if image[..8] == V3_SAVE_HEADER {
        let loaded, ok = from_bytes<V3Creature[>..]>(image[8..]);
        if !ok || loaded.len > MAX_CREATURES { return [], false; }
        for old in loaded {
            reef.push(Creature { x: old.x, y: old.y, speed: old.speed, phase: old.phase, size: old.size,
                points: old.points, tier: old.tier, born: old.born, name: [] });
        }
    } else if image[..8] == V2_SAVE_HEADER {
        let loaded, ok = from_bytes<V2Creature[>..]>(image[8..]);
        if !ok || loaded.len > MAX_CREATURES { return [], false; }
        for old in loaded {
            reef.push(Creature { x: old.x, y: old.y, speed: old.speed, phase: old.phase, size: old.size, points: old.points, name: [] });
        }
    } else if image[..8] == LEGACY_SAVE_HEADER {
        let loaded, ok = from_bytes<LegacyCreature[>..]>(image[8..]);
        if !ok || loaded.len > MAX_CREATURES { return [], false; }
        for old in loaded {
            reef.push(Creature { x: old.x, y: old.y, speed: old.speed, phase: old.phase, points: old.points, name: [] });
        }
    } else { return [], false; }
    for fish in reef {
        if (image[..8] == SAVE_HEADER || image[..8] == V4_SAVE_HEADER || image[..8] == V3_SAVE_HEADER) &&
           !(fish.tier >= 0 && fish.tier < 6 && fish.born > 0.0 && fish.born < 1.0e12) {
            return [], false;
        }
        if (image[..8] == SAVE_HEADER || image[..8] == V4_SAVE_HEADER) &&
           (!valid_name(fish.name) || clean_name(fish.name) != fish.name) { return [], false; }
        let artwork_ok = if fish.image_id == 0 { valid_points(fish.points) && !fish.image_flip } else { fish.points.len == 0 };
        if !artwork_ok || !(fish.x >= 0.0 && fish.x <= 1.0 &&
            fish.y >= 0.1 && fish.y <= 0.9 && abs(fish.speed) <= 0.2 &&
            fish.phase >= 0.0 && fish.phase <= 6.284 && fish.size >= 0.0 && fish.size <= 1.0) { return [], false; }
    }
    return reef, true;
}

fn upgrade_growth(reef: Creature[>..]&, save_path: const u8[:], original: const u8[:], now: f64, random: rng&) -> bool {
    if !(now > 0.0 && now < 1.0e12) { return false; }
    var staged: Creature[>..] = [];
    staged.append(reef);
    for i in staged.len {
        let fish .= staged[i];
        if fish.tier == -1 && fish.born == 0.0 {
            fish.tier = tier_from_roll(rand_int(random, 100));
            fish.born = now;
        }
        if fish.name.len == 0 { fish.name.append(str("Fish ", i + 1)); }
    }
    if original.len > 0 {
        if original.len < 8 { return false; }
        let header = original[..8];
        if header == LEGACY_SAVE_HEADER || header == V2_SAVE_HEADER || header == V3_SAVE_HEADER || header == V4_SAVE_HEADER {
            let backup_path = str(save_path, if header == LEGACY_SAVE_HEADER { ".v1.bak" }
                else if header == V2_SAVE_HEADER { ".v2.bak" } else if header == V3_SAVE_HEADER { ".v3.bak" } else { ".v4.bak" });
            if file_exists(backup_path) {
                var backup: u8[>..] = [];
                if !read_file(backup_path, backup) || backup != original { return false; }
            } else if !write_file_atomic(backup_path, original) { return false; }
        } else if header != SAVE_HEADER { return false; }
    }
    if !write_file_atomic(save_path, encode_reef(staged)) { return false; }
    reef.clear(); reef.append(staged);
    return true;
}
