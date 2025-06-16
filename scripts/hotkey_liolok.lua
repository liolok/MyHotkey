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
  local current = head_node
  for _, key in ipairs({ ... }) do
    if not current then return end

    local next = current[key]
    if type(next) == 'function' then -- for code like `ThePlayer.replica.inventory:GetActiveItem()`
      current = next(current) -- this could be `false`/`nil` so avoid assigning with `type(next) == 'function' and next(current) or next`
    else
      current = next
    end
  end
  return current
end

local function IsMasterSim() return Get(TheWorld, 'ismastersim') end -- detect local forest-only world
local function Ctl() return Get(ThePlayer, 'components', 'playercontroller') end
local function Inv() return Get(ThePlayer, 'replica', 'inventory') end

local function IsPlaying(character)
  if not (TheWorld and ThePlayer) then return end -- in game, yeah
  if character and ThePlayer.prefab ~= character then return end -- optionally check for right character
  if ThePlayer.HUD and ThePlayer.HUD:HasInputFocus() then return end -- typing or in some menu
  return true -- it's all good, man
end

local function FindInvItemBy(IsRight) -- find right item in inventory | 在所有格子里找正确的物品
  local inventory = Inv()
  if not (inventory and type(IsRight) == 'function') then return end

  -- try to put item on cursor back into slot | 尝试将光标上的物品放回格子里
  if inventory:GetActiveItem() then inventory:ReturnActiveItem() end

  -- all equipped items | 所有已装备物品
  for _, item in pairs(inventory:GetEquips()) do
    if IsRight(item) then return item end
  end

  -- all items of all opened containers | 所有打开的容器的所有物品
  for container in pairs(inventory:GetOpenContainers()) do
    for _, item in pairs(Get(container, 'replica', 'container', 'GetItems') or {}) do
      if IsRight(item) then return item end
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

local function Drop(item)
  if item then
    local is_single = true
    if IsMasterSim() and Inv() then
      Inv():DropItemFromInvTile(item, is_single)
    elseif Ctl() then
      Ctl():RemoteDropItemFromInvTile(item, is_single)
    end
    return true
  end
end

local function Use(item, action)
  if item then
    if IsMasterSim() and Inv() then
      Inv():UseItemFromInvTile(item)
    elseif Ctl() then
      Ctl():RemoteUseItemFromInvTile(BufferedAction(ThePlayer, nil, ACTIONS[action], item), item)
    end
    return true
  end
end

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

local function Tip(message)
  local talker, time, no_anim, force = Get(ThePlayer, 'components', 'talker'), nil, true, true
  return talker and talker:Say(message, time, no_anim, force)
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

local function GetTargetPosition(distance)
  local player = Get(ThePlayer, 'GetPosition')
  local cursor = Get(TheInput, 'GetWorldPosition')
  if not (player and cursor) then return end

  local distance = distance or 7.99
  local dx, dz = cursor.x - player.x, cursor.z - player.z
  local d = math.sqrt(dx ^ 2 + dz ^ 2)
  local x, z = player.x + dx / d * distance, player.z + dz / d * distance
  return Vector3(x, 0, z)
end

local function SetSpell(inst, spell_name)
  local book = Get(inst, 'components', 'spellbook')
  for id, item in pairs(Get(book, 'items') or {}) do
    if item.label == spell_name then return book:SelectSpell(id) and id end
  end
end

local function CastFromInv(inst, spell_name)
  return SetSpell(inst, spell_name) and Inv() and Inv():CastSpellBookFromInv(inst)
end

local function DoCastAOE(inst, spell_name, target_position)
  local spell_id = SetSpell(inst, spell_name)
  if not spell_id then return end

  local pos = target_position or Get(TheInput, 'GetWorldPosition')
  local act = BufferedAction(ThePlayer, nil, ACTIONS.CASTAOE, inst, pos)
  return Do(act, 'LeftClick', pos.x, pos.z, nil, nil, nil, nil, nil, nil, nil, inst, spell_id)
end

local function TryTipCD(percent, time)
  if type(percent) == 'number' and type(time) == 'number' then
    Tip(math.ceil(percent * time) .. 's')
    return true
  end
end

local function TryTaskTwice(callback, container)
  if type(callback) == 'function' and not callback() then -- task not done, open container and retry.
    if container and not Get(container, 'replica', 'container', '_isopen') then -- not opened yet
      Use(container, 'RUMMAGE') -- open
      return ThePlayer:DoTaskInTime(0.5, callback) -- wait a little then retry
    end
  end
end

local function IsFollowing(inst, player) return Get(inst, 'replica', 'follower', 'GetLeader') == player end

--------------------------------------------------------------------------------
-- General Hotkey | 通用热键

fn.DropLantern = function() return IsPlaying() and Drop(FindFueled('lantern') or Find('lightbulb')) end

fn.UseBeargerFurSack = function()
  return (not IsInCD('Polar Bearger Bin') and IsPlaying()) and Use(Find('beargerfur_sack'), 'RUMMAGE')
end

fn.UseCane = function()
  return IsPlaying()
    and SwitchHand(FindPrefabs('cane', 'orangestaff', 'walking_stick', 'ruins_bat') or FindFueled('balloonspeed'))
end

fn.JumpInOrMigrate = function()
  if not IsPlaying() then return end

  local radius, ignore_height, must_tags = 40, true
  local cant_tags, must_one_of_tags = { 'channeling' }, { 'teleporter', 'migrator' }
  local target = FindClosestEntity(ThePlayer, radius, ignore_height, must_tags, cant_tags, must_one_of_tags)
  return DoControllerAction(target, target:HasTag('teleporter') and 'JUMPIN' or 'MIGRATE')
end

fn.ToggleUmbrella = function()
  if not IsPlaying() then return end

  local radius, ignore_height, cant_tags = 12, true, { 'fueldepleted' } -- broken
  local must_tags = { 'shadow_item', 'umbrella', 'acidrainimmune', 'lunarhailprotection' }
  local target = FindClosestEntity(ThePlayer, radius, ignore_height, must_tags, cant_tags)
  if target then -- toggle the nearby Umbralla
    return DoControllerAction(target, target:HasTag('turnedon') and 'TURNOFF' or 'TURNON')
  else -- drop inventory Umbralla then open it
    return Drop(FindFueled('voidcloth_umbrella')) and ThePlayer:DoTaskInTime(0.5, fn.ActivateUmbrella)
  end
end

local IS_MURDER_PROTECT = { oceanfish_small_8 = true, oceanfish_medium_8 = true } -- Scorching Sunfish & Ice Bream | 炽热太阳鱼和冰鲷鱼

local function IsMurderTarget(item) -- health from componentactions.lua
  return Get(item, 'replica', 'health', 'CanMurder') and not IS_MURDER_PROTECT[Get(item, 'prefab')]
end

fn.Murder = function() return IsPlaying() and Use(FindInvItemBy(IsMurderTarget), 'MURDER') end

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
}

local IS_FIRE_ON_SELF = { BURST = true, FRENZY = true }

local function HasEmber(count) return Inv() and Inv():Has('willow_ember', count) end

local function Fire(name)
  if not (IsPlaying('willow') and HasSkill(FIRE_SKILL[name])) then return end

  if not HasEmber(TUNING['WILLOW_EMBER_' .. name]) then return end

  local spell_name = Get(STRINGS, 'PYROMANCY', 'FIRE_' .. name)
  local target_position = IS_FIRE_ON_SELF[name] and Get(ThePlayer, 'GetPosition')
  return DoCastAOE(Find('willow_ember'), spell_name, target_position)
end

fn.FireThrow = function() return Fire('THROW') end
fn.FireBurst = function() return Fire('BURST') end
fn.FireBall = function() return Fire('BALL') end
fn.FireFrenzy = function() return Fire('FRENZY') end

fn.LunarOrShadowFire = function()
  if not IsPlaying('willow') then return end

  local is_lunar = (HasSkill('willow_allegiance_lunar_fire') and HasEmber(TUNING.WILLOW_EMBER_LUNAR))
    and not Get(ThePlayer, 'replica', 'rider', 'IsRiding')
  local is_shadow = not is_lunar and HasSkill('willow_allegiance_shadow_fire') and HasEmber(TUNING.WILLOW_EMBER_SHADOW)
  if not (is_lunar or is_shadow) then return end

  local cooldown = Get(ThePlayer, 'components', 'spellbookcooldowns')
  local cooldown_percent = cooldown and cooldown:GetSpellCooldownPercent(is_lunar and 'lunar_fire' or 'shadow_fire')
  local cooldown_time = is_lunar and TUNING.WILLOW_LUNAR_FIRE_COOLDOWN or TUNING.WILLOW_SHADOW_FIRE_COOLDOWN
  local spell_name = Get(STRINGS, 'PYROMANCY', is_lunar and 'LUNAR_FIRE' or 'SHADOW_FIRE')
  return TryTipCD(cooldown_percent, cooldown_time) or DoCastAOE(Find('willow_ember'), spell_name, GetTargetPosition())
end

--------------------------------------------------------------------------------
-- Wolfgang | 沃尔夫冈

fn.UseDumbBell = function()
  if not IsPlaying('wolfgang') then return end

  local bell = FindPrefabs('dumbbell_gem', 'dumbbell_marble', 'dumbbell_golden', 'dumbbell')
    or FindPrefabs('dumbbell_bluegem', 'dumbbell_redgem', 'dumbbell_heat')
  return SwitchHand(bell) and Use(bell, bell:HasTag('lifting') and 'STOP_LIFT_DUMBBELL' or 'LIFT_DUMBBELL')
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

local function GhostCommand(name)
  if not HasSkill(GHOST_CMD_SKILL[name]) then return end

  local flower = Find('abigail_flower')
  if not flower then return end

  if ThePlayer:HasTag('ghostfriend_notsummoned') then return Use(flower, 'CASTSUMMON') end

  if HAS_GHOST_CMD_CD[name] then
    local cooldown = Get(ThePlayer, 'components', 'spellbookcooldowns')
    local percent = cooldown and cooldown:GetSpellCooldownPercent('ghostcommand')
    local time = TUNING.WENDYSKILL_COMMAND_COOLDOWN or 4
    if name == 'ATTACK_AT' and FindEntity(ThePlayer, 80, IsFollowing, { 'gestalt' }) then -- Gestalt Abigail
      percent = cooldown and cooldown:GetSpellCooldownPercent('do_ghost_attackat')
      time = TUNING.WENDYSKILL_GESTALT_ATTACKAT_COMMAND_COOLDOWN or 10
    end
    if TryTipCD(percent, time) then return end
  end

  local spell_name = Get(STRINGS, 'GHOSTCOMMANDS', name) or Get(STRINGS, 'ACTIONS', 'COMMUNEWITHSUMMONED', name)
  if IS_GHOST_CMD_AOE[name] then return DoCastAOE(flower, spell_name) end

  return CastFromInv(flower, spell_name)
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

local function Spell(name)
  return IsPlaying('waxwell') and DoCastAOE(FindFueled('waxwelljournal'), Get(STRINGS, 'SPELLS', name))
end

fn.ShadowWorker = function() return Spell('SHADOW_WORKER') end
fn.ShadowProtector = function() return Spell('SHADOW_PROTECTOR') end
fn.ShadowTrap = function() return Spell('SHADOW_TRAP') end
fn.ShadowPillars = function() return Spell('SHADOW_PILLARS') end

--------------------------------------------------------------------------------
-- Wigfrid | 薇格弗德

local function IsRecharging(item)
  return Get(item, 'replica', '_', 'inventoryitem', 'classified', 'recharge', 'value') ~= 180
end

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
  if not IsPlaying('wathgrithr') then return end

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

local function EngineerRemote(name)
  return (IsPlaying('winona') and HasSkill(REMOTE_SKILL[name]))
    and DoCastAOE(FindFueled('winona_remote'), Get(STRINGS, 'ENGINEER_REMOTE', name))
end

fn.CatapultWakeUp = function() return EngineerRemote('WAKEUP') end
fn.CatapultBoost = function() return EngineerRemote('BOOST') end
fn.CatapultVolley = function() return EngineerRemote('VOLLEY') end
fn.CatapultElementalVolley = function() return EngineerRemote('ELEMENTAL_VOLLEY') end

--------------------------------------------------------------------------------
-- Wormwood | 沃姆伍德

fn.MakeLivingLog = function() return IsPlaying('wormwood') and Make('livinglog') end
fn.MakeLightFlier = function() return IsPlaying('wormwood') and Make('wormwood_lightflier') end

fn.FertilizeSpoiledFood = function()
  return not IsInCD('Fertilize self with Rot', 4)
    and IsPlaying('wormwood')
    and TryTaskTwice(
      function() return Use(Find('spoiled_food'), 'FERTILIZE') end,
      FindPrefabs('supertacklecontainer', 'tacklecontainer') -- Spectackler Box or Tackle Box
    )
end

--------------------------------------------------------------------------------
-- Wurt | 沃特

local function IsToHire(inst, player)
  if Get(inst, 'prefab') ~= 'mermguard' or not Get(inst, 'replica', 'follower') then return end

  local leader = Get(inst, 'replica', 'follower', 'GetLeader')
  if not leader then return true end -- no leader yet, need to hire.

  if leader == player then -- already following, hire if hungry.
    local as = Get(inst, 'AnimState')
    if as and as:IsCurrentAnimation('hungry') then return true end -- state "funnyidle" from stategraphs/SGmerm.lua
  end
end

fn.HireMermGuard = function()
  if not IsPlaying('wurt') then return end

  local food = FindPrefabs('rock_avocado_fruit_ripe', 'kelp', 'pondfish')
  if not food then return end

  local radius, ignore_height, must_tags, cant_tags, must_one_of_tags = 20, true, { 'mermguard' }, { 'player' }, {}
  local merm = FindClosestEntity(ThePlayer, radius, ignore_height, must_tags, cant_tags, must_one_of_tags, IsToHire)
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
