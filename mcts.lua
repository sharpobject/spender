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
  self.Qsi = {}
  self.Nsi = {}
  self.Ns = {}
  self.Ps = {}
  self.Es = {}
  self.Vs = {}
  self.nv = {}
  self.rootified = {}
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
      local count = self.Nsi[s][i]
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
    probs[i] = (self.Nsi[s][i] or 0)^(1/temp)
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
    local valids, nvalids = state:list_moves()
    local sum = 0
    for i=1,nvalids do
      sum = sum + ps[valids[i]]
      ps[i] = ps[valids[i]]
    end
    ps = ps:narrow(1, 1, nvalids)
    if sum > 0 then
      ps:div(sum)
    else
      print("All valid moves were masked, and yes I did copy this from alpha-zero-general")
      ps:fill(1/nvalids)
    end
    self.Ps[s] = ps
    self.Vs[s] = valids
    self.nv[s] = nvalids
    self.Ns[s] = 0
    return -v
  end
  local nvalids = self.nv[s]
  local best_score = -1e99
  local bests = {-1}
  local nbests = 1
  local epsilon = self.epsilon
  -- Dirichlet noise
  if is_root and epsilon > 0 and not self.rootified[s] then
    local noise_in = self.noise_in:narrow(1, 1, nvalids)
    noise_in:fill(self.alpha)
    local noise = dist.dir.rnd(noise_in)
    self.Ps[s] = self.Ps[s] * (1-epsilon) + noise * epsilon
    self.rootified[s] = true
  end
  local ns_term = self.Ns[s]
  if ns_term == 0 then
    ns_term = EPS
  end
  local cpuct_term = self.cpuct * sqrt(ns_term)
  for i=1,nvalids do
    local u
    local p = self.Ps[s][i]
    if self.Qsi[s] and self.Qsi[s][i] then
      u = self.Qsi[s][i] + self.cpuct * p * sqrt(self.Ns[s]) / (1+self.Nsi[s][i])
    else
      u = self.cpuct * p * sqrt(self.Ns[s] + EPS)
    end
    if u > best_score then
      best_score = u
      bests = {i}
      nbests = 1
    elseif u == best_score then
      nbests = nbests + 1
      bests[nbests] = i
    end
  end

  local i = uniformly(bests)
  local a = self.Vs[s][i]
  --print("mcts move "..a)
  local next_state = GameState(state)
  next_state:apply_move(a)
  self.current_states[s] = true
  local v = self:search(next_state)
  self.current_states[s] = false
  if self.Qsi[s] and self.Qsi[s][i] then
    self.Qsi[s][i] = (self.Nsi[s][i] * self.Qsi[s][i] + v) / (self.Nsi[s][i] + 1)
    self.Nsi[s][i] = self.Nsi[s][i] + 1
  else
    self.Qsi[s] = self.Qsi[s] or {}
    self.Qsi[s][i] = v
    self.Nsi[s] = self.Nsi[s] or {}
    self.Nsi[s][i] = 1
  end

  self.Ns[s] = self.Ns[s] + 1
  return -v
end
