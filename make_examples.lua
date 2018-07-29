require"torch"
local socket = require"socket"
require"mcts"
require"nnet"
require"state"
require"cunn"
local json = require"dkjson"
local n_moves = #(require"moves")
local coroutine = coroutine
local coroutine_create = coroutine.create
local coroutine_resume = coroutine.resume
local coroutine_status = coroutine.status
local json_encode = json.encode
local print=print
local random = math.random

return function(conf, gen, best)
  math.randomseed(gen*3 - 2)
  torch.manualSeed(gen*3 - 2)

  local mcts_sims = conf.mcts_sims
  local cpuct = conf.cpuct
  local alpha = conf.alpha
  local epsilon = conf.epsilon
  local temp_threshold = conf.temp_threshold
  local n_eps = conf.n_eps

  local net
  if gen == 1 then
    net = NNet(10)
    net:cuda()
  else
    local net_filename = "net_snapshot_gen"..left_pad(best, 4, "0")..".nn"
    net = torch.load(net_filename, "ascii")
    net:cuda()
    net:evaluate()
  end

  local nnet_eval = coroutine.yield

  local function make_examples()
    --print "starting  new game!!"
    local mcts = MCTS(nnet_eval, mcts_sims, cpuct, alpha, epsilon)
    local state = GameState()
    local examples = {}
    local n_examples = 0
    local episode_step = 0
    while state.result == nil do
      episode_step = episode_step + 1
      --print(episode_step)
      local temp = 1
      if episode_step >= temp_threshold then
        temp = 0
      end
      local pi, valids = mcts:probs(state, temp)
      n_examples = n_examples + 1
      examples[n_examples] = {
        state:as_string(),
        torch.totable(pi),
        valids,
      }
      local move = valids[torch.multinomial(pi, 1)[1]]
      state:apply_move(move)
    end
    for i=1,n_examples do
      local z = state.result
      if i % 2 == 0 then
        z = -z
      end
      examples[i][4] = z
    end
    return examples
  end

  local concurrent_eps = 500
  local eps_so_far = 0
  local coros = {}
  local results = {}
  local all_examples = {}
  for i=1,concurrent_eps do
    coros[i] = coroutine_create(make_examples)
    eps_so_far = eps_so_far + 1
  end

  local ostart = 0
  local input = {}
  for i=1,concurrent_eps do
    input[i] = {}
  end
  local game_in = {}
  local n_coros = #coros


  local cuda_in = torch.Tensor(n_coros, 588):cuda()
  while #all_examples < n_eps do
    local i = 1
    --print("n coros "..n_coros)
    local prev_n_in = #input
    while i <= n_coros do
      local arg = game_in[i] or {}
      local _, __, ___
      _, results[i], __, ___ = coroutine_resume(coros[i], arg[1], arg[2])
      --_, results[i], __, ___ = coroutine.resume(coros[i], torch.Tensor(1227):fill(0.2), random())
      --print(_, results[i], __, ___)
      if coroutine_status(coros[i]) == "suspended" then
        results[i]:dump_to_tensor(input[i])
        i = i + 1
      elseif results[i] == nil then
        coros[i] = coroutine_create(make_examples)
      else
        local res_i = results[i]
        --print(json.encode(results[i]))
        all_examples[#all_examples+1] = results[i]
        if eps_so_far < n_eps then
          coros[i] = coroutine_create(make_examples)
          eps_so_far = eps_so_far + 1
        else
          --print("Retiring a coro")
          coros[i] = coros[n_coros]
          coros[n_coros] = nil
          input[n_coros] = nil
          n_coros = n_coros-1
        end
      end
    end
    if n_coros == 1 then
      input[2] = input[1]
    end
    if n_coros == 0 then
      break
    end
    if prev_n_in ~= #input then
      cuda_in = cuda_in:narrow(1,1,#input)
    end
    local start = socket.gettime()
    print("total "..(start-ostart)*1000)
    cuda_in:copy(torch.Tensor(input))
    local output = net:forward(cuda_in)
    output[1] = output[1]:double()
    output[2] = output[2]:double()
    for i=1,n_coros do
      game_in[i] = {output[1][i], output[2][i][1]}
    end
    local dt = (socket.gettime() - start) * 1000
    print("took "..dt)
    ostart = start
  end

  if gen == 1 then
    torch.save("net_snapshot_gen0.nn", net, "ascii")
  end
  local examples_out = {}
  local nex_out = 0
  for _,examples in ipairs(all_examples) do
    for _,example in ipairs(examples) do
      nex_out = nex_out + 1
      examples_out[nex_out] = json.encode(example)
    end
  end
  examples_out[nex_out+1] = ""
  local sp_filename = "self_play_ep_"..left_pad(gen-1, 4, "0")
  set_file(sp_filename, table.concat(examples_out, "\n"))

end