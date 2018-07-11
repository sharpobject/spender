require"torch"
require"nnet"
local socket = require "socket"
require"state"
local os = os
for batch_size=10,10 do
  local n = NNet(1)
  local c = nn.ParallelCriterion(false)
  local kld = nn.DistKLDivCriterion()
  local mse = nn.MSECriterion()
  c:add(kld, 1227)
  c:add(mse)
  local nr = 100
  --local batch_size = 1
  local dog
  --for batch_size = 1,1 do
    local target = {torch.Tensor(batch_size,1227), torch.Tensor(batch_size,1)}
    for i=1,batch_size do
      target[1][i][1] = 1
      target[2][i][1] = 1
      for j=2,1227 do
        target[1][i][j] = 0
      end
    end
    local input = torch.Tensor(batch_size, 588)
    dog = input
    local start = socket.gettime()
    for i=1,nr do
      print(i)
      for j=1,batch_size do
        GameState():dump_to_tensor(input[j])
      end
      c:forward(n:forward(input), target)
      print(kld.output * 1227, mse.output, torch.exp(n.output[1][1][1]), n.output[2][1][1])
      n:zeroGradParameters()
      n:backward(input, c:backward(n.output, target))
      n:updateParameters(0.01*10/batch_size)
    end
    local endt = socket.gettime()
    local dt = endt-start
    print(batch_size, dt, dt / (nr* batch_size), (nr*batch_size)/dt)
  --end
  n:evaluate()
  local game = GameState()
  for i=1,batch_size do
    local input = torch.Tensor(i,588)
    for j=1,i do
      game:dump_to_tensor(input[j])
    end
    local target = {torch.Tensor(i,1227), torch.Tensor(i,1)}
    for j=1,i do
      target[1][j][1] = 1
      target[2][j][1] = 1
      for k=2,1227 do
        target[1][j][k] = 0
      end
    end
    --for j=1,588 do
    --  input[1][j] = dog[i][j]
    --end

    --print(input)
    c:forward(n:forward(input), target)
    print(i, kld.output*1227, mse.output)
    print("hi"..i,torch.exp(n.output[1][1][1]), n.output[2][1][1])
  end
  --[[input = GameState():as_tensor():view(1,588)
  blah = n.trunk:forward(input)
  print(torch.exp(n.trunk.output[1][1][1]), n.trunk.output[2][1][1])
  print(torch.exp(blah[1][1][1]))
  print(blah[2])--]]
end