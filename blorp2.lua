bit_array_to_str = require"bit_array_to_str"
require"state"
require"torch"
state = GameState()
s = state:as_string()
other = GameState(state)
assert(other:as_string() == state:as_string())
print(s, #s)
