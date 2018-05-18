require"state"
require"torch"
require"nn"
require"util"
json=require"dkjson"
a = GameState()
b = GameState(a:as_tensor())
print(json.encode(a))
print(json.encode(b))
assert(deepeq(a,b))