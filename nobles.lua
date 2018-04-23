--local json = require"dkjson"
require("stridx")
local s = "WBRGUWBRGU"
ret = {}
for i=1,5 do
  ret[#ret+1] = {[s[i]] = 4, [s[i+1]] = 4}
  --print(json.encode(ret[#ret]))
end
for i=1,5 do
  ret[#ret+1] = {[s[i]] = 3, [s[i+1]] = 3, [s[i+2]] = 3}
  --print(json.encode(ret[#ret]))
end
return ret
