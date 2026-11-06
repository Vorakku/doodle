#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

typedef struct { const uint8_t *data; int64_t len; } ReefBytes;
static HWND reef_window;

uint8_t reef_wallpaper_prepare(ReefBytes output) {
    if (output.len) {
        fputs("Choose the Windows monitor in Lively, not with --output.\n", stderr);
        return 0;
    }
    return _putenv_s("SDL_WINDOW_ACTIVATE_WHEN_SHOWN", "0") == 0;
}

static BOOL CALLBACK find_reef_window(HWND window, LPARAM unused) {
    DWORD pid = 0;
    wchar_t title[64];
    (void)unused;
    GetWindowThreadProcessId(window, &pid);
    if (pid == GetCurrentProcessId() && GetWindowTextW(window, title, 64) &&
        wcscmp(title, L"DOODLE REEF") == 0) {
        reef_window = window;
        return FALSE;
    }
    return TRUE;
}

uint8_t reef_wallpaper_ready(void) {
    EnumWindows(find_reef_window, 0);
    if (!reef_window) {
        fputs("Wallpaper window was not found.\n", stderr);
        return 0;
    }
    LONG_PTR old_style = GetWindowLongPtrW(reef_window, GWL_EXSTYLE);
    SetLastError(0);
    LONG_PTR result = SetWindowLongPtrW(reef_window, GWL_EXSTYLE, old_style |
        WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW);
    if ((!result && GetLastError()) || !SetLayeredWindowAttributes(reef_window, 0, 255, LWA_ALPHA)) {
        fprintf(stderr, "Could not enable wallpaper click-through (Win32 error %lu).\n", GetLastError());
        SetWindowLongPtrW(reef_window, GWL_EXSTYLE, old_style);
        return 0;
    }
    return 1;
}

uint8_t reef_wallpaper_alive(void) { return reef_window && IsWindow(reef_window); }
void reef_wallpaper_stop(void) { reef_window = NULL; }

uint8_t reef_background_button_available(void) { return 1; }
uint8_t reef_background_uses_lively(void) { return 1; }

uint8_t reef_set_background(ReefBytes data_directory) {
    wchar_t script[4096], directory[4096], previous[4096], powershell[MAX_PATH], command[9000];
    DWORD count = GetModuleFileNameW(NULL, script, 4096);
    if (!count || count >= 4096 || data_directory.len <= 0 || data_directory.len > 12000) return 0;
    wchar_t *slash = wcsrchr(script, L'\\');
    if (!slash) return 0;
    slash[1] = L'\0';
    if (wcscat_s(script, 4096, L"set-background-windows.ps1") ||
        GetFileAttributesW(script) == INVALID_FILE_ATTRIBUTES) return 0;
    int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)data_directory.data,
                                    (int)data_directory.len, directory, 4095);
    if (!length) return 0;
    directory[length] = L'\0';
    count = GetSystemDirectoryW(powershell, MAX_PATH);
    if (!count || count >= MAX_PATH || wcscat_s(powershell, MAX_PATH, L"\\WindowsPowerShell\\v1.0\\powershell.exe")) return 0;
    if (_snwprintf_s(command, 9000, _TRUNCATE,
        L"\"%ls\" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%ls\"", powershell, script) < 0) return 0;

    /* Pass the data path as a literal environment value, never as PowerShell code. */
    DWORD old_length = GetEnvironmentVariableW(L"DOODLE_REEF_BACKGROUND_DATA", previous, 4096);
    if (old_length >= 4096 || !SetEnvironmentVariableW(L"DOODLE_REEF_BACKGROUND_DATA", directory)) return 0;
    STARTUPINFOW startup = {0};
    PROCESS_INFORMATION process = {0};
    startup.cb = sizeof startup;
    startup.dwFlags = STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_HIDE;
    BOOL started = CreateProcessW(powershell, command, NULL, NULL, FALSE, CREATE_NO_WINDOW,
                                  NULL, NULL, &startup, &process);
    SetEnvironmentVariableW(L"DOODLE_REEF_BACKGROUND_DATA", old_length ? previous : NULL);
    if (!started) return 0;
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return 1;
}
