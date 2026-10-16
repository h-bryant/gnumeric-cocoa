# Release notes

The text of each GitHub release
(<https://github.com/h-bryant/gnumeric-cocoa/releases>), newest first.
Each release carries `GnumericCocoa-<version>.zip`: the relocatable bundle
from `scripts/bundle.sh`, zipped with `ditto -c -k --norsrc --keepParent`.
The tag `v<version>` marks the commit the bundle was built from.

## 0.2.1 (2026-10-16)

Fixes from the first use of 0.2.0:

- The grid's scroll bars are always visible, with a grey track. The
  system's overlay scrollers showed only while scrolling and blended into
  white cells.
- A sheet opens where it was left. The selected cell, the focused sheet,
  and the scroll position are saved with the file and restored on open,
  and a sheet comes back to its place when you switch tabs.
- A right-click on a cell, a column header, or a row header shows
  Gnumeric's context menu: Cut, Copy, Paste, and Paste Special; Insert and
  Delete Cells; Insert Rows Above, Insert Columns to the Left, Delete Rows,
  and Delete Columns; Clear Contents; the comment and hyperlink items;
  Format Cells and Conditional Formatting; and the Cell, Column, and Row
  submenus (merge, auto fit, width and height, hide and unhide). The
  header menus' Insert and Delete items are no longer greyed out.
- While typing a formula, a click on the grid inserts the cell's reference
  and a drag inserts a range.
- Version 0.2.1, build 3, so a double-clicked file opens in this copy
  rather than in an older build left on the machine.

Unsigned; see README for first launch. macOS 15 or later, Apple silicon.

SHA-256 of `GnumericCocoa-0.2.1.zip`:
`1d4b7f590aa3db4c9baca25f8eb566d0512dfe72d14df59a99284d7f09154987`

## 0.2.0 (2026-10-13)

Unsigned; see README for first launch.
