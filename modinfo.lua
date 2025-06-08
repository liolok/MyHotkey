local function T(en, zh, zht) return ChooseTranslationTable({ en, zh = zh, zht = zht or zh }) end

name = T('Hotkey of liolok', '热键：李皓奇')
author = T('liolok', '李皓奇')
local date = '2025-06-08'
version = date .. '-4' -- for revision in same day
description = T(
  [[󰀏 Tip:
Enable this mod and click "Apply", its key bindings will be way more easy,
and also adjustable in bottom of Settings > Controls page.]],
  [[󰀏 提示：
启用本模组并点击「应用」，它的按键绑定会变得非常方便，
并且也可以在设置 > 控制页面下方实时调整。]]
) .. '\n󰀰 ' .. T('Last updated at: ', '最后更新于：') .. date
api_version = 10
dst_compatible = true
client_only_mod = true
icon = 'modicon.tex'
icon_atlas = 'modicon.xml'
configuration_options = {}

local keyboard = { -- from STRINGS.UI.CONTROLSSCREEN.INPUTS[1] of strings.lua, need to match constants.lua too.
  { 'F1', 'F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8', 'F9', 'F10', 'F11', 'F12', 'Print', 'ScrolLock', 'Pause' },
  { '1', '2', '3', '4', '5', '6', '7', '8', '9', '0' },
  { 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M' },
  { 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z' },
  { 'Escape', 'Tab', 'CapsLock', 'LShift', 'LCtrl', 'LSuper', 'LAlt' },
  { 'Space', 'RAlt', 'RSuper', 'RCtrl', 'RShift', 'Enter', 'Backspace' },
  { 'BackQuote', 'Minus', 'Equals', 'LeftBracket', 'RightBracket' },
  { 'Backslash', 'Semicolon', 'Quote', 'Period', 'Slash' }, -- punctuation
  { 'Up', 'Down', 'Left', 'Right', 'Insert', 'Delete', 'Home', 'End', 'PageUp', 'PageDown' }, -- navigation
}
local numpad = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'Period', 'Divide', 'Multiply', 'Minus', 'Plus' }
local mouse = { '\238\132\130', '\238\132\131', '\238\132\132' } -- Middle Mouse Button, Mouse Button 4 and 5
local key_disabled = { description = 'Disabled', data = 'KEY_DISABLED' }
keys = { key_disabled }
for i = 1, #mouse do
  keys[#keys + 1] = { description = mouse[i], data = mouse[i] }
end
for i = 1, #keyboard do
  for j = 1, #keyboard[i] do
    local key = keyboard[i][j]
    keys[#keys + 1] = { description = key, data = 'KEY_' .. key:upper() }
  end
  keys[#keys + 1] = key_disabled
end
for i = 1, #numpad do
  local key = numpad[i]
  keys[#keys + 1] = { description = 'Numpad ' .. key, data = 'KEY_KP_' .. key:upper() }
end

local function Header(...)
  configuration_options[#configuration_options + 1] =
    { name = T(...), options = { { description = '', data = 0 } }, default = 0 }
end

local function Config(name, label, hover)
  configuration_options[#configuration_options + 1] =
    { name = name, label = label, hover = hover, options = keys, default = 'KEY_DISABLED' }
end

Config('DropLantern', T('Drop Lantern', '丢弃提灯'))
Config(
  'UseBeargerFurSack',
  T('Polar Bearger Bin', '极地熊獾桶'),
  T('Open/Close Polar Bearger Bin', '打开/关闭极地熊獾桶')
)
Config(
  'UseCane',
  T('Walking Cane', '步行手杖'),
  T(
    [[Equip a speed-up hand tool, or switch back to former hand equipment.
Priority: Walking Cane > The Lazy Explorer > Speedy Balloon > Wooden Walking Stick > Thulecite Club]],
    [[装备一个加速的手部工具，或切换回之前的手部装备。
优先级：步行手杖 > 懒人魔杖 > 迅捷气球 > 木手杖 > 铥矿棒]]
  )
)
Config(
  'JumpInOrMigrate',
  T('Jump In / Travel via', '跳入/游历'),
  T(
    'Jump In: Wormhole, Big Slimy Pit, Time Rift\nTravel via: Sinkhole, Stairs',
    '跳入：虫洞、硕大的泥坑、时间裂缝\n游历：洞穴、楼梯'
  )
)
Config(
  'SaveGame',
  T('Save Game', '保存游戏'),
  T('Press twice or hold to confirm action!', '双击或按住以确认操作！')
)
Config(
  'ResetGame',
  T('Reset Game', '重置游戏'),
  T(
    'Restart the server from the last save.\nPress twice or hold to confirm action!',
    '从最后的存档重启服务器。\n双击或按住以确认操作！'
  )
)
Config('ToggleMovementPrediction', T('Toggle Movement Prediction', '切换延迟补偿'))

Header('Willow', '薇洛')
Config(
  'UseLighter',
  T('Willow: Lighter', '薇洛：打火机'),
  T(
    'Equip a Lighter and Absorb Fire, or switch back to former hand equipment.',
    '装备一个打火机并吸火，或切换回之前的手部装备。'
  )
)

Header('Wolfgang', '沃尔夫冈')
Config(
  'UseDumbBell',
  T('Wolfgang: Dumbbell', '沃尔夫冈：哑铃'),
  T(
    [[Equip a Dumbbell and start lifting, or switch back to former hand equipment.
Priority: Gembell > Marbell > Golden Dumbbell > Dumbbell > Icebell > Firebell > Thermbell]],
    [[装备一个哑铃并开始举重，或切换回之前的手部装备。
优先级：宝石 > 大理石 > 黄金 > 石头 > 冰铃 > 火铃 > 热铃]]
  )
)

Header('Maxwell', '麦斯威尔')
Config(
  'UseMagicianToolOrStop',
  T("Maxwell: Magician's Top Hat", '麦斯威尔：魔术师高礼帽'),
  T("Use Magician's Top Hat, or Stop.", '使用魔术师高礼帽，或者停止。')
)

Header('Wigfrid', '薇格弗德')
Config('StrikeOrBlock', T('Wigfrid: Lightning Strike / Block', '薇格弗德：闪电突袭/格挡'))

Header('Winona', '薇诺娜')
Config(
  'UseTeleBrella',
  T('Winona: Portasol', '薇诺娜：传送伞'),
  T(
    'Equip a Portasol and Activate it, or switch back to former hand equipment.',
    '装备一个传送伞并激活，或切换回之前的手部装备。'
  )
)

Header('Wormwood', '沃姆伍德')
Config('MakeLivingLog', T('Wormwood: Grow Living Log', '沃姆伍德：生长活木头'))
Config('MakeLightFlier', T('Wormwood: Transform Bulbous Lightbug', '沃姆伍德：变形球状光虫'))

Header('Wanda', '旺达')
Config('UsePocketWatchHeal', T('Wanda: Activate Ageless Watch', '旺达：激活不老表'))
Config('UsePocketWatchWarp', T('Wanda: Activate Backstep Watch', '旺达：激活倒走表'))
