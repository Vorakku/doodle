import std;
import math;
import os;
import binary;

let PNG_LIMIT: i64 = 16 * 1024 * 1024;
let IMAGE_LIMIT: i64 = 16 + 512 * 512 * 4;
let IMAGE_HEADER: const u8[:] = "DIMG0001";
struct ImageData { width: i64 = 0, height: i64 = 0, rgba: u8[>..] = [] }
extern fn reef_read_image_file(path: const u8[:], output: u8[:]) -> i64;

fn read_image_file(path: const u8[:], limit: i64) -> u8[>..], bool {
    var bytes: u8[>..] = []; bytes.resize(limit, 0);
    let length = reef_read_image_file(path, bytes);
    if length < 0 { return [], false; }
    bytes.resize(length);
    return bytes, true;
}

fn image_be32(bytes: const u8[:], at: i64) -> i64 {
    return (bytes[at] as i64 << 24) | (bytes[at + 1] as i64 << 16) | (bytes[at + 2] as i64 << 8) | bytes[at + 3];
}

fn png_dimensions(bytes: const u8[:]) -> i64, i64, bool {
    let signature: u8[8] = [137, 80, 78, 71, 13, 10, 26, 10];
    if bytes.len < 45 || bytes.len > PNG_LIMIT || bytes[..8] != signature ||
       image_be32(bytes, 8) != 13 || bytes[12..16] != "IHDR" { return 0, 0, false; }
    let w = image_be32(bytes, 16); let h = image_be32(bytes, 20);
    if w < 1 || h < 1 || w > 4096 || h > 4096 { return 0, 0, false; }
    var at: i64 = 33;
    var data = false;
    while at <= bytes.len - 12 {
        let length = image_be32(bytes, at);
        if length > bytes.len - at - 12 { return 0, 0, false; }
        let kind = bytes[at + 4..at + 8];
        if kind == "IHDR" { return 0, 0, false; }
        if kind == "IDAT" { data = true; }
        if kind == "IEND" { return w, h, data && length == 0 && at + 12 == bytes.len; }
        at += length + 12;
    }
    return 0, 0, false;
}

fn normalize_image(rgba: const u8[:], width: i64, height: i64) -> ImageData, const u8[:] {
    if width < 1 || height < 1 || width > 4096 || height > 4096 || rgba.len != width * height * 4 {
        return ImageData {}, "Invalid image dimensions.";
    }
    var left = width; var top = height; var right = 0; var bottom = 0;
    var transparent = false;
    for y in height {
        for x in width {
            let a = rgba[(y * width + x) * 4 + 3];
            transparent = transparent || a < 255;
            if a > 0 { left = min(left, x); top = min(top, y); right = max(right, x + 1); bottom = max(bottom, y + 1); }
        }
    }
    if right <= left || bottom <= top { return ImageData {}, "This PNG has no visible artwork."; }
    if !transparent { return ImageData {}, "Choose a PNG with a transparent background."; }
    let cw = right - left; let ch = bottom - top;
    let scale = min(1.0, min(512.0 / cw, 512.0 / ch));
    var image = ImageData { width: max(1, round(cw * scale) as! i64), height: max(1, round(ch * scale) as! i64) };
    image.rgba.resize(image.width * image.height * 4, 0);
    for y in image.height {
        for x in image.width {
            let x0 = left + x * cw / image.width; let x1 = left + (x + 1) * cw / image.width;
            let y0 = top + y * ch / image.height; let y1 = top + (y + 1) * ch / image.height;
            var alpha: i64 = 0;
            var rgb: i64[3] = [0, 0, 0];
            for sy in y0..y1 {
                for sx in x0..x1 {
                    let i = (sy * width + sx) * 4;
                    let a = rgba[i + 3] as i64;
                    alpha += a;
                    for c in 3 { rgb[c] += rgba[i + c] * a; }
                }
            }
            if alpha > 0 {
                let i = (y * image.width + x) * 4;
                let samples = (x1 - x0) * (y1 - y0);
                image.rgba[i + 3] = max(1, (alpha + samples / 2) / samples) as! u8;
                for c in 3 { image.rgba[i + c] = ((rgb[c] + alpha / 2) / alpha) as! u8; }
            }
        }
    }
    return image, "";
}

fn encode_image(image: const ImageData&) -> u8[>..] {
    var bytes: u8[>..] = []; bytes.append(IMAGE_HEADER);
    for value in [image.width, image.height] {
        for i in 4 { bytes.push(((value >> (i * 8)) & 255) as! u8); }
    }
    bytes.append(image.rgba);
    return bytes;
}

fn decode_image(bytes: const u8[:]) -> ImageData, bool {
    if bytes.len < 16 || bytes.len > IMAGE_LIMIT || bytes[..8] != IMAGE_HEADER { return ImageData {}, false; }
    let w, wok = binary::read_u32le(bytes, 8); let h, hok = binary::read_u32le(bytes, 12);
    if !wok || !hok || w < 1 || h < 1 || w > 512 || h > 512 || bytes.len != 16 + (w as i64) * h * 4 {
        return ImageData {}, false;
    }
    var image = ImageData { width: w, height: h }; image.rgba.append(bytes[16..]);
    var visible = false;
    for i in image.width * image.height { visible = visible || image.rgba[i * 4 + 3] > 0; }
    return image, visible;
}

fn image_path(directory: const u8[:], id: u64, extension: const u8[:] = ".rgba") -> u8[>..] {
    return str(directory, "/images/", id, extension);
}

fn save_image(directory: const u8[:], image: const ImageData&, png: const u8[:], random: rng&) -> u64, bool {
    if !make_dir(str(directory, "/images")) { return 0, false; }
    for attempt in 16 {
        let id = rand_u64(random);
        let raw_path = image_path(directory, id); let png_path = image_path(directory, id, ".png");
        if id == 0 || file_exists(raw_path) || file_exists(png_path) { continue; }
        if !write_file_atomic(png_path, png) { return 0, false; }
        if !write_file_atomic(raw_path, encode_image(image)) { delete_file(png_path); return 0, false; }
        return id, true;
    }
    return 0, false;
}

fn discard_new_image(directory: const u8[:], id: u64) {
    if id != 0 { delete_file(image_path(directory, id)); delete_file(image_path(directory, id, ".png")); }
}
