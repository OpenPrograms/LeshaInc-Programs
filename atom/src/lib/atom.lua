local class = require("class")

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
    checkArg(1, event, "string"
    
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

------------------------------------------------------------

return {
  EventDispatcher = EventDispatcher
}
