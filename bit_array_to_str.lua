local char = string.char
local concat = table.concat
return function(t)
  local ret = {}
  local idx = 1
  for i=1,#t,8 do
    ret[idx] = char(
      (t[i]   == 1 and   1 or 0) +
      (t[i+1] == 1 and   2 or 0) +
      (t[i+2] == 1 and   4 or 0) +
      (t[i+3] == 1 and   8 or 0) +
      (t[i+4] == 1 and  16 or 0) +
      (t[i+5] == 1 and  32 or 0) +
      (t[i+6] == 1 and  64 or 0) +
      (t[i+7] == 1 and 128 or 0))
    idx = idx + 1
  end
  return concat(ret)
end