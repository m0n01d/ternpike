/***
Typed bindings for Ink 5 (the React-for-the-terminal renderer) + its companion
input packages. Ink components are ordinary React components, bound with
`@module(...) @react.component external make`. No `%raw`, no `Obj.magic`,
no `%identity` — every value crosses the boundary through a typed `external`.
*/

// render: mount a React element as the root of an Ink app. (The real return is
// an Instance; widen to an opaque type with @send when programmatic
// unmount/waitUntilExit is needed.)
@module("ink")
external render: React.element => unit = "render"

// A Box dimension is a JS `number | string` (cells or a "%"). Modeled as an
// unboxed variant so both cross the boundary type-safely.
@unboxed
type dimension =
  | Cells(int)
  | Percent(string)

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
    ~flexGrow: int=?,
    ~gap: int=?,
    ~padding: int=?,
    ~paddingX: int=?,
    ~paddingY: int=?,
    ~marginTop: int=?,
    ~marginBottom: int=?,
    ~width: dimension=?,
    ~borderStyle: [#single | #double | #round | #bold | #classic]=?,
    ~borderColor: string=?,
    ~children: React.element=?,
  ) => React.element = "Box"
}

module Text = {
  // `color`/`backgroundColor` are chalk color names (kept as `string` so any
  // chalk color works).
  @module("ink") @react.component
  external make: (
    ~color: string=?,
    ~backgroundColor: string=?,
    ~bold: bool=?,
    ~dimColor: bool=?,
    ~italic: bool=?,
    ~underline: bool=?,
    ~wrap: [
      | #wrap
      | #truncate
      | #"truncate-start"
      | #"truncate-middle"
      | #"truncate-end"
    ]=?,
    ~children: React.element=?,
  ) => React.element = "Text"
}

// ink-text-input — single-line controlled input (default export).
module TextInput = {
  @module("ink-text-input") @react.component
  external make: (
    ~value: string,
    ~onChange: string => unit,
    ~onSubmit: string => unit=?,
    ~placeholder: string=?,
    ~focus: bool=?,
  ) => React.element = "default"
}

// ink-select-input — arrow-key list (default export). Item values cross the
// boundary as `string`; callers map back to their own type (see TierSelect).
module SelectInput = {
  type item = {label: string, value: string}

  @module("ink-select-input") @react.component
  external make: (
    ~items: array<item>,
    ~onSelect: item => unit,
    ~initialIndex: int=?,
  ) => React.element = "default"
}

// ink-spinner — animated spinner (default export). `type` is the spinner name.
module Spinner = {
  @module("ink-spinner") @react.component
  external make: (@as("type") ~type_: string=?) => React.element = "default"
}

// useInput((input, key) => unit) — keyboard handler. `input` is the raw
// character(s); `key` is the modifier/special-key record (the fields screens
// use; add more from Ink's set as needed).
type key = {
  escape: bool,
  return: bool,
  upArrow: bool,
  downArrow: bool,
  leftArrow: bool,
  rightArrow: bool,
  pageUp: bool,
  pageDown: bool,
  ctrl: bool,
  shift: bool,
  meta: bool,
  tab: bool,
  backspace: bool,
  delete: bool,
}

@module("ink")
external useInput: ((string, key) => unit) => unit = "useInput"

// useApp() -> { exit } — programmatic unmount (no-arg form).
type app = {exit: unit => unit}

@module("ink")
external useApp: unit => app = "useApp"
