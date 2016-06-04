package.loaded["atom"] = nil

local atom = require("atom")
local app = atom.App()

app:add(atom.Toolbar{
    dim = atom.Dim(1, 1, 80, 1),
    title = "GLaDOS Atom Demo"
})

app:add(atom.Label{
    dim = atom.Dim(2, 3),
    caption = "Hello, world!"
})

app:run()
