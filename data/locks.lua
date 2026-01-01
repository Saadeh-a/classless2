--LOCKS
local tlocks={

-- Movement Speeds and gap closers
{100,20252,3411,781,2983,36554,49576,1953,48020,1850},

-- Interrupts
{47528,6552,72,1766,57994,0000000,47476,2139,15487,34490},

-- Damage Increase
-- {49016,12292,57934,19574,31884,47241,50334},

-- Health Increase
--{{48982,49005,55233},12975,19236,6201,61336},

-- Reduce Damage
{871,498,19263,5277,48792,30823,22812,47585},

-- Fear
{5246,8122,5484},

-- Battle Ress
{693,20484},

-- Aoe Taunt
{1161,59671,5209,31789},

-- Bloodlust Hero
{32182,2825},

-- Teleport and portals
{{3563,3567,3566,32272,49358,35715,49361,11417,32267,11418,11420,35717},{3561,3562,3565,32271,49359,33690,49360,32266,11416,10059,11419,33691}},

{12051,64901,{1454,18220},34074,29166,16190,54428},

-- Reduces the duration of all movement slowing effects
{49042,12299,16252,20143},

-- Dodge
{55129,12297,{17002,57878},16254,20096},
}

if CLDB==nil then CLDB={} end
if CLDB.locks==nil then CLDB.locks={} end

CLDB.locks={}
for i=1,#tlocks do
local spells=tlocks[i]
for j=1,#spells do

spell=spells[j]
if type(spell)~="table" then spell={spell} end

for k=1,#spell do
tspell=spell[k]
if CLDB.locks[tspell]==nil then CLDB.locks[tspell] ={} end

for l=1,#spells do
if l~=j then 
if type(spells[l])~="table" then
tinsert(CLDB.locks[tspell],spells[l]) else for m=1,#spells[l] do tinsert(CLDB.locks[tspell],spells[l][m]) end end
end

end
end
end
end
