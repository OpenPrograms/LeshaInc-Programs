local component = require("component")
local computer = require("computer")
local class = require("30log")
local event = require("event")

local gpu = component.gpu

------------------------------------------------------------

local EventDispatcher = class "EventDispatcher" do
  function EventDispatcher:init()
    self.handlers = {}
  end
  
  function EventDispatcher:dispatch(event, ...)
    checkArg(1, event, "string")
    if not self.handlers[event] then return end
    
    for _, handler in ipairs(self.handlers[event]) do
      handler(...)
    end
  end
  
  function EventDispatcher:bind(event, handler)
    checkArg(1, event, "string")
    checkArg(2, handler, "function")
    
    if not self.handlers[event] then
      self.handlers[event] = {}
    end
    
    table.insert(self.handlers[event], handler)
  end
  
  function EventDispatcher:unbind(event, handler)
    checkArg(1, event, "string")
    
    if handler then
      if not self.handlers[event] then return end
      
      for i, in_handler in ipairs(self.handlers[event]) do
        if in_handler == handler then
          table.remove(self.handlers[event], i)
        end
      end
    else
      self.handlers[event] = nil
    end
  end
end


local Dim = class "Dim" do
  function Dim:init(x, y, w, h)
    self.x = x or 1
    self.y = y or 1
    self.w = w or 1
    self.h = h or 1
  end
  
  function Dim:pointCollision(x, y)
    return x >= self.x and 
           y >= self.y and
           x < self.x + self.w and
           y < self.y + self.h
  end
end


local Padding = class "Padding" do
  function Padding:init(top, right, bottom, left)
    self.top    = top or 0
    self.right  = right or 0
    self.bottom = bottom or 0
    self.left   = left or 0
  end
end


local Margin = Padding:extend "Margin"


local boxChars = {
  single = {
    hl = "─",
    vl = "│",
    
    tl = "┌",
    tr = "┐",
    bl = "└",
    br = "┘"
  },
  double = {
    hl = "═",
    vl = "║",
    
    tl = "╔",
    tr = "╗",
    bl = "╚",
    br = "╝"
  }
}

local function drawBox(br, dim)
  if br == 0 then
    gpu.fill(dim.x, dim.y, dim.w, 1, " ")
    gpu.fill(dim.x, dim.y, 1, dim.h, " ")
    gpu.fill(dim.x, dim.y + dim.h - 1, dim.w, 1, " ")
    gpu.fill(dim.x + dim.w - 1, dim.y, 1, dim.h, " ")
  else
    local ns = br == 2 and "double" or "single"
    
    gpu.fill(dim.x, dim.y, dim.w, 1, boxChars[ns].hl)
    gpu.fill(dim.x, dim.y, 1, dim.h, boxChars[ns].vl)
    gpu.fill(dim.x, dim.y + dim.h - 1, dim.w, 1, boxChars[ns].hl)
    gpu.fill(dim.x + dim.w - 1, dim.y, 1, dim.h, boxChars[ns].vl)
    
    gpu.set(dim.x, dim.y, boxChars[ns].tl)
    gpu.set(dim.x + dim.w - 1, dim.y, boxChars[ns].tr)
    gpu.set(dim.x, dim.y + dim.h - 1, boxChars[ns].bl)
    gpu.set(dim.x + dim.w - 1, dim.y + dim.h - 1, boxChars[ns].br)
  end
end


local Widget = EventDispatcher:extend "Widget" do
  function Widget:init(options)
    options = type(options) == "table" and options or {}
    EventDispatcher.init(self)
    
    self.dim = options.dim or Dim()
    self.zIndex = options.zIndex or 1
  end
end


local Label = Widget:extend "Label" do
  function Label:init(options)
    options = type(options) == "table" and options or {}
    Widget.init(self, options)
    
    self.dim.h = 1
    self.dim.w = self.dim.w > #options.caption and self.dim.w 
                 or #options.caption
    
    self.caption = options.caption or ""
    self.foreground = options.foreground or 0xFFFFFF
  end
  
  function Label:draw(dim)
    gpu.setBackground(({gpu.get(dim.x, dim.y)})[3])
    gpu.setForeground(self.foreground)
    
    gpu.set(dim.x, dim.y, self.caption)
  end
end


local BorderBox = Widget:extend "BorderBox" do
  function BorderBox:init(options)
    options = type(options) == "table" and options or {}
    Widget.init(self, options)
    
    self.title = options.title or ""
    self.foreground = options.foreground or 0xFFFFFF
    self.titleForeground = options.titleForeground or 0xFFFFFF
    
    self.borderType = options.borderType or "single"
  end
  
  function BorderBox:draw(dim)
    gpu.setBackground(({gpu.get(dim.x, dim.y)})[3])
    gpu.setForeground(self.foreground)
    
    drawBox(self.borderType == "single" and 1 or 2, dim)
    
    gpu.setForeground(self.titleForeground)
    gpu.set(dim.x + 2, dim.y, self.title)
  end
end


local Button = Widget:extend "Button" do
  function Button:init(options)
    options = type(options) == "table" and options or {}
    Widget.init(self, options)
    
    self.dim.h = self.dim.h > 0 and self.dim.h or 1
    self.dim.w = self.dim.w > #options.caption + 4 and self.dim.w 
                 or #options.caption + 4
    
    self.caption = options.caption or ""
    self.background = options.background or 0x3465a4
    self.foreground = options.foreground or 0xffffff
    self.activeBackground = options.activeBackground or 0x7093bf
    self.activeForeground = options.activeForeground or 0xffffff
    
    self:bind("signal:touch", function (_, addr, x, y, nick)
      if self.cdim:pointCollision(x, y) then
        self:dispatch("click", self, addr, x, y, nick)
        self:draw(self.cdim, true)
        os.sleep(0.5)
        self:draw(self.cdim)
      end
    end)
  end
  
  function Button:draw(dim, clicked)
    self.cdim = dim
    
    if clicked then
      gpu.setBackground(self.activeBackground)
      gpu.setForeground(self.activeForeground)
    else
      gpu.setBackground(self.background)
      gpu.setForeground(self.foreground)
    end
    
    local capX, capY = math.ceil(dim.w / 2 - #self.caption / 2), 
                       math.ceil(dim.h / 2)
    
    gpu.fill(dim.x, dim.y, dim.w, dim.h, " ")
    
    if dim.h == 1 then
      gpu.set(dim.x, dim.y, "[")
      gpu.set(dim.x + dim.w - 1, dim.y, "]")
    else
      gpu.fill(dim.x, dim.y, 1, dim.h, boxChars.single.vl)
      gpu.fill(dim.x + dim.w - 1, dim.y, 1, dim.h, boxChars.single.vl)
      
      gpu.set(dim.x, dim.y, boxChars.single.tl)
      gpu.set(dim.x + dim.w - 1, dim.y, boxChars.single.tr)
      gpu.set(dim.x, dim.y + dim.h - 1, boxChars.single.bl)
      gpu.set(dim.x + dim.w - 1, dim.y + dim.h - 1, boxChars.single.br)
    end
    
    gpu.set(dim.x + capX, dim.y + capY - 1, self.caption)
  end
end


local App = EventDispatcher:extend "App" do
  function App:init(options)
    options = type(options) == "table" and options or {}
    EventDispatcher.init(self)
    
    local scrW, scrH = gpu.getResolution()
    
    self.running = false
    self.dim = options.dim or Dim(1, 1, scrW, scrH)
    self.background = options.background or 0x302f30
    self.padding = options.padding or Padding()
    
    self.widgets = {}
    
    self:bind("signal", function (name, ...)
      for _, widget in ipairs(self.widgets) do
        widget:dispatch("signal", widget, name, ...)
        widget:dispatch("signal:".. tostring(name), widget, ...)
      end
    end)
  end
  
  function App:stop()
    self.running = false
    event.push("app_stopped")
  end
  
  function App:add(widget)
    checkArg(1, widget, "table")
    
    table.insert(self.widgets, widget)
    widget:dispatch("appended", widget, self)
  end
  
  function App:draw()
    gpu.setBackground(self.background)
    gpu.fill(self.dim.x, self.dim.y, self.dim.w, self.dim.h, " ")
    
    local elevations = {{}}
    local currentElevation = 1
    
    for _, widget in ipairs(self.widgets) do
      if (widget.zIndex or 1) > currentElevation then
        currentElevation = currentElevation + 1
        elevations[currentElevation] = {}
      end
      
      table.insert(elevations[currentElevation], widget)
    end
    
    local maxDim = self.dim
    maxDim.x = maxDim.x + self.padding.left
    maxDim.y = maxDim.y + self.padding.top
    maxDim.w = maxDim.w - self.padding.left - self.padding.right
    maxDim.h = maxDim.h - self.padding.top - self.padding.bottom
    
    for _, elevationGroup in ipairs(elevations) do
      for _, widget in ipairs(elevationGroup) do
        if widget.draw then
          local widgetDim = Dim(
            widget.dim.x + self.padding.left, 
            widget.dim.y + self.padding.top,
            widget.dim.w,
            widget.dim.h
          )
          
          if maxDim:pointCollision(widgetDim.x, widgetDim.y) and
             maxDim:pointCollision(widgetDim.x + widgetDim.w - 1, 
                                   widgetDim.y + widgetDim.h - 1) then
          
            widget:draw(widgetDim)
          end
        end
      end
    end
  end
  
  function App:run()
    self.running = true
    
    self:draw()
    
    while self.running do
      local e = {event.pull()}
      
      if e[1] then
        self:dispatch("signal", table.unpack(e))
        self:dispatch("signal:" .. tostring(e[1]), table.unpack(e, 2))
      end
    end
  end
end


------------------------------------------------------------

return {
  EventDispatcher = EventDispatcher,
  Dim = Dim,
  Padding = Padding,
  Margin = Margin,
  boxChars = boxChars,
  drawBox = drawBox,
  App = App,
  
  Label = Label,
  BorderBox = BorderBox,
  Button = Button
}
