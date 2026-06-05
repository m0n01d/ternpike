/***
App frame, ported from Layout.tsx: header (title + apiUrl + status/error), a
left section rail, the screen body, and a hints footer. `section` is the active
section key (see App's `sectionKey`).
*/

let sections = [
  ("users", "Users"),
  ("dbs", "Databases"),
  ("sharedtrips", "SharedTrips"),
  ("seed", "Seed"),
  ("notifications", "Notifications"),
  ("qr", "QR stickers"),
]

@react.component
let make = (
  ~section: string,
  ~hints: string,
  ~status: string,
  ~error: option<string>,
  ~children: React.element,
) =>
  <Ink.Box flexDirection=#column width=Percent("100%")>
    <Ink.Box
      borderStyle=#round borderColor="cyan" paddingX=1 justifyContent=#"space-between">
      <Ink.Text>
        <Ink.Text color="cyan" bold=true> {React.string("ternpike-admin")} </Ink.Text>
        {React.string(" · " ++ Config.apiUrl)}
      </Ink.Text>
      <Ink.Text color={Option.isSome(error) ? "red" : "green"}>
        {React.string(
          switch error {
          | Some(e) => "error: " ++ e
          | None => status
          },
        )}
      </Ink.Text>
    </Ink.Box>
    <Ink.Box>
      <Ink.Box
        flexDirection=#column
        borderStyle=#single
        borderColor="gray"
        paddingX=1
        width=Cells(16)>
        {sections
        ->Array.map(((key, label)) => {
          let active = key === section
          <Ink.Text key color={active ? "cyan" : "white"}>
            {React.string((active ? "› " : "  ") ++ label)}
          </Ink.Text>
        })
        ->React.array}
      </Ink.Box>
      <Ink.Box flexGrow=1 flexDirection=#column paddingX=1> children </Ink.Box>
    </Ink.Box>
    <Ink.Box borderStyle=#single borderColor="gray" paddingX=1>
      <Ink.Text color="gray"> {React.string(hints)} </Ink.Text>
    </Ink.Box>
  </Ink.Box>
