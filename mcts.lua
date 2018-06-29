local class = require"class"
require"state"
require"util"
require"torch"
local dist = require"distributions"
local moves = require"moves"
local sqrt = math.sqrt

local nmoves = #moves
local EPS = 1e-8

MCTS = class(function(self, nnet_eval, nsims, cpuct, alpha, epsilon)
  self.nnet_eval = nnet_eval
  self.nsims = nsims
  self.cpuct = cpuct
  self.alpha = alpha
  self.epsilon = epsilon
  self.noise_in = torch.Tensor(nmoves)
  self.Qsa = {}
  self.Nsa = {}
  self.Ns = {}
  self.Ps = {}
  self.Es = {}
  self.Vs = {}
end)

function MCTS:probs(state, temp)
  self.current_states = {}
  temp = temp or 1
  for _=1,self.nsims do
    self:search(state, true)
  end
  local s = state:as_string()
  if temp == 0 then
    local bests = {}
    local nbests = 0
    local best_count = 0
    for i=1,nmoves do
      local count = self.Nsa[s][i]
      if count > best_count then
        bests = {}
        nbests = 1
        best_count = count
        bests[nbests] = i
      end
      if count >= best_count then
        nbests = nbests + 1
        bests[nbests] = i
      end
    end
    local probs = torch.Tensor(nmoves)
    --for i=1,nmoves do
    --  probs[i] = 0
    --end
    for i=1,nbests do
      probs[bests[i]] = 1/nbests
    end
    return probs
  end
  local probs = torch.Tensor(nmoves)
  local sum = 0
  for i=1,nmoves do
    probs[i] = (self.Nsa[s][i] or 0)^(1/temp)
    sum = sum + probs[i]
  end
  for i=1,nmoves do
    probs[i] = probs[i] / sum
  end
  return probs
end

function MCTS:search(state, is_root)
  local s = state:as_string()
  if self.Es[s] == nil then
    self.Es[s] = state.result
  end
  if self.Es[s] ~= nil then
    return -self.Es[s]
  end
  if self.Ps[s] == nil or self.current_states[s] then
    local ps, v = self.nnet_eval(state)
    self.Ps[s] = ps
    local valids = state:list_moves()
    local sum = 0
    for i=1,nmoves do
      if valids[i] then
        sum = sum + ps[i]
      else
        ps[i] = 0
      end
    end
    if sum > 0 then
      for i=1,nmoves do
        ps[i] = ps[i] / sum
      end
    else
      print("All valid moves were masked, and yes I did copy this from alphago_zero_general")
      local nvalid = 0
      for _,_ in pairs(valids) do
        nvalid = nvalid + 1
      end
      for k,_ in pairs(valids) do
        ps[k] = 1/nvalid
      end
    end
    self.Vs[s] = valids
    self.Ns[s] = 0
    return -v
  end
  local valids = self.Vs[s]
  local best_score = -1e99
  local bests = {-1}
  local nbests = 1
  local epsilon = self.epsilon
  local noise = nil
  -- Dirichlet noise
  if is_root and epsilon > 0 then
    local noise_in = self.noise_in
    for i=1,nmoves do
      noise_in[i] = valids[i] and self.alpha or 0
    end
    noise = dist.dir.rnd(noise_in) * epsilon
  end
  for a=1,nmoves do
    if valids[a] then
      local u
      local p = self.Ps[s][a]
      if noise then
        p = (1-epsilon) * p + epsilon * noise[a]
      end
      if self.Qsa[s] and self.Qsa[s][a] then
        u = self.Qsa[s][a] + self.cpuct * p * sqrt(self.Ns[s]) / (1+self.Nsa[s][a])
      else
        u = self.cpuct * p * sqrt(self.Ns[s] + EPS)
      end
      if u > best_score then
        best_score = u
        bests = {a}
        nbests = 1
      elseif u == best_score then
        nbests = nbests + 1
        bests[nbests] = a
      end
    end
  end

  local a = uniformly(bests)
  --print("mcts move "..a)
  local next_state = GameState(state)
  next_state:apply_move(a)
  self.current_states[s] = true
  local v = self:search(next_state)
  self.current_states[s] = false
  if self.Qsa[s] and self.Qsa[s][a] then
    self.Qsa[s][a] = (self.Nsa[s][a] * self.Qsa[s][a] + v) / (self.Nsa[s][a] + 1)
    self.Nsa[s][a] = self.Nsa[s][a] + 1
  else
    self.Qsa[s] = self.Qsa[s] or {}
    self.Qsa[s][a] = v
    self.Nsa[s] = self.Nsa[s] or {}
    self.Nsa[s][a] = 1
  end

  self.Ns[s] = self.Ns[s] + 1
  return -v
end
