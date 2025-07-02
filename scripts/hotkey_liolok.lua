local fn = {}

--------------------------------------------------------------------------------
-- Utility Function | 工具函数

local is_in_cd = {} -- cooldown | 冷却
local function IsInCD(key, cooldown)
  if is_in_cd[key] then return true end
  is_in_cd[key] = ThePlayer and ThePlayer:DoTaskInTime(cooldown or 1, function() is_in_cd[key] = false end)
end

-- shortcut for code like `ThePlayer and ThePlayer.replica and ThePlayer.replica.inventory`
local function Get(head_node, ...)
  local current_node = head_node
  for _, key in ipairs({ ... }) do
    if not current_node then return end

    local next_node = current_node[key]
    if type(next_node) == 'function' then -- for code like `ThePlayer.replica.inventory:GetActiveItem()`
      current_node = next_node(current_node) -- this could be `false`/`nil` so avoid assigning with `and or`
    else
      current_node = next_node
    end
  end
  return current_node
end

local function IsPlaying(character)
  if not (TheWorld and ThePlayer) then return end -- in game, yeah
  if character and ThePlayer.prefab ~= character then return end -- optionally check for right character
  if ThePlayer.HUD and ThePlayer.HUD:HasInputFocus() then return end -- typing or in some menu
  return true -- it's all good, man
end

local function HasSkill(skill)
  if not skill then return true end

  local skill_tree = Get(ThePlayer, 'components', 'skilltreeupdater')
  if not skill_tree then return end

  if type(skill) == 'string' then return skill_tree:IsActivated(skill) end

  for _, v in ipairs(type(skill) == 'table' and skill or {}) do
    if skill_tree:IsActivated(v) then return true end
  end
end

local function IsRiding() return Get(ThePlayer, 'replica', 'rider', 'IsRiding') end

--------------------------------------------------------------------------------
-- Inventory Item | 格子物品

local function Inv() return Get(ThePlayer, 'replica', 'inventory') end

local function FindInvItemBy(IsRight) -- find right item in inventory | 在所有格子里找正确的物品
  local inventory = Inv()
  if not (inventory and type(IsRight) == 'function') then return end

  -- try to put item on cursor back into slot | 尝试将光标上的物品放回格子里
  if inventory:GetActiveItem() then inventory:ReturnActiveItem() end

  -- all equipped items | 所有已装备物品
  for _, item in pairs(inventory:GetEquips()) do
    if IsRight(item) then return item end
  end

  -- all slots of all opened containers | 所有打开的容器的所有格子
  for open_container in pairs(inventory:GetOpenContainers()) do
    local container = Get(open_container, 'replica', 'container')
    if container then
      for slot = 1, container:GetNumSlots() do
        local item = container:GetItemInSlot(slot)
        if IsRight(item) then return item end
      end
    end
  end

  -- all slots of inventory bar | 物品栏的所有格子
  for slot = 1, inventory:GetNumSlots() do
    local item = inventory:GetItemInSlot(slot)
    if IsRight(item) then return item end
  end
end

local function Find(prefab, filter)
  return FindInvItemBy(function(item)
    if not (item and item.prefab == prefab) then return end
    if not filter then return true end -- optional extra filter
    if type(filter) == 'function' then return filter(item) end
    if type(filter) == 'string' then return item:HasTag(filter) end
    if type(filter) == 'table' then
      if filter.no_tags and item:HasOneOfTags(filter.no_tags) then return end
      return true
    end
  end)
end

local function FindFueled(prefab) return Find(prefab, { no_tags = 'fueldepleted' }) end

local function FindPrefabs(...)
  for _, prefab in ipairs({ ... }) do
    local item = Find(prefab)
    if item then return item end
  end
end

local function IsRecharging(item) return Get(item, 'replica', 'inventoryitem', 'classified', 'recharge', 'value') ~= 180 end

--------------------------------------------------------------------------------
-- Inventory Item Action | 格子物品操作

local function Ctl() return Get(ThePlayer, 'components', 'playercontroller') end

local function Drop(item)
  if item then
    local is_single = true
    if Get(TheWorld, 'ismastersim') and Inv() then -- local forest-only world
      Inv():DropItemFromInvTile(item, is_single)
    elseif Ctl() then
      Ctl():RemoteDropItemFromInvTile(item, is_single)
    end
    return true
  end
end

local function Use(item, action)
  if item then
    if Get(TheWorld, 'ismastersim') and Inv() then -- local forest-only world
      Inv():UseItemFromInvTile(item)
    elseif Ctl() then
      Ctl():RemoteUseItemFromInvTile(BufferedAction(ThePlayer, nil, ACTIONS[action], item), item)
    end
    return true
  end
end

local former_hand = {}
local function SwitchHand(item)
  if not item then return end

  local current_hand_item = Inv() and Inv():GetEquippedItem(EQUIPSLOTS.HANDS)
  if current_hand_item == item then
    if former_hand[item] then return Use(former_hand[item], 'EQUIP') end
  else
    former_hand[item] = current_hand_item
    Use(item, 'EQUIP')
  end

  return true -- item equipped on hand slot
end

local function TryTaskTwice(callback, container)
  if type(callback) == 'function' and not callback() then -- task not done, open container and retry.
    if container and not Get(container, 'replica', 'container', '_isopen') then -- not opened yet
      Use(container, 'RUMMAGE') -- open
      return ThePlayer:DoTaskInTime(0.5, callback) -- wait a little then retry
    end
  end
end

--------------------------------------------------------------------------------
-- Other Actions | 其他操作

local function Do(buffered_action, rpc_name, ...)
  local action = Get(buffered_action, 'action', 'code')
  if Get(Ctl(), 'CanLocomote') then
    local other_args = { ... }
    buffered_action.preview_cb = function() return SendRPCToServer(RPC[rpc_name], action, unpack(other_args)) end
    return Ctl() and Ctl():DoAction(buffered_action)
  else
    return SendRPCToServer(RPC[rpc_name], action, ...)
  end
end

local function DoControllerAction(target, action)
  return target and Do(BufferedAction(ThePlayer, target, ACTIONS[action]), 'ControllerActionButton', target)
end

local function Make(prefab) return SendRPCToServer(RPC.MakeRecipeFromMenu, Get(AllRecipes, prefab, 'rpc_id')) end

local function Tip(message)
  local talker, time, no_anim, force = Get(ThePlayer, 'components', 'talker'), nil, true, true
  return talker and talker:Say(message, time, no_anim, force)
end

--------------------------------------------------------------------------------
-- Cast Spell | 施法

local function GetTargetPosition(distance)
  local player = Get(ThePlayer, 'GetPosition')
  local cursor = Get(TheInput, 'GetWorldPosition')
  if not (player and cursor) then return end

  local dx, dz = cursor.x - player.x, cursor.z - player.z
  local d = math.sqrt(dx ^ 2 + dz ^ 2)
  local x, z = player.x + dx / d * distance, player.z + dz / d * distance
  return Vector3(x, 0, z)
end

local function SetSpell(inst, spell_name)
  local book = Get(inst, 'components', 'spellbook')
  for id, item in pairs(Get(book, 'items') or {}) do
    if item.label == spell_name then return book and book:SelectSpell(id) and id end
  end
end

local function CastFromInv(inst, spell_name)
  return SetSpell(inst, spell_name) and Inv() and Inv():CastSpellBookFromInv(inst)
end

local function CastAOE(inst, spell_name, param)
  local spell_id = SetSpell(inst, spell_name)
  if not spell_id then return end

  if Get(param, 'is_target_only') then return Ctl() and Ctl():StartAOETargetingUsing(inst) end

  local pos = Get(param, 'position') or Get(TheInput, 'GetWorldPosition')
  local act = BufferedAction(ThePlayer, nil, ACTIONS.CASTAOE, inst, pos, nil, Get(param, 'distance') or 8)
  return Do(act, 'LeftClick', Get(pos, 'x'), Get(pos, 'z'), nil, nil, nil, nil, nil, nil, nil, inst, spell_id)
end

local function TryTipCD(name, time)
  if not (type(name) == 'string' and type(time) == 'number') then return end

  local cooldown = Get(ThePlayer, 'components', 'spellbookcooldowns')
  local percent = cooldown and cooldown:GetSpellCooldownPercent(name)
  if type(percent) ~= 'number' then return end

  Tip(math.ceil(percent * time) .. 's')
  return true
end

--------------------------------------------------------------------------------
-- General Hotkey | 通用热键

fn.DropLantern = function() return IsPlaying() and Drop(FindFueled('lantern') or Find('lightbulb')) end

fn.UseBeargerFurSack = function()
  return (not IsInCD('Polar Bearger Bin') and IsPlaying()) and Use(Find('beargerfur_sack'), 'RUMMAGE')
end

fn.UseCane = function()
  return IsPlaying()
    and SwitchHand(
      FindPrefabs('cane', 'orangestaff', 'spear_wathgrithr_lightning', 'walking_stick', 'ruins_bat')
        or FindFueled('balloonspeed')
    )
end

fn.UseArmorSnurtleShell = function()
  if not IsPlaying() then return end

  local armor = Find('armorsnurtleshell')
  local body_item = Inv() and Inv():GetEquippedItem(EQUIPSLOTS.BODY)
  return Use(armor, body_item == armor and 'USEITEM' or 'EQUIP')
end

fn.JumpInOrMigrate = function()
  if not IsPlaying() then return end

  local radius, ignore_height, must_tags = 40, true
  local cant_tags, must_one_of_tags = { 'channeling' }, { 'teleporter', 'migrator' }
  local target = FindClosestEntity(ThePlayer, radius, ignore_height, must_tags, cant_tags, must_one_of_tags)
  return target and DoControllerAction(target, target:HasTag('teleporter') and 'JUMPIN' or 'MIGRATE')
end

fn.ToggleUmbrella = function()
  if not IsPlaying() then return end

  local radius, ignore_height, cant_tags = 12, true, { 'fueldepleted' } -- broken
  local must_tags = { 'shadow_item', 'umbrella', 'acidrainimmune', 'lunarhailprotection' }
  local target = FindClosestEntity(ThePlayer, radius, ignore_height, must_tags, cant_tags)
  if target then -- toggle the nearby Umbralla
    return DoControllerAction(target, target:HasTag('turnedon') and 'TURNOFF' or 'TURNON')
  else -- drop inventory Umbralla then open it
    return Drop(FindFueled('voidcloth_umbrella')) and ThePlayer:DoTaskInTime(0.1, fn.ToggleUmbrella)
  end
end

local BLOCK_MURDER = { oceanfish_small_8_inv = true, oceanfish_medium_8_inv = true } -- Scorching Sunfish & Ice Bream | 炽热太阳鱼和冰鲷鱼
local function CanMurder(item) -- murderable and health of componentactions.lua
  return (item and not BLOCK_MURDER[item.prefab])
    and (item:HasTag('murderable') or Get(item, 'replica', 'health', 'CanMurder'))
end
fn.Murder = function() return IsPlaying() and Use(FindInvItemBy(CanMurder), 'MURDER') end

local IS_SMALL_USAGE_BOOK = {
  book_birds = true,
  book_horticulture_upgraded = true,
  book_fire = true,
  book_light = true,
  book_moon = true,
  book_bees = true,
  book_research_station = true,
}
local function CanRead(item)
  if not (item and item:HasTags('book', 'bookcabinet_item')) then return end

  local prefab = Get(item, 'prefab')
  local percent = Get(item, 'replica', 'inventoryitem', 'classified', 'percentused', 'value') -- (0, 100]
  local threshold_percent = IS_SMALL_USAGE_BOOK[prefab] and 33 or 20 -- last one usage of 3 or 5
  return type(percent) == 'number' and percent > threshold_percent
end
fn.Read = function() return IsPlaying() and ThePlayer:HasTag('reader') and Use(FindInvItemBy(CanRead), 'READ') end

fn.ClickContainerButton = function() -- credit: Tony workshop-2111412487/main/modules/quick_wrap.lua
  if not (IsPlaying() and Inv()) then return end

  for container in pairs(Inv():GetOpenContainers()) do
    local button = Get(container, 'replica', 'container', 'GetWidget', 'buttoninfo')
    if button and (type(button.validfn) ~= 'function' or button.validfn(container)) then
      if button.text ~= Get(STRINGS, 'ACTIONS', 'INCINERATE') or IsInCD('Confirm Destroy', 0.5) then
        return type(button.fn) == 'function' and button.fn(container, ThePlayer)
      end
    end
  end
end

fn.SaveGame = function() return IsPlaying() and IsInCD('Confirm Save') and not IsInCD('Save Game', 5) and c_save() end

fn.ResetGame = function()
  if IsPlaying() and IsInCD('Confirm Reset') and not IsInCD('Reset Game', 5) then
    TheNet:SetServerPaused(false) -- unpause server
    Tip(Get(STRINGS, 'UI', 'BUILTINCOMMANDS', 'RESET', 'PRETTYNAME') or 'Reset')
    ThePlayer:DoTaskInTime(1, function() return c_reset() end)
  end
end

fn.ToggleMovementPrediction = function()
  if not IsPlaying() then return end

  local is_enabled = not Get(ThePlayer, 'components', 'locomotor', 'is_prediction_enabled')
  ThePlayer:EnableMovementPrediction(is_enabled)

  local PREDICTION = Get(STRINGS, 'UI', 'OPTIONS', 'MOVEMENTPREDICTION') or 'Lag Compensation:'
  local SEPARATION = PREDICTION:sub(-1) == ':' and ' ' or ''
  local ENABLED = Get(STRINGS, 'UI', 'OPTIONS', 'MOVEMENTPREDICTION_ENABLED') or 'Predictive'
  local DISABLED = Get(STRINGS, 'UI', 'OPTIONS', 'MOVEMENTPREDICTION_DISABLED') or 'None'
  return Tip(PREDICTION .. SEPARATION .. (is_enabled and ENABLED or DISABLED))
end

--------------------------------------------------------------------------------
-- Willow | 薇洛

fn.UseLighter = function()
  if not IsPlaying('willow') then return end

  local lighter = Find('lighter')
  local action = ThePlayer:IsChannelCasting() and 'STOP_CHANNELCAST' or 'START_CHANNELCAST'
  return SwitchHand(lighter) and Use(lighter, action)
end

fn.DropBernie = function() return IsPlaying('willow') and Drop(FindFueled('bernie_inactive')) end

local FIRE_SKILL = {
  THROW = 'willow_embers',
  BURST = 'willow_fire_burst',
  BALL = 'willow_fire_ball',
  FRENZY = 'willow_fire_frenzy',
  LUNAR = 'willow_allegiance_lunar_fire',
  SHADOW = 'willow_allegiance_shadow_fire',
}
local IS_FIRE_ON_CURSOR = { THROW = true, BALL = true }

local function Fire(name)
  if not (IsPlaying('willow') and HasSkill(FIRE_SKILL[name])) then return end
  if not (Inv() and Inv():Has('willow_ember', TUNING['WILLOW_EMBER_' .. name])) then return end

  local cooldown_name = name:lower() .. '_fire'
  local cooldown_time = Get(TUNING, 'WILLOW_' .. name .. '_FIRE_COOLDOWN')
  if TryTipCD(cooldown_name, cooldown_time) then return end

  return CastAOE(
    Find('willow_ember'),
    Get(STRINGS, 'PYROMANCY', 'FIRE_' .. name) or Get(STRINGS, 'PYROMANCY', name .. '_FIRE'),
    { position = not IS_FIRE_ON_CURSOR[name] and GetTargetPosition(6.5) } -- 6.5 from line_reticule_mouse_target_function of prefabs/willow_ember.lua
  )
end

fn.FireThrow = function() return Fire('THROW') end
fn.FireBurst = function() return Fire('BURST') end
fn.FireBall = function() return Fire('BALL') end
fn.FireFrenzy = function() return Fire('FRENZY') end
fn.FireLunar = function() return Fire('LUNAR') end
fn.FireShadow = function() return Fire('SHADOW') end

--------------------------------------------------------------------------------
-- Wolfgang | 沃尔夫冈

fn.UseDumbBell = function()
  if not IsPlaying('wolfgang') then return end

  local bell = FindPrefabs('dumbbell_gem', 'dumbbell_marble', 'dumbbell_golden', 'dumbbell')
    or FindPrefabs('dumbbell_bluegem', 'dumbbell_redgem', 'dumbbell_heat')
  return SwitchHand(bell)
    and not IsRiding()
    and Use(bell, bell:HasTag('lifting') and 'STOP_LIFT_DUMBBELL' or 'LIFT_DUMBBELL')
end

--------------------------------------------------------------------------------
-- Abigail | 阿比盖尔

fn.UseFastRegenElixir = function()
  return IsPlaying('wendy')
    and TryTaskTwice(
      function() return Use(Find('ghostlyelixir_fastregen'), 'APPLYELIXIR') end,
      HasSkill('wendy_potion_container') and Find('elixir_container') -- Picnic Casket
    )
end

local GHOST_CMD_SKILL = {
  ESCAPE = 'wendy_ghostcommand_1',
  ATTACK_AT = 'wendy_ghostcommand_2',
  HAUNT_AT = 'wendy_ghostcommand_3',
  SCARE = 'wendy_ghostcommand_3',
}
local HAS_GHOST_CMD_CD = { ESCAPE = true, ATTACK_AT = true, HAUNT_AT = true, SCARE = true }
local IS_GHOST_CMD_AOE = { ATTACK_AT = true, HAUNT_AT = true }

local function IsFollowing(inst, player) return Get(inst, 'replica', 'follower', 'GetLeader') == player end
local function GhostCommand(name)
  local flower = Find('abigail_flower')
  if not (flower and HasSkill(GHOST_CMD_SKILL[name])) then return end

  if ThePlayer:HasTag('ghostfriend_notsummoned') then return Use(flower, 'CASTSUMMON') end

  if HAS_GHOST_CMD_CD[name] then
    local is_gestalt_attack = name == 'ATTACK_AT' and FindEntity(ThePlayer, 80, IsFollowing, { 'abigail', 'gestalt' })
    local cooldown_name = is_gestalt_attack and 'do_ghost_attackat' or 'ghostcommand'
    local time = is_gestalt_attack and (TUNING.WENDYSKILL_GESTALT_ATTACKAT_COMMAND_COOLDOWN or 10)
      or (TUNING.WENDYSKILL_COMMAND_COOLDOWN or 4)
    if TryTipCD(cooldown_name, time) then return end
  end

  local spell_name = Get(STRINGS, 'GHOSTCOMMANDS', name) or Get(STRINGS, 'ACTIONS', 'COMMUNEWITHSUMMONED', name)
  if IS_GHOST_CMD_AOE[name] then
    return CastAOE(flower, spell_name, { distance = 20 })
  else
    return CastFromInv(flower, spell_name)
  end
end

fn.SummonOrRecallAbigail = function()
  if not IsPlaying('wendy') then return end

  if ThePlayer:HasTag('ghostfriend_notsummoned') then
    return Use(Find('abigail_flower'), 'CASTSUMMON')
  elseif ThePlayer:HasTag('ghostfriend_summoned') then
    return GhostCommand('UNSUMMON')
  end
end

fn.CommuneWithSummoned = function()
  return IsPlaying('wendy')
    and GhostCommand(ThePlayer:HasTag('has_aggressive_follower') and 'MAKE_DEFENSIVE' or 'MAKE_AGGRESSIVE')
end

fn.AbigailEscape = function() return IsPlaying('wendy') and GhostCommand('ESCAPE') end
fn.AbigailAttackAt = function() return IsPlaying('wendy') and GhostCommand('ATTACK_AT') end
fn.AbigailHauntAt = function() return IsPlaying('wendy') and GhostCommand('HAUNT_AT') end
fn.AbigailScare = function() return IsPlaying('wendy') and GhostCommand('SCARE') end

--------------------------------------------------------------------------------
-- Maxwell | 麦斯威尔

fn.UseMagicianToolOrStop = function()
  if IsInCD("Magician's Top Hat") or not IsPlaying('waxwell') then return end

  if ThePlayer:HasTag('usingmagiciantool') then -- already opened, close it.
    local x, _, z = ThePlayer.Transform:GetWorldPosition()
    return Do(BufferedAction(ThePlayer, ThePlayer, ACTIONS.STOPUSINGMAGICTOOL), 'RightClick', x, z, ThePlayer)
  end

  local hat = Find('tophat', 'magiciantool') -- find one to open
  return hat and Do(BufferedAction(ThePlayer, nil, ACTIONS.USEMAGICTOOL, hat), 'UseItemFromInvTile', hat, 1)
end

local function Spell(name, is_target_only)
  if IsPlaying('waxwell') then
    return CastAOE(FindFueled('waxwelljournal'), Get(STRINGS, 'SPELLS', name), { is_target_only = is_target_only })
  end
end

fn.ShadowWorker = function() return Spell('SHADOW_WORKER') end
fn.ShadowWorkerIndicator = function() return Spell('SHADOW_WORKER', true) end
fn.ShadowProtector = function() return Spell('SHADOW_PROTECTOR') end
fn.ShadowProtectorIndicator = function() return Spell('SHADOW_PROTECTOR', true) end
fn.ShadowTrap = function() return Spell('SHADOW_TRAP') end
fn.ShadowTrapIndicator = function() return Spell('SHADOW_TRAP', true) end
fn.ShadowPillars = function() return Spell('SHADOW_PILLARS') end
fn.ShadowPillarsIndicator = function() return Spell('SHADOW_PILLARS', true) end

--------------------------------------------------------------------------------
-- Wigfrid | 薇格弗德

local function IsValidBattleSong(item) -- function `singable` from componentactions.lua
  if not (item and item:HasTag('battlesong')) then return end -- not battle song at all

  local data = item.songdata
  if not (data and HasSkill(data.REQUIRE_SKILL)) then return end

  if data.INSTANT then -- Battle Stinger
    if IsRecharging(item) then return end -- Battle Stinger in CD | 战吼正在冷却
  else -- Battle Song
    for _, v in ipairs(Get(ThePlayer, 'player_classified', 'inspirationsongs') or {}) do
      if v:value() == data.battlesong_netid then return end -- Battle Song already activated
    end
  end

  return true
end

fn.UseBattleSong = function()
  return IsPlaying('wathgrithr')
    and TryTaskTwice(
      function() return Use(FindInvItemBy(IsValidBattleSong), 'SING') end,
      HasSkill('wathgrithr_songs_container') and Find('battlesong_container') -- Battle Call Canister
    )
end

local function GetStrikeTargetPosition()
  if not (TheWorld and TheWorld.Map) then return end

  for distance = 7.99, 0.1, -0.1 do
    local p = GetTargetPosition(distance)
    if p and TheWorld.Map:IsPassableAtPoint(p.x, 0, p.z) then return p end
  end
end

fn.StrikeOrBlock = function()
  if not IsPlaying('wathgrithr') or IsRiding() then return end

  local item = FindPrefabs('spear_wathgrithr_lightning_charged', 'spear_wathgrithr_lightning', 'wathgrithr_shield')
  if item == (Inv() and Inv():GetEquippedItem(EQUIPSLOTS.HANDS)) then -- already equipped on hand slot
    if IsRecharging(item) then return end
  else -- not equipped yet
    return Use(item, 'EQUIP')
  end

  local pos = GetStrikeTargetPosition()
  return pos and Do(BufferedAction(ThePlayer, nil, ACTIONS.CASTAOE, item, pos), 'LeftClick', pos.x, pos.z)
end

--------------------------------------------------------------------------------
-- Webber | 韦伯

fn.UseSpiderWhistle = function()
  return IsPlaying('webber') and (Use(Find('spider_whistle'), 'HERD_FOLLOWERS') or Make('spider_whistle'))
end

--------------------------------------------------------------------------------
-- Winona | 薇诺娜

fn.UseTeleBrella = function()
  if not IsPlaying('winona') then return end

  local brella = FindFueled('winona_telebrella')
  return SwitchHand(brella) and Use(brella, 'REMOTE_TELEPORT')
end

local REMOTE_SKILL = {
  WAKEUP = 'winona_portable_structures',
  VOLLEY = 'winona_catapult_volley_1',
  BOOST = 'winona_catapult_boost_1',
  ELEMENTAL_VOLLEY = { 'winona_shadow_3', 'winona_lunar_3' },
}
local function EngineerRemote(name, is_target_only)
  if IsPlaying('winona') and HasSkill(REMOTE_SKILL[name]) then
    local remote = FindFueled('winona_remote')
    local spell_name = Get(STRINGS, 'ENGINEER_REMOTE', name)
    return CastAOE(remote, spell_name, { is_target_only = is_target_only, distance = Get(TUNING.WINONA_REMOTE_RANGE) })
  end
end

fn.CatapultWakeUp = function() return EngineerRemote('WAKEUP') end
fn.CatapultBoost = function() return EngineerRemote('BOOST') end
fn.CatapultVolley = function() return EngineerRemote('VOLLEY') end
fn.CatapultVolleyIndicator = function() return EngineerRemote('VOLLEY', true) end
fn.CatapultElementalVolley = function() return EngineerRemote('ELEMENTAL_VOLLEY') end
fn.CatapultElementalVolleyIndicator = function() return EngineerRemote('ELEMENTAL_VOLLEY', true) end

--------------------------------------------------------------------------------
-- Wormwood | 沃姆伍德

fn.MakeLivingLog = function() return IsPlaying('wormwood') and Make('livinglog') end
fn.MakeLightFlier = function() return IsPlaying('wormwood') and Make('wormwood_lightflier') end

local function FertilizeSpoiledFoodTask()
  if Get(ThePlayer, 'replica', 'health', 'GetPercent') == 1 then return true end
  return not ThePlayer:HasOneOfTags('busy', 'moving')
    and Use(Find('spoiled_food'), 'FERTILIZE')
    and ThePlayer:DoTaskInTime(4.1, FertilizeSpoiledFoodTask)
end
fn.FertilizeSpoiledFood = function()
  return IsPlaying('wormwood')
    and TryTaskTwice(FertilizeSpoiledFoodTask, FindPrefabs('supertacklecontainer', 'tacklecontainer')) -- Spectackler Box or Tackle Box
end

--------------------------------------------------------------------------------
-- Wurt | 沃特

---@param inst Instance
local function RefreshHirable(inst)
  local AS = Get(inst, 'AnimState')
  if not AS then return end

  local is_hired = AS:IsCurrentAnimation('eat') or AS:IsCurrentAnimation('buff')
  local is_hungry = AS:IsCurrentAnimation('hungry') -- state "funnyidle" from stategraphs/SGmerm.lua
  if inst:HasTag('hirable') then
    if is_hired then inst:RemoveTag('hirable') end
  elseif (Get(inst, 'replica', 'follower', 'GetLeader') ~= ThePlayer) or is_hungry then
    inst:AddTag('hirable')
  end
end

---@param inst Instance
fn.HookMermGuard = function(inst) return Get(ThePlayer, 'prefab') == 'wurt' and inst:DoPeriodicTask(1, RefreshHirable) end

fn.HireMermGuard = function()
  if not IsPlaying('wurt') then return end

  local food = FindPrefabs(
    'rock_avocado_fruit_ripe_cooked', -- Cooked Stone Fruit | 熟石果
    'rock_avocado_fruit_ripe', -- Ripe Stone Fruit | 成熟石果
    'boatpatch_kelp', -- Kelp Patch | 海带补丁
    'kelp_cooked', -- Cooked Kelp Fronds | 熟海带叶
    'kelp', -- Kelp Fronds | 海带叶
    'carrot_cooked', -- Roasted Carrot | 烤胡萝卜
    'carrot', -- Carrot | 胡萝卜
    'ratatouille', -- Ratatouille | 蔬菜杂烩
    'pondfish' -- Freshwater Fish | 淡水鱼
  )
  if not food then return end

  local radius, ignore_height, must_tags = 20, true, { 'mermguard', 'hirable' }
  local merm = FindClosestEntity(ThePlayer, radius, ignore_height, must_tags)
  if not merm then return end

  return Do(BufferedAction(ThePlayer, merm, ACTIONS.GIVE, food), 'ControllerUseItemOnSceneFromInvTile', food, merm)
end

--------------------------------------------------------------------------------
-- Woby | 沃比

fn.WobyRummage = function()
  if IsInCD('Rummage Woby') or not IsPlaying('walter') then return end

  local woby = Get(ThePlayer, 'woby_commands_classified', 'GetWoby')
  if woby == Get(ThePlayer, 'replica', 'rider', 'GetMount') then -- is riding on Woby
    return CastFromInv(ThePlayer, Get(STRINGS, 'ACTIONS', 'RUMMAGE', 'GENERIC'))
  elseif ThePlayer:IsNear(woby, 16) then -- Woby is nearby
    return DoControllerAction(woby, 'RUMMAGE')
  end
end

fn.WobyCourier = function()
  if Get(ThePlayer, 'woby_commands_classified', 'IsOutForDelivery') then return end
  if not (IsPlaying('walter') and HasSkill('walter_camp_wobycourier')) then return end

  local woby = Get(ThePlayer, 'woby_commands_classified', 'GetWoby')
  return ThePlayer:IsNear(woby, 16)
    and SetSpell(woby, Get(STRINGS, 'WOBY_COMMANDS', 'COURIER'))
    and (Ctl() and Ctl():PullUpMap(woby, ACTIONS.DIRECTCOURIER_MAP))
end

fn.WobyDash = function() -- credit: 川小胖 workshop-3460815078 from DoDoubleTapDir() in components/playercontroller.lua
  if not (IsPlaying('walter') and HasSkill('walter_woby_dash')) then return end

  local cursor, player = Get(TheInput, 'GetWorldPosition'), Get(ThePlayer, 'GetPosition')
  if not (cursor and player) then return end

  local picker = Get(ThePlayer, 'components', 'playeractionpicker')
  local dir = Get(cursor - player, 'GetNormalized')
  local act = Get(picker and picker:GetDoubleClickActions(nil, dir), 1)
  if Get(act, 'action') ~= ACTIONS.DASH then return end

  local x, z = Get(act, 'pos', 'local_pt', 'x'), Get(act, 'pos', 'local_pt', 'z')
  local no_force, mod_name = Get(act, 'action', 'canforce'), Get(act, 'action', 'mod_name')
  local platform = Get(act, 'pos', 'walkable_platform')
  local platform_relative = platform ~= nil
  return Do(act, 'DoubleTapAction', x, z, no_force, mod_name, platform, platform_relative)
end

--------------------------------------------------------------------------------
-- Wanda | 旺达

local function FindWatch(name) return Find('pocketwatch_' .. name, 'pocketwatch_inactive') end

fn.UsePocketWatchHeal = function() return IsPlaying('wanda') and Use(FindWatch('heal'), 'CAST_POCKETWATCH') end
fn.UsePocketWatchWarp = function() return IsPlaying('wanda') and Use(FindWatch('warp'), 'CAST_POCKETWATCH') end

--------------------------------------------------------------------------------

return fn
