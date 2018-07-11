require"state"
require"torch"
require"nnet"
state = GameState()
net = NNet(20)
p,v = net:forward(state:as_tensor():view(-1, 588))
print(torch.exp(p), v)
