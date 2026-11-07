import std;
import math;

let ADULT_WIDTHS: f32[6] = [64.0, 89.6, 121.6, 166.4, 224.0, 320.0];
let GROWTH_SECONDS: f64[6] = [7200.0, 21600.0, 64800.0, 259200.0, 604800.0, 2592000.0];
let TIER_NAMES: const u8[:][6] = ["E", "D", "C", "B", "A", "S"];
let BABY_WIDTH: f32 = 19.2;

fn tier_from_roll(roll: i64) -> i64 {
    assert(roll >= 0 && roll < 100);
    if roll < 40 { return 0; }
    if roll < 68 { return 1; }
    if roll < 86 { return 2; }
    if roll < 95 { return 3; }
    if roll < 99 { return 4; }
    return 5;
}

fn growth_progress(tier: i64, born: f64, now: f64) -> f64 {
    if tier < 0 || tier >= 6 || born <= 0.0 { return 0.0; }
    return clamp((now - born) / GROWTH_SECONDS[tier], 0.0, 1.0);
}

fn growth_width(tier: i64, born: f64, now: f64) -> f32 {
    if tier < 0 || tier >= 6 || born <= 0.0 { return BABY_WIDTH; }
    let p = growth_progress(tier, born, now);
    let baby: f64 = BABY_WIDTH;
    let adult: f64 = ADULT_WIDTHS[tier];
    return (baby + (adult - baby) * p * (2.0 - p)) as f32;
}
