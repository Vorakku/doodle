import std;
import math;

// Hue, saturation and brightness, each 0..1. The picker keeps these rather than RGB,
// so dragging through grey or black doesn't lose the hue.
struct Hsv { h: f32, s: f32, v: f32 }

fn hsv_to_rgb(c: Hsv) -> u8[4] {
    let sector = c.h * 6.0;
    let index = (floor(sector) as! i64) % 6;
    let f = sector - floor(sector);
    let p = c.v * (1.0 - c.s);
    let q = c.v * (1.0 - c.s * f);
    let t = c.v * (1.0 - c.s * (1.0 - f));
    let r = if index == 0 || index == 5 { c.v } else if index == 1 { q } else if index == 4 { t } else { p };
    let g = if index == 1 || index == 2 { c.v } else if index == 0 { t } else if index == 3 { q } else { p };
    let b = if index == 3 || index == 4 { c.v } else if index == 2 { t } else if index == 5 { q } else { p };
    return [round(r * 255.0) as! u8, round(g * 255.0) as! u8, round(b * 255.0) as! u8, 255];
}

// Greys have no hue of their own, so they keep the one the picker already had.
fn rgb_to_hsv(c: u8[4], keep_hue: f32) -> Hsv {
    let r: f32 = c[0] / 255.0;
    let g: f32 = c[1] / 255.0;
    let b: f32 = c[2] / 255.0;
    let high = max(r, max(g, b));
    let low = min(r, min(g, b));
    let span = high - low;
    if span == 0.0 { return Hsv { keep_hue, 0.0, high }; }
    var h = if high == r { (g - b) / span } else if high == g { 2.0 + (b - r) / span } else { 4.0 + (r - g) / span };
    h /= 6.0;
    if h < 0.0 { h += 1.0; }
    return Hsv { h, span / high, high };
}

fn color_hex(c: u8[4]) -> u8[>..] {
    let digits: const u8[:] = "0123456789ABCDEF";
    var out: u8[>..] = [];
    for i in 3 {
        out.push(digits[c[i] / 16]);
        out.push(digits[c[i] % 16]);
    }
    return out;
}

fn hex_digit(c: u8) -> i64 {
    if c >= 48 && c <= 57 { return c - 48; }
    if c >= 65 && c <= 70 { return c - 55; }
    if c >= 97 && c <= 102 { return c - 87; }
    return -1;
}

fn parse_hex(text: const u8[:]) -> u8[4], bool {
    var out: u8[4] = [0, 0, 0, 255];
    if text.len != 6 { return out, false; }
    for i in 3 {
        let high = hex_digit(text[i * 2]);
        let low = hex_digit(text[i * 2 + 1]);
        if high < 0 || low < 0 { return out, false; }
        out[i] = (high * 16 + low) as! u8;
    }
    return out, true;
}
