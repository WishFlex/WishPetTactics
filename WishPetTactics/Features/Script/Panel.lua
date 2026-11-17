local ADDON_NAME, ns = ...
local Theme = ns.Theme


-- Runtime drafts belong to team objects, not the current array index or focus.
-- They deliberately do not modify the saved team until the user clicks Save.
local scriptDrafts = setmetatable({}, {__mode = "k"})
function ns:HasScriptDraft(team)
    return team and scriptDrafts[team] ~= nil or false
end
function ns:RecordScriptDraft(editBox)
    local team = editBox and editBox._draftTeam
    if not team or not ns.Syntax then return end
    local text = ns.Syntax:StripColors(editBox:GetText() or "")
    if text == (team.script or "") then
        scriptDrafts[team] = nil
    else
        local draft = scriptDrafts[team] or {base = team.script or ""}
        draft.text = text
        scriptDrafts[team] = draft
    end
end
function ns:SyncScriptEditor(team)
    local box = self.ScriptEditBox
    if not box or not team or not self.Syntax then return end
    local switched = box._draftTeam ~= team
    local draft = scriptDrafts[team]
    if switched or (not draft and not box:HasFocus()) then
        box._draftTeam = team
        self.Syntax:ApplyToEditBox(box, draft and draft.text or team.script or "", 0)
    end
    if self.MainFrame and self.MainFrame.MarkScriptUnsaved then
        self.MainFrame.MarkScriptUnsaved(draft ~= nil)
    end
end

local PURPLE_BORDER = { 0.58, 0.32, 0.96, 1.0 }

local SCRIPT_UI_TEXT = (ns.locale == "zhTW") and {
    catExt        = "擴展",
    catLv         = "練寵",
    catAct        = "動作",
    catDbg        = "除錯",
    catCond       = "條件",
    catStruct     = "結構",
    catRound      = "回合",
    catState      = "狀態",
    catAb         = "技能",
    catAura       = "光環",
    catWeather    = "天氣",
    catStat       = "屬性",
    catSlot       = "槽位",
    catSwap       = "換寵",
    catTarget     = "目標",
    catTeamPet    = "本隊寵",
    catSyntax     = "語法",
    slotPetCatFmt = "%d號寵",
    teamPetFmt    = "%d號槽位寵物 (%s:%d)",
    teamPetIdFmt  = "%d號槽位寵物+ID",
    slotSkillFmt  = "%d號寵%s: %s",
    castSlotFmt   = "施放%d號寵 %s 技能",
    castHashFmt   = "施放 %s 技能",
    petAbIdxFmt   = "%d號寵 #%d 技能",
    noAuraFmt     = "敵方無 %s 時",
    subInfoFmt    = "|cffc084fc當前隊伍:|r |cffffffff%s|r  |cff6b7280(補全槽位: %d號寵)|r",
    savedFmt      = "|cff10b981[已儲存] %s (對戰即時生效)|r",
} or (ns.locale ~= "zhCN") and {
    catExt        = "Ext",
    catLv         = "Level",
    catAct        = "Action",
    catDbg        = "Debug",
    catCond       = "Cond",
    catStruct     = "Block",
    catRound      = "Round",
    catState      = "State",
    catAb         = "Skill",
    catAura       = "Aura",
    catWeather    = "Weather",
    catStat       = "Stat",
    catSlot       = "Slot",
    catSwap       = "Swap",
    catTarget     = "Target",
    catTeamPet    = "Team",
    catSyntax     = "Syntax",
    slotPetCatFmt = "Pet #%d",
    teamPetFmt    = "Slot #%d Pet (%s:%d)",
    teamPetIdFmt  = "Slot #%d Pet+ID",
    slotSkillFmt  = "Pet #%d %s: %s",
    castSlotFmt   = "Cast Pet #%d %s ability",
    castHashFmt   = "Cast %s ability",
    petAbIdxFmt   = "Pet #%d Ability #%d",
    noAuraFmt     = "Enemy missing %s",
    subInfoFmt    = "|cffc084fcTeam:|r |cffffffff%s|r  |cff6b7280(Auto-Complete: Slot #%d)|r",
    savedFmt      = "|cff10b981[Saved] %s (Active immediately)|r",
} or {
    catExt        = "扩展",
    catLv         = "练宠",
    catAct        = "动作",
    catDbg        = "调试",
    catCond       = "条件",
    catStruct     = "结构",
    catRound      = "回合",
    catState      = "状态",
    catAb         = "技能",
    catAura       = "光环",
    catWeather    = "天气",
    catStat       = "属性",
    catSlot       = "槽位",
    catSwap       = "换宠",
    catTarget     = "目标",
    catTeamPet    = "本队宠",
    catSyntax     = "语法",
    slotPetCatFmt = "%d号宠",
    teamPetFmt    = "%d号槽位宠物 (%s:%d)",
    teamPetIdFmt  = "%d号槽位宠物+ID",
    slotSkillFmt  = "%d号宠%s: %s",
    castSlotFmt   = "施放%d号宠 %s 技能",
    castHashFmt   = "施放 %s 技能",
    petAbIdxFmt   = "%d号宠 #%d 技能",
    noAuraFmt     = "敌方无 %s 时",
    subInfoFmt    = "|cffc084fc当前队伍:|r |cffffffff%s|r  |cff6b7280(补全槽位: %d号宠)|r",
    savedFmt      = "|cff10b981[已保存] %s (对战即时生效)|r",
}

local function LDesc(zhCN, zhTW, enUS)
    if ns.locale == "zhTW" then return zhTW end
    if ns.locale ~= "zhCN" then return enUS end
    return zhCN
end

-- ==================== 1. 零分配语法高亮、脱色与纯字节光标双向映射引擎 ====================
ns.Syntax = {}

local COLOR_COMMENT = "|cff6b7280"
local COLOR_KEYWORD = "|cffc084fc"
local COLOR_ACTION  = "|cff38bdf8"
local COLOR_SKILL   = "|cff10b981"
local COLOR_COND    = "|cff60a5fa"
local COLOR_PET     = "|cfffb923c"
local COLOR_AURA    = "|cffe879f9"
local COLOR_PROP    = "|cffc4b5fd"
local COLOR_OPERATOR = "|cff94a3b8"
local COLOR_NUM     = "|cffffb800"
local COLOR_RESET   = "|r"

local function IsHex8Bytes(str, startPos)
    for idx = startPos, startPos + 7 do
        local b = string.byte(str, idx)
        if not b then return false end
        if not ((b >= 48 and b <= 57) or (b >= 65 and b <= 70) or (b >= 97 and b <= 102)) then
            return false
        end
    end
    return true
end

function ns.Syntax:StripColors(text)
    if not text or text == "" then return "" end
    local s = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    s = string.gsub(s, "|r", "")
    return s
end

-- 纯字节扫描：将带颜色码文本中的光标位置 (0-based) 精准转换为纯文本字节位置 (零子串分配)
function ns.Syntax:ColoredCursorToCleanPos(coloredText, coloredCursorPos)
    if not coloredText or coloredText == "" or not coloredCursorPos or coloredCursorPos <= 0 then
        return 0
    end
    local len = #coloredText
    local limit = math.min(len, coloredCursorPos)
    local i = 1
    local cleanCount = 0

    while i <= limit do
        if string.byte(coloredText, i) == 124 then -- '|'
            local nextByte = string.byte(coloredText, i + 1)
            if nextByte == 99 and (i + 9) <= len and IsHex8Bytes(coloredText, i + 2) then -- 'c'
                i = i + 10
            elseif nextByte == 114 then -- 'r'
                i = i + 2
            else
                cleanCount = cleanCount + 1
                i = i + 1
            end
        else
            cleanCount = cleanCount + 1
            i = i + 1
        end
    end
    return cleanCount
end

-- 纯字节扫描：将纯文本字节位置精准还原为着色后文本的光标位置 (零子串分配)
function ns.Syntax:CleanPosToColoredCursor(coloredText, targetCleanPos)
    if not coloredText or coloredText == "" or not targetCleanPos or targetCleanPos <= 0 then
        return 0
    end
    local len = #coloredText
    local i = 1
    local cleanCount = 0

    while i <= len do
        if cleanCount >= targetCleanPos then
            while i <= len and string.byte(coloredText, i) == 124 do
                local nb = string.byte(coloredText, i + 1)
                if nb == 99 and (i + 9) <= len and IsHex8Bytes(coloredText, i + 2) then
                    i = i + 10
                elseif nb == 114 then
                    i = i + 2
                else
                    break
                end
            end
            return i - 1
        end

        if string.byte(coloredText, i) == 124 then
            local nextByte = string.byte(coloredText, i + 1)
            if nextByte == 99 and (i + 9) <= len and IsHex8Bytes(coloredText, i + 2) then
                i = i + 10
            elseif nextByte == 114 then
                i = i + 2
            else
                cleanCount = cleanCount + 1
                i = i + 1
            end
        else
            cleanCount = cleanCount + 1
            i = i + 1
        end
    end
    return len
end

-- Context-aware token coloring. Parentheses carry the semantic category:
-- use(#2) is a skill slot, self(#2) is a pet slot, aura(918) is an aura.
local scriptLinesScratch = {}
local colorParts, colorStack = {}, {}
local CALL_COLORS = {
    use = COLOR_ACTION, ability = COLOR_ACTION, change = COLOR_ACTION, test = COLOR_ACTION,
    self = COLOR_COND, ally = COLOR_COND, enemy = COLOR_COND, is = COLOR_COND,
    aura = COLOR_AURA, buff = COLOR_AURA, debuff = COLOR_AURA, weather = COLOR_AURA,
}
local ARG_COLORS = {
    use = COLOR_SKILL, ability = COLOR_SKILL, change = COLOR_PET,
    self = COLOR_PET, ally = COLOR_PET, enemy = COLOR_PET, is = COLOR_PET,
    aura = COLOR_AURA, buff = COLOR_AURA, debuff = COLOR_AURA, weather = COLOR_AURA,
    test = COLOR_COMMENT,
}
local KEYWORDS = { ["if"]=true, ["elseif"]=true, ["else"]=true, ["then"]=true,
    ["end"]=true, ["endif"]=true, ["and"]=true, ["or"]=true, ["not"]=true }
local ACTIONS = {standby=true, pass=true, trap=true, catch=true, quit=true}
function ns.Syntax:ColorizeLine(rawLine)
    local clean = self:StripColors(rawLine or "")
    local trimmed = strtrim(clean)
    if trimmed:sub(1,2) == "--" or trimmed:sub(1,1) == "#" then
        return COLOR_COMMENT .. clean .. COLOR_RESET
    end
    local i, n, depth, pending = 1, 0, 0, nil
    while i <= #clean do
        local ch = clean:sub(i,i)
        local text, color
        if clean:sub(i,i+1) == "--" then
            text, color = clean:sub(i), COLOR_COMMENT; i = #clean + 1
        elseif ch == "(" then
            depth = depth + 1; colorStack[depth] = (pending and ARG_COLORS[pending]) or (i>1 and clean:sub(i-1,i-1)=="." and COLOR_AURA) or false
            pending = nil; text = ch; i = i + 1
        elseif ch == ")" then
            colorStack[depth] = nil; depth = math.max(0, depth - 1)
            pending = nil; text = ch; i = i + 1
        elseif depth > 0 and colorStack[depth] then
            local stop = clean:find("[()]", i) or (#clean + 1)
            text, color = clean:sub(i,stop-1), colorStack[depth]; i = stop
        elseif ch:match("%s") then
            local stop = clean:find("%S", i) or (#clean + 1)
            text = clean:sub(i, stop-1); i = stop
        elseif ch:match("[%a_]") then
            local stop = i + 1
            while stop <= #clean and clean:sub(stop,stop):match("[%w_]") do stop = stop + 1 end
            text = clean:sub(i,stop-1)
            local low = strlower(text)
            color = KEYWORDS[low] and COLOR_KEYWORD or CALL_COLORS[low]
                or (ACTIONS[low] and COLOR_ACTION) or COLOR_PROP
            local nextToken = clean:find("%S", stop)
            pending = nextToken and clean:byte(nextToken) == 40 and low or nil
            i = stop
        elseif ch:match("%d") or (ch == "#" and clean:sub(i+1,i+1):match("%d")) then
            local stop = i + 1
            while stop <= #clean and clean:sub(stop,stop):match("[%d%.]") do stop = stop + 1 end
            text, color = clean:sub(i,stop-1), ch == "#" and COLOR_PET or COLOR_NUM
            pending = nil; i = stop
        else
            text = ch
            if ch:match("[!&|=<>~%[%]%.:]") then color = COLOR_OPERATOR end
            if not ch:match("%s") then pending = nil end
            i = i + 1
        end
        n = n + 1; colorParts[n] = color and (color .. text .. COLOR_RESET) or text
    end
    local result = table.concat(colorParts, "", 1, n)
    for j = 1, n do colorParts[j] = nil end
    for j = 1, depth do colorStack[j] = nil end
    return result
end

function ns.Syntax:ColorizeScript(rawText)
    if not rawText or rawText == "" then return "" end
    local clean = self:StripColors(rawText)
    clean = string.gsub(clean, "\r\n", "\n")
    wipe(scriptLinesScratch)
    local n = 0
    for line in string.gmatch(clean .. "\n", "(.-)\n") do
        n = n + 1
        scriptLinesScratch[n] = self:ColorizeLine(line)
    end
    local res = table.concat(scriptLinesScratch, "\n", 1, n)
    wipe(scriptLinesScratch)
    return res
end

function ns.Syntax:ApplyToEditBox(editBox, rawText, cleanCursorOffset)
    if not editBox then return end
    editBox._suppressChange = true
    local clean = self:StripColors(rawText or "")
    local colored = editBox._wishAppliedColored
    if editBox._wishAppliedClean ~= clean or not colored or editBox:GetText() ~= colored then
        colored = self:ColorizeScript(clean)
        editBox:SetText(colored)
        editBox._wishAppliedClean, editBox._wishAppliedColored = clean, colored
    end
    if cleanCursorOffset and cleanCursorOffset >= 0 then
        local targetColoredPos = self:CleanPosToColoredCursor(colored, cleanCursorOffset)
        editBox:SetCursorPosition(math.min(#colored, targetColoredPos))
    end
    editBox._suppressChange = false
    if editBox.UpdateLineNumbers then
        editBox:UpdateLineNumbers(clean)
    end
end

-- ==================== 2. 激活槽位智能判定与带缓存的补全词库 ====================
-- 返回当前队伍 3 个槽位的宠物名称与 SpeciesID，供 change() / self() / is() 智能补全
local function GetTeamPetTargetOptions()
    local team = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
    local opts = {}
    for s = 1, 3 do
        local spID = 0
        local spName = nil
        if C_PetBattles and C_PetBattles.IsInBattle() then
            local ally = (Enum and Enum.BattlePetOwner and Enum.BattlePetOwner.Ally) or 1
            spID = C_PetBattles.GetPetSpeciesID(ally, s) or 0
            local cName, origName = C_PetBattles.GetName(ally, s)
            spName = origName or cName
        else
            local petID = C_PetJournal.GetPetLoadOutInfo(s)
            if petID then
                spID, _, _, _, _, _, _, spName = C_PetJournal.GetPetInfoByPetID(petID)
            end
            if (not spID or spID == 0) and team and team.speciesLoadout and team.speciesLoadout[s] and team.speciesLoadout[s] > 0 then
                spID = team.speciesLoadout[s]
                spName = C_PetJournal.GetPetInfoBySpeciesID(spID)
            end
        end
        if spID and spID > 0 and spName and spName ~= "" then
            opts[#opts + 1] = {
                raw      = spName,
                rawLower = strlower(spName),
                desc     = string.format(SCRIPT_UI_TEXT.teamPetFmt, s, spName, spID),
            }
            opts[#opts + 1] = {
                raw      = string.format("%s:%d", spName, spID),
                rawLower = strlower(string.format("%s:%d", spName, spID)),
                desc     = string.format(SCRIPT_UI_TEXT.teamPetIdFmt, s),
            }
        end
    end
    return opts
end

-- 返回 3 个技能 ID 标量，避免每次输入创建临时数组
local function GetSlotActiveThreeAbilities(team, slot)
    if C_PetBattles and C_PetBattles.IsInBattle() then
        local ally = (Enum and Enum.BattlePetOwner and Enum.BattlePetOwner.Ally) or 1
        local b1 = C_PetBattles.GetAbilityInfo(ally, slot, 1) or 0
        local b2 = C_PetBattles.GetAbilityInfo(ally, slot, 2) or 0
        local b3 = C_PetBattles.GetAbilityInfo(ally, slot, 3) or 0
        if b1 > 0 or b2 > 0 or b3 > 0 then
            return b1, b2, b3
        end
    end

    local lvSlot = (team and team.levelingSlot) or (ns.db and ns.db.settings.levelingSlot) or 2
    if team and team.hasLevelingSlot and lvSlot == slot then
        return 0, 0, 0
    end

    local petID, ca1, ca2, ca3 = C_PetJournal.GetPetLoadOutInfo(slot)
    local loadedSpID = (petID and C_PetJournal.GetPetInfoByPetID(petID)) or 0
    local targetSpID = (team and team.speciesLoadout and tonumber(team.speciesLoadout[slot])) or 0

    if not (ns.staging and ns.staging.isDirty) and targetSpID > 0 and loadedSpID ~= targetSpID then
        local savedAbs = team and team.abilities and team.abilities[slot]
        local val = ns.AutoRouting:ValidateAbilitiesForSpecies(targetSpID, savedAbs)
        return val[1] or 0, val[2] or 0, val[3] or 0
    end

    if (ca1 or 0) > 0 or (ca2 or 0) > 0 or (ca3 or 0) > 0 then
        return ca1 or 0, ca2 or 0, ca3 or 0
    end

    if team and team.abilities and team.abilities[slot] then
        local spID = (targetSpID > 0) and targetSpID or loadedSpID
        if spID > 0 then
            local val = ns.AutoRouting:ValidateAbilitiesForSpecies(spID, team.abilities[slot])
            return val[1] or 0, val[2] or 0, val[3] or 0
        end
        local tAbs = team.abilities[slot]
        return tAbs[1] or 0, tAbs[2] or 0, tAbs[3] or 0
    end

    return 0, 0, 0
end

local slotStackScratch = {}

local function ResolveActivePetSlotForEditor(cleanBeforeCursor)
    local battleActiveSlot = nil
    if C_PetBattles and C_PetBattles.IsInBattle() then
        local ally = (Enum and Enum.BattlePetOwner and Enum.BattlePetOwner.Ally) or 1
        local act = C_PetBattles.GetActivePet(ally)
        if act and act >= 1 and act <= 3 then
            battleActiveSlot = act
        end
    end

    if cleanBeforeCursor and cleanBeforeCursor ~= "" then
        local lastLine = string.match(cleanBeforeCursor, "([^\r\n]*)$") or ""
        local inlineSlot = string.match(lastLine, "[sS][eE][lL][fF]%s*%(%s*#?(%d)%s*%)%s*%.%s*active")
            or string.match(lastLine, "[aA][lL][lL][yY]%s*%(%s*#?(%d)%s*%)%s*%.%s*active")
        if inlineSlot then
            local n = tonumber(inlineSlot)
            if n and n >= 1 and n <= 3 then return n end
        end

        local depth = 0
        for rawLine in string.gmatch(cleanBeforeCursor .. "\n", "(.-)\n") do
            local line = strtrim(rawLine)
            local cPos = string.find(line, "--", 1, true)
            if cPos then line = strtrim(string.sub(line, 1, cPos - 1)) end
            if line ~= "" and string.byte(line, 1) ~= 35 then -- '#'
                local fw = strlower(string.match(line, "^([a-zA-Z_]+)") or "")
                if fw == "if" then
                    local sNum = string.match(line, "[sS][eE][lL][fF]%s*%(%s*#?(%d)%s*%)%s*%.%s*active")
                        or string.match(line, "[aA][lL][lL][yY]%s*%(%s*#?(%d)%s*%)%s*%.%s*active")
                    depth = depth + 1
                    slotStackScratch[depth] = tonumber(sNum) or false
                elseif fw == "elseif" then
                    if depth > 0 then
                        local sNum = string.match(line, "[sS][eE][lL][fF]%s*%(%s*#?(%d)%s*%)%s*%.%s*active")
                            or string.match(line, "[aA][lL][lL][yY]%s*%(%s*#?(%d)%s*%)%s*%.%s*active")
                        slotStackScratch[depth] = tonumber(sNum) or false
                    end
                elseif fw == "else" then
                    if depth > 0 then
                        slotStackScratch[depth] = false
                    end
                elseif fw == "end" or fw == "endif" then
                    if depth > 0 then
                        slotStackScratch[depth] = nil
                        depth = depth - 1
                    end
                end
            end
        end

        for i = depth, 1, -1 do
            local s = slotStackScratch[i]
            slotStackScratch[i] = nil
            if s and s >= 1 and s <= 3 then
                for k = 1, i - 1 do slotStackScratch[k] = nil end
                return s
            end
        end
    end

    if battleActiveSlot then
        return battleActiveSlot
    end

    local selSlot = ns.db and tonumber(ns.db.activeTargetSlot)
    if selSlot and selSlot >= 1 and selSlot <= 3 then
        return selSlot
    end
    return 1
end

-- Battle-outside skill labels for the parameter picker; only three cached rows.
local cachedSugSlot, cachedSugA1, cachedSugA2, cachedSugA3
local cachedRawSkills = {}
local function CollectActivePetSuggestions(cleanBeforeCursor)
    local slot = ResolveActivePetSlotForEditor(cleanBeforeCursor)
    local team = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
    local a1,a2,a3 = GetSlotActiveThreeAbilities(team,slot)
    if slot==cachedSugSlot and a1==cachedSugA1 and a2==cachedSugA2 and a3==cachedSugA3 then return cachedRawSkills end
    wipe(cachedRawSkills)
    for idx=1,3 do
        local id=(idx==1 and a1) or (idx==2 and a2) or a3
        if id>0 then
            local name=(C_PetBattles and C_PetBattles.GetAbilityInfoByID and select(2,C_PetBattles.GetAbilityInfoByID(id)))
                or C_PetJournal.GetPetAbilityInfo(id)
            if name then cachedRawSkills[idx]={skillName=name,skillID=id} end
        end
    end
    cachedSugSlot,cachedSugA1,cachedSugA2,cachedSugA3=slot,a1,a2,a3
    return cachedRawSkills
end

-- ==================== 3. 脚本语法错误提示条 ====================
function ns:ShowScriptBugFrame(errMsg, errLineNum, errLineCode)
    if not ns.ScriptWorkspaceModal then return end
    local bugBar = ns.ScriptWorkspaceModal.bugBar
    if not bugBar then return end
    bugBar._errLineNum = tonumber(errLineNum)
    local jumpHint = bugBar._errLineNum and ("  |cff9ca3af(" .. ns:TF("点击跳转到第 %d 行", bugBar._errLineNum) .. ")|r") or ""
    bugBar.errTxt:SetText(string.format("|cffff4d4d%s|r %s%s", ns:T("[语法校验未通过]"), tostring(errMsg or ns:T("未知语法错误")), jumpHint))
    bugBar.codeTxt:SetText(errLineCode and errLineCode ~= "" and (ns:T("问题代码: ") .. "|cffffd000" .. strtrim(errLineCode) .. "|r") or "")
    bugBar:Show()
end

function ns:HideScriptBugFrame()
    if ns.ScriptWorkspaceModal and ns.ScriptWorkspaceModal.bugBar then
        ns.ScriptWorkspaceModal.bugBar:Hide()
    end
end

-- ==================== 4. 对战脚本配置独立工作台（首次打开时惰性创建） ====================
function ns:CreateScriptWorkspaceModal()
    if ns.ScriptWorkspaceModal then return ns.ScriptWorkspaceModal end

    local px = Theme:GetPixelScale()

    local m = CreateFrame("Frame", "WishPetTacticsScriptWorkspaceModal", UIParent, "BackdropTemplate")
    m:SetSize(740, 500)
    m:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetFrameLevel(500)
    m:SetToplevel(true)
    m:SetMovable(true)
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    m:SetScript("OnDragStart", m.StartMoving)
    m:SetScript("OnDragStop", m.StopMovingOrSizing)
    Theme:ApplyBackdrop(m, Theme.Colors.bgMain, Theme.Colors.border, false)
    if ns.MakeModal then ns:MakeModal(m) end

    m:HookScript("OnShow", function(self)
        self:SetFrameStrata("FULLSCREEN_DIALOG")
        self:SetFrameLevel(500)
        if ns.RefreshModalBlocker then
            ns:RefreshModalBlocker()
        end
        if ns.TeamBuilderModal and ns.TeamBuilderModal:IsShown() then
            ns.TeamBuilderModal:Hide()
        end
        if ns.PetPickerModal and ns.PetPickerModal:IsShown() then
            ns.PetPickerModal:Hide()
        end
        if ns.AutoCompletePopup then
            ns.AutoCompletePopup:SetFrameStrata("TOOLTIP")
            ns.AutoCompletePopup:SetFrameLevel(650)
        end
    end)

    m:HookScript("OnHide", function()
        if ns.AutoCompletePopup then ns.AutoCompletePopup:Hide() end
    end)

    m:Hide()

    local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 24, -20)
    Theme:HookLocalizedFontString(title)
    title:SetText(ns:T("|cffc084fcBATTLE SCRIPT ENGINE // 独立对战脚本编辑工作台|r"))
    m.title = title

    local closeBtn = Theme:CreateCloseIconButton(m, function()
        if ns.ScriptEditBox then ns.ScriptEditBox:ClearFocus() end
        if ns.AutoCompletePopup then ns.AutoCompletePopup:Hide() end
        m:Hide()
    end)
    closeBtn:SetPoint("TOPRIGHT", -22, -22)

    local subInfo = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subInfo:SetPoint("RIGHT", closeBtn, "LEFT", -12, 0)
    Theme:HookLocalizedFontString(subInfo)
    m.subInfo = subInfo

    local hdrLine = m:CreateTexture(nil, "BORDER")
    hdrLine:SetHeight(px)
    hdrLine:SetPoint("TOPLEFT", 24, -52)
    hdrLine:SetPoint("TOPRIGHT", -24, -52)
    hdrLine:SetTexture("Interface\\Buttons\\WHITE8X8")
    hdrLine:SetVertexColor(unpack(Theme.Colors.divider))

    local editorBox = CreateFrame("Frame", nil, m, "BackdropTemplate")
    editorBox:SetPoint("TOPLEFT", 24, -64)
    editorBox:SetPoint("BOTTOMRIGHT", -24, 56)
    editorBox:SetClipsChildren(true)
    Theme:ApplyBackdrop(editorBox, { 0.053, 0.053, 0.053, 0.98 }, Theme.Colors.border, false)
    m.editorBox = editorBox

    local gutter = CreateFrame("Frame", nil, editorBox, "BackdropTemplate")
    gutter:SetWidth(36)
    gutter:SetPoint("TOPLEFT", 0, 0)
    gutter:SetPoint("BOTTOMLEFT", 0, 0)
    Theme:ApplyBackdrop(gutter, { 0.08, 0.08, 0.08, 0.98 }, Theme.Colors.border, false)

    local lineNumTxt = gutter:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    lineNumTxt:SetPoint("TOPRIGHT", -6, -10)
    lineNumTxt:SetJustifyH("RIGHT")
    lineNumTxt:SetJustifyV("TOP")
    lineNumTxt:SetTextColor(0.38, 0.45, 0.58, 0.9)
    lineNumTxt:SetText("1")

    local scrollFrame = CreateFrame("ScrollFrame", "WishPetTacticsScriptScrollFrame", editorBox)
    scrollFrame:SetPoint("TOPLEFT", 44, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -18, 10)
    scrollFrame:EnableMouseWheel(true)
    m.scrollFrame = scrollFrame

    local editBox = CreateFrame("EditBox", "WishPetTacticsScriptEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(610)
    editBox:SetAutoFocus(false)
    editBox:EnableKeyboard(true)
    scrollFrame:SetScrollChild(editBox)
    editBox._lastLineCount = 1
    ns.ScriptEditBox = editBox

    editBox:SetScript("OnEditFocusGained", function(self)

        if ns.BattleHUD and ns.BattleHUD.driverBtn and not InCombatLockdown() then
            ClearOverrideBindings(ns.BattleHUD.driverBtn)
        end
    end)

    local lineNumScratch = {}
    function editBox:UpdateLineNumbers(cleanStr)
        local text = cleanStr or ns.Syntax:StripColors(self:GetText() or "")
        local _, nlCount = string.gsub(text, "\n", "\n")
        local count = math.max(1, (nlCount or 0) + 1)
        if self._lastLineCount == count then return end
        self._lastLineCount = count

        for i = 1, count do
            lineNumScratch[i] = tostring(i)
        end
        lineNumTxt:SetText(table.concat(lineNumScratch, "\n", 1, count))
    end

    editorBox:EnableMouse(true)
    editorBox:SetScript("OnMouseDown", function() editBox:SetFocus() end)
    scrollFrame:EnableMouse(true)
    scrollFrame:SetScript("OnMouseDown", function() editBox:SetFocus() end)

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        self:UpdateScrollChildRect()
        local maxScroll = math.max(0, self:GetVerticalScrollRange())
        local nextScroll = math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 28))
        self:SetVerticalScroll(nextScroll)
        lineNumTxt:SetPoint("TOPRIGHT", -6, -10 + nextScroll)
    end)

    local bugBar = CreateFrame("Frame", nil, editorBox, "BackdropTemplate")
    bugBar:SetPoint("BOTTOMLEFT", 40, 4)
    bugBar:SetPoint("BOTTOMRIGHT", -6, 4)
    bugBar:SetHeight(44)
    bugBar:SetFrameLevel(editBox:GetFrameLevel() + 8)
    bugBar:EnableMouse(true)
    Theme:ApplyBackdrop(bugBar, { 0.22, 0.05, 0.08, 0.96 }, { 0.95, 0.25, 0.25, 1 }, false)
    bugBar:SetScript("OnMouseDown", function(self)
        local targetLine = tonumber(self._errLineNum)
        if not targetLine or targetLine < 1 then return end
        local raw = editBox:GetText() or ""
        local clean = ns.Syntax:StripColors(raw)
        local pos, curLine = 0, 1
        while curLine < targetLine do
            local nl = string.find(clean, "\n", pos + 1, true)
            if not nl then break end
            pos = nl
            curLine = curLine + 1
        end
        editBox:SetFocus()
        local coloredPos = ns.Syntax:CleanPosToColoredCursor(raw, pos)
        editBox:SetCursorPosition(math.min(#raw, coloredPos))
    end)
    bugBar:Hide()
    m.bugBar = bugBar

    bugBar.errTxt = bugBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bugBar.errTxt:SetPoint("TOPLEFT", 10, -6)
    bugBar.errTxt:SetPoint("TOPRIGHT", -10, -6)
    bugBar.errTxt:SetJustifyH("LEFT")
    Theme:HookLocalizedFontString(bugBar.errTxt)

    bugBar.codeTxt = bugBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    bugBar.codeTxt:SetPoint("BOTTOMLEFT", 10, 6)
    bugBar.codeTxt:SetJustifyH("LEFT")
    Theme:HookLocalizedFontString(bugBar.codeTxt)

    -- ==================== 5. 宽屏防重叠自动补全弹窗（静态行回调 + 单帧合并触发） ====================
    local acPopup = CreateFrame("Frame", "WishPetTacticsAutoCompletePopup", m, "BackdropTemplate")
    acPopup:SetSize(610, 224)
    acPopup:SetPoint("BOTTOMLEFT", editorBox, "BOTTOMLEFT", 42, 10)
    acPopup:SetFrameStrata("TOOLTIP")
    acPopup:SetFrameLevel(650)
    acPopup:SetToplevel(true)
    acPopup:SetClampedToScreen(true)
    acPopup:EnableMouse(true)
    Theme:ApplyBackdrop(acPopup, Theme.Colors.bgPopup, Theme.Colors.border, false)
    acPopup:Hide()
    ns.AutoCompletePopup = acPopup

    acPopup.matches = {}
    acPopup.selIdx = 1
    acPopup.offset = 0
    acPopup.replaceStart = 1
    acPopup.replaceEnd = 0
    acPopup.rows = {}
    acPopup.keywordRequested = false

    local function AcceptAutoCompleteItem(idx)
        local item = acPopup.skillMode and acPopup.skillPicker:GetSelectedItem()
            or acPopup.matches[idx or acPopup.selIdx]
        if not item then
            acPopup:Hide()
            return
        end
        if item.contextRevision and ns.ScriptContext and item.contextRevision ~= ns.ScriptContext.revision then
            if ns.RefreshLiveScriptCompletion then ns.RefreshLiveScriptCompletion() end
            return
        end
        local raw = ns.Syntax:StripColors(editBox:GetText() or "")
        local sPos = math.max(1, item.replaceStart or acPopup.replaceStart or 1)
        local ePos = math.max(sPos - 1, item.replaceEnd or acPopup.replaceEnd or 0)
        local insertStr = item.insertText or item.token

        local beforeStr = string.sub(raw, 1, sPos - 1)
        local afterStr  = string.sub(raw, ePos + 1)
        local newRaw    = beforeStr .. insertStr .. afterStr
        local newCleanCursor = (sPos - 1) + (item.cursorOffset or #insertStr)

        acPopup:Hide()
        ns.Syntax:ApplyToEditBox(editBox, newRaw, newCleanCursor)
        editBox:SetFocus()
        acPopup.keywordRequested = false
        acPopup.stage = item.nextStage
        if acPopup.stage then
            acPopup.stage.anchor = newCleanCursor
            acPopup.stage.prefix = newRaw:sub(1,newCleanCursor)
            if ns.RefreshLiveScriptCompletion then ns.RefreshLiveScriptCompletion() end
        end
        ns:RecordScriptDraft(editBox)
        if ns.MainFrame and ns.MainFrame.MarkScriptUnsaved then
            ns.MainFrame.MarkScriptUnsaved(ns:HasScriptDraft(editBox._draftTeam))
        end
    end

    acPopup.skillPicker = ns:CreateScriptSkillPicker(acPopup, function()
        AcceptAutoCompleteItem()
    end, function() editBox:SetFocus() end)

    local MAX_AC_ROWS = 8
    for i = 1, MAX_AC_ROWS do
        local r = Theme:CreateMenuRow(acPopup, 602, 24, "")
        r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 25)
        r.rowIdx = i

        r.descTxt = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.descTxt:SetPoint("RIGHT", r, "RIGHT", -10, 0)
        r.descTxt:SetWidth(215)
        r.descTxt:SetJustifyH("RIGHT")
        r.descTxt:SetWordWrap(false)
        Theme:HookLocalizedFontString(r.descTxt)

        r.text:ClearAllPoints()
        r.text:SetPoint("LEFT", r, "LEFT", 10, 0)
        r.text:SetPoint("RIGHT", r.descTxt, "LEFT", -14, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)

        r:SetScript("OnClick", function(selfBtn)
            AcceptAutoCompleteItem((acPopup.offset or 0) + selfBtn.rowIdx)
        end)

        acPopup.rows[i] = r
    end

    local tipRow = acPopup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tipRow:SetPoint("BOTTOMLEFT", 10, 5)
    Theme:HookLocalizedFontString(tipRow)
    tipRow:SetText(ns:T("|cff9ca3af输入首字母选命令 → 选参数  |  ↑↓ 选择  |  Tab / Enter / 左键插入|r"))

    function acPopup:RefreshUI()
        if self.skillMode then
            for _, row in ipairs(self.rows) do row:Hide() end
            tipRow:Hide()
            self:SetSize(650, 180)
            self._lastH = nil
            self.skillPicker:Show()
            self:Show()
            return
        end
        self.skillPicker:Hide()
        tipRow:Show()
        self:SetWidth(610)
        local count = math.min(MAX_AC_ROWS, #self.matches)
        if count == 0 then
            self:Hide()
            return
        end
        self:SetFrameStrata("TOOLTIP")
        self:SetFrameLevel(math.max(650, (m:GetFrameLevel() or 500) + 80))
        local targetH = count * 25 + 24
        if self._lastH ~= targetH then
            self._lastH = targetH
            self:SetHeight(targetH)
        end

        for i = 1, MAX_AC_ROWS do
            local r = self.rows[i]
            local mItem = self.matches[(self.offset or 0) + i]
            if mItem then
                r:Show()
                r:SetSelected((self.offset or 0) + i == self.selIdx)
                local coloredCode = mItem.displayToken or ns.Syntax:ColorizeLine(mItem.token or "")
                r.text:SetText(coloredCode)
                r.descTxt:SetText(string.format("|cff6b7280[%s] %s|r", mItem.cat or SCRIPT_UI_TEXT.catSyntax, mItem.desc or ""))
            else
                r:Hide()
            end
        end
        self:Show()
    end

    acPopup:EnableMouseWheel(true)
    acPopup:SetScript("OnMouseWheel", function(self, delta)
        if self.skillMode then
            self.skillPicker:Move(delta > 0 and -1 or 1)
            return
        end
        self.offset = math.max(0, math.min((self.offset or 0) - delta, math.max(0,#self.matches-MAX_AC_ROWS)))
        self.selIdx = self.offset + 1
        self:RefreshUI()
    end)

    local function UpdateAutoCompleteFromCursor()
        if not editBox:HasFocus() then
            acPopup:Hide()
            return
        end

        local rawColored = editBox:GetText() or ""
        local clean = ns.Syntax:StripColors(rawColored)
        if clean == "" then
            acPopup:Hide()
            return
        end

        local coloredCursor = editBox:GetCursorPosition() or #rawColored
        local cursorCleanPos = ns.Syntax:ColoredCursorToCleanPos(rawColored, coloredCursor)
        cursorCleanPos = math.max(0, math.min(#clean, cursorCleanPos))

        local lineStart = 1
        for i = cursorCleanPos, 1, -1 do
            local b = string.byte(clean, i)
            if b == 10 or b == 13 then
                lineStart = i + 1
                break
            end
        end

        local lineEnd = #clean
        for i = cursorCleanPos + 1, #clean do
            local b = string.byte(clean, i)
            if b == 10 or b == 13 then
                lineEnd = i - 1
                break
            end
        end

        local cleanBeforeCursor = string.sub(clean, 1, cursorCleanPos)
        local lineBeforeCursor  = string.sub(clean, lineStart, cursorCleanPos)
        local lineAfterCursor   = string.sub(clean, cursorCleanPos + 1, lineEnd)

        if string.find(lineBeforeCursor, "%-%-") or string.find(strtrim(lineBeforeCursor), "^#") then
            acPopup:Hide()
            return
        end

        local skillModel = ns.ScriptCompletion:GetSkillPicker(clean, cursorCleanPos, {
            typed=acPopup.keywordRequested, stage=acPopup.stage,
            skillActive=acPopup.skillMode and acPopup:IsShown(),
            resolve=ResolveActivePetSlotForEditor, collect=CollectActivePetSuggestions,
        })
        local wasSkillMode = acPopup.skillMode and acPopup:IsShown()
        acPopup.skillMode = skillModel ~= nil
        if skillModel then
            if not wasSkillMode then acPopup.skillPicker.model = nil end
            acPopup.skillPicker:SetModel(skillModel)
            acPopup.replaceStart, acPopup.replaceEnd = skillModel.replaceStart, skillModel.replaceEnd
            acPopup:RefreshUI()
            return
        end

        local matches, first, last, keepStage = ns.ScriptCompletion:GetSuggestions(clean, cursorCleanPos, acPopup.stage, {
            typed=acPopup.keywordRequested,
            resolve=ResolveActivePetSlotForEditor,
            collect=CollectActivePetSuggestions,
            pets=GetTeamPetTargetOptions,
        })
        if not keepStage then acPopup.stage = nil end
        wipe(acPopup.matches)
        for i,item in ipairs(matches) do acPopup.matches[i]=item end
        acPopup.replaceStart,acPopup.replaceEnd=first,last
        acPopup.selIdx=1
        acPopup.offset=0
        acPopup:RefreshUI()
    end

    -- 单帧合并防抖调度器，彻底消除 OnChar + OnTextChanged 双倍重复计算
    local acUpdatePending = false
    local function RunQueuedAutoComplete()
        acUpdatePending = false
        UpdateAutoCompleteFromCursor()
    end
    local function QueueAutoCompleteUpdate()
        if not acUpdatePending then
            acUpdatePending = true
            C_Timer.After(0, RunQueuedAutoComplete)
        end
    end

    ns.RefreshLiveScriptCompletion = QueueAutoCompleteUpdate

    editBox:SetScript("OnTextChanged", function(self, userInput)
        if self._suppressChange then return end
        local clean = ns.Syntax:StripColors(self:GetText() or "")
        self:UpdateLineNumbers(clean)
        if userInput then
            ns:RecordScriptDraft(self)
            if ns.MainFrame and ns.MainFrame.MarkScriptUnsaved then
                ns.MainFrame.MarkScriptUnsaved(ns:HasScriptDraft(self._draftTeam))
            end
            ns:HideScriptBugFrame()
            local pos = ns.Syntax:ColoredCursorToCleanPos(self:GetText() or "", self:GetCursorPosition() or 0)
            acPopup.keywordRequested = clean:sub(pos,pos):match("[%a%d%.%(=~<>!%,%s]") ~= nil
            QueueAutoCompleteUpdate()
        end
    end)

    editBox:SetScript("OnMouseUp", function()
        acPopup.keywordRequested = false
        acPopup.stage = nil
        acPopup:Hide()
    end)

    editBox:SetScript("OnKeyDown", function(self, key)

        if not acPopup:IsShown() then return end
        if acPopup.skillMode then
            if key == "DOWN" or key == "UP" then
                acPopup.skillPicker:Move(key == "DOWN" and 1 or -1)
            elseif key == "LEFT" or key == "RIGHT" then
                acPopup.skillPicker:ChangeColumn(key == "RIGHT" and 1 or -1)
            end
            return
        end
        if #acPopup.matches == 0 then return end
        if key == "DOWN" then
            acPopup.selIdx = (acPopup.selIdx % #acPopup.matches) + 1
            if acPopup.selIdx > (acPopup.offset or 0)+MAX_AC_ROWS then acPopup.offset=acPopup.selIdx-MAX_AC_ROWS end
            if acPopup.selIdx <= (acPopup.offset or 0) then acPopup.offset=acPopup.selIdx-1 end
            acPopup:RefreshUI()
        elseif key == "UP" then
            local maxCount = #acPopup.matches
            acPopup.selIdx = ((acPopup.selIdx - 2 + maxCount) % maxCount) + 1
            if acPopup.selIdx > (acPopup.offset or 0)+MAX_AC_ROWS then acPopup.offset=acPopup.selIdx-MAX_AC_ROWS end
            if acPopup.selIdx <= (acPopup.offset or 0) then acPopup.offset=acPopup.selIdx-1 end
            acPopup:RefreshUI()
        elseif key == "LEFT" or key == "RIGHT" then
            acPopup.keywordRequested = false
            acPopup.stage = nil
            acPopup:Hide()
        end
    end)

    editBox:SetScript("OnTabPressed", function(self)
        if acPopup:IsShown() and (acPopup.skillMode or #acPopup.matches > 0) then
            AcceptAutoCompleteItem(acPopup.selIdx)
        else
            self:Insert("    ")
        end
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        if acPopup:IsShown() and (acPopup.skillMode or #acPopup.matches > 0) then
            AcceptAutoCompleteItem(acPopup.selIdx)
        else
            self:Insert("\n")
        end
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        acPopup.keywordRequested = false
        acPopup.stage = nil
        if acPopup:IsShown() then
            acPopup:Hide()
        else
            self:ClearFocus()
        end
    end)

    local function OnEditFocusLostDeferred()
        if acPopup and not editBox:HasFocus() then
            acPopup:Hide()
        end
        if ns.ApplyBattleHotKeyBinding then
            ns:ApplyBattleHotKeyBinding()
        end
    end

    editBox:SetScript("OnEditFocusLost", function()
        C_Timer.After(0.15, OnEditFocusLostDeferred)
        local rawColored = editBox:GetText() or ""
        local curClean = ns.Syntax:ColoredCursorToCleanPos(rawColored, editBox:GetCursorPosition() or 0)
        local raw = ns.Syntax:StripColors(rawColored)
        ns.Syntax:ApplyToEditBox(editBox, raw, curClean)
    end)

    local checkBtn = Theme:CreateActionButton(m, 118, 30, "校验", "validate", nil)
    checkBtn:SetPoint("BOTTOMLEFT", 24, 14)
    checkBtn:HookScript("OnEnter", function(self)
        ns:ShowCustomTooltip(self, "ANCHOR_TOP",
            ns:T("校验脚本并更新语法着色"),
            COLOR_ACTION..ns:T("命令").."|r  "..COLOR_SKILL..ns:T("技能及技能槽").."|r  "..COLOR_PET..ns:T("宠物编号 / 名称 / 物种 ID").."|r",
            COLOR_AURA..ns:T("光环").."|r  "..COLOR_NUM..ns:T("回合等数值").."|r  "..COLOR_KEYWORD..ns:T("分支与逻辑关键字").."|r"
        )
    end)
    checkBtn:HookScript("OnLeave", function(self) ns:HideCustomTooltip(self) end)
    checkBtn:SetScript("OnClick", function()
        local rawColored = editBox:GetText() or ""
        local curClean = ns.Syntax:ColoredCursorToCleanPos(rawColored, editBox:GetCursorPosition() or 0)
        local raw = ns.Syntax:StripColors(rawColored)
        ns.Syntax:ApplyToEditBox(editBox, raw, curClean)
        local ok, errMsg, errLine, errCode = ns.ScriptEngine:ValidateScript(raw)
        if ok then
            ns:HideScriptBugFrame()
            m.subInfo:SetText(ns:T("|cff10b981[通过] 脚本语法校验通过|r"))
        else
            ns:ShowScriptBugFrame(errMsg, errLine, errCode)
            m.subInfo:SetText(ns:T("|cffff4d4d[错误] 发现语法错误|r"))
        end
    end)

    local importScriptBtn = Theme:CreateActionButton(m, 110, 30, "导入", "import", "粘贴并导入对战脚本")
    importScriptBtn:SetPoint("LEFT", checkBtn, "RIGHT", 8, 0)
    importScriptBtn:SetScript("OnClick", function()
        ns:ShowImportModal("SCRIPT")
    end)
    m.importScriptBtn = importScriptBtn

    local exportScriptBtn = Theme:CreateActionButton(m, 110, 30, "导出", "export", "导出队伍或当前对战脚本")
    exportScriptBtn:SetPoint("LEFT", importScriptBtn, "RIGHT", 8, 0)
    exportScriptBtn:SetScript("OnClick", function()
        local rawColored = editBox:GetText() or ""
        local cleanLive = ns.Syntax and strtrim(ns.Syntax:StripColors(rawColored)) or strtrim(rawColored)
        local curTeam = editBox._draftTeam or (ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx])
        ns:ShowExportChoiceModal({
            fromScriptEditor = true,
            liveScript = cleanLive,
            team = curTeam,
        })
    end)
    m.exportScriptBtn = exportScriptBtn

    local discardScriptBtn = Theme:CreateActionButton(m, 106, 30, ns:UXText("discardDraft"), "clear")
    discardScriptBtn:SetPoint("LEFT", exportScriptBtn, "RIGHT", 8, 0)
    discardScriptBtn:SetScript("OnClick", function()
        local team = editBox._draftTeam
        if not team or not scriptDrafts[team] then return end
        if StaticPopupDialogs and StaticPopup_Show then
            StaticPopupDialogs.WPT_DISCARD_SCRIPT_DRAFT = {
                text = ns:UXText("discardDraftPrompt"), button1 = YES, button2 = NO,
                timeout = 0, whileDead = true, hideOnEscape = true,
                OnAccept = function(_, capturedTeam)
                    if not capturedTeam then return end
                    scriptDrafts[capturedTeam] = nil
                    if editBox._draftTeam == capturedTeam then
                        ns.Syntax:ApplyToEditBox(editBox, capturedTeam.script or "", 0)
                        if ns.MainFrame and ns.MainFrame.MarkScriptUnsaved then ns.MainFrame.MarkScriptUnsaved(false) end
                    end
                end,
            }
            StaticPopup_Show("WPT_DISCARD_SCRIPT_DRAFT", nil, nil, team)
        end
    end)

    local initUnsaved = ns._scriptUnsavedState and true or false
    local saveScriptBtn = Theme:CreateActionButton(m, 136, 30, initUnsaved and "* 保存" or "保存", "save", "保存脚本到当前队伍", "PRIMARY")
    saveScriptBtn:SetPoint("BOTTOMRIGHT", -24, 14)
    saveScriptBtn:SetScript("OnClick", function()
        local team = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
        if not team then return end
        if editBox._draftTeam ~= team then
            ns:SyncScriptEditor(team)
            ns:PrintError(ns:UXText("previewChanged"))
            return
        end
        local draft = scriptDrafts[team]
        if draft and draft.base ~= (team.script or "") then
            ns:PrintError(ns:UXText("draftConflict"))
            return
        end
        local rawColored = editBox:GetText() or ""
        local curClean = ns.Syntax:ColoredCursorToCleanPos(rawColored, editBox:GetCursorPosition() or 0)
        local raw = ns.Syntax:StripColors(rawColored)
        raw = ns:LocalizeScriptAbilities(raw)

        local ok, errMsg, errLine, errCode = ns.ScriptEngine:ValidateScript(raw)
        if not ok then
            ns:ShowScriptBugFrame(errMsg, errLine, errCode)
            ns:PrintError(errMsg)
            return
        end

        ns:HideScriptBugFrame()
        team.script = raw
        scriptDrafts[team] = nil
        if ns.ShowUIFeedback then ns:ShowUIFeedback(ns:UXText("scriptSaved")) end
        ns.Syntax:ApplyToEditBox(editBox, raw, curClean)
        if ns.MainFrame and ns.MainFrame.MarkScriptUnsaved then
            ns.MainFrame.MarkScriptUnsaved(false)
        end
        m.subInfo:SetText(string.format(SCRIPT_UI_TEXT.savedFmt, team.name or ns:T("未命名队伍")))
    end)
    m.saveScriptBtn = saveScriptBtn

    function m:Refresh()
        if C_PetBattles and C_PetBattles.IsInBattle() and PetBattleFrame then
            if self:GetParent() ~= PetBattleFrame then
                self:SetParent(PetBattleFrame)
            end
        elseif self:GetParent() ~= UIParent then
            self:SetParent(UIParent)
        end
        ns:MatchMainUIScale(self)
        self:SetFrameStrata("FULLSCREEN_DIALOG")
        self:SetFrameLevel(500)

        local team = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
        if team then
            local actSlot = ResolveActivePetSlotForEditor("")
            self.subInfo:SetText(string.format(SCRIPT_UI_TEXT.subInfoFmt, team.name or ns:T("未命名队伍"), actSlot))
            ns:SyncScriptEditor(team)
        end
        ns:HideScriptBugFrame()
    end

    ns.ScriptWorkspaceModal = m
    ns:BindHeaderHubPanel(m)
    return m
end

function ns:ToggleScriptWorkspace(forceShow)
    if forceShow == false then
        if ns.ScriptWorkspaceModal and ns.ScriptWorkspaceModal:IsShown() then
            if ns.ScriptEditBox then ns.ScriptEditBox:ClearFocus() end
            if ns.AutoCompletePopup then ns.AutoCompletePopup:Hide() end
            ns.ScriptWorkspaceModal:Hide()
        end
        return
    end

    local m = self:CreateScriptWorkspaceModal()
    if ns.RoutingModal and ns.RoutingModal:IsShown() then
        ns.RoutingModal:Hide()
    end
    local inBattle = C_PetBattles and C_PetBattles.IsInBattle()

    if forceShow == true or not m:IsShown() then
        if not inBattle then self:HideAllPopups() end
        m:Refresh()
        m:Show()
    else
        if ns.ScriptEditBox then ns.ScriptEditBox:ClearFocus() end
        if ns.AutoCompletePopup then ns.AutoCompletePopup:Hide() end
        m:Hide()
    end
end

-- 仅注册轻量状态钩子，不在打开主窗口时提前创建整个脚本编辑器框体树
function ns:InitScriptPanel(f)
    if f then
        f.MarkScriptUnsaved = function(unsaved)
            ns._scriptUnsavedState = unsaved and true or false
            if ns.ScriptWorkspaceModal and ns.ScriptWorkspaceModal.saveScriptBtn then
                ns.ScriptWorkspaceModal.saveScriptBtn.text:SetText(unsaved and "* 保存" or "保存")
            end
        end
    end
end