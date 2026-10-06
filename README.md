# Spaces

A menu bar app for instant Space switching and window snapping on macOS 27.

- **⌃← / ⌃→** switch Spaces without the slide animation, with a glass pill
  showing which Desktop you landed on.
- **⌃⌥← / ⌃⌥→** put the window on the left or right half. Press again to
  cycle through ½, ⅔ and ⅓ of the screen.
- **⌃⌥↩** maximizes the window. Press it again to restore the previous size.
- **Thirds**: first, center and last third, and first or last two thirds.
  These have no shortcut until you set one.
- **⌃⌥⌘C** opens Control Center (press it again to close).
- **Snap areas**: drag a window to a screen edge or corner and a translucent
  preview shows where it will land. Each edge and corner's action is set in
  Settings. Drag a snapped window away and it returns to its earlier size.

All shortcuts can be changed in Settings → Shortcuts. Space switching and
window snapping can each be turned off in Settings or the menu bar menu.

```sh
brew install --cask gustaferiksson/tap/spaces
```

Then:

1. Allow Spaces in System Settings → Privacy & Security → Accessibility.
2. Untick **Move left a space** and **Move right a space** in System Settings →
   Keyboard → Keyboard Shortcuts → Mission Control, so macOS doesn't take
   ⌃←/→ first.
3. If you use snap areas, turn off **Drag windows to screen edges to tile** in
   System Settings → Desktop & Dock, so macOS doesn't tile the same drag.

Spaces updates itself from GitHub Releases.

## Moving from the `spaces` command-line tool

```sh
brew services stop spaces
brew uninstall --formula spaces
```

Then remove the old `spaces` entry from the Accessibility list and allow
Spaces.app instead. The grant doesn't carry over.

## URL scheme

Every shortcut action can also be triggered with a URL, for example from a
mouse button:

```sh
open -g spaces://left-half
```

Actions: `previous-space`, `next-space`, `control-center`, `left-half`,
`right-half`, `maximize`, `first-third`, `center-third`, `last-third`,
`first-two-thirds`, `last-two-thirds`.

## How it works

Space switching posts a synthetic Dock swipe, the same kind of event a
three-finger trackpad swipe produces, with almost no travel and a high release
velocity. The Dock commits the switch with nothing left to animate. macOS 27
also checks that the swipe carries a serialized trackpad (IOHID) record, so one
is attached. The approach follows [noswoosh](https://github.com/mmathys/noswoosh),
which documents it in depth. It relies on undocumented event fields and a
private SkyLight call (to know which Space you're on), so a macOS update can
break it.

Windows are moved through the Accessibility API. Switching stops at the first
and last Space instead of bouncing, and with several displays it follows the
display under the pointer.

Requires macOS 27 on Apple silicon.

## Building

```sh
./build.sh                                        # dist/Spaces.app
swift test --package-path Packages/SpacesCore     # tests
```

Releases: [`docs/RELEASING.md`](docs/RELEASING.md).
