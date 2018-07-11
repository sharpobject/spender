require"nn"
--require"nninit"
local class = require"class"

local input_sz = 588
local hidden_sz = 588
local output_sz = 1227
local value_narrow_sz = 256

local function conv_block()
  local s = nn.Sequential()
  s:add(nn.Linear(input_sz, hidden_sz, false))
  s:add(nn.BatchNormalization(hidden_sz))
  s:add(nn.ReLU(true))
  return s
end

-- i have no idea what im doing . jpeg
local function res_block()
  local s = nn.Sequential()
  s:add(nn.Linear(hidden_sz, hidden_sz, false))
  s:add(nn.BatchNormalization(hidden_sz))
  s:add(nn.ReLU(true))
  s:add(nn.Linear(hidden_sz, hidden_sz, false))
  s:add(nn.BatchNormalization(hidden_sz))

  return nn.Sequential()
    :add(nn.ConcatTable()
      :add(s)
      :add(nn.Identity()))
    :add(nn.CAddTable(true))
    :add(nn.ReLU(true))
end

NNet = function(n_res_blocks)
  local net = nn.Sequential()
  net:add(conv_block())
  for _=1,n_res_blocks do
    net:add(res_block())
  end
  local policy = nn.Sequential()
  policy:add(nn.Linear(hidden_sz, output_sz, false))
  policy:add(nn.BatchNormalization(output_sz))
  policy:add(nn.ReLU(true))
  policy:add(nn.Linear(output_sz, output_sz))
  policy:add(nn.LogSoftMax())

  local value = nn.Sequential()
  value:add(nn.Linear(hidden_sz, hidden_sz, false))
  value:add(nn.BatchNormalization(hidden_sz))
  value:add(nn.ReLU(true))
  value:add(nn.Linear(hidden_sz, value_narrow_sz))
  value:add(nn.ReLU(true))
  value:add(nn.Linear(value_narrow_sz, 1))
  value:add(nn.Tanh(true))

  local concat = nn.ConcatTable()
  concat:add(policy)
  concat:add(value)
  net:add(concat)
  return net
end