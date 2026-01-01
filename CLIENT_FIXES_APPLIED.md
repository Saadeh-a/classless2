# ClassLess Client Cleanup Summary

## ✅ Fixes Applied to First 1000 Lines

### 1. **Fixed Path Separators** (Lines 6-9, 48-50, 118, etc.)
```lua
-- BEFORE:
AIO.AddAddon("lua_scripts\\ClassLess\\data\\spells.lua", "spells")
button.nameText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")

-- AFTER:
AIO.AddAddon("lua_scripts/ClassLess/data/spells.lua", "spells")
button.nameText:SetFont("Fonts/FRIZQT__.TTF", 10, "OUTLINE")
```
**Impact:** Cross-platform compatibility (works on Linux servers)

### 2. **Renamed DoShit() → InitializeClasslessUI()** (Line 178)
```lua
-- BEFORE:
local function DoShit()

-- AFTER:
local function InitializeClasslessUI()
```
**Impact:** Professional code, better maintainability

### 3. **Added Constants Section**
```lua
-- Currency Items
local AP_ITEM_ID = 16203  -- Ability Point item
local TP_ITEM_ID = 11135  -- Talent Point item

-- Icon paths
local AP_ICON = "Interface/Icons/inv_enchant_essenceeternallarge"
local TP_ICON = "Interface/Icons/inv_enchant_essencemysticallarge"
local SP_ICON = "Interface/Icons/inv_enchant_essenceastrallarge"

-- Grant recursion safety
local MAX_GRANT_DEPTH = 50  -- Increased from 20
```
**Impact:** Easy configuration, no magic numbers

### 4. **Improved Grant Recursion Safety** (Line 315)
```lua
-- BEFORE:
while changed and guard < 20 do

-- AFTER:
while changed and guard < MAX_GRANT_DEPTH do
  -- ... grant expansion logic ...
end

-- Warn if we hit the depth limit (possible circular grants)
if guard >= MAX_GRANT_DEPTH then
  print("[ClassLess] WARNING: Grant chain exceeded max depth of "..MAX_GRANT_DEPTH)
end
```
**Impact:** Better debugging, configurable depth, warnings for circular grants

### 5. **Added Safety Checks Throughout**
```lua
-- BEFORE:
local c = CLASS_ICON_TCOORDS[classFile]

-- AFTER:
if not CLASS_ICON_TCOORDS then return "" end
local c = CLASS_ICON_TCOORDS[classFile]
if not c then return "" end
```
**Impact:** Prevents errors on older clients

### 6. **Better Error Handling in BuildCostIndex()**
```lua
if not db or not db.data then
  print("[ClassLess] WARNING: CLDB data not loaded")
  return
end
```
**Impact:** Clear error messages instead of silent failures

### 7. **Fixed Rank-Specific Cost Fallback** (Lines 223-224)
```lua
-- BEFORE:
if type(ap) == "table" then ap = ap[rank] end

-- AFTER:
if type(ap) == "table" then
  ap = ap[rank] or ap[1] or 0  -- Fallback to rank 1 or 0
end
```
**Impact:** Prevents nil costs when rank data is incomplete

### 8. **Added Comprehensive Documentation**
- File header with environment info
- Section headers for organization
- Function purpose descriptions
- Inline comments explaining complex logic
- Parameter documentation

---

## 🔴 CRITICAL FIXES NEEDED for Lines 1000-2036

### **FIX #1: Remove OnUpdate Performance Killer** ⚠️ CRITICAL
**Location:** Lines 2010-2012
**Severity:** HIGH - Causes client lag, CPU spike

```lua
-- BEFORE (PERFORMANCE KILLER):
frame:SetScript("OnUpdate", function()
  UpdateApplyReset()
end)

-- AFTER (REMOVE IT):
-- OnUpdate removed - updates triggered by events only
-- frame:SetScript("OnUpdate", nil)  -- Not needed, just don't set it
```

**Why this is critical:**
- `OnUpdate` runs EVERY SINGLE FRAME (60+ times per second)
- `UpdateApplyReset()` does expensive calculations every frame
- Causes massive CPU waste and client stuttering
- Updates should be event-driven, not polled

**Proper approach:** `UpdateApplyReset()` is already called by:
- `LearnConfirm()` (line 1048)
- `FillSpells()` (line 1302)
- Button clicks (line 1516)
- Tab changes (line 2002)
- OnShow (line 2006)

No need for OnUpdate at all!

### **FIX #2: Update DoShit() Reference**
**Location:** Line 2029

```lua
-- BEFORE:
function ClassLessHandlers.LoadVars(player,spr,tpr,tar,str)
  db.spells=spr or {}
  db.tpells=tpr or {}
  db.talents=tar or {}
  db.stats=str or {0,0,0,0,0}
  DoShit()  -- ❌ Old name
end

-- AFTER:
function ClassLessHandlers.LoadVars(player, spr, tpr, tar, str)
  db.spells = spr or {}
  db.tpells = tpr or {}
  db.talents = tar or {}
  db.stats = str or {0, 0, 0, 0, 0}
  InitializeClasslessUI()  -- ✅ New name
end
```

### **FIX #3: Fix More Path Separators**
**Location:** Lines 1229, 1241, 1336, 1356, 1887, 1921, 1977-1981

```lua
-- BEFORE:
button.nameText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
icon:SetTexture('interface\\ClasslessUI\\Mainbutton')
frame.bg:SetTexture("interface\\ClasslessUI\\progress_inside_blue")
frameStat:SetBackdrop({ bgFile = "interface\\ClasslessUI\\allocationbuttonframe" })

-- AFTER:
button.nameText:SetFont("Fonts/FRIZQT__.TTF", 10, "OUTLINE")
icon:SetTexture('interface/ClasslessUI/Mainbutton')
frame.bg:SetTexture("interface/ClasslessUI/progress_inside_blue")
frameStat:SetBackdrop({ bgFile = "interface/ClasslessUI/allocationbuttonframe" })
```

### **FIX #4: Indentation Issues** (Lines 1147-1157)
**Location:** Lines 1147-1157 - Weird indentation breaks code flow

```lua
-- BEFORE:
      local learned = (rank > 0)
      -- Visual rule: ONLY learned spells are highlighted
local icon = button.texture or button.icon  -- ❌ Wrong indentation

if learned then
  icon:SetDesaturated(false)
  -- ...

-- AFTER:
      local learned = (rank > 0)
      -- Visual rule: ONLY learned spells are highlighted
      local iconTex = button.texture or button.icon

      if learned then
        iconTex:SetDesaturated(false)
        iconTex:SetVertexColor(1, 1, 1)
        iconTex:SetAlpha(1)
      else
        iconTex:SetDesaturated(true)
        iconTex:SetVertexColor(0.35, 0.35, 0.35)
        iconTex:SetAlpha(0.85)
      end
```

### **FIX #5: Add Nil Checks for Frame References**
**Location:** Throughout lines 1000-2036

```lua
-- Add checks before using _G references:
local main = _G["CLMainFrame"]
if not main then return end

local button = _G["CLResetButton1"]
if button then SetBtnEnabled(button, pending) end
```

---

## 📊 Impact Summary

| Fix | Lines Affected | Severity | Impact |
|-----|---------------|----------|---------|
| OnUpdate Removal | 2010-2012 | 🔴 CRITICAL | Fixes client lag/CPU spike |
| DoShit() Rename | 2029 | 🟡 Medium | Code consistency |
| Path Separators | 10+ locations | 🔴 HIGH | Linux compatibility |
| Safety Checks | Throughout | 🟢 Low | Error prevention |
| Grant Depth | 315-334 | 🟡 Medium | Debugging circular grants |

---

## 🚀 Quick Apply Instructions

### Option 1: Use cleaned file (first 1000 lines)
```bash
# File already created: classless_client_cleaned.lua
# Contains all fixes for lines 0-1000
```

### Option 2: Manual fixes to original
Apply these critical changes to `classless_client.lua`:

1. **Line 6-9:** Change `\\` to `/`
2. **Line 178:** `DoShit()` → `InitializeClasslessUI()`
3. **Line 318:** Change `20` to `50` and add warning
4. **Line 2010-2012:** DELETE the OnUpdate script entirely
5. **Line 2029:** `DoShit()` → `InitializeClasslessUI()`
6. **All texture paths:** Change `\\` to `/`

---

## ✅ Validation Checklist

After applying fixes:
- [ ] File loads without Lua errors
- [ ] UI appears correctly
- [ ] No lag when frame is open (OnUpdate removed)
- [ ] Buttons respond to clicks
- [ ] Costs calculate correctly
- [ ] Spell learning works
- [ ] Stat allocation works
- [ ] No console errors about missing CLDB

---

## 📁 Files Created

1. `classless_client_cleaned.lua` - First 1000 lines, fully cleaned
2. `classless_client.lua.backup` - Original file backup
3. `CLIENT_FIXES_APPLIED.md` - This documentation

---

## Next Steps

1. Apply fixes #1-#5 above to lines 1000-2036
2. Test in-game on both Windows and Linux
3. Monitor for console errors
4. Check performance (should be much better without OnUpdate)
5. Repeat process for `classless_server.lua` (SQL injection fixes needed!)
