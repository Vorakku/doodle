# DOODLE REEF

A small, offline desktop aquarium written in Goose. Draw something silly and send those same strokes swimming.

## Run on Windows

Double-click the **Doodle Reef** shortcut in this folder to open the aquarium without a terminal. The Windows build creates this shortcut and configures the executable as a GUI application.

You can also run the executable directly, or use the existing launcher from a terminal:

```powershell
.\start.cmd
```

The compiled program is `build\doodle_reef.exe`. `start.cmd` still works, but double-clicking a batch file can briefly flash a terminal; use the shortcut to avoid that. The font and graphics libraries are embedded; the executable does not need the compiler or a network connection at runtime.

- **Draw a creature** opens the studio. Tools are on the left, the canvas is in the middle, and colors and everything else are on the right. Hover a tool to see its name.
- **Draw** is freehand. Drag on the checkered canvas to draw; drawing stays inside its boundary, which has the aquarium's aspect ratio.
- **Shapes** (line, rectangle, circle, triangle, diamond, hexagon, star, heart): drag on the canvas to place one, using your current color and brush size. Hold **Shift** for equal sides, such as a perfect circle or square. Each shape counts as one Undo step and can be filled.
- **Colors**: drag in the square for saturation and brightness and along the rainbow bar for hue, type a 6-digit hex code and press Enter, or click a swatch. **In this drawing** lists colors you've already used. The eyedropper picks up a color from your drawing. Colors are always fully opaque.
- Change the brush size, or use Undo / Redo / Clear canvas.
- **Scroll over the canvas** or use **+ / -** to zoom (25%–1600%). **Fit** shows the whole canvas again. Hold the **middle mouse button**, or **Space + left drag**, to pan. Zooming changes your view, not the drawing's size. The canvas keeps its proportions when you resize the window; Clear starts a fresh canvas using the current aquarium proportions.
- Keep the mouse button held when leaving the canvas: drawing resumes as the same connected stroke when you return. Releasing outside ends the stroke; a new stroke must start inside the canvas.
- Choose **Fill**, then click inside a closed outline to fill it with the selected color. Your outline can be several strokes. If it leaks, loose stroke ends within about 2% of the canvas width are connected to the nearest line; if the spot still isn't enclosed, a message says so and nothing changes. Fills sit underneath your lines, so eyes and details stay visible, and small enclosed shapes can still be filled separately. Click a filled area again to recolor it. One Undo removes one whole fill. Fills count toward the drawing-point limit, and shapes only a few pixels across can't be filled. Older builds show filled creatures as thin lines, so rebuild the wallpaper along with the editor.
- **Ctrl+Z** and **Ctrl+Y** undo and redo in the drawing studio, the same as the Undo and Redo buttons.
- **Bring to Life** asks you to name your fish first. Enter a nonblank name of up to 32 characters, then confirm with the button or Enter. Cancel or Escape keeps the drawing on the canvas. Names are saved with the fish; a failed save keeps both the drawing and typed name for retry. The canvas clears only after a successful save.
- **Every creature starts as a tiny baby about 19 pixels wide**, however big or small you draw it, then grows toward its tier's adult size. All tiers start equally small. Its proportions are preserved; large creatures scale down to fit smaller tanks without losing growth progress. Drawing at a higher zoom gives more detail.
- **Back to aquarium** and Escape preserve your in-memory canvas while switching views.
- Creatures independently pick alternating upper and lower destinations every 14-21 seconds. They ease into climbs and dives, slowing horizontal travel during steeper moves, and stay within the vertical swimming area. Each creature has its own rhythm; vertical travel is independent of horizontal position and turns. Pause and holding a creature stop its movement.
- Bodies tilt toward their travel direction using forward and vertical speed in screen pixels. A critically damped angular response eases into climbs, dives and level swimming without following the small body bob. Tilts work in both directions, remain steady through turns into the tank, and stop while paused or held. The outline and fills rotate together within the selection area; tilt is limited to 70 degrees.
- Each creature eases between gentle pushes and slower glides, with occasional short rests. The rhythm and strength vary independently per creature and cycle. Pacing affects both horizontal and vertical travel and the body bob; a resting fish settles in place and gradually levels out before accelerating again. Base swimming speeds and the save format are unchanged.
- **Pause / Resume** (or Space in aquarium view) pauses swimming and scenery.
- **Reset swim** repositions creatures; it does not delete them.
- Each creature's name swims below it in aquarium view. Click a creature to select it: a mint outline appears, and its tier shows below its name, like "Tier C". The studio and desktop wallpaper don't show these labels. Click **Delete fish (Del)** or press Delete to remove it permanently. Click empty water or press Escape to deselect. Deletion is saved immediately; if saving fails, the creature stays. Deleting every creature leaves an empty aquarium across restarts.
- Hold and drag a creature to move it. It follows the exact point where you grabbed it, stays fully on screen, and stops swimming while held. Release to resume swimming (or keep it still using Pause). The drop position is saved when you release it.
- Drew a creature facing left? Select it in aquarium view and click **Flip fish** beside Delete at the bottom. This mirrors its artwork and saves the correction. Click it again to reverse the correction. The wallpaper picks up the saved flip too. If saving fails, the original artwork is restored.
- **Set as desktop background** (top left) saves the current aquarium and applies it. On Windows it asks Lively to use the primary monitor; install/open Lively's standalone desktop edition once first, and the button guides you if setup is needed. On Hyprland it covers every current monitor and comes back after login. Use Bring to Life first to include a new canvas drawing.

Saved creatures live in **`build\data\creatures.reef`**, beside the executable, unless `--data-dir PATH` selects another directory. The Linux launchers use `$XDG_DATA_HOME/doodle-reef` or `~/.local/share/doodle-reef`. Keep your data folder when moving or replacing the executable. Drawings are stored losslessly as colored strokes in a versioned binary file; writes are atomic. If a save is unreadable, the program preserves it and disables saving. Unreleased canvas drawings are not saved when the app closes.

This first version allows 12 creatures (including the starter fish) and 8,192 drawing points per creature. The point limit is a memory/rendering safety cap; zoom and pan do not expand the actual aquarium boundary. Creatures should face right in their base artwork; use **Flip fish** to correct a doodle drawn facing left. Past one edge of the screen, they come back in from the opposite edge at the same height. Now and then a creature turns around mid-swim, each on its own rhythm, usually about every half minute: it swings around in depth, shrinking and narrowing as it heads into the tank, then comes back at its usual size facing the other way. A creature swimming left is drawn mirrored, which also mirrors any text in the doodle. The manual Flip fish action mirrors the saved strokes without changing swimming direction.

Names, growth and imported images use save format **DREEF005**. The editor reads DREEF001 through DREEF004 saves, backs up their original bytes as `creatures.reef.v1.bak` through `creatures.reef.v4.bak`, then atomically upgrades them on opening. Existing drawings and empty aquariums are preserved. Unnamed older fish receive placeholder names such as Fish 1. DREEF003 creatures keep their existing tier and birth time; DREEF001/002 creatures receive one permanent tier and start their growth clocks at the upgrade. If a backup cannot be created, an existing backup has different bytes, or the upgrade cannot be saved, the original is preserved and saving is disabled.

Older application binaries cannot read DREEF005: restart/update the wallpaper renderer alongside the editor, and reimport the rebuilt Lively ZIP if using its copied executable. The updated wallpaper remains read-only; DREEF001/002 aquariums stay baby-size until you open the updated editor once to save growth metadata. Existing DREEF003 growth remains intact during the naming upgrade.

## Importing a transparent PNG

Open the studio with an empty canvas and click **Import** (use **Clear** first if you have drawn something). Choose a PNG with a transparent background, up to 16 MB and 4096 x 4096 pixels. Opaque or wholly invisible images are rejected with a message, and a cancelled or rejected import leaves the canvas as it was. The image is imported as-is: transparent padding is trimmed, and you can zoom and pan the preview, but you can't draw on it. **Bring to Life** then names it like any drawing. Imported fish grow, swim, turn and flip like drawn fish.

The app keeps its own copy, so you can move or delete the original afterward. Each imported fish adds two files to `images` inside the data folder: `<id>.png`, the exact original, and `<id>.rgba`, a copy of at most 512 pixels per side that the app renders. Keep the `images` folder with `creatures.reef` when moving your data. A fish whose image file is missing keeps its saved record and shows as a crossed-out outline. Deleting a fish leaves its image files in place, because backups can still refer to them.

## Passive growth and tiers

Each creature gets a single random tier when successfully saved. Restarting, moving, flipping or reloading a creature keeps that tier. Its tier and UTC birth time are saved with the artwork, so growth continues while the app and wallpaper are closed and is not counted twice when both run.

| Tier | Chance | Adult width | Time to adulthood |
| --- | ---: | ---: | ---: |
| E | 40% | 64 px | 2 hours |
| D | 28% | 89.6 px | 6 hours |
| C | 18% | 121.6 px | 18 hours |
| B | 9% | 166.4 px | 3 days |
| A | 4% | 224 px | 7 days |
| S | 1% | 320 px | 30 days |

Growth is gradual and slows near adulthood. Adult widths are reference maxima; the current window caps rendering size and adjusts the swimming range to keep large creatures inside the tank. Select a creature to see its tier, growth percentage and adult/growing state in the status bar. Pause stops swimming, while real-time growth continues. This iteration has passive growth only; feeding is not implemented.

## Build and check

The Windows wallpaper renderer has passed a bounded standalone runtime check; attachment through Lively is **unverified**. Earlier Linux builds, tests and the Hyprland wallpaper have been run on Arch; see Current scope.

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
Start-Process -FilePath .\build\doodle_reef.exe -ArgumentList '--frames', '60' -Wait -WindowStyle Hidden
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
sudo pacman -S --needed base-devel pkgconf sdl3 wayland wayland-protocols vulkan-icd-loader curl jq
mkdir -p .tools
curl -fL -o .tools/goose-linux.tar.gz https://github.com/aardappel/goose/releases/download/v2026.3/goose-v2026.3-linux-x64.tar.gz
tar -xzf .tools/goose-linux.tar.gz -C .tools
bash build-linux.sh
bash start-linux.sh
```

Install the Vulkan driver appropriate to your hardware if it is not already present; `vulkan-icd-loader` alone is not a GPU driver. Arch supplies the SDL3 headers through [the sdl3 package](https://archlinux.org/packages/extra/x86_64/sdl3/). Set `GOOSE=/absolute/path/to/goose` if using the v2026.3 compiler from another location, or `CC=clang` to select clang. The script only compiles by default; `bash build-linux.sh --test` first runs the model and offscreen UI checks.

Use **`build-linux.sh`**, rather than a plain `goose build`, for the Linux application. It generates C from the same Goose source, uses Goose's bundled graphics/UI libraries, generates the Wayland protocol bindings, and links a small C bridge with GNU `--wrap=SDL_CreateWindow`. It links the system SDL3 instead of Goose's bundled `libSDL3.a`, because the bundled one in v2026.3 has no Wayland driver, so a pacman SDL3 update can affect the app. The bridge changes window creation only for wallpaper mode, using SDL's [custom roleless surface API](https://github.com/libsdl-org/SDL/blob/main/docs/README-wayland.md#using-custom-wayland-windowing-protocols-with-sdl-windows), then assigns a real background layer with an empty pointer-input region and no keyboard focus. Normal editor windows use the original SDL creation call.

## Hyprland / Caelestia wallpaper

Open the editor with `bash start-linux.sh` and click **Set as desktop background**. Without the editor:

```bash
bash build-linux.sh
build/set-background-linux.sh "$HOME/.local/share/doodle-reef"
```

To undo it and get your previous wallpaper back:

```bash
build/set-background-linux.sh --off
```

Setting the background does three things in your user account, and `--off` reverses the first two:

1. Installs and enables `~/.config/systemd/user/doodle-reef-wallpaper@.service`, one instance per current monitor. It needs a systemd-managed session such as uwsm.
2. Once the aquarium is on screen, sets `background.wallpaperEnabled` to `false` in `~/.config/caelestia/shell.json` if that file exists, so Caelestia's widgets stay above the aquarium ([Caelestia's opt-in for a separate wallpaper daemon](https://github.com/caelestia-dots/shell/discussions/2094)). `--off` sets it to `true`.
3. Keeps your original Caelestia config once, as `shell.json.doodle-reef.bak`. `--off` leaves this file in place.

Keep the project folder where it is: the service runs `build/doodle_reef` from there. Click the button again after moving the project, rebuilding, or adding a monitor. If another wallpaper daemon such as hyprpaper or swww is running, stop it yourself first.

The wallpaper is read-only and reloads changed saves once per second, preserving the current creatures when a new save is malformed. It defaults to 30 FPS. If a process exits, for example because its monitor was unplugged, systemd retries every 10 seconds. Logs: `journalctl --user -u 'doodle-reef-wallpaper@*'`.

To run it in the foreground for testing instead, use `bash wallpaper-linux.sh --output eDP-1`, with a name from `hyprctl monitors`. `DOODLE_REEF_DATA_DIR=/absolute/path` overrides the launchers' data directory. On first launch only, they copy an existing portable `build/data/creatures.reef` into an empty Linux data directory; they never replace an existing Linux save.

## Current scope

Windows native compilation, graphics/UI examples, aquarium/studio rendering, automated model checks, and offscreen UI input checks have been run locally. Model checks cover colors, shapes, fills (closed shapes, gaps, recoloring, undo/redo and the point limit), movement timing and boundaries, drag placement/clamping, stroke continuity on leaving/re-entering the canvas, release outside, padded drawing bounds, invalid point data, selection (including overlaps and resized views), three-creature persistence to disk, deletion and failed saves, empty reefs, and rejection of corrupt/truncated saves. UI checks drive the actual application through its internal mouse/key event system: drawing and filling a circle in the studio, dragging a shape, typing a hex color, swatches, the eyedropper, selecting a fish, deleting through the real button or Delete key, restarting an empty reef, dragging without a position jump or swimming while held, resuming after release, moving while paused, and saving the drop position. Desktop automation is not needed for these checks.

On Arch with Hyprland and Caelestia at 1920x1080, one monitor: earlier builds, model checks and UI checks passed. The editor ran natively on Wayland. The wallpaper was confirmed on screen with Caelestia's widgets above it, along with the button, live reload, restart after a crash, and `--off`. It used about 8% of one CPU core. A full reboot, click-through, multiple monitors and fractional scaling have not been tested. The current Windows standalone renderer has been run against isolated growth saves: valid changes reload, malformed changes retain the current aquarium, and the renderer leaves save bytes untouched. Attachment through Lively has not been verified.

The current Windows build passes model and offscreen UI checks for studio tools, movement/pacing/tilt, tier allocation, time-based growth, v1/v2 growth-save migration and backups, failed upgrades, metadata persistence across restart, mature-S sizing and selection, and dragging/resizing bounds. Growth uses the shared implementation; this growth release has not been runtime-tested on Linux or as an attached desktop wallpaper.

This is a starter application, not the full release described in `DOODLE_REEF.md`. Eraser, draft recovery, automatic startup/restart on Windows, and performance tuning remain. The canvas itself is the initial creature preview.

## References and font

Implementation follows the graphics and UI samples bundled with the pinned Goose release: `27_gfx_cube.goose` and `29_ui_todo.goose`. See the official [Goose repository](https://github.com/aardappel/goose) and [graphics/UI package](https://github.com/aardappel/goose_gfx).

`assets/Roboto-Regular.ttf` comes from the bundled UI sample. Roboto is distributed under Apache 2.0; see `assets/Roboto-LICENSE.txt` and `assets/Roboto-NOTICE.txt`.

The vendored `platform/wlr-layer-shell-unstable-v1.xml` comes from [swaywm/wlr-protocols at d1598e8](https://github.com/swaywm/wlr-protocols/blob/d1598e82240d6e8ca57729495a94d4e11d222033/unstable/wlr-layer-shell-unstable-v1.xml); its copyright and permissive license remain in the file. The Linux build generates bindings for the system wayland-protocols xdg-shell XML as well, prefixing those descriptors to avoid SDL symbol collisions.
