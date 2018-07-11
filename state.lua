local class = require("class")
local json = require("dkjson")
local holdings = require("holdings")
local nobles = require("nobles")
local moves = require("moves")
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
for i=1,4 do
  local n = 50 - i * 10
  decks[i] = {[0]=n}
  for j=1,n do
    decks[i][j] = j + deck_offsets[i]
  end
  --print(json.encode(decks[i]))
end

GameState = class(function(self, tensor)
  self.cards = tb_new(123, 0)
  self.nobles = tb_new(3, 0)
  self.bank = {4,4,4,4,4,5}
  self.my_chips = {0,0,0,0,0,0}
  self.opp_chips = {0,0,0,0,0,0}
  self.my_bonuses = {0,0,0,0,0}
  self.opp_bonuses = {0,0,0,0,0}
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
  local deck = decks[deck_idx]
  local n = deck[0]
  for i=1,n do
    local j = random(i, n)
    deck[i], deck[j] = deck[j], deck[i]
    if self.cards[deck[i]] == "D" then
      if self.p1 then
        self.cards[deck[i]] = "1"
      else
        self.cards[deck[i]] = "2"
      end
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
  0x0, 0x400, 0xc00, 0x1c00, 0x1c00,
  0x0, 0x2000, 0x6000, 0xe000, 0xe000,
  0x0, 0x10000, 0x30000, 0x70000, 0x70000,
  0x0, 0x80000, 0x180000, 0x380000, 0x380000,
  0x0, 0x400000, 0xc00000, 0x1c00000, 0x1c00000,
  0x0, 0x2000000, 0x6000000, 0xe000000, 0xe000000, 0xe000000,
}

function GameState:list_chip_moves()
  local move_list = {}
  local n_legal = 0
  local my_n_chips = self.my_n_chips
  local bank_chips = self.bank
  local my_chips = self.my_chips
  local state_mask =
         mask_parts[bank_chips[1]] +
         mask_parts[bank_chips[2]+5] +
         mask_parts[bank_chips[3]+10] +
         mask_parts[bank_chips[4]+15] +
         mask_parts[bank_chips[5]+20] +
         mask_parts[my_chips[1]+25] +
         mask_parts[my_chips[2]+30] +
         mask_parts[my_chips[3]+35] +
         mask_parts[my_chips[4]+40] +
         mask_parts[my_chips[5]+45] +
         mask_parts[my_chips[6]+50]
  local take_colors = ((bank_chips[1] > 0) and 1 or 0) +
                      ((bank_chips[2] > 0) and 1 or 0) +
                      ((bank_chips[3] > 0) and 1 or 0) +
                      ((bank_chips[4] > 0) and 1 or 0) +
                      ((bank_chips[5] > 0) and 1 or 0)
  local take_two = (bank_chips[1] > 3) or
                   (bank_chips[2] > 3) or
                   (bank_chips[3] > 3) or
                   (bank_chips[4] > 3) or
                   (bank_chips[5] > 3)
  if my_n_chips <= 7 and take_colors >= 3 then
    n_legal = add_chip_moves(state_mask, move_list, n_legal, 1, 10)
  end
  if my_n_chips <= 8 and take_two then
    n_legal = add_chip_moves(state_mask, move_list, n_legal, 11, 15)
  end
  if (take_colors == 2 and my_n_chips <= 8) or my_n_chips == 8 then
    n_legal = add_chip_moves(state_mask, move_list, n_legal, 16, 25)
  end
  if (take_colors == 1 and my_n_chips <= 9) or my_n_chips == 9 then
    for i=1,5 do
      if bank_chips[i] >= 1 and bank_chips[i] < 4 then
        n_legal = n_legal + 1; move_list[n_legal] = i + 25
      end
    end
  end
  if n_legal == 0 then
    n_legal = n_legal + 1; move_list[n_legal] = 31
  end
  if my_n_chips == 8 and take_colors >= 3 then
    n_legal = add_chip_moves(state_mask, move_list, n_legal, 32, 61)
  end
  if my_n_chips == 9 then
    if take_colors >= 3 then
      n_legal = add_chip_moves(state_mask, move_list, n_legal, 62, 121)
    end
    if take_two then
      n_legal = add_chip_moves(state_mask, move_list, n_legal, 122, 146)
    end
    if take_colors >= 2 then
      n_legal = add_chip_moves(state_mask, move_list, n_legal, 147, 186)
    end
  end
  if my_n_chips == 10 then
    if take_colors >= 3 then
      n_legal = add_chip_moves(state_mask, move_list, n_legal, 187, 286)
    end
    if take_two then
      n_legal = add_chip_moves(state_mask, move_list, n_legal, 287, 361)
    end
    if take_colors >= 2 then
      n_legal = add_chip_moves(state_mask, move_list, n_legal, 362, 461)
    end
    n_legal = add_chip_moves(state_mask, move_list, n_legal, 462, 486)
  end
  return move_list, n_legal
end

local chip_moves_lookup = {}
local id_table = {}

function GameState:get_chip_id()
  local my_chips = self.my_chips
  local my_n_chips = self.my_n_chips
  local bank = self.bank
  local bwild = bank[6]
  bank[6] = 0
  for i=1,6 do
    local banki = bank[i]
    local myi = my_chips[i]
    local idtbi = "1"
    if banki == 4 then
      idtbi = "2"
    elseif banki > 0 then
      idtbi = "3"
    end
    if my_n_chips >= 8 and myi >= 1 then
      if banki > 0 then
        idtbi = "4"
        if my_n_chips >= 10 and myi >= 3 then
          idtbi = "5"
        elseif my_n_chips >= 9 and myi >= 2 then
          idtbi = "6"
        end
      else
        idtbi = "7"
        if my_n_chips >= 10 and myi >= 3 then
          idtbi = "8"
        elseif my_n_chips >= 9 and my_chips[i] >= 2 then
          idtbi = "9"
        end
      end
    end
    id_table[i] = idtbi
  end
  bank[6] = bwild
  return tb_concat(id_table)
end

do
  local state = GameState()
  local my_chips = state.my_chips
  local opp_chips = state.opp_chips
  local bank = state.bank
  local inverted_idx = {}
  local idx = {}
  for i=1,90 do
    state.cards[i] = "_"
  end
  for a=0,4 do for b=0,4 do for c=0,4 do for d=0,4 do for e=0,4 do for f=0,5 do
  if a+b+c+d+e+f <= 10 then
    for oa=0,4-a do for ob=0,4-b do for oc=0,4-c do for od=0,4-d do for oe=0,4-e do
      if oa+ob+oc+od+oe <= 10 then
        state.my_n_chips = a+b+c+d+e+f
        my_chips[1] = a
        my_chips[2] = b
        my_chips[3] = c
        my_chips[4] = d
        my_chips[5] = e
        my_chips[6] = f
        opp_chips[1] = oa
        opp_chips[2] = ob
        opp_chips[3] = oc
        opp_chips[4] = od
        opp_chips[5] = oe
        bank[1] = 4-a-oa
        bank[2] = 4-b-ob
        bank[3] = 4-c-oc
        bank[4] = 4-d-od
        bank[5] = 4-e-oe
        bank[6] = 5-f
        local id = state:get_chip_id()
        local move_list = state:list_chip_moves()
        if not idx[id] then
          idx[id] = move_list
        end
      end
    end end end end end
  end
  end end end end end end
  for k,v in pairs(idx) do
    local inv_key = json.encode(v)
    local entry = inverted_idx[inv_key]
    if entry then
      entry.n = entry.n + 1
      entry[entry.n] = k
    else
      inverted_idx[inv_key] = {n=1,canonical=v,k}
      v[0] = #v
    end
  end
  for k,v in pairs(inverted_idx) do
    local canonical = v.canonical
    for i=1,v.n do
      chip_moves_lookup[v[i]] = canonical
    end
  end
end

function GameState:list_moves_exdee()
  local chip_id = self:get_chip_id()
  local chip_moves = chip_moves_lookup[chip_id]
  local n_legal = chip_moves[0]
  local move_list = tb_new(n_legal + 30, 0)
  for i=1,n_legal do
    move_list[i] = chip_moves[i]
  end
  local my_n_chips = self.my_n_chips
  local take_wild = self.bank[6] > 0
  local my_chips = self.my_chips
  local my_wild = my_chips[6]
  local return_w = my_chips[1] > 0
  local return_b = my_chips[2] > 0
  local return_r = my_chips[3] > 0
  local return_g = my_chips[4] > 0
  local return_u = my_chips[5] > 0
  local idx = 487
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
      if my_n_chips <= 9 and take_wild then
        n_legal = n_legal + 1; move_list[n_legal] = idx + 1
      end
      if my_n_chips == 10 or not take_wild then
        n_legal = n_legal + 1; move_list[n_legal] = idx + 2
      end
      if my_n_chips == 10 and take_wild then
        if return_w then
          n_legal = n_legal + 1; move_list[n_legal] = idx + 3
        end
        if return_b then
          n_legal = n_legal + 1; move_list[n_legal] = idx + 4
        end
        if return_r then
          n_legal = n_legal + 1; move_list[n_legal] = idx + 5
        end
        if return_g then
          n_legal = n_legal + 1; move_list[n_legal] = idx + 6
        end
        if return_u then
          n_legal = n_legal + 1; move_list[n_legal] = idx + 7
        end
      end
    end
    idx = idx + 8
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
      if my_n_chips <= 9 and take_wild then
        n_legal = n_legal + 1; move_list[n_legal] = idx
      end
      if my_n_chips == 10 or not take_wild then
        n_legal = n_legal + 1; move_list[n_legal] = idx + 1
      end
      if my_n_chips == 10 and take_wild then
        if return_w then
          n_legal = n_legal + 1; move_list[n_legal] = idx + 2
        end
        if return_b then
          n_legal = n_legal + 1; move_list[n_legal] = idx + 3
        end
        if return_r then
          n_legal = n_legal + 1; move_list[n_legal] = idx + 4
        end
        if return_g then
          n_legal = n_legal + 1; move_list[n_legal] = idx + 5
        end
        if return_u then
          n_legal = n_legal + 1; move_list[n_legal] = idx + 6
        end
      end
    end
    idx = idx + 7
  end
  return move_list, n_legal
end

function GameState:apply_move(move_id, print_stuff)
  local passed = move_id == 31
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
  local ret = torch.Tensor(588)
  self:dump_to_tensor(ret)
  return ret
end

function GameState:as_array()
  local ret = tb_new(588, 0)
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
  t[119] = my_n_chips < 10 and ("0"..my_n_chips) or my_n_chips
  t[120] = opp_n_chips < 10 and ("0"..opp_n_chips) or opp_n_chips
  t[121] = self.my_n_reserved
  t[122] = self.opp_n_reserved
  t[123] = self.passed and "P" or "N"
  local ret = tb_concat(t)
  for i=91,123 do t[i] = nil end
  return ret
--  return tb_concat(t)
end

local ch_to_offset = {C=1,D=2,["1"]=3,["2"]=4}
function GameState:dump_to_tensor(ret)
  for i=1,588 do
    ret[i] = 0
  end
  if self.p1 then
    ret[1] = 1
  else
    ret[2] = 1
  end
  local my_reserve, opp_reserve = "1", "2"
  if not self.p1 then
    my_reserve, opp_reserve = opp_reserve, my_reserve
  end
  ch_to_offset[my_reserve] = 3
  ch_to_offset[opp_reserve] = 4
  local cards = self.cards
  local idx = 2
  for i=1,90 do
    local card = cards[i]
    if card ~= "_" then
      ret[idx + ch_to_offset[card]] = 1
    end
    idx = idx + 4
  end
  idx = idx + 1
  for i=1,3 do
    if self.nobles[i] then
      ret[idx+self.nobles[i]] = 1
    end
  end
  idx = idx + 9
  local t = self.bank
  for i=373,372+t[1] do
    ret[i] = 1
  end
  for i=377,376+t[2] do
    ret[i] = 1
  end
  for i=381,380+t[3] do
    ret[i] = 1
  end
  for i=385,384+t[4] do
    ret[i] = 1
  end
  for i=389,388+t[5] do
    ret[i] = 1
  end
  for i=393,392+t[6] do
    ret[i] = 1
  end
  t = self.my_chips
  for i=398,397+t[1] do
    ret[i] = 1
  end
  for i=402,401+t[2] do
    ret[i] = 1
  end
  for i=406,405+t[3] do
    ret[i] = 1
  end
  for i=410,409+t[4] do
    ret[i] = 1
  end
  for i=414,413+t[5] do
    ret[i] = 1
  end
  for i=418,417+t[6] do
    ret[i] = 1
  end
  t = self.opp_chips
  for i=423,422+t[1] do
    ret[i] = 1
  end
  for i=427,426+t[2] do
    ret[i] = 1
  end
  for i=431,430+t[3] do
    ret[i] = 1
  end
  for i=435,434+t[4] do
    ret[i] = 1
  end
  for i=439,438+t[5] do
    ret[i] = 1
  end
  for i=443,442+t[6] do
    ret[i] = 1
  end
  t = self.my_bonuses
  for i=448,447+t[1] do
    ret[i] = 1
  end
  for i=455,454+t[2] do
    ret[i] = 1
  end
  for i=462,461+t[3] do
    ret[i] = 1
  end
  for i=469,468+t[4] do
    ret[i] = 1
  end
  for i=476,475+t[5] do
    ret[i] = 1
  end
  t = self.opp_bonuses
  for i=483,482+t[1] do
    ret[i] = 1
  end
  for i=490,489+t[2] do
    ret[i] = 1
  end
  for i=497,496+t[3] do
    ret[i] = 1
  end
  for i=504,503+t[4] do
    ret[i] = 1
  end
  for i=511,510+t[5] do
    ret[i] = 1
  end
  for i=518,517+self.score do
    ret[i] = 1
  end
  for i=540,539+self.opp_score do
    ret[i] = 1
  end
  for i=562,561+self.my_n_reserved do
    ret[i] = 1
  end
  for i=565,564+self.opp_n_reserved do
    ret[i] = 1
  end
  for i=568,567+self.my_n_chips do
    ret[i] = 1
  end
  for i=578,577+self.opp_n_chips do
    ret[i] = 1
  end
  if self.passed then
    ret[588] = 1
  end
end

function GameState:from_state(s)
  local myt, ot = self.bank, s.bank
  local myc, oc = self.my_chips, s.my_chips
  local myoc, ooc = self.opp_chips, s.opp_chips
  local myb, ob = self.my_bonuses, s.my_bonuses
  local myob, oob = self.opp_bonuses, s.opp_bonuses
  for i=1,6 do
    myt[i] = ot[i]
    myc[i] = oc[i]
    myoc[i] = ooc[i]
    myb[i] = ob[i]
    myob[i] = oob[i]
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
  self.my_n_chips = str_sub(s,121,122) + 0
  self.opp_n_chips = str_sub(s,123,124) + 0
  self.my_n_reserved = s[125] + 0
  self.opp_n_reserved = s[126] + 0
  self.passed = s[127] == "P"
end

function GameState:from_tensor(t)
  local idx = 0
  idx = idx + 1
  self.p1 = t[idx] == 1
  assert(t[idx] + t[idx + 1] == 1)
  idx = idx + 1
  local my_reserve, opp_reserve = "1", "2"
  if not self.p1 then
    my_reserve, opp_reserve = opp_reserve, my_reserve
  end
  local cards = self.cards
  for i=1,90 do
    cards[i] = "_"
    idx = idx + 1
    if t[idx] == 1 then cards[i] = "C" end
    idx = idx + 1
    if t[idx] == 1 then cards[i] = "D" end
    idx = idx + 1
    if t[idx] == 1 then cards[i] = my_reserve end
    idx = idx + 1
    if t[idx] == 1 then cards[i] = opp_reserve end
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
  for _,chip_piles in ipairs({self.bank, self.my_chips, self.opp_chips}) do
    for i=1,5 do
      chip_piles[i] = 0
      for j=1,4 do
        idx = idx + 1
        if t[idx] == 1 then
          chip_piles[i] = j
        end
      end
    end
    chip_piles[6] = 0
    for i=1,5 do
      idx = idx + 1
      if t[idx] == 1 then
        chip_piles[6] = i
      end
    end
  end
  for _,bonus_piles in ipairs({self.my_bonuses, self.opp_bonuses}) do
    for i=1,5 do
      bonus_piles[i] = 0
      for j=1,7 do
        idx = idx + 1
        if t[idx] == 1 then
          bonus_piles[i] = j
        end
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
    idx = idx + 1
    if t[idx] == 1 then
      self.score = i
    end
  end
  for i=1,22 do
    idx = idx + 1
    if t[idx] == 1 then
      self.opp_score = i
    end
  end
  for i=1,3 do
    idx = idx + 1
    if t[idx] == 1 then
      self.my_n_reserved = i
    end
  end
  for i=1,3 do
    idx = idx + 1
    if t[idx] == 1 then
      self.opp_n_reserved = i
    end
  end
  for i=1,10 do
    idx = idx + 1
    if t[idx] == 1 then
      self.my_n_chips = i
    end
  end
  for i=1,10 do
    idx = idx + 1
    if t[idx] == 1 then
      self.opp_n_chips = i
    end
  end
  idx = idx + 1
  self.passed = t[idx] == 1
  assert(idx == 588)
end

