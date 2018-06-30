jit.off()
local profi=require"profi"
local socket = require"socket"
print(socket.gettime())
profi:setGetTimeMethod(socket.gettime)
require"mcts"
require"nnet"
require"state"
local n_moves = #(require"moves")
local coroutine = coroutine
local args = {
  n_steps = 1000,
  n_eps = 2000,
  temp_threshold = 250,
  eval_threshold = 220,
  eval_games = 400,
  steps_for_history = 20,
  cpuct = 1,
  alpha = 0.3,
  epsilon = 0.25,
  minibatch_size = 32,
  n_minibatches = 1000,
  momentum = 0.9,
  l2 = 0.0001,
  mcts_sims = 100,
}

local net = NNet(1)

local function make_examples()
  --[[local nnet_eval = function(state)
    local t = state:as_tensor():view(1,587)
    local s = net:forward(t)
    return torch.exp(s[1][1]), s[2][1][1]
  end--]]
  print "starting  new game!!"
  local nnet_eval = coroutine.yield
  local mcts = MCTS(nnet_eval, args.mcts_sims, args.cpuct, args.alpha, args.epsilon)
  local state = GameState()
  local examples = {}
  local n_examples = 0
  local episode_step = 0
  local prev_move = 0
  while state.result == nil and episode_step ~= 10 do
    episode_step = episode_step + 1
    print(episode_step)
    local temp = 1
    if episode_step >= args.temp_threshold then
      temp = 0
    end
    local pi = mcts:probs(state)
    n_examples = n_examples + 1
    examples[n_examples] = {
      state:as_string(),
      torch.totable(pi),
      state.p1,
    }
    local move = torch.multinomial(pi, 1)[1]
    state:apply_move(move)
    if move == 31 and prev_move == 31 then
      state.result = 0
    end
    prev_move = move
  end
  for i=1,n_examples do
    local z = state.result or 3
    if i % 2 == 0 then
      z = -z
    end
    examples[i][3] = z
  end
  return examples
end

local concurrent_eps = 100
local eps_so_far = 0
local coros = {}
local results = {}
local all_examples = {}
for i=1,concurrent_eps do
  coros[i] = coroutine.create(make_examples)
  eps_so_far = eps_so_far + 1
end

profi:start()
if true then
local ostart = 0
for qqqqq=1,10 do
  local input = {}
  local i = 1
  local n_coros = #coros
  while i <= n_coros do
    local arg = results[i] or {}
    local _, __, ___
    _, results[i], __, ___ = coroutine.resume(coros[i], arg[1], arg[2])
    --print(_, results[i], __, ___)
    if coroutine.status(coros[i]) == "suspended" then
      input[i] = results[i]:as_array()
      i = i + 1
    else
      all_examples[#all_examples+1] = results[i]
      if eps_so_far < args.n_eps then
        coros[i] = coroutine.create(make_examples)
      else
        coros[i] = coros[n_coros]
        coros[n_coros] = nil
        n_coros = n_coros-1
      end
    end
  end
  if #input == 1 then
    input[2] = input[1]
  end
  local start = socket.gettime()
  print("total "..(start-ostart)*1000)
  local output = net:forward(torch.Tensor(input))
  for i=1,n_coros do
    results[i] = {torch.exp(output[1][i]), output[2][i][1]}
  end
  local dt = (socket.gettime() - start) * 1000
  print("took "..dt)
  ostart = start
end
else
  make_examples()
end
profi:stop()
profi:writeReport("profilereport.txt")

local json=require"dkjson"
print(json.encode(all_examples))