local moves = require"moves"
-- For a move to be legal, must have state_mask & move_mask == move_mask
-- (among other things)
-- Mask layout:
-- WWBBRRGGUUWWWBBBRRRGGGUUU***
-- 1  take 11^      return
local bit = require"bit"
local lshift = bit.lshift
local bor = bit.bor
local masks = {}
for i=1,37 do
  local move = moves[i]
  local mask = 0
  for j=1,5 do
    if move[j] >= 1 then
      mask = bor(mask, lshift(1, 2*j - 2))
    end
    if move[j] >= 2 then
      mask = bor(mask, lshift(1, 2*j - 1))
    end
  end
  masks[i] = mask
end

return masks