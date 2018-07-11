local class = require"class"
require"state"
require"util"
require"torch"
local dist = require"distributions"
local moves = require"moves"
local sqrt = math.sqrt
local random = math.random
local string_sub = string.sub
local pairs = pairs
require"table.new"
local tb_new = table.new or function() return {} end

local nmoves = #moves
local EPS = 1e-8

local weakmt = { __mode = 'v' }

MCTS = class(function(self, nnet_eval, nsims, cpuct, alpha, epsilon)
  self.nnet_eval = nnet_eval
  self.nsims = nsims
  self.cpuct = cpuct
  self.epsilon = epsilon
  self.noise_in = torch.Tensor(nmoves)
  self.noise_in:fill(alpha)
  self.nodes = setmetatable({}, weakmt)
  self.gamestate = GameState()
end)

function MCTS:rootify(node)
  local epsilon = self.epsilon
  local nvalids = node.nvalids
  node.rootified = true
  if epsilon > 0 then
    local noise_in = self.noise_in:narrow(1, 1, nvalids)
    local noise = dist.dir.rnd(noise_in):mul(epsilon)
    local P = node.P
    local rest = 1-epsilon
    for i=1,nvalids do
      P[i] = P[i] * rest + noise[i]
    end
  end
end

function MCTS:probs(state, temp)
  temp = temp or 1
  local s = state:as_string()
  local node = self.nodes[s]
  local gamestate = self.gamestate
  for _=1,self.nsims do
    if node and not node.rootified then
      self:rootify(node)
    end
    gamestate:from_state(state)
    _, node = self:search(gamestate, s)
    self.root_node = node
  end
  local valids = node.valids
  local nvalids = node.nvalids
  local Ni = node.Ni
  if temp == 0 then
    local bests = {}
    local best_visit_count = 0
    local nbests = 0
    for i=1,nvalids do
      local count = Ni[i]
      if count > best_visit_count then
        bests = {}
        nbests = 1
        best_visit_count = count
        bests[nbests] = i
      end
      if count >= best_visit_count then
        nbests = nbests + 1
        bests[nbests] = i
      end
    end
    local probs = torch.Tensor(nvalids):fill(0)
    for i=1,nbests do
      probs[bests[i]] = 1--/nbests
    end
    return probs, valids
  elseif temp == 1 then
    local probs = torch.Tensor(Ni)
    --local sum = 0
    for i=1,nvalids do
      local prob = Ni[i]
      probs[i] = prob
      --sum = sum + prob
    end
    --probs:div(sum)
    return probs, valids
  else
    error("I don't actually support temperature other than 1 or 0 thanks")
  end
end

function MCTS:search(state, s, idx)
  if state.result then
    return -state.result
  end
  local node = self.nodes[s]
  if node == nil then
    node = {
      current_visits = 0
    }
    self.nodes[s] = node
  end
  if node.P == nil or node.current_visits > 0 then
    local ps, v = self.nnet_eval(state)
    local valids, nvalids = state:list_moves()
    local tab = tb_new(nvalids, 0)
    local sum = 0
    for i=1,nvalids do
      local element = ps[valids[i]]
      sum = sum + element
      tab[i] = element
    end
    if sum > 0 then
      for i=1,nvalids do
        tab[i] = tab[i] / sum
      end
    else
      print("All valid moves were masked, and yes I did copy this from alpha-zero-general")
      for i=1,nvalids do
        tab[i] = 1/nvalids
      end
    end
    node.P = tab
    node.valids = valids
    node.nvalids = nvalids
    node.N = 0
    node.results = {[0]=-v}
    return -v, node
  end
  if idx ~= nil and idx <= node.N then
    return node.results[idx], node
  end
  local nvalids = node.nvalids
  local P = node.P
  local Qi = node.Qi
  local Ni = node.Ni
  local Ns = node.Ns
  if not Qi then
    Qi, Ni = tb_new(nvalids, 0), tb_new(nvalids, 0)
    Ns = {}
    for i=1,nvalids do
      Qi[i] = 0
      Ni[i] = 0
    end
    node.Qi = Qi
    node.Ni = Ni
    node.Ns = Ns
    node.succ = {}
  end
  local best_score = -1e99
  local best = -1
  local nbests = 1
  local n_term = node.N
  if n_term == 0 then
    n_term = EPS
  end
  local cpuct_term = self.cpuct * sqrt(n_term)
  for i=1,nvalids do
    local p = P[i]
    local u = Qi[i] + p * cpuct_term / (1+Ni[i])
    if u > best_score then
      best_score = u
      best = i
      nbests = 1
    elseif u == best_score then
      nbests = nbests + 1
      if random() < 1/nbests then
        best = i
      end
    end
  end

  state:apply_move(node.valids[best])
  local next_s = state:as_string()
  local next_s_visits = (Ns[next_s] or 0)
  node.current_visits = node.current_visits + 1
  local v, next_node = self:search(state, next_s, next_s_visits)
  node.current_visits = node.current_visits - 1
  Ns[next_s] = next_s_visits + 1
  Qi[best] = (Ni[best] * Qi[best] + v) / (Ni[best] + 1)
  Ni[best] = Ni[best] + 1
  node.N = node.N + 1
  node.results[node.N] = -v
  if next_node then
    node.succ[next_node] = true
  end
  return -v, node
end
