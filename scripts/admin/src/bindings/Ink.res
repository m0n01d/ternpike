/***
Minimal, typed bindings for Ink 5 (https://github.com/vadimdemedes/ink) — the
React-for-the-terminal renderer. Only what the TEA hello-world needs is bound
here; everything the full admin-TUI rewrite will eventually want is listed in
the "NOT YET BOUND" note at the bottom so the next rung knows the surface area.

No `%raw`, no `Obj.magic`, no `%identity` — every value crosses the JS boundary
through a typed `external`. Ink components are ordinary React components, so they
bind with `@module("ink") @react.component external make`.
*/

// ---------------------------------------------------------------------------
// render: mount a React element as the root of an Ink app.
//
// Ink's real signature returns an `Instance` (rerender/unmount/waitUntilExit).
// hello-world never touches it, so we bind the return as `unit`. When the full
// rewrite needs programmatic unmount/waitUntilExit, widen this to an opaque
// `instance` type with @send bindings rather than changing call sites.
// ---------------------------------------------------------------------------
@module("ink")
external render: React.element => unit = "render"

// ---------------------------------------------------------------------------
// <Box> — the flexbox layout primitive. Props are all optional; bind the subset
// hello-world uses. Ink accepts many more (margin/padding/border/width/height/…);
// add them as labelled optional args here when a screen needs them.
// ---------------------------------------------------------------------------
module Box = {
  @module("ink") @react.component
  external make: (
    ~flexDirection: [#row | #column]=?,
    ~alignItems: [#"flex-start" | #center | #"flex-end" | #stretch]=?,
    ~justifyContent: [
      | #"flex-start"
      | #center
      | #"flex-end"
      | #"space-between"
      | #"space-around"
    ]=?,
    ~gap: int=?,
    ~padding: int=?,
    ~paddingX: int=?,
    ~paddingY: int=?,
    ~borderStyle: [#single | #double | #round | #bold | #classic]=?,
    ~children: React.element=?,
  ) => React.element = "Box"
}

// ---------------------------------------------------------------------------
// <Text> — terminal text node. `color`/`backgroundColor` are chalk color names
// (kept as `string` rather than a closed variant so any chalk color works).
// ---------------------------------------------------------------------------
module Text = {
  @module("ink") @react.component
  external make: (
    ~color: string=?,
    ~backgroundColor: string=?,
    ~bold: bool=?,
    ~dimColor: bool=?,
    ~italic: bool=?,
    ~underline: bool=?,
    ~children: React.element=?,
  ) => React.element = "Text"
}

// ---------------------------------------------------------------------------
// useInput((input, key) => unit) — keyboard handler hook. `input` is the raw
// character(s); `key` is the modifier/special-key record. Only the fields
// hello-world reads are bound; the real record has ~20 fields (arrows, ctrl,
// meta, tab, backspace, delete, pageUp/Down, …) — add them as needed.
// ---------------------------------------------------------------------------
type key = {
  escape: bool,
  return: bool,
  upArrow: bool,
  downArrow: bool,
  leftArrow: bool,
  rightArrow: bool,
  ctrl: bool,
  shift: bool,
  tab: bool,
}

@module("ink")
external useInput: ((string, key) => unit) => unit = "useInput"

// ---------------------------------------------------------------------------
// useApp() -> { exit } — programmatic unmount. `exit` optionally takes an Error;
// we bind the no-arg form the quit path uses.
// ---------------------------------------------------------------------------
type app = {exit: unit => unit}

@module("ink")
external useApp: unit => app = "useApp"

// NOT YET BOUND (the full admin TUI will want these — bind on first use, same
// no-escape-hatch rules):
//
//   Components:  Spacer, Newline, Static, Transform.
//   Companion packages: ink-text-input (TextInput), ink-select-input
//     (SelectInput, props items + onSelect), ink-spinner (Spinner, prop type).
//   Hooks: useStdin, useStdout, useStderr, useFocus, useFocusManager.
//   render's real return is an Instance (rerender, unmount, waitUntilExit —
//     waitUntilExit returns a JS Promise of unit).
//   Box: the rest of the flexbox props (width, height, min*, margin*,
//     borderColor, flexGrow, flexShrink, flexBasis).
//   key: the remaining special keys (meta, tab already bound, backspace,
//     delete, pageUp, pageDown, home, end).
