-- classless_client.lua
-- Client-side UI and logic for ClassLess talent/spell system
-- WoW 3.3.5 | AzerothCore | Eluna | AIO

local AIO = AIO or require("AIO")

-- ============================================================
-- Constants
-- ============================================================
-- Currency Items (used as Ability Points and Talent Points)
local AP_ITEM_ID = 16203  -- Ability Point item
local TP_ITEM_ID = 11135  -- Talent Point item

-- Icon paths (use forward slashes for cross-platform compatibility)
local AP_ICON = "Interface/Icons/inv_enchant_essenceeternallarge"
local TP_ICON = "Interface/Icons/inv_enchant_essencemysticallarge"
local SP_ICON = "Interface/Icons/inv_enchant_essenceastrallarge"

-- Grant recursion safety
local MAX_GRANT_DEPTH = 50  -- Maximum grant chain depth (was 20)

-- Color codes for UI text
local WOW_GOLD  = "|cffffd100"
local WOW_WHITE = "|cffffffff"
local WOW_RED   = "|cffff0000"
local WOW_GREEN = "|cff00ff00"

-- ============================================================
-- Data File Loading (Server-side only)
-- ============================================================
if AIO.IsServer() then
  -- Use forward slashes for cross-platform compatibility (Linux/Windows)
  AIO.AddAddon("lua_scripts/ClassLess/data/spells.lua",  "spells")
  AIO.AddAddon("lua_scripts/ClassLess/data/talents.lua", "talents")
  AIO.AddAddon("lua_scripts/ClassLess/data/locks.lua",   "locks")
  AIO.AddAddon("lua_scripts/ClassLess/data/req.lua",     "req")
end
if AIO.AddAddon() then return end

-- ============================================================
-- Global References and State
-- ============================================================
local db = CLDB  -- ClassLess Database (loaded from data files)

-- UI sizing and spacing constants
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

-- Pending changes (tracked client-side before applying to server)
local spellsplus, spellsminus     = {}, {}
local tpellsplus, tpellsminus     = {}, {}
local talentsplus, talentsminus   = {}, {}

-- Stat allocation state
local StatHandlers = AIO.AddHandlers("StatAllocation", {})
local statCache = { left=0, p1=0, p2=0, p3=0, p4=0, p5=0 }
local statUI = {}

-- ============================================================
-- Utility Functions
-- ============================================================

-- Apply stat values to UI elements
local function ApplyStatsToUI()
  if statUI.str then statUI.str:SetText(statCache.p1 or 0) end
  if statUI.agi then statUI.agi:SetText(statCache.p2 or 0) end
  if statUI.sta then statUI.sta:SetText(statCache.p3 or 0) end
  if statUI.int then statUI.int:SetText(statCache.p4 or 0) end
  if statUI.spi then statUI.spi:SetText(statCache.p5 or 0) end
  if statUI.left then statUI.left:SetText(statCache.left or 0) end
end

-- Handler for receiving stat updates from server
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

-- Show a frame (by name or reference)
local function FrameShow(fname)
  local f = (type(fname) == "table") and fname or _G[fname]
  if f and f:IsVisible() ~= 1 then f:Show() end
end

-- Hide a frame (by name or reference)
local function FrameHide(fname)
  local f = (type(fname) == "table") and fname or _G[fname]
  if f and f:IsVisible() == 1 then f:Hide() end
end

-- Class display names
local CLASS_DISPLAY = {
  WARRIOR="Warrior", PALADIN="Paladin", HUNTER="Hunter", ROGUE="Rogue", PRIEST="Priest",
  DEATHKNIGHT="Deathknight", SHAMAN="Shaman", MAGE="Mage", WARLOCK="Warlock", DRUID="Druid",
}

-- Generate class icon texture string for embedding in text
local function ClassIconTex(classFile, size, xOff, yOff)
  -- Validate CLASS_ICON_TCOORDS exists (may not on all clients)
  if not CLASS_ICON_TCOORDS then return "" end

  local c = CLASS_ICON_TCOORDS[classFile]
  if not c then return "" end

  size = size or 14
  xOff = xOff or 0
  yOff = yOff or -1

  local l, r, t, b = c[1]*256, c[2]*256, c[3]*256, c[4]*256
  return string.format(
    "|TInterface/GLUES/CHARACTERCREATE/UI-CHARACTERCREATE-CLASSES:%d:%d:%d:%d:256:256:%d:%d:%d:%d|t",
    size, size, xOff, yOff, l, r, t, b
  )
end

-- Trim whitespace from string
local function Trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- ============================================================
-- Text Measurement and Wrapping
-- ============================================================
local _CLMeasureFrame = CreateFrame("Frame", nil, UIParent)
_CLMeasureFrame:Hide()
local _CLMeasureFS = _CLMeasureFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
_CLMeasureFS:SetFont("Fonts/FRIZQT__.TTF", 10, "OUTLINE")

-- Measure pixel width of text
local function TextWidthPx(text)
  _CLMeasureFS:SetText(text or "")
  return (_CLMeasureFS:GetStringWidth() or 0)
end

-- Wrap spell name into two lines if needed
local function WrapTwoLines(name, maxWidth)
  name = Trim(name)
  if name == "" then return "", "" end
  maxWidth = tonumber(maxWidth) or CL_SPELL_TEXT_WIDTH

  local wFull = TextWidthPx(name)
  if wFull <= maxWidth * 0.92 then return name, "" end

  local words = {}
  for w in name:gmatch("%S+") do table.insert(words, w) end

  -- Single word: split by character
  if #words == 1 then
    local s = words[1]
    local cut = 0
    for i = 1, #s do
      if TextWidthPx(s:sub(1, i)) > maxWidth then
        cut = i - 1
        break
      end
    end
    if cut < 1 then cut = math.max(1, math.floor(#s/2)) end
    return s:sub(1, cut), s:sub(cut + 1)
  end

  if wFull <= maxWidth then return name, "" end

  -- Multiple words: find best split point
  local bestL1, bestL2 = words[1], table.concat(words, " ", 2)
  local bestScore = 1e18

  for i = 1, #words - 1 do
    local l1 = table.concat(words, " ", 1, i)
    local l2 = table.concat(words, " ", i + 1, #words)
    local w1, w2 = TextWidthPx(l1), TextWidthPx(l2)

    if w1 <= maxWidth and w2 <= maxWidth then
      local score = math.abs(w1 - w2) + (math.max(w1, w2) * 0.01)
      if #words >= 3 and i == (#words - 1) then score = score - 2 end
      if score < bestScore then
        bestScore = score
        bestL1, bestL2 = l1, l2
      end
    end
  end

  if bestScore < 1e18 then return bestL1, bestL2 end

  -- Fallback: fit as much as possible on first line
  local l1 = words[1]
  for i = 2, #words do
    local candidate = table.concat(words, " ", 1, i)
    if TextWidthPx(candidate) <= maxWidth then
      l1 = candidate
    else
      break
    end
  end
  local l2 = Trim(name:sub(#l1 + 1))
  if l2 == "" then l2 = table.concat(words, " ", 2) end
  return l1, l2
end

-- ============================================================
-- Main UI Initialization
-- ============================================================
local function InitializeClasslessUI()
  -- Helper: Deep copy table with metatable preservation
  local function tCopy(t)
    local u = {}
    for k, v in pairs(t or {}) do u[k] = v end
    return setmetatable(u, getmetatable(t))
  end

  -- Helper: Remove all instances of key from array
  local function tRemoveKey(tbl, key)
    for i = #tbl, 1, -1 do
      if tbl[i] == key then tremove(tbl, i) end
    end
  end

  -- Fix tooltip first line font to match game style
  local function FixTooltipFirstLineFont(tt)
    if not tt then return end
    local n = tt:GetName()
    if not n then return end

    local L1 = _G[n.."TextLeft1"]
    local R1 = _G[n.."TextRight1"]
    if L1 then L1:SetFontObject(GameTooltipText) end
    if R1 then R1:SetFontObject(GameTooltipText) end
  end

  -- ============================================================
  -- Cost and Meta Information Indexes
  -- ============================================================
  local CostIndex  = {}  -- spellId -> { ap, tp }
  local GrantIndex = {}  -- spellId -> { grantedSpellIds... }
  local NoteIndex  = {}  -- spellId -> noteText

  -- Get metadata from entry (if it exists)
  local function GetNodeMeta(entry)
    if not entry then return nil end
    local m = entry[4]
    if type(m) == "table" then return m end
    return nil
  end

  -- Calculate AP/TP cost for a specific spell/talent rank
  local function GetNodeCost(mode, entry, rank)
    if not entry or not rank then return 0, 0 end

    local meta = entry[4]
    local baseAP = (mode == "spell") and 1 or 0
    local baseTP = (mode == "talent") and 1 or 0

    if type(meta) == "table" then
      local cost = meta.cost or meta.Cost
      if not cost and (meta.ap or meta.tp or meta.AP or meta.TP or meta[1] or meta[2]) then
        cost = meta
      end
      if not cost then return baseAP, baseTP end

      local ap = cost.ap or cost.AP or cost[1]
      local tp = cost.tp or cost.TP or cost[2]

      -- Handle rank-specific costs (costs can be arrays)
      if type(ap) == "table" then
        ap = ap[rank] or ap[1] or 0  -- Fallback to rank 1 or 0
      end
      if type(tp) == "table" then
        tp = tp[rank] or tp[1] or 0  -- Fallback to rank 1 or 0
      end

      ap = tonumber(ap)
      tp = tonumber(tp)

      if ap == nil and tp == nil then return baseAP, baseTP end
      return tonumber(ap or 0) or 0, tonumber(tp or 0) or 0
    end

    -- Legacy format: meta == 1 means special cost
    if meta == 1 then
      if mode == "spell" then
        return baseAP, (rank == 1) and 1 or 0
      else
        return (rank == 1) and 1 or 0, baseTP
      end
    end

    return baseAP, baseTP
  end

  -- Build index of all spell/talent costs
  local function BuildCostIndex()
    if not db or not db.data then
      print("[ClassLess] WARNING: CLDB data not loaded")
      return
    end

    wipe(CostIndex)

    -- Index spell costs
    for class, classTbl in pairs(db.data.spells or {}) do
      for spec = 1, #classTbl do
        for _, entry in ipairs(classTbl[spec][4] or {}) do
          local ranks = entry[1] or {}
          for r = 1, #ranks do
            local sid = ranks[r]
            if sid and sid > 0 then
              local ap, tp = GetNodeCost("spell", entry, r)
              CostIndex[sid] = { ap=ap, tp=tp }
            end
          end
        end
      end
    end

    -- Index talent costs
    for class, classTbl in pairs(db.data.talents or {}) do
      for spec = 1, #classTbl do
        for _, entry in ipairs(classTbl[spec][4] or {}) do
          local ranks = entry[1] or {}
          for r = 1, #ranks do
            local sid = ranks[r]
            if sid and sid > 0 then
              local ap, tp = GetNodeCost("talent", entry, r)
              CostIndex[sid] = { ap=ap, tp=tp }
            end
          end
        end
      end
    end
  end

  -- Build indexes for grants and notes
  local function BuildIndexes()
    if not db or not db.data then
      print("[ClassLess] WARNING: CLDB data not loaded")
      return
    end

    wipe(GrantIndex)
    wipe(NoteIndex)

    local function IndexEntry(entry)
      local meta = GetNodeMeta(entry)
      if not meta then return end

      local ranks = entry[1] or {}

      -- Index grants (spells that are auto-learned with this spell)
      if type(meta.grants) == "table" then
        for r = 1, #ranks do
          local sid = ranks[r]
          if sid and sid > 0 then
            GrantIndex[sid] = tCopy(meta.grants)
          end
        end
      end

      -- Index notes (tooltip text)
      if meta.note ~= nil and tostring(meta.note) ~= "" then
        for r = 1, #ranks do
          local sid = ranks[r]
          if sid and sid > 0 then
            NoteIndex[sid] = tostring(meta.note)
          end
        end
      end
    end

    -- Process spells
    for class, classTbl in pairs(db.data.spells or {}) do
      for spec = 1, #classTbl do
        for _, entry in ipairs(classTbl[spec][4] or {}) do
          IndexEntry(entry)
        end
      end
    end

    -- Process talents
    for class, classTbl in pairs(db.data.talents or {}) do
      for spec = 1, #classTbl do
        for _, entry in ipairs(classTbl[spec][4] or {}) do
          IndexEntry(entry)
        end
      end
    end
  end

  -- Build effective spell list from base + pending adds - pending removes
  local function BuildEffectiveArray(base, plus, minus)
    local arr = tCopy(base or {})

    for i = 1, #(plus or {}) do
      local id = plus[i]
      if id and not tContains(arr, id) then
        tinsert(arr, id)
      end
    end

    for i = 1, #(minus or {}) do
      local id = minus[i]
      if id then
        tRemoveKey(arr, id)
      end
    end

    return arr
  end

  -- Recursively expand grants to include all granted spells
  local function AddGrantsToSet(set)
    if not set then return end

    local changed = true
    local guard = 0

    while changed and guard < MAX_GRANT_DEPTH do
      changed = false
      guard = guard + 1

      for sid, _ in pairs(set) do
        local g = GrantIndex[sid]
        if g then
          for i = 1, #g do
            local gid = g[i]
            if gid and tonumber(gid) and not set[gid] then
              set[gid] = true
              changed = true
            end
          end
        end
      end
    end

    -- Warn if we hit the depth limit (possible circular grants)
    if guard >= MAX_GRANT_DEPTH then
      print("[ClassLess] WARNING: Grant chain exceeded max depth of "..MAX_GRANT_DEPTH)
    end
  end

  -- Build complete set of effective spells including grants
  local function BuildEffectiveSets()
    if not db then
      return {}, {}, {}, {}
    end

    local effSpells  = BuildEffectiveArray(db.spells,  spellsplus,  spellsminus)
    local effTpells  = BuildEffectiveArray(db.tpells,  tpellsplus,  tpellsminus)
    local effTalents = BuildEffectiveArray(db.talents, talentsplus, talentsminus)

    local set = {}
    for i = 1, #effSpells  do set[effSpells[i]]  = true end
    for i = 1, #effTpells  do set[effTpells[i]]  = true end
    for i = 1, #effTalents do set[effTalents[i]] = true end

    AddGrantsToSet(set)
    return effSpells, effTpells, effTalents, set
  end

  -- Sum total AP/TP costs for a set of spells
  local function SumUsedCosts(set)
    local usedAP, usedTP = 0, 0

    for id, _ in pairs(set or {}) do
      local c = CostIndex[id]
      if c then
        usedAP = usedAP + (c.ap or 0)
        usedTP = usedTP + (c.tp or 0)
      end
    end

    return usedAP, usedTP
  end

  -- ============================================================
  -- UI Creation Utilities
  -- ============================================================

  -- Create a texture on a frame
  local function CreateTexture(base, layer, path, blend)
    if not base then return nil end

    local t = base:CreateTexture(nil, layer)
    if path then t:SetTexture(path) end
    if blend then t:SetBlendMode(blend) end
    return t
  end

  -- Set up frame background with corner textures
  local function FrameBackground(frame, background)
    if not frame or not background then return end

    local t = CreateTexture(frame, "BACKGROUND")
    t:SetPoint("TOPLEFT")
    frame.topleft = t

    t = CreateTexture(frame, "BACKGROUND")
    t:SetPoint("TOPLEFT", frame.topleft, "TOPRIGHT")
    frame.topright = t

    t = CreateTexture(frame, "BACKGROUND")
    t:SetPoint("TOPLEFT", frame.topleft, "BOTTOMLEFT")
    frame.bottomleft = t

    t = CreateTexture(frame, "BACKGROUND")
    t:SetPoint("TOPLEFT", frame.topleft, "BOTTOMRIGHT")
    frame.bottomright = t

    frame.topleft:SetTexture(background.."-TopLeft")
    frame.topright:SetTexture(background.."-TopRight")
    frame.bottomleft:SetTexture(background.."-BottomLeft")
    frame.bottomright:SetTexture(background.."-BottomRight")
  end

  -- Set frame size and adjust background textures
  local function FrameLayout(frame, width, height)
    if not frame then return end

    local texture_height = height / (256 + 75)
    local texture_width = width / (256 + 44)

    frame:SetSize(width, height)

    local wl, wr = texture_width * 256, texture_width * 64
    local ht, hb = texture_height * 256, texture_height * 128

    if frame.topleft then frame.topleft:SetSize(wl, ht) end
    if frame.topright then frame.topright:SetSize(wr, ht) end
    if frame.bottomleft then frame.bottomleft:SetSize(wl, hb) end
    if frame.bottomright then frame.bottomright:SetSize(wr, hb) end
  end

  -- Create a standard button with textures
  local function MakeButton(name, parent)
    local button = CreateFrame("Button", name, parent)
    button:SetNormalFontObject(GameFontNormal)
    button:SetHighlightFontObject(GameFontHighlight)
    button:SetDisabledFontObject(GameFontDisable)

    local texture = button:CreateTexture()
    texture:SetTexture("Interface/Buttons/UI-Panel-Button-Up")
    texture:SetTexCoord(0, 0.625, 0, 0.6875)
    texture:SetAllPoints(button)
    button:SetNormalTexture(texture)

    texture = button:CreateTexture()
    texture:SetTexture("Interface/Buttons/UI-Panel-Button-Down")
    texture:SetTexCoord(0, 0.625, 0, 0.6875)
    texture:SetAllPoints(button)
    button:SetPushedTexture(texture)

    texture = button:CreateTexture()
    texture:SetTexture("Interface/Buttons/UI-Panel-Button-Highlight")
    texture:SetTexCoord(0, 0.625, 0, 0.6875)
    texture:SetAllPoints(button)
    button:SetHighlightTexture(texture)

    return button
  end

  -- Create rank display frame for talent buttons
  local function MakeRankFrame(button)
    local bg = CreateFrame("Frame", nil, button)
    bg:SetSize(22, 12)
    bg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
    bg:SetBackdrop({
      bgFile = "Interface/ChatFrame/ChatFrameBackground",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
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
    fs:SetFont("Fonts/FRIZQT__.TTF", 9, "OUTLINE")
    return fs
  end

  -- Create a spell/talent button with icon and borders
  local function NewButton(name, parent, size, icon, wantRank, a, b, c, d)
    local button = CreateFrame("Button", name, parent)
    button:SetSize(size, size)
    button:EnableMouse(true)
    button:SetHitRectInsets(-2, -2, -2, -2)

    -- Icon texture
    local it = CreateTexture(button, "BORDER")
    it:SetSize(size, size)
    it:SetPoint("CENTER")
    button.texture = it
    if icon then
      it:SetTexture(icon)
      if a ~= nil then it:SetTexCoord(a, b, c, d) end
    end

    -- Base border
    local base = CreateTexture(button, "ARTWORK", "Interface/Buttons/UI-Quickslot2")
    base:SetSize(size * CL_BORDER_SCALE, size * CL_BORDER_SCALE)
    base:SetPoint("CENTER", button, "CENTER", 0, 0)
    base:SetVertexColor(1, 1, 1, 1)
    button.baseBorder = base
    button:SetNormalTexture(base)

    -- Color border overlay
    local color = CreateTexture(button, "OVERLAY", "Interface/Buttons/UI-Quickslot2", "ADD")
    color:SetSize(size * CL_BORDER_SCALE, size * CL_BORDER_SCALE)
    color:SetPoint("CENTER", button, "CENTER", 0, 0)
    color:SetAlpha(0)
    button.colorBorder = color

    -- Pushed texture
    local pushed = CreateTexture(button, "ARTWORK", "Interface/Buttons/UI-Quickslot-Depress")
    pushed:SetSize(size, size)
    pushed:SetPoint("CENTER")
    button:SetPushedTexture(pushed)

    -- Highlight texture
    local hl = CreateTexture(button, "HIGHLIGHT", "Interface/Buttons/ButtonHilight-Square", "ADD")
    hl:SetSize(size, size)
    hl:SetPoint("CENTER")
    button:SetHighlightTexture(hl)

    if wantRank then
      button.rank = MakeRankFrame(button)
    end

    return button
  end

  -- Set button border color based on learned state
  local function SetButtonBorder(button, mode, state, rank, ranks, selected)
    if not button or not button.baseBorder or not button.colorBorder then return end

    local function Base(r, g, b, a)
      button.baseBorder:SetVertexColor(r, g, b)
      button.baseBorder:SetAlpha(a or 1)
    end

    local function Color(r, g, b, a, hideBase)
      button.colorBorder:SetVertexColor(r, g, b)
      button.colorBorder:SetAlpha(a or 0)
      if hideBase and (a or 0) > 0 then
        button.baseBorder:SetAlpha(0)
      else
        button.baseBorder:SetAlpha(1)
      end
    end

    -- Reset to defaults
    Base(1, 1, 1, 1)
    Color(1, 1, 1, 0, false)

    -- Selected state (gold)
    if selected then
      Color(1.0, 0.82, 0.0, 0.48, true)
      return
    end

    -- Spell border logic
    if mode == "spell" then
      if rank > 0 then
        Color(1.0, 0.82, 0.0, 0.48, true)  -- Learned = gold
      end
      if state == "disabled" then
        Base(0.55, 0.55, 0.55, 1)
        Color(0.55, 0.55, 0.55, 0.12, false)
      end
      return
    end

    -- Talent border logic
    if mode == "talent" then
      if ranks > 0 and rank >= ranks then
        Color(1.0, 0.82, 0.0, 1.0, true)  -- Max rank = solid yellow
        return
      elseif rank > 0 then
        Color(0.0, 1.0, 0.0, 1.0, true)   -- Learned = solid green
        return
      end
    end

    -- Disabled state
    if state == "disabled" then
      Base(0.55, 0.55, 0.55, 1)
      Color(0.55, 0.55, 0.55, 0.12, false)
      return
    end

    -- Default grey for unlearned talents
    if mode == "talent" then
      Base(0.4, 0.4, 0.4, 1.0)
    end
  end

  -- ============================================================
  -- Tooltip Helpers
  -- ============================================================
  local DIVIDER_TEX = "Interface/DialogFrame/UI-DialogBox-Divider"

  -- Add visual divider line to tooltip
  local function AddDivider(tt)
    if not tt then return end

    local w = math.floor((tt:GetWidth() or 320) - 24)
    if w < 180 then w = 300 end
    tt:AddLine("|T"..DIVIDER_TEX..":8:"..w.."|t", 1, 1, 1, false)
  end

  -- Safely get spell link (fallback for missing spells)
  local function SafeSpellLink(spell)
    local link = GetSpellLink(spell)
    if link == nil then
      link = GetSpellLink(78)  -- Use a known spell as template
      if link then
        link = string.gsub(link, "78", tostring(spell))
      end
    end
    return link
  end

  -- Parse spell tooltip into structured line data
  local function ParseTooltipRich(spell)
    local f = _G["CLTmpTooltip"] or CreateFrame("GameTooltip", "CLTmpTooltip", UIParent, "GameTooltipTemplate")
    f:SetOwner(UIParent, "ANCHOR_NONE")
    f:ClearLines()

    local link = SafeSpellLink(spell)
    if link then f:SetHyperlink(link) end

    local num = f:NumLines() or 0
    local lines = {}

    for i = 1, num do
      local lfs = _G["CLTmpTooltipTextLeft"..i]
      local rfs = _G["CLTmpTooltipTextRight"..i]
      local lt = lfs and lfs:GetText() or nil
      local rt = rfs and rfs:GetText() or nil

      if lt or rt then
        local lr, lg, lb = 1, 1, 1
        local rr, rg, rb = 1, 1, 1
        if lfs then lr, lg, lb = lfs:GetTextColor() end
        if rfs then rr, rg, rb = rfs:GetTextColor() end
        lines[i] = { l=lt, r=rt, lr=lr, lg=lg, lb=lb, rr=rr, rg=rg, rb=rb }
      end
    end

    f:ClearLines()
    f:Hide()
    return lines, num
  end

  local BOOK_SPELL = _G.BOOKTYPE_SPELL or "spell"

  -- Strip WoW color codes from text
  local function CL_StripColorCodes(s)
    if not s or s == "" then return "" end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    return s
  end

  -- Strip texture codes from text
  local function CL_StripTextures(s)
    if not s or s == "" then return "" end
    s = s:gsub("|T.-|t", "")
    return s
  end

  -- Normalize tooltip text for comparison
  local function CL_NormalizeTooltipText(s)
    s = CL_StripTextures(CL_StripColorCodes(s or ""))
    s = Trim(s)
    s = s:gsub("%s+", " ")
    return s
  end

  -- Extract spell ID from spell link
  local function CL_GetSpellIdFromLink(link)
    if not link then return nil end
    local id = link:match("spell:(%d+)")
    return id and tonumber(id) or nil
  end

  -- Find spell book slot by spell ID
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

  -- Check if spell is passive by querying spellbook
  local function CL_IsPassiveBySpellBook(spellId)
    if type(_G.IsPassiveSpell) ~= "function" then return nil end
    local slot = CL_FindSpellBookSlotById(spellId)
    if not slot then return nil end

    local ok, res = pcall(_G.IsPassiveSpell, slot, BOOK_SPELL)
    if ok and res ~= nil then return (res == true or res == 1) end
    return nil
  end

  -- Check if spell is passive by looking for "Passive" token in tooltip
  local function CL_IsPassiveByTooltipToken(lines, num)
    if not lines or (num or 0) <= 0 then return false end

    local passiveToken = _G.PASSIVE or "Passive"
    local r1 = lines[1] and lines[1].r
    if r1 and r1 ~= "" and CL_NormalizeTooltipText(r1) == passiveToken then
      return true
    end

    for i = 1, math.min(num or 0, 4) do
      local l = lines[i] and lines[i].l
      if l and l ~= "" and CL_NormalizeTooltipText(l) == passiveToken then
        return true
      end
    end

    return false
  end

  -- Check if spell looks like an active ability from tooltip
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

  -- Determine if spell is passive (tries multiple methods)
  local function CL_IsSpellPassive(spellId, parsedLines, parsedNum)
    if not spellId then return false end

    -- Try spellbook API first (most reliable)
    local byBook = CL_IsPassiveBySpellBook(spellId)
    if byBook ~= nil then return byBook end

    -- Use parsed tooltip if provided
    if parsedLines and parsedNum then
      if CL_IsPassiveByTooltipToken(parsedLines, parsedNum) then return true end
      if CL_IsProbablyActiveFromTooltip(parsedLines, parsedNum) then return false end
      return true
    end

    -- Parse tooltip ourselves
    local lines, num = ParseTooltipRich(spellId)
    if CL_IsPassiveByTooltipToken(lines, num) then return true end
    if CL_IsProbablyActiveFromTooltip(lines, num) then return false end
    return true
  end

  -- Check if text line starts with "Requires"
  local function CL_LineStartsWithRequires(txt)
    if not txt or txt == "" then return false end
    local clean = CL_NormalizeTooltipText(txt)
    local low = clean:lower()
    return low:find("^requires") ~= nil
  end

  -- Append spell description body to tooltip
  local function AppendSpellBody(tt, spellId, startLine, opts)
    if not tt or not spellId then return end

    opts = opts or {}
    local lines, num = opts.lines, opts.num
    if not lines or not num then
      lines, num = ParseTooltipRich(spellId)
    end

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
            -- Merge multi-line "Requires" text
            local merged = ln.l or ""
            local j = i + 1
            while j <= num do
              local nxt = lines[j]
              if not nxt then
                j = j + 1
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
      else
        i = i + 1
      end
    end
  end

  -- Append spell section (name + body) to tooltip
  local function AppendSpellSection(tt, spellId, showIcon, opts)
    if not tt or not spellId then return end

    local name, _, icon = GetSpellInfo(spellId)
    name = name or ("Spell "..tostring(spellId))
    icon = icon or "Interface/Icons/INV_Misc_QuestionMark"

    local lines, num = ParseTooltipRich(spellId)
    local ln1 = lines and lines[1] or nil
    local leftText = name

    if showIcon then
      leftText = "|T"..icon..":18|t "..leftText
    end

    if ln1 and ln1.r and ln1.r ~= "" then
      tt:AddDoubleLine(leftText, ln1.r, 1, 1, 1, ln1.rr or 1, ln1.rg or 1, ln1.rb or 1)
    else
      tt:AddLine(WOW_WHITE..leftText.."|r", 1, 1, 1, true)
    end

    opts = opts or {}
    opts.lines = lines
    opts.num   = num
    AppendSpellBody(tt, spellId, 2, opts)
  end

  -- Build "Requires level X" line for tooltip
  local function BuildRequiresLine(reqLevel)
    if not reqLevel then return nil end
    local met = UnitLevel("player") >= reqLevel
    local num = (met and WOW_GREEN or WOW_RED)..tostring(reqLevel).."|r"
    return WOW_GOLD.."Requires level:|r "..num
  end

  -- Build cost line showing AP/TP requirements
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

  -- Set up tooltip for spell button
  local function SpellButtonTooltip(button, nspell, spellForId, rank, ranks, reqLevel, apAvail, tpAvail, costAP, costTP, lock, req, rreq)
    if not button then return end

    local bname = button:GetName()
    if not bname then return end

    button.tooltip = _G[bname..'tooltip'] or CreateFrame('GameTooltip', bname..'tooltip', button, 'GameTooltipTemplate')

    button:SetScript("OnEnter", function(self)
      local tt = button.tooltip
      if not tt then return end

      tt:Hide()
      tt:SetOwner(button, "ANCHOR_RIGHT")
      tt:ClearLines()

      local mainSpell = nspell or spellForId
      local grants = GrantIndex[mainSpell] or GrantIndex[spellForId]
      local hasGrants = (type(grants) == "table" and #grants > 0)
      local note = NoteIndex[mainSpell] or NoteIndex[spellForId]

      if (not note or note == "") and not hasGrants then
        AppendSpellBody(tt, mainSpell, 1)
      else
        if note and note ~= "" then
          tt:AddLine(WOW_WHITE..tostring(note).."|r", 1, 1, 1, true)
          AddDivider(tt)
        end
        AppendSpellSection(tt, mainSpell, hasGrants)
        if hasGrants then
          for i = 1, #grants do
            local gid = grants[i]
            if gid then
              AddDivider(tt)
              AppendSpellSection(tt, gid, true, { skipRequires = true })
            end
          end
        end
      end

      if rreq ~= nil then tt:AddLine(rreq, 1, 0, 0, true) end
      if req ~= nil  then tt:AddLine(req,  1, 0, 0, true) end
      if lock ~= nil then tt:AddLine(lock, 1, 0, 0, true) end

      if rank < ranks then
        tt:AddLine(" ")
        tt:AddLine(BuildCostLine(apAvail, tpAvail, costAP, costTP), 1, 1, 1, true)
        local rline = BuildRequiresLine(reqLevel)
        if rline then tt:AddLine(rline, 1, 1, 1, true) end
      end

      tt:AddLine("SPELLID: "..tostring(spellForId), 1, 1, 1, true)
      FixTooltipFirstLineFont(tt)
      tt:Show()
    end)

    button:SetScript("OnLeave", function()
      if button.tooltip then button.tooltip:Hide() end
    end)
  end

  -- Set up tooltip for talent button (handles ranks)
  local function TalentButtonTooltip(button, spellid, rank, ranks, reqLevel, apAvail, tpAvail, costAP, costTP, lock, req, rreq, shownSpellIdForIdLine, canLearnNow)
    if not button or not spellid then return end

    local bname = button:GetName()
    if not bname then return end

    button.tooltip = _G[bname..'tooltip'] or CreateFrame('GameTooltip', bname..'tooltip', button, 'GameTooltipTemplate')

    button:SetScript("OnEnter", function(self)
      local tt = button.tooltip
      if not tt then return end

      tt:Hide()
      tt:SetOwner(button, "ANCHOR_RIGHT")
      tt:ClearLines()

      local curSpell = spellid[(rank > 0) and rank or 1]
      local nextSpell = nil
      if rank > 0 and rank < ranks then nextSpell = spellid[rank + 1] end
      local metaSpell = (rank < ranks and spellid[(rank > 0 and rank + 1) or 1]) or curSpell
      local grants = GrantIndex[metaSpell] or GrantIndex[curSpell]
      local hasGrants = (type(grants) == "table" and #grants > 0)
      local note = NoteIndex[metaSpell] or NoteIndex[curSpell] or (nextSpell and NoteIndex[nextSpell])

      if note and note ~= "" then
        tt:AddLine(WOW_GREEN..tostring(note).."|r", 1, 1, 1, true)
        AddDivider(tt)
      end

      local curName, _, curIcon = GetSpellInfo(curSpell)
      curName = curName or "Talent"
      curIcon = curIcon or "Interface/Icons/INV_Misc_QuestionMark"

      if hasGrants then
        tt:AddLine("|T"..curIcon..":18|t "..WOW_WHITE..curName.."|r", 1, 1, 1, true)
      else
        tt:AddLine(WOW_WHITE..curName.."|r", 1, 1, 1, true)
      end

      tt:AddLine(WOW_WHITE.."Rank "..rank.."/"..ranks.."|r", 1, 1, 1, true)
      AppendSpellBody(tt, curSpell, 2)

      if nextSpell then
        tt:AddLine(" ")
        tt:AddLine(WOW_WHITE.."Next rank:|r", 1, 1, 1, false)
        local nName, _, nIcon = GetSpellInfo(nextSpell)
        nName = nName or "Next"
        nIcon = nIcon or "Interface/Icons/INV_Misc_QuestionMark"

        if hasGrants then
          tt:AddLine("|T"..nIcon..":18|t "..WOW_WHITE..nName.."|r", 1, 1, 1, true)
        else
          tt:AddLine(WOW_WHITE..nName.."|r", 1, 1, 1, true)
        end
        AppendSpellBody(tt, nextSpell, 2)
      end

      if hasGrants then
        for i = 1, #grants do
          local gid = grants[i]
          if gid then
            AddDivider(tt)
            AppendSpellSection(tt, gid, true, { skipRequires = true })
          end
        end
      end

      if rreq ~= nil then tt:AddLine(rreq, 1, 0, 0, true) end
      if req ~= nil  then tt:AddLine(req,  1, 0, 0, true) end
      if lock ~= nil then tt:AddLine(lock, 1, 0, 0, true) end

      if rank < ranks then
        tt:AddLine(" ")
        tt:AddLine(BuildCostLine(apAvail, tpAvail, costAP, costTP), 1, 1, 1, true)
        local rline = BuildRequiresLine(reqLevel)
        if rline then tt:AddLine(rline, 1, 1, 1, true) end
        if canLearnNow then
          tt:AddLine(WOW_GREEN.."Click to learn|r", 1, 1, 1, true)
        end
      end

      tt:AddLine("SPELLID: "..tostring(shownSpellIdForIdLine or curSpell), 1, 1, 1, true)
      FixTooltipFirstLineFont(tt)
      tt:Show()
    end)

    button:SetScript("OnLeave", function()
      if button.tooltip then button.tooltip:Hide() end
    end)
  end

  -- ============================================================
  -- Points System (Item-based currency)
  -- ============================================================
  local function GetPoints(pointType)
    if pointType == "ap" then
      local pool = GetItemCount(AP_ITEM_ID)

      -- Calculate pending cost/refund
      local pendingCost = 0
      for _, sid in ipairs(spellsplus) do
        local c = CostIndex[sid]
        if c then pendingCost = pendingCost + (c.ap or 0) end
      end
      for _, sid in ipairs(talentsplus) do
        local c = CostIndex[sid]
        if c then pendingCost = pendingCost + (c.ap or 0) end
      end

      local pendingRefund = 0
      for _, sid in ipairs(spellsminus) do
        local c = CostIndex[sid]
        if c then pendingRefund = pendingRefund + (c.ap or 0) end
      end
      for _, sid in ipairs(talentsminus) do
        local c = CostIndex[sid]
        if c then pendingRefund = pendingRefund + (c.ap or 0) end
      end

      return pool - pendingCost + pendingRefund, 0
    end

    if pointType == "tp" then
      local pool = GetItemCount(TP_ITEM_ID)

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

    if pointType == "sp" then
      return statCache.left or 0, 0
    end

    return 0, 0
  end

  -- ============================================================
  -- Apply / Reset Functions
  -- ============================================================
  local function SetBtnEnabled(btn, enabled)
    if not btn then return end
    if enabled then
      btn:Enable()
      btn:SetAlpha(1.0)
    else
      btn:Disable()
      btn:SetAlpha(0.35)
    end
  end

  local function PendingAny()
    return (#spellsplus + #spellsminus + #tpellsplus + #tpellsminus + #talentsplus + #talentsminus) > 0
  end

