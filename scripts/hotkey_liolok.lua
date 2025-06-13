local fn = {}

-- cooldown for functions | 冷却
local is_in_cd = {}
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
    if type(next) == 'function' then
      current = next(current) -- this could be `false` so avoid using `and next(current) or next` assignment
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
  if not (ThePlayer.HUD and ThePlayer.Transform) then return end -- for safe call later
  if ThePlayer.HUD:HasInputFocus() then return end -- typing or in some menu
  if not (Ctl() and Inv()) then return end -- for safe call later
  return true -- it's all good, man
end

local function FindInvItemBy(IsRight) -- find right item in inventory | 在所有格子里找正确的物品
  local inventory = Inv()
  if not (inventory and type(IsRight) == 'function') then return end

  -- item on cursor | 光标上的物品
  local item = inventory:GetActiveItem()
  if IsRight(item) then return item end

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
  return item and (IsMasterSim() and Inv():DropItemFromInvTile(item) or Ctl():RemoteDropItemFromInvTile(item))
end

local function Use(item, act)
  if not item then return end

  return IsMasterSim() and Inv():UseItemFromInvTile(item)
    or Ctl():RemoteUseItemFromInvTile(BufferedAction(ThePlayer, nil, ACTIONS[act], item), item)
end

local function Do(buffered_action, rpc_name, ...)
  if IsMasterSim() then return Ctl():DoAction(buffered_action) end
  return SendRPCToServer(RPC[rpc_name], Get(buffered_action, 'action', 'code'), ...)
end

local function Make(prefab) return SendRPCToServer(RPC.MakeRecipeFromMenu, Get(AllRecipes, prefab, 'rpc_id')) end

local former_hand = {}
local function SwitchHand(item)
  if not item then return end

  local current_hand_item = Inv():GetEquippedItem(EQUIPSLOTS.HANDS)
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

local function GetSpellID(book, name)
  for id, spell in pairs(Get(book, 'items') or {}) do
    if spell.label == name then return id, spell end
  end
end

local function SetSpell(inst, name)
  local book = Get(inst, 'components', 'spellbook')
  return book and book:SelectSpell(GetSpellID(book, name))
end

local function IsNumber(...)
  for _, value in ipairs({ ... }) do
    if type(value) ~= 'number' then return end
  end
  return true
end

local function TipCooldown(percent, time) return Tip(math.ceil(percent * time) .. 's') end

--------------------------------------------------------------------------------

fn.DropLantern = function() return IsPlaying() and Drop(FindFueled('lantern')) end

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
  if not target then return end

  local action = target:HasTag('teleporter') and ACTIONS.JUMPIN or ACTIONS.MIGRATE
  return Do(BufferedAction(ThePlayer, target, action), 'ControllerActionButton', target)
end

fn.ToggleUmbrella = function()
  if not IsPlaying() then return end

  local radius, ignore_height, cant_tags = 12, true, { 'fueldepleted' } -- broken
  local must_tags = { 'shadow_item', 'umbrella', 'acidrainimmune', 'lunarhailprotection' }
  local target = FindClosestEntity(ThePlayer, radius, ignore_height, must_tags, cant_tags)
  if not target then
    local inventory_umbrella = FindFueled('voidcloth_umbrella')
    if not inventory_umbrella then return end

    Drop(inventory_umbrella)
    return ThePlayer:DoTaskInTime(0.5, fn.ActivateUmbrella)
  end

  local action = target:HasTag('turnedon') and ACTIONS.TURNOFF or ACTIONS.TURNON
  return Do(BufferedAction(ThePlayer, target, action), 'ControllerActionButton', target)
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

local function Fire(name)
  if not (IsPlaying('willow') and HasSkill(FIRE_SKILL[name])) then return end

  if not Inv():Has('willow_ember', TUNING['WILLOW_EMBER_' .. name]) then return end

  local ember = Find('willow_ember')
  local spell_name = Get(STRINGS, 'PYROMANCY', 'FIRE_' .. name)
  return SetSpell(ember, spell_name) and Ctl():StartAOETargetingUsing(ember)
end

fn.FireThrow = function() return Fire('THROW') end
fn.FireBurst = function() return Fire('BURST') end
fn.FireBall = function() return Fire('BALL') end
fn.FireFrenzy = function() return Fire('FRENZY') end

fn.LunarOrShadowFire = function()
  if not IsPlaying('willow') then return end

  local ember = Find('willow_ember')
  if not ember then return end

  local cooldown = Get(ThePlayer, 'components', 'spellbookcooldowns')
  if not cooldown then return end

  local spell_name, cooldown_percent, cooldown_time
  if HasSkill(FIRE_SKILL.LUNAR) and Inv():Has('willow_ember', TUNING.WILLOW_EMBER_LUNAR or 5) then
    if Get(ThePlayer, 'replica', 'rider', 'IsRiding') then return end
    spell_name = Get(STRINGS, 'PYROMANCY', 'LUNAR_FIRE')
    cooldown_percent = cooldown:GetSpellCooldownPercent('lunar_fire')
    cooldown_time = TUNING.WILLOW_LUNAR_FIRE_COOLDOWN or 13
  elseif HasSkill(FIRE_SKILL.SHADOW) and Inv():Has('willow_ember', TUNING.WILLOW_EMBER_SHADOW or 5) then
    spell_name = Get(STRINGS, 'PYROMANCY', 'SHADOW_FIRE')
    cooldown_percent = cooldown:GetSpellCooldownPercent('shadow_fire')
    cooldown_time = TUNING.WILLOW_SHADOW_FIRE_COOLDOWN or 8
  else
    return
  end

  if IsNumber(cooldown_percent, cooldown_time) then return TipCooldown(cooldown_percent, cooldown_time) end

  local pos = GetTargetPosition() or ThePlayer:GetPosition()
  if not (pos and SetSpell(ember, spell_name)) then return end

  local act = BufferedAction(ThePlayer, nil, ACTIONS.CASTAOE, ember, pos)
  local spell_id = GetSpellID(Get(ember, 'components', 'spellbook'), spell_name)
  return Do(act, 'LeftClick', pos.x, pos.z, nil, nil, nil, nil, nil, nil, nil, ember, spell_id)
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
  if not IsPlaying('wendy') then return end

  local container = HasSkill('wendy_potion_container') and Find('elixir_container')
  if container and not Get(container, 'replica', 'container', '_isopen') then
    Use(container, 'RUMMAGE') -- open Picnic Casket
    return ThePlayer:DoTaskInTime(0.5, fn.UseFastRegenElixir) -- wait a little
  end

  return Use(Find('ghostlyelixir_fastregen'), 'APPLYELIXIR')
end

local function IsSister(ghost, player) return Get(ghost, 'replica', 'follower', 'GetLeader') == player end -- credit: RICK workshop-2895442474/scripts/CharacterKeybinds.lua

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
    if name == 'ATTACK_AT' and FindEntity(ThePlayer, 80, IsSister, { 'gestalt' }) then -- Gestalt Abigail
      percent = cooldown and cooldown:GetSpellCooldownPercent('do_ghost_attackat')
      time = TUNING.WENDYSKILL_GESTALT_ATTACKAT_COMMAND_COOLDOWN or 10
    end
    if IsNumber(percent, time) then return TipCooldown(percent, time) end
  end

  local spell_name = Get(STRINGS, 'GHOSTCOMMANDS', name) or Get(STRINGS, 'ACTIONS', 'COMMUNEWITHSUMMONED', name)
  if not SetSpell(ember, spell_name) then return end

  if IS_GHOST_CMD_AOE[name] then
    return Ctl():StartAOETargetingUsing(flower)
  else
    return Inv():CastSpellBookFromInv(flower)
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

local function Spell(name)
  if not IsPlaying('waxwell') then return end

  local journal = FindFueled('waxwelljournal')
  return SetSpell(journal, Get(STRINGS, 'SPELLS', name)) and Ctl():StartAOETargetingUsing(journal)
end

fn.ShadowWorker = function() return Spell('SHADOW_WORKER') end
fn.ShadowProtector = function() return Spell('SHADOW_PROTECTOR') end
fn.ShadowTrap = function() return Spell('SHADOW_TRAP') end
fn.ShadowPillars = function() return Spell('SHADOW_PILLARS') end

--------------------------------------------------------------------------------
-- Wigfrid | 薇格弗德

local function IsValidBattleSong(item) -- function `singable` from componentactions.lua
  if not (item and item:HasTag('battlesong')) then return end -- not battle song at all

  local song = item.songdata
  if not song then return end

  if not HasSkill(song.REQUIRE_SKILL) then return end -- no skill required by this song

  if song.INSTANT then -- Battle Stinger
    local recharge_value = Get(item, 'replica', '_', 'inventoryitem', 'classified', 'recharge', 'value')
    if recharge_value and recharge_value ~= 180 then return end -- Battle Stinger in CD | 战吼正在冷却
  else -- Battle Song
    for _, v in ipairs(Get(ThePlayer, 'player_classified', 'inspirationsongs') or {}) do
      if v:value() == song.battlesong_netid then return end -- Battle Song already activated
    end
  end

  return true
end

local function UseValidBattleSong() return Use(FindInvItemBy(IsValidBattleSong), 'SING') end

fn.UseBattleSong = function()
  if not IsPlaying('wathgrithr') then return end

  local container = HasSkill('wathgrithr_songs_container') and Find('battlesong_container')
  if container and not Get(container, 'replica', 'container', '_isopen') then
    Use(container, 'RUMMAGE') -- open Battle Call Canister
    return ThePlayer:DoTaskInTime(0.5, UseValidBattleSong) -- wait a little to sing
  end

  return UseValidBattleSong()
end

fn.StrikeOrBlock = function()
  if not IsPlaying('wathgrithr') then return end

  local pos = GetTargetPosition()
  return pos and Do(BufferedAction(ThePlayer, nil, ACTIONS.CASTAOE, nil, pos), 'LeftClick', pos.x, pos.z)
end

--------------------------------------------------------------------------------
-- Webber | 韦伯

fn.UseSpiderWhistle = function()
  if not IsPlaying('webber') then return end

  local whistle = Find('spider_whistle')
  if whistle then
    return Use(whistle, 'HERD_FOLLOWERS')
  else
    return Make('spider_whistle')
  end
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
  if not (IsPlaying('winona') and HasSkill(REMOTE_SKILL[name])) then return end

  local remote = FindFueled('winona_remote')
  return SetSpell(remote, Get(STRINGS, 'ENGINEER_REMOTE', name)) and Ctl():StartAOETargetingUsing(remote)
end

fn.CatapultWakeUp = function() return EngineerRemote('WAKEUP') end
fn.CatapultBoost = function() return EngineerRemote('BOOST') end
fn.CatapultVolley = function() return EngineerRemote('VOLLEY') end
fn.CatapultElementalVolley = function() return EngineerRemote('ELEMENTAL_VOLLEY') end

--------------------------------------------------------------------------------
-- Wormwood | 沃姆伍德

fn.MakeLivingLog = function() return IsPlaying('wormwood') and Make('livinglog') end
fn.MakeLightFlier = function() return IsPlaying('wormwood') and Make('wormwood_lightflier') end

--------------------------------------------------------------------------------
-- Woby | 沃比

fn.WobyRummage = function()
  if IsInCD('Rummage Woby') or not IsPlaying('walter') then return end

  local woby = Get(ThePlayer, 'woby_commands_classified', 'GetWoby')
  if woby == Get(ThePlayer, 'replica', 'rider', 'GetMount') then -- is riding on Woby
    return SetSpell(ThePlayer, Get(STRINGS, 'ACTIONS', 'RUMMAGE', 'GENERIC')) and Inv():CastSpellBookFromInv(ThePlayer)
  elseif ThePlayer:IsNear(woby, 16) then -- Woby is nearby
    return Do(BufferedAction(ThePlayer, woby, ACTIONS.RUMMAGE), 'ControllerActionButton', woby)
  end
end

fn.WobyCourier = function()
  if Get(ThePlayer, 'woby_commands_classified', 'IsOutForDelivery') then return end
  if not (IsPlaying('walter') and HasSkill('walter_camp_wobycourier')) then return end

  local woby = Get(ThePlayer, 'woby_commands_classified', 'GetWoby')
  if not woby or woby:HasOneOfTags('transforming', 'INLIMBO') then return end

  return SetSpell(woby, Get(STRINGS, 'WOBY_COMMANDS', 'COURIER')) and Ctl():PullUpMap(woby, ACTIONS.DIRECTCOURIER_MAP)
end

fn.WobyDash = function() -- credit: 川小胖 workshop-3460815078 from DoDoubleTapDir() in components/playercontroller.lua
  if not (IsPlaying('walter') and HasSkill('walter_woby_dash')) then return end

  local target_pos, player_pos = Get(TheInput, 'GetWorldPosition'), Get(ThePlayer, 'GetPosition')
  if not (target_pos and player_pos) then return end

  local picker = Get(ThePlayer, 'components', 'playeractionpicker')
  local dir = Get(target_pos - player_pos, 'GetNormalized')
  local act = Get(picker and picker:GetDoubleClickActions(nil, dir), 1)
  if Get(act, 'action') ~= ACTIONS.DASH then return end

  local x, z, no_force = Get(act, 'pos', 'local_pt', 'x'), Get(act, 'pos', 'local_pt', 'z')
  local mod_name, platform = Get(act, 'action', 'mod_name'), Get(act, 'pos', 'walkable_platform')
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
