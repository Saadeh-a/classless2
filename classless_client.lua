-- classless_client.lua

local AIO = AIO or require("AIO")

-- Send data files to client
if AIO.IsServer() then
  AIO.AddAddon("lua_scripts\\ClassLess\\data\\spells.lua",  "spells")
  AIO.AddAddon("lua_scripts\\ClassLess\\data\\talents.lua", "talents")
  AIO.AddAddon("lua_scripts\\ClassLess\\data\\locks.lua",   "locks")
  AIO.AddAddon("lua_scripts\\ClassLess\\data\\req.lua",     "req")
end
if AIO.AddAddon() then return end

local db = CLDB

local WOW_GOLD  = "|cffffd100"
local WOW_WHITE = "|cffffffff"
local WOW_RED   = "|cffff0000"
local WOW_GREEN = "|cff00ff00"

-- ============================================================
-- UI sizing / spacing
-- ============================================================
local CL_SPEC_ICON_SIZE   = 30
local CL_NODE_ICON_SIZE   = 30
local CL_BORDER_SCALE     = 1.62 

local CL_TALENT_COLS      = 4
local CL_TALENT_COL_STEP  = 58
local CL_TALENT_ROW_STEP  = 36
local CL_TALENT_TOP_PAD   = 18

-- Spells grid spacing
local CL_SPELL_LEFT_PAD   = 12
local CL_SPELL_TOP_PAD    = 18
local CL_SPELL_COL_STEP   = 122
local CL_SPELL_ROW_STEP   = 36

-- Spell name placement
local CL_SPELL_TEXT_X     = 3
local CL_SPELL_NAME_Y     = -1
local CL_SPELL_TEXT_WIDTH = 90

-- Items used as currencies
local AP_ITEM = 16203
local TP_ITEM = 11135

-- Requested icons
local AP_ICON = "Interface\\Icons\\inv_enchant_essenceeternallarge"    
local TP_ICON = "Interface\\Icons\\inv_enchant_essencemysticallarge" 
local SP_ICON = "Interface\\Icons\\inv_enchant_essenceastrallarge"  

-- tentative
local spellsplus,spellsminus = {},{}
local tpellsplus,tpellsminus = {},{}
local talentsplus,talentsminus = {},{}

-- stats cache
local StatHandlers = AIO.AddHandlers("StatAllocation", {})
local statCache = { left=0, p1=0, p2=0, p3=0, p4=0, p5=0 }
local statUI = {}

local function ApplyStatsToUI()
  if statUI.str then statUI.str:SetText(statCache.p1 or 0) end
  if statUI.agi then statUI.agi:SetText(statCache.p2 or 0) end
  if statUI.sta then statUI.sta:SetText(statCache.p3 or 0) end
  if statUI.int then statUI.int:SetText(statCache.p4 or 0) end
  if statUI.spi then statUI.spi:SetText(statCache.p5 or 0) end
  if statUI.left then statUI.left:SetText(statCache.left or 0) end
end

function StatHandlers.SetStats(player, left, p1, p2, p3, p4, p5)
  statCache.left = left or 0
  statCache.p1   = p1 or 0
  statCache.p2   = p2 or 0
  statCache.p3   = p3 or 0
  statCache.p4   = p4 or 0
  statCache.p5   = p5 or 0
  ApplyStatsToUI()
  if UpdateTopBar then UpdateTopBar() end
end

local function FrameShow(fname)
  local f = (type(fname)=="table") and fname or _G[fname]
  if f and f:IsVisible()~=1 then f:Show() end
end
local function FrameHide(fname)
  local f = (type(fname)=="table") and fname or _G[fname]
  if f and f:IsVisible()==1 then f:Hide() end
end

local CLASS_DISPLAY = {
  WARRIOR="Warrior", PALADIN="Paladin", HUNTER="Hunter", ROGUE="Rogue", PRIEST="Priest",
  DEATHKNIGHT="Deathknight", SHAMAN="Shaman", MAGE="Mage", WARLOCK="Warlock", DRUID="Druid",
}

local function ClassIconTex(classFile, size, xOff, yOff)
  local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
  size = size or 14
  xOff = xOff or 0
  yOff = yOff or -1
  if not c then return "" end

  local l,r,t,b = c[1]*256, c[2]*256, c[3]*256, c[4]*256
  return string.format(
    "|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:%d:%d:%d:%d:256:256:%d:%d:%d:%d|t",
    size, size, xOff, yOff, l, r, t, b
  )
end

local function Trim(s) return (s or ""):gsub("^%s+",""):gsub("%s+$","") end

-- ============================================================
-- Pixel-width text wrapping
-- ============================================================
local _CLMeasureFrame = CreateFrame("Frame", nil, UIParent)
_CLMeasureFrame:Hide()
local _CLMeasureFS = _CLMeasureFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
_CLMeasureFS:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")

local function TextWidthPx(text)
  _CLMeasureFS:SetText(text or "")
  return (_CLMeasureFS:GetStringWidth() or 0)
end

local function WrapTwoLines(name, maxWidth)
  name = Trim(name)
  if name == "" then return "", "" end
  maxWidth = tonumber(maxWidth) or CL_SPELL_TEXT_WIDTH

  local wFull = TextWidthPx(name)
  if wFull <= maxWidth * 0.92 then return name, "" end

  local words = {}
  for w in name:gmatch("%S+") do table.insert(words, w) end

  if #words == 1 then
    local s = words[1]
    local cut = 0
    for i=1,#s do
      if TextWidthPx(s:sub(1,i)) > maxWidth then cut = i-1 break end
    end
    if cut < 1 then cut = math.max(1, math.floor(#s/2)) end
    return s:sub(1,cut), s:sub(cut+1)
  end

  if wFull <= maxWidth then return name, "" end

  local bestL1, bestL2 = words[1], table.concat(words, " ", 2)
  local bestScore = 1e18

  for i=1,#words-1 do
    local l1 = table.concat(words, " ", 1, i)
    local l2 = table.concat(words, " ", i+1, #words)
    local w1, w2 = TextWidthPx(l1), TextWidthPx(l2)

    if w1 <= maxWidth and w2 <= maxWidth then
      local score = math.abs(w1-w2) + (math.max(w1,w2) * 0.01)
      if #words >= 3 and i == (#words-1) then score = score - 2 end
      if score < bestScore then
        bestScore = score
        bestL1, bestL2 = l1, l2
      end
    end
  end

  if bestScore < 1e18 then return bestL1, bestL2 end

  local l1 = words[1]
  for i=2,#words do
    local candidate = table.concat(words, " ", 1, i)
    if TextWidthPx(candidate) <= maxWidth then l1 = candidate else break end
  end
  local l2 = Trim(name:sub(#l1+1))
  if l2 == "" then l2 = table.concat(words, " ", 2) end
  return l1, l2
end

local function DoShit()
  local function tCopy(t)
    local u = {}
    for k, v in pairs(t or {}) do u[k] = v end
    return setmetatable(u, getmetatable(t))
  end
  local function tRemoveKey(tbl, key)
    for i=#tbl,1,-1 do if tbl[i]==key then tremove(tbl,i) end end
  end

  local function FixTooltipFirstLineFont(tt)
    local n = tt:GetName()
    local L1 = _G[n.."TextLeft1"]
    local R1 = _G[n.."TextRight1"]
    if L1 then L1:SetFontObject(GameTooltipText) end
    if R1 then R1:SetFontObject(GameTooltipText) end
  end

  -- ============================================================
  -- Costs + Meta
  -- ============================================================
  local CostIndex  = {}
  local GrantIndex = {}
  local NoteIndex  = {}

  local function GetNodeMeta(entry)
    local m = entry and entry[4]
    if type(m) == "table" then return m end
    return nil
  end

  local function GetNodeCost(mode, entry, rank)
    local meta = entry and entry[4]
    local baseAP = (mode=="spell") and 1 or 0
    local baseTP = (mode=="talent") and 1 or 0

    if type(meta) == "table" then
      local cost = meta.cost or meta.Cost
      if not cost and (meta.ap or meta.tp or meta.AP or meta.TP or meta[1] or meta[2]) then
        cost = meta
      end
      if not cost then return baseAP, baseTP end

      local ap = cost.ap or cost.AP or cost[1]
      local tp = cost.tp or cost.TP or cost[2]
      if type(ap) == "table" then ap = ap[rank] end
      if type(tp) == "table" then tp = tp[rank] end

      ap = tonumber(ap)
      tp = tonumber(tp)

      if ap == nil and tp == nil then return baseAP, baseTP end
      return tonumber(ap or 0) or 0, tonumber(tp or 0) or 0
    end

    if meta == 1 then
      if mode == "spell" then return baseAP, (rank == 1) and 1 or 0
      else return (rank == 1) and 1 or 0, baseTP end
    end

    return baseAP, baseTP
  end

  local function BuildCostIndex()
    wipe(CostIndex)
    for class, classTbl in pairs(db.data.spells or {}) do
      for spec=1,#classTbl do
        for _, entry in ipairs(classTbl[spec][4] or {}) do
          local ranks = entry[1] or {}
          for r=1,#ranks do
            local sid = ranks[r]
            local ap,tp = GetNodeCost("spell", entry, r)
            CostIndex[sid] = { ap=ap, tp=tp }
          end
        end
      end
    end

    for class, classTbl in pairs(db.data.talents or {}) do
      for spec=1,#classTbl do
        for _, entry in ipairs(classTbl[spec][4] or {}) do
          local ranks = entry[1] or {}
          for r=1,#ranks do
            local sid = ranks[r]
            local ap,tp = GetNodeCost("talent", entry, r)
            CostIndex[sid] = { ap=ap, tp=tp }
          end
        end
      end
    end
  end

  local function BuildIndexes()
    wipe(GrantIndex)
    wipe(NoteIndex)
    local function IndexEntry(entry)
      local meta = GetNodeMeta(entry)
      if not meta then return end
      local ranks = entry[1] or {}
      if type(meta.grants) == "table" then
        for r=1,#ranks do
          local sid = ranks[r]
          GrantIndex[sid] = tCopy(meta.grants)
        end
      end
      if meta.note ~= nil and tostring(meta.note) ~= "" then
        for r=1,#ranks do
          local sid = ranks[r]
          NoteIndex[sid] = tostring(meta.note)
        end
      end
    end
    for class, classTbl in pairs(db.data.spells or {}) do
      for spec=1,#classTbl do
        for _, entry in ipairs(classTbl[spec][4] or {}) do IndexEntry(entry) end
      end
    end
    for class, classTbl in pairs(db.data.talents or {}) do
      for spec=1,#classTbl do
        for _, entry in ipairs(classTbl[spec][4] or {}) do IndexEntry(entry) end
      end
    end
  end

  local function BuildEffectiveArray(base, plus, minus)
    local arr = tCopy(base or {})
    for i=1,#(plus or {}) do
      local id = plus[i]
      if id and not tContains(arr, id) then tinsert(arr, id) end
    end
    for i=1,#(minus or {}) do
      local id = minus[i]
      if id then tRemoveKey(arr, id) end
    end
    return arr
  end

  local function AddGrantsToSet(set)
    local changed = true
    local guard = 0
    while changed and guard < 20 do
      changed = false
      guard = guard + 1
      for sid,_ in pairs(set) do
        local g = GrantIndex[sid]
        if g then
          for i=1,#g do
            local gid = g[i]
            if gid and not set[gid] then
              set[gid] = true
              changed = true
            end
          end
        end
      end
    end
  end

  local function BuildEffectiveSets()
    local effSpells  = BuildEffectiveArray(db.spells,  spellsplus,  spellsminus)
    local effTpells  = BuildEffectiveArray(db.tpells,  tpellsplus,  tpellsminus)
    local effTalents = BuildEffectiveArray(db.talents, talentsplus, talentsminus)
    local set = {}
    for i=1,#effSpells  do set[effSpells[i]]  = true end
    for i=1,#effTpells  do set[effTpells[i]]  = true end
    for i=1,#effTalents do set[effTalents[i]] = true end
    AddGrantsToSet(set)
    return effSpells, effTpells, effTalents, set
  end

  local function SumUsedCosts(set)
    local usedAP, usedTP = 0, 0
    for id,_ in pairs(set or {}) do
      local c = CostIndex[id]
      if c then
        usedAP = usedAP + (c.ap or 0)
        usedTP = usedTP + (c.tp or 0)
      end
    end
    return usedAP, usedTP
  end
  
  -- ============================================================
  -- Utility Functions
  -- ============================================================
  local function CreateTexture(base, layer, path, blend)
    local t = base:CreateTexture(nil, layer)
    if path then t:SetTexture(path) end
    if blend then t:SetBlendMode(blend) end
    return t
  end

  local function FrameBackground(frame, background)
    local t = CreateTexture(frame, "BACKGROUND")
    t:SetPoint("TOPLEFT"); frame.topleft = t
    t = CreateTexture(frame, "BACKGROUND")
    t:SetPoint("TOPLEFT", frame.topleft, "TOPRIGHT"); frame.topright = t
    t = CreateTexture(frame, "BACKGROUND")
    t:SetPoint("TOPLEFT", frame.topleft, "BOTTOMLEFT"); frame.bottomleft = t
    t = CreateTexture(frame, "BACKGROUND")
    t:SetPoint("TOPLEFT", frame.topleft, "BOTTOMRIGHT"); frame.bottomright = t
    frame.topleft:SetTexture(background.."-TopLeft")
    frame.topright:SetTexture(background.."-TopRight")
    frame.bottomleft:SetTexture(background.."-BottomLeft")
    frame.bottomright:SetTexture(background.."-BottomRight")
  end

  local function FrameLayout(frame, width, height)
    local texture_height = height / (256+75)
    local texture_width = width / (256+44)
    frame:SetSize(width, height)
    local wl, wr, ht, hb = texture_width*256, texture_width*64, texture_height*256, texture_height*128
    frame.topleft:SetSize(wl, ht)
    frame.topright:SetSize(wr, ht)
    frame.bottomleft:SetSize(wl, hb)
    frame.bottomright:SetSize(wr, hb)
  end

  local function MakeButton(name, parent)
    local button = CreateFrame("Button", name, parent)
    button:SetNormalFontObject(GameFontNormal)
    button:SetHighlightFontObject(GameFontHighlight)
    button:SetDisabledFontObject(GameFontDisable)
    local texture = button:CreateTexture()
    texture:SetTexture"Interface\\Buttons\\UI-Panel-Button-Up"
    texture:SetTexCoord(0, 0.625, 0, 0.6875)
    texture:SetAllPoints(button)
    button:SetNormalTexture(texture)
    texture = button:CreateTexture()
    texture:SetTexture"Interface\\Buttons\\UI-Panel-Button-Down"
    texture:SetTexCoord(0, 0.625, 0, 0.6875)
    texture:SetAllPoints(button)
    button:SetPushedTexture(texture)
    texture = button:CreateTexture()
    texture:SetTexture"Interface\\Buttons\\UI-Panel-Button-Highlight"
    texture:SetTexCoord(0, 0.625, 0, 0.6875)
    texture:SetAllPoints(button)
    button:SetHighlightTexture(texture)
    return button
  end

  local function MakeRankFrame(button)
    local bg = CreateFrame("Frame", nil, button)
    bg:SetSize(22, 12)
    bg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
    bg:SetBackdrop({
      bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 6,
      insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    bg:SetBackdropColor(0, 0, 0, 1)
    bg:SetBackdropBorderColor(0, 0, 0, 1)
    bg:SetFrameLevel(button:GetFrameLevel() + 5)
    bg:Hide()
    button.rankBG = bg
    local fs = bg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", bg, "CENTER", 0, 0)
    fs:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    return fs
  end

  local function NewButton(name, parent, size, icon, wantRank, a,b,c,d)
    local button = CreateFrame("Button", name, parent)
    button:SetSize(size, size)
    button:EnableMouse(true)
    button:SetHitRectInsets(-2,-2,-2,-2)

    local it = CreateTexture(button, "BORDER")
    it:SetSize(size, size)
    it:SetPoint("CENTER")
    button.texture = it
    if icon then
      it:SetTexture(icon)
      if a~=nil then it:SetTexCoord(a,b,c,d) end
    end

    local base = CreateTexture(button, "ARTWORK", "Interface\\Buttons\\UI-Quickslot2")
    base:SetSize(size*CL_BORDER_SCALE, size*CL_BORDER_SCALE)
    base:SetPoint("CENTER", button, "CENTER", 0, 0)
    base:SetVertexColor(1,1,1,1)
    button.baseBorder = base
    button:SetNormalTexture(base)

    local color = CreateTexture(button, "OVERLAY", "Interface\\Buttons\\UI-Quickslot2", "ADD")
    color:SetSize(size*CL_BORDER_SCALE, size*CL_BORDER_SCALE)
    color:SetPoint("CENTER", button, "CENTER", 0, 0)
    color:SetAlpha(0)
    button.colorBorder = color

    local pushed = CreateTexture(button, "ARTWORK", "Interface\\Buttons\\UI-Quickslot-Depress")
    pushed:SetSize(size, size)
    pushed:SetPoint("CENTER")
    button:SetPushedTexture(pushed)

    local hl = CreateTexture(button, "HIGHLIGHT", "Interface\\Buttons\\ButtonHilight-Square", "ADD")
    hl:SetSize(size, size)
    hl:SetPoint("CENTER")
    button:SetHighlightTexture(hl)

    if wantRank then button.rank = MakeRankFrame(button) end
    return button
  end

  local function SetButtonBorder(button, mode, state, rank, ranks, selected)
    local function Base(r,g,b,a)
      button.baseBorder:SetVertexColor(r,g,b)
      button.baseBorder:SetAlpha(a or 1)
    end
    local function Color(r,g,b,a, hideBase)
      button.colorBorder:SetVertexColor(r,g,b)
      button.colorBorder:SetAlpha(a or 0)
      if hideBase and (a or 0) > 0 then button.baseBorder:SetAlpha(0) else button.baseBorder:SetAlpha(1) end
    end

    Base(1,1,1,1)
    Color(1,1,1,0,false)

    if selected then
      Color(1.0,0.82,0.0,0.48,true)
      return
    end

    -- Fix for "Grey Bug": Check Learned status first!
    if mode=="spell" then
      if rank > 0 then Color(1.0,0.82,0.0,0.48,true) end
      if state=="disabled" then
         Base(0.55,0.55,0.55,1)
         Color(0.55,0.55,0.55,0.12,false)
      end
      return
    end

    if mode=="talent" then
      if ranks > 0 and rank >= ranks then
        Color(1.0,0.82,0.0,1.0,true) -- Solid Yellow for Max
        return
      elseif rank > 0 then
        Color(0.0,1.0,0.0,1.0,true) -- Solid Green for Learned
        return
      end
    end

    -- Only if NOT learned do we consider disabled state for the button
    if state=="disabled" then
      Base(0.55,0.55,0.55,1)
      Color(0.55,0.55,0.55,0.12,false)
      return
    end
    
    -- Default grey for unlearned and enabled
    if mode == "talent" then
      Base(0.4, 0.4, 0.4, 1.0)
    end
  end

  -- ============================================================
  -- Tooltip helpers
  -- ============================================================
  local DIVIDER_TEX = "Interface\\DialogFrame\\UI-DialogBox-Divider"

  local function AddDivider(tt)
    local w = math.floor((tt:GetWidth() or 320) - 24)
    if w < 180 then w = 300 end
    tt:AddLine("|T"..DIVIDER_TEX..":8:"..w.."|t", 1,1,1, false)
  end

  local function SafeSpellLink(spell)
    local link = GetSpellLink(spell)
    if link == nil then
      link = GetSpellLink(78)
      if link then link = string.gsub(link, "78", tostring(spell)) end
    end
    return link
  end

  local function ParseTooltipRich(spell)
    local f = _G["CLTmpTooltip"] or CreateFrame("GameTooltip", "CLTmpTooltip", UIParent, "GameTooltipTemplate")
    f:SetOwner(UIParent, "ANCHOR_NONE")
    f:ClearLines()
    local link = SafeSpellLink(spell)
    if link then f:SetHyperlink(link) end
    local num = f:NumLines() or 0
    local lines = {}
    for i=1,num do
      local lfs = _G["CLTmpTooltipTextLeft"..i]
      local rfs = _G["CLTmpTooltipTextRight"..i]
      local lt = lfs and lfs:GetText() or nil
      local rt = rfs and rfs:GetText() or nil
      if lt or rt then
        local lr,lg,lb = 1,1,1
        local rr,rg,rb = 1,1,1
        if lfs then lr,lg,lb = lfs:GetTextColor() end
        if rfs then rr,rg,rb = rfs:GetTextColor() end
        lines[i] = { l=lt, r=rt, lr=lr, lg=lg, lb=lb, rr=rr, rg=rg, rb=rb }
      end
    end
    f:ClearLines()
    f:Hide()
    return lines, num
  end

  local BOOK_SPELL = _G.BOOKTYPE_SPELL or "spell"

  local function CL_StripColorCodes(s)
    if not s or s == "" then return "" end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    return s
  end

  local function CL_StripTextures(s)
    if not s or s == "" then return "" end
    s = s:gsub("|T.-|t", "")
    return s
  end

  local function CL_NormalizeTooltipText(s)
    s = CL_StripTextures(CL_StripColorCodes(s or ""))
    s = Trim(s)
    s = s:gsub("%s+", " ")
    return s
  end

  local function CL_GetSpellIdFromLink(link)
    if not link then return nil end
    local id = link:match("spell:(%d+)")
    return id and tonumber(id) or nil
  end

  local function CL_FindSpellBookSlotById(spellId)
    if not spellId then return nil end
    if type(GetNumSpellTabs) ~= "function" or type(GetSpellTabInfo) ~= "function" then return nil end
    if type(GetSpellLink) ~= "function" then return nil end
    for tab = 1, GetNumSpellTabs() do
      local _, _, offset, numSpells = GetSpellTabInfo(tab)
      offset = tonumber(offset) or 0
      numSpells = tonumber(numSpells) or 0
      for i = 1, numSpells do
        local slot = offset + i
        local link = GetSpellLink(slot, BOOK_SPELL)
        local sid = CL_GetSpellIdFromLink(link)
        if sid == spellId then return slot end
      end
    end
    return nil
  end

  local function CL_IsPassiveBySpellBook(spellId)
    if type(_G.IsPassiveSpell) ~= "function" then return nil end
    local slot = CL_FindSpellBookSlotById(spellId)
    if not slot then return nil end
    local ok, res = pcall(_G.IsPassiveSpell, slot, BOOK_SPELL)
    if ok and res ~= nil then return (res == true or res == 1) end
    return nil
  end

  local function CL_IsPassiveByTooltipToken(lines, num)
    if not lines or (num or 0) <= 0 then return false end
    local passiveToken = _G.PASSIVE or "Passive"
    local r1 = lines[1] and lines[1].r
    if r1 and r1 ~= "" and CL_NormalizeTooltipText(r1) == passiveToken then return true end
    for i = 1, math.min(num or 0, 4) do
      local l = lines[i] and lines[i].l
      if l and l ~= "" and CL_NormalizeTooltipText(l) == passiveToken then return true end
    end
    return false
  end

  local function CL_IsProbablyActiveFromTooltip(lines, num)
    if not lines or (num or 0) <= 0 then return false end
    local function looksLikeCostLine(low)
      if low:match("^%d+%s+mana") then return true end
      if low:match("^%d+%%?%s*of%s*base%s+mana") then return true end
      if low:match("^%d+%s+rage") then return true end
      if low:match("^%d+%s+energy") then return true end
      if low:match("^%d+%s+focus") then return true end
      if low:match("^%d+%s+runic%s+power") then return true end
      return false
    end
    local function chk(s)
      s = CL_NormalizeTooltipText(s)
      if s == "" then return false end
      local low = s:lower()
      if low == "instant" then return true end
      if low:match("%d+%s*sec%s+cast") then return true end
      if low:match("%d+%s*min%s+cast") then return true end
      if low == "melee range" then return true end
      if low:match("%d+%s*yds?%s+range") then return true end
      if low:find("cooldown remaining", 1, true) then return true end
      if low:match("%d+%s*sec%s+cooldown") then return true end
      if low:match("%d+%s*min%s+cooldown") then return true end
      if low:match("^reagents") then return true end
      if looksLikeCostLine(low) then return true end
      return false
    end
    for i = 1, math.min(num, 6) do
      local ln = lines[i]
      if ln and (chk(ln.l) or chk(ln.r)) then return true end
    end
    return false
  end

  local function CL_IsSpellPassive(spellId, parsedLines, parsedNum)
    if not spellId then return false end
    local byBook = CL_IsPassiveBySpellBook(spellId)
    if byBook ~= nil then return byBook end
    if parsedLines and parsedNum then
      if CL_IsPassiveByTooltipToken(parsedLines, parsedNum) then return true end
      if CL_IsProbablyActiveFromTooltip(parsedLines, parsedNum) then return false end
      return true
    end
    local lines, num = ParseTooltipRich(spellId)
    if CL_IsPassiveByTooltipToken(lines, num) then return true end
    if CL_IsProbablyActiveFromTooltip(lines, num) then return false end
    return true
  end

  local function CL_LineStartsWithRequires(txt)
    if not txt or txt == "" then return false end
    local clean = CL_NormalizeTooltipText(txt)
    local low = clean:lower()
    return low:find("^requires") ~= nil
  end

  local function AppendSpellBody(tt, spellId, startLine, opts)
    opts = opts or {}
    local lines, num = opts.lines, opts.num
    if not lines or not num then lines, num = ParseTooltipRich(spellId) end
    num = num or 0
    if num <= 0 then return end
    local startAt = tonumber(startLine) or 2
    if startAt < 1 then startAt = 1 end
    local isPassive = (opts.isPassive ~= nil) and opts.isPassive or CL_IsSpellPassive(spellId, lines, num)
    local skipRequiresForPassive = (opts.skipRequiresForPassive ~= false)
    local forceSkipRequires = (opts.skipRequires == true)
    local function isRequiresLine(ln)
      if not ln then return false end
      return CL_LineStartsWithRequires(ln.l) or CL_LineStartsWithRequires(ln.r)
    end
    local i = startAt
    while i <= num do
      local ln = lines[i]
      if ln then
        local reqLine = isRequiresLine(ln)
        if reqLine and (forceSkipRequires or (skipRequiresForPassive and isPassive)) then
          i = i + 1
        else
          if reqLine and (ln.r == nil or ln.r == "") then
            local merged = ln.l or ""
            local j = i + 1
            while j <= num do
              local nxt = lines[j]
              if not nxt then j = j + 1
              else
                if (nxt.r and nxt.r ~= "") then break end
                local nclean = CL_NormalizeTooltipText(nxt.l or "")
                if nclean == "" then break end
                if CL_LineStartsWithRequires(nxt.l) then break end
                if nclean:find(":", 1, true) then break end
                if nclean:match("%d") then break end
                if #nclean > 24 then break end
                merged = merged .. " " .. nclean
                j = j + 1
              end
            end
            tt:AddLine(merged, ln.lr or 1, ln.lg or 1, ln.lb or 1, false)
            i = j
          else
            if ln.r and ln.r ~= "" then
              tt:AddDoubleLine(ln.l or "", ln.r, ln.lr or 1, ln.lg or 1, ln.lb or 1, ln.rr or 1, ln.rg or 1, ln.rb or 1)
            else
              tt:AddLine(ln.l or "", ln.lr or 1, ln.lg or 1, ln.lb or 1, true)
            end
            i = i + 1
          end
        end
      else i = i + 1 end
    end
  end

  local function AppendSpellSection(tt, spellId, showIcon, opts)
    local name, _, icon = GetSpellInfo(spellId)
    name = name or ("Spell "..tostring(spellId))
    icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    local lines, num = ParseTooltipRich(spellId)
    local ln1 = lines and lines[1] or nil
    local leftText = name
    if showIcon then leftText = "|T"..icon..":18|t "..leftText end
    if ln1 and ln1.r and ln1.r ~= "" then
      tt:AddDoubleLine(leftText, ln1.r, 1,1,1, ln1.rr or 1, ln1.rg or 1, ln1.rb or 1)
    else
      tt:AddLine(WOW_WHITE..leftText.."|r", 1,1,1, true)
    end
    opts = opts or {}
    opts.lines = lines
    opts.num   = num
    AppendSpellBody(tt, spellId, 2, opts)
  end

  local function BuildRequiresLine(reqLevel)
    if not reqLevel then return nil end
    local met = UnitLevel("player") >= reqLevel
    local num = (met and WOW_GREEN or WOW_RED)..tostring(reqLevel).."|r"
    return WOW_GOLD.."Requires level:|r "..num
  end

  local function BuildCostLine(apAvail, tpAvail, costAP, costTP)
    costAP = tonumber(costAP or 0) or 0
    costTP = tonumber(costTP or 0) or 0
    local s = WOW_GOLD.."Cost:|r "
    if costAP > 0 then
      local c = (apAvail >= costAP) and WOW_GREEN or WOW_RED
      s = s .. c .. tostring(costAP) .. "|r |T"..AP_ICON..":12|t"
    end
    if costTP > 0 then
      if costAP > 0 then s = s .. " " end
      local c = (tpAvail >= costTP) and WOW_GREEN or WOW_RED
      s = s .. c .. tostring(costTP) .. "|r |T"..TP_ICON..":12|t"
    end
    return s
  end

  local function SpellButtonTooltip(button, nspell, spellForId, rank, ranks, reqLevel, apAvail, tpAvail, costAP, costTP, lock, req, rreq)
    local bname = button:GetName()
    button.tooltip = _G[bname..'tooltip'] or CreateFrame('GameTooltip', bname..'tooltip', button, 'GameTooltipTemplate')
    button:SetScript("OnEnter", function(self)
      local tt = button.tooltip
      tt:Hide()
      tt:SetOwner(button, "ANCHOR_RIGHT")
      tt:ClearLines()
      local mainSpell = nspell or spellForId
      local grants = GrantIndex[mainSpell] or GrantIndex[spellForId]
      local hasGrants = (type(grants)=="table" and #grants > 0)
      local note = NoteIndex[mainSpell] or NoteIndex[spellForId]
      if (not note or note == "") and not hasGrants then
        AppendSpellBody(tt, mainSpell, 1)
      else
        if note and note ~= "" then
          tt:AddLine(WOW_WHITE..tostring(note).."|r", 1,1,1, true)
          AddDivider(tt)
        end
        AppendSpellSection(tt, mainSpell, hasGrants)
        if hasGrants then
          for i=1,#grants do
            local gid = grants[i]
            if gid then
              AddDivider(tt)
              AppendSpellSection(tt, gid, true, { skipRequires = true })
            end
          end
        end
      end
      if rreq~=nil then tt:AddLine(rreq, 1,0,0, true) end
      if req~=nil  then tt:AddLine(req,  1,0,0, true) end
      if lock~=nil then tt:AddLine(lock, 1,0,0, true) end
      if rank < ranks then
        tt:AddLine(" ")
        tt:AddLine(BuildCostLine(apAvail, tpAvail, costAP, costTP), 1,1,1, true)
        local rline = BuildRequiresLine(reqLevel)
        if rline then tt:AddLine(rline, 1,1,1, true) end
      end
      tt:AddLine("SPELLID: "..tostring(spellForId), 1,1,1, true)
      FixTooltipFirstLineFont(tt)
      tt:Show()
    end)
    button:SetScript("OnLeave", function() button.tooltip:Hide() end)
  end

  local function TalentButtonTooltip(button, spellid, rank, ranks, reqLevel, apAvail, tpAvail, costAP, costTP, lock, req, rreq, shownSpellIdForIdLine, canLearnNow)
    local bname = button:GetName()
    button.tooltip = _G[bname..'tooltip'] or CreateFrame('GameTooltip', bname..'tooltip', button, 'GameTooltipTemplate')
    button:SetScript("OnEnter", function(self)
      local tt = button.tooltip
      tt:Hide()
      tt:SetOwner(button, "ANCHOR_RIGHT")
      tt:ClearLines()
      local curSpell = spellid[(rank>0) and rank or 1]
      local nextSpell = nil
      if rank > 0 and rank < ranks then nextSpell = spellid[rank+1] end
      local metaSpell = (rank < ranks and spellid[(rank>0 and rank+1) or 1]) or curSpell
      local grants = GrantIndex[metaSpell] or GrantIndex[curSpell]
      local hasGrants = (type(grants)=="table" and #grants > 0)
      local note = NoteIndex[metaSpell] or NoteIndex[curSpell] or (nextSpell and NoteIndex[nextSpell])

      if note and note ~= "" then
        tt:AddLine(WOW_GREEN..tostring(note).."|r", 1,1,1, true)
        AddDivider(tt)
      end

      local curName, _, curIcon = GetSpellInfo(curSpell)
      curName = curName or "Talent"
      curIcon = curIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
      if hasGrants then
        tt:AddLine("|T"..curIcon..":18|t "..WOW_WHITE..curName.."|r", 1,1,1, true)
      else
        tt:AddLine(WOW_WHITE..curName.."|r", 1,1,1, true)
      end
      tt:AddLine(WOW_WHITE.."Rank "..rank.."/"..ranks.."|r", 1,1,1, true)
      AppendSpellBody(tt, curSpell, 2)

      if nextSpell then
        tt:AddLine(" ")
        tt:AddLine(WOW_WHITE.."Next rank:|r", 1,1,1, false)
        local nName, _, nIcon = GetSpellInfo(nextSpell)
        nName = nName or "Next"
        nIcon = nIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
        if hasGrants then
          tt:AddLine("|T"..nIcon..":18|t "..WOW_WHITE..nName.."|r", 1,1,1, true)
        else
          tt:AddLine(WOW_WHITE..nName.."|r", 1,1,1, true)
        end
        AppendSpellBody(tt, nextSpell, 2)
      end

      if hasGrants then
        for i=1,#grants do
          local gid = grants[i]
          if gid then
            AddDivider(tt)
            AppendSpellSection(tt, gid, true, { skipRequires = true })
          end
        end
      end

      if rreq~=nil then tt:AddLine(rreq, 1,0,0, true) end
      if req~=nil  then tt:AddLine(req,  1,0,0, true) end
      if lock~=nil then tt:AddLine(lock, 1,0,0, true) end

      if rank < ranks then
        tt:AddLine(" ")
        tt:AddLine(BuildCostLine(apAvail, tpAvail, costAP, costTP), 1,1,1, true)
        local rline = BuildRequiresLine(reqLevel)
        if rline then tt:AddLine(rline, 1,1,1, true) end
        if canLearnNow then
          tt:AddLine(WOW_GREEN.."Click to learn|r", 1,1,1, true)
        end
      end
      tt:AddLine("SPELLID: "..tostring(shownSpellIdForIdLine or curSpell), 1,1,1, true)
      FixTooltipFirstLineFont(tt)
      tt:Show()
    end)
    button:SetScript("OnLeave", function() button.tooltip:Hide() end)
  end

  -- ============================================================
  -- POINTS SYSTEM (Now uses Item Count)
  -- ============================================================
  local function GetPoints(type)
    if type=="ap" then
      local pool = GetItemCount(AP_ITEM) -- reliant on item
      local _,_,_, set = BuildEffectiveSets()
      local usedAP = select(1, SumUsedCosts(set))
      -- We don't subtract usedAP from pool because pool is the item count in bag
      -- The system should consume items on apply, so pool is "available"
      -- However, pending plus/minus needs consideration.
      -- If we added talents to 'plus', they are not applied yet, so not consumed.
      -- But we want to show remaining points.
      
      -- Calculate cost of PENDING changes:
      local pendingCost = 0
      for _, sid in ipairs(spellsplus) do
          local c = CostIndex[sid]
          if c then pendingCost = pendingCost + (c.ap or 0) end
      end
      for _, sid in ipairs(talentsplus) do
          local c = CostIndex[sid]
          if c then pendingCost = pendingCost + (c.ap or 0) end
      end
      
      -- Refunding cost from Unlearned pending:
      local pendingRefund = 0
      for _, sid in ipairs(spellsminus) do
          local c = CostIndex[sid]
          if c then pendingRefund = pendingRefund + (c.ap or 0) end
      end
      for _, sid in ipairs(talentsminus) do
          local c = CostIndex[sid]
          if c then pendingRefund = pendingRefund + (c.ap or 0) end
      end

      return pool - pendingCost + pendingRefund, 0 -- Display remaining avail
    end

    if type=="tp" then
      local pool = GetItemCount(TP_ITEM)
      local pendingCost = 0
      for _, sid in ipairs(tpellsplus) do
          local c = CostIndex[sid]
          if c then pendingCost = pendingCost + (c.tp or 0) end
      end
      for _, sid in ipairs(talentsplus) do
          local c = CostIndex[sid]
          if c then pendingCost = pendingCost + (c.tp or 0) end
      end
      local pendingRefund = 0
       for _, sid in ipairs(tpellsminus) do
          local c = CostIndex[sid]
          if c then pendingRefund = pendingRefund + (c.tp or 0) end
      end
      for _, sid in ipairs(talentsminus) do
          local c = CostIndex[sid]
          if c then pendingRefund = pendingRefund + (c.tp or 0) end
      end

      return pool - pendingCost + pendingRefund, 0
    end
    
    if type=="sp" then return statCache.left or 0, 0 end
    return 0,0
  end

  -- ============================================================
  -- Apply / Reset
  -- ============================================================
  local function SetBtnEnabled(btn, enabled)
    if not btn then return end
    if enabled then btn:Enable(); btn:SetAlpha(1.0) else btn:Disable(); btn:SetAlpha(0.35) end
  end
  local function PendingAny()
    return (#spellsplus + #spellsminus + #tpellsplus + #tpellsminus + #talentsplus + #talentsminus) > 0
  end

  local UpdateSpecUsage = function() end 
  local UpdateTopBar = function() end

  local function UpdateApplyReset()
    local main = _G["CLMainFrame"]; if not main then return end
    local tab = main:GetAttribute("tab") or 0
    local frameBtns = _G["CLResetButtonFrame"]; if not frameBtns then return end

    if tab ~= 1 then FrameHide(frameBtns); return end
    FrameShow(frameBtns)
    local pending = PendingAny()
    SetBtnEnabled(_G["CLResetButton1"], pending)
    SetBtnEnabled(_G["CLResetButton2"], pending)

    UpdateSpecUsage()
    UpdateTopBar()
  end

  local function LearnConfirm(action)
    local tab=_G["CLMainFrame"]:GetAttribute("tab")
    if tab ~= 1 then return end

    if action=="Apply" then
      for i=1,#spellsminus do tRemoveKey(db.spells, spellsminus[i]) end
      for i=1,#tpellsminus do tRemoveKey(db.tpells, tpellsminus[i]) end
      for i=1,#spellsplus  do if not tContains(db.spells,spellsplus[i]) then tinsert(db.spells,spellsplus[i]) end end
      for i=1,#tpellsplus  do if not tContains(db.tpells,tpellsplus[i]) then tinsert(db.tpells,tpellsplus[i]) end end

      for i=1,#talentsminus do tRemoveKey(db.talents, talentsminus[i]) end
      for i=1,#talentsplus  do if not tContains(db.talents,talentsplus[i]) then tinsert(db.talents,talentsplus[i]) end end

      wipe(spellsplus); wipe(spellsminus)
      wipe(tpellsplus); wipe(tpellsminus)
      wipe(talentsplus); wipe(talentsminus)

      sort(db.spells); sort(db.tpells); sort(db.talents)

      AIO.Handle("ClassLess", "ApplyAll", db.spells, db.tpells, db.talents)
    end

    if action=="Reset" then
      wipe(spellsplus); wipe(spellsminus)
      wipe(tpellsplus); wipe(tpellsminus)
      wipe(talentsplus); wipe(talentsminus)
    end
    UpdateApplyReset()
  end

  local function TempLearnSpell(spell)
    if tContains(spellsminus,spell) then tRemoveKey(spellsminus,spell) end
    if not tContains(spellsplus,spell) then tinsert(spellsplus,spell) end
  end
  local function TempUnlearnSpell(spell)
    if tContains(spellsplus,spell) then tRemoveKey(spellsplus,spell) end
    if not tContains(spellsminus,spell) then tinsert(spellsminus,spell) end
  end
  local function TempLearnTalent(spell)
    if tContains(talentsminus,spell) then tRemoveKey(talentsminus,spell) end
    if not tContains(talentsplus,spell) then tinsert(talentsplus,spell) end
  end
  local function TempUnlearnTalent(spell)
    if tContains(talentsplus,spell) then tRemoveKey(talentsplus,spell) end
    if not tContains(talentsminus,spell) then tinsert(talentsminus,spell) end
  end

  local function GetTalentPos(entry)
    local p = entry and entry[3]
    if type(p) == "string" and p ~= "" then
      local a,b = p:match("^(%d+)%s*,%s*(%d+)$")
      if a and b then return tonumber(a), tonumber(b) end
    elseif type(p) == "table" then
      local tier = tonumber(p.tier or p[1])
      local col  = tonumber(p.col  or p[2])
      if tier and col then return tier, col end
    end
    return nil,nil
  end

  -- ============================================================
  -- Fill Spells / Talents
  -- ============================================================
  local function FillSpells(class, spec, parent, mode)
    local effSpells, effTpells, effTalents, allSet = BuildEffectiveSets()

    local spellcheck
    local nodes
    if mode=="spell" then
      nodes = db.data.spells[class][spec][4]
      spellcheck = effSpells
    else
      nodes = db.data.talents[class][spec][4]
      spellcheck = effTalents
    end

    local allspells = {}
    for id,_ in pairs(allSet) do tinsert(allspells, id) end

    local apAvail = select(1, GetPoints("ap"))
    local tpAvail = select(1, GetPoints("tp"))

    local tal_cols = CL_TALENT_COLS
    local gridW = (tal_cols - 1) * CL_TALENT_COL_STEP + CL_NODE_ICON_SIZE
    local baseX = math.floor((parent:GetWidth() - gridW) / 2)

    for i=1,#nodes do
      local spellid,levelid = nodes[i][1], nodes[i][2]
      local rank,ranks = 0,#spellid
      for j=1,ranks do if tContains(spellcheck,spellid[j]) then rank=j end end

      local spell,nspell,nlevel,nrank
      if rank>0 then spell=spellid[rank] else rank=0 spell=spellid[1] end
      if rank+1<=ranks then
        nspell,nlevel,nrank=spellid[rank+1],levelid[rank+1],rank+1
      else
        nspell,nlevel,nrank=spellid[rank],levelid[rank],rank
      end

      local icon=({GetSpellInfo(nspell)})[3]
      local button=_G["CLSpellsClass"..class.."Spec"..spec..mode..i] or NewButton("CLSpellsClass"..class.."Spec"..spec..mode..i, parent, CL_NODE_ICON_SIZE, icon, true)
      button:SetButtonState("NORMAL","true")
      button:ClearAllPoints()

      if mode=="spell" then
        local col = (i-1) % 3
        local row = math.floor((i-1) / 3)
        button:SetPoint("TOPLEFT", CL_SPELL_LEFT_PAD + (col * CL_SPELL_COL_STEP), -CL_SPELL_TOP_PAD - (row * CL_SPELL_ROW_STEP))
      else
        local tier,col = GetTalentPos(nodes[i])
        if tier and col then
          local x = baseX + (col-1)*CL_TALENT_COL_STEP
          local y = -CL_TALENT_TOP_PAD - (tier-1)*CL_TALENT_ROW_STEP
          button:SetPoint("TOPLEFT", x, y)
        else
          local col2 = (i-1) % 5
          local row2 = math.floor((i-1) / 5)
          button:SetPoint("TOPLEFT", 42 + (col2*45), -25 - (row2*45))
        end
      end

      local costAP, costTP = 0,0
      if rank < ranks then costAP, costTP = GetNodeCost(mode, nodes[i], nrank) end

      local learned = (rank > 0)
      -- Visual rule: ONLY learned spells are highlighted
local icon = button.texture or button.icon  -- pick whichever your UI uses

if learned then
  icon:SetDesaturated(false)
  icon:SetVertexColor(1, 1, 1)
  icon:SetAlpha(1)
else
  icon:SetDesaturated(true)
  icon:SetVertexColor(0.35, 0.35, 0.35)  -- darker = more “black/grey”
  icon:SetAlpha(0.85)                     -- optional
end


      local canLearnNext = (rank < ranks)
      local lock, req, rreq = nil, nil, nil

      if canLearnNext then
        if UnitLevel("player") < nlevel then canLearnNext = false end
        if apAvail < costAP or tpAvail < costTP then canLearnNext = false end
        if canLearnNext and db.locks and db.locks[spell] ~= nil then
          for h=1,#db.locks[spell] do
            if tContains(allspells, db.locks[spell][h]) then
              canLearnNext = false
              lock = "Locked by \""..({GetSpellInfo(db.locks[spell][h])})[1].."\" "..mode
              break
            end
          end
        end
        if canLearnNext and db.req and db.req[nspell] ~= nil then
          local reqs, reqr = ({GetSpellInfo(db.req[nspell])})[1], ({GetSpellInfo(db.req[nspell])})[2]
          if not tContains(allspells, db.req[nspell]) then
            canLearnNext = false
            req = "req "..mode.." \""..reqs..((reqr~="" and ("("..reqr..")\"")) or "\"")
          end
        end
      end

      local state = "normal"
      if rank == ranks then state = "full"
      elseif (not learned) and (not canLearnNext) then state = "disabled" end

      local desat = 0
      if rank == 0 and state == "disabled" then desat = 1 end
      button.texture:SetDesaturated(desat)
      
      button.allowLeft  = canLearnNext
      button.allowRight = (rank > 0)

      if db.rreq and db.rreq[spell]~=nil then
        local rreqs,rreqr=({GetSpellInfo(db.rreq[spell])})[1],({GetSpellInfo(db.rreq[spell])})[2]
        if tContains(allspells, db.rreq[spell]) then
          rreq="Required for "..mode.." \""..rreqs
          if rreqr~="" then rreq=rreq.."("..rreqr..")\"" else rreq=rreq.."\"" end
        end
      end

      SetButtonBorder(button, mode, state, rank, ranks, false)

      if button.rank then
        if mode=="spell" then
          button.rank:SetText("")
          if button.rankBG then button.rankBG:Hide() end
        else
          if UnitLevel("player") < nlevel then
            button.rank:SetText("")
            if button.rankBG then button.rankBG:Hide() end
          else
            local txt = rank.."/"..ranks
            button.rank:SetText(txt)
            if rank >= ranks and ranks > 0 then button.rank:SetTextColor(1, 0.82, 0)
            elseif rank > 0 then button.rank:SetTextColor(0, 1, 0)
            else button.rank:SetTextColor(1, 1, 1) end
            if button.rankBG then button.rankBG:Show() end
          end
        end
      end

      if mode=="spell" then
        local spellName = ({GetSpellInfo(nspell)})[1] or "Spell"
        local l1,l2 = WrapTwoLines(spellName, CL_SPELL_TEXT_WIDTH)
        if not button.nameText then
          button.nameText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          button.nameText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
          button.nameText:SetJustifyH("LEFT")
          button.nameText:SetJustifyV("TOP")
          button.nameText:SetWidth(CL_SPELL_TEXT_WIDTH)
        end
        button.nameText:ClearAllPoints()
        button.nameText:SetPoint("TOPLEFT", button, "TOPRIGHT", CL_SPELL_TEXT_X, CL_SPELL_NAME_Y)
        button.nameText:SetText(WOW_GOLD..l1..(l2~="" and ("\n"..l2) or "").."|r")
        button.nameText:Show()

        if not button.levelText then
          button.levelText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          button.levelText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
          button.levelText:SetJustifyH("LEFT")
          button.levelText:SetWidth(CL_SPELL_TEXT_WIDTH)
        end
        button.levelText:ClearAllPoints()
        button.levelText:SetPoint("TOPLEFT", button.nameText, "BOTTOMLEFT", 0, -2)
        if UnitLevel("player") < nlevel then button.levelText:SetText(WOW_RED.."Level "..nlevel.."|r")
        else button.levelText:SetText(WOW_WHITE.."Level "..nlevel.."|r") end
        button.levelText:Show()
        button:SetHitRectInsets(0, -(CL_SPELL_TEXT_X + CL_SPELL_TEXT_WIDTH), 0, 0)
      else
        if button.nameText then button.nameText:Hide() end
        if button.levelText then button.levelText:Hide() end
        button:SetHitRectInsets(-2,-2,-2,-2)
      end

      local allowLeft, allowRight = false, false
      if state ~= "disabled" then
        if rank > 0 then allowRight = true end
        if rank < ranks then allowLeft = true end
      end
      if allowLeft and allowRight then button:RegisterForClicks("LeftButtonDown","RightButtonDown")
      elseif allowLeft then button:RegisterForClicks("LeftButtonDown")
      elseif allowRight then button:RegisterForClicks("RightButtonDown")
      else button:RegisterForClicks("") end

      button:SetScript("OnClick", function(self, key)
        local shift = IsShiftKeyDown()
        local didChange = false

        if mode=="talent" and shift then
          if key=="LeftButton" and allowLeft then
            local stepRank = rank
            -- Cache initial points to avoid recalculating in loop
            local apNow = select(1, GetPoints("ap"))
            local tpNow = select(1, GetPoints("tp"))

            while stepRank < ranks do
              local nextRank = stepRank + 1
              local nextSpell = spellid[nextRank]
              local nextLevel = levelid[nextRank]
              if UnitLevel("player") < (nextLevel or 1) then break end

              local needAP, needTP = GetNodeCost("talent", nodes[i], nextRank)
              if apNow < needAP or tpNow < needTP then break end

              TempLearnTalent(nextSpell)
              apNow = apNow - needAP
              tpNow = tpNow - needTP
              stepRank = stepRank + 1
              didChange = true
            end
          end
          if key=="RightButton" and allowRight then
            local stepRank = rank
            while stepRank > 0 do
              local curSpell = spellid[stepRank]
              TempUnlearnTalent(curSpell)
              stepRank = stepRank - 1
              didChange = true
            end
          end
        else
          if key=="LeftButton" and allowLeft then
            if mode=="spell" then TempLearnSpell(nspell) else TempLearnTalent(nspell) end
            didChange = true
          end
          if key=="RightButton" and allowRight then
            if mode=="spell" then TempUnlearnSpell(spell) else TempUnlearnTalent(spell) end
            didChange = true
          end
        end

        -- Only update UI once at the end
        if didChange then
          FillSpells(class, spec, parent, mode)
          UpdateApplyReset()
        end

        local onEnter = self:GetScript("OnEnter")
        if onEnter and self:IsMouseOver() then onEnter(self) end
      end)

      local apNow = select(1, GetPoints("ap"))
      local tpNow = select(1, GetPoints("tp"))
      if mode=="spell" then
        SpellButtonTooltip(button, nspell, spell, rank, ranks, nlevel, apNow, tpNow, costAP, costTP, lock, req, rreq)
      else
        local canLearnNow = allowLeft and (rank < ranks) and (UnitLevel("player") >= nlevel)
        TalentButtonTooltip(button, spellid, rank, ranks, nlevel, apNow, tpNow, costAP, costTP, lock, req, rreq, spell, canLearnNow)
      end
    end
  end

  -- ============================================================
  -- Minimap button
  -- ============================================================
  local button=CreateFrame("Button", "CLButton", Minimap);
  CLButton:SetFrameStrata('HIGH')
  CLButton:SetWidth(31)
  CLButton:SetHeight(31)
  CLButton:SetFrameLevel(8)
  CLButton:RegisterForClicks('anyUp')
  CLButton:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
  local overlay = CLButton:CreateTexture(nil, 'OVERLAY')
  overlay:SetWidth(53)
  overlay:SetHeight(53)
  overlay:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
  overlay:SetPoint('TOPLEFT')
  local icon = CLButton:CreateTexture(nil, 'BACKGROUND')
  icon:SetWidth(20)
  icon:SetHeight(20)
  icon:SetTexture('interface\\ClasslessUI\\Mainbutton')
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  icon:SetPoint('TOPLEFT', 7, -5)
  CLButton.icon = icon
  CLButton:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -2, 2)
  CLButton:SetScript("OnClick", function() ToggleTalentFrame() end)

-- ============================================================
-- Main frame
-- ============================================================
local frame = CLMainFrame or CreateFrame("Frame", "CLMainFrame", UIParent)

frame:Hide()
frame:SetMovable(true)
frame:EnableMouse(true)
frame:SetToplevel(true)
frame:RegisterForDrag("LeftButton")
frame:SetSize(820, 658)
frame:SetBackdrop(nil)
frame.bg = frame.bg or frame:CreateTexture(nil, "BACKGROUND", nil, -8)
frame.bg:SetTexture("interface\\ClasslessUI\\progress_inside_blue")
frame.bg:ClearAllPoints()

local SHIFT_X = 12 
local SHIFT_Y = 10 
local INSET_LEFT   = 0 
local INSET_RIGHT  = 60 
local INSET_TOP    = -100 
local INSET_BOTTOM = 40 

frame.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", SHIFT_X + INSET_LEFT, SHIFT_Y - INSET_TOP)
frame.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", SHIFT_X - INSET_RIGHT, SHIFT_Y + INSET_BOTTOM)
frame:ClearAllPoints()
frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 320, -104)
frame:SetClampedToScreen(true)
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetAttribute("tab", 0)


UIPanelWindows = UIPanelWindows or {}
UIPanelWindows["CLMainFrame"] = { area = "left", pushable = 1, whileDead = 1 }

UISpecialFrames = UISpecialFrames or {}
local found = false
for i=1,#UISpecialFrames do
  if UISpecialFrames[i] == "CLMainFrame" then found = true break end
end
if not found then table.insert(UISpecialFrames, "CLMainFrame") end



local close = _G["CLMainFrameClose"] or CreateFrame("Button", "CLMainFrameClose", frame)
close:SetSize(20, 20)
close:ClearAllPoints()
close:SetPoint("TOPRIGHT", -8, -6)
close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
close:SetScript("OnClick", function() HideUIPanel(frame) end)

local pointsFrame = _G["CLPointsFrame"] or CreateFrame("Frame", "CLPointsFrame", frame)
pointsFrame:SetSize(220, 29)
pointsFrame:SetPoint("TOPRIGHT", -40, -6)

local apFrame = _G["CLPointsFrameAP"] or CreateFrame("Button", "CLPointsFrameAP", pointsFrame)
apFrame:SetSize(80, 29)
apFrame:ClearAllPoints()
apFrame:SetPoint("LEFT", pointsFrame, "LEFT", 0, 0)
apFrame.text = apFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
apFrame.text:SetPoint("RIGHT", 0, -1)

apFrame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 5)
    GameTooltip:ClearLines()
    GameTooltip:AddLine(WOW_WHITE.."Ability Power|r")
    GameTooltip:AddLine(WOW_GOLD.."Allows you to learn Abilities.|r")
    GameTooltip:Show()
end)
apFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

local tpFrame = _G["CLPointsFrameTP"] or CreateFrame("Button", "CLPointsFrameTP", pointsFrame)
tpFrame:SetSize(80, 29)
tpFrame:ClearAllPoints()
tpFrame:SetPoint("LEFT", apFrame, "RIGHT", 3, 0)
tpFrame.text = tpFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
tpFrame.text:SetPoint("RIGHT", 0, -1)

tpFrame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 5)
    GameTooltip:ClearLines()
    GameTooltip:AddLine(WOW_WHITE.."Talent Point|r")
    GameTooltip:AddLine(WOW_GOLD.."Allows you to learn Talents.|r")
    GameTooltip:Show()
end)
tpFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

local spFrame = _G["CLPointsFrameSP"] or CreateFrame("Button", "CLPointsFrameSP", pointsFrame)
spFrame:SetSize(80, 29)
spFrame:ClearAllPoints()
spFrame:SetPoint("LEFT", tpFrame, "RIGHT", 3, 0)
spFrame.text = spFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
spFrame.text:SetPoint("RIGHT", 0, -1)

spFrame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 5)
    GameTooltip:ClearLines()
    GameTooltip:AddLine(WOW_WHITE.."Stat Points|r")
    GameTooltip:AddLine(WOW_GOLD.."Allows you to allocate stats.|r")
    GameTooltip:Show()
end)
spFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)


UpdateTopBar = function()
    local ap = select(1, GetPoints("ap"))
    local tp = select(1, GetPoints("tp"))
    local sp = select(1, GetPoints("sp"))

    apFrame.text:SetText(WOW_WHITE..ap.."|r |T"..AP_ICON..":12:12:0:-1|t")
    apFrame:SetWidth(apFrame.text:GetStringWidth() + 16)
    
    tpFrame.text:SetText(WOW_WHITE..tp.."|r |T"..TP_ICON..":12:12:0:-1|t")
    tpFrame:SetWidth(tpFrame.text:GetStringWidth() + 16)
    tpFrame:SetPoint("LEFT", apFrame, "RIGHT", 3, 0)

    spFrame.text:SetText(WOW_WHITE..sp.."|r |T"..SP_ICON..":12:12:0:-1|t")
    spFrame:SetWidth(spFrame.text:GetStringWidth() + 16)
    spFrame:SetPoint("LEFT", tpFrame, "RIGHT", 3, 0)
end

  local frameReset = _G["CLResetFrame"] or CreateFrame("Frame", "CLResetFrame", frame)
  frameReset:SetSize(160, 32)
  frameReset:SetPoint("BOTTOMLEFT", 200, 12)

  local frameResetButtons = _G["CLResetButtonFrame"] or CreateFrame("Frame", "CLResetButtonFrame", frameReset)
  frameResetButtons:SetSize(160, 32)
  frameResetButtons:SetPoint("CENTER")
  frameResetButtons:Show()

  local buttons={"Apply","Reset"}
  for i=1,#buttons do
    local b = _G["CLResetButton"..i] or MakeButton("CLResetButton"..i, frameResetButtons)
    b:SetText(buttons[i])
    b:SetSize(50,25)
    b:SetPoint("CENTER",50*(i-3.89),-8.5)
    b:SetScript("OnClick", function () LearnConfirm(buttons[i]) end)
  end

  local c1 = _G["CLContainer1"] or CreateFrame("Frame", "CLContainer1", frame)
  c1:SetSize(790,360)
  c1:SetPoint("TOPLEFT", 6, -70)
  c1:Hide()

  local c2 = _G["CLContainer2"] or CreateFrame("Frame", "CLContainer2", frame)
  c2:SetSize(790,360)
  c2:SetPoint("TOPLEFT", 6, -70)
  c2:Hide()

local function SelectMainTab(tab, playSound)
  local current = frame:GetAttribute("tab")

  -- Play tab sound only for real user tab changes
  if playSound and frame:IsShown() and current ~= tab then
    PlaySound("igCharacterInfoTab")
  end

  if tab==1 then c1:Show(); c2:Hide() else c1:Hide(); c2:Show() end
  frame:SetAttribute("tab", tab)
end


  local tabNames={"Spells & Talents","Stats"}
  for i=1,2 do
    local b=_G["CLButton"..i] or MakeButton("CLButton"..i, frame)
    b:SetText(tabNames[i])
    b:SetSize(130,32)
    b:SetPoint("TOPLEFT", 140*(i-0.85)+8, -25)
b:SetScript("OnClick", function()
  SelectMainTab(i, true)   -- true = user click, play tab sound
  UpdateApplyReset()
end)

  end

  -- ============================================================
  -- Spec frames
  -- ============================================================
  local selectedClass, selectedSpec
  local currentSpecFrame = nil
  local specFrames = {}

  local function SpecNameFromData(class, spec)
    return (db.data and db.data.spells and db.data.spells[class] and db.data.spells[class][spec] and db.data.spells[class][spec][1]) or ("Spec "..tostring(spec))
  end
  local function DefaultClassSpec()
    local _, classFile = UnitClass("player")
    if classFile and db.data.spells and db.data.spells[classFile] then return classFile, 1 end
    for class,_ in pairs(db.data.spells) do return class, 1 end
    return "WARRIOR", 1
  end
  selectedClass, selectedSpec = DefaultClassSpec()

  local function CreateSpecFrame(class, spec)
    specFrames[class] = specFrames[class] or {}
    if specFrames[class][spec] then return specFrames[class][spec] end
    local f = CreateFrame("Frame", "CLSpecFrame_"..class.."_"..spec, c1)
    f:SetSize(660, 360)
    f:SetPoint("TOPLEFT", 0, 0)
    f:Hide()
    local spellsPanel = CreateFrame("Frame", "CLSpecSpells_"..class.."_"..spec, f)
    spellsPanel:SetSize(280, 352)
    spellsPanel:SetPoint("TOPLEFT", 25, 0)
    FrameBackground(spellsPanel, ""..db.data.spells[class][spec][3])
    FrameLayout(spellsPanel, spellsPanel:GetWidth(), spellsPanel:GetHeight())
    local talentsPanel = CreateFrame("Frame", "CLSpecTalents_"..class.."_"..spec, f)
    talentsPanel:SetSize(280, 352)
    talentsPanel:ClearAllPoints()
    talentsPanel:SetPoint("TOPLEFT", spellsPanel, "TOPRIGHT", 60, 0)
    FrameBackground(talentsPanel, ""..db.data.talents[class][spec][3])
    FrameLayout(talentsPanel, talentsPanel:GetWidth(), talentsPanel:GetHeight())
    f:SetScript("OnShow", function()
      local timer=GetTime()
      f:SetScript("OnUpdate", function()
        if GetTime()-timer>=0.05 then
          FillSpells(class, spec, spellsPanel, "spell")
          FillSpells(class, spec, talentsPanel, "talent")
          UpdateApplyReset()
          f:SetScript("OnUpdate", nil)
        end
      end)
    end)
    specFrames[class][spec] = f
    return f
  end

  local function ShowSpec(class, spec)
    selectedClass, selectedSpec = class, spec
    if currentSpecFrame then currentSpecFrame:Hide() end
    currentSpecFrame = CreateSpecFrame(class, spec)
    currentSpecFrame:Show()
    UpdateApplyReset()
  end

local CL_SELECTOR_WIDTH  = 290
local CL_SPEC_ROW_H      = 18
local CL_SPEC_ROW_GAP    = -1
local CL_SPEC_PAD_X      = 5

  local CLASS_ORDER = {
    "DRUID","HUNTER","MAGE","PALADIN","PRIEST",
    "ROGUE","SHAMAN","WARLOCK","WARRIOR","DEATHKNIGHT",
  }

  local selector = _G["CLSelector"] or CreateFrame("Frame", "CLSelector", c1)
  selector:ClearAllPoints()
  selector:SetSize(CL_SELECTOR_WIDTH, 560)
  selector:SetPoint("TOPLEFT", 638, 45)
  selector:Show()
  if _G["CLSelectorScroll"] then _G["CLSelectorScroll"]:Hide() end
  if _G["CLSelectorScrollScrollBar"] then _G["CLSelectorScrollScrollBar"]:Hide() end

  local content = _G["CLSelectorContent"] or CreateFrame("Frame", "CLSelectorContent", selector)
  content:ClearAllPoints()
  content:SetPoint("TOPLEFT", selector, "TOPLEFT", 0, -2)
  content:SetWidth(CL_SELECTOR_WIDTH)
  local specButtons = {}

local function SpecDisplayName(class, spec)
  local className = CLASS_DISPLAY[class] or class
  local specName  = SpecNameFromData(class, spec) or ("Spec "..tostring(spec))
  local clean = Trim(specName)
  if clean:lower():find(className:lower(), 1, true) then clean = Trim(clean:gsub(className, "")) end
  if class == "DRUID" then clean = clean:gsub("^Feral Combat$", "Feral"); clean = clean:gsub("Feral Combat", "Feral") end
  return Trim(clean)
end

  local function NewSpecRowButton(name, parent, w, h, class)
    local b = _G[name] or CreateFrame("Button", name, parent)
    b:SetSize(w, h)
    b:EnableMouse(true)
    b:RegisterForClicks("LeftButtonUp")

    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    local r,g,bb = 0.25,0.25,0.25
    if c then r,g,bb = c.r, c.g, c.b end

    if not b._styled then
        -- Layout: [AP Num] [AP Icon] [TP Num] [TP Icon] Right Aligned
        local usageFont, usageSize = "Fonts\\FRIZQT__.TTF", 9
        local ICON_SIZE = 13 -- Increased slightly from 12

        -- TP Icon (Rightmost)
        b.tpIcon = b:CreateTexture(nil, "OVERLAY")
        b.tpIcon:SetTexture(TP_ICON)
        b.tpIcon:SetSize(ICON_SIZE, ICON_SIZE)
        b.tpIcon:SetPoint("RIGHT", b, "RIGHT", -3, 0)
        
        -- TP Text (Left of TP Icon)
        b.tpFS = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.tpFS:SetFont(usageFont, usageSize, "OUTLINE")
        b.tpFS:SetPoint("RIGHT", b.tpIcon, "LEFT", -3, 0) -- Gap 3
        b.tpFS:SetShadowColor(0,0,0,0.85)
        b.tpFS:SetShadowOffset(1,-1)

        -- AP Icon (Left of TP Text)
        b.apIcon = b:CreateTexture(nil, "OVERLAY")
        b.apIcon:SetTexture(AP_ICON)
        b.apIcon:SetSize(ICON_SIZE, ICON_SIZE)
        b.apIcon:SetPoint("RIGHT", b.tpFS, "LEFT", -6, 0) -- Gap between groups
        
        -- AP Text (Left of AP Icon)
        b.apFS = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.apFS:SetFont(usageFont, usageSize, "OUTLINE")
        b.apFS:SetPoint("RIGHT", b.apIcon, "LEFT", -3, 0) -- Gap 3
        b.apFS:SetShadowColor(0,0,0,0.85)
        b.apFS:SetShadowOffset(1,-1)

        b:SetBackdrop({
          bgFile   = "Interface\\Buttons\\WHITE8X8",
          edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
          tile = false, edgeSize = 1,
          insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        b:SetBackdropBorderColor(0,0,0,0.55)

      b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
      local hl = b:GetHighlightTexture()
      if hl then
        hl:SetBlendMode("ADD")
        hl:ClearAllPoints()
        -- Tighten highlight to avoid bleed
        hl:SetPoint("TOPLEFT", 1, -1)
        hl:SetPoint("BOTTOMRIGHT", -1, 1)
      end

      b:SetPushedTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
      local pushed = b:GetPushedTexture()
      if pushed then
        pushed:ClearAllPoints()
        pushed:SetPoint("TOPLEFT", 1, -1)
        pushed:SetPoint("BOTTOMRIGHT", -1, 1)
        pushed:SetVertexColor(1,1,1,0.18)
      end

      b.selectedTex = b:CreateTexture(nil, "OVERLAY")
      b.selectedTex:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
      b.selectedTex:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1) -- Tightened
      b.selectedTex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
      b.selectedTex:SetVertexColor(1.0, 0.82, 0.0, 0.55)
      b.selectedTex:SetBlendMode("ADD")
      b.selectedTex:Hide()

      b.selStripe = b:CreateTexture(nil, "OVERLAY")
      b.selStripe:SetTexture("Interface\\Buttons\\WHITE8X8")
      b.selStripe:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
      b.selStripe:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1)
      b.selStripe:SetWidth(3)
      b.selStripe:SetVertexColor(1.0, 0.82, 0.0, 0.95)
      b.selStripe:Hide()

      b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      b.label:SetPoint("LEFT", b, "LEFT", CL_SPEC_PAD_X, 1)
      b.label:SetJustifyH("LEFT")
      b.label:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
      b.label:SetWordWrap(false)
      b.label:SetShadowColor(0,0,0,0.85)
      b.label:SetShadowOffset(1,-1)
      b._styled = true
    end
    b:SetBackdropColor(r, g, bb, 0.42)
    return b
  end

local function UpdateSpecButtonHighlights()
  for _, b in ipairs(specButtons) do
    local isSel = (b.__class == selectedClass and b.__spec == selectedSpec)
    if b.selectedTex then if isSel then b.selectedTex:Show() else b.selectedTex:Hide() end end
    if b.selStripe then if isSel then b.selStripe:Show() else b.selStripe:Hide() end end
    if isSel then b:SetBackdropBorderColor(1.0, 0.82, 0.0, 0.95) else b:SetBackdropBorderColor(0,0,0,0.55) end
  end
end

local function SpecTooltip(btn, class, spec)
  btn:SetScript("OnEnter", function(self)
    GameTooltip:Hide()
    GameTooltip:SetOwner(self, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("LEFT", self, "RIGHT", 12, -1) -- Adjusted down by 1 point (-1 Y)
    GameTooltip:ClearLines()
    local className = CLASS_DISPLAY[class] or class
    local cleanSpec = SpecDisplayName(class, spec)
    local ICON = 14
    local YOFF = -1
    local classIcon = ClassIconTex(class, ICON, 0, YOFF)
    local iconName = (db.data.spells and db.data.spells[class] and db.data.spells[class][spec] and db.data.spells[class][spec][2]) or "INV_Misc_QuestionMark"
    local specIcon = ("|TInterface\\Icons\\%s:%d:%d:0:%d|t"):format(iconName, ICON, ICON, YOFF)
    GameTooltip:AddLine(WOW_GOLD .. classIcon .. " " .. specIcon .. " " .. cleanSpec .. " " .. className .. "|r")
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function ShowUnlearnMenu(btn, class, spec)
  -- Check if this spec has any learned AP or TP
  local _,_,_, set = BuildEffectiveSets()
  local apUsed, tpUsed = ComputeSpecUsed(class, spec, set)

  -- If nothing is learned, don't show the menu
  if (apUsed or 0) == 0 and (tpUsed or 0) == 0 then
    return
  end

  local menu = CreateFrame("Frame", "CLUnlearnMenu", UIParent, "UIDropDownMenuTemplate")

  local function UnlearnSpells()
    AIO.Handle("ClassLess", "UnlearnSpec", class, spec, "spells")
    CloseDropDownMenus()
  end

  local function UnlearnTalents()
    AIO.Handle("ClassLess", "UnlearnSpec", class, spec, "talents")
    CloseDropDownMenus()
  end

  -- Build menu table based on what's learned
  local menuTable = {}

  -- Add title with spec icon and name
  local iconName = (db.data.spells and db.data.spells[class] and db.data.spells[class][spec] and db.data.spells[class][spec][2]) or "INV_Misc_QuestionMark"
  local specIcon = "|TInterface\\Icons\\" .. iconName .. ":16:16:0:0|t"
  local dispName = SpecDisplayName(class, spec)
  table.insert(menuTable, {text = specIcon .. " " .. dispName, isTitle = true, notCheckable = true})

  -- Only add options for learned powers
  if (apUsed or 0) > 0 then
    table.insert(menuTable, {text = "Unlearn Ability Power", func = UnlearnSpells, notCheckable = true})
  end

  if (tpUsed or 0) > 0 then
    table.insert(menuTable, {text = "Unlearn Talent Power", func = UnlearnTalents, notCheckable = true})
  end

  -- Position menu to the right of the button
  EasyMenu(menuTable, menu, btn, 0, 0, "MENU", 1)

  -- Store reference for closing
  if not _G.CLActiveUnlearnMenu then
    _G.CLActiveUnlearnMenu = menu
  end
end


  local function ComputeSpecUsed(class, spec, learnedSet)
    local apUsed, tpUsed = 0,0
    local sNodes = (db.data.spells[class] and db.data.spells[class][spec] and db.data.spells[class][spec][4]) or {}
    for _, entry in ipairs(sNodes) do
      for _, sid in ipairs(entry[1] or {}) do
        if learnedSet[sid] then
          local c = CostIndex[sid]
          if c then apUsed = apUsed + (c.ap or 0); tpUsed = tpUsed + (c.tp or 0) end
        end
      end
    end
    local tNodes = (db.data.talents[class] and db.data.talents[class][spec] and db.data.talents[class][spec][4]) or {}
    for _, entry in ipairs(tNodes) do
      for _, sid in ipairs(entry[1] or {}) do
        if learnedSet[sid] then
          local c = CostIndex[sid]
          if c then apUsed = apUsed + (c.ap or 0); tpUsed = tpUsed + (c.tp or 0) end
        end
      end
    end
    return apUsed, tpUsed
  end

UpdateSpecUsage = function()
  local _,_,_, set = BuildEffectiveSets()
  for _, b in ipairs(specButtons) do
    local apUsed, tpUsed = ComputeSpecUsed(b.__class, b.__spec, set)
    b.label:SetText(b.__baseLabel)

    if (apUsed or 0) > 0 then
        b.apFS:SetText(WOW_WHITE .. apUsed .. "|r")
        b.apFS:Show(); b.apIcon:Show()
    else
        b.apFS:Hide(); b.apIcon:Hide()
    end

    if (tpUsed or 0) > 0 then
        b.tpFS:SetText(WOW_WHITE .. tpUsed .. "|r")
        b.tpFS:Show(); b.tpIcon:Show()
    else
        b.tpFS:Hide(); b.tpIcon:Hide()
    end
  end
end

  local specList = {}
  for _, class in ipairs(CLASS_ORDER) do
    if db.data.spells[class] then
      for spec=1, #db.data.spells[class] do table.insert(specList, { class=class, spec=spec }) end
    end
  end
  local extra = {}
  for class,_ in pairs(db.data.spells) do
    local known = false
    for i=1,#CLASS_ORDER do if CLASS_ORDER[i] == class then known = true break end end
    if not known then table.insert(extra, class) end
  end
  table.sort(extra)
  for _, class in ipairs(extra) do
    for spec=1, #db.data.spells[class] do table.insert(specList, { class=class, spec=spec }) end
  end

  local rowW = (CL_SELECTOR_WIDTH - 130)
  for i, info in ipairs(specList) do
    local class, spec = info.class, info.spec
    local btnName = "CLSelectSpecRow_" .. class .. "_" .. spec
    local btn = NewSpecRowButton(btnName, content, rowW, CL_SPEC_ROW_H, class)
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((i-1) * (CL_SPEC_ROW_H + CL_SPEC_ROW_GAP)))
    btn.__class = class
    btn.__spec  = spec
    local iconName = (db.data.spells[class] and db.data.spells[class][spec] and db.data.spells[class][spec][2]) or "INV_Misc_QuestionMark"
    local iconTex  = "|TInterface\\Icons\\" .. iconName .. ":20|t"
    local dispName = SpecDisplayName(class, spec)
    btn.__baseLabel = WOW_WHITE .. iconTex .. "  " .. dispName .. "|r"
    local RIGHT_RESERVE = 5 -- Increased reserve for 2 icons + numbers
    btn.label:SetWidth(rowW - (CL_SPEC_PAD_X * 2) - RIGHT_RESERVE)
    btn.label:SetText(btn.__baseLabel)
    SpecTooltip(btn, class, spec)
btn:SetScript("OnClick", function(self, button)
  if button == "RightButton" then
    ShowUnlearnMenu(btn, class, spec)
  else
    -- Close any open unlearn menu when switching specs
    CloseDropDownMenus()
    PlaySound("igCharacterInfoTab")
    ShowSpec(class, spec)
    UpdateSpecButtonHighlights()
    UpdateApplyReset()
  end
end)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    table.insert(specButtons, btn)
  end
  content:SetHeight(#specButtons * (CL_SPEC_ROW_H + CL_SPEC_ROW_GAP))
  UpdateSpecButtonHighlights()
  UpdateSpecUsage()

  -- ============================================================
  -- Stats tab
  -- ============================================================
  local frameAttributes = CreateFrame("Frame", "frameAttributes", c2)
  frameAttributes:SetSize(50, 300)
  frameAttributes:SetPoint("CENTER", 0, 0)
  frameAttributes:SetBackdrop(nil)

  local fontAttributesTitle = frameAttributes:CreateFontString("fontAttributesTitle")
  fontAttributesTitle:SetFont("Fonts\\FRIZQT__.TTF", 12.5)
  fontAttributesTitle:SetSize(300, 5)
  fontAttributesTitle:SetPoint("CENTER", 0, 152.5)
  fontAttributesTitle:SetText(WOW_GOLD.."Hold "..WOW_WHITE.."Shift|r "..WOW_GOLD.."to allocate 10 points per stat|r")

  local fontAttributesPointsLeftTitle = frameAttributes:CreateFontString("fontAttributesPointsLeftTitle")
  fontAttributesPointsLeftTitle:SetFont("Fonts\\MORPHEUS.ttf", 18, "OUTLINE")
  fontAttributesPointsLeftTitle:SetSize(300, 0)
  fontAttributesPointsLeftTitle:SetPoint("CENTER", 8, -135)
  fontAttributesPointsLeftTitle:SetText(WOW_GOLD.."Available Stat Points|r")

  local AttributesLeftVisual1 = _G["AttributesLeftVisual1"] or CreateFrame("Frame", "AttributesLeftVisual1", frameAttributes)
  AttributesLeftVisual1:SetSize(140, 75)
  AttributesLeftVisual1:ClearAllPoints()
  AttributesLeftVisual1:SetPoint("CENTER", 8, -172)
  AttributesLeftVisual1:SetBackdrop({ bgFile = "interface\\ClasslessUI\\dialog_glow" })

  local fontAttributesPointsLeft = frameAttributes:CreateFontString("fontAttributesPointsLeft")
  fontAttributesPointsLeft:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
  fontAttributesPointsLeft:SetSize(50, 5)
  fontAttributesPointsLeft:SetPoint("CENTER", 8, -153)
  statUI.left = fontAttributesPointsLeft

  local function StatCurrentValue(statId)
    if statId == 1 then return statCache.p1 or 0 end
    if statId == 2 then return statCache.p2 or 0 end
    if statId == 3 then return statCache.p3 or 0 end
    if statId == 4 then return statCache.p4 or 0 end
    if statId == 5 then return statCache.p5 or 0 end
    return 0
  end

  local function SetupIconTooltip(btn, title, line1, line2)
    btn:EnableMouse(true)
    btn:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:ClearLines()
      GameTooltip:AddLine("|cFFF5F5F5"..title.."|r")
      if line1 and line1 ~= "" then GameTooltip:AddLine(line1) end
      if line2 and line2 ~= "" then GameTooltip:AddLine(line2) end
      GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end

  local function MakeStatBlock(name, y, label, statId, iconTex, iconHighlight, tip1, tip2)
    local frameStat = CreateFrame("Frame", name, frameAttributes)
    frameStat:SetSize(400, 105)
    frameStat:SetPoint("CENTER", 0, y)
    frameStat:SetBackdrop({ bgFile = "interface\\ClasslessUI\\allocationbuttonframe" })

    local title = frameStat:CreateFontString(name.."Title")
    title:SetFont("Fonts\\MORPHEUS.ttf", 14, "OUTLINE")
    title:SetSize(137, 5)
    title:SetPoint("CENTER", 10, 18.5)
    title:SetText(WOW_GOLD..label.."|r")
    
    local iconBtnName = "button"..name
    local iconBtn = _G[iconBtnName] or CreateFrame("Button", iconBtnName, frameStat)
    iconBtn:SetSize(50, 50)
    iconBtn:ClearAllPoints()
    iconBtn:SetPoint("CENTER", -92.5, 4)
    iconBtn:SetNormalTexture(iconTex)
    iconBtn:SetHighlightTexture(iconHighlight)
    local hl = iconBtn:GetHighlightTexture()
    if hl then hl:SetBlendMode("ADD") end
    SetupIconTooltip(iconBtn, label, tip1, tip2)

    local inc = CreateFrame("Button", name.."Inc", frameStat)
    inc:SetSize(25, 25)
    inc:SetPoint("CENTER", 60, -2)
    inc:SetNormalTexture("Interface/BUTTONS/UI-SpellbookIcon-NextPage-Up")
    inc:SetHighlightTexture("Interface/BUTTONS/UI-Panel-MinimizeButton-Highlight")
    inc:SetPushedTexture("Interface/BUTTONS/UI-SpellbookIcon-NextPage-Down")
    inc:SetScript("OnMouseUp", function()
      local amt = IsShiftKeyDown() and 10 or 1
      local left = tonumber(statCache.left or 0) or 0
      if left <= 0 then return end
      if amt > left then amt = left end
      if amt <= 0 then return end
      AIO.Handle("StatAllocation", "AttributesIncrease", statId, amt)
    end)

    local dec = CreateFrame("Button", name.."Dec", frameStat)
    dec:SetSize(25, 25)
    dec:SetPoint("CENTER", -40, -2)
    dec:SetNormalTexture("Interface/BUTTONS/UI-SpellbookIcon-PrevPage-Up")
    dec:SetHighlightTexture("Interface/BUTTONS/UI-Panel-MinimizeButton-Highlight")
    dec:SetPushedTexture("Interface/BUTTONS/UI-SpellbookIcon-PrevPage-Down")
    dec:SetScript("OnMouseUp", function()
      local amt = IsShiftKeyDown() and 10 or 1
      local cur = tonumber(StatCurrentValue(statId)) or 0
      if cur <= 0 then return end
      if amt > cur then amt = cur end
      if amt <= 0 then return end
      AIO.Handle("StatAllocation", "AttributesDecrease", statId, amt)
    end)

    local value = frameStat:CreateFontString(name.."Value")
    value:SetFont("Fonts\\FRIZQT__.TTF", 15)
    value:SetSize(50, 5)
    value:SetPoint("CENTER", 8, -2)
    return value
  end

  statUI.str = MakeStatBlock("AttributesStrength", 112, "Strength", 1, "interface\\ClasslessUI\\strength", "interface\\ClasslessUI\\strength_h", "Strength increases melee |cFFF5F5F5attack power|r and damage you can |cFFF5F5F5block|r with a shield.", "Strength also converts into |cFFF5F5F5parry|r.")
  statUI.sta = MakeStatBlock("AttributesStamina", 58.5, "Stamina", 3, "interface\\ClasslessUI\\stamina", "interface\\ClasslessUI\\stamina_h", "Stamina increases your maximum |cFFF5F5F5health|r and increases pet's health.", "")
  statUI.agi = MakeStatBlock("AttributesAgility", 5, "Agility", 2, "interface\\ClasslessUI\\agility", "interface\\ClasslessUI\\agility_h", "Agility increases melee and ranged |cFFF5F5F5attack power|r, |cFFF5F5F5critical strike chance|r, and |cFFF5F5F5armor rating|r.", "Agility also converts into |cFFF5F5F5dodge|r.")
  statUI.int = MakeStatBlock("AttributesIntellect", -48.5, "Intellect", 4, "interface\\ClasslessUI\\intellect", "interface\\ClasslessUI\\intellect_h", "Intellect increases your maximum |cFFF5F5F5mana|r, and your chance to score a |cFFF5F5F5critical strike|r with spells.", "")
  statUI.spi = MakeStatBlock("AttributesSpirit", -102, "Spirit", 5, "interface\\ClasslessUI\\spirit", "interface\\ClasslessUI\\spirit_h", "Spirit increases |cFFF5F5F5health|r and |cFFF5F5F5mana|r regeneration.", "")

  BuildIndexes()
  BuildCostIndex()

  -- Event handling for Item Updates (Fix for #4 and Reliance on Items)
  local function OnBagUpdate()
      UpdateApplyReset()
      if currentSpecFrame and currentSpecFrame:IsVisible() then
         -- Force refresh of buttons to update "canLearnNext" status based on new item count
         FillSpells(selectedClass, selectedSpec, _G["CLSpecSpells_"..selectedClass.."_"..selectedSpec], "spell")
         FillSpells(selectedClass, selectedSpec, _G["CLSpecTalents_"..selectedClass.."_"..selectedSpec], "talent")
      end
  end

  local eventFrame = CreateFrame("Frame")
  eventFrame:RegisterEvent("BAG_UPDATE")
  eventFrame:SetScript("OnEvent", OnBagUpdate)


frame:SetScript("OnShow", function()
    if frame:GetAttribute("tab") == 0 then frame:SetAttribute("tab", 1) end
    SelectMainTab(frame:GetAttribute("tab") or 1, false)

    ShowSpec(selectedClass, selectedSpec)
    UpdateSpecButtonHighlights()
    UpdateApplyReset()
    ApplyStatsToUI()
  end)

  frame:SetScript("OnUpdate", function()
    UpdateApplyReset()
  end)

  ApplyStatsToUI()
  SelectMainTab(1, false)

  ShowSpec(selectedClass, selectedSpec)
  UpdateSpecButtonHighlights()
  UpdateApplyReset()
end

local ClassLessHandlers = AIO.AddHandlers("ClassLess", {})

function ClassLessHandlers.LoadVars(player,spr,tpr,tar,str)
  db.spells=spr or {}
  db.tpells=tpr or {}
  db.talents=tar or {}
  db.stats=str or {0,0,0,0,0}

  -- Clear any pending changes when receiving fresh data from server
  wipe(spellsplus); wipe(spellsminus)
  wipe(tpellsplus); wipe(tpellsminus)
  wipe(talentsplus); wipe(talentsminus)

  -- If UI is already initialized, update it
  if _G["CLMainFrame"] and _G["CLMainFrame"]:IsShown() then
    -- Refresh the currently displayed spec
    if selectedClass and selectedSpec and currentSpecFrame then
      FillSpells(selectedClass, selectedSpec, _G["CLSpecSpells_"..selectedClass.."_"..selectedSpec], "spell")
      FillSpells(selectedClass, selectedSpec, _G["CLSpecTalents_"..selectedClass.."_"..selectedSpec], "talent")
    end
    UpdateApplyReset()
  else
    -- Initial load - build everything
    DoShit()
  end
end

function ToggleTalentFrame()
  local f = _G["CLMainFrame"]
  if not f then return end
  if f:IsShown() then HideUIPanel(f) else ShowUIPanel(f) end
end