import std;
import math;
import vec;
import os;
import gfx;
import reef_model;
import reef_image_data;
extern fn reef_image_dialog_open() -> bool;
extern fn reef_image_dialog_result(output: u8[:]) -> i64;

struct ImageSlot {
    key: u64 = 0,
    source: gfx::Texture = gfx::Texture { 0 }, pose: gfx::Texture = gfx::Texture { 0 },
    width: i64 = 0, height: i64 = 0, output_width: i64 = 0, output_height: i64 = 0,
}
struct ImageVertex { position: float3, uv: float2 }
struct ImageRenderer {
    pipeline: gfx::Pipeline = gfx::Pipeline { 0 }, sampler: gfx::Sampler = gfx::Sampler { 0 },
    buffer: gfx::Buffer = gfx::Buffer { 0 }, slots: ImageSlot[..12] = [],
}

fn load_png_image(path: const u8[:], directory: const u8[:]) -> ImageData, u8[>..], const u8[:] {
    let bytes, read_ok = read_image_file(path, PNG_LIMIT);
    if !read_ok { return ImageData {}, [], "Cannot read this PNG (maximum 16 MB)."; }
    let w, h, png_ok = png_dimensions(bytes);
    if !png_ok { return ImageData {}, [], "Choose a valid PNG up to 4096 x 4096 pixels."; }
    let snapshot = str(directory, "/.import-", random_seed(), ".png");
    if snapshot.len >= 1000 || file_exists(snapshot) || !write_file_atomic(snapshot, bytes) {
        return ImageData {}, [], "Cannot prepare the image in the save folder.";
    }
    let source = gfx::load_texture(snapshot, 0);
    delete_file(snapshot);
    if source.id == 0 { return ImageData {}, [], "This PNG could not be decoded."; }
    let info = gfx::texture_info(source);
    if info.width != w || info.height != h { gfx::release(source); return ImageData {}, [], "Invalid PNG dimensions."; }
    let rgba = gfx::read_pixels(source);
    gfx::release(source);
    let image, error = normalize_image(rgba, w, h);
    if error.len > 0 { return ImageData {}, [], error; }
    return image, bytes, "";
}

fn release_image_slot(slot: ImageSlot&) {
    if slot.source.id != 0 { gfx::release(slot.source); }
    if slot.pose.id != 0 { gfx::release(slot.pose); }
    slot = ImageSlot {};
}

fn prepare_image_slot(slot: ImageSlot&, image: const ImageData&) -> bool {
    var pixels: u8[>..] = []; pixels.append(image.rgba);
    for i in image.width * image.height {
        let alpha = pixels[i * 4 + 3] as u32;
        for c in 3 { pixels[i * 4 + c] = ((pixels[i * 4 + c] * alpha + 127) / 255) as! u8; }
    }
    let source = gfx::texture(gfx::TextureDesc { width: image.width as! i32, height: image.height as! i32, mips: 0 });
    if source.id == 0 { return false; }
    if !gfx::update_texture(source, pixels) { gfx::release(source); return false; }
    gfx::generate_mips(source);
    release_image_slot(slot);
    slot.source = source; slot.width = image.width; slot.height = image.height;
    return true;
}

fn prepare_image_renderer(renderer: ImageRenderer&) -> bool {
    if renderer.pipeline.id != 0 { return true; }
    let vs = embed_shader("vert", """
        layout(location = 0) in vec3 a_position;
        layout(location = 1) in vec2 a_uv;
        layout(location = 0) out vec2 v_uv;
        void main() {
            v_uv = a_uv;
            gl_Position = vec4(a_position.xy * a_position.z, 0.0, a_position.z);
        }
        """);
    let fs = embed_shader("frag", """
        layout(set = 2, binding = 0) uniform sampler2D art;
        layout(location = 0) in vec2 v_uv;
        layout(location = 0) out vec4 result;
        void main() {
            vec4 c = texture(art, v_uv);
            result = vec4(c.a > 0.00001 ? c.rgb / c.a : vec3(0.0), c.a);
        }
        """);
    renderer.pipeline = gfx::pipeline(vs, fs);
    renderer.sampler = gfx::sampler(gfx::LINEAR, gfx::CLAMP);
    renderer.buffer = gfx::buffer(gfx::BUFFER_VERTEX, 72 * 20, []);
    return renderer.pipeline.id != 0 && renderer.sampler.id != 0 && renderer.buffer.id != 0;
}

fn render_image_pose(renderer: ImageRenderer&, slot: ImageSlot&, w: f32, h: f32,
                     phase: f32, swim: bool, heading: f32, pitch: f32, flip: bool) -> gfx::Texture {
    if slot.source.id == 0 || w <= 0.0 || h <= 0.0 || !prepare_image_renderer(renderer) { return gfx::Texture { 0 }; }
    let ow = max(1, min(1024, ceil(w + 16.0) as! i64));
    let oh = max(1, min(1024, ceil(h + 16.0) as! i64));
    if ow != slot.output_width || oh != slot.output_height {
        if slot.pose.id != 0 { gfx::release(slot.pose); }
        slot.pose = gfx::render_target(ow, oh, gfx::RGBA8);
        slot.output_width = ow; slot.output_height = oh;
    }
    if slot.pose.id == 0 { return gfx::Texture { 0 }; }
    let turn = turn_view(heading, w, pitch);
    let scale = min(w / (slot.width * abs(turn.tilt_cos) + slot.height * abs(turn.tilt_sin)),
                      h / (slot.width * abs(turn.tilt_sin) + slot.height * abs(turn.tilt_cos)));
    var vertices: ImageVertex[>..] = [];
    let triangles: i64[6] = [0, 1, 2, 0, 2, 3];
    for piece in 12 {
        var corners: ImageVertex[>..] = [];
        let positions: f32[2][4] = [[piece / 12.0, 0.0], [(piece + 1) / 12.0, 0.0],
                                    [(piece + 1) / 12.0, 1.0], [piece / 12.0, 1.0]];
        for uv in positions {
            let wave = if swim { sin(phase + uv[0] * 3.0) * wave_height(turn.across) } else { 0.0 };
            let x, y, near = body_point(turn, (uv[0] - 0.5) * slot.width * scale, (uv[1] - 0.5) * slot.height * scale + wave);
            corners.push(ImageVertex { position: float3 { (8.0 + w * 0.5 + x) / (w + 16.0) * 2.0 - 1.0,
                1.0 - (8.0 + h * 0.5 + y) / (h + 16.0) * 2.0, 1.0 / near },
                uv: float2 { if flip { 1.0 - uv[0] } else { uv[0] }, uv[1] } });
        }
        for index in triangles { vertices.push(corners[index]); }
    }
    if !gfx::update_buffer(renderer.buffer, bytes_of(vertices)) { return gfx::Texture { 0 }; }
    if !gfx::begin_pass(slot.pose, gfx::Texture { 0 }, float4 { 0.0, 0.0, 0.0, 0.0 }) { return gfx::Texture { 0 }; }
    gfx::bind(renderer.pipeline);
    gfx::bind_vertex_buffer(renderer.buffer);
    gfx::bind_texture(gfx::FRAGMENT, 0, slot.source, renderer.sampler);
    gfx::draw(vertices.len);
    gfx::end_pass();
    return slot.pose;
}

fn sync_image_slots(renderer: ImageRenderer&, reef: const Creature[:], directory: const u8[:]) {
    while renderer.slots.len > reef.len {
        release_image_slot(renderer.slots[renderer.slots.len - 1]);
        renderer.slots.resize(renderer.slots.len - 1);
    }
    while renderer.slots.len < reef.len { renderer.slots.push(ImageSlot {}); }
    for i in reef.len {
        let slot .= renderer.slots[i];
        if slot.key == reef[i].image_id { continue; }
        release_image_slot(slot);
        if reef[i].image_id != 0 {
            let bytes, read_ok = read_image_file(image_path(directory, reef[i].image_id), IMAGE_LIMIT);
            if read_ok {
                let image, ok = decode_image(bytes);
                if ok { prepare_image_slot(slot, image); }
            }
            slot.key = reef[i].image_id;
            if slot.source.id == 0 { write_stderr("An imported image is missing or unreadable; its saved record has been kept.\n"); }
        }
    }
}

fn release_image_renderer(renderer: ImageRenderer&) {
    for &slot in renderer.slots { release_image_slot(slot); }
    if renderer.pipeline.id != 0 { gfx::release(renderer.pipeline); }
    if renderer.sampler.id != 0 { gfx::release(renderer.sampler); }
    if renderer.buffer.id != 0 { gfx::release(renderer.buffer); }
    renderer = ImageRenderer {};
}
