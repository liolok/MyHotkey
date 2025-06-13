modimport('keybind')

local handler = {} -- config name to key event handlers

local FN = require('hotkey_liolok')

local Input = GLOBAL.TheInput
local OLD_DOUBLE_CLICK_TIMEOUT = GLOBAL.DOUBLE_CLICK_TIMEOUT

function KeyBind(name, key)
  if handler[name] then handler[name]:Remove() end
  local function f(_key, down) return (_key == key and down) and FN[name]() end
  handler[name] = key and (key >= 1000 and Input:AddMouseButtonHandler(f) or Input:AddKeyHandler(f))

  if name == 'WobyDash' then GLOBAL.DOUBLE_CLICK_TIMEOUT = key and 0 or OLD_DOUBLE_CLICK_TIMEOUT end
end
