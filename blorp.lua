require"state"
require"torch"
require"nn"
require"util"
json=require"dkjson"
a = GameState()
b = GameState(a:as_tensor())
print(a:as_tensor())
assert(deepeq(a,b))
c = GameState(a:as_string())
assert(deepeq(a,c))

require"nnet"

net = NNet(20)
p,v = net:forward(a:as_tensor():view(1,587))

