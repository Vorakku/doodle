# DOODLE REEF — Build Instructions for AI Coding Agent

> **Read this entire file, then begin implementing the application.** This is the project's single source of requirements. Do not create additional planning documents or ask for permission to start ordinary implementation work. Make sensible decisions, validate them against current Goose documentation, and report actual progress and blockers.

## 1. Project vision

Build **DOODLE REEF**, a lightweight, offline-first desktop aquarium in which the user can **draw anything** on a canvas, click **Bring to Life**, and watch their original doodle swim around as a quirky fish-like creature. The aquarium must eventually function as a **live desktop wallpaper**, not merely a screensaver or a normal application window.

The magic moment is: **draw something silly → click Bring to Life → see that exact drawing swim**.

The product should feel calming, playful, polished, and personal. Preserve the user's artwork rather than replacing it with generic generated fish.

## 2. Target platforms

Support these two environments from the beginning:

- **Windows 10 / 11**, x86-64.
- **Arch Linux**, x86-64, running **Hyprland on Wayland with Caelestia Shell**.

The aquarium, drawing tools, creature behaviors, persistence, and rendering must share one implementation. Only operating-system integration should differ. Test both targets where environments are available; never claim untested platform support is verified.

## 3. Technology decisions

- **Primary language: Goose** (`aardappel/goose`). Write the editor, application state, simulation, fish behavior, drawing logic, and rendering orchestration in Goose.
- **Graphics/input/UI:** use Goose's current `gfx` and `ui` libraries backed by SDL3, subject to what the installed version actually supports.
- **Shaders:** use GLSL through Goose's documented shader pipeline when helpful; do not make shaders a prerequisite for the first playable build.
- **Native bridge:** allow a *small, focused amount of C* for Windows shell APIs and Wayland layer-shell / SDL integration that Goose cannot directly express.
- **Persistence:** local files only. Use a simple, versioned metadata format such as JSON where supported, plus lossless image data for drawings. Use appropriate user-data locations for each OS.
- **No Electron, React, Flutter, Python server, cloud backend, database server, account system, or AI-image API.**
- **No mandatory network connection at runtime.** Build-time dependencies are allowed.

**Important:** Goose is experimental and its API changes. Read its real docs and working samples before writing code. Do not invent function names, flags, or packages. Prefer compiled, tested behavior to speculative architecture.

Authoritative references:
- Goose source / installation: https://github.com/aardappel/goose
- Goose language and library documentation: https://aardappel.github.io/goose/
- Goose graphics package: https://github.com/aardappel/goose_gfx
- SDL3 custom Wayland window surfaces: https://github.com/libsdl-org/SDL/blob/main/docs/README-wayland.md
- Lively application wallpapers: https://github.com/lively-community/lively/wiki/Application-Wallpaper

## 4. Product experience

### A. Aquarium mode

A beautiful 2D underwater scene with soft gradient water, subtle caustics/light rays, drifting bubbles, a sandy bottom, gently moving plants, and creatures swimming at different speeds and depths. Keep the scene simple until the core experience works. The aquarium should feel alive even when the user does nothing.

Creatures should:
- wander independently, turn naturally, and stay within aquarium bounds;
- have individual speeds, sizes, idle patterns, and small randomized personalities;
- animate with a gentle body/tail wave rather than sliding like a static picture;
- remain visually recognizable as the user's original drawing;
- optionally react to mouse movement or feeding in a later iteration.

### B. Drawing Studio

A normal, resizable application window with:
- a large canvas supporting mouse input (tablet input is a bonus, not a prerequisite);
- brush, eraser, color picker, brush size, undo, redo, clear;
- transparent drawing background and an obvious **Bring to Life** action;
- a preview of how the creature will appear;
- a way to name, view, and delete saved creatures;
- a way to return to the aquarium without losing work.

A first iteration can use simple strokes and a basic palette. Avoid making the editor overly complicated.

### C. Bring to Life transformation

This is the signature feature. Do **not** require the user to draw a fish.

For the MVP:
1. Capture the user-drawn pixels or strokes with transparency.
2. Find the non-empty bounds, crop with safe padding, and retain the artwork.
3. Create a creature sprite/texture from that drawing.
4. Animate it swimming with a gentle mesh/wave deformation, or a simpler reliable wobble as an interim step.
5. Move it around the aquarium with sensible turning and direction handling. Avoid mirrored text/artwork when possible.
6. Save it and restore it after restarting.

If useful, offer subtle optional fish features like an eye or tail, but **never erase or replace the original doodle**. Realistic AI-based shape reinterpretation is **out of scope** for the initial release.

### D. Wallpaper mode

The same aquarium should render behind ordinary desktop windows without intercepting normal desktop clicks.

**Windows:** first prove a standalone aquarium window. For the initial wallpaper integration, investigate **Lively Wallpaper application wallpaper** as the least risky route. The wallpaper renderer should be a **single-window executable/process** because Lively's application wallpaper support has limitations around multi-window apps. Later, if useful, implement a native Win32 desktop-host adapter. Never rely on `SetParent`/WorkerW tricks without runtime validation and clean recovery.

**Arch / Hyprland / Caelestia:** investigate a **Wayland layer-shell background surface**. A regular XDG-toplevel or always-on-bottom window is **not** an acceptable final wallpaper. SDL3 documents custom, roleless Wayland surfaces; a minimal C bridge may be needed for `wlr-layer-shell` integration and surface sizing. Do not assume this already exists in Goose's `gfx` API.

Caelestia can allow a separate wallpaper daemon to draw beneath its widgets by disabling its own wallpaper in `~/.config/caelestia/shell.json`:

```json
{
  "background": {
    "wallpaperEnabled": false
  }
}
```

**Do not silently edit the user's Caelestia or Hyprland configuration.** Explain any manual opt-in changes. Preserve normal panels, desktop widgets, keyboard focus, and input behavior. Also account for display resizing, monitor selection, and compositor restarts later.

## 5. Core architecture (conceptual, not a required folder structure)

Keep these concerns separate in code, even if the prototype begins with very few files:

- **Aquarium simulation:** fixed/controlled delta-time updates, creature positions, velocities, boundaries, behavior states.
- **Drawing / creature assets:** canvas strokes or pixels, transparent images, metadata, save/load.
- **Rendering:** one scene renderer reusable in normal-window and wallpaper contexts.
- **Studio UI:** editing controls and aquarium management.
- **Platform adapter:** regular window, Windows wallpaper host, and Wayland wallpaper host.

The drawing editor and wallpaper renderer may be separate processes if that makes desktop embedding more reliable; they should share saved state. Do not force everything into one OS window when doing so would break wallpaper mode.

## 6. Development order — actually start coding

**Milestone 0 — Verify Goose setup**
- Inspect the available OS, compiler, Goose version, graphics support, and build tools.
- Read a current Goose `gfx` example, the UI example, and current build instructions.
- Run or compile a minimal graphics sample. Record exact working commands.
- If the compiler is unavailable, install or document the exact necessary setup within the permissions of the environment. Do not fabricate successful builds.

**Milestone 1 — First playable aquarium**
- Open a resizable desktop window in Goose.
- Draw a simple underwater background and animate **one test creature**.
- Make the creature move, turn, stay in bounds, and animate visibly.
- Use frame-time-based movement; cap frame rate where practical.
- Verify this runs locally before expanding the scope.

**Milestone 2 — Drawing becomes a creature**
- Add the basic drawing canvas and **Bring to Life**.
- Capture the actual drawing and make it appear in the aquarium.
- Support at least three saved creatures and persistence across restarts.
- Make even an arbitrary doodle (not shaped like a fish) swim.

**Milestone 3 — Wallpaper proof**
- Verify Windows wallpaper hosting and Linux/Hyprland background-layer hosting independently.
- Preserve desktop input, panels, and normal windows.
- Make mode switching and shutdown reliable.
- If one platform is unavailable for testing, clearly mark it **unverified** and provide exact reproduction steps; continue with what can be tested.

**Milestone 4 — Polish**
- Improve swim deformation, lighting, bubbles, plants, visual quality, editor UX, and creature management.
- Add sensible settings for resolution/scaling, FPS, pause, and auto-start.
- Optimize idle CPU/GPU usage and test resize/restart/save recovery.

**Prioritization rule:** Make a tiny **working** milestone before adding ambitious effects or complex architecture. Wallpaper feasibility on both OSes is the main technical risk; prototype it early, without blocking the initial creative experience.

## 7. UX and visual direction

- Cozy 2D, handmade characters, premium-but-playful desktop feel.
- Deep blue/teal water, warm sandy accents, softly glowing bubbles and light.
- Clean, minimal controls; aquarium itself is the hero.
- Fluid motion without distracting effects or excessive glow.
- No placeholder dashboards, giant sidebars, web-app styling, or unnecessary screens.
- Respect high-DPI screens and window resizing.

## 8. Performance, safety, and reliability

- Aim for smooth 60 FPS on a typical desktop, with 30 FPS and pause options for wallpaper mode. These are **targets to measure**, not guarantees.
- Avoid unbounded memory growth from new drawings, textures, or particles; set sensible limits.
- Handle malformed saved data gracefully and avoid overwriting user drawings accidentally.
- Never seize keyboard focus or block desktop clicks in wallpaper mode.
- Keep all data local; the product should work without an account or cloud dependency.
- Do not automatically alter shell configs, install startup entries, or change system settings without explicit user approval.
- Prefer small native dependencies and documented setup instructions.

## 9. Definition of done for the first real release

A user can:
1. Launch DOODLE REEF in a normal window.
2. Draw a ridiculous shape using a mouse.
3. Click **Bring to Life**.
4. Recognize their exact drawing swimming among other creatures.
5. Quit and relaunch without losing their creatures.
6. Enable a working live aquarium wallpaper on Windows or Hyprland/Caelestia through clearly documented platform-specific setup, without disrupting the desktop.

Only claim a platform is supported after it is tested on that platform. A partial release is acceptable if honestly labeled.

## 10. Instructions to the coding agent

**Start implementing now. Do not respond with only a plan.**

1. Inspect the repository and environment.
2. Validate Goose syntax and graphics APIs against official source/examples.
3. State a short implementation plan, then create the smallest working code.
4. Run build/tests or explain precisely why execution cannot be verified.
5. Fix compilation/runtime errors before claiming a milestone is finished.
6. Continue toward the next milestone within the current task's scope.
7. End each work session with: **what was implemented, exact commands to run it, what was tested, what remains, and blockers**.

Do not replace Goose with another application framework just because it is easier. Native C should remain an OS-integration bridge only. If a Goose limitation makes a feature impossible, demonstrate the limitation, propose the smallest workaround, and keep as much product logic as possible in Goose.

**Do not produce extra PRDs, roadmaps, or folder diagrams. This single file is the handoff. Create only the code and assets necessary to make the app work.**

**First immediate action:** Verify the Goose toolchain and create a running, resizable underwater window with one animated creature.
