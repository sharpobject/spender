require"nnet"
require"mcts"

local foo = NNet(20)
function nnet_eval(state)
  local t = state:as_tensor():view(1,587)
  local s = foo:forward(t)
  return torch.exp(s[1][1]), s[2][1][1]
end

mcts = MCTS(nnet_eval, 100, 1, .3, .25)
blorp = mcts:probs(GameState())
print(blorp:view(1,-1))