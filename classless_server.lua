local AIO = AIO or require("AIO")

-- ============================================================
-- Utilities
-- ============================================================
local function toTable(str)
  local t = {}
  if str and str ~= '' then
    for v in string.gmatch(str, '([^,]+)') do
      table.insert(t, tonumber(v))
    end
  end
  return t
end

local function toString(tbl)
  if not tbl or #tbl == 0 then return '' end
  if #tbl == 1 then return tostring(tbl[1]) end
  return table.concat(tbl, ",")
end

local function listToSet(tbl)
  local s = {}
  if not tbl then return s end
  for i = 1, #tbl do
    local v = tbl[i]
    if v then s[v] = true end
  end
  return s
end

local function safeRemoveSpell(player, spellId)
  if not spellId or spellId == 0 then return end
  if not player or not player:HasSpell(spellId) then return end

  local ok = pcall(function()
    player:RemoveSpell(spellId, false, false)
  end)
  if not ok then
    pcall(function()
      player:RemoveSpell(spellId)
    end)
  end
end

-- ============================================================
-- Load data for Grants (from spells.lua / talents.lua)
-- Meta format:
--   entry[4] can be table and include: grants={...} or grants[rank]={...}
-- ============================================================
local GrantIndex = {} -- nodeSpellId -> { grantedSpellIds... }

local function _GetMeta(entry)
  if entry and type(entry[4]) == "table" then return entry[4] end
  return nil
end

local function BuildGrantIndexFromCLDB()
  GrantIndex = {}

  local function addEntry(entry)
    local ranks = entry[1] or {}
    local meta = _GetMeta(entry)
    if not meta or meta.grants == nil then return end

    for r=1,#ranks do
      local sid = ranks[r]
      local g = meta.grants
      local gList = nil

      if type(g) == "table" then
        if #g > 0 then
          gList = g
        elseif type(g[r]) == "table" then
          gList = g[r]
        end
      end

      if gList and #gList > 0 then
        local cp = {}
        for i=1,#gList do cp[i] = tonumber(gList[i]) end
        GrantIndex[sid] = cp
      end
    end
  end

  if not CLDB or not CLDB.data then return end

  if CLDB.data.spells then
    for _, classTbl in pairs(CLDB.data.spells) do
      for spec=1,#classTbl do
        for _, entry in ipairs(classTbl[spec][4] or {}) do
          addEntry(entry)
        end
      end
    end
  end

  if CLDB.data.talents then
    for _, classTbl in pairs(CLDB.data.talents) do
      for spec=1,#classTbl do
        for _, entry in ipairs(classTbl[spec][4] or {}) do
          addEntry(entry)
        end
      end
    end
  end
end

-- ============================================================
-- Stat Points System
-- ============================================================
local StatAllocation = AIO.AddHandlers("StatAllocation", {})
local playerStats = {} -- [guid] = {left=0, p1=0, p2=0, p3=0, p4=0, p5=0}

local function DBEnsureStatsRow(guid)
  local q = CharDBQuery("SELECT `guid` FROM `custom`.`classless_spells` WHERE guid="..guid)
  if not q then
    CharDBQuery("INSERT INTO `custom`.`classless_spells` (`guid`,`spells`,`tpells`,`talents`,`stats`) VALUES ("..guid..", '', '', '', '0,0,0,0,0,0')")
  end
end

local function DBReadStats(guid)
  local q = CharDBQuery("SELECT `stats` FROM `custom`.`classless_spells` WHERE guid="..guid)
  if q then
    local str = q:GetString(0)
    local parts = {}
    for v in string.gmatch(str, '([^,]+)') do
      table.insert(parts, tonumber(v) or 0)
    end
    return {
      left = parts[1] or 0,
      p1   = parts[2] or 0,
      p2   = parts[3] or 0,
      p3   = parts[4] or 0,
      p4   = parts[5] or 0,
      p5   = parts[6] or 0
    }
  end
  return {left=0, p1=0, p2=0, p3=0, p4=0, p5=0}
end

local function DBWriteStats(guid, stats)
  local str = string.format("%d,%d,%d,%d,%d,%d", 
    stats.left or 0, stats.p1 or 0, stats.p2 or 0, 
    stats.p3 or 0, stats.p4 or 0, stats.p5 or 0)
  CharDBQuery("UPDATE `custom`.`classless_spells` SET `stats`='"..str.."' WHERE guid="..guid)
end

local function LoadPlayerStats(player)
  local guid = player:GetGUIDLow()
  DBEnsureStatsRow(guid)
  playerStats[guid] = DBReadStats(guid)
end

local function UnloadPlayerStats(player)
  local guid = player:GetGUIDLow()
  if playerStats[guid] then
    DBWriteStats(guid, playerStats[guid])
    playerStats[guid] = nil
  end
end

local function SendStatsToClient(player)
  local guid = player:GetGUIDLow()
  local s = playerStats[guid] or {left=0, p1=0, p2=0, p3=0, p4=0, p5=0}
  return AIO.Handle(player, "StatAllocation", "SetStats", s.left, s.p1, s.p2, s.p3, s.p4, s.p5)
end

function StatAllocation.AttributesIncrease(player, statId, amount)
  local guid = player:GetGUIDLow()
  local s = playerStats[guid]
  if not s or s.left < amount then return end
  
  s.left = s.left - amount
  if statId == 1 then 
    s.p1 = s.p1 + amount
    player:SetStat(0, player:GetStat(0) + amount)
  elseif statId == 2 then 
    s.p2 = s.p2 + amount
    player:SetStat(1, player:GetStat(1) + amount)
  elseif statId == 3 then 
    s.p3 = s.p3 + amount
    player:SetStat(2, player:GetStat(2) + amount)
  elseif statId == 4 then 
    s.p4 = s.p4 + amount
    player:SetStat(3, player:GetStat(3) + amount)
  elseif statId == 5 then 
    s.p5 = s.p5 + amount
    player:SetStat(4, player:GetStat(4) + amount)
  end
  
  DBWriteStats(guid, s)
  SendStatsToClient(player)
  player:UpdateStats(statId - 1)
  player:SaveToDB()
end

function StatAllocation.AttributesDecrease(player, statId, amount)
  local guid = player:GetGUIDLow()
  local s = playerStats[guid]
  if not s then return end
  
  local current = 0
  if statId == 1 then current = s.p1
  elseif statId == 2 then current = s.p2
  elseif statId == 3 then current = s.p3
  elseif statId == 4 then current = s.p4
  elseif statId == 5 then current = s.p5
  end
  
  if current < amount then amount = current end
  if amount <= 0 then return end
  
  s.left = s.left + amount
  if statId == 1 then 
    s.p1 = s.p1 - amount
    player:SetStat(0, player:GetStat(0) - amount)
  elseif statId == 2 then 
    s.p2 = s.p2 - amount
    player:SetStat(1, player:GetStat(1) - amount)
  elseif statId == 3 then 
    s.p3 = s.p3 - amount
    player:SetStat(2, player:GetStat(2) - amount)
  elseif statId == 4 then 
    s.p4 = s.p4 - amount
    player:SetStat(3, player:GetStat(3) - amount)
  elseif statId == 5 then 
    s.p5 = s.p5 - amount
    player:SetStat(4, player:GetStat(4) - amount)
  end
  
  DBWriteStats(guid, s)
  SendStatsToClient(player)
  player:UpdateStats(statId - 1)
  player:SaveToDB()
end


local function TryLoadClassLessData()
  pcall(dofile, "lua_scripts\\ClassLess\\data\\spells.lua")
  pcall(dofile, "lua_scripts\\ClassLess\\data\\talents.lua")
  BuildGrantIndexFromCLDB()
end

TryLoadClassLessData()

-- ============================================================
-- Shared Cost Calculation Function
-- ============================================================
local function getCost(spellId)
  if not CLDB or not CLDB.data then return 0, 0 end

  -- Search in spells database
  for _, classTbl in pairs(CLDB.data.spells or {}) do
    for spec=1,#classTbl do
      for _, entry in ipairs(classTbl[spec][4] or {}) do
        local ranks = entry[1] or {}
        for r=1,#ranks do
          if ranks[r] == spellId then
            local meta = entry[4]
            local baseAP = 1
            local baseTP = 0

            if type(meta) == "table" then
              local cost = meta.cost or meta.Cost
              if not cost and (meta.ap or meta.tp or meta.AP or meta.TP or meta[1] or meta[2]) then
                cost = meta
              end
              if cost then
                local ap = cost.ap or cost.AP or cost[1]
                local tp = cost.tp or cost.TP or cost[2]
                if type(ap) == "table" then ap = ap[r] end
                if type(tp) == "table" then tp = tp[r] end
                ap = tonumber(ap) or 0
                tp = tonumber(tp) or 0
                if ap ~= nil or tp ~= nil then
                  return ap, tp
                end
              end
            end

            if meta == 1 then
              return baseAP, (r == 1) and 1 or 0
            end

            return baseAP, baseTP
          end
        end
      end
    end
  end

  -- Search in talents database
  for _, classTbl in pairs(CLDB.data.talents or {}) do
    for spec=1,#classTbl do
      for _, entry in ipairs(classTbl[spec][4] or {}) do
        local ranks = entry[1] or {}
        for r=1,#ranks do
          if ranks[r] == spellId then
            local meta = entry[4]
            local baseAP = 0
            local baseTP = 1

            if type(meta) == "table" then
              local cost = meta.cost or meta.Cost
              if not cost and (meta.ap or meta.tp or meta.AP or meta.TP or meta[1] or meta[2]) then
                cost = meta
              end
              if cost then
                local ap = cost.ap or cost.AP or cost[1]
                local tp = cost.tp or cost.TP or cost[2]
                if type(ap) == "table" then ap = ap[r] end
                if type(tp) == "table" then tp = tp[r] end
                ap = tonumber(ap) or 0
                tp = tonumber(tp) or 0
                if ap ~= nil or tp ~= nil then
                  return ap, tp
                end
              end
            end

            if meta == 1 then
              return (r == 1) and 1 or 0, baseTP
            end

            return baseAP, baseTP
          end
        end
      end
    end
  end

  return 0, 0
end

local function ExpandGrants(nodeSet)
  local out = {}
  for k,_ in pairs(nodeSet or {}) do out[k] = true end
  local q = {}
  for k,_ in pairs(out) do q[#q+1] = k end

  while #q > 0 do
    local id = q[#q]; q[#q] = nil
    local gl = GrantIndex[id]
    if gl then
      for i=1,#gl do
        local g = gl[i]
        if g and not out[g] then
          out[g] = true
          q[#q+1] = g
        end
      end
    end
  end

  return out
end

-- ============================================================
-- ClassLess (spells + talents) with diff-unlearn + grants expansion
-- ============================================================
local ClassLess = AIO.AddHandlers("ClassLess", {})

local spells, tpells, talents = {}, {}, {}

local function DBEnsureClasslessRow(guid)
  local q = CharDBQuery("SELECT `guid` FROM `custom`.`classless_spells` WHERE guid="..guid)
  if not q then
    CharDBQuery("INSERT INTO `custom`.`classless_spells` (`guid`,`spells`,`tpells`,`talents`,`stats`) VALUES ("..guid..", '', '', '', '0,0,0,0,0,0')")
  end
end

local function DBReadClassless(guid)
  local sp, tsp, tal = '', '', ''
  local q = CharDBQuery("SELECT `spells`,`tpells`,`talents` FROM `custom`.`classless_spells` WHERE guid="..guid)
  if q then
    sp  = q:GetString(0)
    tsp = q:GetString(1)
    tal = q:GetString(2)
  end
  return sp, tsp, tal
end

local function DBWriteClassless(guid, col, value)
  CharDBQuery("UPDATE `custom`.`classless_spells` SET `"..col.."`='"..value.."' WHERE guid="..guid)
end

local function LoadPlayerClassLess(player)
  local guid = player:GetGUIDLow()
  DBEnsureClasslessRow(guid)
  local sp, tsp, tal = DBReadClassless(guid)
  spells[guid]  = toTable(sp)
  tpells[guid]  = toTable(tsp)
  talents[guid] = toTable(tal)
end

local function UnloadPlayerClassLess(player)
  local guid = player:GetGUIDLow()
  if spells[guid]  then DBWriteClassless(guid, "spells",  toString(spells[guid])) end
  if tpells[guid]  then DBWriteClassless(guid, "tpells",  toString(tpells[guid])) end
  if talents[guid] then DBWriteClassless(guid, "talents", toString(talents[guid])) end
  spells[guid], tpells[guid], talents[guid] = nil, nil, nil
end

local function SendVars(msg, player)
  local guid = player:GetGUIDLow()
  local s = playerStats[guid] or {left=0, p1=0, p2=0, p3=0, p4=0, p5=0}
  msg:Add("ClassLess", "LoadVars",
    spells[guid]  or {},
    tpells[guid]  or {},
    talents[guid] or {},
    {s.p1, s.p2, s.p3, s.p4, s.p5} -- actual stats
  )
  return msg:Add("StatAllocation", "SetStats", s.left, s.p1, s.p2, s.p3, s.p4, s.p5)
end
AIO.AddOnInit(SendVars)

-- ============================================================
-- ApplyAll (stores only node lists, but teaches node+grants)
-- ============================================================
function ClassLess.ApplyAll(player, newSpells, newTpells, newTalents)
  local guid = player:GetGUIDLow()

  newSpells  = newSpells  or {}
  newTpells  = newTpells  or {}
  newTalents = newTalents or {}

  local AP_ITEM = 16203
  local TP_ITEM = 11135

  -- Use shared getCost() function defined at module level

  local oldSpells = spells[guid] or {}
  local oldTpells = tpells[guid] or {}
  local oldTalents = talents[guid] or {}
  
  local oldSet = listToSet(oldSpells)
  for k,_ in pairs(listToSet(oldTpells)) do oldSet[k] = true end
  for k,_ in pairs(listToSet(oldTalents)) do oldSet[k] = true end
  
  local newSet = listToSet(newSpells)
  for k,_ in pairs(listToSet(newTpells)) do newSet[k] = true end
  for k,_ in pairs(listToSet(newTalents)) do newSet[k] = true end
  
  local totalAP, totalTP = 0, 0
  
  for spellId,_ in pairs(newSet) do
    if not oldSet[spellId] then
      local ap, tp = getCost(spellId)
      totalAP = totalAP + ap
      totalTP = totalTP + tp
    end
  end
  
  for spellId,_ in pairs(oldSet) do
    if not newSet[spellId] then
      local ap, tp = getCost(spellId)
      totalAP = totalAP - ap
      totalTP = totalTP - tp
    end
  end
  
  if totalAP > 0 then
    local current = player:GetItemCount(AP_ITEM)
    if current < totalAP then
      player:SendBroadcastMessage("Insufficient Ability Points")
      return
    end
    player:RemoveItem(AP_ITEM, totalAP)
  elseif totalAP < 0 then
    player:AddItem(AP_ITEM, -totalAP)
  end
  
  if totalTP > 0 then
    local current = player:GetItemCount(TP_ITEM)
    if current < totalTP then
      player:SendBroadcastMessage("Insufficient Talent Points")
      return
    end
    player:RemoveItem(TP_ITEM, totalTP)
  elseif totalTP < 0 then
    player:AddItem(TP_ITEM, -totalTP)
  end

  local desiredNodes = listToSet(newSpells)
  for k,_ in pairs(listToSet(newTpells))  do desiredNodes[k] = true end
  for k,_ in pairs(listToSet(newTalents)) do desiredNodes[k] = true end

  local desiredAll = ExpandGrants(desiredNodes)

  local oldNodes = listToSet(oldSpells)
  for k,_ in pairs(listToSet(oldTpells))  do oldNodes[k] = true end
  for k,_ in pairs(listToSet(oldTalents)) do oldNodes[k] = true end

  local oldAll = ExpandGrants(oldNodes)

  for spellId,_ in pairs(oldAll) do
    if not desiredAll[spellId] then
      safeRemoveSpell(player, spellId)
    end
  end

  for spellId,_ in pairs(desiredAll) do
    if spellId and spellId ~= 0 and not player:HasSpell(spellId) then
      player:LearnSpell(spellId)
    end
  end

  pcall(function() player:CastSpell(player, 47292) end)

DBWriteClassless(guid, "spells", toString(newSpells))
  DBWriteClassless(guid, "tpells", toString(newTpells))
  DBWriteClassless(guid, "talents", toString(newTalents))

  spells[guid]  = newSpells
  tpells[guid]  = newTpells
  talents[guid] = newTalents
  
  local msg = AIO.Msg()
  SendVars(msg, player)
  msg:Send(player)
end

function ClassLess.UnlearnSpec(player, class, spec, mode)
  local guid = player:GetGUIDLow()
  local AP_ITEM = 16203
  local TP_ITEM = 11135

  -- Use shared getCost() function defined at module level

  local specSpells = {}
  if CLDB and CLDB.data and CLDB.data.spells and CLDB.data.spells[class] and CLDB.data.spells[class][spec] then
    for _, entry in ipairs(CLDB.data.spells[class][spec][4] or {}) do
      for _, sid in ipairs(entry[1] or {}) do
        table.insert(specSpells, sid)
      end
    end
  end
  
  local specTalents = {}
  if CLDB and CLDB.data and CLDB.data.talents and CLDB.data.talents[class] and CLDB.data.talents[class][spec] then
    for _, entry in ipairs(CLDB.data.talents[class][spec][4] or {}) do
      for _, sid in ipairs(entry[1] or {}) do
        table.insert(specTalents, sid)
      end
    end
  end
  
  local currentSpells = spells[guid] or {}
  local currentTpells = tpells[guid] or {}
  local currentTalents = talents[guid] or {}
  
  local refundAP, refundTP = 0, 0
  
  if mode == "spells" or mode == "both" then
    local newSpells = {}
    local newTpells = {}
    for _, sid in ipairs(currentSpells) do
      local found = false
      for _, specSid in ipairs(specSpells) do
        if sid == specSid then found = true break end
      end
      if not found then
        table.insert(newSpells, sid)
      else
        local ap, tp = getCost(sid)
        refundAP = refundAP + ap
        refundTP = refundTP + tp
      end
    end
    for _, sid in ipairs(currentTpells) do
      local found = false
      for _, specSid in ipairs(specSpells) do
        if sid == specSid then found = true break end
      end
      if not found then
        table.insert(newTpells, sid)
      else
        local ap, tp = getCost(sid)
        refundAP = refundAP + ap
        refundTP = refundTP + tp
      end
    end
    spells[guid] = newSpells
    tpells[guid] = newTpells
  end
  
  if mode == "talents" or mode == "both" then
    local newTalents = {}
    for _, sid in ipairs(currentTalents) do
      local found = false
      for _, specSid in ipairs(specTalents) do
        if sid == specSid then found = true break end
      end
      if not found then
        table.insert(newTalents, sid)
      else
        local ap, tp = getCost(sid)
        refundAP = refundAP + ap
        refundTP = refundTP + tp
      end
    end
    talents[guid] = newTalents
  end
  
  if refundAP > 0 then
    player:AddItem(AP_ITEM, refundAP)
  end
  if refundTP > 0 then
    player:AddItem(TP_ITEM, refundTP)
  end
  
  local desiredNodes = listToSet(spells[guid])
  for k,_ in pairs(listToSet(tpells[guid])) do desiredNodes[k] = true end
  for k,_ in pairs(listToSet(talents[guid])) do desiredNodes[k] = true end
  local desiredAll = ExpandGrants(desiredNodes)
  
  local oldNodes = listToSet(currentSpells)
  for k,_ in pairs(listToSet(currentTpells)) do oldNodes[k] = true end
  for k,_ in pairs(listToSet(currentTalents)) do oldNodes[k] = true end
  local oldAll = ExpandGrants(oldNodes)
  
  for spellId,_ in pairs(oldAll) do
    if not desiredAll[spellId] then
      safeRemoveSpell(player, spellId)
    end
  end
  
  pcall(function() player:CastSpell(player, 47292) end)
  
  player:SendBroadcastMessage("Unlearned "..mode.." for spec "..spec)
  DBWriteClassless(guid, "spells", toString(spells[guid]))
  DBWriteClassless(guid, "tpells", toString(tpells[guid]))
  DBWriteClassless(guid, "talents", toString(talents[guid]))
  
  local msg = AIO.Msg()
  SendVars(msg, player)
  msg:Send(player)
end

-- ============================================================
-- Player events
-- ============================================================
local function OnLogin(event, player)
  LoadPlayerClassLess(player)
  LoadPlayerStats(player) -- ADD THIS LINE

  -- Ensure grants are present on login too (learn missing)
  local guid = player:GetGUIDLow()
  local desiredNodes = listToSet(spells[guid] or {})
  for k,_ in pairs(listToSet(tpells[guid] or {}))  do desiredNodes[k] = true end
  for k,_ in pairs(listToSet(talents[guid] or {})) do desiredNodes[k] = true end
  local desiredAll = ExpandGrants(desiredNodes)

  for spellId,_ in pairs(desiredAll) do
    if spellId and spellId ~= 0 and not player:HasSpell(spellId) then
      player:LearnSpell(spellId)
    end
  end
  
  SendStatsToClient(player) -- ADD THIS LINE
end

local function OnLogout(event, player)
  UnloadPlayerClassLess(player)
  UnloadPlayerStats(player) -- ADD THIS LINE
end

RegisterPlayerEvent(3, OnLogin)
RegisterPlayerEvent(4, OnLogout)
