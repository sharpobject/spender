require("util")
require("stridx")
json = require"dkjson"

-- WBRGU
local data = {
  ["1021"] = {"RGUWB", "BRGUW"},
  ["103"] = {"UGWRB"},
  ["101111"] = {"BRGUW", "RGUWB", "GUWBR", "UWBRG"},
  ["1022"] = {"BWRUG", "UGWRB"},
  ["102111"] = {"GUWBR", "BRGUW", "RGUWB", "UWBRG"},
  ["10221"] = {"GUWBR", "UWBRG", "BRGUW"},
  ["10311"] = {"WRBUG", "UBWGR", "BGRWU"},
  ["114"] = {"GUWBR"},
  ["21322"] = {"GWBUR", "RUWBG", "BGRWU"},
  ["21332"] = {"RGUWB", "UWBRG", "WBRGU"},
  ["22421"] = {"RGUWB", "BRGUW", "GUWBR"},
  ["2253"] = {"RGBUW", "BRWGU"},
  ["225"] = {"RWBGU"},
  ["236"] = {"WBRGU"},
  ["335333"] = {"RGUWB", "BRGUW", "GUWBR", "UWBRG"},
  ["347"] = {"BRGUW"},
  ["34633"] = {"BRGUW", "WBRGU", "RGUWB"},
  ["3573"] = {"BRGUW", "WBRGU"},
}

local letter_to_number = {
  "W","B","R","G","U",
  W=1,
  B=2,
  R=3,
  G=4,
  U=5,
}

local holdings = {}
for k,v in spairs(data) do
  local deck = tonumber(k[1])
  local points = tonumber(k[2])
  local costs = k:sub(3)
  for i=1,5 do
    local holding = {0,0,0,0,0}
    holding.deck = deck
    holding.points = points
    holding.bonus = i
    for j=1,#costs do
      holding[letter_to_number[v[j][i]]] = tonumber(costs[j])
    end
    holdings[#holdings+1] = holding
    --print(json.encode(holding))
  end
end

sort_colors = {B=1,U=2,G=3,R=4,W=5}
color_names = {"white", "black", "red", "green", "blue"}

table.sort(holdings, function(a, b)
  local dog = sort_colors[letter_to_number[a.bonus]] - sort_colors[letter_to_number[b.bonus]]
  if dog ~= 0 then
    return dog < 0
  end
  dog = a.deck - b.deck
  if dog ~= 0 then
    return dog < 0
  end
  dog = a.points - b.points
  return dog < 0
end)

for k,holding in ipairs(holdings) do
  print(holding.deck..","..
        color_names[holding.bonus]..","..
        holding.points..","..
        (holding[2]~=0 and holding[2] or "")..","..
        (holding[1]~=0 and holding[1] or "")..","..
        (holding[3]~=0 and holding[3] or "")..","..
        (holding[5]~=0 and holding[5] or "")..","..
        (holding[4]~=0 and holding[4] or ""))
end

return holdings
