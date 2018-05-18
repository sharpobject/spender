require"nn"
--require"nninit"
local class = require"class"

local input_sz = 587
local hidden_sz = 587
local output_sz = 1227

local function conv_block()
  local s = nn.Sequential()
  s:add(nn.Linear(input_sz, hidden_sz))
  s:add(nn.BatchNormalization(hidden_sz))
  s:add(nn.ReLU(true))
  return s
end

-- i have no idea what im doing . jpeg
local function res_block()
  local s = nn.Sequential()
  s:add(nn.Linear(hidden_sz, hidden_sz))
  s:add(nn.BatchNormalization(hidden_sz))
  s:add(nn.ReLU(true))
  s:add(nn.Linear(hidden_sz, hidden_sz))
  s:add(nn.BatchNormalization(hidden_sz))

  return nn.Sequential()
    :add(nn.ConcatTable()
      :add(s)
      :add(nn.Identity()))
    :add(nn.CAddTable(true))
    :add(nn.ReLU(true))
end

NNet = class(function(self, n_res_blocks)
  self.trunk = nn.Sequential()
  self.trunk:add(conv_block())
  for i=1,n_res_blocks do
    self.trunk:add(res_block())
  end
  self.policy = nn.Sequential()
  self.policy:add(nn.Linear(hidden_sz, output_sz))
  self.policy:add(nn.BatchNormalization(output_sz))
  self.policy:add(nn.ReLU(true))
  self.policy:add(nn.Linear(output_sz, output_sz))
  self.policy:add(nn.LogSoftMax())

  self.value = nn.Sequential()
  self.value:add(nn.Linear(hidden_sz, hidden_sz))
  self.value:add(nn.BatchNormalization(hidden_sz))
  self.value:add(nn.ReLU(true))
  self.value:add(nn.Linear(hidden_sz, 256))
  self.value:add(nn.ReLU(true))
  self.value:add(nn.Linear(256, 1))
  self.value:add(nn.Tanh(true))
end)

function NNet:forward(s)
  s = self.trunk:forward(s)
  local v = self.value:forward(s)
  local p = self.policy:forward(s)
  return p, v
end