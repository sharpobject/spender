require"state"
require"torch"
require"nnet"
state = GameState()
net = NNet(20)
p,v = unpack(net:forward(state:as_tensor():view(-1, 313)))
print(torch.exp(p), v)
