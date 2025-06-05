modimport('keybind')

local Input = GLOBAL.TheInput

local FN = require('hotkey_liolok')

local handler = {} -- config name to key event handlers

function KeyBind(name, key)
  if handler[name] then handler[name]:Remove() end
  local function f(_key, down) return (_key == key and down) and FN[name]() end
  handler[name] = key and (key >= 1000 and Input:AddMouseButtonHandler(f) or Input:AddKeyHandler(f))
end
