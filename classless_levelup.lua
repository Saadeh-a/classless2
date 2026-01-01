local AP_ITEM = 16203
local TP_ITEM = 11135
local STAT_ITEM = 132862
local STAT_POINTS_PER_USE = 5

local function OnLevelChanged(_, player, oldLevel)
  local newLevel = player:GetLevel()
  local gained = newLevel - oldLevel
  if gained <= 0 then return end

  player:AddItem(AP_ITEM, gained)

  local tpGained = math.max(0, newLevel - math.max(oldLevel, 9))
  if tpGained > 0 then
    player:AddItem(TP_ITEM, tpGained)
  end
end

local function OnUseStatItem(_, player, item)
  if item:GetEntry() ~= STAT_ITEM then return end
  
  local guid = player:GetGUIDLow()
  local q = CharDBQuery("SELECT `stats` FROM `custom`.`classless_spells` WHERE guid="..guid)
  if q then
    local str = q:GetString(0)
    local parts = {}
    for v in string.gmatch(str, '([^,]+)') do
      table.insert(parts, tonumber(v) or 0)
    end
    local left = (parts[1] or 0) + STAT_POINTS_PER_USE
    parts[1] = left
    local newStr = table.concat(parts, ",")
    CharDBQuery("UPDATE `custom`.`classless_spells` SET `stats`='"..newStr.."' WHERE guid="..guid)
    
    AIO.Handle(player, "StatAllocation", "SetStats", parts[1], parts[2], parts[3], parts[4], parts[5], parts[6])
    
    player:RemoveItem(STAT_ITEM, 1)
    player:SendBroadcastMessage("Gained "..STAT_POINTS_PER_USE.." stat points")



    local msg = AIO.Msg()
    msg:Add("StatAllocation", "SetStats", parts[1], parts[2], parts[3], parts[4], parts[5], parts[6])
    msg:Send(player)
  end
end
  end
end

RegisterPlayerEvent(13, OnLevelChanged)
RegisterPlayerEvent(8, OnUseStatItem)