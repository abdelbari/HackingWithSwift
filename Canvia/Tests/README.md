# Tests

`GeometryTests.swift` covers the transform math and the store's undo /
grouping / distribute / clipboard semantics — the same assertions that cover
the JavaScript sibling implementation in the `story` repo (where all 73 pass).

These files sit **outside** `Canvia/Canvia/`, which is a synchronized folder
that Xcode compiles wholesale into the app target — keeping them here means
they never affect the app build.

To run them:

1. **File ▸ New ▸ Target… ▸ Unit Testing Bundle**, name it `CanviaTests`.
2. Drag `GeometryTests.swift` into that target.
3. **⌘U**.
