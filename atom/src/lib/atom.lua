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
      handler(event, ...)
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

local App = EventDispatcher:extend "App" do
  function App:init()
    EventDispatcher:init(self)
    
    self.running = false
  end
  
  function App:stop()
    self.running = false
    event.push("app_stopped")
  end
  
  function App:draw()
    
  end
  
  function App:run()
    self.running = true
    
    self:draw()
    
    while self.running do
      local e = {event.pull()}
      
      if e[1] then
        self.dispatch("signal", table.unpack(e))
        self.dispatch("signal:" .. tostring(e[1]), table.unpack(e, 2))
      end
    end
  end
end


------------------------------------------------------------

return {
  EventDispatcher = EventDispatcher,
  App = App
}
