#include <stdint.h>
#include <stdio.h>
#include <string.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif
typedef struct { const uint8_t *data; int64_t len; } ReefImagePath;
typedef struct { uint8_t *data; int64_t len; } ReefImageBuffer;

/* Take a bounded UTF-8-path snapshot before decoding external data. */
int64_t reef_read_image_file(ReefImagePath path, ReefImageBuffer output) {
    if (path.len <= 0 || path.len >= 4096 || output.len <= 0 || memchr(path.data, 0, (size_t)path.len)) return -1;
    FILE *file = NULL;
#ifdef _WIN32
    wchar_t name[4096];
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)path.data, (int)path.len, name, 4095);
    if (!count) return -1;
    name[count] = 0;
    if (_wfopen_s(&file, name, L"rb") || !file) return -1;
    if (_fseeki64(file, 0, SEEK_END)) { fclose(file); return -1; }
    int64_t size = _ftelli64(file);
    if (_fseeki64(file, 0, SEEK_SET)) { fclose(file); return -1; }
#else
    char name[4096];
    memcpy(name, path.data, (size_t)path.len); name[path.len] = 0;
    file = fopen(name, "rb");
    if (!file) return -1;
    if (fseeko(file, 0, SEEK_END)) { fclose(file); return -1; }
    int64_t size = (int64_t)ftello(file);
    if (fseeko(file, 0, SEEK_SET)) { fclose(file); return -1; }
#endif
    if (size < 0 || size > output.len) { fclose(file); return -1; }
    size_t got = fread(output.data, 1, (size_t)size, file);
    int extra = fgetc(file), failed = ferror(file);
    fclose(file);
    return got == (size_t)size && extra == EOF && !failed ? size : -1;
}
