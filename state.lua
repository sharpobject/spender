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
local lshift = bit.lshift
local band = bit.band
local bor = bit.bor
local ipairs = ipairs
local type = type
local getmetatable = getmetatable
local pairs = pairs
local assert = assert
require"table.new"
local tb_new = table.new or function() return {} end
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
  self.cards = tb_new(90, 0)
  self.nobles = tb_new(10, 0)
  self.bank = {4,4,4,4,4,5}
  self.my_chips = {0,0,0,0,0,0}
  self.opp_chips = {0,0,0,0,0,0}
  self.my_bonuses = {0,0,0,0,0}
  self.opp_bonuses = {0,0,0,0,0}
  self.turn = 0
  if tensor then
    if type(tensor) == "table" then
      if getmetatable(tensor) == GameState then
        self:from_state(tensor)
        return
      else
        self:from_tensor(tensor)
        return
      end
    elseif type(tensor) == "string" then
      self:from_string(tensor)
      return
    else
      self:from_tensor(tensor)
      return
    end
  end
  for i=1,90 do
    -- D = deck
    -- C = community
    -- 1 = p1 reserved
    -- 2 = p2 reserved
    -- _ = gone
    self.cards[i] = "D"
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
    for _=1,4 do
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
  for i=1,n do
    local j = math.random(i, n)
    deck[i], deck[j] = deck[j], deck[i]
    if self.cards[deck[i]] == "D" then
      self.cards[deck[i]] = "C"
      return
    end
  end
end

function GameState:reserve_from_deck(deck_idx)
  local deck = decks[deck_idx]
  local n = deck[0]
  for i=1,n do
    local j = math.random(i, n)
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
  ret.nobles = {}
  for i=1,10 do
    if self.nobles[i] then
      ret.nobles[#ret.nobles+1] = nobles[i]
    end
  end
  return ret
end

function GameState:list_moves()
  local my_reserve, opp_reserve = "1", "2"
  if not self.p1 then
    my_reserve, opp_reserve = opp_reserve, my_reserve
  end
  if self.move_list then
    return self.move_list, self.n_legal
  end
  local move_list = tb_new(100, 0)
  local n_legal = 0
  local move_list, n_legal = self:list_moves_exdee()
  local move_set = {}
  for idx=487,n_moves do
    local move = moves[idx]
    local ok = true
    if move.type == "reserve" then
      ok = ok and self.my_n_reserved < 3
      if move.card then
        ok = ok and self.cards[move.card] == "C"
      else -- reserve from deck
        local any_in_deck = false
        for i=1,90 do
          if holdings[i].deck == move.deck and self.cards[i] == "D" then
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
      ok = ok and (self.cards[move.card] == "C" or self.cards[move.card] == my_reserve)
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
      n_legal = n_legal + 1
      move_list[n_legal] = idx
    end
  end
  self.move_list, self.n_legal = move_list, n_legal
  --print(json.encode(set_to_arr(move_set)))
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

local bank_mask_parts = {
  [0] = 0x0, 0x1, 0x1, 0x1, 0x3,
  0x0, 0x4, 0x4, 0x4, 0xc,
  0x0, 0x10, 0x10, 0x10, 0x30,
  0x0, 0x40, 0x40, 0x40, 0xc0,
  0x0, 0x100, 0x100, 0x100, 0x300,
}
local my_mask_parts = {
  [0] = 0x0, 0x400, 0xc00, 0x1c00, 0x1c00,
  0x0, 0x2000, 0x6000, 0xe000, 0xe000,
  0x0, 0x10000, 0x30000, 0x70000, 0x70000,
  0x0, 0x80000, 0x180000, 0x380000, 0x380000,
  0x0, 0x400000, 0xc00000, 0x1c00000, 0x1c00000,
  0x0, 0x2000000, 0x6000000, 0xe000000, 0xe000000, 0xe000000,
}

local function get_mask(bank_chips, my_chips)
  local ret = 
         bank_mask_parts[bank_chips[1]]+
         bank_mask_parts[bank_chips[2]+5]+
         bank_mask_parts[bank_chips[3]+10]+
         bank_mask_parts[bank_chips[4]+15]+
         bank_mask_parts[bank_chips[5]+20]+
         my_mask_parts[my_chips[1]]+
         my_mask_parts[my_chips[2]+5]+
         my_mask_parts[my_chips[3]+10]+
         my_mask_parts[my_chips[4]+15]+
         my_mask_parts[my_chips[5]+20]+
         my_mask_parts[my_chips[6]+25]
  return ret
end

function GameState:list_moves_exdee(move_list, n_legal)
  local move_list = move_list or tb_new(100, 0)
  local n_legal = n_legal or 0
  local my_n_chips = self.my_n_chips
  local bank_chips = self.bank
  local my_chips = self.my_chips
  local state_mask = get_mask(bank_chips, my_chips)
  local take_wild = bank_chips[6] > 0
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
  local my_w = my_chips[1]
  local my_b = my_chips[2]
  local my_r = my_chips[3]
  local my_g = my_chips[4]
  local my_u = my_chips[5]
  local my_wild = my_chips[6]
  local return_w = my_w > 0
  local return_b = my_b > 0
  local return_r = my_r > 0
  local return_g = my_g > 0
  local return_u = my_u > 0
  if my_n_chips <= 7 and take_colors >= 3 then
    n_legal = add_chip_moves(state_mask, move_list, n_legal, 1, 10)
  end
  if my_n_chips <= 8 and take_two then
    n_legal = add_chip_moves(state_mask, move_list, n_legal, 11, 15)
  end
  if take_colors == 2 or my_n_chips == 8 then
    n_legal = add_chip_moves(state_mask, move_list, n_legal, 16, 25)
  end
  if take_colors == 1 or my_n_chips == 9 then
    n_legal = add_chip_moves(state_mask, move_list, n_legal, 26, 30)
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
function GameState:list_moves_quickly(move_list, n_legal)
  local move_list = move_list or tb_new(100, 0)
  local n_legal = n_legal or 0
  local my_n_chips = self.my_n_chips
  local bank_chips = self.bank
  local my_chips = self.my_chips
  local state_mask = 0
  for i=1,5 do
    if bank_chips[i] >= 1 then
      state_mask = bor(state_mask, lshift(1, 2*i - 2))
    end
    if bank_chips[i] >= 4 then
      state_mask = bor(state_mask, lshift(1, 2*i - 1))
    end
  end
  for i=1,6 do
    if my_chips[i] >= 1 then
      state_mask = bor(state_mask, lshift(1, 3*i + 7))
    end
    if my_chips[i] >= 2 then
      state_mask = bor(state_mask, lshift(1, 3*i + 8))
    end
    if my_chips[i] >= 3 then
      state_mask = bor(state_mask, lshift(1, 3*i + 9))
    end
  end
  local take_wild = bank_chips[6] > 0
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
  local my_w = my_chips[1]
  local my_b = my_chips[2]
  local my_r = my_chips[3]
  local my_g = my_chips[4]
  local my_u = my_chips[5]
  local my_wild = my_chips[6]
  local return_w = my_w > 0
  local return_b = my_b > 0
  local return_r = my_r > 0
  local return_g = my_g > 0
  local return_u = my_u > 0
  if my_n_chips <= 7 and take_colors >= 3 then
    for i=1,10 do
      local mask = move_masks[i]
      if band(state_mask, mask) == mask then
        n_legal = n_legal + 1; move_list[n_legal] = i
      end
    end
  end
  if my_n_chips <= 8 and take_two then
    for i=11,15 do
      local mask = move_masks[i]
      if band(state_mask, mask) == mask then
        n_legal = n_legal + 1; move_list[n_legal] = i
      end
    end
  end
  if take_colors == 2 or my_n_chips == 8 then
    for i=16,25 do
      local mask = move_masks[i]
      if band(state_mask, mask) == mask then
        n_legal = n_legal + 1; move_list[n_legal] = i
      end
    end
  end
  if take_colors == 1 or my_n_chips == 9 then
    for i=26,30 do
      local mask = move_masks[i]
      if band(state_mask, mask) == mask then
        n_legal = n_legal + 1; move_list[n_legal] = i
      end
    end
  end
  if n_legal == 0 then
    n_legal = n_legal + 1; move_list[n_legal] = 31
  end
  if my_n_chips == 8 and take_colors >= 3 then
    for i=32,61 do
      local mask = move_masks[i]
      if band(state_mask, mask) == mask then
        n_legal = n_legal + 1; move_list[n_legal] = i
      end
    end
  end
  if my_n_chips == 9 then
    if take_colors >= 3 then
      for i=62,121 do
        local mask = move_masks[i]
        if band(state_mask, mask) == mask then
          n_legal = n_legal + 1; move_list[n_legal] = i
        end
      end
    end
    if take_two then
      for i=122,146 do
        local mask = move_masks[i]
        if band(state_mask, mask) == mask then
          n_legal = n_legal + 1; move_list[n_legal] = i
        end
      end
    end
    if take_colors >= 2 then
      for i=147,186 do
        local mask = move_masks[i]
        if band(state_mask, mask) == mask then
          n_legal = n_legal + 1; move_list[n_legal] = i
        end
      end
    end
  end
  if my_n_chips == 10 then
    if take_colors >= 3 then
      for i=187,286 do
        local mask = move_masks[i]
        if band(state_mask, mask) == mask then
          n_legal = n_legal + 1; move_list[n_legal] = i
        end
      end
    end
    if take_two then
      for i=287,361 do
        local mask = move_masks[i]
        if band(state_mask, mask) == mask then
          n_legal = n_legal + 1; move_list[n_legal] = i
        end
      end
    end
    if take_colors >= 2 then
      for i=362,461 do
        local mask = move_masks[i]
        if band(state_mask, mask) == mask then
          n_legal = n_legal + 1; move_list[n_legal] = i
        end
      end
    end
    for i=462,486 do
      local mask = move_masks[i]
      if band(state_mask, mask) == mask then
        n_legal = n_legal + 1; move_list[n_legal] = i
      end
    end
  end
  return move_list, n_legal
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

  -- stalemate?
  self.move_list = nil
  if self.my_chips == 10 and self.opp_chips == 10 and not self.result then
    local move_list, n_legal = self:list_moves()
    if n_legal == 1 and move_list[1] == 31 and not self.sm_check then
      local next_state = GameState(self)
      next_state.sm_check = true
      next_state:apply_move(31)
      move_list, n_legal = next_state:list_moves()
      if n_legal == 1 and move_list[1] == 31 then
        next_state:apply_move(31)
        if self.score == next_state.score and self.opp_score == next_state.opp_score then
          --print("STALEMATE MOTHERFUCKER")
          self.result = 0
        end
      end
    end
  end
end

function GameState:as_tensor()
  local ret = torch.Tensor(587)
  self:dump_to_tensor(ret)
  return ret
end

function GameState:as_array()
  local ret = tb_new(587, 0)
  self:dump_to_tensor(ret)
  return ret
end

function GameState:as_string()
  return bit_array_to_str(self:as_array())
end

function GameState:dump_to_tensor(ret)
  local idx = 0
  idx = idx + 1
  ret[idx] = self.p1 and 1 or 0
  idx = idx + 1
  ret[idx] = (not self.p1) and 1 or 0
  local my_reserve, opp_reserve = "1", "2"
  if not self.p1 then
    my_reserve, opp_reserve = opp_reserve, my_reserve
  end
  local cards = self.cards
  for i=1,90 do
    idx = idx + 1
    ret[idx] = cards[i] == "C" and 1 or 0
    idx = idx + 1
    ret[idx] = cards[i] == "D" and 1 or 0
    idx = idx + 1
    ret[idx] = cards[i] == my_reserve and 1 or 0
    idx = idx + 1
    ret[idx] = cards[i] == opp_reserve and 1 or 0
  end
  for i=1,10 do
    idx = idx + 1
    ret[idx] = self.nobles[i] and 1 or 0
  end
  for _,chip_piles in ipairs({self.bank, self.my_chips, self.opp_chips}) do
    for i=1,5 do
      for j=1,4 do
        idx = idx + 1
        ret[idx] = chip_piles[i] >= j and 1 or 0
      end
    end
    for i=1,5 do
      idx = idx + 1
      ret[idx] = chip_piles[6] >= i and 1 or 0
    end
  end
  for _,bonus_piles in ipairs({self.my_bonuses, self.opp_bonuses}) do
    for i=1,5 do
      for j=1,7 do
        idx = idx + 1
        ret[idx] = bonus_piles[i] >= j and 1 or 0
      end
    end
  end
  for _, score in ipairs({self.score, self.opp_score}) do
    for i=1,22 do
      idx = idx + 1
      ret[idx] = score >= i and 1 or 0
    end
  end
  for _, n_reserved in ipairs({self.my_n_reserved, self.opp_n_reserved}) do
    for i=1,3 do
      idx = idx + 1
      ret[idx] = n_reserved >= i and 1 or 0
    end
  end
  for _, n_chips in ipairs({self.my_n_chips, self.opp_n_chips}) do
    for i=1,10 do
      idx = idx + 1
      ret[idx] = n_chips >= i and 1 or 0
    end
  end
  assert(idx == 587)
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
  for i=1,10 do
    myt[i] = ot[i]
  end
  self.score = s.score
  self.opp_score = s.opp_score
  self.my_n_reserved = s.my_n_reserved
  self.opp_n_reserved = s.opp_n_reserved
  self.my_n_chips = s.my_n_chips
  self.opp_n_chips = s.opp_n_chips
  self.p1 = s.p1
  self.turn = s.turn
  self.move_list = s.move_list
  self.n_legal = s.n_legal
end

function GameState:from_string(s)
  self:from_tensor(immutable_bit_array(s))
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
  for i=1,10 do
    idx = idx + 1
    self.nobles[i] = t[idx] == 1
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
  assert(idx == 587)
end

