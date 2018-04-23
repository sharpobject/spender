import("class")
local json = import("dkjson")
local holdings = require("holdings")
local nobles = require("nobles")
local decks = {}
local deck_offsets = {0,40,70,0}
for i=1,4 do
  local n = 50 - i * 10
  decks[i] = {[0]=n}
  for j=1,n do
    decks[i][j] = j + deck_offsets[i]
  end
end

GameState = class(function(self)
  self.community_cards = {}
  self.deck_cards = {}
  self.my_reserved = {}
  self.opp_reserved = {}
  for i=1,90 do
    self.community_cards[i] = false
    self.deck_cards[i] = true
    self.my_reserved[i] = false
    self.opp_reserved[i] = false
  end
  self.nobles = {}
  -- WBRGU*
  self.bank = {4,4,4,4,4,5}
  self.my_chips = {0,0,0,0,0,0}
  self.opp_chips = {0,0,0,0,0,0}
  self.my_bonuses = {0,0,0,0,0}
  self.opp_bonuses = {0,0,0,0,0}
  self.score = 0
  self.opp_score = 0
  self.my_n_reserved = 0
  self.opp_n_reserved = 0
  self.my_n_chips = 0
  self.opp_n_chips = 0
  self.p1 = true
  for i=1,3 do
    self:deal_noble()
    for i=1,4 do
      slef:deal_card(i)
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

-- 1-90: is card community card?
-- 91-180: is card in deck?
-- 181-270: is card reserved by me?
-- 271-360: is card reserved by opponent?
-- 361-370: is noble available?
-- 371-396:
