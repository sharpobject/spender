return function (init)
  local c,mt = {},{}
  c.__index = c
  mt.__call = function(_, ...)
    local obj = {}
    setmetatable(obj,c)
    init(obj,...)
    return obj
  end
  setmetatable(c, mt)
  return c
end
