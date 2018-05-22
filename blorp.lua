require"state"
require"torch"
require"nn"
require"util"
json=require"dkjson"
a = GameState()
b = GameState(a:as_tensor())
c = GameState(a:as_string())
assert(deepeq(a,b))
assert(deepeq(a,c))
