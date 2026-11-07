#include <stdint.h>
#include <stdbool.h>
#include <string.h>

/* The pinned Windows SDK ships SDL binaries without public headers.
   These SDL3 declarations match https://wiki.libsdl.org/SDL3/SDL_ShowOpenFileDialog. */
typedef struct SDL_Window SDL_Window;
typedef struct SDL_Mutex SDL_Mutex;
typedef struct { const char *name; const char *pattern; } SDL_DialogFileFilter;
extern SDL_Window *SDL_GetKeyboardFocus(void);
extern SDL_Mutex *SDL_CreateMutex(void);
extern void SDL_LockMutex(SDL_Mutex *mutex);
extern void SDL_UnlockMutex(SDL_Mutex *mutex);
extern void SDL_ShowOpenFileDialog(void (*callback)(void *, const char *const *, int),
    void *userdata, SDL_Window *window, const SDL_DialogFileFilter *filters,
    int nfilters, const char *default_location, bool allow_many);

typedef struct { uint8_t *data; int64_t len; } ReefDialogBuffer;
typedef struct { const uint8_t *data; int64_t len; } ReefDialogPath;
/* A callback can outlive its window; all storage and its mutex have process lifetime. */
static SDL_Mutex *mutex;
static char selected[4096];
static int state; /* 0 idle, 1 pending, 2 selected, -1 canceled, -2 error */
static const SDL_DialogFileFilter filter = { "Transparent PNG image", "png" };
#ifdef REEF_IMPORT_TESTS
static char queued[4096];
static int has_queued;
void reef_import_test_path(ReefDialogPath path) {
    if (!mutex) mutex = SDL_CreateMutex();
    if (!mutex) return;
    SDL_LockMutex(mutex);
    size_t n = path.len >= 0 && path.len < 4096 ? (size_t)path.len : 0;
    memcpy(queued, path.data, n); queued[n] = 0; has_queued = 1;
    SDL_UnlockMutex(mutex);
}
#endif
static void chosen(void *unused, const char *const *files, int filter_index) {
    (void)unused; (void)filter_index;
    SDL_LockMutex(mutex);
    if (!files) state = -2;
    else if (!files[0]) state = -1;
    else {
        size_t n = strlen(files[0]);
        if (!n || n >= sizeof selected) state = -2;
        else { memcpy(selected, files[0], n + 1); state = 2; }
    }
    SDL_UnlockMutex(mutex);
}
uint8_t reef_image_dialog_open(void) {
    if (!mutex) mutex = SDL_CreateMutex();
    if (!mutex) return 0;
    SDL_LockMutex(mutex);
    if (state == 1) { SDL_UnlockMutex(mutex); return 0; }
    state = 1;
#ifdef REEF_IMPORT_TESTS
    if (has_queued) {
        memcpy(selected, queued, sizeof selected); has_queued = 0;
        state = selected[0] ? 2 : -1;
        SDL_UnlockMutex(mutex); return 1;
    }
#endif
    SDL_UnlockMutex(mutex);
    SDL_ShowOpenFileDialog(chosen, NULL, SDL_GetKeyboardFocus(), &filter, 1, NULL, false);
    return 1;
}
int64_t reef_image_dialog_result(ReefDialogBuffer output) {
    if (!mutex) return -2;
    SDL_LockMutex(mutex);
    int64_t result = 0;
    if (state == 2) {
        size_t n = strlen(selected);
        if (output.len < 0 || n > (size_t)output.len) result = -2;
        else { memcpy(output.data, selected, n); result = (int64_t)n; }
        state = 0;
    } else if (state < 0) { result = state; state = 0; }
    SDL_UnlockMutex(mutex);
    return result;
}
