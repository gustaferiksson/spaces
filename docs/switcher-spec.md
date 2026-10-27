# Window switcher: flow spec

An opt-in replacement for Mission Control: a glass panel listing the apps that have windows on the current Space,
grouped by app, in a stable A to Z order. Off by default.

## Goals

- Opening is instant: the hot corner fires on entry, the panel appears without a fade, and nothing on the main thread
  waits for Accessibility or capture.
- Positions are stable: the same set of apps always lands in the same places. Launching or quitting an app only moves
  the tiles after it.
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
    not answer still gets its tile, built from its CG windows by the same size rule.
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
- Columns: a fixed maximum per display width (as many 112 pt tiles as fit in 80% of the visible frame, at most 8),
  filled row by row, so inserting an app only shifts the tiles after it. Fewer apps than the maximum use one row of
  exactly that many columns. Positions are stable per display; a narrower display may hold fewer columns.
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

## Panel layout

- A borderless `NSPanel` subclass with `canBecomeKey` true and `.nonactivatingPanel`, sized to the visible frame of
  the display under the pointer, above full-screen windows, on every Space. It takes key status without activating
  Spaces, so the app the user came from stays frontmost until a choice is made.
- The whole panel catches clicks; a click that is not on the card closes it.
- One card, centred horizontally, its top a third of the way down the free space above and below the collapsed card.
  The card grows downward and symmetrically sideways when previews appear, so the tiles never move.
- The card is `.glassEffect(.regular)` over a 90% window background fill, 24 pt corner radius, 16 pt padding. The fill
  keeps the card the same tone over light and dark content; plain glass took on the light or dark of whatever was
  behind each half. Reduce Transparency and Increase Contrast are handled by the glass itself.
- Every size, padding and radius is a multiple of 4 pt. No coloured accents; selection uses a neutral fill, and
  buttons have no focus ring.
- Appears at once, with no fade; disappears at once.

### App tile (112 x 112 pt)

- The app icon at 64 pt on top, the app name below in 12 pt medium, one line, truncated at the tail.
- Window count badge at the icon's top trailing corner when the app has more than one window: a capsule with the
  number in 11 pt semibold, monospaced digits, regular material background.
- Stacked-cards look when there are 2 or more windows: one card shape behind the icon for 2 windows, two for 3 or
  more, each 4 pt higher and 8 pt narrower than the one in front, filled with a faint primary tint.
- Selected tile (hover or keyboard): a 16 pt radius neutral fill behind the tile.
- VoiceOver: a button labelled "<App>, 1 window" or "<App>, <n> windows", with a "Show Windows" action that
  expands it.

### Window previews

- Expanding an app shows its windows as previews in rows below the grid, 16 pt under the last tile row, centred in the
  card. Window order is creation order and does not change while the panel is open.
- Each preview is a fixed 16:10 box with the window's capture aspect-fit inside (8 pt radius), the cleaned title
  centred below in 13 pt, one line, truncated in the middle. Selection is a 16 pt radius neutral fill around box and
  title.
- Sizing: the box is as wide as possible up to 320 pt, in the space between the grid and 32 pt above the bottom of
  the visible frame, and the panel width less 32 pt margins. Row counts from one up to the window count are tried
  with balanced columns (6 windows: 6, 3 x 2, 2 x 3, ...), and the widest box wins, ties going to fewer rows. Widths
  round down to 4 pt, never below 96 pt; past that the card is clipped at the bottom of the panel.
- Captures: on every open with Screen Recording access, one `SCShareableContent` call and then a
  `SCScreenshotManager` capture of every listed window (`desktopIndependentWindow` filter, at most 320 x 200 pt at the
  display's scale), started in A to Z order. They run after the panel is up and fill in as they finish.
- Cache: captures are kept per window ID across opens, so a reopen shows the last image at once while a fresh one is
  captured behind it. Entries for windows that are no longer listed are dropped on each enumeration.
- Title card: until a window has a capture, or always without Screen Recording access, its box is a faint neutral
  fill with the app icon (at most 64 pt) centred. Same size as a preview, so nothing moves when a capture arrives.

### Empty state

- The glass card holds a `ContentUnavailableView` with the `macwindow` symbol, "No Windows on This Space" and
  "Open windows on this Space appear here, grouped by app." Esc, click outside or the trigger closes it.

### Overflow

- No scrolling. With 8 columns, the grid would need about 48 apps with windows on one Space to overflow; past that
  the card is clipped to the visible frame.

## Mouse paths

| Action | Result |
| --- | --- |
| Hover a tile | Selects it. |
| Rest 200 ms on a tile | Expands it, whatever its window count, replacing any other expanded app. Moving off before then cancels, so crossing other tiles on the way down to the previews does not switch apps. |
| Click a tile | Focuses the app's most recent window and closes the panel, whatever the window count and however long the pointer rested. Expansion is by hover or keyboard only, so a click on the same spot always does the same thing. |
| Hover a preview | Selects it (and its app's tile). |
| Click a preview | Focuses that window and closes the panel. |
| Pointer leaves the card | Nothing; previews stay until another tile expands or the panel closes. |
| Click outside the card | Closes. |

## Keyboard paths

| Key | Collapsed | Expanded |
| --- | --- | --- |
| ← → ↑ ↓ | Move the tile selection (stops at the edges; ↓ from a row with no tile directly below goes to the last tile). | Move the preview selection with the same rules over the preview rows; the first arrow selects the first preview. ← from the first column collapses. |
| Space | Expands the selected tile and selects its first preview. | Collapses. |
| Return | Focuses the selected app's most recent window. | Focuses the selected window, or the app's most recent one if none is selected. |
| Esc | Closes the panel. | Collapses. |

- The first tile is selected when the panel opens via the shortcut or URL; with the hot corner, nothing is selected
  until the pointer hovers a tile or an arrow key is pressed (the arrow then selects the first tile).
- Decision: → moves the selection rather than expanding, since a grid needs all four arrows. Space expands, as in
  Finder. Arrows follow visual direction.

## Focusing a window

0. Check the window still exists (its `AXRole` reads; for a window without an Accessibility element, its app is
   still running). If not, re-enumerate, keep the panel open and stop.
1. Set the app's `AXFrontmost` to true. Cooperative activation can refuse `NSRunningApplication.activate()` from a
   background app, while the Accessibility route does not.
2. `AXRaise` on the window and set its `AXMain` to true. Doing this after activation keeps the app from re-keying its
   previous main window. Windows without an Accessibility element stop after step 1.
3. Close the panel.

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

1. Toggle **Window switcher**: "Show the apps with windows on this Space and previews of their windows, from a hot
   corner or a shortcut." Turning it on while no corner is chosen preselects the corner macOS uses for Mission Control
   (`wvous-*-corner` = 2), if any.
2. **Hot corner** picker (Off, Top-Left, Top-Right, Bottom-Left, Bottom-Right) and the **Shortcut** row (the same
   recorder as the Shortcuts tab). Footer when both are unset: "Choose a hot corner or shortcut to open it."
3. When the switcher is on and the chosen corner also has a macOS hot corner: "macOS also uses this corner. Set it
   to - under Hot Corners, or both will open." with an **Open Desktop & Dock…** button. `com.apple.dock` is re-read
   each time Settings becomes active.
4. **Window previews**: Screen Recording status (Allowed / Allow…). Allowed: "Shows a live preview of each window."
   Not allowed: "Strongly recommended. Without Screen Recording access, windows show as title cards. After allowing
   it, quit and reopen Spaces."

The hot corner and shortcut rows are disabled while the toggle is off. Restore Defaults in the Shortcuts tab leaves
the switcher shortcut alone. The menu bar menu gets a **Window Switcher**
toggle next to the other two features.

## Out of scope

- Windows on other Spaces, minimized windows, hidden apps.
- Closing, minimizing or quitting from the panel.
- Type-to-select by app name (a cheap follow-up that fits the A to Z grid).
- Moving VoiceOver focus into the panel on open.
