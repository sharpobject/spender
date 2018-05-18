require"stridx"
local bit = require"bit"
local lshift = bit.lshift
local band = bit.band
local byte = string.byte
local setmetatable = setmetatable

local mt = {
  __index = function(self, idx)
    local remainder = (idx - 1) % 8
    local cidx = (idx - remainder - 1) / 8 + 1
    return band(byte(self.s[cidx]), lshift(1, remainder)) ~= 0 and 1 or 0
  end,
  __len = function(self)
    return self.n
  end,
}

return function(s)
  return setmetatable({s=s, n=#s*8}, mt)
end