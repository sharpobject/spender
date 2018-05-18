bit_array_to_str = require"bit_array_to_str"
require"state"
require"torch"
state = GameState()
t = state:as_array()
s = bit_array_to_str(t)
print(s, #s)