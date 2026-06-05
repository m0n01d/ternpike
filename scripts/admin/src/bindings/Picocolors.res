/***
Typed binding for picocolors' default export — the subset of color functions
the admin CLI uses. Each is `string => string`. No `%raw`, no escape hatches.
*/

type t = {
  bgGreen: string => string,
  bgYellow: string => string,
  black: string => string,
  gray: string => string,
  green: string => string,
  inverse: string => string,
  yellow: string => string,
}

@module("picocolors") external colors: t = "default"
