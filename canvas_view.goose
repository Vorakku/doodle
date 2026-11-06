import std;
import math;
import reef_model;

struct CanvasView { zoom: f32 = 1.0, pan_x: f32 = 0.0, pan_y: f32 = 0.0 }

fn canvas_document(aspect: f32) -> Bounds {
    Bounds { 0.0, 0.0, min(1.0, aspect), min(1.0, 1.0 / aspect) }
}

fn canvas_area(view: CanvasView, viewport: Bounds, document: Bounds) -> Bounds {
    let scale = min(viewport.w / document.w, viewport.h / document.h) * view.zoom;
    Bounds { viewport.x + view.pan_x, viewport.y + view.pan_y, document.w * scale, document.h * scale }
}

fn pan_canvas(view: CanvasView&, viewport: Bounds, document: Bounds, dx: f32, dy: f32) {
    let area = canvas_area(view, viewport, document);
    view.pan_x = clamp(view.pan_x + dx, min(0.0, viewport.w - area.w), max(0.0, viewport.w - area.w));
    view.pan_y = clamp(view.pan_y + dy, min(0.0, viewport.h - area.h), max(0.0, viewport.h - area.h));
}

fn zoom_canvas(view: CanvasView&, viewport: Bounds, document: Bounds, x: f32, y: f32, factor: f32) {
    let before = canvas_area(view, viewport, document);
    view.zoom = clamp(view.zoom * factor, 0.25, 16.0);
    let after = canvas_area(view, viewport, document);
    view.pan_x = x - viewport.x - (x - before.x) / before.w * after.w;
    view.pan_y = y - viewport.y - (y - before.y) / before.h * after.h;
    pan_canvas(view, viewport, document, 0.0, 0.0);
}

fn intersect_area(a: Bounds, b: Bounds) -> Bounds {
    let x = max(a.x, b.x);
    let y = max(a.y, b.y);
    Bounds { x, y, max(0.0, min(a.x + a.w, b.x + b.w) - x), max(0.0, min(a.y + a.h, b.y + b.h) - y) }
}

// Clip before calling Nuklear: zoomed coordinates can exceed its 16-bit command storage.
fn clip_line(x0: f32, y0: f32, x1: f32, y1: f32, clip: Bounds, padding: f32) -> f32, f32, f32, f32, bool {
    let dx = x1 - x0;
    let dy = y1 - y0;
    let p: f32[4] = [-dx, dx, -dy, dy];
    let q: f32[4] = [x0 - clip.x + padding, clip.x + clip.w + padding - x0,
                       y0 - clip.y + padding, clip.y + clip.h + padding - y0];
    var first: f32 = 0.0;
    var last: f32 = 1.0;
    for i in 4 {
        if p[i] == 0.0 {
            if q[i] < 0.0 { return 0.0, 0.0, 0.0, 0.0, false; }
        } else {
            let t = q[i] / p[i];
            if p[i] < 0.0 { first = max(first, t); } else { last = min(last, t); }
        }
    }
    return x0 + first * dx, y0 + first * dy, x0 + last * dx, y0 + last * dy, first <= last;
}
