/***
Tiny `JSON.t` decode combinators. The stdlib gives us the `JSON.t` variant;
these make screen decoders terse. Everything returns `option` so callers default
with `Option.getOr`.
*/

let string = (json: JSON.t): option<string> =>
  switch json {
  | JSON.String(s) => Some(s)
  | _ => None
  }

let float = (json: JSON.t): option<float> =>
  switch json {
  | JSON.Number(n) => Some(n)
  | _ => None
  }

let int = (json: JSON.t): option<int> => float(json)->Option.map(Float.toInt)

let bool = (json: JSON.t): option<bool> =>
  switch json {
  | JSON.Boolean(b) => Some(b)
  | _ => None
  }

let array = (json: JSON.t): option<array<JSON.t>> =>
  switch json {
  | JSON.Array(a) => Some(a)
  | _ => None
  }

let field = (json: JSON.t, key: string): option<JSON.t> =>
  switch json {
  | JSON.Object(d) => Dict.get(d, key)
  | _ => None
  }

let stringField = (json: JSON.t, key: string): option<string> =>
  field(json, key)->Option.flatMap(string)

let intField = (json: JSON.t, key: string): option<int> =>
  field(json, key)->Option.flatMap(int)

let boolField = (json: JSON.t, key: string): option<bool> =>
  field(json, key)->Option.flatMap(bool)

let arrayField = (json: JSON.t, key: string): option<array<JSON.t>> =>
  field(json, key)->Option.flatMap(array)
