require"util"
require"torch"
require"cunn"
require"state"
require"stridx"
require"optim"
local socket = require"socket"
local json = require"dkjson"
math.randomseed(1)
torch.manualSeed(1)

local minibatch_size = 2048
local n_minibatches = 1000
local needed_examples = n_minibatches * minibatch_size

local str = file_contents("self_play_ep_0000")
local lines = str:split("\n")
local examples = {}
local nex = 0
for _,line in ipairs(lines) do
  if line[1] == "[" then
    nex = nex + 1
    examples[nex] = json.decode(line)
  end
end


print("read "..#examples.." examples")
if #examples < needed_examples then
  local t = {}
  local n = 0
  while n < needed_examples do
    shuffle(examples)
    for i=1,#examples do
      n = n+1
      t[n] = examples[i]
    end
  end
  examples = t
end
print("using "..#examples.." examples")

local net = torch.load("net_snapshot_gen0.nn", "ascii")
net:cuda()

print("loaded")

print("let's learn motherfucker!!!")
local config = {
  learningRate = 1e-2,
  momentum = 0.9,
  dampening = 0,
  nesterov = true,
  weightDecay = 1e-4,
}

local c = nn.ParallelCriterion(false)
local kld = nn.DistKLDivCriterion()
local mse = nn.MSECriterion()
c:add(kld, 1227)
c:add(mse)
c:cuda()


local input = torch.Tensor(minibatch_size, 588):cuda()
local output = {
  torch.Tensor(minibatch_size, 1227):cuda(),
  torch.Tensor(minibatch_size, 1):cuda()
}
--net:double()
--c:double()
--input = input:double()
--output[1] = output[1]:double()
--output[2] = output[2]:double()
local params, gradParams = net:getParameters()
local intab = {}
local outptab = {}
local outvtab = {}
for i=1,minibatch_size do
  intab[i] = {}
  for j=1,588 do
    intab[i][j] = 0
  end
  outptab[i] = {}
  for j=1,1227 do
    outptab[i][j] = 0
  end
  outvtab[i] = {0}
end

local gamestate = GameState()
local ex_idx = 1
local function prep_input(n)
  for i=1,n do
    local example = examples[ex_idx]
    ex_idx = ex_idx + 1
    gamestate:from_string(example[1])
    local otherstate = GameState(example[1])
    if not deepeq(otherstate, gamestate) then
      print(example[1])
      print(json.encode(gamestate))
      print(json.encode(otherstate))
      error("fucker")
    end
    gamestate:dump_to_tensor(intab[i])
    if #intab[i] ~= 588 then
      print(example[1])
    end
    local ps, idxs, v = example[2], example[3], example[4]
    local total = 0
    for j=1,#ps do
      total = total + ps[j]
    end
    for j=1,1227 do
      outptab[i][j] = 0
    end
    for j=1,#ps do
      outptab[i][idxs[j]] = ps[j] / total
    end
    outvtab[i][1] = v
  end
  input:copy(torch.Tensor(intab))
  output[1]:copy(torch.Tensor(outptab))
  output[2]:copy(torch.Tensor(outvtab))
  --output[2]:narrow(1,1,n):copy(torch.Tensor(outvtab):narrow(1,1,n))
end

local function feval(params)
  gradParams:zero()
  local n = minibatch_size
  prep_input(n)
--  local batch_inputs = input:narrow(1,1,n)
--  local batch_labels = {output[1]:narrow(1,1,n), output[2]:narrow(1,1,n)}
  local batch_inputs = input
  local batch_labels = output
  local outputs = net:forward(batch_inputs)
  local loss = c:forward(outputs, batch_labels)
  local dloss_doutputs = c:backward(outputs, batch_labels)
  net:backward(batch_inputs, dloss_doutputs)
  print("loss !! "..loss.." "..mse.output.." "..kld.output*1227)
  return loss, gradParams
end


for i=1,n_minibatches do
  local start = socket.gettime()
  optim.sgd(feval, params, config)
  print("took "..(socket.gettime()-start))
end

torch.save("net_snapshot_gen0001.nn", net, "ascii")
