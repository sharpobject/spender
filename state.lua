local class = require("class")
local json = require("dkjson")
local holdings = require("holdings")
local nobles = require("nobles")
local moves = require("moves")
require"util"
local n_moves = #moves
local move_masks = require"move_masks"
local bit_array_to_str = require("bit_array_to_str")
local immutable_bit_array = require("immutable_bit_array")
local bit = require"bit"
local band = bit.band
local ipairs = ipairs
local type = type
local getmetatable = getmetatable
local pairs = pairs
local assert = assert
local min = math.min
local random = math.random
local str_sub = string.sub
require"table.new"
local tb_new = table.new or function() return {} end
local tb_concat = table.concat
local tb_sort = table.sort
local decks = {}
local deck_offsets = {0,40,70,-1}
local floor = math.floor

local function round(n)
  return floor(n+.5)
end

for i=1,4 do
  local n = 50 - i * 10
  decks[i] = {[0]=n}
  for j=1,n do
    decks[i][j] = j + deck_offsets[i]
  end
  --print(json.encode(decks[i]))
end

GameState = class(function(self, tensor, det)
  self.cards = tb_new(123, 0)
  self.nobles = tb_new(3, 0)
  self.bank = {4,4,4,4,4,5}
  self.my_chips = {0,0,0,0,0,0}
  self.opp_chips = {0,0,0,0,0,0}
  self.my_bonuses = {0,0,0,0,0}
  self.opp_bonuses = {0,0,0,0,0}
  self.can_return = {0,0,0,0,0}
  if tensor and tensor.cards then
    self:from_state(tensor)
    return
  elseif type(tensor) == "string" then
    self:from_string(tensor)
    return
  elseif tensor then
    self:from_tensor(tensor)
    return
  end
  for i=1,90 do
    -- D = deck
    -- C = community
    -- 1 = p1 reserved
    -- 2 = p2 reserved
    -- _ = gone
    self.cards[i] = "D"
  end
  -- WBRGU*
  self.score = 0
  self.opp_score = 0
  self.my_n_reserved = 0
  self.opp_n_reserved = 0
  self.my_n_chips = 0
  self.opp_n_chips = 0
  self.p1 = true
  if det then
    local decks = {}
    for i=1,3 do
      local n = 50 - i * 10
      decks[i] = {[0]=n}
      for j=1,n do
        decks[i][j] = j + deck_offsets[i]
      end
      shuffle(decks[i])
    end
    self.decks = decks
  end
  for i=1,3 do
    for _=1,4 do
      self:deal_card(i)
    end
  end
  self:deal_nobles()
  tb_sort(self.nobles)
  self.passed = false
end)

function GameState:deal_nobles()
  local deck = decks[4]
  local n = deck[0]
  for i=1,3 do
    local j = random(i, n)
    deck[i], deck[j] = deck[j], deck[i]
    self.nobles[i] = deck[i]
  end
end

function GameState:deal_card(deck_idx)
  if self.decks then
    local deck = self.decks[deck_idx]
    local idx = deck[0]
    if idx > 0 then
      local card = deck[idx]
      deck[0] = idx - 1
      self.cards[card] = "C"
    end
  end
  local deck = decks[deck_idx]
  local n = deck[0]
  for i=1,n do
    local j = random(i, n)
    local oldj = deck[j]
    local oldi = deck[i]
    deck[i], deck[j] = oldj, oldi
    if self.cards[oldj] == "D" then
      self.cards[oldj] = "C"
      return
    end
  end
end

function GameState:reserve_from_deck(deck_idx)
  local whoami = "2"
  if self.p1 then
    whoami = "1"
  end
  if self.decks then
    local deck = self.decks[deck_idx]
    local idx = deck[0]
    if idx > 0 then
      local card = deck[idx]
      deck[0] = idx - 1
      self.cards[card] = whoami
    end
  end
  local deck = decks[deck_idx]
  local n = deck[0]
  for i=1,n do
    local j = random(i, n)
    deck[i], deck[j] = deck[j], deck[i]
    if self.cards[deck[i]] == "D" then
      self.cards[deck[i]] = whoami
      return
    end
  end
end

function GameState:pretty()
  local ret = {}
  ret.community_cards = {}
  for i=1,90 do
    if self.cards[i] == "C" then
      ret.community_cards[#ret.community_cards+1] = holdings[i]
    end
  end
  ret.nobles = self.nobles
  return ret
end

function GameState:list_moves()
  if self.move_list then
    return self.move_list, self.n_legal
  end
  local move_list, n_legal = self:list_moves_exdee()
  self.move_list, self.n_legal = move_list, n_legal
  return move_list, n_legal
end

local function add_chip_moves(state,list,n,lo,hi)
  for i=lo,hi do
    local mask = move_masks[i]
    if band(state, mask) == mask then
      n = n + 1; list[n] = i
    end
  end
  return n
end

local mask_parts = {
  [0] = 0x0, 0x1, 0x1, 0x1, 0x3,
  0x0, 0x4, 0x4, 0x4, 0xc,
  0x0, 0x10, 0x10, 0x10, 0x30,
  0x0, 0x40, 0x40, 0x40, 0xc0,
  0x0, 0x100, 0x100, 0x100, 0x300,
}

function GameState:list_chip_moves()
  local move_list = {}
  local n_legal = 0
  local my_n_chips = self.my_n_chips
  local my_chips = self.my_chips

  if my_n_chips > 10 then
    for i=1,6 do
      if my_chips[i] > 0 then
        n_legal = n_legal + 1
        move_list[n_legal] = i + 31
      end
    end
    return move_list, n_legal
  end

  local bank_chips = self.bank
  local state_mask =
         mask_parts[bank_chips[1]] +
         mask_parts[bank_chips[2]+5] +
         mask_parts[bank_chips[3]+10] +
         mask_parts[bank_chips[4]+15] +
         mask_parts[bank_chips[5]+20]
  local take_colors = ((bank_chips[1] > 0) and 1 or 0) +
                      ((bank_chips[2] > 0) and 1 or 0) +
                      ((bank_chips[3] > 0) and 1 or 0) +
                      ((bank_chips[4] > 0) and 1 or 0) +
                      ((bank_chips[5] > 0) and 1 or 0)
  if take_colors >= 3 then
    n_legal = add_chip_moves(state_mask, move_list, n_legal, 1, 10)
  end
  n_legal = add_chip_moves(state_mask, move_list, n_legal, 11, 15)
  if take_colors == 2 or my_n_chips >= 8 then
    n_legal = add_chip_moves(state_mask, move_list, n_legal, 16, 25)
  end
  if take_colors == 1 or my_n_chips >= 9 then
    for i=1,5 do
      if bank_chips[i] >= 1 and bank_chips[i] < 4 then
        n_legal = n_legal + 1; move_list[n_legal] = i + 25
      end
    end
  end
  if n_legal == 0 or my_n_chips == 10 then
    n_legal = n_legal + 1; move_list[n_legal] = 31
  end
  return move_list, n_legal
end

function GameState:list_moves_exdee()
  local move_list, n_legal = self:list_chip_moves()
  if self.my_n_chips > 10 then
    return move_list
  end
  local my_chips = self.my_chips
  local my_wild = my_chips[6]
  local idx = 38
  local my_reserve = "1"
  if not self.p1 then
    my_reserve = "2"
  end
  local cards = self.cards
  local my_bonuses = self.my_bonuses
  local can_reserve = self.my_n_reserved < 3
  for card_idx=1,90 do
    local card = cards[card_idx]
    if card == "C" or card == my_reserve then
      local deficit = 0
      local holding = holdings[card_idx]
      for i=1,5 do
        if my_bonuses[i] + my_chips[i] < holding[i] then
          deficit = deficit + holding[i] - my_bonuses[i] - my_chips[i]
        end
      end
      if deficit <= my_wild then
        n_legal = n_legal + 1; move_list[n_legal] = idx
      end
    end
    if can_reserve and card == "C" then
      n_legal = n_legal + 1; move_list[n_legal] = idx + 1
    end
    idx = idx + 2
  end
  local any_d = {false, false, false}
  for i=1,40 do
    if cards[i] == "D" then
      any_d[1] = true
      break
    end
  end
  for i=41,70 do
    if cards[i] == "D" then
      any_d[2] = true
      break
    end
  end
  for i=71,90 do
    if cards[i] == "D" then
      any_d[3] = true
      break
    end
  end
  for deck_idx=1,3 do
    if can_reserve and any_d[deck_idx] then
      n_legal = n_legal + 1; move_list[n_legal] = idx
    end
    idx = idx + 1
  end
  return move_list, n_legal
end

function GameState:apply_move(move_id, print_stuff)
  local move_list = self.move_list
  local n_legal = self.n_legal
  self.move_list = nil
  self.n_legal = nil
  local a,b,c = GameState(self), GameState(self:as_string()),
                  GameState(self:as_array())
  assert(deepeq(self, a))
  assert(deepeq(self, b))
  assert(deepeq(self, c))
  self.n_legal = n_legal
  self.move_list = move_list
  local passed = move_id == 31
  local move = moves[move_id]
  local old_n_chips = self.my_n_chips
  if move.type == "chip" then
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
      if self.p1 then
        self.cards[move.card] = "1"
      else
        self.cards[move.card] = "2"
      end
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
    if self.bank[6] > 0 then
      self.my_chips[6] = self.my_chips[6] + 1
      self.bank[6] = self.bank[6] - 1
      self.my_n_chips = self.my_n_chips + 1
    end
  end
  if move.type == "buy" then
    if print_stuff then
      print("buying")
    end
    local holding = holdings[move.card]
    local n_chips = 0
    for i=1,5 do
      for _=self.my_bonuses[i]+1,holding[i] do
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
    local deal_card = self.cards[move.card] == "C"
    n_chips = n_chips + self.my_chips[6]
    self.my_n_chips = n_chips
    if not deal_card then
      self.my_n_reserved = self.my_n_reserved - 1
    end
    self.cards[move.card] = "_"
    self.score = self.score + holding.points
    self.my_bonuses[holding.bonus] = min(self.my_bonuses[holding.bonus] + 1, 7)
    if deal_card then
      self:deal_card(holding.deck)
    end
  end

  if self.my_n_chips > 10 then
    -- Have to return some chips before turn ends.
    if old_n_chips <= 10 then
      -- This was the move that pushed us over 10.
      -- Set up can_return
      if move.type == "chip" and old_n_chips == 10 then
        -- Ban "synthetic pass" by preventing take GG -> return GG
        for i=1,5 do
          self.can_return[i] = move[i] == 0 and 1 or 0
        end
      else
        -- otherwise, we can return any color
        for i=1,5 do
          self.can_return[i] = 1
        end
      end
    end
    self.move_list = nil
    return
  end
  -- If we're not over 10, we can't return anything.
  for i=1,5 do
    self.can_return[i] = 0
  end

  -- claim noble
  for i=1,3 do
    if self.nobles[i] then
      local noble = nobles[self.nobles[i]]
      local ok = true
      for j=1,5 do
        ok = ok and self.my_bonuses[j] >= noble[j]
      end
      if ok then
        self.score = self.score + 3
        self.nobles[i] = false
        for j=i,2 do
          self.nobles[j], self.nobles[j+1] = self.nobles[j+1], self.nobles[j]
        end
        passed = false
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
  self.move_list = nil

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

  -- stalemate?
  if (not self.result) and passed and self.passed then
    self.result = 0
  end
  self.passed = passed
end

function GameState:as_tensor()
  local ret = torch.Tensor(313)
  self:dump_to_tensor(ret)
  return ret
end

function GameState:as_array()
  local ret = tb_new(313, 0)
  self:dump_to_tensor(ret)
  return ret
end

function GameState:as_string()
  local t = self.cards
  local nobles = self.nobles
  local my_chips = self.my_chips
  local opp_chips = self.opp_chips
  local my_bonus = self.my_bonuses
  local opp_bonus = self.opp_bonuses
  local whoami = self.p1 and "1" or "2"
  local my_score = self.score
  local opp_score = self.opp_score
  local my_n_chips = self.my_n_chips
  local opp_n_chips = self.opp_n_chips
  t[91] = whoami
  t[92] = my_chips[1]
  t[93] = my_chips[2]
  t[94] = my_chips[3]
  t[95] = my_chips[4]
  t[96] = my_chips[5]
  t[97] = my_chips[6]
  t[98] = opp_chips[1]
  t[99] = opp_chips[2]
  t[100] = opp_chips[3]
  t[101] = opp_chips[4]
  t[102] = opp_chips[5]
  t[103] = opp_chips[6]
  t[104] = my_bonus[1]
  t[105] = my_bonus[2]
  t[106] = my_bonus[3]
  t[107] = my_bonus[4]
  t[108] = my_bonus[5]
  t[109] = opp_bonus[1]
  t[110] = opp_bonus[2]
  t[111] = opp_bonus[3]
  t[112] = opp_bonus[4]
  t[113] = opp_bonus[5]
  t[114] = nobles[1] or "_"
  t[115] = nobles[2] or "_"
  t[116] = nobles[3] or "_"
  t[117] = my_score < 10 and ("0"..my_score) or my_score
  t[118] = opp_score < 10 and ("0"..opp_score) or opp_score
  t[119] = self.my_n_reserved
  t[120] = self.opp_n_reserved
  t[121] = self.passed and "P" or "N"
  t[122] = self.can_return[1]
  t[123] = self.can_return[2]
  t[124] = self.can_return[3]
  t[125] = self.can_return[4]
  t[126] = self.can_return[5]
  local ret = tb_concat(t)
  for i=91,128 do t[i] = nil end
  return ret
--  return tb_concat(t)
end

local ch_to_offset = {D=3,["1"]=1,["2"]=2}
function GameState:dump_to_tensor(ret)
  for i=1,313 do
    ret[i] = 0
  end
  if self.p1 then
    ret[1] = 1
  end
  local my_reserve, opp_reserve = "1", "2"
  if not self.p1 then
    my_reserve, opp_reserve = opp_reserve, my_reserve
  end
  ch_to_offset[my_reserve] = 1
  ch_to_offset[opp_reserve] = 2
  local cards = self.cards
  local idx = 1
  for i=1,90 do
    local card = cards[i]
    if card == "C" then
      ret[idx + 1] = 1
      ret[idx + 2] = 1
    elseif card ~= "_" then
      ret[idx + ch_to_offset[card]] = 1
    end
    idx = idx + 3
  end
  idx = idx + 1
  for i=1,3 do
    if self.nobles[i] then
      ret[idx+self.nobles[i]] = 1
    end
  end
  idx = idx + 9
  local t = self.my_chips
  ret[282] = t[1] * .25
  ret[283] = t[2] * .25
  ret[284] = t[3] * .25
  ret[285] = t[4] * .25
  ret[286] = t[5] * .25
  ret[287] = t[6] * .25
  t = self.opp_chips
  ret[288] = t[1] * .25
  ret[289] = t[2] * .25
  ret[290] = t[3] * .25
  ret[291] = t[4] * .25
  ret[292] = t[5] * .25
  ret[293] = t[6] * .25
  t = self.my_bonuses
  ret[294] = t[1] * .143
  ret[295] = t[2] * .143
  ret[296] = t[3] * .143
  ret[297] = t[4] * .143
  ret[298] = t[5] * .143
  t = self.opp_bonuses
  ret[299] = t[1] * .143
  ret[300] = t[2] * .143
  ret[301] = t[3] * .143
  ret[302] = t[4] * .143
  ret[303] = t[5] * .143
  ret[304] = self.score * .072
  ret[305] = self.opp_score * .072
  ret[306] = self.my_n_reserved * .34
  ret[307] = self.opp_n_reserved * .34
  if self.passed then
    ret[308] = 1
  end
  t = self.can_return
  ret[309] = t[1]
  ret[310] = t[2]
  ret[311] = t[3]
  ret[312] = t[4]
  ret[313] = t[5]
end

function GameState:from_state(s)
  local myt, ot = self.bank, s.bank
  local myc, oc = self.my_chips, s.my_chips
  local myoc, ooc = self.opp_chips, s.opp_chips
  local myb, ob = self.my_bonuses, s.my_bonuses
  local myob, oob = self.opp_bonuses, s.opp_bonuses
  local mycr, ocr = self.can_return, s.can_return
  for i=1,6 do
    myt[i] = ot[i]
    myc[i] = oc[i]
    myoc[i] = ooc[i]
    myb[i] = ob[i]
    myob[i] = oob[i]
    mycr[i] = ocr[i]
  end
  myt, ot = self.cards, s.cards
  for i=1,90 do
    myt[i] = ot[i]
  end
  myt, ot = self.nobles, s.nobles
  for i=1,3 do
    myt[i] = ot[i]
  end
  self.score = s.score
  self.opp_score = s.opp_score
  self.my_n_reserved = s.my_n_reserved
  self.opp_n_reserved = s.opp_n_reserved
  self.my_n_chips = s.my_n_chips
  self.opp_n_chips = s.opp_n_chips
  self.p1 = s.p1
  self.move_list = s.move_list
  self.n_legal = s.n_legal
  self.result = s.result
  self.passed = s.passed
end

function GameState:from_string(s)
  local t = self.cards
  for i=1,90 do
    t[i] = s[i]
  end
  local nobles = self.nobles
  local my_chips = self.my_chips
  local opp_chips = self.opp_chips
  local my_bonus = self.my_bonuses
  local opp_bonus = self.opp_bonuses
  local can_return = self.can_return
  local bank = self.bank
  self.p1 = s[91] == "1"
  my_chips[1] = s[92] + 0
  my_chips[2] = s[93] + 0
  my_chips[3] = s[94] + 0
  my_chips[4] = s[95] + 0
  my_chips[5] = s[96] + 0
  my_chips[6] = s[97] + 0
  opp_chips[1] = s[98] + 0
  opp_chips[2] = s[99] + 0
  opp_chips[3] = s[100] + 0
  opp_chips[4] = s[101] + 0
  opp_chips[5] = s[102] + 0
  opp_chips[6] = s[103] + 0
  bank[1] = 4 - my_chips[1] - opp_chips[1]
  bank[2] = 4 - my_chips[2] - opp_chips[2]
  bank[3] = 4 - my_chips[3] - opp_chips[3]
  bank[4] = 4 - my_chips[4] - opp_chips[4]
  bank[5] = 4 - my_chips[5] - opp_chips[5]
  bank[6] = 5 - my_chips[6] - opp_chips[6]
  my_bonus[1] = s[104] + 0
  my_bonus[2] = s[105] + 0
  my_bonus[3] = s[106] + 0
  my_bonus[4] = s[107] + 0
  my_bonus[5] = s[108] + 0
  opp_bonus[1] = s[109] + 0
  opp_bonus[2] = s[110] + 0
  opp_bonus[3] = s[111] + 0
  opp_bonus[4] = s[112] + 0
  opp_bonus[5] = s[113] + 0
  nobles[1] = s[114] ~= "_" and (s[114] + 0) or false
  nobles[2] = s[115] ~= "_" and (s[115] + 0) or false
  nobles[3] = s[116] ~= "_" and (s[116] + 0) or false
  self.score = str_sub(s,117,118) + 0
  self.opp_score = str_sub(s,119,120) + 0
  self.my_n_chips = my_chips[1] + my_chips[2] + my_chips[3] +
                    my_chips[4] + my_chips[5] + my_chips[6]
  self.opp_n_chips = opp_chips[1] + opp_chips[2] + opp_chips[3] +
                     opp_chips[4] + opp_chips[5] + opp_chips[6]
  self.my_n_reserved = s[121] + 0
  self.opp_n_reserved = s[122] + 0
  self.passed = s[123] == "P"
  can_return[1] = s[124] + 0
  can_return[2] = s[125] + 0
  can_return[3] = s[126] + 0
  can_return[4] = s[127] + 0
  can_return[5] = s[128] + 0
end

function GameState:from_tensor(t)
  local idx = 0
  idx = idx + 1
  self.p1 = t[idx] == 1
  local my_reserve, opp_reserve = "1", "2"
  if not self.p1 then
    my_reserve, opp_reserve = opp_reserve, my_reserve
  end
  local cards = self.cards
  for i=1,90 do
    cards[i] = "_"
    idx = idx + 1
    if t[idx] == 1 then
      if t[idx+1] == 1 then
        cards[i] = "C"
      else
        cards[i] = my_reserve
      end
    elseif t[idx+1] == 1 then
      cards[i] = opp_reserve
    end
    idx = idx + 2
    if t[idx] == 1 then cards[i] = "D" end
  end
  self.nobles[1], self.nobles[2], self.nobles[3] = false, false, false
  local n_nobles = 0
  for i=0,9 do
    idx = idx + 1
    if t[idx] == 1 then
      n_nobles = n_nobles + 1
      self.nobles[n_nobles] = i
    end
  end
  assert(idx == 281)
  local out = self.my_chips
  out[1] = round(t[282] * 4)
  out[2] = round(t[283] * 4)
  out[3] = round(t[284] * 4)
  out[4] = round(t[285] * 4)
  out[5] = round(t[286] * 4)
  out[6] = round(t[287] * 4)
  out = self.opp_chips
  out[1] = round(t[288] * 4)
  out[2] = round(t[289] * 4)
  out[3] = round(t[290] * 4)
  out[4] = round(t[291] * 4)
  out[5] = round(t[292] * 4)
  out[6] = round(t[293] * 4)
  local my_chips, opp_chips, bank = self.my_chips, self.opp_chips, self.bank
  bank[1] = 4 - my_chips[1] - opp_chips[1]
  bank[2] = 4 - my_chips[2] - opp_chips[2]
  bank[3] = 4 - my_chips[3] - opp_chips[3]
  bank[4] = 4 - my_chips[4] - opp_chips[4]
  bank[5] = 4 - my_chips[5] - opp_chips[5]
  bank[6] = 5 - my_chips[6] - opp_chips[6]
  out = self.my_bonuses
  out[1] = round(t[294] * 6.993006993006993)
  out[2] = round(t[295] * 6.993006993006993)
  out[3] = round(t[296] * 6.993006993006993)
  out[4] = round(t[297] * 6.993006993006993)
  out[5] = round(t[298] * 6.993006993006993)
  out = self.opp_bonuses
  out[1] = round(t[299] * 6.993006993006993)
  out[2] = round(t[300] * 6.993006993006993)
  out[3] = round(t[301] * 6.993006993006993)
  out[4] = round(t[302] * 6.993006993006993)
  out[5] = round(t[303] * 6.993006993006993)
  self.score = round(t[304] * 13.888888888888889)
  self.opp_score = round(t[305] * 13.888888888888889)
  self.my_n_chips = my_chips[1] + my_chips[2] + my_chips[3] +
                    my_chips[4] + my_chips[5] + my_chips[6]
  self.opp_n_chips = opp_chips[1] + opp_chips[2] + opp_chips[3] +
                     opp_chips[4] + opp_chips[5] + opp_chips[6]
  self.my_n_reserved = round(t[306] * 2.941176470588235)
  self.opp_n_reserved = round(t[307] * 2.941176470588235)
  self.passed = t[308] == 1
  out = self.can_return
  out[1] = t[309]
  out[2] = t[310]
  out[3] = t[311]
  out[4] = t[312]
  out[5] = t[313]
end

