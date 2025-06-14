local function T(en, zh, zht) return ChooseTranslationTable({ en, zh = zh, zht = zht or zh }) end

name = T('Hotkey of liolok', '热键：李皓奇')
author = T('liolok', '李皓奇')
local date = '2025-06-14'
version = date .. '' -- for revision in same day
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
优先级：步行手杖 > 懒人魔杖 > 木手杖 > 铥矿棒 > 迅捷气球]]
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
  'ToggleUmbrella',
  T('Open/Close Umbralla', '打开/关闭暗影伞'),
  T(
    'If no Umbralla on ground, will try to drop one and open.',
    '如果地上没有暗影伞，会尝试丢下一个并打开。'
  )
)
Config(
  'Murder',
  T('Murder', '谋杀'),
  T('Will ignore Scorching Sunfish & Ice Bream', '会略过炽热太阳鱼和冰鲷鱼')
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
Config('DropBernie', T('Willow: Drop Bernie', '薇洛：丢弃伯尼'))
Config('FireThrow', T('Willow: Flame Cast', '薇洛：火焰投掷'))
Config('FireBurst', T('Willow: Combustion', '薇洛：燃烧术'))
Config('FireBall', T('Willow: Fire Ball', '薇洛：火球术'))
Config('FireFrenzy', T('Willow: Burning Frenzy', '薇洛：狂热焚烧'))
Config('LunarOrShadowFire', T('Willow: Lunar/Shadow Fire', '薇洛：月焰/暗焰'))

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

Header('Abigail', '阿比盖尔')
Config(
  'UseFastRegenElixir',
  T('Abigail: Apply Spectral Cure-All', '阿比盖尔：使用灵魂万灵药'),
  T('Will open Picnic Casket first', '会先打开野餐盒')
)
Config('SummonOrRecallAbigail', T('Abigail: Summon / Recall', '阿比盖尔：召唤/解除召唤'))
Config('CommuneWithSummoned', T('Abigail: Rile Up / Soothe', '阿比盖尔：激怒/安慰'))
Config('AbigailEscape', T('Abigail: Escape', '阿比盖尔：逃离'))
Config('AbigailAttackAt', T('Abigail: Attack At', '阿比盖尔：攻击'))
Config('AbigailHauntAt', T('Abigail: Haunt At', '阿比盖尔：作祟'))
Config('AbigailScare', T('Abigail: Scare', '阿比盖尔：惊吓'))

Header('Maxwell', '麦斯威尔')
Config(
  'UseMagicianToolOrStop',
  T("Maxwell: Magician's Top Hat", '麦斯威尔：魔术师高礼帽'),
  T("Use Magician's Top Hat, or Stop.", '使用魔术师高礼帽，或者停止。')
)
Config('ShadowWorker', T('Maxwell: Shadow Servant', '麦斯威尔：暗影仆人'))
Config('ShadowProtector', T('Maxwell: Shadow Duelist', '麦斯威尔：暗影角斗士'))
Config('ShadowTrap', T('Maxwell: Shadow Sneak', '麦斯威尔：暗影陷阱'))
Config('ShadowPillars', T('Maxwell: Shadow Prison', '麦斯威尔：暗影囚牢'))

Header('Wigfrid', '薇格弗德')
Config(
  'UseBattleSong',
  T('Wigfrid: Sing Battle Call', '薇格弗德：吟唱战斗号子'),
  T('Will open Battle Call Canister first', '会先打开战斗号子罐')
)
Config('StrikeOrBlock', T('Wigfrid: Lightning Strike / Block', '薇格弗德：闪电突袭/格挡'))

Header('Webber', '韦伯')
Config(
  'UseSpiderWhistle',
  T('Webber: Whistle', '韦伯：口哨'),
  T(
    "Blow to Herd Spiders, or craft a whistle if don't have one.",
    '吹哨召集蜘蛛，如果没有的话会制作一个口哨。'
  )
)

Header('Winona', '薇诺娜')
Config(
  'UseTeleBrella',
  T('Winona: Portasol', '薇诺娜：传送伞'),
  T(
    'Equip a Portasol and Activate it, or switch back to former hand equipment.',
    '装备一个传送伞并激活，或切换回之前的手部装备。'
  )
)
Config('CatapultWakeUp', T('Catapult: Arm', '投石机：武装'))
Config('CatapultBoost', T('Catapult: Barrage', '投石机：齐射'))
Config('CatapultVolley', T('Catapult: Target', '投石机：瞄准'))
Config('CatapultElementalVolley', T('Catapult: Planar Strike', '投石机：位面袭击'))

Header('Wormwood', '沃姆伍德')
Config('MakeLivingLog', T('Wormwood: Grow Living Log', '沃姆伍德：生长活木头'))
Config('MakeLightFlier', T('Wormwood: Transform Bulbous Lightbug', '沃姆伍德：变形球状光虫'))

Header('Woby', '沃比')
Config('WobyRummage', T('Woby: Open/Close', '沃比：打开/关闭'))
Config('WobyCourier', T('Woby: Deliver', '沃比：运送'))
Config(
  'WobyDash',
  T('Woby: Dash', '沃比：冲刺'),
  T('Bind this key Will disable vanilla double tapping dash.', '绑定此键会禁用原生的双击冲刺。')
)

Header('Wanda', '旺达')
Config('UsePocketWatchHeal', T('Wanda: Activate Ageless Watch', '旺达：激活不老表'))
Config('UsePocketWatchWarp', T('Wanda: Activate Backstep Watch', '旺达：激活倒走表'))
