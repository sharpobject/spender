local moves = require"moves"
local masks = require"move_masks"
local json = require"dkjson"
local bit = require"bit"
local lshift = bit.lshift
local band = bit.band
require"stridx"
local colors = "WBRGU*"
local function bin(mask)
  local ret = ""
  for i=0,27 do
    if band(mask, lshift(1, i)) ~= 0 then
      ret = ret .. "1"
    else
      ret = ret .. "_"
    end
  end
  return ret
end
local function format_move(move, mask)
  local ret = "hi"
  if move.type == "chip" or move.type == "reserve" then
    ret = "Take "
    for i=1,6 do
      for j=1,move[i] do
        ret = ret .. colors[i]
      end
    end
    if move.returns then
      ret = ret .. " Return "
      for i=1,6 do
        for j=-1,move[i],-1 do
          ret = ret .. colors[i]
        end
      end
    end
  elseif move.type == "buy" then
    ret = "Buy "..move.card
  end
  if move.type == "reserve" then
    local extra = " "..ret
    if extra == " Take " then extra = "" end
    if move.card then
      ret = "Reserve "..move.card .. extra
    else
      ret = "Reserve deck "..move.deck ..extra
    end
  end
  if ret == "Take " then ret = "Pass" end
  if mask then
    ret = ret.." "..bin(mask)
  end
  return ret
end
for i=1,1227 do
  print(i.." "..format_move(moves[i], masks[i]))
end