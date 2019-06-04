require"nnet"
require"state"
local print = print
local clock = os.clock
local net = NNet(20)
local states = {}
local batch_size = 128
local input = torch.Tensor(batch_size,313)
local minibatch = true
for i=1,batch_size do
  states[i] = GameState()
  states[i]:dump_to_tensor(input[i])
end
if not minibatch then
  input={}
  for i=1,32 do
    input[i] = states[i]:as_tensor():view(1,-1)
  end
end
local p,v
local st,et
local total = 0
for i=1,10 do
  st = clock()
  if minibatch then
    p,v = unpack(net:forward(input))
  else
    for i=1,32 do
      p,v = unpack(net:forward(input[i]))
    end
  end
  et = clock()
  total = total + et - st
  print(total)
end
print(p)
print(v)
print(total)

-- 12.958667s to do 100x32 with size 32 minibatch