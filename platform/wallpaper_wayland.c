#include <SDL3/SDL.h>
#include <wayland-client.h>
#include <poll.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "wlr-layer-shell-client-protocol.h"

typedef struct { const uint8_t *data; int64_t len; } ReefBytes;
typedef struct {
    struct wl_output *object;
    uint32_t global;
    char name[128];
} ReefOutput;
static struct {
    bool requested, configured, closed;
    char output_name[128];
    SDL_Window *window;
    struct wl_display *display;       /* Borrowed from SDL. */
    struct wl_surface *surface;       /* Borrowed from SDL. */
    struct wl_registry *registry;
    struct wl_compositor *compositor;
    struct zwlr_layer_shell_v1 *shell;
    struct zwlr_layer_surface_v1 *layer;
    ReefOutput outputs[32];
    unsigned output_count;
    uint32_t selected_global;
} reef;

void reef_wallpaper_stop(void);
SDL_Window *__real_SDL_CreateWindow(const char *title, int w, int h, SDL_WindowFlags flags);

static void output_geometry(void *data, struct wl_output *o, int32_t x, int32_t y,
    int32_t pw, int32_t ph, int32_t subpixel, const char *make, const char *model, int32_t transform) {
    (void)data; (void)o; (void)x; (void)y; (void)pw; (void)ph;
    (void)subpixel; (void)make; (void)model; (void)transform;
}
static void output_mode(void *data, struct wl_output *o, uint32_t flags, int32_t w, int32_t h, int32_t refresh) {
    (void)data; (void)o; (void)flags; (void)w; (void)h; (void)refresh;
}
static void output_done(void *data, struct wl_output *o) { (void)data; (void)o; }
static void output_scale(void *data, struct wl_output *o, int32_t scale) { (void)data; (void)o; (void)scale; }
static void output_name(void *data, struct wl_output *o, const char *name) {
    (void)o;
    ReefOutput *output = data;
    snprintf(output->name, sizeof output->name, "%s", name);
}
static void output_description(void *data, struct wl_output *o, const char *text) { (void)data; (void)o; (void)text; }
static const struct wl_output_listener output_listener = {
    .geometry = output_geometry, .mode = output_mode, .done = output_done,
    .scale = output_scale, .name = output_name, .description = output_description
};

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
                            const char *interface, uint32_t version) {
    (void)data;
    if (!strcmp(interface, "wl_compositor") && !reef.compositor) {
        reef.compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 1);
    } else if (!strcmp(interface, "zwlr_layer_shell_v1") && !reef.shell) {
        reef.shell = wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface, version < 4 ? version : 4);
    } else if (!strcmp(interface, "wl_output") && reef.output_count < 32) {
        ReefOutput *output = &reef.outputs[reef.output_count++];
        output->global = name;
        output->object = wl_registry_bind(registry, name, &wl_output_interface, version < 4 ? version : 4);
        wl_output_add_listener(output->object, &output_listener, output);
    }
}
static void registry_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data; (void)registry;
    if (name == reef.selected_global) reef.closed = true;
}
static const struct wl_registry_listener registry_listener = { registry_global, registry_remove };

static void layer_configure(void *data, struct zwlr_layer_surface_v1 *layer,
                            uint32_t serial, uint32_t width, uint32_t height) {
    (void)data;
    zwlr_layer_surface_v1_ack_configure(layer, serial);
    int w, h;
    SDL_GetWindowSize(reef.window, &w, &h);
    if (width) w = (int)width;
    if (height) h = (int)height;
    if (w < 1 || h < 1 || !SDL_SetWindowSize(reef.window, w, h)) {
        reef.closed = true;
        return;
    }
    reef.configured = true;
}
static void layer_closed(void *data, struct zwlr_layer_surface_v1 *layer) {
    (void)data; (void)layer;
    reef.closed = true;
}
static const struct zwlr_layer_surface_v1_listener layer_listener = { layer_configure, layer_closed };

uint8_t reef_wallpaper_prepare(ReefBytes output) {
    if (output.len < 0 || output.len >= (int64_t)sizeof reef.output_name) {
        fputs("The Wayland output name is too long.\n", stderr);
        return 0;
    }
    memset(&reef, 0, sizeof reef);
    if (output.len) memcpy(reef.output_name, output.data, (size_t)output.len);
    reef.requested = true;
    return SDL_SetHintWithPriority(SDL_HINT_VIDEO_DRIVER, "wayland", SDL_HINT_OVERRIDE) &&
           SDL_SetHint(SDL_HINT_WINDOW_ACTIVATE_WHEN_SHOWN, "0");
}

/* The linker wraps Goose gfx's one SDL_CreateWindow call; the renderer stays unchanged. */
SDL_Window *__wrap_SDL_CreateWindow(const char *title, int w, int h, SDL_WindowFlags flags) {
    if (!reef.requested) return __real_SDL_CreateWindow(title, w, h, flags);
    if (strcmp(SDL_GetCurrentVideoDriver(), "wayland")) {
        SDL_SetError("Wallpaper mode requires native Wayland, not X11/XWayland");
        return NULL;
    }
    SDL_PropertiesID props = SDL_CreateProperties();
    if (!props) return NULL;
    if (!SDL_SetStringProperty(props, SDL_PROP_WINDOW_CREATE_TITLE_STRING, title) ||
        !SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER, w) ||
        !SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER, h) ||
        !SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_FLAGS_NUMBER, (Sint64)flags) ||
        !SDL_SetBooleanProperty(props, SDL_PROP_WINDOW_CREATE_HIGH_PIXEL_DENSITY_BOOLEAN, true) ||
        !SDL_SetBooleanProperty(props, SDL_PROP_WINDOW_CREATE_FOCUSABLE_BOOLEAN, false) ||
        !SDL_SetBooleanProperty(props, SDL_PROP_WINDOW_CREATE_WAYLAND_SURFACE_ROLE_CUSTOM_BOOLEAN, true)) {
        SDL_DestroyProperties(props);
        return NULL;
    }
    SDL_Window *window = SDL_CreateWindowWithProperties(props);
    SDL_DestroyProperties(props);
    if (!window) return NULL;
    reef.window = window;
    props = SDL_GetWindowProperties(window);
    reef.display = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WAYLAND_DISPLAY_POINTER, NULL);
    reef.surface = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER, NULL);
    if (!reef.display || !reef.surface) { SDL_SetError("SDL did not provide a custom Wayland surface"); goto fail; }
    reef.registry = wl_display_get_registry(reef.display);
    wl_registry_add_listener(reef.registry, &registry_listener, NULL);
    if (wl_display_roundtrip(reef.display) < 0 || wl_display_roundtrip(reef.display) < 0) {
        SDL_SetError("Could not enumerate Wayland globals"); goto fail;
    }
    if (!reef.shell || !reef.compositor) { SDL_SetError("Compositor does not provide wlr-layer-shell"); goto fail; }
    struct wl_output *output = NULL;
    if (reef.output_name[0]) {
        for (unsigned i = 0; i < reef.output_count; ++i) {
            if (!strcmp(reef.output_name, reef.outputs[i].name)) {
                output = reef.outputs[i].object;
                reef.selected_global = reef.outputs[i].global;
                break;
            }
        }
        if (!output) { SDL_SetError("Wayland output '%s' not found (output naming requires wl_output v4)", reef.output_name); goto fail; }
    }
    reef.layer = zwlr_layer_shell_v1_get_layer_surface(reef.shell, reef.surface, output,
        ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND, "doodle-reef");
    if (!reef.layer) { SDL_SetError("Could not create a Wayland background layer"); goto fail; }
    zwlr_layer_surface_v1_add_listener(reef.layer, &layer_listener, NULL);
    zwlr_layer_surface_v1_set_anchor(reef.layer, ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
        ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM | ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
    zwlr_layer_surface_v1_set_size(reef.layer, 0, 0);
    zwlr_layer_surface_v1_set_exclusive_zone(reef.layer, -1);
    zwlr_layer_surface_v1_set_keyboard_interactivity(reef.layer, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);
    struct wl_region *input = wl_compositor_create_region(reef.compositor);
    if (!input) { SDL_SetError("Could not create an empty wallpaper input region"); goto fail; }
    wl_surface_set_input_region(reef.surface, input);
    wl_region_destroy(input);
    wl_surface_commit(reef.surface);

    Uint64 deadline = SDL_GetTicks() + 5000;
    while (!reef.configured && !reef.closed && SDL_GetTicks() < deadline) {
        while (wl_display_prepare_read(reef.display) != 0) {
            if (wl_display_dispatch_pending(reef.display) < 0) { SDL_SetError("Wayland dispatch failed"); goto fail; }
        }
        wl_display_flush(reef.display);
        struct pollfd fd = { wl_display_get_fd(reef.display), POLLIN, 0 };
        int result = poll(&fd, 1, 100);
        if (result > 0 && (fd.revents & POLLIN)) {
            if (wl_display_read_events(reef.display) < 0) { SDL_SetError("Wayland connection closed"); goto fail; }
        } else {
            wl_display_cancel_read(reef.display);
            if ((result < 0 && errno != EINTR) || (result > 0 && (fd.revents & (POLLERR | POLLHUP | POLLNVAL)))) {
                SDL_SetError("Wayland connection failed"); goto fail;
            }
        }
        if (wl_display_dispatch_pending(reef.display) < 0) { SDL_SetError("Wayland dispatch failed"); goto fail; }
    }
    if (!reef.configured || reef.closed) { SDL_SetError("Background layer did not configure within five seconds"); goto fail; }
    return window;
fail:
    fprintf(stderr, "DOODLE REEF Wayland: %s\n", SDL_GetError());
    reef_wallpaper_stop();
    SDL_DestroyWindow(window);
    return NULL;
}

uint8_t reef_wallpaper_ready(void) { return reef.configured && !reef.closed; }
uint8_t reef_wallpaper_alive(void) {
    if (!reef.display || wl_display_dispatch_pending(reef.display) < 0) return 0;
    return reef.configured && !reef.closed && wl_display_get_error(reef.display) == 0;
}
void reef_wallpaper_stop(void) {
    if (reef.layer) zwlr_layer_surface_v1_destroy(reef.layer);
    if (reef.shell) {
        if (wl_proxy_get_version((struct wl_proxy *)reef.shell) >= 3) zwlr_layer_shell_v1_destroy(reef.shell);
        else wl_proxy_destroy((struct wl_proxy *)reef.shell);
    }
    for (unsigned i = 0; i < reef.output_count; ++i)
        if (reef.outputs[i].object) wl_output_destroy(reef.outputs[i].object);
    if (reef.compositor) wl_compositor_destroy(reef.compositor);
    if (reef.registry) wl_registry_destroy(reef.registry);
    if (reef.display) wl_display_flush(reef.display);
    memset(&reef, 0, sizeof reef);
}

uint8_t reef_background_button_available(void) { return 0; }
uint8_t reef_set_background(ReefBytes directory) { (void)directory; return 0; }
