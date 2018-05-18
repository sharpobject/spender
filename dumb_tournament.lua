require"state"
local moves = require"moves"
local function comp(f, blorp, ...)
  if blorp == nil then return f end
  local dog = comp(blorp, ...)
  return function(...)
    return f(dog(...))
  end
end

-- Never Return Gold
local function nrg(ids, state)
  local ret = {}
  for i=1,#ids do
    local move = moves[ids[i]]
    if (not move[6]) or move[6] >= 0 then
      ret[#ret+1] = ids[i]
    end
  end
  return ret, state
end
-- Never reserve for 0 gold
local function nrzg(ids, state)
  local ret = {}
  for i=1,#ids do
    local move = moves[ids[i]]
    if move.type~="reserve" or move[6] == 1 then
      ret[#ret+1] = ids[i]
    end
  end
  return ret, state
end
-- Never take for 0,1 if you can buy
local function bntzo(ids, state)
  local can_buy = false
  local ret = {}
  for i=1,#ids do
    local move = moves[ids[i]]
    if move.type == "buy" then
      can_buy = true
    end
    if move.type ~= "chips" or move.sum > 1 then
      ret[#ret+1] = ids[i]
    end
  end
  if can_buy then
    return ret, state
  end
  return ids, state
end
-- Always buy
local function ab(ids, state)
  local ret = {}
  for i=1,#ids do
    local move = moves[ids[i]]
    if move.type=="buy" then
      ret[#ret+1] = ids[i]
    end
  end
  if #ret > 0 then
    return ret, state
  end
  return ids, state
end
local function score_move(id, state)
  if moves[id].type ~= "buy" then return 0 end
  -- TODO: be less dumb?
  local new_state = deepcpy(state)
  new_state:apply_move(id)
  return new_state.opp_score - state.score
end
-- Always get the most points
local function amp(ids, state)
  local best = 0
  local ret = {}
  for i=1,#ids do
    local score = score_move(ids[i], state)
    if score == best then
      ret[#ret+1] = ids[i]
    elseif score > best then
      best = score
      ret = {ids[i]}
    end
  end
  return ret
end
local policies = {
  Antoinette = comp(uniformly),
  Benedict   = comp(uniformly, ab),
  Cornelius  = comp(uniformly, bntzo),
  Dominique  = comp(uniformly, nrg),
  Emma       = comp(uniformly, nrg, ab),
  Francoise  = comp(uniformly, nrg, bntzo),
  Gwendolyn  = comp(uniformly, nrzg),
  Hildegaard = comp(uniformly, nrzg, ab),
  Iolanthe   = comp(uniformly, nrzg, bntzo),
  Jocelyn    = comp(uniformly, nrg, nrzg),
  Katherine  = comp(uniformly, nrg, nrzg, ab),
  Lynnette   = comp(uniformly, nrg, nrzg, bntzo),
  Melisandra = comp(uniformly, amp),
  Natalya    = comp(uniformly, amp, ab),
  Ophelia    = comp(uniformly, amp, bntzo),
  Philippine = comp(uniformly, amp, nrg),
  Quentin    = comp(uniformly, amp, nrg, ab),
  Raphael    = comp(uniformly, amp, nrg, bntzo),
  Scarlett   = comp(uniformly, amp, nrzg),
  Tuesday    = comp(uniformly, amp, nrzg, ab),
  Umeko      = comp(uniformly, amp, nrzg, bntzo),
  Valentine  = comp(uniformly, amp, nrg, nrzg),
  Winnifred  = comp(uniformly, amp, nrg, nrzg, ab),
  Xavier     = comp(uniformly, amp, nrg, nrzg, bntzo),
}

local scores = {}
local times = {}
for a,_ in pairs(policies) do
  scores[a] = {}
  times[a] = {}
  for b,_ in pairs(policies) do
    scores[a][b] = 0
    times[a][b] = {0, 0}
  end
end


local function play_game(a, b)
  local state = GameState()
  local i=0
  print(a.." vs. "..b)
  while not state.result do
    i = i + 1
    local legalmoves = set_to_arr(state:list_moves())
    table.sort(legalmoves)
    local move = policies[a](legalmoves, state)
    state:apply_move(move, false)
    local legalmoves = set_to_arr(state:list_moves())
    table.sort(legalmoves)
    local move = policies[b](legalmoves, state)
    state:apply_move(move, false)
    if i==400 then print("stalemate :(") return end
  end
  times[a][b][1] = times[a][b][1] + state.turn
  times[a][b][2] = times[a][b][2] + 1
  if state.result == 1 then
    print(a.." wins!")
    scores[a][b] = scores[a][b] + 1
  elseif state.result == -1 then
    print(b.." wins!")
    scores[b][a] = scores[b][a] + 1
  elseif state.result == 0 then
    print("draw")
    scores[a][b] = scores[a][b] + .5
    scores[b][a] = scores[b][a] + .5
  else
    error("what lol")
  end
end

for i=1,100 do
  for a,_ in pairs(policies) do
    play_game(a, "Antoinette")
    --play_game("Antoinette", a)
    --play_game(a,a)
  end
  print(json.encode(scores))
end
for k,v in pairs(times) do
  for kk, vv in pairs(v) do
    v[kk] = vv[1] / vv[2]
    if v[kk] ~= v[kk] then
      v[kk] = nil
    else
      print(vv[1], vv[2], v[kk])
    end
  end
end
print(json.encode(times))
if true then return end

math.randomseed(5)
for qq=1,1000 do
  print("starting a new game!")
  local state = GameState()
  --print(json.encode(state:pretty()))
  local legalmoves = set_to_arr(state:list_moves())
  table.sort(legalmoves)
  --print(json.encode(legalmoves))
  for _,move in ipairs(legalmoves) do
  --  print(json.encode(moves[move]))
  end
  local i = 0
  while not state.result do
    i = i + 1
    local legalmoves = set_to_arr(state:list_moves())
    table.sort(legalmoves)
    local move = uniformly(legalmoves)
    state:apply_move(move, true)
    print(i, move, state.score, state.opp_score, json.encode(state.my_chips), json.encode(state.opp_chips), state.my_n_chips, state.opp_n_chips)
    if i==400 then break end
  end
end
-- 1-90: is card community card?
-- 91-180: is card in deck?
-- 181-270: is card reserved by me?
-- 271-360: is card reserved by opponent?
-- 361-370: is noble available?
-- 371-396:--]]
