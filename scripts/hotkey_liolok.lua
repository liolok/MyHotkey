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
  if type(IsRight) ~= 'function' then return end

  local inventory = Inv()

  local item = inventory:GetActiveItem()
  if IsRight(item) then return item end

  -- all items of all opened containers | 所有打开的容器的所有物品
  for container in pairs(inventory:GetOpenContainers()) do
    for _, item in pairs(Get(container, 'replica', 'container', 'GetItems') or {}) do
      if IsRight(item) then return item end
    end
  end

  -- all equipped items | 所有已装备物品
  for _, item in pairs(inventory:GetEquips()) do
    if IsRight(item) then return item end
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
      -- TODO: maybe?
    end
  end)
end

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

local function Tip(message)
  local talker, time, no_anim, force = Get(ThePlayer, 'components', 'talker'), nil, true, true
  return talker and talker:Say(message, time, no_anim, force)
end

--------------------------------------------------------------------------------

fn.DropLantern = function() return IsPlaying() and Drop(Find('lantern')) end

fn.UseBeargerFurSack = function()
  return (not IsInCD('Polar Bearger Bin') and IsPlaying()) and Use(Find('beargerfur_sack'), 'RUMMAGE')
end

local item_before_cane
fn.UseCane = function()
  if not IsPlaying() then return end

  local cane = FindPrefabs('cane', 'orangestaff')
    or Find('balloonspeed', function(inst) return not inst:HasTag('fueldepleted') end)
    or FindPrefabs('walking_stick', 'ruins_bat')
  if not cane then return end

  local hand_item = Inv():GetEquippedItem(EQUIPSLOTS.HANDS)
  if hand_item == cane then
    if item_before_cane then return Use(item_before_cane, 'EQUIP') end
  else
    item_before_cane = hand_item
    return Use(cane, 'EQUIP')
  end
end

fn.JumpInOrMigrate = function()
  if not IsPlaying() then return end

  local radius, ignore_height, must_tags, cant_tags, must_one_of_tags =
    40, true, nil, { 'channeling' }, { 'teleporter', 'migrator' }
  local target = FindClosestEntity(ThePlayer, radius, ignore_height, must_tags, cant_tags, must_one_of_tags)
  if not target then return end

  local action = target:HasTag('teleporter') and ACTIONS.JUMPIN or ACTIONS.MIGRATE
  return SendRPCToServer(RPC.ControllerActionButton, action.code, target)
end

fn.SaveGame = function() return IsPlaying() and IsInCD('Confirm Save') and not IsInCD('Save Game', 5) and c_save() end

fn.ResetGame = function() return IsPlaying() and IsInCD('Confirm Load') and not IsInCD('Load Game', 5) and c_reset() end

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

local item_before_lighter
fn.UseLighter = function()
  if not IsPlaying('willow') then return end

  local lighter = Find('lighter')
  if not lighter then return end

  local hand_item = Inv():GetEquippedItem(EQUIPSLOTS.HANDS)
  if hand_item == lighter then
    if item_before_lighter then return Use(item_before_lighter, 'EQUIP') end
  else
    item_before_lighter = hand_item
    Use(lighter, 'EQUIP')
  end

  return Use(lighter, ThePlayer:IsChannelCasting() and 'STOP_CHANNELCAST' or 'START_CHANNELCAST')
end

--------------------------------------------------------------------------------
-- Wolfgang | 沃尔夫冈

local item_before_dumbbell
fn.UseDumbBell = function()
  if not IsPlaying('wolfgang') then return end

  local bell = FindPrefabs(
    'dumbbell_gem',
    'dumbbell_marble',
    'dumbbell_golden',
    'dumbbell',
    'dumbbell_bluegem',
    'dumbbell_redgem',
    'dumbbell_heat'
  )
  if not bell then return end

  local hand_item = Inv():GetEquippedItem(EQUIPSLOTS.HANDS)
  if hand_item == bell then
    if item_before_dumbbell then return Use(item_before_dumbbell, 'EQUIP') end
  else
    item_before_dumbbell = hand_item
    Use(bell, 'EQUIP')
  end

  return Use(bell, bell:HasTag('lifting') and 'STOP_LIFT_DUMBBELL' or 'LIFT_DUMBBELL')
end

--------------------------------------------------------------------------------
-- Maxwell | 麦斯威尔

fn.UseMagicianToolOrStop = function()
  if IsInCD("Magician's Top Hat") or not IsPlaying('waxwell') then return end

  if ThePlayer:HasTag('usingmagiciantool') then -- already opened, close it.
    local act = BufferedAction(ThePlayer, ThePlayer, ACTIONS.STOPUSINGMAGICTOOL)
    local x, _, z = ThePlayer.Transform:GetWorldPosition()
    return IsMasterSim() and act:Do() or SendRPCToServer(RPC.RightClick, Get(act, 'action', 'code'), x, z, ThePlayer)
  end

  local hat = Find('tophat', 'magiciantool') -- find one to open
  if not hat then return end

  local act = BufferedAction(ThePlayer, nil, ACTIONS.USEMAGICTOOL, hat)
  return IsMasterSim() and act:Do() or SendRPCToServer(RPC.UseItemFromInvTile, Get(act, 'action', 'code'), hat, 1)
end

--------------------------------------------------------------------------------
-- Wormwood | 沃姆伍德

fn.MakeLivingLog = function()
  return IsPlaying('wormwood') and SendRPCToServer(RPC.MakeRecipeFromMenu, Get(AllRecipes, 'livinglog', 'rpc_id'))
end

--------------------------------------------------------------------------------
-- Wanda | 旺达

local function FindWatch(name) return Find('pocketwatch_' .. name, 'pocketwatch_inactive') end

fn.UsePocketWatchHeal = function() return IsPlaying('wanda') and Use(FindWatch('heal'), 'CAST_POCKETWATCH') end
fn.UsePocketWatchWarp = function() return IsPlaying('wanda') and Use(FindWatch('warp'), 'CAST_POCKETWATCH') end

--------------------------------------------------------------------------------

return fn
