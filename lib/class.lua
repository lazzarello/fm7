function class(base, init)
  local c = {}
  if not init and type(base) == 'function' then
    init = base
    base = nil
  elseif type(base) == 'table' then
    for i,v in pairs(base) do
      c[i] = v
    end
    c._base = base
  end
  c.__index = c
  
  local mt = {}
  -- the ... syntax is like * in ruby. A variable number of arguments to a function.
  mt.__call = function(class_tbl, ...)
    local obj = {}
    setmetatable(obj,c)
    if init then
      init(obj,...)
    else
      if base and base.init then
        base.init(obj,...)
      end
    end
    return obj
  end
  c.init = init
  c.is_a = function(self, klass)
    local m = getmetatable(self)
    while m do
      if m == klass then return true end
      m = m._base
    end
    return false
  end
  setmetatable(c,mt)
  return c
end
