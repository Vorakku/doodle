# DOODLE REEF

A small, offline desktop aquarium written in Goose. Draw something silly and send those same strokes swimming.

## Run on Windows

Double-click **start.cmd**, or from this folder:

```powershell
.\start.cmd
```

The compiled program is `build\doodle_reef.exe`. The font and graphics libraries are embedded; the executable does not need the compiler or a network connection at runtime.

- **Draw a creature** opens the studio. Drag on the checkered canvas to draw.
- Choose one of six colors, change the brush size, or use Undo / Redo / Clear canvas.
- The studio uses a large **left-anchored canvas**, with the drawing controls on the right. Its checkered boundary has the aquarium's aspect ratio; drawing stays inside that boundary.
- **Scroll over the canvas** or use **+ / -** to zoom (25%–1600%). **Fit** shows the whole canvas again. Hold the **middle mouse button**, or **Space + left drag**, to pan. Zooming changes your view, not the drawing's size. The canvas keeps its proportions when you resize the window; Clear starts a fresh canvas using the current aquarium proportions.
- Keep the mouse button held when leaving the canvas: drawing resumes as the same connected stroke when you return. Releasing outside ends the stroke; a new stroke must start inside the canvas.
- **Bring to Life** saves the doodle and releases it into the aquarium. The canvas clears only after a successful save.
- **Larger drawings create larger creatures.** Their proportions are preserved and their size is capped to fit inside the tank. Existing creatures keep their previous size. Drawing at a higher zoom gives more detail without making a creature bigger by itself.
- **Back to aquarium** and Escape preserve your in-memory canvas while switching views.
- **Pause / Resume** (or Space in aquarium view) pauses swimming and scenery.
- **Reset swim** repositions creatures; it does not delete them.
- Click a creature in aquarium view to select it (a mint outline appears). Click **Delete fish (Del)** or press Delete to remove it permanently. Click empty water or press Escape to deselect. Deletion is saved immediately; if saving fails, the creature stays. Deleting every creature leaves an empty aquarium across restarts.
- Hold and drag a creature to move it. It follows the exact point where you grabbed it and stops swimming while held. Release to resume swimming (or keep it still using Pause). The drop position is saved when you release it.
- Drew a creature facing left? Select it in aquarium view and click **Flip fish** beside Delete at the bottom. This mirrors its artwork, saves the correction, and keeps automatic wall turns working. Click it again to reverse the correction. The wallpaper picks up the saved flip too. If saving fails, the original artwork is restored.
- **Set as desktop background** (top left, Windows) saves the current aquarium and asks Lively to apply it to the primary monitor. Install/open Lively's standalone desktop edition once first; the button guides you if setup is needed. Use Bring to Life first to include a new canvas drawing.

Saved creatures live in **`build\data\creatures.reef`**, beside the executable, unless `--data-dir PATH` selects another directory. The Linux launchers use `$XDG_DATA_HOME/doodle-reef` or `~/.local/share/doodle-reef`. Keep your data folder when moving or replacing the executable. Drawings are stored losslessly as colored strokes in a versioned binary file; writes are atomic. If a save is unreadable, the program preserves it and disables saving. Unreleased canvas drawings are not saved when the app closes.

This first version allows 12 creatures (including the starter fish) and 8,192 drawing points per creature. The point limit is a memory/rendering safety cap; zoom and pan do not expand the actual aquarium boundary. Creatures should face right in their base artwork; use **Flip fish** to correct a doodle drawn facing left. They then flip horizontally when swimming left and flip back when swimming right, including at wall turns. This also mirrors any text in the doodle while swimming left. Automatic turns affect rendering only; the manual Flip fish action mirrors the saved strokes without changing swimming direction.

The new drawing sizes use save format **DREEF002**. Older DREEF001 saves are read automatically, retaining their artwork and creature sizes. When opening an older save in the editor, it first creates `creatures.reef.v1.bak` if that backup does not already exist. If the backup cannot be written, saving is disabled. The main save is upgraded only when you save an edit. Older application binaries cannot read the new format: restart/update the wallpaper renderer along with the editor; reimport the rebuilt Lively ZIP if using its copied executable.

## Build and check

The wallpaper work was compiled on Windows without running tests, per request. Both wallpaper adapters are **unverified at runtime**; the Linux build is also unverified until built on Arch.

The project-local toolchain is the official [Goose v2026.3 Windows x64 release](https://github.com/aardappel/goose/releases/tag/v2026.3). To restore it, download `goose-v2026.3-windows-x64.zip` from that release and extract it into `.tools`, preserving the archive's top-level directory. No global PATH change is needed.

Goose builds native executables using Visual Studio Build Tools (MSVC), which it discovers automatically on this machine. Close the aquarium before rebuilding its executable.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

That command runs the model checks and real UI input checks in an offscreen window, then builds `build\doodle_reef.exe`. UI checks use isolated test saves under `.test-data`; they do not move the system mouse or use your desktop. To run the model checks alone:

```powershell
$env:GOOSE_HOME = "$PWD\.tools\cache"
& .\.tools\goose-v2026.3-windows-x64\goose.exe reef_test.goose --debug
```

For a bounded graphics check that does not control the desktop:

```powershell
$env:GOOSE_GFX_HEADLESS = '1'
& .\build\doodle_reef.exe --frames 60
Remove-Item Env:GOOSE_GFX_HEADLESS
```

This writes `build\preview.png` and exits. Add `--studio` to capture the drawing view.

To rebuild and package without running any tests:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -SkipTests
```

Both build commands also create `build\doodle-reef-lively.zip`.

## Windows desktop wallpaper — Lively

1. Install the **standalone desktop release** of [Lively Wallpaper](https://github.com/rocksdanister/lively/releases). Its application wallpaper feature is [not available in the Microsoft Store version](https://github.com/lively-community/lively/wiki/Application-Wallpaper).
2. Open Lively once and complete its first-run setup. Open **`start.cmd`**, then click **Set as desktop background** at the top left. The app saves the current aquarium, registers its own project inside your configured Lively library, and sends Lively's [`setwp` command](https://github.com/lively-community/lively/wiki/Command-Line-Controls#set-wallpaper). No manual ZIP import is needed for this button. It uses the primary monitor; choose another monitor in Lively if desired.
3. Keep using the editor to draw/manage creatures. Saved additions/deletions appear in the wallpaper within about one second. Keep `build\set-background-windows.ps1` beside `build\doodle_reef.exe`; the build copies this Windows integration helper automatically. It runs without a console window and shows a setup message if Lively is missing or needs configuration. The managed library entry references this executable and your current data directory; it does not copy or move your drawings. For a custom/portable Lively installation, open Lively first so its running executable can be found.
4. Use Lively to remove/change the wallpaper or stop its process. For multiple displays, use Lively's display selection.

Alternatively, drag **`build\doodle-reef-lively.zip`** into Lively's library and apply it there. This remains useful for manual import. Lively hosts and sizes the app behind desktop windows; DOODLE REEF does not use WorkerW/SetParent embedding. The button's library registration follows Lively's [project-directory requirement](https://github.com/rocksdanister/lively/blob/core-separation/src/Lively/Lively/Commandline/CommandHandler.cs); it updates only its own `wallpapers/doodle-reef-managed/LivelyInfo.json` entry, without changing Lively settings or startup preferences.

The package runs `doodle_reef.exe --wallpaper --fps 30 --data-dir "<this project's build\data>"`. This creates one renderer window with no editor, toolbar, footer, selection, dragging, or keyboard shortcuts. It requests no activation and uses Win32 layered/transparent/no-activate styles for click-through ([Microsoft's behavior reference](https://learn.microsoft.com/en-us/windows/win32/winmsg/window-features)). Keep Lively's mouse/keyboard forwarding disabled for this wallpaper.

Running `--wallpaper` directly creates the renderer window; **Lively is still required to attach it to the Windows desktop**. Rebuild/reimport the ZIP if the project folder moves or the executable changes. Do not delete the project's data folder after importing the ZIP; its absolute path is intentionally shared with the editor. Lively's application wallpapers may not pause automatically behind other windows, as its documentation notes. `--fps 30` limits the renderer's requested rate; performance has not been measured.

## Arch Linux — build and run

Target: x86-64 Arch, Hyprland on native Wayland, with or without Caelestia. A Vulkan-capable GPU and its matching driver are required. The editor can also use SDL's ordinary desktop backends; the wallpaper specifically requires `wlr-layer-shell` and will reject X11/XWayland instead of displaying a fake desktop background.

Copy this project to Arch, including `assets` and `platform`. To bring existing Windows creatures along, also copy `build/data/creatures.reef`. From the project directory:

```bash
sudo pacman -S --needed base-devel pkgconf sdl3 wayland wayland-protocols vulkan-icd-loader curl
mkdir -p .tools
curl -fL -o .tools/goose-linux.tar.gz https://github.com/aardappel/goose/releases/download/v2026.3/goose-v2026.3-linux-x64.tar.gz
tar -xzf .tools/goose-linux.tar.gz -C .tools
bash build-linux.sh
bash start-linux.sh
```

Install the Vulkan driver appropriate to your hardware if it is not already present; `vulkan-icd-loader` alone is not a GPU driver. Arch supplies the SDL3 headers through [the sdl3 package](https://archlinux.org/packages/extra/x86_64/sdl3/). Set `GOOSE=/absolute/path/to/goose` if using the v2026.3 compiler from another location, or `CC=clang` to select clang. The script compiles only and runs no tests.

Use **`build-linux.sh`**, rather than a plain `goose build`, for the Linux application. It generates C from the same Goose source, uses Goose's bundled graphics/UI/SDL libraries, generates the Wayland protocol bindings, and links a small C bridge with GNU `--wrap=SDL_CreateWindow`. The system SDL3 package supplies headers; it is not linked as a second SDL instance. The bridge changes window creation only for wallpaper mode, using SDL's [custom roleless surface API](https://github.com/libsdl-org/SDL/blob/main/docs/README-wayland.md#using-custom-wayland-windowing-protocols-with-sdl-windows), then assigns a real background layer with an empty pointer-input region and no keyboard focus. Normal editor windows use the original SDL creation call.

## Hyprland / Caelestia wallpaper

List your displays, then use the exact output name:

```bash
hyprctl monitors
bash wallpaper-linux.sh --output DP-1
```

Replace `DP-1` with your monitor. Without `--output`, the compositor chooses one output. Run a separate process per output for multiple monitors; all processes share the same creature file. Start `bash start-linux.sh` separately to edit while the background runs. `DOODLE_REEF_DATA_DIR=/absolute/path` overrides the launchers' data directory. On first launch only, they copy an existing portable `build/data/creatures.reef` into an empty Linux data directory; they never replace an existing Linux save.

The wallpaper is read-only and reloads changed saves once per second, preserving the current creatures when a new save is malformed. It defaults to 30 FPS; append `--fps 60` if desired. Display configure events update its logical size through SDL, which handles high-DPI scaling. If an explicitly selected output disappears, its process exits. After a compositor restart, relaunch it. Stop the foreground launcher with Ctrl+C. Automatic restart/autostart is not installed.

For **Caelestia**, manually merge this setting into `~/.config/caelestia/shell.json`, preserving your existing keys:

```json
{
  "background": {
    "wallpaperEnabled": false
  }
}
```

This is Caelestia's [documented opt-in for a separate wallpaper daemon](https://github.com/caelestia-dots/shell/discussions/2094): its background becomes transparent on the bottom layer, leaving its widgets above the aquarium. Restore `true` when returning to Caelestia's own wallpapers. If another wallpaper daemon is active, stop it yourself before starting DOODLE REEF so the two background surfaces do not cover each other. No script edits Caelestia/Hyprland configuration, startup entries, or system wallpaper settings.

Both platforms need manual confirmation of embedding/layer placement, click-through, focus, resize/scaling, and shutdown on your machines. The new Windows button/helper was compiled and packaged without launching it or changing the desktop. **No wallpaper runtime tests or Linux builds were performed in this Windows session.**

## Current scope

Windows native compilation, graphics/UI examples, aquarium/studio rendering, automated model checks, and offscreen UI input checks have been run locally. Model checks cover movement timing and boundaries, drag placement/clamping, stroke continuity on leaving/re-entering the canvas, release outside, padded drawing bounds, invalid point data, selection (including overlaps and resized views), three-creature persistence to disk, deletion and failed saves, empty reefs, and rejection of corrupt/truncated saves. UI checks drive the actual application through its internal mouse/key event system: selecting a fish, deleting through the real button or Delete key, restarting an empty reef, dragging without a position jump or swimming while held, resuming after release, moving while paused, and saving the drop position. Desktop automation is not needed for these checks.

Those editor checks predate the wallpaper changes; they were not rerun for this change at your request. The Windows executable and Lively ZIP were rebuilt. Linux compilation and both platforms' wallpaper runtime behavior remain unverified.

The larger studio, cursor-centered zoom, panning, drawing-size scaling, save migration, and doubled point capacity were compiled on Windows without runtime testing, per your preference. Regression checks for canvas transforms/clipping, large-creature bounds, size persistence, and legacy save migration were added and typechecked only.

This is a starter application, not the full release described in `DOODLE_REEF.md`. Eraser, arbitrary color picker, creature names, draft recovery, automatic startup/restart, and performance tuning remain. The canvas itself is the initial creature preview.

## References and font

Implementation follows the graphics and UI samples bundled with the pinned Goose release: `27_gfx_cube.goose` and `29_ui_todo.goose`. See the official [Goose repository](https://github.com/aardappel/goose) and [graphics/UI package](https://github.com/aardappel/goose_gfx).

`assets/Roboto-Regular.ttf` comes from the bundled UI sample. Roboto is distributed under Apache 2.0; see `assets/Roboto-LICENSE.txt` and `assets/Roboto-NOTICE.txt`.

The vendored `platform/wlr-layer-shell-unstable-v1.xml` comes from [swaywm/wlr-protocols at d1598e8](https://github.com/swaywm/wlr-protocols/blob/d1598e82240d6e8ca57729495a94d4e11d222033/unstable/wlr-layer-shell-unstable-v1.xml); its copyright and permissive license remain in the file. The Linux build generates bindings for the system wayland-protocols xdg-shell XML as well, prefixing those descriptors to avoid SDL symbol collisions.
