modimport('keybind')

TUNING.HOTKEY_LIOLOK = {}
local T = TUNING.HOTKEY_LIOLOK
T.handler = {} -- config name to key event handlers

local FN = require('hotkey_liolok')

local Input = GLOBAL.TheInput
local OLD_DOUBLE_CLICK_TIMEOUT = GLOBAL.DOUBLE_CLICK_TIMEOUT

function KeyBind(name, key)
  if T.handler[name] then T.handler[name]:Remove() end
  local function f(_key, down) return (_key == key and down) and FN[name]() end
  T.handler[name] = key and (key >= 1000 and Input:AddMouseButtonHandler(f) or Input:AddKeyHandler(f))

  if name == 'WobyDash' then GLOBAL.DOUBLE_CLICK_TIMEOUT = key and 0 or OLD_DOUBLE_CLICK_TIMEOUT end
end

AddClassPostConstruct('widgets/controls', function(self) T.CONTROLS = self end) -- to check CPMAPanel shown or not

PrefabFiles = { 'generic_blink_marker' } -- Furthest Telepoof target position display | 最远传送目标位置显示
AddComponentPostInit('playercontroller', FN.RefreshBlinkMarker)

AddPrefabPostInit('mermguard', function(inst) return inst:DoTaskInTime(1, FN.HookMermGuard) end)
