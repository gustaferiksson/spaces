# Window switcher: flow spec

An opt-in replacement for Mission Control: a full-screen overlay on the desktop picture showing live previews of the
windows on the current Space, stacked by app in a stable A to Z order. Off by default.

## Goals

- Opening is instant: the hot corner fires on entry, the overlay is on screen in the first frame with the animation
  starting right away, and nothing on the main thread waits for Accessibility, capture or image decoding.
- Positions are stable: the same set of apps always lands in the same places, in A to Z order.
- Windows never vanish: every on-screen window is listed, even when its app answers Accessibility badly or slowly.
- Every path works with the mouse alone and with the keyboard alone.

## Triggers

| Trigger | Behaviour |
| --- | --- |
| Hot corner | One corner of the display under the pointer, chosen in Settings (default Off). Fires as soon as the pointer enters a 4 pt square at that corner, like the macOS hot corners. |
| Shortcut | Recordable in Settings, no default. Uses the existing `HotKeyListener`. |
| URL | `spaces://window-switcher`, behaves like the shortcut. |

Each trigger toggles: firing while the panel is open closes it. Shortcut and URL do nothing while the feature is off,
and every trigger does nothing without Accessibility access.

### Hot corner rules

- Fires when the pointer enters the corner with no mouse button held. It does not fire again until the pointer has
  left the corner. Entering with a button held (a snap-area drag) does not fire, and releasing the button while still
  in the corner does not fire either.
- Global event monitors miss events over Spaces' own windows, so both a global and a local monitor feed the machine.
- The corner is checked against the full frame (not the visible frame) of the display that contains the pointer. No
  special case for a corner shared with a neighbouring display.
- The monitors exist only while the switcher is on and a corner is chosen.
- macOS's own hot corner on the same corner would also fire. Settings reads `com.apple.dock` `wvous-<corner>-corner`
  (and its `-modifier`; a corner that needs a modifier does not conflict) and, when it is set, shows a note with a
  button that opens Desktop & Dock so the user can set that corner to "-".

## What is listed

- **Windows on the current Space of every display.** The source of truth is the on-screen, layer 0 windows from
  `CGWindowListCopyWindowInfo` (owner pid, window ID, bounds and front-to-back order; none of these need Screen
  Recording). Accessibility adds titles and filters out non-window surfaces:
  - Each app's Accessibility windows are mapped to window IDs with `_AXUIElementGetWindow`. Matches with subrole
    `AXStandardWindow` or `AXDialog` are listed with their title; other matches (panels, palettes, sheets) are
    dropped.
  - A layer 0 window with no Accessibility match (Java, Wine and some Electron windows) is listed as title-less when
    it is at least 100 x 100 pt and not fully transparent. It is focused by activating its app.
  - Apps are queried in parallel off the main thread, each Accessibility call with a 100 ms timeout. An app that does
    not answer still gets its stack, built from its CG windows by the same size rule.
  - The panel opens at once with the list from the previous enumeration (the first one runs when the switcher starts)
    and swaps in the fresh list when it arrives, typically within 10 ms. Selection and expansion survive the swap
    unless their app or window is gone.
  - Decision: all displays, not only the panel's display. "Displays have separate Spaces" makes the current Space
    per display, but the panel is about getting to a window quickly, and hiding the other display's windows means
    hunting for the right corner. Grouping by app works the same either way.
- **Windows parked outside every display** (some apps keep hidden helper windows at far-off coordinates): excluded.
- **Minimized windows: excluded.** They are not on any Space and Mission Control does not show them in its grid.
- **Hidden apps: excluded.** Their windows are not on screen. ⌘Tab still reaches them.
- **Full-screen apps:** a full-screen window is its own Space. On that Space, the panel lists it (and any other
  display's windows). From a desktop Space it is not listed, matching Mission Control's per-Space view.
- **Spaces' own windows** (Settings) are excluded by pid.
- **Stage Manager:** whatever CG reports on screen is listed, so windows in side stages appear; picking one lets
  macOS switch stage.
- **Native window tabs:** only the visible tab is a window, so only it is listed.

### Ordering

- Apps: by localized name, using Finder ordering (`localizedStandardCompare`: case and diacritic insensitive, numbers
  in numeric order), ties broken by pid. Never by recency.
- Grid: filled row by row; the column count follows from the app count and the display (see Stacks).
- Windows within an app: by window ID ascending, which is creation order and does not change when a window is
  focused. The app's **most recent window** is its frontmost one in the on-screen order, used when the stack itself
  is chosen.

### Titles

- From Accessibility (`AXTitle`), never `kCGWindowName` (that needs Screen Recording).
- Cleanup removes a trailing app name joined by a separator: ` — `, ` – `, ` - `, ` | `, ` · `, `: `, compared case
  and diacritic insensitively (`Inbox — Mail` becomes `Inbox`). Only one suffix is removed. Leading app names are
  left alone.
- Whitespace is trimmed. If the result is empty, or the title was only the app name, the window is **title-less**.
- Title-less windows show `Untitled Window` in secondary text. With several title-less windows, they are numbered
  in creation order: `Untitled Window 2`.

## Overlay

- A borderless `NSPanel` subclass with `canBecomeKey` true and `.nonactivatingPanel`, covering the full frame of the
  display under the pointer (menu bar and Dock included), above full-screen windows, on every Space. It takes key
  status without activating Spaces, so the app the user came from stays frontmost until a choice is made.
- Backdrop: that display's desktop picture (`NSWorkspace.desktopImageURL(for:)`), drawn the way macOS draws it from
  `desktopImageOptions(for:)`: fill when clipping is allowed, fit on the fill colour when not, stretched for
  "scale axes independently". "Center" is drawn as fit. A black layer at 32% dims it, like Mission Control. Without
  a readable picture (or before the first one has loaded) the backdrop is a dark regular material.
- Wallpapers are decoded off the main thread with `CGImageSourceCreateThumbnailAtIndex` at the largest display's
  pixel size, when the switcher starts and on every open, and cached per URL. Opening only looks the image up, so it
  costs nothing; a picture that changed shows from the next open (or as soon as it has loaded).
- Labels and badges are always light on dark, whatever the system appearance, as in Mission Control.
- Every size, padding and radius is a multiple of 4 pt. No coloured accents; selection is a 16 pt radius white fill
  at 16%, and buttons have no focus ring.

### Stacks

- One stack per app, in a grid inside the visible frame inset by 5% on each side (90% of it). The grid is centred,
  and a short last row is centred too.
- Size: row counts from one up to the app count are tried with balanced columns (10 apps: 10, 5 x 2, 4 x 3, ...);
  the widest slot wins, ties going to fewer rows. A slot is 16:10, at most 480 pt wide, rounded down to 4 pt and
  never below 96 pt; each cell adds 8 pt around it and a 40 pt label area below. Every cell has the same size, so
  column gaps are even whatever the windows' shapes. The same apps on the same display always get the same layout;
  launching or quitting an app can change the tile size and reflow the grid, but never the A to Z order.
- Face: a live preview of the app's **main window** (its frontmost one), aspect-fit in the slot and aligned to the
  slot's bottom so titles line up across a row; 8 pt radius and a soft shadow. The app icon is a 32 pt badge inside
  its bottom-leading corner.
- Below the face: the window title in 13 pt medium and the app name in 11 pt secondary, each one line, truncated in
  the middle.
- Several windows: a count capsule at the face's top trailing corner (11 pt semibold, monospaced digits, regular
  material), and one card (2 windows) or two cards (3 or more) peeking above the face, each 4 pt higher and 16 pt
  narrower than the one in front, white at 32% and 16%.
- VoiceOver: a button labelled "<App>, 1 window" or "<App>, <n> windows", with a "Show Windows" action that
  expands it.

### Expanded stack

- Expanding swaps the grid for the app's windows, laid out with the same rule over the same 90% area: 16:10 slots up
  to 640 pt wide, a 24 pt title area below, window order by creation. The other stacks fade out and nothing else
  moves.
- Decision: expand over the grid rather than fanning out in place. The stacks already fill the screen, so a fan of
  four to six windows would either cover the neighbours anyway or shrink the previews below the stack size, which
  defeats expanding. Reusing the full area gives the biggest previews and reuses the grid rule.
- Each preview is the window's capture aspect-fit and bottom-aligned in its slot with the icon badge, and the cleaned
  title centred below in 13 pt medium.

### Captures

- On every open with Screen Recording access, one `SCShareableContent` call and then a `SCScreenshotManager` capture
  per listed window (`desktopIndependentWindow` filter, at most 640 x 400 pt at the display's scale). Every app's
  main window is captured first, all at once; the other windows start when those have finished. They run after the
  overlay is up and fill in as they finish.
- Cache: captures are kept per window ID across opens, so a reopen shows the last image at once while a fresh one is
  captured behind it. Entries for windows that are no longer listed are dropped on each enumeration.
- Title card: until a window has a capture, or always without Screen Recording access, its face is a dark fill with
  the app icon (at most 96 pt) centred and no corner badge. It has the window's shape, so nothing moves when a
  capture arrives.

### Animation

- Opening: the overlay appears on the first frame showing the undimmed wallpaper with every window's cached capture
  at that window's real on-screen frame, so it looks like the desktop. Then, in 240 ms (`.smooth`), the backdrop dims,
  each main window's preview moves into its stack face, the other windows move into their app's stack and fade out,
  and labels, badges and peeking cards fade in. Windows without a cached capture fade in at their slot instead.
  Windows on another display start off screen.
- Expanding and collapsing move the app's previews between the stack and the expanded slots with the same timing.
- Closing with Esc, a click on the backdrop or the trigger runs the opening in reverse, then hides the overlay.
  Picking a window runs it in reverse with the picked preview on top, then hides the overlay and focuses the window.
- Real windows are never moved.
- Reduce Motion: the overlay crossfades in and out and expansion crossfades, with nothing moving.
- **Animate windows** off in Settings: no animation at all; the overlay appears and disappears at once.
- Closing because the Space or display configuration changed, or because another app became active, is immediate.

### Empty state

- A glass card tinted dark, centred on the backdrop, holds a `ContentUnavailableView` with the `macwindow` symbol,
  "No Windows on This Space" and "Open windows on this Space appear here, grouped by app." Esc, a click on the
  backdrop or the trigger closes it.

### Overflow

- No scrolling. Past the 96 pt minimum slot (around 70 apps with windows on one Space on a laptop display) the grid
  is clipped.

## Mouse paths

| Action | Result |
| --- | --- |
| Hover a stack | Selects it. |
| Rest 200 ms on a stack with several windows | Expands it. Moving off before then cancels. After a collapse, a stack under the resting pointer does not expand again until the pointer leaves and re-enters it. |
| Click a single-window stack | Focuses that window. |
| Click a stack with several windows | Expands it at once. |
| Hover a preview | Selects it. |
| Click a preview | Focuses that window. |
| Click the backdrop | Collapses when expanded, otherwise closes, like Mission Control. |

## Keyboard paths

| Key | Collapsed | Expanded |
| --- | --- | --- |
| ← → ↑ ↓ | Move the stack selection (stops at the edges; ↓ from a row with no stack directly below goes to the last stack). | Move the preview selection with the same rules; the first arrow selects the first preview. ← from the first column collapses. |
| Space | Expands the selected stack (any window count) and selects its first preview. | Collapses. |
| Return | Focuses the selected app's main window. | Focuses the selected window, or the app's main one if none is selected. |
| Esc | Closes the overlay. | Collapses. |

- The first stack is selected when the overlay opens via the shortcut or URL; with the hot corner, nothing is
  selected until the pointer hovers a stack or an arrow key is pressed (the arrow then selects the first stack).
- Decision: → moves the selection rather than expanding, since a grid needs all four arrows. Space expands, as in
  Finder. Arrows follow visual direction.
- Keys are ignored while the closing animation runs.

## Focusing a window

0. Check the window still exists (its `AXRole` reads; for a window without an Accessibility element, its app is
   still running). If not, re-enumerate, keep the overlay open and stop.
1. Run the closing animation and hide the overlay.
2. Set the app's `AXFrontmost` to true. Cooperative activation can refuse `NSRunningApplication.activate()` from a
   background app, while the Accessibility route does not.
3. `AXRaise` on the window and set its `AXMain` to true. Doing this after activation keeps the app from re-keying its
   previous main window. Windows without an Accessibility element stop after step 2.

## Live changes while open

- The panel is open for about a second, so it does not watch for changes. The list is the enumeration started on
  open.
- Picking a window that has closed meanwhile re-enumerates and keeps the panel open, with nothing selected or
  expanded.
- Closes when: the active Space changes, the display configuration changes, or the panel loses key status (another
  app activated, click elsewhere).

## Permissions

- **Accessibility** (already required, status shown in General): without it the triggers do nothing.
- **Screen Recording** (strongly recommended): needed for window previews. Without it the panel works fully, with
  title cards (app icon and window title) in place of previews. Settings shows an **Allow…** button: the first press calls `CGRequestScreenCaptureAccess`, which
  prompts only once; later presses open Privacy & Security → Screen Recording. Checked with
  `CGPreflightScreenCaptureAccess` each time Settings becomes active and each time the panel opens. A grant made
  while Spaces runs may need a relaunch before captures work, so the footer says so. macOS periodically asks the
  user to reconfirm apps with Screen Recording access.

## Settings tab: "Window Switcher"

Icon `square.grid.2x2`. Sections:

1. Toggle **Window switcher**: "Show previews of the windows on this Space, stacked by app, from a hot corner or a
   shortcut." Turning it on while no corner is chosen preselects the corner macOS uses for Mission Control
   (`wvous-*-corner` = 2), if any.
2. **Hot corner** picker (Off, Top-Left, Top-Right, Bottom-Left, Bottom-Right) and the **Shortcut** row (the same
   recorder as the Shortcuts tab). Footer when both are unset: "Choose a hot corner or shortcut to open it."
3. When the switcher is on and the chosen corner also has a macOS hot corner: "macOS also uses this corner. Set it
   to - under Hot Corners, or both will open." with an **Open Desktop & Dock…** button. `com.apple.dock` is re-read
   each time Settings becomes active.
4. **Window previews**: Screen Recording status (Allowed / Allow…). Allowed: "Shows a live preview of each window."
   Not allowed: "Strongly recommended. Without Screen Recording access, windows show as title cards. After allowing
   it, quit and reopen Spaces." Below it, the **Animate windows** toggle (on by default): "Previews move between each
   window's place on screen and the grid, like Mission Control."

The hot corner, shortcut and Animate windows rows are disabled while the toggle is off. Restore Defaults in the Shortcuts tab leaves
the switcher shortcut alone. The menu bar menu gets a **Window Switcher**
toggle next to the other two features.

## Out of scope

- Windows on other Spaces, minimized windows, hidden apps.
- Closing, minimizing or quitting from the panel.
- Type-to-select by app name (a cheap follow-up that fits the A to Z grid).
- Moving VoiceOver focus into the panel on open.
