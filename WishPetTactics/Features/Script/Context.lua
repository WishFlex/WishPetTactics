local ADDON_NAME, ns = ...
local Context = {revision = 0}
local function L(s) return ns:CompletionText(s) end
ns.ScriptContext = Context
local function Public(v)
    if ns.IsSecretValue and ns:IsSecretValue(v) then return nil end
    return v
end
local function Read(fn, ...)
    if not fn then return nil end
    local ok, a,b,c,d = pcall(fn, ...)
    if not ok then return nil end
    return Public(a),Public(b),Public(c),Public(d)
end
local function Name(v)
    if type(v) ~= "string" or v == "" then return nil end
    -- Do not invent altered names that the engine could not resolve.
    if v:find("[():%[%]\r\n|]") then return nil end
    return v
end
local function AbilityName(id)
    local _, battleName = Read(C_PetBattles and C_PetBattles.GetAbilityInfoByID,id)
    return Name(battleName) or Name(Read(C_PetJournal and C_PetJournal.GetPetAbilityInfo,id))
end
function Context:GetSnapshot()
    if not C_PetBattles or not Read(C_PetBattles.IsInBattle) then self.snapshot=nil;return nil end
    if self.snapshot and self.snapshotRevision == self.revision then return self.snapshot end
    local ally = Enum.BattlePetOwner.Ally
    local enemy = Enum.BattlePetOwner.Enemy
    local snap = {pets={},active={},ally=ally,enemy=enemy}
    local se = ns.ScriptEngine or {}
    snap.round = Public(se.currentRound)
    snap.rounds = {[ally]=Public(se.sideRound and se.sideRound[ally]),[enemy]=Public(se.sideRound and se.sideRound[enemy])}
    for _, owner in ipairs({ally,enemy}) do
        snap.pets[owner] = {}
        local active = Read(C_PetBattles.GetActivePet,owner)
        if type(active) == "number" then snap.active[owner] = active end
        local count = Read(C_PetBattles.GetNumPets,owner)
        count = type(count) == "number" and math.min(3,count) or 0
        for slot = 1,count do
            local custom, speciesName = Read(C_PetBattles.GetName,owner,slot)
            local id = Read(C_PetBattles.GetPetSpeciesID,owner,slot)
            local pet = {slot=slot,id=type(id)=="number" and id or nil,name=Name(custom) or Name(speciesName),skills={}}
            for idx=1,3 do
                local abID, abName = Read(C_PetBattles.GetAbilityInfo,owner,slot,idx)
                if type(abID)=="number" and abID>0 then
                    local usable, cd, lockdown = Read(C_PetBattles.GetAbilityState,owner,slot,idx)
                    pet.skills[#pet.skills+1] = {id=abID,name=Name(abName) or AbilityName(abID),idx=idx,
                        usable=type(usable)=="boolean" and usable,cd=type(cd)=="number" and cd or nil,lockdown=lockdown}
                end
            end
            snap.pets[owner][slot] = pet
        end
    end
    self.snapshot,self.snapshotRevision = snap,self.revision
    return snap
end
local function Target(snap, text, defaultOwner)
    local who, arg = text:match("([%a]+)%(([^()]*)%)%.$")
    if not who then who = text:match("([%a]+)%.$") end
    local owner = defaultOwner or snap.ally
    if who then
        local low = strlower(who)
        if low == "enemy" then owner = snap.enemy
        elseif low == "self" or low == "ally" then owner = snap.ally end
    end
    local slot = snap.active[owner]
    if arg then
        local number = tonumber(arg:match("^#(%d+)$"))
        if number then slot=number else
            local id = tonumber(arg:match(":(%d+)$")) or tonumber(arg)
            local name = strlower(strtrim(arg:match("^([^:]+)") or arg))
            slot=nil
            for index,pet in ipairs(snap.pets[owner] or {}) do
                if (id and pet.id==id) or (pet.name and strlower(pet.name)==name) then slot=index;break end
            end
        end
    end
    return owner,slot
end
function Context:GetAuras(snap,owner,slot)
    snap.auras = snap.auras or {}
    local key=tostring(owner)..":"..tostring(slot)
    if snap.auras[key] then return snap.auras[key] end
    local rows,seen={},{}
    if slot then
        for _,checkSlot in ipairs({slot,PET_BATTLE_PAD_INDEX or 0}) do
            local count=Read(C_PetBattles.GetNumAuras,owner,checkSlot)
            count=type(count)=="number" and math.min(50,count) or 0
            for i=1,count do
                local id,_,turns=Read(C_PetBattles.GetAuraInfo,owner,checkSlot,i)
                if type(id)=="number" and id>0 and not seen[id] then
                    seen[id]=true;rows[#rows+1]={id=id,name=AbilityName(id),turns=type(turns)=="number" and turns or nil}
                end
            end
        end
    end
    snap.auras[key]=rows
    return rows
end
local function RawName(item)
    return item.name and item.id and (item.name..":"..item.id) or item.id and tostring(item.id)
end
local function PetVariants(pet, full)
    local list={"#"..pet.slot}
    if full and pet.id and pet.id>3 then list[#list+1]=tostring(pet.id) end
    local raw=RawName(pet)
    if raw then list[#list+1]=raw end
    if pet.name and (full or not raw) then list[#list+1]=pet.name end
    return list
end
local function PetsInOrder(snap,owner)
    local list={}
    local active=snap.active[owner]
    if active and snap.pets[owner][active] then list[1]=snap.pets[owner][active] end
    for i,pet in ipairs(snap.pets[owner]) do if i~=active then list[#list+1]=pet end end
    return list
end

-- Returns a replacement range in clean bytes (matching the editor's cursor API).
-- nil means the legacy, battle-outside completion should handle the prefix.
function Context:GetSuggestions(clean,cursor,resolveAllySlot)
    local snap=self:GetSnapshot()
    if not snap then return nil end
    local beforeAll=clean:sub(1,cursor)
    local before=beforeAll:match("([^\r\n]*)$") or ""
    local lineBase=cursor-#before
    local after=clean:sub(cursor+1):match("^[^\r\n]*") or ""
    if before:find("--",1,true) or strtrim(before):sub(1,1)=="#" then return {},cursor+1,cursor,true end
    local results,seen={},{}
    local startPos,endPos=cursor+1,cursor
    local function Add(token,insert,desc,cat,query)
        if not token or seen[insert] or #results>=32 then return end
        if query and query~="" and not strlower(token.." "..(desc or "")):find(strlower(query),1,true) then return end
        seen[insert]=true
        results[#results+1]={token=token,insertText=insert,desc=ns:CompletionText(desc),cat=ns:CompletionText(cat or "实时"),contextRevision=self.revision,
            displayToken=ns.Syntax:ColorizeLine(token)}
    end
    local function SkillTarget(prefix)
        local owner, slot = Target(snap,prefix,snap.ally)
        local explicit = prefix:match("[%a]+%([^()]*%)%.$") or prefix:match("[%a]+%.$")
        if not explicit and owner==snap.ally and resolveAllySlot then
            local chosen=resolveAllySlot(beforeAll)
            if chosen and snap.pets[owner][chosen] then slot=chosen end
        end
        return owner,slot
    end
    local fn,arg=before:match("([%a_]+)%(([^()]*)$")
    if fn then
        local low=strlower(fn)
        local query=strtrim(arg)
        startPos=cursor-#arg+1
        local close=after:find(")",1,true)
        endPos=close and cursor+close or cursor
        local prefix=before:sub(1,#before-#arg-#fn-1)
        if low=="self" or low=="ally" or low=="enemy" or low=="change" or low=="is" then
            local owner=low=="enemy" and snap.enemy or snap.ally
            if low=="is" then owner=Target(snap,prefix,snap.ally) end
            for order,pet in ipairs(PetsInOrder(snap,owner)) do
                local desc=(pet.slot==snap.active[owner] and L("当前激活 · ") or "").."#"..pet.slot.." "..(pet.name or L("宠物"))..L(" · 物种ID ")..tostring(pet.id or L("不可读"))
                local variants=PetVariants(pet,order==1)
                for _,raw in ipairs(variants) do if raw then Add(fn.."("..raw..")",raw..")",desc,"宠物",query) end end
            end
            if low=="change" then Add("change(next)","next)","下一只存活宠物","换宠",query) end
            return results,startPos,endPos,true
        elseif low=="use" or low=="ability" then
            local owner,slot=SkillTarget(prefix)
            local pet=slot and snap.pets[owner][slot]
            for _,skill in ipairs(pet and pet.skills or {}) do
                local desc="#"..skill.idx.." "..(skill.name or tostring(skill.id))..(skill.usable==true and L(" · 可用") or skill.usable==false and L(" · 暂不可用") or L(" · 状态不可读"))..(skill.cd and (" · CD "..skill.cd) or "")
                for _,raw in ipairs({RawName(skill),"#"..skill.idx}) do Add(fn.."("..raw..")",raw..")",desc,"当前技能",query) end
            end
            return results,startPos,endPos,true
        elseif low=="aura" or low=="buff" or low=="debuff" or low=="weather" then
            local auras
            if low=="weather" then
                local id,_,turns=Read(C_PetBattles.GetAuraInfo,Enum.BattlePetOwner.Weather,PET_BATTLE_PAD_INDEX or 0,1)
                auras=type(id)=="number" and id>0 and {{id=id,name=AbilityName(id),turns=turns}} or {}
            else
                local owner,slot=Target(snap,prefix,snap.enemy)
                auras=self:GetAuras(snap,owner,slot)
            end
            for _,aura in ipairs(auras) do
                local desc=L("当前光环")..(aura.turns and string.format(L(" · 剩余 %d 轮"), aura.turns) or "")
                for _,raw in ipairs({RawName(aura),tostring(aura.id)}) do Add(fn.."("..raw..")",raw..")",desc,L("当前光环"),query) end
            end
            return results,startPos,endPos,true
        end
    end
    -- Complete a round expression, including an existing comparison/value.
    local rs,_,expr,op=strlower(before):find("([%a]+%([^()]*%)%.round)%s*([=<>!~]*)%s*%d*$")
    if not rs then rs,_,expr,op=strlower(before):find("([%a]+%.round)%s*([=<>!~]*)%s*%d*$") end
    if not rs then rs,_,expr,op=strlower(before):find("(round)%s*([=<>!~]*)%s*%d*$") end
    local wordStart,_,word=before:find("([^%s%(%)[%]=<>]+)$")
    if word then
        local negation=word:match("^!+") or ""
        wordStart=wordStart+#negation
        word=word:sub(#negation+1)
    end
    local kw=word and strlower(word) or ""
    local roundKey
    if expr then roundKey=strlower(expr) else
        for _,key in ipairs({"round","self.round","ally.round","enemy.round"}) do
            if kw~="" and kw~="self" and kw~="ally" and kw~="enemy" and key:sub(1,#kw)==kw then roundKey=key;break end
        end
    end
    local condition=before:find("[",1,true) or before:match("^%s*[iI][fF]%s") or before:match("^%s*[eE][lL][sS][eE][iI][fF]%s")
    local function ConditionToken(token)
        if not condition then return "["..token.."]" end
        if before:find("[",1,true) and not after:find("]",1,true) then return token.."]" end
        return token
    end
    if roundKey then
        local value=snap.round
        if roundKey~="round" then
            local owner=roundKey:match("^enemy") and snap.enemy or snap.ally
            value=snap.rounds[owner]
        end
        startPos=lineBase+(rs or wordStart)
        endPos=cursor+#(after:match("^%d*") or "")
        if type(value)=="number" then
            local token=ConditionToken((expr or roundKey).." "..(op and op~="" and op or "=").." "..value)
            Add(token,token,roundKey=="round" and "本轮总回合数" or "当前宠物本次上场轮数","当前轮数")
        end
        return results,startPos,endPos,true
    end
    if not wordStart or kw=="" then return nil end
    startPos=lineBase+wordStart
    endPos=cursor+#(after:match("^[%w_]*") or "")
    -- Replace a completed call when editing the keyword, not its trailing property.
    local oldCall=after:match("^%([^()]*%)")
    if oldCall then endPos=cursor+#oldCall end
    local ownerKey=kw:match("^(enemy)") or kw:match("^(self)") or kw:match("^(ally)")
    if kw=="enemy" or kw=="self" or kw=="ally" then
        local owner=kw=="enemy" and snap.enemy or snap.ally
        for order,pet in ipairs(PetsInOrder(snap,owner)) do
            local variants=PetVariants(pet,order==1)
            for _,raw in ipairs(variants) do
                local hasProperty = after:sub((oldCall and #oldCall or 0)+1):match("^%.")
                local reference = kw.."("..raw..")"
                local token = hasProperty and reference or ConditionToken(reference..".active")
                Add(token,token,(pet.slot==snap.active[owner] and L("当前激活 · ") or "").."#"..pet.slot.." "..(pet.name or L("宠物")),"当前宠物")
            end
        end
        return results,startPos,endPos,true
    end
    if kw=="use" or kw=="ability" or kw:match("%.ability$") then
        local prefix=""
        if kw:match("%.ability$") then
            prefix=kw==".ability" and (before:sub(1,wordStart-1)..".") or kw:sub(1,#kw-#"ability")
        end
        local owner,slot=SkillTarget(prefix)
        local pet=slot and snap.pets[owner][slot]
        for _,skill in ipairs(pet and pet.skills or {}) do
            for _,raw in ipairs({RawName(skill),"#"..skill.idx}) do
                local token=kw.."("..raw..")"
                Add(token,token,"#"..skill.idx.." "..(skill.name or L("技能"))..(skill.usable==true and L(" · 可用") or skill.usable==false and L(" · 暂不可用") or L(" · 状态不可读")),"当前技能")
            end
        end
        return results,startPos,endPos,true
    end
    local auraKey=kw:match("(debuff)$") or kw:match("(aura)$") or kw:match("(buff)$")
    if auraKey then
        local who=ownerKey or "enemy"
        local owner=who=="enemy" and snap.enemy or snap.ally
        local slot=snap.active[owner]
        local base=who.."."..auraKey
        if kw:sub(1,1)=="." then
            owner,slot=Target(snap,before:sub(1,wordStart-1)..".",snap.enemy)
            base="."..auraKey
        end
        local hasProperty=after:sub((oldCall and #oldCall or 0)+1):match("^%.")
        for _,aura in ipairs(self:GetAuras(snap,owner,slot)) do
            local reference=base.."("..RawName(aura)..")"
            local token=hasProperty and reference or ConditionToken(reference..".exists")
            Add(token,token,L("当前光环")..(aura.turns and string.format(L(" · 剩余 %d 轮"), aura.turns) or ""),L("当前光环"))
        end
        return results,startPos,endPos,true
    end
    return nil
end

local watcher=CreateFrame("Frame")
for _,event in ipairs({"PET_BATTLE_OPENING_START","PET_BATTLE_OPENING_DONE","PET_BATTLE_PET_CHANGED",
    "PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE","PET_BATTLE_ABILITY_CHANGED","PET_BATTLE_AURA_APPLIED",
    "PET_BATTLE_AURA_CHANGED","PET_BATTLE_AURA_CANCELED","PET_BATTLE_CLOSE"}) do
    pcall(watcher.RegisterEvent,watcher,event)
end
watcher:SetScript("OnEvent",function(_,event)
    Context.revision=Context.revision+1
    Context.snapshot=nil
    if event=="PET_BATTLE_CLOSE" then
        if ns.AutoCompletePopup then ns.AutoCompletePopup:Hide() end
        return
    end
    if ns.RefreshLiveScriptCompletion and ns.AutoCompletePopup and ns.AutoCompletePopup:IsShown()
        and ns.ScriptEditBox and ns.ScriptEditBox:HasFocus() then ns.RefreshLiveScriptCompletion() end
end)
