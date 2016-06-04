package.loaded["atom"] = nil

local atom = require("atom")
local App, Dim, Label, Button, BorderBox = 
    atom.App, atom.Dim, atom.Label, atom.Button, atom.BorderBox


local app = App{
    padding = atom.Padding(1, 1, 1, 1)
}

app:add(Label{
    dim = Dim(3, 4),
    caption = "Label"
})

app:add(Button{
    dim = Dim(10, 4),
    caption = "Button"
})

do
    local b = Button{
        dim = Dim(22, 3, _, 3),
        caption = "Big Button"
    }
    
    b:bind("click", function ()
        print("WOW!")
    end)
    
    app:add(b)
end

app:add(BorderBox{
    dim = Dim(1, 1, 37, 7),
    title = "BorderBox"
})

app:run()
