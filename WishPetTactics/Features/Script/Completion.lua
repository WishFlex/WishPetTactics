local ADDON_NAME, ns = ...
local Completion={}
ns.ScriptCompletion=Completion
local KEYWORDS={
 {"use","技能","call"},{"ability","技能","call"},{"change","换宠","call"},
 {"self","我方宠物","owner"},{"ally","我方宠物","owner"},{"enemy","敌方宠物","owner"},
 {"round","战斗总轮数","value"},{"end","结束分支"},{"endif","结束分支"},
 {"else","否则分支"},{"elseif","条件分支","space"},{"if","条件分支","space"},
 {"standby","待命"},{"catch","抓宠"},{"trap","抓宠"},{"quit","退出战斗"},
 {"test","调试消息","call"},{"weather","天气","call"},{"then","分支开始"},
 {"true","真"},{"false","假"},
}
local PROPERTIES={
 {"ability","宠物技能","call"},{"aura","光环","call"},{"buff","光环别名","call"},
 {"debuff","光环别名","call"},{"is","指定宠物判断","call"},
 {"round","上场轮数","value"},{"hp","生命值","value"},{"hpp","生命百分比","value"},
 {"id","物种ID","value"},{"level","等级","value"},{"power","攻击","value"},
 {"speed","速度","value"},{"quality","品质","value"},{"type","宠物类型","value"},
 {"count","入场宠物数","value"},{"active","当前激活"},{"dead","阵亡"},
 {"alive","存活"},{"exists","存在"},{"played","已经上场"},
 {"hp.full","满血"},{"hp.high","比对方血量高"},{"hp.low","比对方血量低"},
 {"hp.can_explode","会被对方自爆击杀"},{"hp.explode","可自爆击杀对方"},
 {"level.max","满级"},{"speed.fast","比对方快"},{"speed.slow","比对方慢"},
}
local SPECIAL={
 {"self.hp.can_explode","当前我方会被自爆击杀"},{"enemy.hp.can_explode","当前敌方会被自爆击杀"},
 {"self(#2).hp.explode","我方2号自爆可击杀"},
 {"self.hp.full","当前我方满血"},{"enemy.hp.full","当前敌方满血"},
 {"self.hp.high","我方血量更高"},{"self.hp.low","我方血量更低"},
 {"self.level.max","我方满级"},{"self.speed.fast","我方更快"},{"self.speed.slow","我方更慢"},
}
local TYPES={"人型","龙类","飞行","亡灵","小动物","魔法","元素","野兽","水栖","机械"}
local QUALITY={"弱小","普通","优秀","精良","史诗","传奇"}
local function Safe(v)
 if ns.IsSecretValue and ns:IsSecretValue(v) then return nil end
 return v
end
local function Read(fn,...)
 if not fn then return nil end
 local ok,a,b,c=pcall(fn,...)
 if ok then return Safe(a),Safe(b),Safe(c) end
end
local function Starts(text,prefix) return strlower(text):sub(1,#prefix)==strlower(prefix) end
local function Add(rows,token,insert,desc,cat,extra)
 for _,existing in ipairs(rows) do if existing.token==token and existing.insertText==insert then return end end
 local row={token=token,insertText=insert,desc=ns:CompletionText(desc),cat=ns:CompletionText(cat or "分步补全"),displayToken=ns.Syntax:ColorizeLine(token)}
 for k,v in pairs(extra or {}) do row[k]=v end
 rows[#rows+1]=row
end
local function InCondition(before)
 return before:find("[",1,true) or before:match("^%s*[iI][fF]%s") or before:match("^%s*[eE][lL][sS][eE][iI][fF]%s")
end
local function Wrap(text,before,after)
 if not InCondition(before) then return "["..text.."]",1 end
 if before:find("[",1,true) and not after:find("]",1,true) then return text.."]",0 end
 return text,0
end
local function Resolve(snap,expr)
 expr=expr:gsub("^!+", "")
 local who,arg=expr:match("^([%a]+)%(([^()]*)%)")
 who=who or expr:match("^([%a]+)")
 local owner=who and strlower(who)=="enemy" and snap.enemy or snap.ally
 local slot=snap.active[owner]
 if arg then
  slot=tonumber(arg:match("^#(%d+)$"))
  if not slot then
   local id=tonumber(arg:match(":(%d+)$")) or tonumber(arg)
   local name=strlower(arg:match("^([^:]+)") or arg)
   for i,pet in ipairs(snap.pets[owner] or {}) do
    if (id and id==pet.id) or (pet.name and name==strlower(pet.name)) then slot=i;break end
   end
  end
 end
 return owner,slot
end
local function Values(stage,snap)
 local expr,property=stage.expression,stage.property
 local values={}
 local function Push(value,desc,live)
  if value~=nil then
   for _,item in ipairs(values) do if item.value==tostring(value) then return end end
   values[#values+1]={value=tostring(value),desc=desc,live=live}
  end
 end
 local value
 if snap then
  local owner,slot=Resolve(snap,expr)
  local pet=slot and snap.pets[owner][slot]
  if property=="round" then value=expr=="round" and snap.round or snap.rounds[owner]
  elseif property=="id" then value=pet and pet.id
  elseif property=="count" then value=Read(C_PetBattles.GetNumPets,owner)
  elseif property=="hp" then value=slot and Read(C_PetBattles.GetHealth,owner,slot)
  elseif property=="hpp" then
   local hp=slot and Read(C_PetBattles.GetHealth,owner,slot)
   local max=slot and Read(C_PetBattles.GetMaxHealth,owner,slot)
   if type(hp)=="number" and type(max)=="number" and max>0 then value=hp/max*100 end
  elseif property=="level" then value=slot and Read(C_PetBattles.GetLevel,owner,slot)
  elseif property=="power" then value=slot and Read(C_PetBattles.GetPower,owner,slot)
  elseif property=="speed" then value=slot and Read(C_PetBattles.GetSpeed,owner,slot)
  elseif property=="quality" then value=slot and Read(C_PetBattles.GetBreedQuality,owner,slot)
  elseif property=="type" then
   local arg=expr:match("%.ability%(([^()]*)%)")
   if arg and pet then
    local id=tonumber(arg:match(":(%d+)$")) or tonumber(arg)
    local index=tonumber(arg:match("^#(%d+)$"))
    for _,skill in ipairs(pet.skills) do
     if skill.idx==index or skill.id==id or skill.name==arg then
      local ok,_,_,_,_,_,_,kind=pcall(C_PetBattles.GetAbilityInfo,owner,slot,skill.idx)
      value=ok and Safe(kind) or nil;break
     end
    end
   else value=slot and Read(C_PetBattles.GetPetType,owner,slot) end
  elseif property=="duration" then
   local arg=expr:match("%.ability%(([^()]*)%)")
   if arg and pet then
    local id=tonumber(arg:match(":(%d+)$")) or tonumber(arg)
    local idx=tonumber(arg:match("^#(%d+)$"))
    for _,skill in ipairs(pet.skills) do
     if skill.idx==idx or skill.id==id or skill.name==arg then
      if type(skill.cd)=="number" or type(skill.lockdown)=="number" then value=math.max(skill.cd or 0,type(skill.lockdown)=="number" and skill.lockdown or 0) end
      break
     end
    end
   else
    local auraArg=expr:match("%.aura%(([^()]*)%)") or expr:match("%.buff%(([^()]*)%)") or expr:match("%.debuff%(([^()]*)%)") or expr:match("%.%(([^()]*)%)")
    local weather=expr:match("^weather%(([^()]*)%)")
    if weather then
     local id,_,turns=Read(C_PetBattles.GetAuraInfo,Enum.BattlePetOwner.Weather,PET_BATTLE_PAD_INDEX or 0,1)
     local wanted=tonumber(weather:match(":(%d+)$")) or tonumber(weather)
     local _,currentName=Read(C_PetBattles.GetAbilityInfoByID,id)
     if not currentName then currentName=Read(C_PetJournal and C_PetJournal.GetPetAbilityInfo,id) end
     if id and ((wanted and id==wanted) or (not wanted and type(currentName)=="string" and strlower(currentName)==strlower(weather))) then value=turns end
    elseif auraArg then
     local wanted=tonumber(auraArg:match(":(%d+)$")) or tonumber(auraArg)
     local name=auraArg:match("^([^:]+)") or auraArg
     for _,aura in ipairs(ns.ScriptContext:GetAuras(snap,owner,slot)) do
      if (wanted and aura.id==wanted) or aura.name==name then value=aura.turns;break end
     end
    end
   end
  end
 end
 if type(value)=="number" then
  local label=property=="type" and TYPES[value] or property=="quality" and QUALITY[value]
  Push(string.format("%g",value),ns:CompletionText("当前实际值")..(label and (" · "..ns:CompletionText(label)) or ""),true)
 end
 if property=="type" then for i,name in ipairs(TYPES) do if i~=value then Push(i,name,false) end end
 elseif property=="quality" then for i,name in ipairs(QUALITY) do if i~=value then Push(i,name,false) end end
 else
  for _,v in ipairs(property=="level" and {1,25} or property=="hpp" and {25,50,75,100} or {1,2,3}) do Push(v,"参考数值，可手动输入",false) end
 end
 return values
end

local OPERATORS={
 {"=","等于"},{"~=","不等于"},{"<","小于"},{"<=","小于等于"},
 {">","大于"},{">=","大于等于"},{"~","匹配列表，如 1,3,5"},{"!~","排除列表，如 2,4"},
}
local NUMERIC={round=true,hp=true,hpp=true,id=true,level=true,power=true,speed=true,quality=true,type=true,count=true,duration=true}
local function NumericExpression(text)
 local expr=text:match("([^%s%[%]&|]+)%s*$")
 if not expr then return end
 local property=strlower(expr:match("%.([%a_]+)$") or expr)
 if not NUMERIC[property] or (strlower(expr)~="round" and not expr:find(".",1,true)) then return end
 return expr,property
end
local function ValueRows(stage,query)
 local rows={}
 for _,item in ipairs(Values(stage,ns.ScriptContext:GetSnapshot())) do
  if query=="" or Starts(item.value,query) or item.desc:find(query,1,true) then
   Add(rows,item.value,item.value,item.desc,"数值参数",item.live and {contextRevision=ns.ScriptContext.revision} or nil)
  end
 end
 if stage.operator=="~" or stage.operator=="!~" then
  local list=stage.property=="hpp" and "25,50,75" or "1,3,5"
  if query=="" or Starts(list,query) then Add(rows,list,list,"逗号分隔列表，可继续编辑","列表参数") end
 end
 return rows
end
local function OperatorRows(stage,query,before,after,whole)
 local rows={}
 for _,pair in ipairs(OPERATORS) do
  if query=="" or Starts(pair[1],query) then
   local insert=pair[1].." "
   local offset=#insert
   if whole then
    insert=stage.expression.." "..insert
    offset=#insert
    local wrapped,leading=Wrap(insert,before,after)
    insert=wrapped;offset=offset+leading
   end
   Add(rows,pair[1],insert,pair[2],"比较运算符",{
    cursorOffset=offset,nextStage={kind="value",property=stage.property,expression=stage.expression,operator=pair[1]},
   })
  end
 end
 return rows
end
function Completion:GetNumericSuggestions(clean,cursor)
 local before=clean:sub(1,cursor):match("([^\r\n]*)$") or ""
 local after=clean:sub(cursor+1):match("^[^\r\n]*") or ""
 if before:find("--",1,true) or strtrim(before):sub(1,1)=="#" or after:match("^%.") then return end
 local base,op,query=before:match("^(.-)%s*([=~<>!]+)%s*([%d%,%.%-]*)$")
 if base then
  local expr,property=NumericExpression(base)
  if expr then
   local valid=false
   for _,item in ipairs(OPERATORS) do if item[1]==op then valid=true end end
   if op=="==" or op=="!=" then valid=true end
   if valid then
    local stage={kind="value",property=property,expression=expr,operator=op}
    local first=cursor-#query+1
    return ValueRows(stage,query),first,cursor+#(after:match("^[%d%,%.%-]*") or ""),false
   elseif query=="" then
    local first=cursor-#op+1
    return OperatorRows({expression=expr,property=property},op,before,after,false),first,cursor,false
   end
  end
  return
 end
 local expr,property=NumericExpression(before)
 if expr then
  local first=cursor-#before+#before:gsub("%s+$","")-#expr+1
  -- If a comparison already follows the cursor, retain the normal keyword editor.
  if after:match("^%s*[=~<>!]") then return end
  return OperatorRows({expression=expr,property=property},"",before,after,true),first,cursor,false
 end
end

function Completion:GetSuggestions(clean,cursor,stage,tools)
 tools=tools or {}
 local beforeAll=clean:sub(1,cursor)
 local before=beforeAll:match("([^\r\n]*)$") or ""
 local lineBase=cursor-#before
 local after=clean:sub(cursor+1):match("^[^\r\n]*") or ""
 local rows={}
 if before:find("--",1,true) or strtrim(before):sub(1,1)=="#" then return rows,cursor+1,cursor,false end
 -- Parameter/value popups are entered only by accepting a keyword.
 if stage then
  if cursor<stage.anchor or clean:sub(1,stage.anchor)~=stage.prefix then return self:GetSuggestions(clean,cursor,nil,tools) end
  local query=clean:sub(stage.anchor+1,cursor)
  if query:find("[()%[%]\r\n]") then return self:GetSuggestions(clean,cursor,nil,tools) end
  if stage.kind=="owner" then
   if query~="" or after:sub(1,1)=="." then
    return self:GetSuggestions(clean,cursor,nil,{typed=true})
   end
   Add(rows,".",".",ns:T("当前上场宠物"),"宠物参数",{nextStage={kind="properties"}})
   for i=1,3 do
    local slot="(#"..i..")"
    Add(rows,slot,slot..".",ns:T("宠物槽位"),"宠物参数",{nextStage={kind="properties"}})
   end
   return rows,cursor+1,cursor,true
  elseif stage.kind=="properties" then
   return self:GetSuggestions(clean,cursor,nil,{typed=true})
  elseif stage.kind=="operator" then
   return OperatorRows(stage,strtrim(query),before,after,false),stage.anchor+1,cursor,true
  elseif stage.kind=="arguments" then
   local live,first,last,handled=ns.ScriptContext:GetSuggestions(clean,cursor,tools.resolve)
   if handled then
    for _,item in ipairs(live) do
     local slot=item.insertText:match("^#([123])%)$")
     if slot then Add(rows,"#"..slot,item.insertText,item.desc,"技能 / 宠物参数",{contextRevision=item.contextRevision,slotOrder=tonumber(slot),displayToken="|cff10b981#"..slot.."|r"}) end
    end
    table.sort(rows,function(a,b) return a.slotOrder<b.slotOrder end)
    for _,item in ipairs(live) do
     if not item.insertText:match("^#([123])%)$") then rows[#rows+1]=item end
    end
    -- Slots are the initial choices for skills; enemy/ally keep the active pet first.
    if stage.fn~="use" and stage.fn~="ability" then rows=live end
    if #rows>0 then return rows,first,last,true end
   end
   local first=stage.anchor+1
   local close=after:find(")",1,true)
   local last=close and cursor+close or cursor
   local low=stage.fn
   if low=="use" or low=="ability" then
    local skills
    if tools.collect and Read(C_PetBattles and C_PetBattles.IsInBattle)==false then skills=tools.collect(beforeAll) end
    for i=1,3 do
     if query=="" or Starts("#"..i,query) or tostring(i)==query then
      local skill=skills and skills[i]
      Add(rows,"#"..i,"#"..i..")",skill and skill.skillName or (ns:CompletionText("技能槽").." #"..i),"技能参数",{displayToken="|cff10b981#"..i.."|r"})
     end
    end
   elseif low=="self" or low=="ally" or low=="enemy" or low=="change" or low=="is" then
    for i=1,3 do if query=="" or Starts("#"..i,query) then Add(rows,"#"..i,"#"..i..")","宠物槽位","宠物参数",{displayToken="|cfffb923c#"..i.."|r"}) end end
    if low=="change" and (query=="" or Starts("next",query)) then Add(rows,"next","next)","下一只存活宠物","宠物参数") end
    if low~="enemy" and tools.pets and Read(C_PetBattles and C_PetBattles.IsInBattle)==false then
     for _,pet in ipairs(tools.pets()) do if query=="" or Starts(pet.raw,query) then Add(rows,pet.raw,pet.raw..")",pet.desc,"我方宠物",{displayToken="|cfffb923c"..pet.raw.."|r"}) end end
    end
   elseif low=="test" and query=="" then Add(rows,"Condition met","Condition met)","可自行修改调试消息","消息参数") end
   return rows,first,last,true
  elseif stage.kind=="value" then
   return ValueRows(stage,query),stage.anchor+1,cursor+#(after:match("^[%d%,%.%-]*") or ""),true
  end
 end
 if not tools.typed then return rows,cursor+1,cursor,false end
 local numeric,firstNumeric,lastNumeric,keepNumeric=self:GetNumericSuggestions(clean,cursor)
 if numeric then return numeric,firstNumeric,lastNumeric,keepNumeric end
 -- A normal popup starts only with an alphabetic prefix, never on whitespace or a bare '('.
 local start,_,word=before:find("([%a_][%w_%.]*)$")
 if before:sub(-1) == "." and not word then
  start, word = #before + 1, ""
 end
 if not word or (not word:match("%a$") and before:sub(-1) ~= ".") then return rows,cursor+1,cursor,false end
 local first=lineBase+start
 local last=cursor+#(after:match("^[%w_]*") or "")
 local prefix=before:sub(1,start-1)
 local scope,property=word:match("^(.*)%.([^%.]*)$")
 local list=KEYWORDS
 local qualifier=""
 local query=strlower(word)
 if scope then
  list=PROPERTIES;qualifier=scope..".";query=strlower(property)
 elseif prefix:sub(-1)=="." then list=PROPERTIES end
 local ownerExpr=prefix..qualifier
 if ownerExpr:match("[hH][pP][pP]?%.$") then
  list={{"full","满血"},{"high","血量更高"},{"low","血量更低"},{"can_explode","会被对方自爆击杀"},{"explode","可自爆击杀对方"}}
 elseif ownerExpr:match("speed%.$") then list={{"fast","速度更快"},{"slow","速度更慢"}}
 elseif ownerExpr:match("level%.$") then list={{"max","满级"}}
 elseif ownerExpr:match("%.ability%([^()]*%)%.$") then list={{"usable","技能可用"},{"duration","技能冷却","value"},{"strong","重击"},{"weak","轻击"},{"type","技能属性","value"}}
 elseif ownerExpr:match("%.aura%([^()]*%)%.$") or ownerExpr:match("%.buff%([^()]*%)%.$") or ownerExpr:match("%.debuff%([^()]*%)%.$") or ownerExpr:match("%.%([^()]*%)%.$") or ownerExpr:match("weather%([^()]*%)%.$") then
  list={{"exists","光环存在"},{"duration","光环剩余轮数","value"}}
 end
 for _,item in ipairs(list) do
  local name,desc,kind=item[1],item[2],item[3]
  if Starts(name,query) then
   local token=qualifier..name
   local insert=token
   local nextStage,offset
   local existing=after:match("^%([^()]*%)")
   if kind=="owner" then
    if not existing and after:sub(1,1)~="." then
     offset=#insert
     nextStage={kind="owner"}
    end
   elseif kind=="call" then
    if existing then
     -- Preserve existing arguments when renaming a function; do not chain into them.
     insert=token
    else
     insert=token.."()";offset=#insert-1;nextStage={kind="arguments",fn=name}
    end
   elseif kind=="value" and clean:sub(last+1):match("^%s*[=<>!~]+") then
    insert=token
   elseif kind=="value" then
    local expr=prefix..token
    expr=expr:match("([^%s%[%]&|]+)$") or token
    insert=token.." "
    nextStage={kind="operator",property=name,expression=expr}
    offset=#insert
   elseif kind=="space" then insert=token.." " end
   -- Root condition keywords after an action get a bracket shell, not a complete strategy.
   if prefix:sub(-1)~="." and not InCondition(before)
    and ((not scope and (name=="self" or name=="ally" or name=="enemy" or name=="round" or name=="weather")) or scope)
    and not existing and after:sub(1,1)~="." then
    local wrapped,leading=Wrap(insert,before,after)
    insert=wrapped
    if offset then offset=offset+leading end
   end
   if nextStage and before:find("[",1,true) and not after:find("]",1,true) then insert=insert.."]" end
   Add(rows,token,insert,desc,"命令",{nextStage=nextStage,cursorOffset=offset})
  end
 end
 -- Carefully selected complete expressions remain available as exceptions.
 for _,item in ipairs(SPECIAL) do
  if word ~= "" and before:sub(-1) ~= "." and Starts(item[1],word) then
   local insert=Wrap(item[1],before,after)
   Add(rows,item[1],insert,item[2],"完整表达式",{replaceEnd=cursor+#(after:match("^[^%s%]&|]*") or "")})
  end
 end
 return rows,first,last,false
end

-- A skill picker is a view model; the UI never manufactures IDs or skill names.
function Completion:GetSkillPicker(clean,cursor,tools)
 tools=tools or {}
 if not tools.typed and not tools.stage and not tools.skillActive then return nil end
 local beforeAll=clean:sub(1,cursor)
 local before=beforeAll:match("([^\r\n]*)$") or ""
 local after=clean:sub(cursor+1):match("^[^\r\n]*") or ""
 if before:find("--",1,true) or strtrim(before):sub(1,1)=="#" then return nil end
 local start,_,fn,query=before:find("([%a_]+)%(([^()]*)$")
 local arguments=start~=nil
 if not start then start,_,fn=before:find("([%a_]+)$");query="" end
 if not fn then return nil end
 local low=strlower(fn)
 if low~="use" and low~="ability" then return nil end
 query=strtrim(query)
 if query:find("[%[%]\r\n]") then return nil end
 local prefix=before:sub(1,start-1)
 local last=cursor
 if arguments then
  local close=after:match("^[^()%[%]]*%)")
  if close then last=cursor+#close end
 else
  local existing=after:match("^%([^()]*%)")
  if existing then last=cursor+#existing end
 end
 local model={skills={},replaceStart=cursor-#before+start,replaceEnd=last,key=prefix..fn,fn=fn}
 local snap=ns.ScriptContext:GetSnapshot()
 local skills,revision
 if snap then
  local expr=prefix:match("([%a]+%([^()]*%)%.)$") or prefix:match("([%a]+%.)$")
  local owner,slot
  if expr then owner,slot=Resolve(snap,expr)
  else
   owner=snap.ally
   slot=tools.resolve and tools.resolve(beforeAll) or snap.active[owner]
  end
  local pet=slot and snap.pets[owner][slot]
  skills=pet and pet.skills
  revision=ns.ScriptContext.revision
 elseif tools.collect and Read(C_PetBattles and C_PetBattles.IsInBattle)==false then
  skills=tools.collect(beforeAll)
 end
 for i=1,3 do
  local skill
  for index,item in pairs(skills or {}) do
   if (item.idx or index)==i then skill=item;break end
  end
  local name=skill and (skill.name or skill.skillName)
  local id=skill and (skill.id or skill.skillID)
  if type(name)~="string" or name:find("[():%[%]\r\n|]") then name=nil end
  if type(id)~="number" or id<=0 then id=nil end
  local search="#"..i.." "..(name or "").." "..tostring(id or "")
  if query=="" or strlower(search):find(strlower(query),1,true) then
   local entry={idx=i,name=name,id=id,usable=skill and skill.usable,cd=skill and skill.cd,variants={}}
   local function Variant(raw,desc)
    entry.variants[#entry.variants+1]={token=fn.."("..raw..")",insertText=fn.."("..raw..")",desc=desc,
     replaceStart=model.replaceStart,replaceEnd=model.replaceEnd,contextRevision=revision}
   end
   Variant("#"..i,ns:CompletionText("宠物槽位").." #"..i)
   if name and id then Variant(name..":"..id,name.." · ID "..id) end
   if id then Variant(tostring(id),"ID "..id) end
   model.skills[#model.skills+1]=entry
  end
 end
 if #model.skills==0 then return nil end
 return model
end
