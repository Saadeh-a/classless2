--REQUIREMENTS
local treq={
{25899,20911},
{{25782,25916,27141,48933,48934},{19838,25291,27140,48931,48932}},
{61846,13165},
{55610,50887},
}

if CLDB==nil then CLDB={} end
if CLDB.req==nil then CLDB.req={} end

for i=1,#treq do
local spells=treq[i]
local rspells,nspells=spells[1],spells[2]
if type(rspells)~="table" then rspells={rspells} end
if type(nspells)~="table" then nspells={nspells} end

for j=1,#rspells do
CLDB.req[rspells[j]]=nspells[j]
end

end



if CLDB.rreq==nil then CLDB.rreq={} end
local i=1
for k,v in pairs(CLDB.req) do
CLDB.rreq[v]=k
i=i+1
end
