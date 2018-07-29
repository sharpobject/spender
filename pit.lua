require"torch"
require"util"
require"cunn"
require"stridx"
require"state"
require"mcts"
local socket = require"socket"
local coroutine_yield = coroutine.yield
local coroutine_status = coroutine.status
local coroutine_resume = coroutine.resume
local coroutine_create = coroutine.create
local assert = assert
local print = print

return function(config, gen, inc_gen)
  math.randomseed(gen*3)
  torch.manualSeed(gen*3)
  local eval_games = config.eval_games
  local eval_margin = config.eval_margin
  local cpuct = config.cpuct
  local mcts_sims = config.mcts_sims

  local incumbent_filename = "net_snapshot_gen"..left_pad(inc_gen, 4, "0")..".nn"
  local incumbent = torch.load(incumbent_filename, "ascii")
  incumbent:cuda()
  incumbent:evaluate()
  local challenger_filename = "net_snapshot_gen"..left_pad(gen, 4, "0")..".nn"
  local challenger = torch.load(challenger_filename, "ascii")
  challenger:cuda()
  challenger:evaluate()

  local function fight(p1_name, p2_name)
    local function p1_eval(x) return coroutine_yield(x, p1_name) end
    local function p2_eval(x) return coroutine_yield(x, p2_name) end
    local p1_search = MCTS(p1_eval, mcts_sims, cpuct)
    local p2_search = MCTS(p2_eval, mcts_sims, cpuct)
    local state = GameState()
    while state.result == nil do
      local pi, valids = p1_search:probs(state, 0)
      local move = valids[torch.multinomial(pi, 1)[1]]
      state:apply_move(move)
      if state.result then
        assert(state.result == 0)
        return state.result
      end
      pi, valids = p2_search:probs(state, 0)
      move = valids[torch.multinomial(pi, 1)[1]]
      state:apply_move(move)
    end
    if state.result == 0 then
      return 0
    end
    if state.result == 1 then
      return p1_name
    end
    if state.result == -1 then
      return p2_name
    end
    error("hello???")
  end

  local function fight_incumbent_first()
    return fight("incumbent", "challenger")
  end

  local function fight_challenger_first()
    return fight("challenger", "incumbent")
  end

  local coros = {}
  local results = {}
  local game_in = {}
  local n_finished = 0
  local inc_in = {}
  local cha_in = {}
  for i=1,eval_games,2 do
    coros[i] = coroutine_create(fight_incumbent_first)
    coros[i+1] = coroutine_create(fight_challenger_first)
  end
  for i=1,eval_games do
    results[i] = {}
    inc_in[i], cha_in[i] = {}, {}
    for j=1,588 do
      inc_in[i][j], cha_in[i][j] = 0, 0
    end
  end

  local score = 0
  local n_coros = eval_games
  local inc_cuda_in = torch.Tensor(eval_games, 588):cuda()
  local cha_cuda_in = torch.Tensor(eval_games, 588):cuda()
  local net_ins = {incumbent = inc_in, challenger=cha_in}
  while n_finished < eval_games do
    local i = 1
    local inc_n, cha_n = 0, 0
    while i <= n_coros do
      local arg = game_in[i] or {}
      local _, __
      --print("arg !!", arg[1], arg[2])
      _, results[i][1], results[i][2], __ = 
          coroutine_resume(coros[i], arg[1], arg[2])
      --print(_, results[i][1], results[i][2], __)
      if coroutine_status(coros[i]) == "suspended" then
        if results[i][2] == "incumbent" then
          inc_n = inc_n + 1
          results[i][1]:dump_to_tensor(inc_in[inc_n])
        else
          assert(results[i][2] == "challenger")
          cha_n = cha_n + 1
          results[i][1]:dump_to_tensor(cha_in[cha_n])
        end
        i = i + 1
      else
        if results[i][1] == "challenger" then
          score = score + 1
          print("challenger wins")
        elseif results[i][1] == "incumbent" then
          score = score - 1
          print("incumbent wins")
        else
          assert(results[i][1] == 0)
          print("draw")
        end
        print("retiring a coro")
        coros[i] = coros[n_coros]
        coros[n_coros] = nil
        inc_in[n_coros] = nil
        cha_in[n_coros] = nil
        n_coros = n_coros-1
        if n_coros > 0 then
          inc_cuda_in = inc_cuda_in:narrow(1,1,n_coros)
          cha_cuda_in = cha_cuda_in:narrow(1,1,n_coros)
        end
      end
    end
    if n_coros == 0 then
      break
    end
    local start = socket.gettime()
    inc_cuda_in:copy(torch.Tensor(inc_in))
    cha_cuda_in:copy(torch.Tensor(cha_in))
    local output = incumbent:forward(inc_cuda_in)
    output[1] = output[1]:double()
    output[2] = output[2]:double()
    local inc_idx = 0
    for i=1,n_coros do
      if results[i][2] == "incumbent" then
        inc_idx = inc_idx + 1
        game_in[i] = {output[1][inc_idx], output[2][inc_idx][1]}
        --print("set game_in for "..i)
      end
    end
    assert(inc_idx == inc_n)
    output = challenger:forward(inc_cuda_in)
    output[1] = output[1]:double()
    output[2] = output[2]:double()
    local cha_idx = 0
    for i=1,n_coros do
      if results[i][2] == "challenger" then
        cha_idx = cha_idx + 1
        game_in[i] = {output[1][cha_idx], output[2][cha_idx][1]}
        --print("set game_in for "..i)
      end
    end
    assert(cha_idx == cha_n)
    local dt = (socket.gettime() - start) * 1000
    print("took "..dt)
  end

  print("final score !! "..score)
  if score >= eval_margin then
    return
  end
end