local pit = require"pit"
local config = {
  eval_margin = 20,
  eval_games = 400,
  cpuct = 1,
  mcts_sims = 100,
}
pit(config, 1, 1)