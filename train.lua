local make_examples = require"make_examples"
local learn = require"learn"
local pit = require"pit"
local json = require"dkjson"
local config = {
  n_steps = 1000,       -- Aim high! Train 1000 generations of models
  n_eps = 2000,         -- 2000 games of self play per generation
  mcts_sims = 100,      -- Searches per position in mcts
  temp_threshold = 24,  -- After 24 moves, pick top move only in self play
  cpuct = 1,            -- Exploration vs exploitation in mcts
  alpha = 0.3,          -- For dirichlet noise in self-play
  epsilon = 0.25,       -- For dirichlet noise in self-play
  example_eps = 20,     -- How many gens of self-play to learn from
  minibatch_size = 2048,-- For learn step
  n_minibatches = 1000, -- For learn step
  momentum = 0.9,       -- For sgd with momentum
  l2 = 1e-4,            -- weight decay/l2 regularization
  pit_games = 400,      -- How many games to play in pit step
  pit_margin = 20,      -- Required margin of victory for promotion
  lr_schedule = {
    1e-2,
    [401] = 1e-3,
    [601] = 1e-4,
  }
}
local best = 0
local step = 1
if file_exists("best_step") then
  local junk = json.decode(file_contents("best_step"))
  best = junk[1]
  step = junk[2]
end
for i=step,config.n_steps do
  set_file("best_step", json.encode({best, step}))
  make_examples(config, i, best)
  learn(config, i)
  best = pit(config, i, best)
end