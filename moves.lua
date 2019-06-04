require("util")
local json = require"dkjson"

local function permutations(arr, idx, ret)
  ret = ret or {}
  idx = idx or 1
  if idx == #arr then
    local arr_cpy = {}
    for i=1,#arr do
      arr_cpy[i] = arr[i]
    end
    ret[#ret+1] = arr_cpy
    return
  end
  for i=idx, #arr do
    arr[i], arr[idx] = arr[idx], arr[i]
    permutations(arr, idx+1, ret)
    arr[i], arr[idx] = arr[idx], arr[i]
  end
  return ret
end

local function uniq_permutations(arr)
  local ret = {}
  local perms = permutations(arr)
  for i=1,#perms do
    local ok = true
    for j=1,#ret do
      if deepeq(ret[j], perms[i]) then
        ok = false
        break
      end
    end
    if ok then
      ret[#ret+1] = perms[i]
    end
  end
  return ret
end

local function zero_wild(arr) return arr[6] <= 0 end

local move_types = {
  {1,1,1,0,0,0},
  {1,1,0,0,0,0},
  {2,0,0,0,0,0},
  {1,0,0,0,0,0},
  {0,0,0,0,0,0},
  {-1,0,0,0,0,0},
}

local ret = {}
for i=1,#move_types do
  local moves = filter(zero_wild, uniq_permutations(move_types[i]))
  for j=1,#moves do
    ret[#ret+1] = moves[j]
    --print(#ret, json.encode(moves[j]), reduce(function(a,b)return a+b end, moves[j]))
  end
end


for i=1,#ret do
  local move = ret[i]
  move.sum = 0
  for j=1,6 do
    move.sum = move.sum + move[j]
  end
  move.type = "chip"
end

for i=1,93 do
  local move = {}
  move.type = "reserve"
  local idx = #ret+1
  if i <= 90 then
    move.card = i
  else
    move.deck = i-90
  end
  ret[idx] = move
  --print(json.encode(move))
end

for i=1,90 do
  ret[#ret+1] = {type="buy", card=i}
end

table.sort(ret, function(a,b)
  if a.type == "chip" and b.type ~= "chip" then return true end
  if a.type ~= "chip" and b.type == "chip" then return false end
  if a.card and not b.card then return true end
  if b.card and not a.card then return false end
  if a.card ~= b.card then
    return a.card < b.card
  end
  if a.type == "buy" and b.type ~= "buy" then return true end
  if a.type ~= "buy" and b.type == "buy" then return false end
  if a.deck ~= b.deck then
    return a.deck < b.deck
  end
  if a.sum ~= b.sum then return a.sum > b.sum end
  local aps, bps = 0,0
  for i=1,6 do
    if a[i] and a[i] > 0 then aps = aps + a[i] end
    if b[i] and b[i] > 0 then bps = bps + b[i] end
  end
  if aps ~= bps then return aps > bps end
  for i=1,6 do
    if a[i] ~= b[i] and (a[i] > 1 or b[i] > 1) then
      return a[i] > b[i]
    end
  end
  for i=1,6 do
    if a[i] ~= b[i] and (a[i] > 0 or b[i] > 0) then
      return a[i] > b[i]
    end
  end
  for i=1,6 do
    if a[i] ~= b[i] then
      return a[i] < b[i]
    end
  end
end)

for i=1,#ret do
  print(i, json.encode(ret[i]))
end

return ret