local class = require("class")
local json = require("dkjson")
local holdings = require("holdings")
local nobles = require("nobles")
local moves = require("moves")
local decks = {}
local deck_offsets = {0,40,70,0}
for i=1,4 do
  local n = 50 - i * 10
  decks[i] = {[0]=n}
  for j=1,n do
    decks[i][j] = j + deck_offsets[i]
  end
  --print(json.encode(decks[i]))
end

GameState = class(function(self, tensor)
  self.community_cards = {}
  self.deck_cards = {}
  self.my_reserved = {}
  self.opp_reserved = {}
  self.nobles = {}
  self.bank = {4,4,4,4,4,5}
  self.my_chips = {0,0,0,0,0,0}
  self.opp_chips = {0,0,0,0,0,0}
  self.my_bonuses = {0,0,0,0,0}
  self.opp_bonuses = {0,0,0,0,0}
  self.turn = 0
  if tensor then
    self:from_tensor(tensor)
    return
  end
  for i=1,90 do
    self.community_cards[i] = false
    self.deck_cards[i] = true
    self.my_reserved[i] = false
    self.opp_reserved[i] = false
  end
  for i=1,10 do
    self.nobles[i] = false
  end
  -- WBRGU*
  self.score = 0
  self.opp_score = 0
  self.my_n_reserved = 0
  self.opp_n_reserved = 0
  self.my_n_chips = 0
  self.opp_n_chips = 0
  self.p1 = true
  for i=1,3 do
    self:deal_noble()
    for j=1,4 do
      self:deal_card(i)
    end
  end
end)

function GameState:deal_noble()
  local deck = decks[4]
  local n = deck[0]
  for i=1,n do
    local j = math.random(i, n)
    deck[i], deck[j] = deck[j], deck[i]
    if not self.nobles[deck[i]] then
      self.nobles[deck[i]] = true
      return
    end
  end
end

function GameState:deal_card(deck_idx)
  local deck = decks[deck_idx]
  local n = deck[0]
  local offset
  for i=1,n do
    local j = math.random(i, n)
    deck[i], deck[j] = deck[j], deck[i]
    if self.deck_cards[deck[i]] then
      self.deck_cards[deck[i]] = false
      self.community_cards[deck[i]] = true
      return
    end
  end
end

function GameState:reserve_from_deck(deck_idx)
  local deck = decks[deck_idx]
  local n = deck[0]
  local offset
  for i=1,n do
    local j = math.random(i, n)
    deck[i], deck[j] = deck[j], deck[i]
    if self.deck_cards[deck[i]] then
      self.deck_cards[deck[i]] = false
      self.my_reserved[deck[i]] = true
      return
    end
  end
end

function GameState:pretty()
  local ret = {}
  ret.community_cards = {}
  for i=1,90 do
    if self.community_cards[i] then
      ret.community_cards[#ret.community_cards+1] = holdings[i]
    end
  end
  ret.nobles = {}
  for i=1,10 do
    if self.nobles[i] then
      ret.nobles[#ret.nobles+1] = nobles[i]
    end
  end
  return ret
end

function GameState:list_moves()
  local move_set = {}
  for idx,move in ipairs(moves) do
    local ok = true
    if move.type == "reserve" then
      ok = ok and self.my_n_reserved < 3
      if move.card then
        ok = ok and self.community_cards[move.card]
      else -- reserve from deck
        local any_in_deck = false
        for i=1,90 do
          if holdings[i].deck == move.deck and self.deck_cards[i] then
            any_in_deck = true
          end
        end
        ok = ok and any_in_deck
      end
    end
    if ok and (move.type == "chip" or move.type == "reserve") then
      ok = ok and move.sum + self.my_n_chips <= 10
      if move.returns then
        ok = ok and move.sum + self.my_n_chips == 10
      elseif move.supermoves then
        for _,supermove in ipairs(move.supermoves) do
          ok = ok and not move_set[supermove]
        end
      end
      for i=1,6 do
        ok = ok and (move[i] <= 0 or self.bank[i] >= move[i] * move[i])
        ok = ok and (self.my_chips[i] + move[i] >= 0)
      end
    end
    if move.type == "buy" then
      ok = ok and (self.my_reserved[move.card] or self.community_cards[move.card])
      if ok then
        local deficit = 0
        local holding = holdings[move.card]
        for i=1,5 do
          if self.my_bonuses[i] + self.my_chips[i] < holding[i] then
            deficit = deficit + holding[i] - self.my_bonuses[i] - self.my_chips[i]
          end
        end
        ok = ok and deficit <= self.my_chips[6]
      end
    end
    if ok then
      move_set[idx] = true
    end
  end
  return move_set
end

function GameState:apply_move(move_id, print_stuff)
  local move = moves[move_id]
  if move.type == "chip" or move.type == "reserve" then
    local n_chips = 0
    for i=1,6 do
      self.bank[i] = self.bank[i] - move[i]
      self.my_chips[i] = self.my_chips[i] + move[i]
      n_chips = n_chips + self.my_chips[i]
    end
    self.my_n_chips = n_chips
  end
  if move.type == "reserve" then
    if move.card then
      self.community_cards[move.card] = false
      self.my_reserved[move.card] = true
      if print_stuff then
	print("reserving")
      end
      self:deal_card(holdings[move.card].deck)
    else
      if print_stuff then
	print("reserving from deck")
      end
      self:reserve_from_deck(move.deck)
    end
    self.my_n_reserved = self.my_n_reserved + 1
  end
  if move.type == "buy" then
    if print_stuff then
      print("buying")
    end
    local holding = holdings[move.card]
    local n_chips = 0
    for i=1,5 do
      for j=self.my_bonuses[i]+1,holding[i] do
        if self.my_chips[i] > 0 then
          self.my_chips[i] = self.my_chips[i] - 1
          self.bank[i] = self.bank[i] + 1
        elseif self.my_chips[6] > 0 then
          self.my_chips[6] = self.my_chips[6] - 1
          self.bank[6] = self.bank[6] + 1
        end
      end
      n_chips = n_chips + self.my_chips[i]
    end
    local deal_card = self.community_cards[move.card]
    n_chips = n_chips + self.my_chips[6]
    self.my_n_chips = n_chips
    if not self.community_cards[move.card] then
      self.my_n_reserved = self.my_n_reserved - 1
    end
    self.community_cards[move.card] = false
    self.my_reserved[move.card] = false
    self.deck_cards[move.card] = false
    self.opp_reserved[move.card] = false
    self.score = self.score + holding.points
    self.my_bonuses[holding.bonus] = self.my_bonuses[holding.bonus] + 1
    if deal_card then
      self:deal_card(holding.deck)
    end
  end

  -- claim noble
  for i=1,10 do
    if self.nobles[i] then
      local noble = nobles[i]
      local ok = true
      for j=1,5 do
        ok = ok and self.my_bonuses[j] >= noble[j]
      end
      if ok then
        self.score = self.score + 3
        self.nobles[i] = false
	if print_stuff then
	  print("claimed a noble!")
	end
        break
      end
    end
  end

  -- next player's turn
  self.my_reserved,   self.opp_reserved   = self.opp_reserved,   self.my_reserved
  self.my_chips,      self.opp_chips      = self.opp_chips,      self.my_chips
  self.my_bonuses,    self.opp_bonuses    = self.opp_bonuses,    self.my_bonuses
  self.score,         self.opp_score      = self.opp_score,      self.score
  self.my_n_reserved, self.opp_n_reserved = self.opp_n_reserved, self.my_n_reserved
  self.my_n_chips,    self.opp_n_chips    = self.opp_n_chips,    self.my_n_chips
  self.p1 = not self.p1

  if self.p1 then
    self.turn = self.turn + 1
  end

  -- game over?
  if (self.score >= 15 or self.opp_score >= 15) and self.p1 then
    local my_bonuses = 0
    local opp_bonuses = 0
    for i=1,5 do
      my_bonuses = my_bonuses + self.my_bonuses[i]
      opp_bonuses = opp_bonuses + self.opp_bonuses[i]
    end
    if self.score > self.opp_score then
      self.result = 1
    elseif self.score < self.opp_score then
      self.result = -1
    elseif my_bonuses < opp_bonuses then
      self.result = 1
    elseif my_bonuses > opp_bonuses then
      self.result = -1
    else
      self.result = 0
    end
  end
end

function GameState:as_tensor()
  local ret = torch.Tensor(587)
  self:dump_to_tensor(ret)
  return ret
end

function GameState:as_array()
  local ret = {}
  self:dump_to_tensor(ret)
  return ret
end

function GameState:as_string()
  local t = {}
  self:dump_to_tensor(t)
  return
end

function GameState:dump_to_tensor(ret)
  local idx = 1
  for _,card_set in ipairs({self.community_cards, self.deck_cards, self.my_reserved, self.opp_reserved}) do
    for i=1,90 do
      ret[idx] = card_set[i] and 1 or 0
      idx = idx + 1
    end
  end
  for i=1,10 do
    ret[idx] = self.nobles[i] and 1 or 0
    idx = idx + 1
  end
  for _,chip_piles in ipairs({self.bank, self.my_chips, self.opp_chips}) do
    for i=1,5 do
      for j=1,4 do
	ret[idx] = chip_piles[i] >= j and 1 or 0
	idx = idx + 1
      end
    end
    for i=1,5 do
      ret[idx] = chip_piles[6] >= i and 1 or 0
      idx = idx + 1
    end
  end
  for _,bonus_piles in ipairs({self.my_bonuses, self.opp_bonuses}) do
    for i=1,5 do
      for j=1,7 do
	ret[idx] = bonus_piles[i] >= j and 1 or 0
	idx = idx + 1
      end
    end
  end
  for _, score in ipairs({self.score, self.opp_score}) do
    for i=1,22 do
      ret[idx] = score >= i and 1 or 0
      idx = idx + 1
    end
  end
  for _, n_reserved in ipairs({self.my_n_reserved, self.opp_n_reserved}) do
    for i=1,3 do
      ret[idx] = n_reserved >= i and 1 or 0
      idx = idx + 1
    end
  end
  for _, n_chips in ipairs({self.my_n_chips, self.opp_n_chips}) do
    for i=1,10 do
      ret[idx] = n_chips >= i and 1 or 0
      idx = idx + 1
    end
  end
  ret[idx] = self.p1 and 1 or 0
  idx = idx + 1
  ret[idx] = (not self.p1) and 1 or 0
  assert(idx == 587)
end

function GameState:from_tensor(t)
  local idx = 1
  for _,card_set in ipairs({self.community_cards, self.deck_cards, self.my_reserved, self.opp_reserved}) do
    for i=1,90 do
      card_set[i] = t[idx] == 1
      idx = idx + 1
    end
  end
  for i=1,10 do
    self.nobles[i] = t[idx] == 1
    idx = idx + 1
  end
  for _,chip_piles in ipairs({self.bank, self.my_chips, self.opp_chips}) do
    for i=1,5 do
      chip_piles[i] = 0
      for j=1,4 do
	if t[idx] == 1 then
	  chip_piles[i] = j
	end
	idx = idx + 1
      end
    end
    chip_piles[6] = 0
    for i=1,5 do
      if t[idx] == 1 then
	chip_piles[6] = i
      end
      idx = idx + 1
    end
  end
  for _,bonus_piles in ipairs({self.my_bonuses, self.opp_bonuses}) do
    for i=1,5 do
      bonus_piles[i] = 0
      for j=1,7 do
	if t[idx] == 1 then
	  bonus_piles[i] = j
	end
	idx = idx + 1
      end
    end
  end
  self.score = 0
  self.opp_score = 0
  self.my_n_reserved = 0
  self.opp_n_reserved = 0
  self.my_n_chips = 0
  self.opp_n_chips = 0
  for i=1,22 do
    if t[idx] == 1 then
      self.score = i
    end
    idx = idx + 1
  end
  for i=1,22 do
    if t[idx] == 1 then
      self.opp_score = i
    end
    idx = idx + 1
  end
  for i=1,3 do
    if t[idx] == 1 then
      self.my_n_reserved = i
    end
    idx = idx + 1
  end
  for i=1,3 do
    if t[idx] == 1 then
      self.opp_n_reserved = i
    end
    idx = idx + 1
  end
  for i=1,10 do
    if t[idx] == 1 then
      self.my_n_chips = i
    end
    idx = idx + 1
  end
  for i=1,10 do
    if t[idx] == 1 then
      self.opp_n_chips = i
    end
    idx = idx + 1
  end
  self.p1 = t[idx] == 1
  print(idx)
  print(t[idx], t[idx + 1])
  assert(t[idx] + t[idx + 1] == 1)
  idx = idx + 1
  assert(idx == 587)
end

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
--[[
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
