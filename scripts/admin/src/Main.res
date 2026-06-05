/***
Entry point. Mounts the TEA hello-world into an Ink app. The next rungs of the
admin-TUI rewrite will swap <HelloTea /> for the real root component (router /
screen switcher) but keep this `Ink.render(...)` shape.
*/

Ink.render(<HelloTea />)
