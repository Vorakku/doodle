extern fn reef_wallpaper_prepare(output: const u8[:]) -> bool;
extern fn reef_wallpaper_ready() -> bool;
extern fn reef_wallpaper_alive() -> bool;
extern fn reef_wallpaper_stop();
extern fn reef_background_button_available() -> bool;
extern fn reef_set_background(data_directory: const u8[:]) -> bool;
