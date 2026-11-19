local ADDON_NAME, ns = ...

ns.SearchFilter = {}
ns.Leveling     = {}
ns.AutoRouting  = {}
ns.ScriptEngine = {}
ns.BattleStats  = {
    sessionStartTime   = GetTime(),
    battlesCount       = 0,
    lastPlayerXP       = 0,
    lastPlayerMaxXP    = 1,
    lastPlayerLevel    = 1,
    lastBattlePlayerXP = 0,
    totalPlayerXP      = 0,
    lastBattleDuration = 0,
    battleStartTime    = 0,
}

-- 弱引用表记录队伍脚本技能同步状态，绝不污染 SavedVariables 磁盘存档
local syncedScriptByTeam = setmetatable({}, { __mode = "k" })

-- 技能静态元数据缓存（避免搜索筛选与光环判定时重复查询 C API）
local journalAbilityCache = {}
local battleAbilityCache  = {}

local function GetCachedJournalAbility(abilityID)
    local info = journalAbilityCache[abilityID]
    if info then return info.name, info.nameLower, info.petType, info.noHints end
    local abName, _, abPetType, noHints = C_PetJournal.GetPetAbilityInfo(abilityID)
    if abName then
        info = {
            name      = abName,
            nameLower = strlower(abName),
            petType   = abPetType,
            noHints   = noHints,
        }
        journalAbilityCache[abilityID] = info
        return info.name, info.nameLower, info.petType, info.noHints
    end
    return nil, nil, abPetType, noHints
end

local function GetCachedBattleAbility(abilityID)
    local info = battleAbilityCache[abilityID]
    if info then return info.name, info.nameLower, info.icon, info.petType, info.noHints end
    if C_PetBattles and C_PetBattles.GetAbilityInfoByID then
        local _, name, icon, _, _, _, petType, noHints = C_PetBattles.GetAbilityInfoByID(abilityID)
        if name then
            info = {
                name      = name,
                nameLower = strlower(name),
                icon      = icon,
                petType   = petType,
                noHints   = noHints,
            }
            battleAbilityCache[abilityID] = info
            return info.name, info.nameLower, info.icon, info.petType, info.noHints
        end
    end
    return nil, nil, nil, nil, nil
end

-- 检测是否处于禁止宠物对战的常规副本（五人本/大秘境/团本/战场/竞技场），用于后台自动休眠
local function IsInRestrictedCombatInstance()
    if not IsInInstance then return false end
    local inInst, instType = IsInInstance()
    if not inInst then return false end
    return instType == "party" or instType == "raid" or instType == "pvp" or instType == "arena"
end

function ns:IsSecretValue(val)
    if val == nil then return false end
    if issecretvalue and issecretvalue(val) then return true end
    if canaccessvalue and not canaccessvalue(val) then return true end
    return false
end

local REVIVE_PETS_SPELL_ID = 125439 -- 复活战斗宠物技能 ID

function ns:GetRevivePetCooldownRemain()
    local start, duration = 0, 0
    if C_Spell and C_Spell.GetSpellCooldown then
        local cdInfo = C_Spell.GetSpellCooldown(REVIVE_PETS_SPELL_ID)
        if cdInfo and not self:IsSecretValue(cdInfo.startTime) and not self:IsSecretValue(cdInfo.duration) then
            start = cdInfo.startTime or 0
            duration = cdInfo.duration or 0
        end
    elseif GetSpellCooldown then
        local s, d = GetSpellCooldown(REVIVE_PETS_SPELL_ID)
        if not self:IsSecretValue(s) and not self:IsSecretValue(d) then
            start, duration = s or 0, d or 0
        end
    end
    if not start or start == 0 or not duration or duration <= 1.5 then
        return 0
    end
    return math.max(0, (start + duration) - GetTime())
end

function ns:IsRevivePetCooldownReady()
    if self:GetRevivePetCooldownRemain() > 0 then
        return false
    end
    if C_Spell and C_Spell.IsSpellUsable then
        local ok, usable = pcall(C_Spell.IsSpellUsable, REVIVE_PETS_SPELL_ID)
        if ok and not self:IsSecretValue(usable) and usable == false then
            return false
        end
    end
    return true
end

-- ==================== 1. 三套完全独立的过滤状态 (队伍 / 所有宠物 / 练级队列，保留存档引用) ====================

ns.teamFilterState = ns.teamFilterState or {
    keyword  = "",
    scope    = "ALL",
    category = "ALL",
    group    = "ALL",
    sortBy   = "TARGET_NAME",
}

ns.petFilterState = ns.petFilterState or {
    keyword         = "",
    showCollected   = true,
    onlyFav         = false,
    showUncollected = false,
    petType         = -1,
    strongVs        = -1,
    toughVs         = -1,
    source          = -1,
    expansion       = -1,
    rarity          = -1,
    levelType       = "ALL",
    marker          = -1,
    healthMode      = "ALL",
    onlyInTeam      = false,
    onlyTradable    = false,
    hasNotes        = false,
    scriptFilter    = "NONE",
    sortBy          = "DEFAULT",
    similarSpecies  = nil,
    movesetSpecies  = nil,
}

ns.queueFilterState = ns.queueFilterState or {
    keyword      = "",
    levelRange   = "ALL",
    rarity       = -1,
    petType      = -1,
    skipDead     = true,
    onlyFav      = false,
}

local function GetActiveQueueFilterTable()
    local state = (ns.db and type(ns.db.queueFilterState) == "table") and ns.db.queueFilterState or ns.queueFilterState
    -- Old saved filters are ignored and cleared, but breed labels remain visible.
    state.breed = nil
    ns.queueFilterState = state
    return state
end

local function GetActivePetFilterTable()
    local state = (ns.db and type(ns.db.petFilterState) == "table") and ns.db.petFilterState or ns.petFilterState
    state.breed = nil
    if state.scriptFilter == "SPEED300" or state.scriptFilter == "POWER300" or state.scriptFilter == "HEALTH1500" then
        state.scriptFilter = "NONE"
    end
    ns.petFilterState = state
    return state
end

-- Pet-list categories accept legacy scalar saves and new sets of checked values.
-- An empty selection means unrestricted; choices in one category are ORed.
function ns.SearchFilter:IsPetFilterSelectionActive(selection)
    if type(selection) == "table" then
        for _, checked in pairs(selection) do
            if checked then return true end
        end
        return false
    end
    return selection ~= nil and selection ~= -1
end

function ns.SearchFilter:IsPetFilterOptionSelected(selection, value)
    if value == -1 then return not self:IsPetFilterSelectionActive(selection) end
    if type(selection) == "table" then return selection[value] == true end
    return selection == value
end

function ns.SearchFilter:TogglePetFilterOption(state, key, value)
    if value == -1 then state[key] = -1; return end
    local old = state[key]
    local selected = {}
    if type(old) == "table" then
        for option, checked in pairs(old) do
            if checked then selected[option] = true end
        end
    elseif old ~= nil and old ~= -1 then
        selected[old] = true
    end
    selected[value] = not selected[value] or nil
    state[key] = next(selected) and selected or -1
end

function ns.SearchFilter:MatchPetFilterSelection(selection, value, matcher)
    if not self:IsPetFilterSelectionActive(selection) then return true end
    if type(selection) ~= "table" then
        if matcher then return matcher(self, value, selection) end
        return value == selection
    end
    if not matcher then return selection[value] == true end
    for option, checked in pairs(selection) do
        if checked and matcher(self, value, option) then return true end
    end
    return false
end

function ns.SearchFilter:MatchPetSource(sourceText, source)
    local keyword = strlower(ns:GetLocalizedSourceKeyword(source))
    return keyword == "" or string.find(sourceText, keyword, 1, true) ~= nil
end

function ns:GetSlotThreshold(team, slotIndex)
    if team and team.slotThresholds and team.slotThresholds[slotIndex] ~= nil then
        return tonumber(team.slotThresholds[slotIndex]) or 0
    end
    if ns.db and ns.db.defaultSlotThresholds and ns.db.defaultSlotThresholds[slotIndex] ~= nil then
        return tonumber(ns.db.defaultSlotThresholds[slotIndex]) or 0
    end
    return 0
end

function ns:SetSlotThreshold(team, slotIndex, val)
    val = math.max(0, math.floor(tonumber(val) or 0))
    if team then
        team.slotThresholds = team.slotThresholds or { [1] = 0, [2] = 0, [3] = 0 }
        team.slotThresholds[slotIndex] = val
    end
    if ns.db then
        ns.db.defaultSlotThresholds = ns.db.defaultSlotThresholds or { [1] = 0, [2] = 0, [3] = 0 }
        ns.db.defaultSlotThresholds[slotIndex] = val
    end
end

function ns:IsPetHealthyForThreshold(hp, maxHp, threshold)
    hp = hp or 0
    maxHp = (maxHp and maxHp > 0) and maxHp or 100
    if hp <= 0 then return false end
    threshold = tonumber(threshold) or 0
    if threshold <= 0 then return true end
    if threshold <= 100 then
        return ((hp / maxHp) * 100) > threshold
    else
        return hp > threshold
    end
end

function ns:IsPetHealthyForLoadout(hp, maxHp, threshold)
    hp = hp or 0
    maxHp = (maxHp and maxHp > 0) and maxHp or 100
    if hp <= 0 then return false end
    threshold = tonumber(threshold) or 0
    if threshold <= 0 then
        return hp >= maxHp
    elseif threshold <= 100 then
        return ((hp / maxHp) * 100) > threshold
    else
        return hp > threshold
    end
end

function ns.SearchFilter:ResetPetFilters()
    local st = GetActivePetFilterTable()
    st.keyword         = ""
    st.showCollected   = true
    st.onlyFav         = false
    st.showUncollected = false
    st.petType         = -1
    st.strongVs        = -1
    st.toughVs         = -1
    st.source          = -1
    st.expansion       = -1
    st.rarity          = -1
    st.levelType       = "ALL"
    st.marker          = -1
    st.healthMode      = "ALL"
    st.onlyInTeam      = false
    st.onlyTradable    = false
    st.hasNotes        = false
    st.scriptFilter    = "NONE"
    st.sortBy          = "DEFAULT"
    st.similarSpecies  = nil
    st.movesetSpecies  = nil
end

function ns.SearchFilter:ResetQueueFilters()
    local st = GetActiveQueueFilterTable()
    if ns.db and ns.db.settings then ns.db.settings.levelingRule = "MANUAL" end
    st.keyword    = ""
    st.levelRange = "ALL"
    st.minLv      = nil
    st.maxLv      = nil
    st.rarity     = -1
    st.petType    = -1
    st.skipDead   = true
    st.onlyFav    = false
end

function ns.SearchFilter:IsQueueFilterActive()
    local st = GetActiveQueueFilterTable()
    if not st then return false end
    return (st.keyword and strtrim(st.keyword) ~= "")
        or (st.levelRange and st.levelRange ~= "ALL")
        or (st.minLv and st.minLv > 1)
        or (st.maxLv and st.maxLv < 25)
        or (st.rarity and st.rarity ~= -1)
        or (st.petType and st.petType ~= -1)
        or (st.onlyFav == true)
        or (st.skipDead == false)
end

function ns.SearchFilter:IsPetFilterActive()
    local st = GetActivePetFilterTable()
    if not st then return false end
    return (st.keyword and strtrim(st.keyword) ~= "")
        or (st.showCollected == false)
        or (st.onlyFav == true)
        or (st.showUncollected == true)
        or self:IsPetFilterSelectionActive(st.petType)
        or self:IsPetFilterSelectionActive(st.strongVs)
        or self:IsPetFilterSelectionActive(st.toughVs)
        or self:IsPetFilterSelectionActive(st.source)
        or self:IsPetFilterSelectionActive(st.expansion)
        or self:IsPetFilterSelectionActive(st.rarity)
        or (st.levelType and st.levelType ~= "ALL")
        or self:IsPetFilterSelectionActive(st.marker)
        or (st.healthMode and st.healthMode ~= "ALL")
        or (st.onlyInTeam == true)
        or (st.onlyTradable == true)
        or (st.hasNotes == true)
        or (st.scriptFilter and st.scriptFilter ~= "NONE")
        or (st.sortBy and st.sortBy ~= "DEFAULT")
        or (st.similarSpecies ~= nil)
        or (st.movesetSpecies ~= nil)
end

function ns.SearchFilter:GetPetBreed(petID, speciesID, maxHealth, power, speed, level, rarity)
    local cache = (not ns._petCacheDirty) and ns._petCache or nil
    if petID and cache and cache.breeds then
        local cachedBreed = cache.breeds[petID]
        if cachedBreed then
            return cachedBreed
        end
    end

    local computed = "B/B"
    if petID and _G.GetBreedID_Journal then
        local ok, breedID = pcall(_G.GetBreedID_Journal, petID)
        if ok and breedID and _G.RetrieveBreedName then
            local bName = _G.RetrieveBreedName(breedID)
            if bName and bName ~= "" then
                if cache and cache.breeds then
                    cache.breeds[petID] = bName
                end
                return bName
            end
        end
    end

    maxHealth = (maxHealth and maxHealth > 100) and maxHealth or 150
    power = (power and power > 0) and power or 10
    speed = (speed and speed > 0) and speed or 10

    local normH = (maxHealth - 100) / 5.0
    local normP = power
    local normS = speed
    local avg = (normH + normP + normS) / 3.0
    if avg > 0 then
        local rH = normH / avg
        local rP = normP / avg
        local rS = normS / avg

        if rP >= 1.10 and (rP - rS) >= 0.06 and (rP - rH) >= 0.06 then
            computed = "P/P"
        elseif rS >= 1.10 and (rS - rP) >= 0.06 and (rS - rH) >= 0.06 then
            computed = "S/S"
        elseif rH >= 1.10 and (rH - rP) >= 0.06 and (rH - rS) >= 0.06 then
            computed = "H/H"
        elseif rP >= 1.01 and rS >= 1.01 and rH < 0.97 then
            computed = "P/S"
        elseif rH >= 1.01 and rP >= 1.01 and rS < 0.97 then
            computed = "H/P"
        elseif rH >= 1.01 and rS >= 1.01 and rP < 0.97 then
            computed = "H/S"
        elseif rP >= 1.04 and math.abs(rH - rS) < 0.06 then
            computed = "P/B"
        elseif rS >= 1.04 and math.abs(rH - rP) < 0.06 then
            computed = "S/B"
        elseif rH >= 1.04 and math.abs(rP - rS) < 0.06 then
            computed = "H/B"
        end
    end

    if petID and cache and cache.breeds then
        cache.breeds[petID] = computed
    end
    return computed
end

function ns.SearchFilter:GetFullPetData(petID)
    if not petID or type(petID) ~= "string" then return nil end
    local journalRevision = ns._petJournalRevision or 0
    local fullPetCache = self._fullPetDataCache
    if not fullPetCache or self._fullPetDataCacheRevision ~= journalRevision then
        fullPetCache = fullPetCache or {}
        wipe(fullPetCache)
        self._fullPetDataCache = fullPetCache
        self._fullPetDataCacheRevision = journalRevision
    end
    local cached = fullPetCache[petID]
    if cached then
        cached.marker = (ns.db and ns.db.petMarkers and ns.db.petMarkers[petID]) or nil
        cached.note = (ns.db and ns.db.petNotes and ns.db.petNotes[cached.speciesID]) or nil
        return cached
    end
    local speciesID, customName, level, xp, maxXp, displayID, isFavorite, name, icon, petType, _, sourceText, _, _, _, isTradable = C_PetJournal.GetPetInfoByPetID(petID)
    if not speciesID then return nil end

    local health, maxHealth, power, speed, rarity = C_PetJournal.GetPetStats(petID)
    health = health or 0
    maxHealth = (maxHealth and maxHealth > 0) and maxHealth or 100
    power = power or 0
    speed = speed or 0
    rarity = rarity or 1
    level = level or 1

    local hpPct = math.floor((health / maxHealth) * 100)
    if health <= 0 then hpPct = 0 end
    local breed = self:GetPetBreed(petID, speciesID, maxHealth, power, speed, level, rarity)
    local marker = (ns.db and ns.db.petMarkers and ns.db.petMarkers[petID]) or nil
    local note = (ns.db and ns.db.petNotes and ns.db.petNotes[speciesID]) or nil
    local fallbackName = name or ns:T("未知宠物")

    local pData = {
        petID       = petID,
        speciesID   = speciesID,
        displayID   = displayID,
        isCollected = true,
        name        = (customName and customName ~= "" and customName) or fallbackName,
        customName  = customName,
        speciesName = fallbackName,
        level       = level,
        xp          = xp or 0,
        maxXp       = (maxXp and maxXp > 0) and maxXp or 100,
        isFavorite  = isFavorite and true or false,
        icon        = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
        petType     = petType or 1,
        sourceText  = sourceText or "",
        isTradable  = isTradable and true or false,
        health      = health,
        maxHealth   = maxHealth,
        hpPct       = hpPct,
        isDead      = (health <= 0),
        isInjured   = (health < maxHealth),
        power       = power,
        speed       = speed,
        rarity      = rarity,
        breed       = breed,
        marker      = marker,
        note        = note,
    }
    fullPetCache[petID] = pData
    return pData
end

function ns.SearchFilter:HasStrongAbilityAgainst(speciesID, targetPetType)
    if not speciesID or targetPetType == -1 then return true end
    local idTable = ns:GetSortedPetAbilities(speciesID)
    if not idTable then return false end

    for i = 1, #idTable do
        local _, _, abilityPetType = GetCachedJournalAbility(idTable[i])
        if abilityPetType and ns.Theme.StrongAgainstMap[abilityPetType] == targetPetType then
            return true
        end
    end
    return false
end

function ns.SearchFilter:IsToughAgainst(petType, enemyAttackType)
    if not petType or enemyAttackType == -1 then return true end
    return ns.Theme.ToughAgainstMap[petType] == enemyAttackType
end

local function ScoreAbilityToken(speciesID, tok)
    if not speciesID then return 0 end
    local idTable = ns:GetSortedPetAbilities(speciesID)
    if not idTable then return 0 end
    local best = 0
    local Fuzzy = ns.FuzzySearch
    for i = 1, #idTable do
        local _, abNameLower = GetCachedJournalAbility(idTable[i])
        if abNameLower then
            local s = Fuzzy:ScoreToken(abNameLower, tok)
            if s > best then
                best = s
                if best >= 1000 then return best end
            end
        end
    end
    return best
end

function ns.SearchFilter:MatchAbilityKeyword(speciesID, kw)
    if not speciesID or not kw or kw == "" then return false end
    local tCount, tokens = ns.FuzzySearch:Prepare(kw)
    if tCount == 0 then return false end
    for i = 1, tCount do
        if ScoreAbilityToken(speciesID, tokens[i]) <= 0 then
            return false
        end
    end
    return true
end

-- All pet search surfaces use the same fuzzy name/species/ability/note/source matching.
-- Returns matched (bool), totalScore (number).
function ns.SearchFilter:MatchPetKeyword(speciesID, name, speciesName, kw, noteText, sourceText)
    if not kw or kw == "" then return true, 0 end
    local Fuzzy = ns.FuzzySearch
    local tCount, tokens = Fuzzy:Prepare(kw)
    if tCount == 0 then return true, 0 end

    local nameLower = (name and name ~= "") and strlower(name) or nil
    local spLower = (speciesName and speciesName ~= "" and speciesName ~= name) and strlower(speciesName) or nil
    local noteLower, sourceLower
    local totalScore = 0

    for i = 1, tCount do
        local tok = tokens[i]
        local best = 0
        if nameLower then
            local s = Fuzzy:ScoreToken(nameLower, tok)
            if s > 0 then best = s + 200 end
        end
        if spLower and best < 1100 then
            local s = Fuzzy:ScoreToken(spLower, tok)
            if s > 0 and (s + 150) > best then best = s + 150 end
        end
        if speciesID and best < 1050 then
            local s = ScoreAbilityToken(speciesID, tok)
            if s > 0 and (s + 80) > best then best = s + 80 end
        end
        if noteText and noteText ~= "" and best < 1050 then
            if not noteLower then noteLower = strlower(noteText) end
            local s = Fuzzy:ScoreToken(noteLower, tok)
            if s > 0 and (s + 60) > best then best = s + 60 end
        end
        if sourceText and sourceText ~= "" and best < 1000 then
            if not sourceLower then sourceLower = strlower(sourceText) end
            local s = Fuzzy:ScoreToken(sourceLower, tok)
            if s > 0 and (s + 20) > best then best = s + 20 end
        end
        if best <= 0 then return false, 0 end
        totalScore = totalScore + best
    end
    return true, totalScore
end

function ns.SearchFilter:CountSharedAbilities(spA, spB)
    if not spA or not spB then return 0 end
    if spA == spB then return 6 end
    local listA = ns:GetSortedPetAbilities(spA)
    local listB = ns:GetSortedPetAbilities(spB)
    if not listA or not listB then return 0 end
    local shared = 0
    for i = 1, #listA do
        local idA = listA[i]
        for j = 1, #listB do
            if idA == listB[j] then
                shared = shared + 1
                break
            end
        end
    end
    return shared
end

function ns.SearchFilter:MatchExpansion(speciesID, expGroup)
    if not expGroup or expGroup == -1 then return true end
    if not speciesID then return false end
    if expGroup == 1 then return speciesID <= 850
    elseif expGroup == 2 then return speciesID > 850 and speciesID <= 1650
    elseif expGroup == 3 then return speciesID > 1650 and speciesID <= 2900
    elseif expGroup == 4 then return speciesID > 2900 and speciesID <= 3550
    elseif expGroup == 5 then return speciesID > 3550
    end
    return true
end

-- 对象池与临时工作表：彻底消除每次筛选/搜索分配上千张表导致的 GC 卡顿
local petRowPool        = {}
local filteredResults   = {}
local inTeamLookupPool  = {}
local activePetSortMode = "DEFAULT"
local activePetSearchActive = false
local filteredCacheJournalRevision = -1
local filteredCacheListRevision = -1
local filteredCacheRouteRevision = -1
local filteredCacheSignature = nil
local filteredResultRevision = 0

-- Filter state is mutable (including saved profiles); a small deterministic key
-- avoids rescanning the journal on scroll, page changes or repeated UI refreshes.
local filterSignatureParts = {}
local filterKeys = {
    "keyword", "showCollected", "onlyFav", "showUncollected", "petType",
    "strongVs", "toughVs", "source", "expansion", "rarity", "levelType",
    "marker", "healthMode", "onlyInTeam", "onlyTradable", "hasNotes",
    "scriptFilter", "sortBy", "similarSpecies", "movesetSpecies",
}
local function BuildPetFilterSignature(state, keywordOverride)
    for i, key in ipairs(filterKeys) do
        local value = state[key]
        if key == "keyword" and keywordOverride ~= nil then value = keywordOverride end
        if type(value) == "table" then
            -- Multi-select categories have a small bounded integer domain.
            local bits = 0
            for k, checked in pairs(value) do
                if checked and type(k) == "number" and k >= 1 and k <= 32 then
                    bits = bits + 2 ^ (k - 1)
                end
            end
            filterSignatureParts[i] = tostring(bits)
        else
            filterSignatureParts[i] = tostring(value)
        end
    end
    return table.concat(filterSignatureParts, "\31")
end

-- 筛选结果持续偏小才释放表池尾部，给短暂搜索保留复用机会。
local resultTrimPending = {}
local function ScheduleResultPoolTrim(pool, results)
    if resultTrimPending[pool] or #pool < (#results + 128) * 2 then return end
    resultTrimPending[pool] = true
    C_Timer.After(5, function()
        resultTrimPending[pool] = nil
        local retained = #results + 128
        if #pool < retained * 2 then return end
        for i = #pool, retained + 1, -1 do
            pool[i] = nil
        end
    end)
end

local function UpdateResultHealth(results, sortOnDeathChange, compare)
    local needsSort = false
    for _, row in ipairs(results) do
        if row.petID then
            local health, maxHealth, power, speed, rarity = C_PetJournal.GetPetStats(row.petID)
            if health == nil or ((maxHealth and maxHealth > 0) and maxHealth or 100) ~= row.maxHealth
                or (power or 0) ~= row.power or (speed or 0) ~= row.speed or (rarity or 1) ~= row.rarity then
                return false
            end
            local isDead = health <= 0
            needsSort = needsSort or (sortOnDeathChange and row.isDead ~= isDead)
            row.health = health
            row.isDead = isDead
            row.isInjured = health < row.maxHealth
            row.hpPct = isDead and 0 or math.floor((health / row.maxHealth) * 100)
            if row._cacheEntry then
                row._cacheEntry.health = health
            end
        end
    end
    if needsSort then
        table.sort(results, compare)
    end
    return true
end

local function CompareFilteredPets(a, b)
    if activePetSearchActive then
        local sa, sb = a._matchScore or 0, b._matchScore or 0
        if sa ~= sb then return sa > sb end
    end
    if a.isCollected ~= b.isCollected then return a.isCollected end
    if activePetSortMode == "NAME" then
        if a.name ~= b.name then return a.name < b.name end
        return (a.petID or "") < (b.petID or "")
    elseif activePetSortMode == "LEVEL" then
        if a.level ~= b.level then return a.level > b.level end
    elseif activePetSortMode == "RARITY" then
        if a.rarity ~= b.rarity then return a.rarity > b.rarity end
    elseif activePetSortMode == "POWER" then
        if a.power ~= b.power then return a.power > b.power end
    elseif activePetSortMode == "SPEED" then
        if a.speed ~= b.speed then return a.speed > b.speed end
    elseif activePetSortMode == "HEALTH" then
        if a.maxHealth ~= b.maxHealth then return a.maxHealth > b.maxHealth end
    end

    if a.isFavorite ~= b.isFavorite then return a.isFavorite end
    if a.level ~= b.level then return a.level > b.level end
    if a.rarity ~= b.rarity then return a.rarity > b.rarity end
    if a.isDead ~= b.isDead then return not a.isDead end
    if a.name ~= b.name then return a.name < b.name end
    return (a.petID or "") < (b.petID or "")
end

function ns.SearchFilter:GetFilteredPets(keywordOverride)
    local cache = ns:GetPetJournalCache()
    local state = GetActivePetFilterTable()
    local signature = BuildPetFilterSignature(state, keywordOverride)
    local journalRevision = ns._petJournalRevision or 0
    local listRevision = ns._petListResultRevision or 0
    local routeRevision = state.onlyInTeam and (ns._routeRevision or 0) or 0
    if not ns._petCacheDirty and filteredCacheSignature == signature
        and filteredCacheJournalRevision == journalRevision
        and filteredCacheListRevision == listRevision
        and filteredCacheRouteRevision == routeRevision then
        return filteredResults
    end
    wipe(filteredResults)

    local entries = cache and cache.entries
    local entryCount = cache and cache.entryCount or 0
    -- A local search box can replace a hidden drawer's saved keyword without
    -- changing its saved filters. Empty string deliberately means no search.
    local kw = strlower(strtrim(keywordOverride ~= nil and keywordOverride or state.keyword or ""))
    local petMarkers = ns.db and ns.db.petMarkers or nil
    local petNotes   = ns.db and ns.db.petNotes or nil
    local unknownStr = ns:T("未知宠物")
    local uncolStr   = ns:T("未收集")

    local useSourceFilter = self:IsPetFilterSelectionActive(state.source)
    local useTeamLookup = (state.onlyInTeam == true)
    if useTeamLookup then
        wipe(inTeamLookupPool)
        for _, t in ipairs(ns.db.teams or {}) do
            if t.pets then
                for s = 1, 3 do
                    if t.pets[s] then inTeamLookupPool[t.pets[s]] = true end
                end
            end
            if t.speciesLoadout then
                for s = 1, 3 do
                    if t.speciesLoadout[s] and t.speciesLoadout[s] > 0 then
                        inTeamLookupPool[t.speciesLoadout[s]] = true
                    end
                end
            end
        end
    end

    local poolIdx = 0

    for i = 1, entryCount do
        local e = entries[i]
        local petID       = e.petID
        local speciesID   = e.speciesID
        local isCollected = e.isCollected
        local customName  = e.customName
        local level       = e.level
        local isFavorite  = e.isFavorite
        local speciesName = e.speciesName
        local icon        = e.icon
        local petType     = e.petType
        local sourceText  = e.sourceText
        local isTradable  = e.isTradable

        local validCol = (isCollected and state.showCollected) or (not isCollected and state.showUncollected)
        if validCol then
            local lv = isCollected and (level or 1) or 1
            local isFav = (isCollected and isFavorite) and true or false
            local pType = petType or 1
            local tradable = (isCollected and isTradable) and true or false
            local marker = (isCollected and petID and petMarkers and petMarkers[petID]) or nil
            local note = petNotes and petNotes[speciesID] or nil
            local sText = sourceText or ""

            -- 第一阶段：纯标量零 API 开销短路过滤
            local pass = true
            if state.onlyFav and not isFav then pass = false end
            if pass and not self:MatchPetFilterSelection(state.petType, pType) then pass = false end

            if pass and state.levelType ~= "ALL" then
                if state.levelType == "MAX" and lv < 25 then pass = false
                elseif state.levelType == "LV1" and lv ~= 1 then pass = false
                elseif state.levelType == "LV_MID" and (lv <= 1 or lv >= 25) then pass = false
                elseif state.levelType == "UNLEVELED" and lv >= 25 then pass = false end
            end

            if pass and not self:MatchPetFilterSelection(state.marker, marker) then pass = false end
            if pass and useTeamLookup and not ((petID and inTeamLookupPool[petID]) or inTeamLookupPool[speciesID]) then pass = false end
            if pass and state.onlyTradable and not tradable then pass = false end
            if pass and state.hasNotes and (not note or note == "") then pass = false end
            if pass and not self:MatchPetFilterSelection(state.expansion, speciesID, self.MatchExpansion) then pass = false end

            if pass and useSourceFilter and not self:MatchPetFilterSelection(state.source, strlower(sText), self.MatchPetSource) then pass = false end

            if pass and not self:MatchPetFilterSelection(state.strongVs, speciesID, self.HasStrongAbilityAgainst) then pass = false end
            if pass and not self:MatchPetFilterSelection(state.toughVs, pType, self.IsToughAgainst) then pass = false end
            if pass and state.similarSpecies and self:CountSharedAbilities(speciesID, state.similarSpecies) < 2 then pass = false end
            if pass and state.movesetSpecies and self:CountSharedAbilities(speciesID, state.movesetSpecies) < 6 then pass = false end
            if pass and state.scriptFilter == "MULTI_COUNT" then
                local cachedList = (not ns._petCacheDirty) and cache and cache.bySpecies and cache.bySpecies[speciesID]
                local count = cachedList and #cachedList or (C_PetJournal.GetNumCollectedInfo(speciesID) or 0)
                if count < 2 then pass = false end
            end

            local matchScore = 0
            if pass and kw ~= "" then
                local spNamePre = speciesName or (isCollected and unknownStr or uncolStr)
                local dispPre = (isCollected and customName and customName ~= "" and customName) or spNamePre
                pass, matchScore = self:MatchPetKeyword(speciesID, dispPre, spNamePre, kw, note, sText)
            end

            -- 第二阶段：仅对通过前置过滤的宠物查询/复用属性与 Breed
            if pass then
                local health, maxHealth, power, speed, rarity, hpPct, isDead, isInjured, breed
                local spName, dispName

                if isCollected and petID then
                    if not e._statsLoaded then
                        local h, mh, pw, sp, rar = C_PetJournal.GetPetStats(petID)
                        e.health      = h or 0
                        e.maxHealth   = (mh and mh > 0) and mh or 100
                        e.power       = pw or 0
                        e.speed       = sp or 0
                        e.rarity      = rar or 1
                        e._statsLoaded = true
                    end
                    health    = e.health
                    maxHealth = e.maxHealth
                    power     = e.power
                    speed     = e.speed
                    rarity    = e.rarity
                    isDead    = (health <= 0)
                    isInjured = (health < maxHealth)
                    hpPct     = isDead and 0 or math.floor((health / maxHealth) * 100)
                    spName    = speciesName or unknownStr
                    dispName  = (customName and customName ~= "" and customName) or spName
                else
                    health    = 0
                    maxHealth = 100
                    power     = 0
                    speed     = 0
                    rarity    = 1
                    isDead    = false
                    isInjured = false
                    hpPct     = 0
                    breed     = uncolStr
                    spName    = speciesName or uncolStr
                    dispName  = spName
                end

                if not self:MatchPetFilterSelection(state.rarity, rarity) then pass = false end
                if pass and state.healthMode == "ALIVE" and isDead then pass = false end
                if pass and state.healthMode == "DEAD" and not isInjured then pass = false end

                if pass then
                    if not breed then
                        breed = self:GetPetBreed(petID, speciesID, maxHealth, power, speed, lv, rarity)
                    end
                end

                if pass then
                    poolIdx = poolIdx + 1
                    local row = petRowPool[poolIdx]
                    if not row then
                        row = {}
                        petRowPool[poolIdx] = row
                    end
                    row.petID       = isCollected and petID or nil
                    row.speciesID   = speciesID
                    row.isCollected = isCollected and true or false
                    row.name        = dispName
                    row.nameLower   = strlower(dispName)
                    row.customName  = isCollected and customName or nil
                    row.speciesName = spName
                    row.level       = lv
                    row.xp          = 0
                    row.maxXp       = 100
                    row.isFavorite  = isFav
                    row.icon        = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
                    row.petType     = pType
                    row.sourceText  = sText
                    row.isTradable  = tradable
                    row.health      = health
                    row.maxHealth   = maxHealth
                    row.hpPct       = hpPct
                    row.isDead      = isDead
                    row.isInjured   = isInjured
                    row.power       = power
                    row.speed       = speed
                    row.rarity      = rarity
                    row.breed       = breed
                    row.marker      = marker
                    row.note        = note
                    row._matchScore = matchScore
                    row._cacheEntry = isCollected and e or nil

                    filteredResults[poolIdx] = row
                end
            end
        end
    end

    activePetSortMode = state.sortBy or "DEFAULT"
    activePetSearchActive = (kw ~= "")
    table.sort(filteredResults, CompareFilteredPets)
    ScheduleResultPoolTrim(petRowPool, filteredResults)
    -- Do not cache the empty journal while login is still loading.
    if not ns._petCacheDirty and entryCount > 0 then
        filteredCacheSignature = signature
        filteredCacheJournalRevision = journalRevision
        filteredCacheListRevision = listRevision
        filteredCacheRouteRevision = routeRevision
        filteredResultRevision = filteredResultRevision + 1
    end
    return filteredResults
end

function ns.SearchFilter:GetResultsRevision()
    return filteredResultRevision
end

function ns.SearchFilter:RefreshResultHealth(results)
    if results ~= filteredResults or ns._petCacheDirty then return false end
    local healthMode = GetActivePetFilterTable().healthMode
    if healthMode == "ALIVE" or healthMode == "DEAD" then return false end
    -- 名称排序只比较名称和宠物 ID；其他模式可能按阵亡状态调整顺序。
    local refreshed = UpdateResultHealth(results, activePetSortMode ~= "NAME", CompareFilteredPets)
    if not refreshed then filteredCacheJournalRevision = -1 end
    return refreshed
end

-- ==================== 2. 练级队列专属引擎（池化复用 + 零分配补位快路径） ====================
-- V4：练级队列是用户主动添加的列表，绝不自动纳入所有未满级宠物。
-- 清理已经满级、放生或重复的项目；收藏为空时，界面不显示队列入口。
local lastQueueOrder = nil
local lastQueueJournalRevision = -1
local lastQueueSnapshot = {}
local lastQueueCount = 0
local inQueueSet = {}
local queueResultRevision = 0

function ns.Leveling:GetQueueRevision()
    return queueResultRevision
end

function ns.Leveling:PruneManualQueue()
    local order = ns.db and ns.db.manualQueueOrder
    if type(order) ~= "table" then return 0 end
    if #order == 0 then
        lastQueueOrder, lastQueueCount = order, 0
        wipe(lastQueueSnapshot)
        wipe(inQueueSet)
        lastQueueJournalRevision = ns._petJournalRevision or 0
        return 0
    end
    local journalRevision = ns._petJournalRevision or 0
    local unchanged = order == lastQueueOrder and journalRevision == lastQueueJournalRevision
        and #order == #lastQueueSnapshot
    if unchanged then
        for i = 1, #order do
            if order[i] ~= lastQueueSnapshot[i] then unchanged = false; break end
        end
    end
    if unchanged then return lastQueueCount end

    -- Do not delete persisted pets before the journal has finished loading.
    local numPets = C_PetJournal.GetNumPets()
    if not numPets or numPets == 0 then return 0 end
    local seen, write = {}, 0
    for read = 1, #order do
        local petID = order[read]
        if type(petID) == "string" and not seen[petID] then
            local speciesID, _, level, _, _, _, _, _, _, _, _, _, _, _, canBattle = C_PetJournal.GetPetInfoByPetID(petID)
            if speciesID and level and level < 25 and canBattle ~= false then
                seen[petID] = true
                write = write + 1
                order[write] = petID
            end
        end
    end
    for i = write + 1, #order do order[i] = nil end
    wipe(lastQueueSnapshot)
    wipe(inQueueSet)
    for i = 1, write do
        local pid = order[i]
        lastQueueSnapshot[i] = pid
        inQueueSet[pid] = true
    end
    lastQueueOrder = order
    lastQueueJournalRevision = journalRevision
    lastQueueCount = write
    queueResultRevision = queueResultRevision + 1
    return write
end

function ns.Leveling:GetManualQueueCount()
    return self:PruneManualQueue()
end

function ns.Leveling:ClearManualQueue()
    if not ns.db or not ns.db.manualQueueOrder then return false end
    if #ns.db.manualQueueOrder == 0 then return false end
    wipe(ns.db.manualQueueOrder)
    wipe(inQueueSet)
    queueResultRevision = queueResultRevision + 1
    return true
end

function ns.Leveling:IsPetInQueue(petID)
    if not petID or not ns.db or not ns.db.manualQueueOrder then return false end
    if lastQueueOrder ~= ns.db.manualQueueOrder then
        self:PruneManualQueue()
    end
    return inQueueSet[petID] == true
end

function ns.Leveling:TogglePetInQueue(petID)
    if not petID or not ns.db or not ns.db.manualQueueOrder then return false end
    self:PruneManualQueue()
    for idx, id in ipairs(ns.db.manualQueueOrder) do
        if id == petID then
            table.remove(ns.db.manualQueueOrder, idx)
            inQueueSet[petID] = nil
            queueResultRevision = queueResultRevision + 1
            return false
        end
    end
    local speciesID, _, level, _, _, _, _, _, _, _, _, _, _, _, canBattle = C_PetJournal.GetPetInfoByPetID(petID)
    if not speciesID or not level or level >= 25 or canBattle == false then return false end
    table.insert(ns.db.manualQueueOrder, 1, petID)
    inQueueSet[petID] = true
    queueResultRevision = queueResultRevision + 1
    return true
end

function ns.Leveling:MovePetToQueueFront(petID)
    if not ns.db or not petID then return false end
    self:PruneManualQueue()
    local speciesID, _, level, _, _, _, _, _, _, _, _, _, _, _, canBattle = C_PetJournal.GetPetInfoByPetID(petID)
    if not speciesID or not level or level >= 25 or canBattle == false then return false end
    local order = ns.db.manualQueueOrder or {}
    ns.db.manualQueueOrder = order
    for i = #order, 1, -1 do
        if order[i] == petID then table.remove(order, i) end
    end
    table.insert(order, 1, petID)
    ns.db.settings.levelingRule = "MANUAL"
    local team = ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
    if team and team.hasLevelingSlot and not (ns.staging and ns.staging.isDirty)
        and not InCombatLockdown() and not (C_PetBattles and C_PetBattles.IsInBattle()) then
        self:AssignTopPetToLevelingSlot(team.levelingSlot)
    end
    return true
end

function ns.Leveling:BatchEnqueueByMode(mode)
    local cache = ns:GetPetJournalCache()
    local entries = cache and cache.entries
    local entryCount = cache and cache.entryCount or 0
    local existing = {}
    for _, id in ipairs(ns.db.manualQueueOrder) do existing[id] = true end
    local addedCount = 0

    for i = 1, entryCount do
        local e = entries[i]
        local petID = e.petID
        local level = e.level
        if e.isCollected and petID and level and level < 25 and not existing[petID] then
            local health, _, _, _, rarity = C_PetJournal.GetPetStats(petID)
            if health and health > 0 then
                rarity = rarity or 1
                local match = false
                if mode == "UNLEVELED_ALL" then
                    match = true
                elseif mode == "RARE_ALL" and rarity == 4 then
                    match = true
                elseif mode == "LV_20_24" and level >= 20 and level <= 24 then
                    match = true
                elseif mode == "LV_1_10" and level >= 1 and level <= 10 and rarity >= 3 then
                    match = true
                elseif mode == "FAV_ALL" and e.isFavorite then
                    match = true
                end
                if match then
                    table.insert(ns.db.manualQueueOrder, petID)
                    existing[petID] = true
                    addedCount = addedCount + 1
                end
            end
        end
    end
    return addedCount
end

-- Health must be checked live before battle; iterate only explicit queue IDs.
local function FindLivingQueuePet()
    if ns.Leveling:PruneManualQueue() == 0 then return false end
    local qState = GetActiveQueueFilterTable()
    local kw = strlower(strtrim(qState.keyword or ""))
    for _, petID in ipairs(ns.db.manualQueueOrder or {}) do
        local speciesID, customName, level, _, _, _, isFavorite, speciesName, _, petType, _, _, _, _, canBattle = C_PetJournal.GetPetInfoByPetID(petID)
        if speciesID and canBattle ~= false and level and level < 25 then
            local pass = true
            if qState.minLv and level < qState.minLv then pass = false end
            if qState.maxLv and level > qState.maxLv then pass = false end
            if qState.levelRange == "LV1_10" and level > 10 then pass = false
            elseif qState.levelRange == "LV11_20" and (level < 11 or level > 20) then pass = false
            elseif qState.levelRange == "LV21_24" and level < 21 then pass = false end
            if pass and qState.petType ~= -1 and (petType or 1) ~= qState.petType then pass = false end
            if pass and qState.onlyFav and not isFavorite then pass = false end
            if pass then
                local health, maxHealth, power, speed, rarity = C_PetJournal.GetPetStats(petID)
                if health and health > 0 and (qState.rarity == -1 or (rarity or 1) >= qState.rarity) then
                    if kw == "" then return true end
                    local name = (customName and customName ~= "" and customName) or speciesName or ""
                    if ns.SearchFilter:MatchPetKeyword(speciesID, name, speciesName, kw) then return true end
                end
            end
        end
    end
    return false
end

function ns.Leveling:HasLivingQueuePet(evaluation)
    if evaluation and evaluation.hasLivingQueuePet ~= nil then
        return evaluation.hasLivingQueuePet
    end
    local found = FindLivingQueuePet()
    if evaluation then evaluation.hasLivingQueuePet = found end
    return found
end

local queueRowPool      = {}
local queueResults      = {}
local priorityRankPool  = {}
local activeQueueRule   = "MANUAL"
local activeQueueSearchActive = false
local activeQueueSkipDead = true
local queueCacheOrder, queueCacheJournal, queueCacheList, queueCacheSignature
local queueCacheSnapshot = {}

local function QueueCacheMatches(order, state, keywordOverride)
    local keyword = keywordOverride ~= nil and keywordOverride or state.keyword or ""
    local signature = table.concat({keyword, state.levelRange or "ALL", tostring(state.minLv or 1), tostring(state.maxLv or 25), tostring(state.rarity),
        tostring(state.petType), tostring(state.skipDead), tostring(state.onlyFav),
        ns.db.settings.levelingRule or "MANUAL"}, "\031")
    if order ~= queueCacheOrder or (ns._petJournalRevision or 0) ~= queueCacheJournal
        or (ns._petListResultRevision or 0) ~= queueCacheList or #order ~= #queueCacheSnapshot
        or signature ~= queueCacheSignature then return false, signature end
    for i = 1, #order do if order[i] ~= queueCacheSnapshot[i] then return false, signature end end
    return true, signature
end

local function IsBetterQueueOrder(aRank, aLv, aRarity, aName, aPetID, bRank, bLv, bRarity, bName, bPetID, rule)
    local hasRarity = (rule == "RARITY_DESC" or rule == "RARITY_LEVEL_ASC" or rule == "RARITY_LEVEL_DESC")
    local lvAsc     = (rule == "LEVEL_ASC" or rule == "RARITY_LEVEL_ASC")
    local lvDesc    = (rule == "LEVEL_DESC" or rule == "RARITY_LEVEL_DESC")

    if hasRarity and aRarity ~= bRarity then
        return aRarity > bRarity
    end
    if lvAsc and aLv ~= bLv then
        return aLv < bLv
    elseif lvDesc and aLv ~= bLv then
        return aLv > bLv
    elseif hasRarity and aLv ~= bLv then
        return aLv > bLv
    end
    -- Manual rank is the primary key in manual mode and a stable tie-breaker otherwise.
    if aRank ~= bRank then return aRank < bRank end
    if aRarity ~= bRarity then return aRarity > bRarity end
    if aName ~= bName then return aName < bName end
    return (aPetID or "") < (bPetID or "")
end

local function CompareQueueEntries(a, b)
    if activeQueueSearchActive then
        local sa, sb = a._matchScore or 0, b._matchScore or 0
        if sa ~= sb then return sa > sb end
    end
    if activeQueueSkipDead and a.isDead ~= b.isDead then
        return not a.isDead
    end
    return IsBetterQueueOrder(
        a.manualRank, a.level, a.rarity, a.name, a.petID,
        b.manualRank, b.level, b.rarity, b.name, b.petID,
        activeQueueRule
    )
end

function ns.Leveling:GetQueue(keywordOverride)
    self:PruneManualQueue()
    local order = ns.db and ns.db.manualQueueOrder
    if not order or #order == 0 then
        wipe(queueResults)
        queueCacheOrder = nil
        return queueResults
    end
    -- PruneManualQueue detects even in-place reordering. Journal and list revisions
    -- invalidate pet data, while the signature tracks every queue filter.
    local qState = GetActiveQueueFilterTable()
    local hit, signature = QueueCacheMatches(order, qState, keywordOverride)
    if hit then return queueResults end
    wipe(queueResults)
    wipe(priorityRankPool)
    local kw = strlower(strtrim(keywordOverride ~= nil and keywordOverride or qState.keyword or ""))
    local petMarkers = ns.db and ns.db.petMarkers or nil
    local petNotes   = ns.db and ns.db.petNotes or nil
    local unknownStr = ns:T("未知宠物")
    for idx, id in ipairs(order) do
        priorityRankPool[id] = idx
    end

    local poolIdx = 0

    for _, petID in ipairs(order) do
        local speciesID, customName, level, _, _, displayID, isFavorite, speciesName, icon, petType, _, sourceText, _, _, canBattle, isTradable = C_PetJournal.GetPetInfoByPetID(petID)
        if speciesID and canBattle ~= false and level and level < 25 then
            local pType = petType or 1
            local isFav = isFavorite and true or false
            local pass = true
            if qState.minLv and level < qState.minLv then pass = false end
            if qState.maxLv and level > qState.maxLv then pass = false end

            if qState.levelRange == "LV1_10" and level > 10 then pass = false
            elseif qState.levelRange == "LV11_20" and (level < 11 or level > 20) then pass = false
            elseif qState.levelRange == "LV21_24" and level < 21 then pass = false end

            if pass and qState.petType ~= -1 and pType ~= qState.petType then pass = false end
            if pass and qState.onlyFav and not isFav then pass = false end

            local spName = speciesName or unknownStr
            local dispName = (customName and customName ~= "" and customName) or spName
            local noteText = petNotes and petNotes[speciesID] or nil
            local matchScore = 0
            if pass then
                pass, matchScore = ns.SearchFilter:MatchPetKeyword(speciesID, dispName, spName, kw, noteText, sourceText)
            end

            if pass then
                local health, maxHealth, power, speed, rarity = C_PetJournal.GetPetStats(petID)
                health = health or 0
                maxHealth = (maxHealth and maxHealth > 0) and maxHealth or 100
                power = power or 0
                speed = speed or 0
                rarity = rarity or 1

                if qState.rarity ~= -1 and rarity < qState.rarity then
                    pass = false
                end

                local breed
                if pass then
                    breed = ns.SearchFilter:GetPetBreed(petID, speciesID, maxHealth, power, speed, level, rarity)
                end

                if pass then
                    local isDead = (health <= 0)
                    poolIdx = poolIdx + 1
                    local row = queueRowPool[poolIdx]
                    if not row then
                        row = {}
                        queueRowPool[poolIdx] = row
                    end
                    row.petID       = petID
                    row.speciesID   = speciesID
                    row.displayID   = displayID
                    row.isCollected = true
                    row.name        = dispName
                    row.nameLower   = strlower(dispName)
                    row.customName  = customName
                    row.speciesName = spName
                    row.level       = level
                    row.xp          = 0
                    row.maxXp       = 100
                    row.isFavorite  = isFav
                    row.icon        = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
                    row.petType     = pType
                    row.sourceText  = sourceText or ""
                    row.isTradable  = isTradable and true or false
                    row.health      = health
                    row.maxHealth   = maxHealth
                    row.hpPct       = isDead and 0 or math.floor((health / maxHealth) * 100)
                    row.isDead      = isDead
                    row.isInjured   = (health < maxHealth)
                    row.power       = power
                    row.speed       = speed
                    row.rarity      = rarity
                    row.breed       = breed
                    row.marker      = petMarkers and petMarkers[petID] or nil
                    row.note        = noteText
                    row._matchScore = matchScore
                    row.manualRank  = priorityRankPool[petID] or 99999

                    queueResults[poolIdx] = row
                end
            end
        end
    end

    activeQueueRule     = ns.db.settings.levelingRule or "MANUAL"
    activeQueueSkipDead = (qState.skipDead ~= false)
    activeQueueSearchActive = (kw ~= "")
    table.sort(queueResults, CompareQueueEntries)
    queueResultRevision = queueResultRevision + 1
    ScheduleResultPoolTrim(queueRowPool, queueResults)
    -- Never retain results from an uninitialized journal.
    if lastQueueOrder == order and lastQueueJournalRevision == (ns._petJournalRevision or 0) then
        queueCacheOrder, queueCacheJournal = order, ns._petJournalRevision or 0
        queueCacheList = ns._petListResultRevision or 0
        queueCacheSignature = signature
        wipe(queueCacheSnapshot)
        for i = 1, #order do queueCacheSnapshot[i] = order[i] end
    end
    return queueResults
end

function ns.Leveling:RefreshResultHealth(results)
    if results ~= queueResults or ns._petCacheDirty then return false end
    local ok = UpdateResultHealth(results, activeQueueSkipDead, CompareQueueEntries)
    if not ok then queueCacheOrder = nil end
    return ok
end

function ns.Leveling:ReorderQueueByDrag(sourcePetID, targetPetID, insertAfter, keywordOverride)
    if not sourcePetID or not targetPetID or sourcePetID == targetPetID then return false end
    local queue = self:GetQueue(keywordOverride)
    local newOrder = {}
    local inVisible = {}
    local srcIdx, dstIdx = nil, nil

    for idx, item in ipairs(queue) do
        local pid = item.petID
        newOrder[idx] = pid
        inVisible[pid] = true
        if pid == sourcePetID then srcIdx = idx end
        if pid == targetPetID then dstIdx = idx end
    end

    if not dstIdx then return false end
    if srcIdx then
        table.remove(newOrder, srcIdx)
    end

    local placeAfter = insertAfter
    if placeAfter == nil then placeAfter = srcIdx ~= nil and srcIdx < dstIdx end
    local insertPos = #newOrder + 1
    for idx, id in ipairs(newOrder) do
        if id == targetPetID then
            insertPos = placeAfter and (idx + 1) or idx
            break
        end
    end
    table.insert(newOrder, insertPos, sourcePetID)
    inVisible[sourcePetID] = true

    if ns.db and type(ns.db.manualQueueOrder) == "table" then
        for _, oldID in ipairs(ns.db.manualQueueOrder) do
            if oldID and not inVisible[oldID] then
                newOrder[#newOrder + 1] = oldID
                inVisible[oldID] = true
            end
        end
    end

    ns.db.manualQueueOrder = newOrder
    ns.db.settings.levelingRule = "MANUAL"

    local team = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
    if team and team.hasLevelingSlot and not (ns.staging and ns.staging.isDirty) then
        self:AssignTopPetToLevelingSlot(team.levelingSlot)
    end
    return true
end

function ns.Leveling:MovePetInQueue(petID, direction)
    local queue = self:GetQueue()
    local newOrder = {}
    local inVisible = {}
    local targetIdx = nil

    for idx, item in ipairs(queue) do
        newOrder[idx] = item.petID
        inVisible[item.petID] = true
        if item.petID == petID then targetIdx = idx end
    end

    if targetIdx then
        local swapIdx = targetIdx + direction
        if swapIdx >= 1 and swapIdx <= #newOrder then
            newOrder[targetIdx], newOrder[swapIdx] = newOrder[swapIdx], newOrder[targetIdx]
        end
    else
        table.insert(newOrder, 1, petID)
        inVisible[petID] = true
    end

    if ns.db and type(ns.db.manualQueueOrder) == "table" then
        for _, oldID in ipairs(ns.db.manualQueueOrder) do
            if oldID and not inVisible[oldID] then
                newOrder[#newOrder + 1] = oldID
                inVisible[oldID] = true
            end
        end
    end

    ns.db.manualQueueOrder = newOrder
    ns.db.settings.levelingRule = "MANUAL"
end

function ns.Leveling:RefreshSelectedSlot()
    local team = ns.db and ns.db.teams[ns.db.selectedTeamIdx]
    if team and team.hasLevelingSlot and (not ns.staging.isDirty or self:GetManualQueueCount() == 0) then
        self:AssignTopPetToLevelingSlot(team.levelingSlot)
    end
end

function ns.Leveling:CaptureSlotFallback(team, slot, fromSaved)
    local petID, a1, a2, a3
    if fromSaved then
        petID = team.pets and team.pets[slot]
        local abilities = team.abilities and team.abilities[slot]
        if abilities then a1, a2, a3 = unpack(abilities) end
    else
        petID, a1, a2, a3 = C_PetJournal.GetPetLoadOutInfo(slot)
    end
    local speciesID = petID and petID ~= "LEVELING" and C_PetJournal.GetPetInfoByPetID(petID)
    team.levelingFallback = {
        petID = speciesID and petID or nil,
        speciesID = speciesID or 0,
        abilities = {a1 or 0, a2 or 0, a3 or 0},
    }
end

function ns.Leveling:GetSlotFallback(team, slot, usedPets, fallback)
    fallback = fallback or team.levelingFallback
    if not fallback then
        -- Legacy teams may still have an ordinary pet recorded in the slot.
        local saved = team.pets and team.pets[slot]
        if saved and saved ~= "LEVELING" then
            fallback = { petID = saved, speciesID = team.speciesLoadout and team.speciesLoadout[slot],
                abilities = team.abilities and team.abilities[slot] }
        else
            return nil
        end
    end
    local petID = fallback.petID
    if petID and C_PetJournal.GetPetInfoByPetID(petID) and not (usedPets and usedPets[petID]) then
        return petID, fallback.abilities
    end
    if (fallback.speciesID or 0) > 0 then
        return ns.AutoRouting:FindAnyCollectedPetForSpecies(fallback.speciesID, usedPets), fallback.abilities
    end
end

function ns.Leveling:RestoreSlotFallback(team, slot, fallback)
    if not team or InCombatLockdown() or (C_PetBattles and C_PetBattles.IsInBattle()) then return end
    local used = {}
    for other = 1, 3 do
        if other ~= slot then
            local petID = C_PetJournal.GetPetLoadOutInfo(other)
            if petID then used[petID] = true end
        end
    end
    local petID, abilities = self:GetSlotFallback(team, slot, used, fallback)
    local live, a1, a2, a3 = C_PetJournal.GetPetLoadOutInfo(slot)
    if petID then
        if live ~= petID or (abilities and ((abilities[1] or 0) > 0 and a1 ~= abilities[1]
            or (abilities[2] or 0) > 0 and a2 ~= abilities[2]
            or (abilities[3] or 0) > 0 and a3 ~= abilities[3])) then
            ns.AutoRouting:EquipPetAndSyncSkills(slot, petID, abilities)
        end
    elseif live then
        ns.AutoRouting:ClearLoadoutSlot(slot)
    end
    return petID
end

-- 当槽位被设为经验槽或点击空经验槽时，自动从图鉴中随机挑选一只存活的未满级可对战宠物加入练级队列并填入槽位
function ns.Leveling:FillRandomUnleveledPetForSlot(customSlot, showFeedback)
    if InCombatLockdown() or (C_PetBattles and C_PetBattles.IsInBattle()) then return nil, false end
    local team = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
    local slot = customSlot or (team and team.levelingSlot) or (ns.db and ns.db.settings and ns.db.settings.levelingSlot) or 2
    self:PruneManualQueue()

    local usedPets = {}
    for s = 1, 3 do
        if s ~= slot then
            local liveID = C_PetJournal and C_PetJournal.GetPetLoadOutInfo and C_PetJournal.GetPetLoadOutInfo(s)
            if liveID then usedPets[liveID] = true end
            local savedID = team and team.pets and team.pets[s]
            if savedID and savedID ~= "LEVELING" then usedPets[savedID] = true end
            local draft = ns.MainFrame and ns.MainFrame.compactDraft
            local draftEntry = draft and draft.slots and draft.slots[s]
            if draftEntry and draftEntry.petID then usedPets[draftEntry.petID] = true end
        end
    end

    local assignedPetID = nil
    local addedRandom = false

    for _, item in ipairs(self:GetQueue()) do
        local pid = item.petID
        if pid and not item.isDead and not usedPets[pid] then
            local hp = C_PetJournal.GetPetStats(pid)
            if hp and hp > 0 then
                assignedPetID = pid
                break
            end
        end
    end

    if not assignedPetID then
        local candidates = {}
        local numPets = (C_PetJournal and C_PetJournal.GetNumPets and C_PetJournal.GetNumPets()) or 0
        for i = 1, numPets do
            local petID, _, isCollected, _, level, _, _, _, _, _, _, _, _, _, canBattle = C_PetJournal.GetPetInfoByIndex(i)
            if isCollected and petID and canBattle ~= false and level and level < 25 and not usedPets[petID] then
                local health = C_PetJournal.GetPetStats(petID)
                if health and health > 0 then
                    candidates[#candidates + 1] = petID
                end
            end
        end
        if #candidates > 0 then
            local chosen = candidates[math.random(#candidates)]
            ns.db.manualQueueOrder = ns.db.manualQueueOrder or {}
            for i = #ns.db.manualQueueOrder, 1, -1 do
                if ns.db.manualQueueOrder[i] == chosen then
                    table.remove(ns.db.manualQueueOrder, i)
                end
            end
            table.insert(ns.db.manualQueueOrder, 1, chosen)
            inQueueSet[chosen] = true
            queueResultRevision = queueResultRevision + 1
            assignedPetID = chosen
            addedRandom = true
        end
    end

    if assignedPetID then
        local draft = ns.MainFrame and ns.MainFrame.compactDraft
        if draft and draft.levelingSlot == slot then
            local spID = C_PetJournal.GetPetInfoByPetID(assignedPetID)
            local ids = spID and ns:GetSortedPetAbilities(spID)
            if ids then
                draft.slots[slot] = { petID = assignedPetID, abilities = { ids[1] or 0, ids[2] or 0, ids[3] or 0 } }
            end
        else
            local currentPetID = C_PetJournal and C_PetJournal.GetPetLoadOutInfo and C_PetJournal.GetPetLoadOutInfo(slot)
            if currentPetID ~= assignedPetID and ns.AutoRouting and ns.AutoRouting.EquipPetAndSyncSkills then
                ns.AutoRouting:EquipPetAndSyncSkills(slot, assignedPetID)
            end
        end
        if showFeedback ~= false and ns.ShowUIFeedback then
            ns:ShowUIFeedback(ns:T("已填入随机宠物开启练级队列"))
        end
    end

    return assignedPetID, addedRandom
end

-- 仅遍历手动练级队列选出最高优先级存活宠物，避免扫描整本图鉴。
function ns.Leveling:AssignTopPetToLevelingSlot(customSlot)
    if InCombatLockdown() or (C_PetBattles and C_PetBattles.IsInBattle()) then return nil end
    local team = ns.db.teams[ns.db.selectedTeamIdx]
    local slot = customSlot or (team and team.levelingSlot) or ns.db.settings.levelingSlot or 2
    if self:PruneManualQueue() == 0 then
        if team and team.hasLevelingSlot and slot == (team.levelingSlot or ns.db.settings.levelingSlot or 2) then
            return self:RestoreSlotFallback(team, slot)
        end
        return nil
    end

    local teamPets = team and team.pets
    local otherPet1 = teamPets and teamPets[slot == 1 and 2 or 1]
    local otherPet2 = teamPets and teamPets[slot == 3 and 2 or 3]
    local bestPetID = nil

    -- 直接复用已缓存且按规则排好序的 GetQueue() 结果，O(1) 取出首位存活宠物，避免重复扫描整条队列
    for _, item in ipairs(self:GetQueue()) do
        local pid = item.petID
        if pid and not item.isDead and pid ~= otherPet1 and pid ~= otherPet2 then
            local hp = C_PetJournal.GetPetStats(pid)
            if hp and hp > 0 then
                bestPetID = pid
                break
            end
        end
    end

    if bestPetID then
        local currentPetID = C_PetJournal.GetPetLoadOutInfo(slot)
        if currentPetID ~= bestPetID then
            ns.AutoRouting:EquipPetAndSyncSkills(slot, bestPetID)
        end
        return bestPetID
    end
    return nil
end

-- ==================== 3. 目标换队与无目标全天候自动顺延准备引擎 ====================

function ns.AutoRouting:ValidateAbilitiesForSpecies(speciesID, desiredAbilities)
    if not speciesID or speciesID <= 0 then return { 0, 0, 0 } end
    local sortedIDs = ns:GetSortedPetAbilities(speciesID)
    if not sortedIDs or #sortedIDs < 3 then
        return desiredAbilities or { 0, 0, 0 }
    end

    local validated = { 0, 0, 0 }
    for abIdx = 1, 3 do
        local tier1ID = sortedIDs[abIdx] or 0
        local tier2ID = sortedIDs[abIdx + 3] or tier1ID
        local req = desiredAbilities and desiredAbilities[abIdx] or 0

        if req == 1 then
            validated[abIdx] = tier1ID
        elseif req == 2 then
            validated[abIdx] = tier2ID
        elseif req == tier1ID or req == tier2ID then
            validated[abIdx] = req
        else
            validated[abIdx] = tier1ID
        end
    end
    return validated
end

function ns.AutoRouting:RememberSlotSpeciesSkills(slotIndex, speciesID, abilitiesTable)
    if not slotIndex or not speciesID or speciesID <= 0 or not abilitiesTable then return end
    ns.db.slotSpeciesMemory = ns.db.slotSpeciesMemory or { [1] = {}, [2] = {}, [3] = {} }
    ns.db.slotSpeciesMemory[slotIndex] = ns.db.slotSpeciesMemory[slotIndex] or {}
    ns.db.slotSpeciesMemory[slotIndex][speciesID] = self:ValidateAbilitiesForSpecies(speciesID, abilitiesTable)
end

function ns.AutoRouting:FindBestHealthyDuplicate(speciesID, usedPetIDs, thresholdVal, allowInjuredFallback)
    if not speciesID or speciesID <= 0 then return nil end
    thresholdVal = tonumber(thresholdVal) or 0
    usedPetIDs = usedPetIDs or {}

    local cache = ns.GetPetJournalCache and ns:GetPetJournalCache()
    local candidates = cache and cache.bySpecies[speciesID]
    if not candidates or #candidates == 0 then return nil end

    local bestCandidate = nil
    local bestScore = -1

    for i = 1, #candidates do
        local petID = candidates[i]
        if not usedPetIDs[petID] then
            local packed = cache.packedPet[petID]
            local level = packed and (packed % 64) or 1
            local health, maxHealth, _, _, rarity = C_PetJournal.GetPetStats(petID)
            health = health or 0
            maxHealth = (maxHealth and maxHealth > 0) and maxHealth or 100

            local pass = allowInjuredFallback and (health > 0) or ns:IsPetHealthyForLoadout(health, maxHealth, thresholdVal)
            if pass then
                local isFullHP = (health >= maxHealth) and 1 or 0
                local hpPct = (health / maxHealth) * 100
                local score = level * 100000 + isFullHP * 10000 + hpPct * 10 + (rarity or 1)
                if score > bestScore then
                    bestScore = score
                    bestCandidate = petID
                end
            end
        end
    end

    return bestCandidate
end

function ns.AutoRouting:FindAnyCollectedPetForSpecies(speciesID, usedPetIDs)
    if not speciesID or speciesID <= 0 then return nil end
    usedPetIDs = usedPetIDs or {}

    local cache = ns.GetPetJournalCache and ns:GetPetJournalCache()
    local candidates = cache and cache.bySpecies[speciesID]
    if not candidates or #candidates == 0 then return nil end

    local bestCandidate, bestLv = nil, -1
    for i = 1, #candidates do
        local petID = candidates[i]
        if not usedPetIDs[petID] then
            local packed = cache.packedPet[petID]
            local level = packed and (packed % 64) or 1
            if level > bestLv then
                bestLv = level
                bestCandidate = petID
            end
        end
    end
    return bestCandidate
end

local slotEquipTokens = { [1] = 0, [2] = 0, [3] = 0 }
local middleCardsRefreshPending = false
local function ScheduleMiddleCardsRefresh()
    if middleCardsRefreshPending then return end
    middleCardsRefreshPending = true
    C_Timer.After(0.05, function()
        middleCardsRefreshPending = false
        if ns.MainFrame and ns.MainFrame:IsShown() and ns.RefreshMiddleCards then
            ns:RefreshMiddleCards()
        end
    end)
end

function ns.AutoRouting:EquipPetAndSyncSkills(slotIndex, petID, explicitAbilities)
    if not slotIndex or not petID then return end
    if InCombatLockdown() or (C_PetBattles and C_PetBattles.IsInBattle()) then return end

    local speciesID = C_PetJournal.GetPetInfoByPetID(petID)
    if not speciesID or speciesID <= 0 then return end

    slotEquipTokens[slotIndex] = (slotEquipTokens[slotIndex] or 0) + 1
    local myToken = slotEquipTokens[slotIndex]

    local rawAbilities = nil
    if explicitAbilities and (explicitAbilities[1] or 0) > 0 then
        rawAbilities = explicitAbilities
    else
        local curTeam = ns.db.teams[ns.db.selectedTeamIdx]
        if not ns.staging.isDirty and curTeam and curTeam.speciesLoadout and curTeam.speciesLoadout[slotIndex] == speciesID and curTeam.abilities and curTeam.abilities[slotIndex] and (curTeam.abilities[slotIndex][1] or 0) > 0 then
            rawAbilities = curTeam.abilities[slotIndex]
        elseif ns.db.slotSpeciesMemory and ns.db.slotSpeciesMemory[slotIndex] and ns.db.slotSpeciesMemory[slotIndex][speciesID] then
            rawAbilities = ns.db.slotSpeciesMemory[slotIndex][speciesID]
        end
    end

    local validAbilities = rawAbilities and self:ValidateAbilitiesForSpecies(speciesID, rawAbilities) or nil

    if C_PetJournal.GetPetLoadOutInfo(slotIndex) ~= petID then
        ns._equippingUntil = GetTime() + 0.55
        C_PetJournal.SetPetLoadOutInfo(slotIndex, petID)
    end

    local function ApplyVerifiedAbilities()
        if slotEquipTokens[slotIndex] ~= myToken then return false end
        if InCombatLockdown() or (C_PetBattles and C_PetBattles.IsInBattle()) then return false end
        local changed = false
        local currentSlottedID, ca1, ca2, ca3 = C_PetJournal.GetPetLoadOutInfo(slotIndex)
        if currentSlottedID ~= petID then
            ns._equippingUntil = GetTime() + 0.55
            C_PetJournal.SetPetLoadOutInfo(slotIndex, petID)
            changed = true
        end

        if currentSlottedID ~= petID then
            currentSlottedID, ca1, ca2, ca3 = C_PetJournal.GetPetLoadOutInfo(slotIndex)
            if currentSlottedID ~= petID then return changed end
        end
        if validAbilities then
            local t1, t2, t3 = validAbilities[1], validAbilities[2], validAbilities[3]
            if t1 and t1 > 0 and (ca1 or 0) ~= t1 then ns._equippingUntil = GetTime() + 0.55; C_PetJournal.SetAbility(slotIndex, 1, t1); changed = true end
            if t2 and t2 > 0 and (ca2 or 0) ~= t2 then ns._equippingUntil = GetTime() + 0.55; C_PetJournal.SetAbility(slotIndex, 2, t2); changed = true end
            if t3 and t3 > 0 and (ca3 or 0) ~= t3 then ns._equippingUntil = GetTime() + 0.55; C_PetJournal.SetAbility(slotIndex, 3, t3); changed = true end
            ns.AutoRouting:RememberSlotSpeciesSkills(slotIndex, speciesID, validAbilities)
        elseif ca1 and ca1 > 0 then
            ns.AutoRouting:RememberSlotSpeciesSkills(slotIndex, speciesID, { ca1, ca2 or 0, ca3 or 0 })
        end
        return changed
    end

    ApplyVerifiedAbilities()
    C_Timer.After(0.15, function()
        if slotEquipTokens[slotIndex] == myToken then
            ApplyVerifiedAbilities()
            ScheduleMiddleCardsRefresh()
        end
    end)
    C_Timer.After(0.40, function()
        if slotEquipTokens[slotIndex] == myToken then
            ApplyVerifiedAbilities()
            ScheduleMiddleCardsRefresh()
        end
    end)
end

function ns.AutoRouting:CancelPendingSlotEquip(slot)
    slotEquipTokens[slot] = slotEquipTokens[slot] + 1
end

function ns.AutoRouting:ClearLoadoutSlot(slot)
    local current, _, _, _, locked = C_PetJournal.GetPetLoadOutInfo(slot)
    if not current or locked then return end
    self:CancelPendingSlotEquip(slot)
    ns._equippingUntil = GetTime() + 0.55
    -- Try the empty GUID first and verify before trying nil.
    pcall(C_PetJournal.SetPetLoadOutInfo, slot, "BattlePet-0-000000000000")
    if C_PetJournal.GetPetLoadOutInfo(slot) == current then
        pcall(C_PetJournal.SetPetLoadOutInfo, slot, nil)
    end
end

function ns.AutoRouting:SetManualLoadoutAbility(slot, col, abilityID)
    ns:EnsureTeamBackup()
    ns._equippingUntil = GetTime() + 0.55
    C_PetJournal.SetAbility(slot, col, abilityID)
    if select(col + 1, C_PetJournal.GetPetLoadOutInfo(slot)) ~= abilityID then return false end
    slotEquipTokens[slot] = slotEquipTokens[slot] + 1
    return true
end

function ns.AutoRouting:SwapLoadoutPets(source, target, petID)
    if source == target or InCombatLockdown() or (C_PetBattles and C_PetBattles.IsInBattle()) then return false end
    local sourceID, s1, s2, s3, sourceLocked = C_PetJournal.GetPetLoadOutInfo(source)
    local targetID, t1, t2, t3, targetLocked = C_PetJournal.GetPetLoadOutInfo(target)
    if sourceLocked or targetLocked or sourceID ~= petID or targetID == sourceID then return false end

    -- The journal exchanges the two slots when the pet is already slotted.
    ns._equippingUntil = GetTime() + 0.55
    C_PetJournal.SetPetLoadOutInfo(target, sourceID)
    if C_PetJournal.GetPetLoadOutInfo(target) ~= sourceID then return false end

    ns:EnsureTeamBackup()
    ns.staging.isDirty = true
    ns:MarkHomeSlotChanged(source)
    ns:MarkHomeSlotChanged(target)
    local team = ns.db.teams[ns.db.selectedTeamIdx]
    if team then
        local levelingSlot = team.levelingSlot or ns.db.settings.levelingSlot or 2
        if team.hasLevelingSlot and (levelingSlot == source or levelingSlot == target) then
            team.levelingSlot = (levelingSlot == source) and target or source
        end
        if team.slotThresholds then
            team.slotThresholds[source], team.slotThresholds[target] = team.slotThresholds[target], team.slotThresholds[source]
        end
        if team.randomSlots then
            team.randomSlots[source], team.randomSlots[target] = team.randomSlots[target], team.randomSlots[source]
        end
    end

    -- Invalidate any pending equip for the source, including when it is now empty.
    slotEquipTokens[source] = slotEquipTokens[source] + 1
    self:EquipPetAndSyncSkills(target, sourceID, { s1, s2, s3 })
    if targetID and C_PetJournal.GetPetLoadOutInfo(source) == targetID then
        self:EquipPetAndSyncSkills(source, targetID, { t1, t2, t3 })
    end
    return true
end

-- Resolve specific families before unrestricted slots so ZR0 cannot take
-- the only pet available for a typed slot.
local function ResolveRandomSlots(team, levelingSlot, usedPets, requireHealthy, selected, evaluation)
    local slots = {}
    selected = selected or {}
    for slot = 1, 3 do
        local family = team.randomSlots and team.randomSlots[slot]
        if family ~= nil and not selected[slot] and not (team.hasLevelingSlot and slot == levelingSlot) then
            slots[#slots + 1] = { index = slot, family = tonumber(family) or 0 }
        end
    end
    if #slots == 0 then return selected end

    table.sort(slots, function(a, b)
        if (a.family == 0) ~= (b.family == 0) then return a.family ~= 0 end
        return a.index < b.index
    end)

    -- One flat snapshot per synchronous evaluation avoids a table per owned pet.
    -- Keep owned-ID order, nil fields and the original reservoir sampling calls.
    -- Each record occupies five slots: ID, family, level, health, maxHealth.
    local candidates = evaluation and evaluation.randomCandidates
    if not candidates then
        candidates = { count = 0 }
        for _, petID in ipairs(C_PetJournal.GetOwnedPetIDs() or {}) do
            local speciesID, _, level, _, _, _, _, _, _, family, _, _, _, _, canBattle = C_PetJournal.GetPetInfoByPetID(petID)
            if speciesID and canBattle then
                local hp, maxHP = C_PetJournal.GetPetStats(petID)
                if hp and hp > 0 then
                    local offset = candidates.count * 5
                    candidates[offset + 1] = petID
                    candidates[offset + 2] = family
                    candidates[offset + 3] = level or 1
                    candidates[offset + 4] = hp
                    candidates[offset + 5] = maxHP
                    candidates.count = candidates.count + 1
                end
            end
        end
        if evaluation then evaluation.randomCandidates = candidates end
    end

    for _, slot in ipairs(slots) do
        local threshold = ns:GetSlotThreshold(team, slot.index)
        local bestScore, best, ties = -1, nil, 0
        for offset = 1, candidates.count * 5, 5 do
            local petID = candidates[offset]
            if not usedPets[petID] and (slot.family == 0 or candidates[offset + 1] == slot.family) then
                local healthy = ns:IsPetHealthyForLoadout(candidates[offset + 3], candidates[offset + 4], threshold)
                if healthy or not requireHealthy then
                    local score = candidates[offset + 2] * 2 + (healthy and 1 or 0)
                    if score > bestScore then
                        bestScore, best, ties = score, petID, 1
                    elseif score == bestScore then
                        ties = ties + 1
                        if math.random(ties) == 1 then best = petID end
                    end
                end
            end
        end
        if best then
            selected[slot.index] = best
            usedPets[best] = true
        end
    end
    return selected
end

local scratchUsedPets = {}

function ns.AutoRouting:FindSlotBackup(team, slot, usedPets, threshold, requireHealthy)
    local list = team.slotBackups and team.slotBackups[slot]
    if not list then return nil end
    for _, entry in ipairs(list) do
        local ids, levels = ns:GetSortedPetAbilities(entry.speciesID)
        local function usable(petID)
            if not petID or usedPets[petID] then return false end
            local species, _, level = C_PetJournal.GetPetInfoByPetID(petID)
            if species ~= entry.speciesID then return false end
            local hp, maxHp = C_PetJournal.GetPetStats(petID)
            if not ((requireHealthy and ns:IsPetHealthyForLoadout(hp, maxHp, threshold)) or (not requireHealthy and hp and hp > 0)) then return false end
            for col = 1, 3 do
                local wanted = entry.abilities and entry.abilities[col]
                if wanted and wanted > 0 then
                    local first, second = ids and ids[col], ids and ids[col + 3]
                    local index = wanted == first and col or wanted == second and col + 3 or nil
                    if not index or (levels and levels[index] and (level or 0) < levels[index]) then return false end
                end
            end
            return true
        end
        if usable(entry.petID) then return entry.petID, entry.abilities end
        local cache = ns.GetPetJournalCache and ns:GetPetJournalCache()
        local candidates = cache and cache.bySpecies[entry.speciesID]
        if candidates then
            for i = 1, #candidates do
                if usable(candidates[i]) then return candidates[i], entry.abilities end
            end
        end
    end
end

function ns.AutoRouting:CanTeamFight(team, requireHealthy, evaluation)
    if not team then return false end
    wipe(scratchUsedPets)
    local lvSlot = team.levelingSlot or ns.db.settings.levelingSlot or 2
    local levelingActive = team.hasLevelingSlot and ns.Leveling:GetManualQueueCount() > 0

    for slot = 1, 3 do
        local slotTh = ns:GetSlotThreshold(team, slot)

        if team.hasLevelingSlot and slot == lvSlot then
            if levelingActive and not ns.Leveling:HasLivingQueuePet(evaluation) then
                return false
            elseif not levelingActive then
                local petID = ns.Leveling:GetSlotFallback(team, slot, scratchUsedPets)
                if not petID then return false end
                local hp, maxHp = C_PetJournal.GetPetStats(petID)
                if requireHealthy and not ns:IsPetHealthyForLoadout(hp, maxHp, slotTh)
                    or not requireHealthy and (not hp or hp <= 0) then return false end
                scratchUsedPets[petID] = true
            end
        elseif not (team.randomSlots and team.randomSlots[slot] ~= nil) then
            local savedPetID = team.pets and team.pets[slot]
            local spID = (team.speciesLoadout and team.speciesLoadout[slot]) or 0
            if savedPetID and savedPetID ~= "LEVELING" and spID == 0 then
                spID = C_PetJournal.GetPetInfoByPetID(savedPetID) or 0
            end

            if spID > 0 then
                local slotReady = false
                if savedPetID and savedPetID ~= "LEVELING" and not scratchUsedPets[savedPetID] then
                    local hp, maxHp = C_PetJournal.GetPetStats(savedPetID)
                    if requireHealthy then
                        if ns:IsPetHealthyForLoadout(hp, maxHp, slotTh) then
                            slotReady = true
                            scratchUsedPets[savedPetID] = true
                        end
                    else
                        if hp and hp > 0 then
                            slotReady = true
                            scratchUsedPets[savedPetID] = true
                        end
                    end
                end
                if not slotReady and ns.db.settings.autoSwapHealthyDup ~= false then
                    local dupID = self:FindBestHealthyDuplicate(spID, scratchUsedPets, slotTh, not requireHealthy)
                    if dupID then
                        slotReady = true
                        scratchUsedPets[dupID] = true
                    end
                end
                if not slotReady then
                    local backupID = self:FindSlotBackup(team, slot, scratchUsedPets, slotTh, requireHealthy)
                    if backupID then
                        slotReady = true
                        scratchUsedPets[backupID] = true
                    end
                end
                if not slotReady then
                    return false
                end
            end
        end
    end

    if team.randomSlots and next(team.randomSlots) then
        local randomPets = ResolveRandomSlots(team, lvSlot, scratchUsedPets, requireHealthy, nil, evaluation)
        for slot = 1, 3 do
            if team.randomSlots[slot] ~= nil and not (team.hasLevelingSlot and slot == lvSlot) and not randomPets[slot] then
                return false
            end
        end
    end
    return true
end

local applyUsedPetsScratch = {}
local teamEquipRevision = 0
local randomPetsByTeam = setmetatable({}, { __mode = "k" })
local randomSlotWarningTeam, randomSlotWarningSlots

function ns.AutoRouting:GetResolvedRandomPet(team, slot)
    local resolved = randomPetsByTeam[team]
    return resolved and resolved[slot]
end

function ns.AutoRouting:ApplyTeamData(team, requireHealthyRandom, evaluation, deferRefresh, restoreOriginal)
    if not team or InCombatLockdown() or (C_PetBattles and C_PetBattles.IsInBattle()) then return end

    ns.staging.isDirty = false
    ns.staging.teamBackup = nil
    ns.staging.backupTeamIdx = nil
    ns.staging.manualAbilities = nil
    ns.staging.changedSlots = nil
    ns.staging.backupSlotDefaults = nil
    ns.staging.backupLoadout = nil

    teamEquipRevision = teamEquipRevision + 1
    local revision = teamEquipRevision
    for slot = 1, 3 do
        slotEquipTokens[slot] = slotEquipTokens[slot] + 1
    end
    local plannedPets, plannedAbilities = {}, {}
    wipe(applyUsedPetsScratch)
    local lvSlot = team.levelingSlot or ns.db.settings.levelingSlot or 2
    local restoredLoadout = ns.staging.revertLoadout
    ns.staging.revertLoadout = nil

    if not team.manualAbilities and team.script and team.script ~= "" and team.speciesLoadout and team.abilities and syncedScriptByTeam[team] ~= team.script then
        syncedScriptByTeam[team] = team.script
        local scriptAbSet = nil
        for idStr in string.gmatch(team.script, ":(%d+)%)") do
            local numID = tonumber(idStr)
            if numID then
                if not scriptAbSet then scriptAbSet = {} end
                scriptAbSet[numID] = true
            end
        end
        if scriptAbSet then
            for s = 1, 3 do
                local spID = team.speciesLoadout[s]
                if spID and spID > 0 then
                    local sortedIDs = ns:GetSortedPetAbilities(spID)
                    if sortedIDs and #sortedIDs >= 6 then
                        team.abilities[s] = self:ValidateAbilitiesForSpecies(spID, team.abilities[s])
                        for abIdx = 1, 3 do
                            local t1 = sortedIDs[abIdx]
                            local t2 = sortedIDs[abIdx + 3]
                            if scriptAbSet[t2] and not scriptAbSet[t1] then
                                team.abilities[s][abIdx] = t2
                            elseif scriptAbSet[t1] and not scriptAbSet[t2] then
                                team.abilities[s][abIdx] = t1
                            end
                        end
                    end
                end
            end
        end
    end

    for slot = 1, 3 do
        local slotTh = ns:GetSlotThreshold(team, slot)
        if team.hasLevelingSlot and slot == lvSlot then
            local lvPetID = ns.Leveling:AssignTopPetToLevelingSlot(slot)
            if lvPetID then applyUsedPetsScratch[lvPetID] = true end
        elseif not (team.randomSlots and team.randomSlots[slot] ~= nil) then
            local savedPetID = team.pets and team.pets[slot]
            local targetSpeciesID = (team.speciesLoadout and team.speciesLoadout[slot]) or 0
            if savedPetID and savedPetID ~= "LEVELING" and targetSpeciesID == 0 then
                targetSpeciesID = C_PetJournal.GetPetInfoByPetID(savedPetID) or 0
            end

            local finalPetID = nil

            if restoreOriginal and savedPetID and savedPetID ~= "LEVELING" and not applyUsedPetsScratch[savedPetID]
                and C_PetJournal.GetPetInfoByPetID(savedPetID) == targetSpeciesID then
                finalPetID = savedPetID
            end

            if not finalPetID and savedPetID and savedPetID ~= "LEVELING" and not applyUsedPetsScratch[savedPetID] then
                local hp, maxHp = C_PetJournal.GetPetStats(savedPetID)
                if hp and hp > 0 then
                    if ns.db.settings.autoSwapHealthyDup == false or ns:IsPetHealthyForLoadout(hp, maxHp, slotTh) then
                        finalPetID = savedPetID
                    end
                end
            end

            if not finalPetID and targetSpeciesID > 0 then
                finalPetID = self:FindBestHealthyDuplicate(targetSpeciesID, applyUsedPetsScratch, slotTh, false)

                if not finalPetID then
                    finalPetID, plannedAbilities[slot] = self:FindSlotBackup(team, slot, applyUsedPetsScratch, slotTh, true)
                end

                if not finalPetID then
                    if savedPetID and savedPetID ~= "LEVELING" and not applyUsedPetsScratch[savedPetID] then
                        local hp = C_PetJournal.GetPetStats(savedPetID)
                        if hp and hp > 0 then
                            finalPetID = savedPetID
                        end
                    end
                end
                if not finalPetID then
                    finalPetID = self:FindBestHealthyDuplicate(targetSpeciesID, applyUsedPetsScratch, slotTh, true)
                end
                if not finalPetID then
                    finalPetID, plannedAbilities[slot] = self:FindSlotBackup(team, slot, applyUsedPetsScratch, slotTh, false)
                end
                if not finalPetID then
                    finalPetID = self:FindAnyCollectedPetForSpecies(targetSpeciesID, applyUsedPetsScratch)
                end
            end

            if not finalPetID and savedPetID and savedPetID ~= "LEVELING" and C_PetJournal.GetPetInfoByPetID(savedPetID) then
                finalPetID = savedPetID
            end

            if finalPetID then
                applyUsedPetsScratch[finalPetID] = true
                plannedPets[slot] = finalPetID
            end
        end
    end

    evaluation = evaluation or {}
    local randomPets = ResolveRandomSlots(team, lvSlot, applyUsedPetsScratch, requireHealthyRandom, nil, evaluation)
    if requireHealthyRandom then
        -- A queue pet may have taken a candidate between the readiness check and loading.
        for slot = 1, 3 do
            if team.randomSlots and team.randomSlots[slot] ~= nil and not randomPets[slot]
                and not (team.hasLevelingSlot and slot == lvSlot) then
                randomPets = ResolveRandomSlots(team, lvSlot, applyUsedPetsScratch, false, randomPets, evaluation)
                break
            end
        end
    end
    randomPetsByTeam[team] = randomPets
    local missingRandomSlots = {}
    for slot = 1, 3 do
        local randomSlot = team.randomSlots and team.randomSlots[slot] ~= nil and not (team.hasLevelingSlot and slot == lvSlot)
        local petID = randomSlot and randomPets[slot] or plannedPets[slot]
        local restored = restoredLoadout and restoredLoadout[slot]
        local leveling = team.hasLevelingSlot and slot == lvSlot
        if restored and not leveling then petID = restored.petID end
        if petID then
            local abilities = restored and restored.abilities or plannedAbilities[slot] or not randomSlot and team.abilities and team.abilities[slot] or nil
            if slot == 1 then
                self:EquipPetAndSyncSkills(slot, petID, abilities)
            else
                local expectedToken = slotEquipTokens[slot]
                C_Timer.After((slot - 1) * 0.06, function()
                    if revision == teamEquipRevision and slotEquipTokens[slot] == expectedToken then
                        self:EquipPetAndSyncSkills(slot, petID, abilities)
                        ScheduleMiddleCardsRefresh()
                    end
                end)
            end
        elseif randomSlot then
            missingRandomSlots[#missingRandomSlots + 1] = slot
        elseif (team.explicitSlots or restored) and not leveling then
            self:ClearLoadoutSlot(slot)
        end
    end
    local missingSlots = table.concat(missingRandomSlots, ", ")
    if missingSlots ~= "" and (randomSlotWarningTeam ~= team or randomSlotWarningSlots ~= missingSlots) then
        ns:PrintError(ns:TF("随机槽位 %s 没有符合类型的可用存活宠物。", missingSlots))
    end
    randomSlotWarningTeam = missingSlots ~= "" and team or nil
    randomSlotWarningSlots = missingSlots

    if not deferRefresh and ns.RefreshAllUI then ns:RefreshAllUI() end
end

-- O(1) 队伍名称索引与未绑定队伍基底名索引，配合脏标记彻底消除切目标全表扫描
local syncRouteByID        = {}
local syncRouteByNameLower = {}
local syncValidTeams       = {}
local syncTeamIdxByName    = {}
local unboundTeamsByBase   = {}
local unboundListPool      = {} -- bounded free-list, never keyed by historical names
local MAX_UNBOUND_FREE_LISTS = 32

function ns.AutoRouting:FindTeamByName(teamName)
    if not teamName or teamName == "" or not ns.db or not ns.db.teams then return nil, nil end
    local cachedIdx = syncTeamIdxByName[teamName]
    if cachedIdx then
        local t = ns.db.teams[cachedIdx]
        if t and t.name == teamName then
            return t, cachedIdx
        end
    end
    for idx, team in ipairs(ns.db.teams) do
        if team.name == teamName then
            syncTeamIdxByName[teamName] = idx
            return team, idx
        end
    end
    return nil, nil
end

function ns.AutoRouting:FindRouteForTarget(npcID, npcName)
    npcID = (not ns:IsSecretValue(npcID)) and tonumber(npcID) or nil
    npcName = (not ns:IsSecretValue(npcName) and type(npcName) == "string") and strtrim(npcName) or nil
    if (not npcID or npcID <= 0) and (not npcName or npcName == "") then
        return nil, nil
    end

    self:SyncTargetGroups()
    local route, key = ns:FindExistingRouteForNPC(npcID, npcName)

    if not route and npcName and npcName ~= "" then
        local targetBase = strlower(ns:ExtractBaseTargetName(npcName))
        local unboundMatches = (targetBase ~= "") and unboundTeamsByBase[targetBase] or nil
        if unboundMatches and #unboundMatches > 0 then
            local matchedCopy = {}
            for i = 1, #unboundMatches do
                matchedCopy[i] = unboundMatches[i]
            end
            local resolvedID = npcID or 0
            key = (resolvedID > 0) and tostring(resolvedID) or npcName
            route = {
                npcID = resolvedID,
                npcName = npcName,
                teamName = matchedCopy[1],
                teams = matchedCopy,
                gossipIndex = 1,
                reviveLoadTeam1 = true,
            }
            ns.db.routeMappings = ns.db.routeMappings or {}
            ns.db.routeMappings[key] = route
            ns:MarkRoutesDirty()
            ns:RegisterRouteInIndex(key, route)
        end
    end

    if route then
        local updatedMeta = false
        if npcID and npcID > 0 and (not route.npcID or route.npcID == 0) then
            route.npcID = npcID
            updatedMeta = true
        end
        if npcName and npcName ~= "" and (not route.npcName or route.npcName == "" or route.npcName == tostring(route.npcID)) then
            route.npcName = npcName
            updatedMeta = true
        end
        if updatedMeta then
            ns:RegisterRouteInIndex(key, route)
        end
        ns.db.lastActiveRouteKey = key
    end
    return route, key
end

local lastScenarioSig

local function IndexSingleRoute(rKey, route)
    local rID = tonumber(route.npcID) or tonumber(rKey) or 0
    if rID > 0 and not syncRouteByID[rID] then
        syncRouteByID[rID] = route
    end
    local kLower = strlower(tostring(rKey))
    if kLower ~= "" and not syncRouteByNameLower[kLower] then
        syncRouteByNameLower[kLower] = route
    end
    if route.npcName and route.npcName ~= "" then
        local nLower = strlower(strtrim(route.npcName))
        local bLower = strlower(ns:ExtractBaseTargetName(route.npcName))
        if nLower ~= "" and not syncRouteByNameLower[nLower] then
            syncRouteByNameLower[nLower] = route
        end
        if bLower ~= "" and not syncRouteByNameLower[bLower] then
            syncRouteByNameLower[bLower] = route
        end
    end
end

function ns.AutoRouting:SyncTargetGroups()
    if not ns.db then return end
    ns.db.routeMappings = ns.db.routeMappings or {}

    local teamCount = ns.db.teams and #ns.db.teams or 0
    if not ns._routesDirty and ns._lastSyncedTeamCount == teamCount then
        return
    end

    lastScenarioSig = nil
    wipe(syncRouteByID)
    wipe(syncRouteByNameLower)
    wipe(syncValidTeams)
    wipe(syncTeamIdxByName)
    for k, list in pairs(unboundTeamsByBase) do
        wipe(list)
        if #unboundListPool < MAX_UNBOUND_FREE_LISTS then
            unboundListPool[#unboundListPool + 1] = list
        end
        unboundTeamsByBase[k] = nil
    end

    for rKey, route in pairs(ns.db.routeMappings) do
        IndexSingleRoute(rKey, route)
    end

    local routeMembers = {}
    for idx, t in ipairs(ns.db.teams or {}) do
        if t.name then
            syncValidTeams[t.name]    = t
            syncTeamIdxByName[t.name] = idx

            local tID = tonumber(t.npcID) or 0
            local tNpcName = strtrim(t.npcName or "")
            if tID > 0 or tNpcName ~= "" then
                local existRoute = (tID > 0 and syncRouteByID[tID]) or nil
                if not existRoute and tNpcName ~= "" then
                    local lowerN = strlower(tNpcName)
                    local lowerB = strlower(ns:ExtractBaseTargetName(tNpcName))
                    existRoute = syncRouteByNameLower[lowerN] or (lowerB ~= "" and syncRouteByNameLower[lowerB])
                end
                if not existRoute then
                    local rKey = (tID > 0) and tostring(tID) or tNpcName
                    local newRoute = {
                        npcID = tID,
                        npcName = (tNpcName ~= "") and tNpcName or ns:ExtractBaseTargetName(t.name),
                        teamName = t.name,
                        teams = { t.name },
                        gossipIndex = t.gossipIndex or 1,
                        reviveLoadTeam1 = true,
                    }
                    ns.db.routeMappings[rKey] = newRoute
                    IndexSingleRoute(rKey, newRoute)
                else
                    existRoute.teams = existRoute.teams or (existRoute.teamName and existRoute.teamName ~= "" and { existRoute.teamName } or {})
                    local members = routeMembers[existRoute]
                    if not members then
                        members = {}
                        for i = 1, #existRoute.teams do members[existRoute.teams[i]] = true end
                        routeMembers[existRoute] = members
                    end
                    if not members[t.name] then
                        members[t.name] = true
                        existRoute.teams[#existRoute.teams + 1] = t.name
                        existRoute.teamName = existRoute.teams[1] or t.name
                    end
                end
            else
                local baseLower = strlower(ns:ExtractBaseTargetName(t.name))
                if baseLower ~= "" then
                    local list = unboundTeamsByBase[baseLower]
                    if not list then
                        local freeIndex = #unboundListPool
                        list = unboundListPool[freeIndex] or {}
                        unboundListPool[freeIndex] = nil
                        unboundTeamsByBase[baseLower] = list
                    end
                    list[#list + 1] = t.name
                end
            end
        end
    end

    local checkedMembers = {}
    for _, route in pairs(ns.db.routeMappings) do
        wipe(checkedMembers)
        if route.reviveLoadTeam1 == nil then
            route.reviveLoadTeam1 = true
        end
        if not route.teams then
            route.teams = (route.teamName and route.teamName ~= "") and { route.teamName } or {}
        end

        local needsClean = false
        for i = 1, #route.teams do
            local tn = route.teams[i]
            local tObj = syncValidTeams[tn]
            if not tObj then
                needsClean = true
                break
            end
            if checkedMembers[tn] then
                needsClean = true
                break
            end
            checkedMembers[tn] = true
            if not tObj.rematchSourceKey or not syncRouteByID[tonumber(tObj.npcID) or 0] or tObj.npcID == route.npcID then
                tObj.npcID = route.npcID or tObj.npcID or 0
                tObj.npcName = route.npcName or ""
            end
        end

        if needsClean then
            local cleaned = {}
            local seen = {}
            for _, tn in ipairs(route.teams) do
                local tObj = syncValidTeams[tn]
                if tObj and not seen[tn] then
                    seen[tn] = true
                    cleaned[#cleaned + 1] = tn
                    if not tObj.rematchSourceKey or not syncRouteByID[tonumber(tObj.npcID) or 0] or tObj.npcID == route.npcID then
                        tObj.npcID = route.npcID or tObj.npcID or 0
                        tObj.npcName = route.npcName or ""
                    end
                end
            end
            route.teams = cleaned
        end
        route.teamName = route.teams[1] or ""
    end

    ns._routeRevision = (ns._routeRevision or 0) + 1
    ns._routesDirty         = false
    ns._lastSyncedTeamCount = teamCount
    ns._routeIndexDirty     = true
    ns:EnsureRouteLookupIndex()
end

function ns.AutoRouting:IsCurrentLoadoutHealthyAndReady(team)
    if not team then return false end
    local lvSlot = team.levelingSlot or ns.db.settings.levelingSlot or 2
    local levelingActive = team.hasLevelingSlot and ns.Leveling:GetManualQueueCount() > 0
    for slot = 1, 3 do
        local petID = C_PetJournal.GetPetLoadOutInfo(slot)
        if not petID then return false end
        local hp, maxHp = C_PetJournal.GetPetStats(petID)
        local slotTh = ns:GetSlotThreshold(team, slot)
        if not ns:IsPetHealthyForLoadout(hp, maxHp, slotTh) then
            return false
        end
        if team.hasLevelingSlot and slot == lvSlot then
            if levelingActive then
                if not ns.Leveling:IsPetInQueue(petID) then return false end
            elseif ns.Leveling:GetSlotFallback(team, slot) ~= petID then
                return false
            end
        elseif team.randomSlots and team.randomSlots[slot] ~= nil then
            if self:GetResolvedRandomPet(team, slot) ~= petID then return false end
        else
            local expectedSpID = team.speciesLoadout and tonumber(team.speciesLoadout[slot]) or 0
            if expectedSpID > 0 then
                local curSpID = C_PetJournal.GetPetInfoByPetID(petID) or 0
                if curSpID ~= expectedSpID then
                    local matched = false
                    local list = team.slotBackups and team.slotBackups[slot]
                    if list then
                        for _, entry in ipairs(list) do
                            if entry.speciesID == curSpID then matched = true; break end
                        end
                    end
                    if not matched then return false end
                end
            end
        end
    end
    return true
end

-- 阶段目标只从当前未完成条件和已有目标绑定读取，扫描过程不写入路由。
local lastScenarioStep
local lastScenarioMatches = {}
local lastScenarioRouteRevision
local EMPTY_MATCHES = {}

local function IsInScenario()
    return C_Scenario and C_Scenario.IsInScenario and C_Scenario.IsInScenario()
end

local function ResetScenarioSelection()
    lastScenarioStep, lastScenarioSig = nil, nil
    wipe(lastScenarioMatches)
    lastScenarioRouteRevision = nil
    if ns.db then ns.db.lastManualDungeonRouteKey = nil end
end

local function ReadScenarioStep()
    if C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo then
        local ok, info = pcall(C_ScenarioInfo.GetScenarioStepInfo)
        if ok and type(info) == "table" and not ns:IsSecretValue(info.numCriteria) then
            local step = not ns:IsSecretValue(info.stepID) and info.stepID or nil
            if step == nil and not ns:IsSecretValue(info.title) then step = info.title end
            return tonumber(info.numCriteria) or 0, step
        end
    end
    if C_Scenario.GetStepInfo then
        local ok, title, _, count = pcall(C_Scenario.GetStepInfo)
        if ok and not ns:IsSecretValue(count) then
            return tonumber(count) or 0, not ns:IsSecretValue(title) and title or nil
        end
    end
    return 0
end

local function ReadScenarioCriterion(index)
    if C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo then
        local ok, info = pcall(C_ScenarioInfo.GetCriteriaInfo, index)
        if ok and type(info) == "table" then return info.description, info.completed end
    end
    if C_Scenario.GetCriteriaInfo then
        local ok, desc, _, completed = pcall(C_Scenario.GetCriteriaInfo, index)
        if ok then return desc, completed end
    end
end

local function NormalizeScenarioNPCName(text)
    text = strlower(strtrim(text or ""))
    text = text:gsub("·", ""):gsub("•", ""):gsub("・", "")
    return (text:gsub("[%s%.]", ""))
end

local function ScenarioTextContainsName(text, name)
    text, name = NormalizeScenarioNPCName(text), NormalizeScenarioNPCName(name)
    if name == "" then return false end
    local startAt = 1
    while true do
        local first, last = string.find(text, name, startAt, true)
        if not first then return false end
        local joinsStart = name:match("^[%w_]") and text:sub(first - 1, first - 1):match("[%w_]")
        local joinsEnd = name:match("[%w_]$") and text:sub(last + 1, last + 1):match("[%w_]")
        if not joinsStart and not joinsEnd then return true end
        startAt = last + 1
    end
end

function ns.AutoRouting:GetScenarioStageMatches()
    if not IsInScenario() or not ns.db then
        ResetScenarioSelection()
        return EMPTY_MATCHES
    end

    local count, step = ReadScenarioStep()
    if step and step ~= lastScenarioStep then
        lastScenarioStep, lastScenarioSig = step, nil
        ns.db.lastManualDungeonRouteKey = nil
    end
    local activeDescs = {}
    for i = 1, count do
        local desc, done = ReadScenarioCriterion(i)
        if not ns:IsSecretValue(done) and not done and not ns:IsSecretValue(desc) and type(desc) == "string" then
            local label = strtrim(desc)
            if label ~= "" then activeDescs[#activeDescs + 1] = strlower(label) end
        end
    end
    if #activeDescs == 0 then
        lastScenarioSig = nil
        return EMPTY_MATCHES
    end

    self:SyncTargetGroups()
    local sig = table.concat(activeDescs, "\1")
    local revision = ns._routeRevision or 0
    if sig == lastScenarioSig and revision == lastScenarioRouteRevision then return lastScenarioMatches end

    local matches = {}
    for key, route in pairs(ns.db.routeMappings or {}) do
        local label = type(route.npcName) == "string" and strtrim(route.npcName) or ""
        if #label >= 3 and not label:match("^%d+$") and route.teams and #route.teams > 0 then
            local name = strlower(label)
            for i, desc in ipairs(activeDescs) do
                if ScenarioTextContainsName(desc, name)
                    or (route.scenarioCriterion and NormalizeScenarioNPCName(desc) == NormalizeScenarioNPCName(route.scenarioCriterion)) then
                    matches[#matches + 1] = {key = key, route = route, label = label, criterionIndex = i}
                    break
                end
            end
        end
    end
    table.sort(matches, function(a, b)
        if a.criterionIndex ~= b.criterionIndex then return a.criterionIndex < b.criterionIndex end
        if a.label ~= b.label then return a.label < b.label end
        return tostring(a.key) < tostring(b.key)
    end)
    lastScenarioSig, lastScenarioMatches = sig, matches
    lastScenarioRouteRevision = revision
    return matches
end

local function FindCurrentScenarioMatch(matches, key)
    for _, match in ipairs(matches) do
        if match.key == key then return match end
    end
end

local function ResolveScenarioMatch(matches)
    if #matches == 1 then return matches[1] end
    return FindCurrentScenarioMatch(matches, ns.db.lastManualDungeonRouteKey)
end

function ns:UpdateDungeonStageBanner(stageMatches)
    if (C_PetBattles and C_PetBattles.IsInBattle()) or not stageMatches or #stageMatches <= 1 then
        if ns.DungeonStageBar then ns.DungeonStageBar:Hide() end
        return
    end

    local Theme = ns.Theme
    if not ns.DungeonStageBar then
        local bar = CreateFrame("Frame", "WishPetTacticsDungeonStageBar", UIParent, "BackdropTemplate")
        bar:SetSize(420, 36)
        bar:SetPoint("TOP", UIParent, "TOP", 0, -96)
        bar:SetFrameStrata("HIGH")
        bar:SetMovable(true)
        bar:SetClampedToScreen(true)
        bar:EnableMouse(true)
        bar:RegisterForDrag("LeftButton")
        bar:SetScript("OnDragStart", bar.StartMoving)
        bar:SetScript("OnDragStop", bar.StopMovingOrSizing)
        Theme:ApplyBackdrop(bar, Theme.Colors.bgPopup, Theme.Colors.borderBlue, true)

        bar.lbl = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.lbl:SetPoint("LEFT", 10, 0)
        Theme:HookLocalizedFontString(bar.lbl)
        bar.lbl:SetText(ns:T("|cff38bdf8地下城阶段:|r"))

        bar.closeBtn = Theme:CreateCloseIconButton(bar, function() bar:Hide() end)
        bar.closeBtn:SetPoint("RIGHT", -10, 0)

        bar.btns = {}
        ns.DungeonStageBar = bar
    end

    local bar = ns.DungeonStageBar
    local curTeam = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
    local count = math.min(5, #stageMatches)
    local xOff = 82

    for i = 1, math.max(count, #bar.btns) do
        local btn = bar.btns[i]
        local item = (i <= count) and stageMatches[i] or nil
        if item then
            if not btn then
                btn = Theme:CreateFlatButton(bar, 102, 24, "")
                btn:SetScript("OnClick", function(selfBtn)
                    if not selfBtn.stageItem or InCombatLockdown() or (C_PetBattles and C_PetBattles.IsInBattle())
                        or (ns.staging and ns.staging.isDirty) then return end
                    local matches = ns.AutoRouting:GetScenarioStageMatches()
                    local it = FindCurrentScenarioMatch(matches, selfBtn.stageItem.key)
                    if it then
                        ns.db.lastActiveRouteKey = it.key
                        ns.db.lastManualDungeonRouteKey = it.key
                        ns.AutoRouting:LoadTeamWithFallbackChain(it.route.teams[1], it.route)
                    end
                    ns:UpdateDungeonStageBanner(matches)
                end)
                bar.btns[i] = btn
            end
            btn.stageItem = item
            local isCur = false
            if curTeam and item.route and item.route.teams then
                for _, tn in ipairs(item.route.teams) do
                    if tn == curTeam.name then isCur = true break end
                end
            end
            if btn._lastXOff ~= xOff then
                btn._lastXOff = xOff
                btn:ClearAllPoints()
                btn:SetPoint("LEFT", bar, "LEFT", xOff, 0)
            end
            xOff = xOff + 108

            btn:SetSelected(isCur)
            btn.text:SetText((isCur and "|cff10b981● " or "") .. (item.label or item.key))
            btn:Show()
        elseif btn then
            btn.stageItem = nil
            btn:Hide()
        end
    end

    bar:SetWidth(xOff + 30)
    bar:Show()
end

local function RouteContainsTeam(route, teamName)
    if not route or not teamName then return false end
    if route.teamName == teamName then return true end
    for i = 1, #(route.teams or {}) do
        if route.teams[i] == teamName then return true end
    end
    return false
end

function ns.AutoRouting:EnsurePreparedRouteAndTeam(targetChanged)
    if not ns.db or not ns.db.settings.autoLoadTarget or InCombatLockdown()
        or (C_PetBattles and C_PetBattles.IsInBattle()) then return end
    if IsInRestrictedCombatInstance() then return end
    if (ns.staging and ns.staging.isDirty) or (ns.MainFrame and ns.MainFrame.compactDraft) then return end

    self:SyncTargetGroups()
    local currentTeam = ns.db.teams[ns.db.selectedTeamIdx]

    local npcID, npcName = self:GetUnitNPCID("target")
    local route, rKey
    if IsInScenario() then
        local matches = self:GetScenarioStageMatches()
        route, rKey = ns:FindExistingRouteForNPC(npcID, npcName)
        local directMatch = route and route.teams and #route.teams > 0
            and (FindCurrentScenarioMatch(matches, rKey) or (#matches == 0 and targetChanged))
        if directMatch then
            ns:UpdateDungeonStageBanner(nil)
        else
            ns:UpdateDungeonStageBanner(matches)
            local match = ResolveScenarioMatch(matches)
            if not match then return end
            route, rKey = match.route, match.key
        end
        ns.db.lastActiveRouteKey = rKey
        if ns.temporaryTeamActive then
            if not RouteContainsTeam(route, currentTeam and currentTeam.name) then return end
            ns.temporaryTeamActive = false
        end
    else
        route, rKey = self:FindRouteForTarget(npcID, npcName)
        ResetScenarioSelection()
        ns:UpdateDungeonStageBanner(nil)
        if ns.temporaryTeamActive then
            if not RouteContainsTeam(route, currentTeam and currentTeam.name) then return end
            ns.temporaryTeamActive = false
        end
        if not route and currentTeam and currentTeam.name then
            route, rKey = ns:FindRouteContainingTeam(currentTeam.name)
            if rKey then ns.db.lastActiveRouteKey = rKey end
        end
        if not route and ns.db.lastActiveRouteKey then
            route = ns.db.routeMappings[ns.db.lastActiveRouteKey]
        end
    end

    if route and route.teams and #route.teams > 0 then
        ns.temporaryTeamActive = false
        local targetTeam = nil
        if route.reviveLoadTeam1 ~= false and ns:IsRevivePetCooldownReady() then
            targetTeam = self:FindTeamByName(route.teams[1])
        end
        if targetTeam and ns._reviveHoldRouteKey == rKey and not ns._reviveResetPending then return end
        local resetPriority = targetTeam and ns._reviveResetPending
        if targetTeam and targetTeam == currentTeam and not resetPriority and self:IsCurrentLoadoutHealthyAndReady(currentTeam) then
            return
        end
        local loaded = self:LoadTeamWithFallbackChain(route.teams[1], route, nil, resetPriority)
        if loaded and resetPriority then ns._reviveHoldRouteKey = rKey end
        ns._reviveResetPending = nil
        return
    end

    if currentTeam then
        local resetPriority = ns._reviveResetPending
        ns._reviveResetPending = nil
        if not resetPriority and self:IsCurrentLoadoutHealthyAndReady(currentTeam) then
            return
        end
        local evaluation = {}
        if resetPriority or self:CanTeamFight(currentTeam, true, evaluation) then
            self:ApplyTeamData(currentTeam, true, evaluation, nil, resetPriority)
        else
            local curGroup = currentTeam.group or "未分组队伍"
            for idx, candTeam in ipairs(ns.db.teams) do
                if idx ~= ns.db.selectedTeamIdx and (candTeam.group or "未分组队伍") == curGroup then
                    if self:CanTeamFight(candTeam, true, evaluation) then
                        ns.db.selectedTeamIdx = idx
                        self:ApplyTeamData(candTeam, true, evaluation)
                        return
                    end
                end
            end
            self:ApplyTeamData(currentTeam, nil, evaluation)
        end
    end
end

local fallbackCandScratch = {}
local fallbackVisitedScratch = {}

local function BattleTeamSequence(team, route)
    if route and route.teams then
        for index, name in ipairs(route.teams) do
            if name == team.name then return "|cffffd100" .. index .. "|r" end
        end
    end
    local index = 0
    local group = team.group or "未分组队伍"
    for _, candidate in ipairs(ns.db.teams) do
        if (candidate.group or "未分组队伍") == group then
            index = index + 1
            if candidate == team then return "|cffffd100" .. index .. "|r" end
        end
    end
    return "|cffffd100" .. tostring(ns.db.selectedTeamIdx or 1) .. "|r"
end

function ns.AutoRouting:LoadTeamWithFallbackChain(startTeamName, routeObj, deferRefresh, resetPriority)
    if routeObj and ns._reviveHoldRouteKey and ns.db.routeMappings
        and ns.db.routeMappings[ns._reviveHoldRouteKey] == routeObj and ns:IsRevivePetCooldownReady() then
        resetPriority = true
    end
    local evaluation = {}
    wipe(fallbackCandScratch)
    wipe(fallbackVisitedScratch)

    local function AddCandidate(tName)
        if tName and tName ~= "" and not fallbackVisitedScratch[tName] then
            fallbackVisitedScratch[tName] = true
            fallbackCandScratch[#fallbackCandScratch + 1] = tName
        end
    end

    if routeObj and routeObj.teams and #routeObj.teams > 0 then
        for _, tn in ipairs(routeObj.teams) do
            AddCandidate(tn)
        end
    else
        AddCandidate(startTeamName)
    end

    if #fallbackCandScratch == 0 then return false end

    local curTeam = ns.db.teams[ns.db.selectedTeamIdx]
    local function ApplyTeamAndNotify(team, teamIndex, requireHealthy)
        local canApplyNow = not InCombatLockdown()
            and not (C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle())
        ns.db.selectedTeamIdx = teamIndex
        self:ApplyTeamData(team, requireHealthy, evaluation, deferRefresh, resetPriority and team == self:FindTeamByName(fallbackCandScratch[1]))
        if canApplyNow and team ~= curTeam and ns.ShowUIFeedback and not ns._battleEndReportPending then
            ns:ShowUIFeedback(ns:TF("已切换到 %s 号队伍", BattleTeamSequence(team, routeObj)))
        end
    end
    local checkReviveTeam1 = (routeObj ~= nil) and (routeObj.reviveLoadTeam1 ~= false)
    if checkReviveTeam1 and ns:IsRevivePetCooldownReady() then
        local team1, tIdx1 = self:FindTeamByName(fallbackCandScratch[1])
        if team1 and (resetPriority or not IsInScenario() or self:CanTeamFight(team1, true, evaluation)) then
            if not resetPriority and curTeam == team1 and self:IsCurrentLoadoutHealthyAndReady(team1) then
                return true
            end
            ApplyTeamAndNotify(team1, tIdx1, IsInScenario())
            return true
        end
    end

    local firstValidTeam, firstValidIdx = nil, nil

    for i = 1, #fallbackCandScratch do
        local team, tIdx = self:FindTeamByName(fallbackCandScratch[i])
        if team then
            if not firstValidTeam then
                firstValidTeam, firstValidIdx = team, tIdx
            end
            if self:CanTeamFight(team, true, evaluation) then
                if curTeam == team and self:IsCurrentLoadoutHealthyAndReady(team) then
                    return true
                end
                ApplyTeamAndNotify(team, tIdx, true)
                return true
            end
        end
    end

    for i = 1, #fallbackCandScratch do
        local team, tIdx = self:FindTeamByName(fallbackCandScratch[i])
        if team and self:CanTeamFight(team, false, evaluation) then
            ApplyTeamAndNotify(team, tIdx, nil)
            return true
        end
    end

    if firstValidTeam then
        ApplyTeamAndNotify(firstValidTeam, firstValidIdx, nil)
        return true
    end
    return false
end

function ns.AutoRouting:LoadTeamByName(teamName)
    return self:LoadTeamWithFallbackChain(teamName, nil)
end

function ns.AutoRouting:GetUnitNPCID(unit)
    if not unit then return nil, nil end
    local okExists, exists = pcall(UnitExists, unit)
    if not okExists or ns:IsSecretValue(exists) or not exists then
        if unit == "npc" and GossipFrame and GossipFrame:IsShown() then
            local titleFS = (GossipFrame.TitleContainer and GossipFrame.TitleContainer.TitleText) or GossipFrameTitleText
            local tText = titleFS and titleFS:GetText()
            if tText and not ns:IsSecretValue(tText) and type(tText) == "string" and strtrim(tText) ~= "" then
                return nil, strtrim(tText)
            end
        end
        return nil, nil
    end

    local okPlayer, isPlayer = pcall(UnitIsPlayer, unit)
    if okPlayer and not ns:IsSecretValue(isPlayer) and isPlayer then
        return nil, nil
    end

    local safeName = nil
    local rawName = UnitName(unit)
    if rawName ~= nil and not ns:IsSecretValue(rawName) and type(rawName) == "string" and rawName ~= "" then
        safeName = rawName
    end

    local safeNpcID = nil
    local guid = UnitGUID(unit)
    if guid and not ns:IsSecretValue(guid) and type(guid) == "string" then
        local ok, unitType, _, _, _, _, npcIDStr = pcall(strsplit, "-", guid)
        if ok and not ns:IsSecretValue(unitType) then
            if unitType == "Player" or unitType == "Pet" then
                return nil, nil
            elseif not ns:IsSecretValue(npcIDStr) and (unitType == "Creature" or unitType == "Vehicle" or unitType == "BattlePet") then
                safeNpcID = tonumber(npcIDStr)
            end
        end
    end

    if (not safeNpcID or not safeName) and C_TooltipInfo and C_TooltipInfo.GetUnit then
        local okTip, tipData = pcall(C_TooltipInfo.GetUnit, unit)
        if okTip and type(tipData) == "table" and not ns:IsSecretValue(tipData) then
            if not safeNpcID and tipData.guid and not ns:IsSecretValue(tipData.guid) and type(tipData.guid) == "string" then
                local okG, uType, _, _, _, _, idStr = pcall(strsplit, "-", tipData.guid)
                if okG and not ns:IsSecretValue(uType) and not ns:IsSecretValue(idStr) and (uType == "Creature" or uType == "Vehicle" or uType == "BattlePet") then
                    safeNpcID = tonumber(idStr)
                end
            end
            if not safeName and type(tipData.lines) == "table" and tipData.lines[1] then
                local lTxt = tipData.lines[1].leftText
                if lTxt and not ns:IsSecretValue(lTxt) and type(lTxt) == "string" and strtrim(lTxt) ~= "" then
                    safeName = strtrim(lTxt)
                end
            end
        end
    end

    if not safeName and UnitBattlePetSpeciesID then
        local okSp, spID = pcall(UnitBattlePetSpeciesID, unit)
        if okSp and spID and not ns:IsSecretValue(spID) and type(spID) == "number" and spID > 0 then
            local spName = C_PetJournal.GetPetInfoBySpeciesID(spID)
            if spName and not ns:IsSecretValue(spName) and spName ~= "" then
                safeName = spName
            end
        end
    end

    if not safeName and unit == "npc" and GossipFrame and GossipFrame:IsShown() then
        local titleFS = (GossipFrame.TitleContainer and GossipFrame.TitleContainer.TitleText) or GossipFrameTitleText
        local tText = titleFS and titleFS:GetText()
        if tText and not ns:IsSecretValue(tText) and type(tText) == "string" and strtrim(tText) ~= "" then
            safeName = strtrim(tText)
        end
    end

    return safeNpcID, safeName
end

-- Dialog IDs verified from the user's live BRD diagnostic captures.
local KNOWN_PET_BATTLE_GOSSIP = {
    [51404] = { npcID = 160207, aliases = { "瑟林·天歌", "瑟琳·天歌" } },
    [51403] = { npcID = 160209 },
    [51406] = { npcID = 160208 },
    [51407] = { npcID = 160210 },
    [51467] = { aliases = { "皮克茜·威兹" } },
    [51405] = { aliases = { "阿尔兰·心影" } },
}
local function FindKnownGossipRoute(known, npcName)
    local route, key = ns:FindExistingRouteForNPC(known.npcID, npcName)
    if not route and known.aliases then
        for _, alias in ipairs(known.aliases or {}) do
            route, key = ns:FindExistingRouteForNPC(known.npcID, alias)
            if route then break end
        end
    end
    if not route and known.aliases then
        local matchedKey
        for candidateKey, candidate in pairs(ns.db and ns.db.routeMappings or {}) do
            for _, alias in ipairs(known.aliases or {}) do
                if NormalizeScenarioNPCName(candidate.npcName) == NormalizeScenarioNPCName(alias) then
                    if matchedKey and matchedKey ~= candidateKey then return nil, nil end
                    route, key, matchedKey = candidate, candidateKey, candidateKey
                    break
                end
            end
        end
    end
    return route, key
end

-- Only explicit, user-confirmed links authorize gossip without unit identity.
local function GetExplicitGossipRoute(options, npcID, npcName)
    local links = ns.db and ns.db.gossipExplicitRouteMap
    local learned = ns.db and ns.db.gossipLearnedRouteMap
    for _, opt in ipairs(options or {}) do
        local id = opt.gossipOptionID
        if not ns:IsSecretValue(id) and (links or learned) then
            local explicitKey = links and links[id]
            local key = explicitKey or (learned and learned[id])
            local route = key and ns.db.routeMappings and ns.db.routeMappings[key]
            local routeID = route and tonumber(route.npcID) or 0
            local nameConflict = not explicitKey and npcName and route and route.npcName
                and not (npcID and npcID > 0 and routeID == npcID)
                and NormalizeScenarioNPCName(npcName) ~= NormalizeScenarioNPCName(route.npcName)
            if route and route.teams and #route.teams > 0 and not nameConflict
                and (not npcID or npcID <= 0 or routeID <= 0 or npcID == routeID) then
                return route, key, id
            end
        end
    end
end

SlashCmdList["WISHBINDDIALOG"] = function()
    local rm = ns.RoutingModal
    local key = rm and rm:IsShown() and rm.selectedKey
    local route = key and ns.db and ns.db.routeMappings and ns.db.routeMappings[key]
    if not route or not route.teams or #route.teams == 0 then
        ns:PrintError("请在目标窗口选中已绑定队伍的目标，再输入 /wpbinddialog。"); return
    end
    if not GossipFrame or not GossipFrame:IsShown() then
        ns:PrintError("请先打开要绑定的 NPC 对话窗口。"); return
    end
    local options = C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.GetOptions()
    local chosen
    for _, opt in ipairs(options or {}) do
        if not ns:IsSecretValue(opt.gossipOptionID) and opt.gossipOptionID
            and not ns:IsSecretValue(opt.name) and type(opt.name) == "string" then
            local name = strlower(opt.name)
            local isBattleOpt = KNOWN_PET_BATTLE_GOSSIP[opt.gossipOptionID] ~= nil
                or string.find(name, "对战", 1, true) ~= nil
                or string.find(name, "對戰", 1, true) ~= nil
                or string.find(name, "battle", 1, true) ~= nil
            if isBattleOpt then
                if chosen then ns:PrintError("存在多个开战选项，未建立关联。"); return end
                chosen = opt.gossipOptionID
            end
        end
    end
    if not chosen then ns:PrintError("未找到可读取的“开启宠物对战。”选项，未建立关联。"); return end
    local npcID = ns.AutoRouting:GetUnitNPCID("npc")
    local routeID = tonumber(route.npcID) or 0
    if npcID and npcID > 0 and routeID > 0 and npcID ~= routeID then
        ns:PrintError("对话 NPC ID 与所选目标不一致，未建立关联。"); return
    end
    ns.db.gossipExplicitRouteMap = ns.db.gossipExplicitRouteMap or {}
    ns.db.gossipExplicitRouteMap[chosen] = key
    -- Save an exact stage link only when there is one unambiguous active criterion.
    local active = {}
    if IsInScenario() then
        local count = ReadScenarioStep()
        for i = 1, count do
            local desc, done = ReadScenarioCriterion(i)
            if not ns:IsSecretValue(done) and not done and not ns:IsSecretValue(desc)
                and type(desc) == "string" and strtrim(desc) ~= "" then active[#active + 1] = strtrim(desc) end
        end
    end
    if #active == 1 then route.scenarioCriterion = active[1] end
    if ns.MarkRoutesDirty then ns:MarkRoutesDirty() end
    print(ns:TF("|cff10b981[Wish 对话绑定]|r 已将选项 %s 关联到目标：%s；队伍：%s。请关闭并重新打开 NPC 对话。", tostring(chosen), tostring(route.npcName or key), tostring(route.teams[1])))
end
SLASH_WISHBINDDIALOG1 = "/wpbinddialog"

-- Return a unique public pet-battle option; never learn travel/quest options
-- merely because a target has a pet team.
function ns.AutoRouting:GetLearnableGossipOption(options)
    local chosen
    for _, opt in ipairs(options or {}) do
        local id, text = opt.gossipOptionID, opt.name
        if not ns:IsSecretValue(id) and type(id) == "number" then
            local battle = KNOWN_PET_BATTLE_GOSSIP[id] ~= nil
            if not battle and not ns:IsSecretValue(text) and type(text) == "string" then
                local lower = strlower(text)
                battle = string.find(lower, "对战", 1, true) or string.find(lower, "對戰", 1, true)
                    or string.find(lower, "battle", 1, true)
            end
            if battle then
                if chosen then return nil end
                chosen = id
            end
        end
    end
    return chosen
end

function ns.AutoRouting:RememberGossipRoute(key, optionID, confirmed)
    if not ns.db or not GossipFrame or not GossipFrame:IsShown() then return false end
    local route = ns.db.routeMappings and ns.db.routeMappings[key]
    if not route then return false end
    local options = C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.GetOptions()
    if self:GetLearnableGossipOption(options) ~= optionID then return false end
    local npcID, npcName = self:GetDialogNPCID(options)
    local routeID = tonumber(route.npcID) or 0
    if npcID and npcID > 0 and routeID > 0 and npcID ~= routeID then return false end
    if not confirmed then
        local matched, matchedKey = ns:FindExistingRouteForNPC(npcID, npcName)
        if matched ~= route or matchedKey ~= key then return false end
    end
    local field = confirmed and "gossipExplicitRouteMap" or "gossipLearnedRouteMap"
    ns.db[field] = ns.db[field] or {}
    local old = ns.db[field][optionID]
    if not confirmed then
        if ns.db.gossipAmbiguousOptions and ns.db.gossipAmbiguousOptions[optionID] then return false end
        if old and old ~= key then
            ns.db[field][optionID] = nil
            ns.db.gossipAmbiguousOptions = ns.db.gossipAmbiguousOptions or {}
            ns.db.gossipAmbiguousOptions[optionID] = true
            return false
        end
    end
    ns.db[field][optionID] = key
    if confirmed and route.teams and #route.teams > 0 then
        local active, count = nil, 0
        if IsInScenario() then
            local n = ReadScenarioStep()
            for i = 1, n do
                local desc, done = ReadScenarioCriterion(i)
                if not ns:IsSecretValue(done) and not done and not ns:IsSecretValue(desc)
                    and type(desc) == "string" and strtrim(desc) ~= "" then
                    active, count = strtrim(desc), count + 1
                end
            end
        end
        if count == 1 and route.scenarioCriterion ~= active then
            route.scenarioCriterion = active
            if ns.MarkRoutesDirty then ns:MarkRoutesDirty() end
        end
    end
    return true
end

function ns.AutoRouting:TryLearnCurrentGossip(key)
    if not GossipFrame or not GossipFrame:IsShown() then return false end
    local options = C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.GetOptions()
    local option = self:GetLearnableGossipOption(options)
    return option and self:RememberGossipRoute(key, option, false) or false
end

-- Resolve the current dialog from public identity data. The known BRD
-- option provides a fallback when unit identity itself is secret.
function ns.AutoRouting:GetDialogNPCID(options)
    local npcID, npcName = self:GetUnitNPCID("npc")
    if npcID and npcName then return npcID, npcName end
    if not GossipFrame or not GossipFrame:IsShown() then return npcID, npcName end

    -- A public target identity can supplement the dialog only when the game
    -- publicly confirms both unit tokens refer to the same NPC.
    if UnitIsUnit then
        local ok, sameUnit = pcall(UnitIsUnit, "target", "npc")
        if ok and not ns:IsSecretValue(sameUnit) and sameUnit then
            local targetID, targetName = self:GetUnitNPCID("target")
            if not npcID or not targetID or npcID == targetID then
                npcID, npcName = npcID or targetID, npcName or targetName
            end
        end
    end
    if npcID and npcName then return npcID, npcName end

    options = options or (C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.GetOptions())
    local linked = GetExplicitGossipRoute(options, npcID, npcName)
    if linked then
        local linkedID = tonumber(linked.npcID) or 0
        return npcID or (linkedID > 0 and linkedID or nil), npcName or linked.npcName
    end
    for _, opt in ipairs(options or {}) do
        local optionID = opt.gossipOptionID
        local known = not ns:IsSecretValue(optionID) and KNOWN_PET_BATTLE_GOSSIP[optionID]
        if known and (not known.npcID or not npcID or npcID == known.npcID) then
            npcID = npcID or known.npcID
            if not npcName then
                local route = FindKnownGossipRoute(known, nil)
                local label = route and route.npcName
                if type(label) == "string" and not ns:IsSecretValue(label) and strtrim(label) ~= "" then
                    npcName = strtrim(label)
                elseif ns.locale == "zhCN" and known.aliases then
                    npcName = known.aliases[1]
                end
            end
            break
        end
    end
    return npcID, npcName
end

-- Manual buttons share the dialog resolver, without treating an unrelated
-- dialog as the currently selected target.
function ns.AutoRouting:GetManualTargetNPCID()
    local npcID, npcName = self:GetUnitNPCID("target")
    if npcID and npcName then return npcID, npcName end
    if not GossipFrame or not GossipFrame:IsShown() or not UnitIsUnit then
        return npcID, npcName
    end
    local ok, sameUnit = pcall(UnitIsUnit, "target", "npc")
    if not ok or ns:IsSecretValue(sameUnit) or not sameUnit then
        return npcID, npcName
    end
    local dialogID, dialogName = self:GetDialogNPCID()
    if npcID and dialogID and npcID ~= dialogID then return npcID, npcName end
    return npcID or dialogID, npcName or dialogName
end

-- ==================== 4. 宠物对战中「无框体纯文本头像下方属性显示」组件（单框体精准刷新） ====================
local BREED_QUALITY_VALUES = { 0.5, 0.55, 0.6, 0.65, 0.7, 0.75 }
local BREED_OFFSETS = {
    [3] = { 5, 5, 5 }, [4] = { 0, 20, 0 }, [5] = { 0, 0, 20 },
    [6] = { 20, 0, 0 }, [7] = { 9, 9, 0 }, [8] = { 0, 9, 9 },
    [9] = { 9, 0, 9 }, [10] = { 4, 9, 4 }, [11] = { 4, 4, 9 },
    [12] = { 9, 4, 4 },
}
local BREED_NAMES = {
    [3] = "B/B", [4] = "P/P", [5] = "S/S", [6] = "H/H", [7] = "H/P",
    [8] = "P/S", [9] = "H/S", [10] = "P/B", [11] = "S/B", [12] = "H/B",
}

local function RoundBreedStat(value)
    return math.floor(value * 0.01 + 0.5) / 0.01
end

local function CalculateBattleBreed(speciesID, quality, level, maxHP, power, speed, wild, flying)
    local base = ns.BreedBaseStats and ns.BreedBaseStats[speciesID]
    if not base or not quality or quality < 1 or quality > 6 or not level or level < 1 then return nil end
    local ql = BREED_QUALITY_VALUES[quality] * 20 * level
    local wildHPFactor, wildPowerFactor = 1, 1
    if wild then
        wildHPFactor = 1.2
        wildPowerFactor = (level < 6) and 1.4 or 1.25
    end
    local targetHP, targetPower, targetSpeed = maxHP * 100, power * 100, speed * 100
    if flying then targetSpeed = targetSpeed / 1.5 end

    local pool = ns.BreedSpeciesPools and ns.BreedSpeciesPools[speciesID]
    local bestBreed, bestDiff, ties
    for breedID = 3, 12 do
        local allowed = not pool
        if pool then
            for i = 1, #pool do
                if pool[i] == breedID then allowed = true; break end
            end
        end
        if allowed then
            local offset = BREED_OFFSETS[breedID]
            local hp = ((base[1] * 10 + offset[1]) * ql * 5 + 10000) / wildHPFactor
            local pwr = (base[2] * 10 + offset[2]) * ql / wildPowerFactor
            local spd = (base[3] * 10 + offset[3]) * ql
            if level <= 2 then
                hp, pwr, spd = RoundBreedStat(hp), RoundBreedStat(pwr), RoundBreedStat(spd)
            end
            local diff = math.abs(hp - targetHP) / 5
                + math.abs(pwr - targetPower) + math.abs(spd - targetSpeed)
            if not bestDiff or diff < bestDiff then
                bestBreed, bestDiff, ties = breedID, diff, 1
            elseif diff == bestDiff then
                ties = ties + 1
            end
        end
    end
    if ties == 1 then return bestBreed end
    return nil
end

local function UpdateSingleUnitFrameBreed(unitFrame, owner, slotIndex, isMainHeader)
    if not unitFrame or not owner or not slotIndex then return end
    if not C_PetBattles or not C_PetBattles.IsInBattle() then return end
    local psf = PetBattleFrame and PetBattleFrame.BottomFrame and PetBattleFrame.BottomFrame.PetSelectionFrame
    if psf and unitFrame:GetParent() == psf then
        if unitFrame.wishBreedText then unitFrame.wishBreedText:Hide() end
        return
    end

    local speciesID = C_PetBattles.GetPetSpeciesID(owner, slotIndex)
    if not speciesID then
        if unitFrame.wishBreedText then unitFrame.wishBreedText:Hide() end
        return
    end

    local speed = C_PetBattles.GetSpeed(owner, slotIndex) or 10
    -- C_PetBattles.GetBreedQuality is zero-based relative to the normal
    -- pet quality APIs. BattlePetBreedID applies this same +1 conversion.
    local rawRarity = C_PetBattles.GetBreedQuality(owner, slotIndex)
    local rarity = (rawRarity or 0) + 1

    local level = C_PetBattles.GetLevel(owner, slotIndex) or 1
    local maxHP = C_PetBattles.GetMaxHealth(owner, slotIndex) or 0
    local power = C_PetBattles.GetPower(owner, slotIndex) or 0
    local isEnemy = owner == ((Enum and Enum.BattlePetOwner and Enum.BattlePetOwner.Enemy) or LE_BATTLE_PET_ENEMY or 2)
    local wild = C_PetBattles.IsWildBattle and C_PetBattles.IsWildBattle() and isEnemy
    local flying = C_PetBattles.GetPetType(owner, slotIndex) == 3
    if flying and not isEnemy then
        local health = C_PetBattles.GetHealth(owner, slotIndex) or 0
        flying = health / math.max(1, maxHP) > 0.5
    end
    local breedID = CalculateBattleBreed(speciesID, rarity, level, maxHP, power, speed, wild, flying)
    local breed = BREED_NAMES[breedID] or "?"
    local qCol = ns.Theme.QualityColors[rarity] or ns.Theme.QualityColors[2]
    local hexCol = string.sub(qCol[4], 1, 10)

    if not unitFrame.wishBreedText then
        local txt = unitFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        local fontPath, fontSize = txt:GetFont()
        if fontPath then
            txt:SetFont(fontPath, fontSize or 12, "OUTLINE")
        end
        ns.Theme:HookLocalizedFontString(txt)
        unitFrame.wishBreedText = txt
    end

    local txt = unitFrame.wishBreedText
    local anchorIcon = unitFrame.Icon or unitFrame
    if txt._anchoredTo ~= anchorIcon or txt._isMain ~= isMainHeader then
        txt._anchoredTo = anchorIcon
        txt._isMain = isMainHeader
        txt:ClearAllPoints()
        txt:SetPoint("TOP", anchorIcon, "BOTTOM", 0, isMainHeader and -3 or -2)
    end

    local newStr = isMainHeader
        and ns:TF("%s%s|r |cff38bdf8%d速|r", hexCol, breed, speed)
        or string.format("%s%s|r", hexCol, breed)

    if txt._lastBreedStr ~= newStr then
        txt._lastBreedStr = newStr
        txt:SetText(newStr)
    end
    txt:Show()
end

function ns:UpdateBattleEnemyBreedDisplay()
    if not C_PetBattles or not C_PetBattles.IsInBattle() or not PetBattleFrame then return end
    local ally = Enum.BattlePetOwner.Ally
    local enemy = Enum.BattlePetOwner.Enemy
    UpdateSingleUnitFrameBreed(PetBattleFrame.ActiveAlly, ally, C_PetBattles.GetActivePet(ally), true)
    UpdateSingleUnitFrameBreed(PetBattleFrame.ActiveEnemy, enemy, C_PetBattles.GetActivePet(enemy), true)
    UpdateSingleUnitFrameBreed(PetBattleFrame.Ally2, ally, PetBattleFrame.Ally2.petIndex, false)
    UpdateSingleUnitFrameBreed(PetBattleFrame.Ally3, ally, PetBattleFrame.Ally3.petIndex, false)
    UpdateSingleUnitFrameBreed(PetBattleFrame.Enemy2, enemy, PetBattleFrame.Enemy2.petIndex, false)
    UpdateSingleUnitFrameBreed(PetBattleFrame.Enemy3, enemy, PetBattleFrame.Enemy3.petIndex, false)
end

function ns:SetupBattleEnemyBreedHUD()
    if ns.battleBreedHooked then return end
    if PetBattleUnitFrame_UpdateDisplay then
        hooksecurefunc("PetBattleUnitFrame_UpdateDisplay", function(unitFrame)
            if not unitFrame or not PetBattleFrame then return end
            if not C_PetBattles or not C_PetBattles.IsInBattle() then return end
            if unitFrame.petOwner and unitFrame.petIndex then
                local isMain = (unitFrame == PetBattleFrame.ActiveAlly or unitFrame == PetBattleFrame.ActiveEnemy)
                UpdateSingleUnitFrameBreed(unitFrame, unitFrame.petOwner, unitFrame.petIndex, isMain)
            end
        end)
        ns.battleBreedHooked = true
    end
end

-- ==================== 5. 战斗脚本语法校验器与预编译执行引擎（完整支持 & / | 逻辑与零分配执行） ====================
ns.ScriptEngine.logs           = {}
ns.ScriptEngine.isPaused       = false
ns.ScriptEngine.currentRound   = 1
ns.ScriptEngine.lastCompletedRound = 0
ns.ScriptEngine.ignoredRoundEvents = 0
ns.ScriptEngine.lastLogKey     = ""
ns.ScriptEngine._lastExecTime  = 0
ns.ScriptEngine.sideRound      = { [1] = 1, [2] = 1 }
ns.ScriptEngine.lastActiveSlot = { [1] = 1, [2] = 1 }
ns.ScriptEngine.swappedInRound = { [1] = false, [2] = false }
ns.ScriptEngine.playedSlots    = { [1] = {}, [2] = {} }

local VALID_CONDITION_ROOTS = {
    ["self"]      = true,
    ["ally"]      = true,
    ["enemy"]     = true,
    ["weather"]   = true,
    ["round"]     = true,
    ["hp"]        = true,
    ["hpp"]       = true,
    ["trap"]      = true,
    ["collected"] = true,
    ["true"]      = true,
    ["false"]     = true,
}

local BARE_PET_PROPS = {
    ["hp"] = true, ["hpp"] = true, ["active"] = true, ["dead"] = true, ["alive"] = true,
    ["aura"] = true, ["buff"] = true, ["debuff"] = true, ["speed"] = true,
    ["power"] = true, ["level"] = true, ["quality"] = true, ["ability"] = true,
    ["count"] = true, ["id"] = true, ["type"] = true, ["exists"] = true,
    ["is"] = true, ["played"] = true,
}

local PET_TYPE_MAP = {
    ["1"] = 1, ["人型"] = 1, ["人形"] = 1, ["humanoid"] = 1,
    ["2"] = 2, ["龙类"] = 2, ["龙"] = 2, ["龍類"] = 2, ["龍"] = 2, ["dragonkin"] = 2, ["dragon"] = 2,
    ["3"] = 3, ["飞行"] = 3, ["飛行"] = 3, ["flying"] = 3,
    ["4"] = 4, ["亡灵"] = 4, ["亡靈"] = 4, ["不死族"] = 4, ["undead"] = 4,
    ["5"] = 5, ["小动物"] = 5, ["小動物"] = 5, ["critter"] = 5,
    ["6"] = 6, ["魔法"] = 6, ["magic"] = 6, ["magical"] = 6,
    ["7"] = 7, ["元素"] = 7, ["elemental"] = 7,
    ["8"] = 8, ["野兽"] = 8, ["野獸"] = 8, ["beast"] = 8,
    ["9"] = 9, ["水栖"] = 9, ["水棲"] = 9, ["aquatic"] = 9, ["water"] = 9,
    ["10"] = 10, ["机械"] = 10, ["機械"] = 10, ["mechanical"] = 10,
}
for i = 1, 10 do
    local locTypeName = _G["BATTLE_PET_NAME_" .. i]
    if type(locTypeName) == "string" and locTypeName ~= "" then
        PET_TYPE_MAP[strlower(locTypeName)] = i
    end
end

local QUALITY_MAP = {
    ["1"] = 1, ["弱小"] = 1, ["粗糙"] = 1, ["poor"] = 1,
    ["2"] = 2, ["普通"] = 2, ["common"] = 2,
    ["3"] = 3, ["优秀"] = 3, ["優秀"] = 3, ["uncommon"] = 3,
    ["4"] = 4, ["精良"] = 4, ["稀有"] = 4, ["rare"] = 4,
    ["5"] = 5, ["史诗"] = 5, ["史詩"] = 5, ["epic"] = 5,
    ["6"] = 6, ["传奇"] = 6, ["传说"] = 6, ["傳奇"] = 6, ["傳說"] = 6, ["legendary"] = 6,
}
for i = 1, 6 do
    local locQualName = _G["BATTLE_PET_BREED_QUALITY" .. i]
    if type(locQualName) == "string" and locQualName ~= "" then
        QUALITY_MAP[strlower(locQualName)] = i
    end
end

local function ParseTokenToNum(token, customMap)
    token = strtrim(token or "")
    if token == "" then return nil end
    local n = tonumber(token)
    if n then return n end
    local low = strlower(token)
    if customMap and customMap[low] then return customMap[low] end
    if PET_TYPE_MAP[low] then return PET_TYPE_MAP[low] end
    if QUALITY_MAP[low] then return QUALITY_MAP[low] end
    return nil
end

local function IsValidComparisonValueList(str)
    if not str or str == "" then return false end
    local hasToken = false
    for token in string.gmatch(str, "[^,]+") do
        token = strtrim(token)
        if token == "" or not ParseTokenToNum(token) then
            return false
        end
        hasToken = true
    end
    return hasToken
end

local function EvalNumericComparison(actualVal, op, rhsStr, customMap)
    if actualVal == nil or not op or not rhsStr then return false end
    rhsStr = strtrim(rhsStr)

    if op == "~" or ((op == "=" or op == "==") and string.find(rhsStr, ",", 1, true)) then
        for token in string.gmatch(rhsStr, "[^,]+") do
            local v = ParseTokenToNum(token, customMap)
            if v and actualVal == v then
                return true
            end
        end
        return false
    elseif op == "!~" or op == "~=" or op == "!=" then
        if op == "!~" or string.find(rhsStr, ",", 1, true) then
            for token in string.gmatch(rhsStr, "[^,]+") do
                local v = ParseTokenToNum(token, customMap)
                if v and actualVal == v then
                    return false
                end
            end
            return true
        end
        local v = ParseTokenToNum(rhsStr, customMap)
        return v ~= nil and (actualVal ~= v)
    end

    local v = ParseTokenToNum(rhsStr, customMap)
    if not v then return false end
    if op == "=" or op == "==" then return actualVal == v
    elseif op == "<" then return actualVal < v
    elseif op == "<=" then return actualVal <= v
    elseif op == ">" then return actualVal > v
    elseif op == ">=" then return actualVal >= v
    end
    return false
end

local function CheckBalancedDelimiters(str)
    local pDepth, bDepth = 0, 0
    for i = 1, #str do
        local c = string.sub(str, i, i)
        if c == "(" then
            pDepth = pDepth + 1
        elseif c == ")" then
            pDepth = pDepth - 1
            if pDepth < 0 then return false, ns:T("存在多余的右括号 ')'") end
        elseif c == "[" then
            bDepth = bDepth + 1
        elseif c == "]" then
            bDepth = bDepth - 1
            if bDepth < 0 then return false, ns:T("存在多余的右中括号 '[]'") end
        end
    end
    if pDepth ~= 0 then return false, ns:T("括号 '()' 未闭合") end
    if bDepth ~= 0 then return false, ns:T("条件中括号 '[]' 未闭合") end
    return true
end

local function ValidateConditionExpression(condExpr)
    condExpr = strtrim(condExpr or "")
    if condExpr == "" then
        return false, ns:T("条件表达式不能为空")
    end

    local okDelim, delimErr = CheckBalancedDelimiters(condExpr)
    if not okDelim then return false, delimErr end

    local normalized = string.gsub(condExpr, "%s+[aA][nN][dD]%s+", "&")
    normalized = string.gsub(normalized, "%s+[oO][rR]%s+", "|")
    normalized = string.gsub(normalized, "|", "&")

    -- Preserve empty operands: gmatch("[^&]+") silently accepts "& true"
    -- and "true && false", which the executor would then partly ignore.
    for part in string.gmatch(normalized .. "&", "(.-)&") do
        local single = strtrim(part)
        if single == "" then
            return false, ns:T("逻辑连接符前后缺少条件")
        end
        while true do
            if string.sub(single, 1, 1) == "!" then
                single = strtrim(string.sub(single, 2))
            elseif string.find(single, "^[nN][oO][tT]%s+") then
                single = strtrim(string.gsub(single, "^[nN][oO][tT]%s+", ""))
            else
                break
            end
        end

        if single == "" then
            return false, ns:T("逻辑取反 '!' 或 'not' 后缺少条件内容")
        end

        local lhs, op, rhs = string.match(single, "^(.-)%s*([=~<>!]+)%s*(.*)$")
        if op then
            if op ~= "=" and op ~= "==" and op ~= "~" and op ~= "!~" and op ~= "~=" and op ~= "!=" and op ~= "<" and op ~= "<=" and op ~= ">" and op ~= ">=" then
                return false, string.format(ns:T("无效的比较运算符 '%s'"), op)
            end
            if not rhs or strtrim(rhs) == "" then
                return false, string.format(ns:T("比较运算符 '%s' 右侧缺少数值"), op)
            end
            rhs = strtrim(rhs)
            if not IsValidComparisonValueList(rhs) and rhs ~= "true" and rhs ~= "false" then
                return false, string.format(ns:T("条件比较值 '%s' 必须是数字、列表或有效的属性/品质名"), rhs)
            end
            single = strtrim(lhs)
        end

        local rootWord = string.match(single, "^([a-zA-Z_]+)")
        if not rootWord then
            return false, string.format(ns:T("无法识别的条件表达式 '%s'"), single)
        end
        rootWord = strlower(rootWord)

        if BARE_PET_PROPS[rootWord] and not string.find(single, "^hp%.diff") and not string.find(single, "^hpp%.diff") then
            return false, string.format(ns:T("条件 '%s' 缺少目标前缀，请改为 self.%s 或 enemy.%s"), single, single, single)
        end

        if not VALID_CONDITION_ROOTS[rootWord] then
            return false, string.format(ns:T("未知的条件关键字 '%s'"), rootWord)
        end

        local petSlotArg = string.match(single, "^[a-zA-Z_]+%(([^%)]*)%)")
        if (rootWord == "self" or rootWord == "ally" or rootWord == "enemy") and petSlotArg then
            petSlotArg = strtrim(petSlotArg)
            if petSlotArg == "" then
                return false, string.format(ns:T("'%s()' 括号内缺少宠物槽位 (#1~#3) 或宠物名称/ID"), rootWord)
            end
            local hashSlot = string.match(petSlotArg, "^#(%d+)$")
            if hashSlot then
                local slotNum = tonumber(hashSlot)
                if not slotNum or slotNum < 1 or slotNum > 3 then
                    return false, string.format(ns:T("宠物槽位 '#%s' 超出范围，仅支持 #1、#2 或 #3"), hashSlot)
                end
            end
        elseif (rootWord == "weather" or string.find(single, "%.aura%(") or string.find(single, "%.buff%(") or string.find(single, "%.debuff%(") or string.find(single, "%.ability%(") or string.find(single, "%.is%(")) then
            local emptyCall = string.match(single, "%(%s*%)")
            if emptyCall then
                return false, string.format(ns:T("条件 '%s' 的括号内缺少名称或 ID 参数"), single)
            end
        end
    end

    return true
end

local function ExtractIfCondition(line, keyword)
    local patternPrefix = "^" .. keyword
    local body = string.match(line, patternPrefix .. "%s+(.+)%s+[tT][hH][eE][nN]$")
        or string.match(line, patternPrefix .. "%s*%((.+)%)%s*[tT][hH][eE][nN]$")
        or string.match(line, patternPrefix .. "%s*%[(.+)%]%s*[tT][hH][eE][nN]?$")
        or string.match(line, patternPrefix .. "%s*%((.+)%)$")
        or string.match(line, patternPrefix .. "%s+(.+)$")
    if body then
        body = strtrim(body)
        local innerBracket = string.match(body, "^%[(.+)%]$")
        if innerBracket then body = strtrim(innerBracket) end
    end
    return body
end

function ns.ScriptEngine:ValidateScript(rawScript)
    local cleanText = ns.Syntax and ns.Syntax:StripColors(rawScript or "") or (rawScript or "")
    if strtrim(cleanText) == "" then
        return true, nil, nil
    end

    local ifStack = {}
    local lineNum = 0
    local normalizedText = string.gsub(cleanText, "\r\n", "\n")

    for rawLine in string.gmatch(normalizedText .. "\n", "(.-)\n") do
        lineNum = lineNum + 1
        local line = strtrim(rawLine)

        if line ~= "" and not string.find(line, "^%-%-") and not string.find(line, "^#") then
            local commentPos = string.find(line, "--", 1, true)
            if commentPos and commentPos > 1 then
                line = strtrim(string.sub(line, 1, commentPos - 1))
            end

            local okDelim, delimErr = CheckBalancedDelimiters(line)
            if not okDelim then
                return false, string.format(ns:T("第 %d 行语法错误：%s"), lineNum, delimErr), lineNum, rawLine
            end

            local firstWord = strlower(string.match(line, "^([a-zA-Z_]+)") or "")

            if firstWord == "if" then
                local cond = ExtractIfCondition(line, "[iI][fF]")
                if not cond or cond == "" then
                    return false, string.format(ns:T("第 %d 行错误：'if' 语句缺少条件表达式"), lineNum), lineNum, rawLine
                end
                local okCond, condErr = ValidateConditionExpression(cond)
                if not okCond then
                    return false, string.format(ns:T("第 %d 行条件错误：%s"), lineNum, condErr), lineNum, rawLine
                end
                table.insert(ifStack, { line = lineNum, hasElse = false })

            elseif firstWord == "elseif" then
                if #ifStack == 0 then
                    return false, string.format(ns:T("第 %d 行错误：'elseif' 缺少对应的起始 'if'"), lineNum), lineNum, rawLine
                end
                if ifStack[#ifStack].hasElse then
                    return false, string.format(ns:T("第 %d 行错误：'else' 分支之后不能再出现 'elseif'"), lineNum), lineNum, rawLine
                end
                local cond = ExtractIfCondition(line, "[eE][lL][sS][eE][iI][fF]")
                if not cond or cond == "" then
                    return false, string.format(ns:T("第 %d 行错误：'elseif' 语句缺少条件表达式"), lineNum), lineNum, rawLine
                end
                local okCond, condErr = ValidateConditionExpression(cond)
                if not okCond then
                    return false, string.format(ns:T("第 %d 行条件错误：%s"), lineNum, condErr), lineNum, rawLine
                end

            elseif firstWord == "else" then
                if strlower(line) ~= "else" then
                    return false, string.format(ns:T("第 %d 行错误：'else' 后不能跟条件（如需条件请用 'elseif'）"), lineNum), lineNum, rawLine
                end
                if #ifStack == 0 then
                    return false, string.format(ns:T("第 %d 行错误：'else' 缺少对应的起始 'if'"), lineNum), lineNum, rawLine
                end
                if ifStack[#ifStack].hasElse then
                    return false, string.format(ns:T("第 %d 行错误：同一个 'if' 块中存在重复的 'else'"), lineNum), lineNum, rawLine
                end
                ifStack[#ifStack].hasElse = true

            elseif firstWord == "end" or firstWord == "endif" then
                if strlower(line) ~= "end" and strlower(line) ~= "endif" then
                    return false, string.format(ns:T("第 %d 行错误：'%s' 后存在多余字符"), lineNum, firstWord), lineNum, rawLine
                end
                if #ifStack == 0 then
                    return false, string.format(ns:T("第 %d 行错误：多余的 '%s'，找不到对应的 'if'"), lineNum, firstWord), lineNum, rawLine
                end
                table.remove(ifStack)

            else
                local actionPart, bracketCond = string.match(line, "^(.-)%s*%[(.+)%]%s*$")
                if not actionPart then
                    if string.find(line, "%[") or string.find(line, "%]") then
                        return false, string.format(ns:T("第 %d 行错误：条件中括号 '[]' 内容为空或格式错误"), lineNum), lineNum, rawLine
                    end
                    actionPart = line
                else
                    actionPart = strtrim(actionPart)
                    local okCond, condErr = ValidateConditionExpression(bracketCond)
                    if not okCond then
                        return false, string.format(ns:T("第 %d 行条件错误：%s"), lineNum, condErr), lineNum, rawLine
                    end
                end

                local actLower = strlower(actionPart)
                if actLower == "standby" or actLower == "pass" or actLower == "trap" or actLower == "catch" or actLower == "quit" or actLower == "test" then
                    -- 合法无参指令
                else
                    local cmdName, cmdArg, trailing = string.match(actionPart, "^([a-zA-Z_]+)%s*%(([^%)]*)%)(.*)$")
                    if not cmdName then
                        local bareCmd = string.match(actionPart, "^([a-zA-Z_]+)$")
                        if bareCmd and (strlower(bareCmd) == "use" or strlower(bareCmd) == "ability" or strlower(bareCmd) == "change") then
                            return false, string.format(ns:T("第 %d 行错误：指令 '%s' 缺少括号与参数，例如 %s(#1)"), lineNum, bareCmd, strlower(bareCmd)), lineNum, rawLine
                        end
                        return false, string.format(ns:T("第 %d 行错误：无法识别的指令 '%s'"), lineNum, actionPart), lineNum, rawLine
                    end

                    cmdName = strlower(cmdName)
                    cmdArg = strtrim(cmdArg or "")
                    trailing = strtrim(trailing or "")

                    if trailing ~= "" then
                        return false, string.format(ns:T("第 %d 行错误：指令末尾存在多余字符 '%s'（条件请用 [] 包裹）"), lineNum, trailing), lineNum, rawLine
                    end

                    if cmdName == "use" or cmdName == "ability" then
                        if cmdArg == "" then
                            return false, string.format(ns:T("第 %d 行错误：'%s()' 括号内缺少技能名称或槽位编号 (#1~#3)"), lineNum, cmdName), lineNum, rawLine
                        end
                        local slotHash = string.match(cmdArg, "^#(%d+)$")
                        if slotHash then
                            local n = tonumber(slotHash)
                            if not n or n < 1 or n > 3 then
                                return false, string.format(ns:T("第 %d 行错误：技能槽位 '#%s' 无效，仅支持 #1、#2 或 #3"), lineNum, slotHash), lineNum, rawLine
                            end
                        end
                    elseif cmdName == "change" then
                        if cmdArg == "" then
                            return false, string.format(ns:T("第 %d 行错误：'change()' 括号内缺少换宠目标 (next、#1~#3 或宠物名称/ID)"), lineNum), lineNum, rawLine
                        end
                        local slotHash = string.match(cmdArg, "^#(%d+)$")
                        if slotHash then
                            local n = tonumber(slotHash)
                            if not n or n < 1 or n > 3 then
                                return false, string.format(ns:T("第 %d 行错误：change(#%s) 槽位超出范围，仅支持 #1、#2 或 #3"), lineNum, slotHash), lineNum, rawLine
                            end
                        end
                    elseif cmdName == "test" then
                        -- test(任意调试消息)
                    else
                        return false, string.format(ns:T("第 %d 行错误：未知的动作指令 '%s'"), lineNum, cmdName), lineNum, rawLine
                    end
                end
            end
        end
    end

    if #ifStack > 0 then
        local lastOpen = ifStack[#ifStack]
        return false, string.format(ns:T("第 %d 行的 'if' 条件块缺少闭合的 'end' 或 'endif'"), lastOpen.line), lastOpen.line, ""
    end

    return true, nil, nil
end

function ns.ScriptEngine:AddLog(msg)
    local logKey = tostring(self.currentRound or 1) .. ":" .. tostring(msg)
    if self.lastLogKey == logKey then return end
    self.lastLogKey = logKey

    local timeStr = date("%H:%M:%S")
    table.insert(self.logs, 1, string.format("|cff6b7280[%s R%d]|r %s", timeStr, self.currentRound or 1, ns:T(msg)))
    while #self.logs > 2 do
        table.remove(self.logs)
    end
    if ns.UpdateBattleHUD then ns:UpdateBattleHUD() end
end

function ns.ScriptEngine:GetPetHPPct(owner, slot)
    if not slot or slot <= 0 then return 0 end
    local hp = C_PetBattles.GetHealth(owner, slot) or 0
    local maxHp = C_PetBattles.GetMaxHealth(owner, slot) or 1
    if maxHp <= 0 then return 0 end
    return math.floor((hp / maxHp) * 100)
end

-- 根据 #1~#3、宠物名称、SpeciesID 或 Name:ID 解析目标宠物所在的队伍槽位 (1..3)
function ns.ScriptEngine:ResolvePetSlot(owner, token, defaultActive)
    local activeSlot = C_PetBattles.GetActivePet(owner) or 1
    if not token or strtrim(token) == "" then
        return defaultActive and activeSlot or nil
    end
    token = strtrim(token)

    local hashNum = tonumber(string.match(token, "^#(%d+)$"))
    if hashNum then
        local numPets = C_PetBattles.GetNumPets(owner) or 0
        if hashNum >= 1 and hashNum <= numPets then
            return hashNum
        end
        return nil
    end

    local numPets = C_PetBattles.GetNumPets(owner) or 0
    local pureNum = tonumber(token)
    if pureNum and pureNum >= 1 and pureNum <= 3 then
        if pureNum <= numPets then
            return pureNum
        end
        return nil
    end

    local explicitID = tonumber(string.match(token, ":(%d+)$")) or pureNum
    local namePart = strtrim(string.match(token, "^([^:]+)") or token)
    local nameLower = strlower(namePart)

    for s = 1, numPets do
        if explicitID and explicitID > 3 then
            local spID = C_PetBattles.GetPetSpeciesID(owner, s)
            if spID == explicitID then
                return s
            end
        end
        if nameLower ~= "" and not tonumber(nameLower) then
            local cName, spName = C_PetBattles.GetName(owner, s)
            if (cName and strlower(cName) == nameLower) or (spName and strlower(spName) == nameLower) then
                return s
            end
        end
    end

    if nameLower ~= "" and not tonumber(nameLower) then
        for s = 1, numPets do
            local cName, spName = C_PetBattles.GetName(owner, s)
            if (cName and string.find(strlower(cName), nameLower, 1, true)) or (spName and string.find(strlower(spName), nameLower, 1, true)) then
                return s
            end
        end
    end

    return nil
end

-- 解析指定宠物槽位上的技能序号 (1..3) 及技能元数据
function ns.ScriptEngine:ResolvePetAbility(owner, slot, abToken)
    if not slot or not abToken then return nil, nil, nil, nil end
    abToken = strtrim(abToken)

    local hashIdx = tonumber(string.match(abToken, "^#(%d+)$"))
    if hashIdx and hashIdx >= 1 and hashIdx <= 3 then
        local id, _, _, _, _, _, petType, noHints = C_PetBattles.GetAbilityInfo(owner, slot, hashIdx)
        if id and not petType then
            local _, _, jType, jNoHints = GetCachedJournalAbility(id)
            petType = jType
            if noHints == nil then noHints = jNoHints end
        end
        return hashIdx, id, petType, noHints
    end

    local pureNum = tonumber(abToken)
    if pureNum and pureNum >= 1 and pureNum <= 3 then
        local id, _, _, _, _, _, petType, noHints = C_PetBattles.GetAbilityInfo(owner, slot, pureNum)
        if id and not petType then
            local _, _, jType, jNoHints = GetCachedJournalAbility(id)
            petType = jType
            if noHints == nil then noHints = jNoHints end
        end
        return pureNum, id, petType, noHints
    end

    local explicitID = tonumber(string.match(abToken, ":(%d+)$")) or pureNum
    local namePart = strtrim(string.match(abToken, "^([^:]+)") or abToken)
    local nameLower = strlower(namePart)

    for idx = 1, 3 do
        local id, name, _, _, _, _, petType, noHints = C_PetBattles.GetAbilityInfo(owner, slot, idx)
        if id then
            if explicitID and id == explicitID then
                if not petType then
                    local _, _, jType, jNoHints = GetCachedJournalAbility(id)
                    petType = jType
                    if noHints == nil then noHints = jNoHints end
                end
                return idx, id, petType, noHints
            end
            if name and nameLower ~= "" and (strlower(name) == nameLower or string.find(strlower(name), nameLower, 1, true)) then
                if not petType then
                    local _, _, jType, jNoHints = GetCachedJournalAbility(id)
                    petType = jType
                    if noHints == nil then noHints = jNoHints end
                end
                return idx, id, petType, noHints
            end
        end
    end

    return nil, nil, nil, nil
end

function ns.ScriptEngine:GetAttackMultiplier(attackType, targetType, noHints)
    if noHints or not attackType or not targetType or attackType <= 0 or targetType <= 0 then
        return 1.0
    end
    if C_PetBattles and C_PetBattles.GetAttackModifier then
        local mult = C_PetBattles.GetAttackModifier(attackType, targetType)
        if mult then return mult end
    end
    if ns.Theme and ns.Theme.StrongAgainstMap and ns.Theme.StrongAgainstMap[attackType] == targetType then
        return 1.5
    elseif ns.Theme and ns.Theme.ToughAgainstMap and ns.Theme.ToughAgainstMap[targetType] == attackType then
        return 2 / 3
    end
    return 1.0
end

-- 计算 caster 的自爆 (Explode, 机械系技能) 对 target 造成的伤害及是否能直接击杀
function ns.ScriptEngine:CanExplodeKill(casterOwner, casterSlot, targetOwner, targetSlot)
    if not casterSlot or not targetSlot then return false end
    local casterMaxHP = C_PetBattles.GetMaxHealth(casterOwner, casterSlot) or 0
    local targetHP = C_PetBattles.GetHealth(targetOwner, targetSlot) or 0
    if casterMaxHP <= 0 or targetHP <= 0 then return false end

    local targetType = C_PetBattles.GetPetType(targetOwner, targetSlot) or 1
    local mult = self:GetAttackMultiplier(10, targetType, false)
    local explodeDamage = math.floor(casterMaxHP * 0.4 * mult)
    return targetHP < explodeDamage
end

function ns.ScriptEngine:CanSwapToSlot(targetSlot)
    if not targetSlot or targetSlot < 1 or targetSlot > 3 then return false end
    local owner = Enum.BattlePetOwner.Ally
    local activeSlot = C_PetBattles.GetActivePet(owner)
    if targetSlot == activeSlot then return false end
    local hp = C_PetBattles.GetHealth(owner, targetSlot) or 0
    if hp <= 0 then return false end
    if C_PetBattles.CanPetSwapIn then
        return C_PetBattles.CanPetSwapIn(targetSlot)
    end
    return true
end

function ns.ScriptEngine:HasAura(owner, slot, auraToken)
    if not auraToken or not slot then return false, 0 end
    local targetID = tonumber(string.match(auraToken, ":(%d+)$")) or tonumber(auraToken)
    local targetName = string.match(auraToken, "^([^:]+):") or auraToken
    targetName = strtrim(targetName)
    local targetNameLower = (targetName ~= "") and strlower(targetName) or ""

    local targetLocalName, _, targetIcon = nil, nil, nil
    if targetID and targetID > 0 then
        targetLocalName, _, targetIcon = GetCachedBattleAbility(targetID)
        if not targetLocalName then
            targetLocalName = GetCachedJournalAbility(targetID)
        end
    end

    local function CheckSlotAuras(checkSlot)
        local num = C_PetBattles.GetNumAuras(owner, checkSlot) or 0
        for i = 1, num do
            local auraID, _, turnsRemaining = C_PetBattles.GetAuraInfo(owner, checkSlot, i)
            if auraID then
                if targetID and auraID == targetID then
                    return true, turnsRemaining or 0
                end
                local auraName, auraNameLower, auraIcon = GetCachedBattleAbility(auraID)
                if not auraName then
                    auraName, auraNameLower = GetCachedJournalAbility(auraID)
                end
                if auraName then
                    if targetLocalName and auraName == targetLocalName then
                        return true, turnsRemaining or 0
                    end
                    if targetNameLower ~= "" and auraNameLower and string.find(auraNameLower, targetNameLower, 1, true) then
                        return true, turnsRemaining or 0
                    end
                end
                if targetIcon and auraIcon and targetIcon == auraIcon and targetID and math.abs(auraID - targetID) <= 5 then
                    return true, turnsRemaining or 0
                end
            end
        end
        return false, 0
    end

    local ok, turns = CheckSlotAuras(slot)
    if ok then return true, turns end
    return CheckSlotAuras(PET_BATTLE_PAD_INDEX or 0)
end

function ns.ScriptEngine:GetWeatherState(wArg)
    local wID, _, turnsRemaining = C_PetBattles.GetAuraInfo(Enum.BattlePetOwner.Weather, PET_BATTLE_PAD_INDEX or 0, 1)
    if not wID then return false, 0 end
    if not wArg or strtrim(wArg) == "" then return true, turnsRemaining or 0 end

    local targetID = tonumber(string.match(wArg, ":(%d+)$")) or tonumber(wArg)
    if targetID and wID == targetID then
        return true, turnsRemaining or 0
    end

    local targetName = strtrim(string.match(wArg, "^([^:]+)") or wArg)
    local targetLower = strlower(targetName)

    local wName, wNameLower, wIcon = GetCachedBattleAbility(wID)
    if not wName then
        wName, wNameLower = GetCachedJournalAbility(wID)
    end

    if targetID and targetID > 0 then
        local tLocalName, _, tIcon = GetCachedBattleAbility(targetID)
        if not tLocalName then tLocalName = GetCachedJournalAbility(targetID) end
        if tLocalName and wName and tLocalName == wName then
            return true, turnsRemaining or 0
        end
        if tIcon and wIcon and tIcon == wIcon then
            return true, turnsRemaining or 0
        end
    end

    if targetLower ~= "" and wNameLower and string.find(wNameLower, targetLower, 1, true) then
        return true, turnsRemaining or 0
    end

    return false, 0
end

local function ParseTargetPrefix(expr)
    local who, arg, rest = string.match(expr, "^([a-zA-Z]+)%(([^%)]*)%)%.(.+)$")
    if who then
        local wLow = strlower(who)
        if wLow == "self" or wLow == "ally" or wLow == "enemy" then
            return wLow, strtrim(arg), rest
        end
    end
    who, rest = string.match(expr, "^([a-zA-Z]+)%.(.+)$")
    if who then
        local wLow = strlower(who)
        if wLow == "self" or wLow == "ally" or wLow == "enemy" then
            return wLow, nil, rest
        end
    end
    return nil, nil, nil
end

-- Use an explicit branch: Lua's a-and-b-or-c idiom cannot return false
-- from its middle expression, so it is not safe for boolean negation.
local function ApplyConditionNegation(result, neg)
    if neg then return not result end
    return result
end

function ns.ScriptEngine:EvalSingleCond(cond)
    cond = strtrim(cond or "")
    if cond == "" then return true end

    local neg = false
    while true do
        if string.sub(cond, 1, 1) == "!" then
            neg = not neg
            cond = strtrim(string.sub(cond, 2))
        elseif string.find(cond, "^[nN][oO][tT]%s+") then
            neg = not neg
            cond = strtrim(string.gsub(cond, "^[nN][oO][tT]%s+", ""))
        else
            break
        end
    end

    local condLower = strlower(cond)
    if condLower == "true" then return not neg end
    if condLower == "false" then return neg end

    local ally = Enum.BattlePetOwner.Ally
    local enemy = Enum.BattlePetOwner.Enemy
    local activeAlly = C_PetBattles.GetActivePet(ally) or 1
    local activeEnemy = C_PetBattles.GetActivePet(enemy) or 1
    local result = false

    -- 1. 全局回合判定：round = 1 / round ~ 1,4,6 / round !~ 2,3
    local rOp, rVal = string.match(condLower, "^round%s*([=~<>!]+)%s*(.+)$")
    if rOp and rVal then
        result = EvalNumericComparison(self.currentRound or 1, rOp, rVal)
        return ApplyConditionNegation(result, neg)
    end

    -- 2. 天气判定：weather(月光) / weather(月光).exists / weather(月光).duration < 3
    local wArg, wTail = string.match(cond, "^[wW][eE][aA][tT][hH][eE][rR]%(([^%)]+)%)%.(.+)$")
    if not wArg then
        wArg = string.match(cond, "^[wW][eE][aA][tT][hH][eE][rR]%(([^%)]+)%)$")
    end
    if wArg then
        local hasWeather, wTurns = self:GetWeatherState(wArg)
        if not wTail or strlower(wTail) == "exists" then
            result = hasWeather
        else
            local dOp, dVal = string.match(strlower(wTail), "^duration%s*([=~<>!]+)%s*(.+)$")
            if dOp and dVal then
                result = hasWeather and EvalNumericComparison(wTurns, dOp, dVal) or false
            end
        end
        return ApplyConditionNegation(result, neg)
    end

    -- 3. 解析以 self / ally / enemy 开头的全部条件
    local who, petToken, propExpr = ParseTargetPrefix(cond)
    if who then
        local own = (who == "enemy") and enemy or ally
        local oppOwn = (own == enemy) and ally or enemy
        local activeOwnSlot = (own == enemy) and activeEnemy or activeAlly
        local activeOppSlot = (own == enemy) and activeAlly or activeEnemy
        local propLower = strlower(propExpr)

        -- 3.1 入场宠物数量 (Ext: self.count<3，本局战斗中阵亡不影响)
        local countOp, countVal = string.match(propLower, "^count%s*([=~<>!]+)%s*(.+)$")
        if countOp and countVal then
            local totalSlotted = (C_PetBattles and C_PetBattles.GetNumPets and C_PetBattles.GetNumPets(own)) or 0
            result = EvalNumericComparison(totalSlotted, countOp, countVal)
            return ApplyConditionNegation(result, neg)
        end

        -- 3.2 我方/敌方当前宠物的登场轮数：self.round = 1 / enemy.round = 1
        local srOp, srVal = string.match(propLower, "^round%s*([=~<>!]+)%s*(.+)$")
        if srOp and srVal then
            local pRound = (self.sideRound and self.sideRound[own]) or 1
            result = EvalNumericComparison(pRound, srOp, srVal)
            return ApplyConditionNegation(result, neg)
        end

        -- 解析目标宠物槽位
        local slot = self:ResolvePetSlot(own, petToken, true)

        -- 3.3 exists 判断宠物是否存在于本局战斗
        if propLower == "exists" then
            result = (slot ~= nil and (C_PetBattles.GetPetSpeciesID(own, slot) ~= nil))
            return ApplyConditionNegation(result, neg)
        end

        if not slot then
            return neg and true or false
        end

        -- 3.4 active / dead / alive / played / is(...)
        if propLower == "active" then
            result = (slot == activeOwnSlot)
            return ApplyConditionNegation(result, neg)
        elseif propLower == "dead" then
            result = ((C_PetBattles.GetHealth(own, slot) or 0) <= 0)
            return ApplyConditionNegation(result, neg)
        elseif propLower == "alive" then
            result = ((C_PetBattles.GetHealth(own, slot) or 0) > 0)
            return ApplyConditionNegation(result, neg)
        elseif propLower == "played" then
            result = (slot == activeOwnSlot) or (self.playedSlots and self.playedSlots[own] and self.playedSlots[own][slot] == true) or false
            return ApplyConditionNegation(result, neg)
        end

        local isArg = string.match(propExpr, "^[iI][sS]%(([^%)]+)%)$")
        if isArg then
            local matchedSlot = self:ResolvePetSlot(own, isArg, false)
            if matchedSlot == slot then
                result = true
            else
                local checkID = tonumber(string.match(isArg, ":(%d+)$")) or tonumber(isArg)
                if checkID and C_PetBattles.GetPetSpeciesID(own, slot) == checkID then
                    result = true
                else
                    local checkName = strlower(strtrim(string.match(isArg, "^([^:]+)") or isArg))
                    local cName, spName = C_PetBattles.GetName(own, slot)
                    if (cName and strlower(cName) == checkName) or (spName and strlower(spName) == checkName) then
                        result = true
                    end
                end
            end
            return ApplyConditionNegation(result, neg)
        end

        -- 3.5 技能条件：ability(...).usable / .duration / .strong / .weak / .type
        local abArg, abProp = string.match(propExpr, "^[aA][bB][iI][lL][iI][tT][yY]%(([^%)]+)%)%.(.+)$")
        if abArg and abProp then
            local abIdx, abID, abPetType, noHints = self:ResolvePetAbility(own, slot, abArg)
            local abPropLower = strlower(abProp)
            if not abIdx or not abID then
                result = false
            elseif abPropLower == "usable" then
                local isUsable = C_PetBattles.GetAbilityState(own, slot, abIdx)
                result = (isUsable == true)
            elseif abPropLower == "strong" then
                local oppType = C_PetBattles.GetPetType(oppOwn, activeOppSlot)
                result = (self:GetAttackMultiplier(abPetType, oppType, noHints) > 1.05)
            elseif abPropLower == "weak" then
                local oppType = C_PetBattles.GetPetType(oppOwn, activeOppSlot)
                result = (self:GetAttackMultiplier(abPetType, oppType, noHints) < 0.95)
            else
                local dOp, dVal = string.match(abPropLower, "^duration%s*([=~<>!]+)%s*(.+)$")
                if dOp and dVal then
                    local _, cd, lockdown = C_PetBattles.GetAbilityState(own, slot, abIdx)
                    local remain = math.max(tonumber(cd) or 0, tonumber(lockdown) or 0)
                    result = EvalNumericComparison(remain, dOp, dVal)
                else
                    local tOp, tVal = string.match(abProp, "^[tT][yY][pP][eE]%s*([=~<>!]+)%s*(.+)$")
                    if tOp and tVal then
                        result = EvalNumericComparison(abPetType or 0, tOp, tVal, PET_TYPE_MAP)
                    end
                end
            end
            return ApplyConditionNegation(result, neg)
        end

        -- 3.6 光环条件：aura(...).exists / .duration
        local auraArg, auraProp = string.match(propExpr, "^[aA][uU][rR][aA]%(([^%)]+)%)%.(.+)$")
        if not auraArg then
            auraArg, auraProp = string.match(propExpr, "^[bB][uU][fF][fF]%(([^%)]+)%)%.(.+)$")
        end
        if not auraArg then
            auraArg, auraProp = string.match(propExpr, "^[dD][eE][bB][uU][fF][fF]%(([^%)]+)%)%.(.+)$")
        end
        if not auraArg then
            auraArg, auraProp = string.match(propExpr, "^%(([^%)]+)%)%.(.+)$")
        end
        if auraArg and auraProp then
            local has, turns = self:HasAura(own, slot, auraArg)
            local aPropLower = strlower(auraProp)
            if aPropLower == "exists" then
                result = has
            else
                local dOp, dVal = string.match(aPropLower, "^duration%s*([=~<>!]+)%s*(.+)$")
                if dOp and dVal then
                    result = has and EvalNumericComparison(turns, dOp, dVal) or false
                end
            end
            return ApplyConditionNegation(result, neg)
        end

        -- 3.7 血量衍生条件：hp.full / hp.high / hp.low / hp.can_explode / hp.explode
        if propLower == "hp.full" or propLower == "hpp.full" then
            local hp = C_PetBattles.GetHealth(own, slot) or 0
            local maxHp = C_PetBattles.GetMaxHealth(own, slot) or 1
            result = (hp > 0 and hp >= maxHp)
            return ApplyConditionNegation(result, neg)
        elseif propLower == "hp.high" then
            local myHp = C_PetBattles.GetHealth(own, slot) or 0
            local oppHp = C_PetBattles.GetHealth(oppOwn, activeOppSlot) or 0
            result = (myHp > oppHp)
            return ApplyConditionNegation(result, neg)
        elseif propLower == "hp.low" then
            local myHp = C_PetBattles.GetHealth(own, slot) or 0
            local oppHp = C_PetBattles.GetHealth(oppOwn, activeOppSlot) or 0
            result = (myHp < oppHp)
            return ApplyConditionNegation(result, neg)
        elseif propLower == "hp.explode" then
            if own == ally then
                result = self:CanExplodeKill(ally, slot, enemy, activeEnemy)
            else
                result = self:CanExplodeKill(ally, activeAlly, enemy, slot)
            end
            return ApplyConditionNegation(result, neg)
        elseif propLower == "hp.can_explode" then
            result = self:CanExplodeKill(oppOwn, activeOppSlot, own, slot)
            return ApplyConditionNegation(result, neg)
        end

        -- 3.8 绝对血量 (hp) 与百分比血量 (hpp) 数值比较
        local hpType, hpOp, hpVal = string.match(propLower, "^(hp+)%s*([=~<>!]+)%s*(.+)$")
        if hpType and hpOp and hpVal then
            local curVal = (hpType == "hpp") and self:GetPetHPPct(own, slot) or (C_PetBattles.GetHealth(own, slot) or 0)
            result = EvalNumericComparison(curVal, hpOp, hpVal)
            return ApplyConditionNegation(result, neg)
        end

        -- 3.9 速度衍生与比较：speed.fast / speed.slow / speed < 200
        if propLower == "speed.fast" then
            local mySpd = C_PetBattles.GetSpeed(own, slot) or 0
            local oppSpd = C_PetBattles.GetSpeed(oppOwn, activeOppSlot) or 0
            result = (mySpd > oppSpd)
            return ApplyConditionNegation(result, neg)
        elseif propLower == "speed.slow" then
            local mySpd = C_PetBattles.GetSpeed(own, slot) or 0
            local oppSpd = C_PetBattles.GetSpeed(oppOwn, activeOppSlot) or 0
            result = (mySpd < oppSpd)
            return ApplyConditionNegation(result, neg)
        end

        local spdOp, spdVal = string.match(propLower, "^speed%s*([=~<>!]+)%s*(.+)$")
        if spdOp and spdVal then
            result = EvalNumericComparison(C_PetBattles.GetSpeed(own, slot) or 0, spdOp, spdVal)
            return ApplyConditionNegation(result, neg)
        end

        -- 3.10 攻击 (power)、等级 (level / level.max)、物种ID (id)、品质 (quality)、类型 (type)
        local pwrOp, pwrVal = string.match(propLower, "^power%s*([=~<>!]+)%s*(.+)$")
        if pwrOp and pwrVal then
            result = EvalNumericComparison(C_PetBattles.GetPower(own, slot) or 0, pwrOp, pwrVal)
            return ApplyConditionNegation(result, neg)
        end

        if propLower == "level.max" then
            result = ((C_PetBattles.GetLevel(own, slot) or 1) >= 25)
            return ApplyConditionNegation(result, neg)
        end

        local lvOp, lvVal = string.match(propLower, "^level%s*([=~<>!]+)%s*(.+)$")
        if lvOp and lvVal then
            result = EvalNumericComparison(C_PetBattles.GetLevel(own, slot) or 1, lvOp, lvVal)
            return ApplyConditionNegation(result, neg)
        end

        local idOp, idVal = string.match(propLower, "^id%s*([=~<>!]+)%s*(.+)$")
        if idOp and idVal then
            result = EvalNumericComparison(C_PetBattles.GetPetSpeciesID(own, slot) or 0, idOp, idVal)
            return ApplyConditionNegation(result, neg)
        end

        local qOp, qVal = string.match(propExpr, "^[qQ][uU][aA][lL][iI][tT][yY]%s*([=~<>!]+)%s*(.+)$")
        if qOp and qVal then
            local rawQ = (C_PetBattles.GetBreedQuality(own, slot) or 0) + 1
            result = EvalNumericComparison(rawQ, qOp, qVal, QUALITY_MAP)
            return ApplyConditionNegation(result, neg)
        end

        local tOp, tVal = string.match(propExpr, "^[tT][yY][pP][eE]%s*([=~<>!]+)%s*(.+)$")
        if tOp and tVal then
            local pType = C_PetBattles.GetPetType(own, slot) or 1
            result = EvalNumericComparison(pType, tOp, tVal, PET_TYPE_MAP)
            return ApplyConditionNegation(result, neg)
        end
    end

    return ApplyConditionNegation(result, neg)
end

local function CompileConditionExpr(expr)
    if not expr or strtrim(expr) == "" then return nil, nil end
    local norm = string.gsub(expr, "%s+[aA][nN][dD]%s+", "&")
    norm = string.gsub(norm, "%s+[oO][rR]%s+", "|")

    if not string.find(norm, "|", 1, true) then
        local parts = {}
        for part in string.gmatch(norm, "[^&]+") do
            local trimmed = strtrim(part)
            if trimmed ~= "" then
                parts[#parts + 1] = trimmed
            end
        end
        return ((#parts > 0) and parts or nil), nil
    end

    local orGroups = {}
    for orBranch in string.gmatch(norm, "[^|]+") do
        local andParts = {}
        for part in string.gmatch(orBranch, "[^&]+") do
            local trimmed = strtrim(part)
            if trimmed ~= "" then
                andParts[#andParts + 1] = trimmed
            end
        end
        if #andParts > 0 then
            orGroups[#orGroups + 1] = andParts
        end
    end
    return nil, ((#orGroups > 0) and orGroups or nil)
end

function ns.ScriptEngine:EvalCondParts(parts)
    if not parts then return true end
    for i = 1, #parts do
        if not self:EvalSingleCond(parts[i]) then
            return false
        end
    end
    return true
end

function ns.ScriptEngine:EvalInstCond(inst)
    if inst.condOrGroups then
        local groups = inst.condOrGroups
        for i = 1, #groups do
            if self:EvalCondParts(groups[i]) then
                return true
            end
        end
        return false
    end
    if inst.condParts then
        return self:EvalCondParts(inst.condParts)
    end
    return true
end

function ns.ScriptEngine:GetCompiledOps(rawScript)
    rawScript = rawScript or "use(1)"
    if self._cachedRawScript == rawScript and self._cachedOps then
        return self._cachedOps
    end

    local scriptText = ns.Syntax and ns.Syntax:StripColors(rawScript) or rawScript
    local ops = {}

    for rawLine in string.gmatch(scriptText, "[^\r\n]+") do
        local line = strtrim(rawLine)
        if line ~= "" and not string.find(line, "^%-%-") and not string.find(line, "^#") then
            local commentPos = string.find(line, "--", 1, true)
            if commentPos and commentPos > 1 then
                line = strtrim(string.sub(line, 1, commentPos - 1))
            end

            local firstWord = strlower(string.match(line, "^([a-zA-Z_]+)") or "")
            local lineLower = strlower(line)

            if firstWord == "if" then
                local ifExpr = ExtractIfCondition(line, "[iI][fF]")
                local cParts, cOr = CompileConditionExpr(ifExpr)
                ops[#ops + 1] = { op = "IF", condParts = cParts, condOrGroups = cOr }
            elseif firstWord == "elseif" then
                local elseifExpr = ExtractIfCondition(line, "[eE][lL][sS][eE][iI][fF]")
                local cParts, cOr = CompileConditionExpr(elseifExpr)
                ops[#ops + 1] = { op = "ELSEIF", condParts = cParts, condOrGroups = cOr }
            elseif lineLower == "else" then
                ops[#ops + 1] = { op = "ELSE" }
            elseif lineLower == "end" or lineLower == "endif" then
                ops[#ops + 1] = { op = "END" }
            else
                local actionPart, bracketCond = string.match(line, "^(.-)%s*%[(.+)%]%s*$")
                if not actionPart then
                    actionPart = line
                    bracketCond = nil
                else
                    actionPart = strtrim(actionPart)
                end

                local cParts, cOr = CompileConditionExpr(bracketCond)
                local inst = {
                    op           = "ACT",
                    condParts    = cParts,
                    condOrGroups = cOr,
                }

                local actLower = strlower(actionPart)
                local changeArg = string.match(actionPart, "^[cC][hH][aA][nN][gG][eE]%s*%(([^%)]+)%)")
                local testArg = string.match(actionPart, "^[tT][eE][sS][tT]%s*%(([^%)]*)%)")

                if changeArg then
                    changeArg = strtrim(changeArg)
                    inst.isChange = true
                    inst.changeRawArg = changeArg
                    if strlower(changeArg) == "next" then
                        inst.changeNext = true
                    else
                        local slotNum = tonumber(string.match(changeArg, "^#(%d)$"))
                        if slotNum then
                            inst.changeSlot = slotNum
                        end
                    end
                elseif actLower == "quit" then
                    inst.isQuit = true
                elseif testArg ~= nil or actLower == "test" then
                    inst.isTest = true
                    inst.testMsg = (testArg and testArg ~= "") and testArg or ns:T("test 条件命中")
                else
                    local useArg = string.match(actionPart, "^[uU][sS][eE]%s*%(([^%)]+)%)")
                        or string.match(actionPart, "^[aA][bB][iI][lL][iI][tT][yY]%s*%(([^%)]+)%)")
                    if useArg then
                        useArg = strtrim(useArg)
                        inst.isUse = true
                        inst.useRawArg = useArg

                        local explicitID = tonumber(string.match(useArg, ":(%d+)$"))
                        local abIndex = nil
                        if not explicitID then
                            local pureNum = tonumber(string.match(useArg, "^#?(%d+)$"))
                            if pureNum and pureNum <= 3 then
                                abIndex = pureNum
                            elseif pureNum and pureNum > 3 then
                                explicitID = pureNum
                            end
                        end
                        inst.abIndex = abIndex
                        inst.explicitID = explicitID
                        if not abIndex and not explicitID then
                            local namePart = strtrim(string.match(useArg, "^([^:]+)") or useArg)
                            inst.nameLower = strlower(namePart)
                        end
                    elseif actLower == "standby" or actLower == "pass" then
                        inst.isPass = true
                    elseif actLower == "trap" or actLower == "catch" then
                        inst.isTrap = true
                    end
                end

                ops[#ops + 1] = inst
            end
        end
    end

    self._cachedRawScript = rawScript
    self._cachedOps = ops
    return ops
end

local execStackPool = {}

function ns.ScriptEngine:ExecuteStep()
    if ns.ScriptEditBox and ns.ScriptEditBox:HasFocus() then return end
    if not C_PetBattles or not C_PetBattles.IsInBattle() then return end
    if self.isPaused then return end
    if not self.battleStateKnown then
        if ns.ShowUIFeedback then ns:ShowUIFeedback(ns:T("重载后无法确认回合，请手动完成本场战斗")) end
        return
    end

    local now = GetTime()
    if now - (self._lastExecTime or 0) < 0.10 then return end
    self._lastExecTime = now

    local owner = Enum.BattlePetOwner.Ally
    local activeSlot = C_PetBattles.GetActivePet(owner)
    if not activeSlot then return end

    if self.playedSlots and self.playedSlots[owner] then
        self.playedSlots[owner][activeSlot] = true
    end
    local enemyOwner = Enum.BattlePetOwner.Enemy
    local activeEnemySlot = C_PetBattles.GetActivePet(enemyOwner)
    if activeEnemySlot and self.playedSlots and self.playedSlots[enemyOwner] then
        self.playedSlots[enemyOwner][activeEnemySlot] = true
    end

    local activeHP = C_PetBattles.GetHealth(owner, activeSlot) or 0
    local needPetSwap = (activeHP <= 0) or (C_PetBattles.ShouldShowPetSelect and C_PetBattles.ShouldShowPetSelect())

    if not needPetSwap and C_PetBattles.IsSkipAvailable and not C_PetBattles.IsSkipAvailable() then
        return
    end

    local team = ns.db.teams[ns.db.selectedTeamIdx]
    local ops = self:GetCompiledOps((team and team.script) or "use(1)")
    local stackDepth = 0
    local currentActive = true

    for i = 1, #ops do
        local inst = ops[i]
        local op = inst.op

        if op == "IF" then
            local parentActive = currentActive
            local condMet = parentActive and self:EvalInstCond(inst) or false
            stackDepth = stackDepth + 1
            local frame = execStackPool[stackDepth]
            if not frame then
                frame = {}
                execStackPool[stackDepth] = frame
            end
            frame.parentActive = parentActive
            frame.branchTaken  = condMet
            frame.active       = condMet
            currentActive = condMet

        elseif op == "ELSEIF" then
            local top = (stackDepth > 0) and execStackPool[stackDepth] or nil
            if top then
                if not top.parentActive or top.branchTaken then
                    top.active = false
                else
                    local condMet = self:EvalInstCond(inst)
                    top.active = condMet
                    if condMet then top.branchTaken = true end
                end
                currentActive = top.active
            end

        elseif op == "ELSE" then
            local top = (stackDepth > 0) and execStackPool[stackDepth] or nil
            if top then
                top.active = top.parentActive and (not top.branchTaken) or false
                top.branchTaken = true
                currentActive = top.active
            end

        elseif op == "END" then
            if stackDepth > 0 then
                stackDepth = stackDepth - 1
            end
            local top = (stackDepth > 0) and execStackPool[stackDepth] or nil
            if top then currentActive = top.active else currentActive = true end

        elseif currentActive and self:EvalInstCond(inst) then
            if inst.isTest then
                DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[Wish Pet Tactics Test]|r " .. tostring(inst.testMsg))
                self:AddLog("|cff38bdf8test:|r " .. tostring(inst.testMsg))

            elseif inst.isQuit then
                if C_PetBattles and C_PetBattles.ForfeitGame then
                    C_PetBattles.ForfeitGame()
                    self:AddLog("|cffff4040" .. ns:T("quit (退出对战)") .. "|r")
                    return
                end

            elseif inst.isChange then
                if inst.changeNext then
                    for offset = 1, 2 do
                        local nextSlot = ((activeSlot - 1 + offset) % 3) + 1
                        if self:CanSwapToSlot(nextSlot) then
                            C_PetBattles.ChangePet(nextSlot)
                            self:AddLog(string.format("change -> |cff61afef#%d|r", nextSlot))
                            return
                        end
                    end
                else
                    local targetSlot = inst.changeSlot or self:ResolvePetSlot(owner, inst.changeRawArg, false)
                    if targetSlot and self:CanSwapToSlot(targetSlot) then
                        C_PetBattles.ChangePet(targetSlot)
                        self:AddLog(string.format("change -> |cff61afef#%d|r", targetSlot))
                        return
                    end
                end

            elseif not needPetSwap then
                if inst.isUse then
                    local abIndex = inst.abIndex
                    if not abIndex and inst.explicitID then
                        for idx = 1, 3 do
                            local id = C_PetBattles.GetAbilityInfo(owner, activeSlot, idx)
                            if id == inst.explicitID then
                                abIndex = idx
                                break
                            end
                        end
                    elseif not abIndex and inst.nameLower then
                        for idx = 1, 3 do
                            local _, name = C_PetBattles.GetAbilityInfo(owner, activeSlot, idx)
                            if name and string.find(strlower(name), inst.nameLower, 1, true) then
                                abIndex = idx
                                break
                            end
                        end
                    end

                    if abIndex and abIndex >= 1 and abIndex <= 3 then
                        local isUsable = C_PetBattles.GetAbilityState(owner, activeSlot, abIndex)
                        if isUsable then
                            local _, abName = C_PetBattles.GetAbilityInfo(owner, activeSlot, abIndex)
                            C_PetBattles.UseAbility(abIndex)
                            self:AddLog(string.format("use: |cff10b981%s (#%d)|r", abName or inst.useRawArg, abIndex))
                            return
                        end
                    end

                elseif inst.isTrap then
                    if C_PetBattles.IsTrapAvailable and C_PetBattles.IsTrapAvailable() and C_PetBattles.UseTrap then
                        C_PetBattles.UseTrap()
                        self:AddLog("|cff61afefcatch/trap|r")
                        return
                    end

                elseif inst.isPass then
                    if C_PetBattles.IsSkipAvailable and C_PetBattles.IsSkipAvailable() then
                        C_PetBattles.SkipTurn()
                        self:AddLog("|cfff59e0bstandby|r")
                        return
                    end
                end
            end
        end
    end

    if needPetSwap then
        for offset = 1, 2 do
            local nextSlot = ((activeSlot - 1 + offset) % 3) + 1
            if self:CanSwapToSlot(nextSlot) then
                C_PetBattles.ChangePet(nextSlot)
                self:AddLog(string.format("Dead Swap -> |cff3b82f6#%d|r", nextSlot))
                return
            end
        end
        return
    end

    for idx = 1, 3 do
        local isUsable = C_PetBattles.GetAbilityState(owner, activeSlot, idx)
        if isUsable then
            local _, abName = C_PetBattles.GetAbilityInfo(owner, activeSlot, idx)
            C_PetBattles.UseAbility(idx)
            self:AddLog(string.format("use: |cff10b981%s|r", abName or ("#" .. idx)))
            return
        end
    end

    if C_PetBattles.IsSkipAvailable and C_PetBattles.IsSkipAvailable() then
        C_PetBattles.SkipTurn()
    end
end

-- ==================== 6. 战斗角色经验快照统计器 ====================
local function SnapshotBattleStartStats()
    local st = ns.BattleStats
    st.battleStartTime = GetTime()
    local uXP = UnitXP("player")
    local uMax = UnitXPMax("player")
    local uLv = UnitLevel("player")
    st.lastPlayerXP = (not ns:IsSecretValue(uXP) and tonumber(uXP)) or 0
    st.lastPlayerMaxXP = math.max(1, (not ns:IsSecretValue(uMax) and tonumber(uMax)) or 1)
    st.lastPlayerLevel = (not ns:IsSecretValue(uLv) and tonumber(uLv)) or 1
end

local function RecordBattleEndStats()
    local st = ns.BattleStats
    if st.battleStartTime and st.battleStartTime > 0 then
        st.lastBattleDuration = math.max(8, GetTime() - st.battleStartTime)
        st.battlesCount = (st.battlesCount or 0) + 1
    end

    local uXP = UnitXP("player")
    local uMax = UnitXPMax("player")
    local uLv = UnitLevel("player")
    local curXP = (not ns:IsSecretValue(uXP) and tonumber(uXP)) or 0
    local curMaxXP = math.max(1, (not ns:IsSecretValue(uMax) and tonumber(uMax)) or 1)
    local curLv = (not ns:IsSecretValue(uLv) and tonumber(uLv)) or 1

    local gainedPlayerXP = 0
    if curLv > (st.lastPlayerLevel or curLv) then
        gainedPlayerXP = math.max(0, (st.lastPlayerMaxXP - st.lastPlayerXP) + curXP)
    elseif curXP > (st.lastPlayerXP or 0) then
        gainedPlayerXP = curXP - st.lastPlayerXP
    end
    if gainedPlayerXP > 0 then
        st.lastBattlePlayerXP = gainedPlayerXP
        st.totalPlayerXP = (st.totalPlayerXP or 0) + gainedPlayerXP
    end
    st.lastPlayerXP = curXP
    st.lastPlayerMaxXP = curMaxXP
    st.lastPlayerLevel = curLv
end

local function CaptureBattleEndLoadout()
    local petIDs = {}
    for slot = 1, 3 do
        petIDs[slot] = C_PetJournal.GetPetLoadOutInfo(slot)
    end
    return petIDs
end

local function GetSameSpeciesReplacementSlots(previousPetIDs)
    local changedSlots = {}
    for slot = 1, 3 do
        local previousPetID = previousPetIDs and previousPetIDs[slot]
        local currentPetID = C_PetJournal.GetPetLoadOutInfo(slot)
        if previousPetID and currentPetID and previousPetID ~= currentPetID then
            local previousSpecies = C_PetJournal.GetPetInfoByPetID(previousPetID)
            local currentSpecies = C_PetJournal.GetPetInfoByPetID(currentPetID)
            if previousSpecies and currentSpecies and previousSpecies == currentSpecies then
                changedSlots[#changedSlots + 1] = tostring(slot)
            end
        end
    end
    return table.concat(changedSlots, "、")
end

local function GetBattleReportRoute(currentTeam)
    local routing = ns.AutoRouting
    local npcID, npcName = routing:GetUnitNPCID("target")
    return routing:FindRouteForTarget(npcID, npcName)
        or ns:FindRouteContainingTeam(currentTeam.name)
        or (ns.db.routeMappings and ns.db.routeMappings[ns.db.lastActiveRouteKey])
end

local function HasHealthyBattleCandidate(currentTeam, route)
    local routing = ns.AutoRouting
    local evaluation = {}
    if routing:CanTeamFight(currentTeam, true, evaluation) then return true end
    if route and route.teams and #route.teams > 0 then
        for _, name in ipairs(route.teams) do
            local team = routing:FindTeamByName(name)
            if team and team ~= currentTeam and routing:CanTeamFight(team, true, evaluation) then return true end
        end
    else
        local group = currentTeam.group or "未分组队伍"
        for _, team in ipairs(ns.db.teams) do
            if team ~= currentTeam and (team.group or "未分组队伍") == group
                and routing:CanTeamFight(team, true, evaluation) then return true end
        end
    end
    return false
end

local function ShowBattleEndTeamReport(previousTeam, previousPetIDs)
    if not ns.db or not ns.db.settings or not ns.db.teams then return end
    local reportText
    local currentTeam = ns.db.teams[ns.db.selectedTeamIdx]
    if not currentTeam then
        reportText = ns:T("战斗结束：没有可用队伍")
    else
        local routing = ns.AutoRouting
        local currentHealthy = routing:IsCurrentLoadoutHealthyAndReady(currentTeam)
        local currentStatus = currentHealthy and ns:T("健康") or ns:T("尚未健康")
        local changedSlots = (currentTeam == previousTeam) and GetSameSpeciesReplacementSlots(previousPetIDs) or ""
        local route = GetBattleReportRoute(currentTeam)
        local sequence = BattleTeamSequence(currentTeam, route)

        if not currentHealthy and not HasHealthyBattleCandidate(currentTeam, route) then
            reportText = "|cffff4040" .. ns:T("当前队伍不健康，且没有可用替换队伍") .. "|r"
            if ns:IsRevivePetCooldownReady() then
                reportText = reportText .. " · |cffff4040" .. ns:T("复活战斗宠物已就绪") .. "|r"
            end
        elseif ns.db.settings.battleEndTeamReport == false then
            return
        elseif currentTeam ~= previousTeam then
            reportText = ns:TF("已切换到 %s 号队伍", sequence)
        elseif changedSlots ~= "" then
            reportText = ns:TF("%s 号队伍已换宠（%s 号槽）· %s", sequence, changedSlots, currentStatus)
        else
            reportText = ns:TF("%s 号队伍 · %s", sequence, currentStatus)
        end
    end

    if ns.db.settings.battleEndTeamReport == false and not currentTeam then return end
    if ns.ShowUIFeedback then ns:ShowUIFeedback(reportText) end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff10b981[Wish Pet Tactics]|r " .. reportText)
    end
end

-- ==================== 7. 统一事件总线监听（主城点玩家短路 + 常规副本休眠 + 自装宠事件防风暴） ====================
local lastAutoCheckTime = 0
local lastKnownCollectedCount = -1
local lastKnownTotalCount = -1
local lastJournalInvalidateTime = 0
local pendingAutoCheckDue = {}
local battleEndReportSerial = 0

local function ThrottledEnsurePrepared(delay)
    if IsInRestrictedCombatInstance() then return end
    local alreadyPending = pendingAutoCheckDue[delay] ~= nil
    pendingAutoCheckDue[delay] = GetTime() + delay
    if alreadyPending then return end
    local function Run()
        local due = pendingAutoCheckDue[delay]
        if not due then return end
        local now = GetTime()
        if now < due then C_Timer.After(due - now, Run); return end
        pendingAutoCheckDue[delay] = nil
        if now - lastAutoCheckTime < 0.25 then
            pendingAutoCheckDue[delay] = lastAutoCheckTime + 0.25
            C_Timer.After(math.max(0.01, pendingAutoCheckDue[delay] - now), Run)
            return
        end
        lastAutoCheckTime = now
        if ns.db and ns.db.settings.autoLoadTarget and not IsInRestrictedCombatInstance() then
            ns.AutoRouting:EnsurePreparedRouteAndTeam()
        end
    end
    C_Timer.After(delay, Run)
end

local journalRefreshPending = false
local journalRefreshNeedsFull = false

local function RefreshAfterJournalUpdate()
    local needsFull = journalRefreshNeedsFull
    journalRefreshPending = false
    journalRefreshNeedsFull = false
    local mainVisible = ns.MainFrame and ns.MainFrame:IsVisible()
    local routingVisible = ns.RoutingModal and ns.RoutingModal:IsVisible()
    if not mainVisible and not routingVisible then return end

    if needsFull and ns.InvalidatePetAndTeamCache then
        lastJournalInvalidateTime = GetTime()
        ns:InvalidatePetAndTeamCache()
    end

    if not mainVisible then
        ns.RoutingModal:Refresh()
    elseif not needsFull and ns.RefreshMiddleCards then
        ns:RefreshMiddleCards()
        if ns.UpdateHeaderToolButtons then ns:UpdateHeaderToolButtons() end
        if routingVisible then ns.RoutingModal:Refresh() end
    elseif ns.RefreshAllUI then
        ns:RefreshAllUI()
    end
end

local engineFrame = CreateFrame("Frame")
engineFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
engineFrame:RegisterEvent("PLAYER_LOGOUT")
engineFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
engineFrame:RegisterEvent("GOSSIP_SHOW")
engineFrame:RegisterEvent("GOSSIP_CLOSED")
engineFrame:RegisterEvent("SCENARIO_UPDATE")
engineFrame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
engineFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
engineFrame:RegisterEvent("PET_BATTLE_OPENING_START")
engineFrame:RegisterEvent("PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE")
engineFrame:RegisterEvent("PET_BATTLE_PET_CHANGED")
engineFrame:RegisterEvent("PET_BATTLE_ACTION_SELECTED")
engineFrame:RegisterEvent("PET_BATTLE_CLOSE")
engineFrame:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
if engineFrame.RegisterUnitEvent then
    engineFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
else
    engineFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end
engineFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
engineFrame:RegisterEvent("PLAYER_XP_UPDATE")

local wasReviveReady = true
local lastCooldownPollTime = 0
local inRoundPlayback = false
local reviveTimer
local function ScheduleReviveReadyCheck()
    if reviveTimer then reviveTimer:Cancel(); reviveTimer = nil end
    local remaining = ns:GetRevivePetCooldownRemain()
    if remaining <= 0 then return end
    reviveTimer = C_Timer.NewTimer(remaining + 0.2, function()
        reviveTimer = nil
        local left = ns:GetRevivePetCooldownRemain()
        if left > 0 then ScheduleReviveReadyCheck(); return end
        if not wasReviveReady then
            wasReviveReady = true
            ns._reviveResetPending = true
            if ns.ShowUIFeedback then ns:ShowUIFeedback("|cffff4040" .. ns:T("复活战斗宠物已就绪") .. "|r") end
            ThrottledEnsurePrepared(0.3)
        end
    end)
end

-- Use stable battle-level identifiers so reload recovery succeeds regardless of mid-turn HP/slot state.
local function BattleReloadSignature()
    local ally, enemy = Enum.BattlePetOwner.Ally, Enum.BattlePetOwner.Enemy
    return table.concat({
        UnitGUID("player") or "",
        C_PetBattles.GetNumPets(ally) or 0,
        C_PetBattles.GetNumPets(enemy) or 0,
        C_PetBattles.GetPetSpeciesID(ally, 1) or 0,
        C_PetBattles.GetPetSpeciesID(enemy, 1) or 0,
        C_PetBattles.GetPetSpeciesID(enemy, 2) or 0,
        C_PetBattles.GetPetSpeciesID(enemy, 3) or 0,
    }, ":")
end
local gossipGeneration = 0
function ns.AutoRouting:GetGossipSession() return gossipGeneration end
local gossipDebugEnabled = false
local function GossipTrace(label, ...)
    if not gossipDebugEnabled then return end
    local fields = {}
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if ns:IsSecretValue(value) then
            fields[i] = "<secret>"
        elseif value == nil then
            fields[i] = "<nil>"
        elseif type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
            fields[i] = tostring(value)
        else
            fields[i] = "<" .. type(value) .. ">"
        end
    end
    print(ns:T("|cff38bdf8[Wish 对话诊断]|r ") .. label .. " " .. table.concat(fields, " / "))
end
local function GossipSnapshot(options)
    if not gossipDebugEnabled then return end
    local function Read(label, fn, ...)
        if not fn then GossipTrace(label, "接口不存在"); return end
        local ok, a, b = pcall(fn, ...)
        GossipTrace(label, ok, a, b)
    end
    Read("npc 名称", UnitName, "npc")
    Read("npc GUID", UnitGUID, "npc")
    Read("target 名称", UnitName, "target")
    Read("target GUID", UnitGUID, "target")
    Read("目标与对话对象是否相同", UnitIsUnit, "target", "npc")
    Read("副本类型", IsInInstance)
    if ns:IsSecretValue(options) or type(options) ~= "table" then
        GossipTrace("选项列表不可读", options); return
    end
    GossipTrace("选项数量", #options)
    for i, opt in ipairs(options) do
        if not ns:IsSecretValue(opt) and type(opt) == "table" then
            GossipTrace("选项 序号/ID/文字", i, opt.gossipOptionID, opt.name)
        end
    end
end
local function SelectGossipWithTrace(optionID)
    if not C_GossipInfo or not C_GossipInfo.GetOptions or not C_GossipInfo.SelectOption
        or ns:IsSecretValue(optionID) then
        GossipTrace("退出：当前对话选项 API/ID 不可用", optionID)
        return false
    end
    local currentOptions = C_GossipInfo.GetOptions()
    local isCurrentOption = false
    for _, opt in ipairs(currentOptions or {}) do
        if not ns:IsSecretValue(opt.gossipOptionID) and opt.gossipOptionID == optionID then
            isCurrentOption = true
            break
        end
    end
    if not isCurrentOption then
        GossipTrace("退出：选项ID已不属于当前对话，拒绝点击", optionID)
        return false
    end
    if not gossipDebugEnabled then return C_GossipInfo.SelectOption(optionID) end
    GossipTrace("调用 SelectOption", optionID)
    local ok, result = pcall(C_GossipInfo.SelectOption, optionID)
    GossipTrace(ok and "SelectOption 已返回（不代表已开战）" or "SelectOption 报错", result)
end
SlashCmdList["WISHGOSSIPDEBUG"] = function(msg)
    gossipDebugEnabled = strlower(strtrim(msg or "")) ~= "off"
    if gossipDebugEnabled then
        print(ns:T("|cff38bdf8[Wish 对话诊断]|r 已开启。请重新打开 NPC 对话。输入 /wp gossip off 关闭。"))
    else
        print(ns:T("|cff38bdf8[Wish 对话诊断]|r 已关闭。"))
    end
end
SLASH_WISHGOSSIPDEBUG1 = "/wpgossip"
SlashCmdList["WISHROUNDDEBUG"] = function()
    local se = ns.ScriptEngine
    local function Text(v)
        if ns:IsSecretValue(v) then return "<secret>" end
        return tostring(v)
    end
    local ally, enemy = Enum.BattlePetOwner.Ally, Enum.BattlePetOwner.Enemy
    print(ns:TF("|cff38bdf8[Wish 回合诊断]|r 总回合=%s 我方上场轮=%s 敌方上场轮=%s 我方槽位=%s 播放中=%s 已完成回合=%s 最近回合事件=%s 已忽略事件=%s",
        Text(se.currentRound), Text(se.sideRound[ally]), Text(se.sideRound[enemy]),
        Text(se.lastActiveSlot[ally]), Text(inRoundPlayback), Text(se.lastCompletedRound or 0),
        Text(se.lastRoundEvent), Text(se.ignoredRoundEvents or 0)))
end
SLASH_WISHROUNDDEBUG1 = "/wpround"
local battleOwners = { 1, 2 }

engineFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    if event == "PLAYER_LOGOUT" then
        local se = ns.ScriptEngine
        if ns.db then
            ns.db.battleReload = nil
            if C_PetBattles and C_PetBattles.IsInBattle()
                and C_PetBattles.IsPlayerNPC(Enum.BattlePetOwner.Enemy) then
                local completed = tonumber(se.lastCompletedRound) or 0
                if inRoundPlayback then
                    completed = completed + 1
                end
                ns.db.battleReload = {
                    savedAt = time and time() or GetTime(),
                    signature = BattleReloadSignature(),
                    completedRound = completed,
                    sideRound = se.sideRound,
                    lastActiveSlot = se.lastActiveSlot,
                    playedSlots = se.playedSlots,
                    battleStartTime = ns.BattleStats.battleStartTime,
                }
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        local snapshot = ns.db and ns.db.battleReload
        if ns.db then ns.db.battleReload = nil end
        if C_PetBattles and C_PetBattles.IsInBattle() then
            local se = ns.ScriptEngine
            local ally = Enum.BattlePetOwner.Ally
            local enemy = Enum.BattlePetOwner.Enemy
            battleOwners[1] = ally
            battleOwners[2] = enemy
            local curTime = time and time() or GetTime()
            local age = snapshot and snapshot.savedAt and (curTime - snapshot.savedAt)
            local snapshotMatched = (age and age >= 0 and age <= 180 and snapshot.signature == BattleReloadSignature()) and true or false

            se.battleStateKnown = true
            se.resumedBattle = true
            inRoundPlayback = false
            se._lastExecTime = 0
            if snapshotMatched then
                se.lastCompletedRound = tonumber(snapshot.completedRound) or 0
                se.currentRound = se.lastCompletedRound + 1
                se.sideRound = snapshot.sideRound or {}
                se.lastActiveSlot = snapshot.lastActiveSlot or {}
                se.playedSlots = snapshot.playedSlots or {}
                se.sideRound[ally] = se.sideRound[ally] or 1
                se.sideRound[enemy] = se.sideRound[enemy] or 1
                se.lastActiveSlot[ally] = C_PetBattles.GetActivePet(ally) or se.lastActiveSlot[ally] or 1
                se.lastActiveSlot[enemy] = C_PetBattles.GetActivePet(enemy) or se.lastActiveSlot[enemy] or 1
                se.playedSlots[ally] = se.playedSlots[ally] or {}
                se.playedSlots[enemy] = se.playedSlots[enemy] or {}
                se.playedSlots[ally][se.lastActiveSlot[ally]] = true
                se.playedSlots[enemy][se.lastActiveSlot[enemy]] = true
                ns.BattleStats.battleStartTime = snapshot.battleStartTime or GetTime()
            else
                local aSlot = C_PetBattles.GetActivePet(ally) or 1
                local eSlot = C_PetBattles.GetActivePet(enemy) or 1
                se.lastCompletedRound = 0
                se.currentRound = 1
                se.sideRound[ally] = 1
                se.sideRound[enemy] = 1
                se.lastActiveSlot[ally] = aSlot
                se.lastActiveSlot[enemy] = eSlot
                wipe(se.playedSlots[ally])
                wipe(se.playedSlots[enemy])
                se.playedSlots[ally][aSlot] = true
                se.playedSlots[enemy][eSlot] = true
                ns.BattleStats.battleStartTime = GetTime()
            end
            se.swappedInRound[ally] = false
            se.swappedInRound[enemy] = false
            se:AddLog(string.format(ns:T("就绪 - 按 |cff3b82f6[%s]|r 执行"), ns.FormatHotKeyDisplay and ns:FormatHotKeyDisplay() or "SPACE"))
            if ns.ShowBattleHUD then ns:ShowBattleHUD(true) end
            if ns.SetupBattleEnemyBreedHUD then ns:SetupBattleEnemyBreedHUD() end
            C_Timer.After(0.25, function()
                if C_PetBattles and C_PetBattles.IsInBattle() then
                    if ns.ShowBattleHUD then ns:ShowBattleHUD(true) end
                    if ns.SetupBattleEnemyBreedHUD then ns:SetupBattleEnemyBreedHUD() end
                    if ns.UpdateBattleEnemyBreedDisplay then ns:UpdateBattleEnemyBreedDisplay() end
                    if ns.ApplyBattleHotKeyBinding then ns:ApplyBattleHotKeyBinding() end
                    if ns.UpdateBattleHUD then ns:UpdateBattleHUD() end
                end
            end)
        end
        if ns.InvalidatePetAndTeamCache then
            ns:InvalidatePetAndTeamCache()
        end
        local numTotal, numCol = C_PetJournal.GetNumPets()
        lastKnownCollectedCount = numCol or -1
        lastKnownTotalCount = numTotal or -1
        ResetScenarioSelection()
        local uXP = UnitXP("player")
        local uMax = UnitXPMax("player")
        local uLv = UnitLevel("player")
        ns.BattleStats.lastPlayerXP = (not ns:IsSecretValue(uXP) and tonumber(uXP)) or 0
        ns.BattleStats.lastPlayerMaxXP = math.max(1, (not ns:IsSecretValue(uMax) and tonumber(uMax)) or 1)
        ns.BattleStats.lastPlayerLevel = (not ns:IsSecretValue(uLv) and tonumber(uLv)) or 1
        wasReviveReady = ns:IsRevivePetCooldownReady()
        if wasReviveReady and not (C_PetBattles and C_PetBattles.IsInBattle()) then
            ns._reviveResetPending = true
        end
        ScheduleReviveReadyCheck()
        if not IsInRestrictedCombatInstance() then
            ThrottledEnsurePrepared(1.2)
        elseif ns.DungeonStageBar then
            ns.DungeonStageBar:Hide()
        end

    elseif event == "SCENARIO_UPDATE" or event == "SCENARIO_CRITERIA_UPDATE" or event == "ZONE_CHANGED_NEW_AREA" then
        if event == "ZONE_CHANGED_NEW_AREA" then
            ResetScenarioSelection()
            ns:UpdateDungeonStageBanner(nil)
        end
        if IsInRestrictedCombatInstance() then
            if ns.DungeonStageBar then ns.DungeonStageBar:Hide() end
            return
        end
        if not InCombatLockdown() then
            ThrottledEnsurePrepared(0.35)
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        if not ns.db or not ns.db.settings.autoLoadTarget then return end
        if InCombatLockdown() or (C_PetBattles and C_PetBattles.IsInBattle()) then return end
        if IsInRestrictedCombatInstance() then return end

        local npcID, npcName = ns.AutoRouting:GetUnitNPCID("target")
        local inScenario = C_Scenario and C_Scenario.IsInScenario and C_Scenario.IsInScenario()
        if npcID or npcName or inScenario then
            ns.AutoRouting:EnsurePreparedRouteAndTeam(true)
        end

    elseif event == "GOSSIP_CLOSED" then
        gossipGeneration = gossipGeneration + 1
        GossipTrace("GOSSIP_CLOSED")
        if ns.GossipLearningModal then ns.GossipLearningModal:Hide() end

    elseif event == "GOSSIP_SHOW" then
        gossipGeneration = gossipGeneration + 1
        if ns.GossipLearningModal then ns.GossipLearningModal:Hide() end
        GossipTrace("GOSSIP_SHOW")
        if not ns.db then GossipTrace("退出：存档未初始化"); return end
        if InCombatLockdown() then GossipTrace("退出：角色战斗锁定"); return end
        if IsInRestrictedCombatInstance() then GossipTrace("退出：常规副本休眠判断"); return end
        if (ns.staging and ns.staging.isDirty) or (ns.MainFrame and ns.MainFrame.compactDraft) then
            GossipTrace("退出：队伍编辑尚未保存")
            return
        end
        GossipTrace("设置 自动对话/自动加载", ns.db.settings.autoGossip, ns.db.settings.autoLoadTarget)

        local options = C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.GetOptions()
        GossipSnapshot(options)
        local npcID, npcName
        if gossipDebugEnabled then
            local ok, a, c = pcall(ns.AutoRouting.GetDialogNPCID, ns.AutoRouting, options)
            if not ok then GossipTrace("退出：身份解析报错", a); return end
            npcID, npcName = a, c
        else
            npcID, npcName = ns.AutoRouting:GetDialogNPCID(options)
        end
        GossipTrace("解析后 NPC ID/名称", npcID, npcName)
        local inScenario = IsInScenario()
        local route, rKey, stageMatches
        local verifiedOptionID

        -- Public, verified option IDs can identify a speaker whose unit
        -- name/GUID is secret. An existing binding is still required.
        for _, opt in ipairs(options or {}) do
            local optionID = opt.gossipOptionID
            local known = not ns:IsSecretValue(optionID) and KNOWN_PET_BATTLE_GOSSIP[optionID]
            if known and (not known.npcID or not npcID or npcID == known.npcID) then
                route, rKey = FindKnownGossipRoute(known, npcName)
                if route then verifiedOptionID = optionID end
                break
            end
        end

        local explicitRoute, explicitKey, explicitOption = GetExplicitGossipRoute(options, npcID, npcName)
        if explicitRoute then
            route, rKey, verifiedOptionID = explicitRoute, explicitKey, explicitOption
        end

        if inScenario then
            stageMatches = ns.AutoRouting:GetScenarioStageMatches()
            if not verifiedOptionID then
                route, rKey = ns:FindExistingRouteForNPC(npcID, npcName)
                -- A route matched to the actual dialog NPC is authoritative.
                -- Scenario text is only a team fallback, not a veto on this match.
            end
        elseif not verifiedOptionID then
            route, rKey = ns.AutoRouting:FindRouteForTarget(npcID, npcName)
        end
        local matchedTalkTarget = route ~= nil
        GossipTrace("直接绑定 键/是否匹配/场景", rKey, matchedTalkTarget, inScenario)

        local chosenOptionID = verifiedOptionID
        if not chosenOptionID and options and #options > 0 then
            local kwList = ns.GossipBattleKeywords or { "对战", "挑战", "宠物", "battle", "challenge", "fight" }
            for _, opt in ipairs(options) do
                if opt.name and not ns:IsSecretValue(opt.name) and opt.gossipOptionID and not ns:IsSecretValue(opt.gossipOptionID) then
                    local lowerOpt = strlower(opt.name)
                    for _, kw in ipairs(kwList) do
                        if string.find(lowerOpt, strlower(kw), 1, true) then
                            chosenOptionID = opt.gossipOptionID
                            break
                        end
                    end
                end
                if chosenOptionID then break end
            end
        end

        ns.db.gossipRouteMap = ns.db.gossipRouteMap or {}

        if not route and inScenario then
            local match = ResolveScenarioMatch(stageMatches)
            if match then route, rKey = match.route, match.key end
        elseif not route and chosenOptionID and ns.db.gossipRouteMap[chosenOptionID] then
            rKey = ns.db.gossipRouteMap[chosenOptionID]
            route = ns.db.routeMappings and ns.db.routeMappings[rKey]
        end

        if not matchedTalkTarget and (ns.db.settings.autoGossip or ns.db.settings.autoLoadTarget)
            and ns.AutoRouting.GetLearnableGossipOption and ns.ShowGossipLearningModal then
            local learnOption = ns.AutoRouting:GetLearnableGossipOption(options)
            if learnOption then
                if ns:ShowGossipLearningModal(learnOption, gossipGeneration) then return end
            end
        end

        if not route or not route.teams or #route.teams == 0 then
            GossipTrace("退出：没有绑定队伍", rKey, chosenOptionID)
            return
        end
        GossipTrace("最终绑定 键/第一队伍", rKey, route.teams[1])

        -- The routing panel's configured option index is authoritative. The
        -- known-option/keyword scan above is only for identifying a route; it
        -- must not silently override a user's choice with the first match.
        local configuredIndex = math.max(1, math.floor(tonumber(route.gossipIndex) or 1))
        local configuredOption = options and options[configuredIndex]
        if configuredOption and configuredOption.gossipOptionID
            and not ns:IsSecretValue(configuredOption.gossipOptionID) then
            chosenOptionID = configuredOption.gossipOptionID
            GossipTrace("使用目标设置的对话序号/选项ID/文字", configuredIndex, chosenOptionID, configuredOption.name)
        else
            chosenOptionID = nil
            GossipTrace("目标设置的对话序号无效，不自动点击", configuredIndex, options and #options or 0)
        end

        GossipTrace("待选择的选项ID", chosenOptionID)
        if chosenOptionID and rKey and matchedTalkTarget then
            ns.AutoRouting:RememberGossipRoute(rKey, chosenOptionID, false)
            ns.db.gossipRouteMap[chosenOptionID] = rKey
        end

        ns.db.lastActiveRouteKey = rKey
        local prevTeam = ns.db.teams[ns.db.selectedTeamIdx]
        local wasReadyBefore = prevTeam and ns.AutoRouting:IsCurrentLoadoutHealthyAndReady(prevTeam) and (prevTeam.name == route.teams[1])

        if ns.db.settings.autoLoadTarget then
            ns.AutoRouting:LoadTeamWithFallbackChain(route.teams[1], route)
        end

        if ns.db.settings.autoGossip and chosenOptionID and (matchedTalkTarget or not inScenario) then
            local newTeam = ns.db.teams[ns.db.selectedTeamIdx]
            local needEquipDelay = ns.db.settings.autoLoadTarget and not (wasReadyBefore and newTeam == prevTeam)
            if needEquipDelay then
                GossipTrace("等待换队 0.45 秒")
                local generation = gossipGeneration
                C_Timer.After(0.45, function()
                    if generation == gossipGeneration and ns.db.settings.autoGossip and not InCombatLockdown()
                        and not (C_PetBattles and C_PetBattles.IsInBattle()) then
                        SelectGossipWithTrace(chosenOptionID)
                    else
                        GossipTrace("退出：延迟期间对话变化、开关关闭或已进入战斗")
                    end
                end)
            else
                SelectGossipWithTrace(chosenOptionID)
            end
        else
            GossipTrace("退出：自动选择条件不成立 开关/选项ID/直接匹配/场景", ns.db.settings.autoGossip, chosenOptionID, matchedTalkTarget, inScenario)
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not ns:IsSecretValue(arg1) and arg1 == "player" then
            local s2 = not ns:IsSecretValue(arg2) and arg2 or nil
            local s3 = not ns:IsSecretValue(arg3) and arg3 or nil
            if s3 == REVIVE_PETS_SPELL_ID or s2 == REVIVE_PETS_SPELL_ID then
                ns._reviveHoldRouteKey = nil
                ns._reviveResetPending = true
                ThrottledEnsurePrepared(0.45)
                C_Timer.After(0.35, function()
                    if ns.RefreshAllUI then ns:RefreshAllUI(true) end
                end)
            end
        end

    elseif event == "SPELL_UPDATE_COOLDOWN" then
        local inPetBattle = C_PetBattles and C_PetBattles.IsInBattle()
        if (InCombatLockdown() or IsInRestrictedCombatInstance()) and not inPetBattle then return end

        local now = GetTime()
        if now - lastCooldownPollTime < 0.25 then return end
        lastCooldownPollTime = now

        if not inPetBattle then
            local nowReady = ns:IsRevivePetCooldownReady()
            if not nowReady then ScheduleReviveReadyCheck() end
            if nowReady and not wasReviveReady then
                wasReviveReady = true
                ns._reviveResetPending = true
                if ns.ShowUIFeedback then ns:ShowUIFeedback("|cffff4040" .. ns:T("复活战斗宠物已就绪") .. "|r") end
                ThrottledEnsurePrepared(0.3)
            else
                wasReviveReady = nowReady
            end
        elseif ns.UpdateBattleHUD and ns.BattleHUD and ns.BattleHUD:IsShown() and ns.db and ns.db.settings and ns.db.settings.hudMonitorExpanded then
            ns:UpdateBattleHUD(true)
        end

    elseif event == "PLAYER_XP_UPDATE" then
        if ns.UpdateBattleHUD and ns.BattleHUD and ns.BattleHUD:IsShown() then
            ns:UpdateBattleHUD()
        end

    elseif event == "PET_BATTLE_OPENING_START" then
        ns._reviveHoldRouteKey = nil
        if ns.ScriptEngine.resumedBattle then return end
        if ns.DungeonStageBar then ns.DungeonStageBar:Hide() end
        SnapshotBattleStartStats()
        local se = ns.ScriptEngine
        se.battleStateKnown = true
        wipe(se.logs)
        se.currentRound = 1
        se.lastCompletedRound = 0
        se.ignoredRoundEvents = 0
        se.lastRoundEvent = nil
        se.lastLogKey = ""
        se._lastExecTime = 0
        inRoundPlayback = false

        local ally = Enum.BattlePetOwner.Ally
        local enemy = Enum.BattlePetOwner.Enemy
        battleOwners[1] = ally
        battleOwners[2] = enemy
        local aSlot = C_PetBattles.GetActivePet(ally) or 1
        local eSlot = C_PetBattles.GetActivePet(enemy) or 1
        se.sideRound[ally] = 1
        se.sideRound[enemy] = 1
        se.lastActiveSlot[ally] = aSlot
        se.lastActiveSlot[enemy] = eSlot
        se.swappedInRound[ally] = false
        se.swappedInRound[enemy] = false
        wipe(se.playedSlots[ally])
        wipe(se.playedSlots[enemy])
        se.playedSlots[ally][aSlot] = true
        se.playedSlots[enemy][eSlot] = true

        se:AddLog(string.format(ns:T("就绪 - 按 |cff3b82f6[%s]|r 执行"), ns.FormatHotKeyDisplay and ns:FormatHotKeyDisplay() or "SPACE"))
        if ns.ShowBattleHUD then ns:ShowBattleHUD(true) end
        ns:SetupBattleEnemyBreedHUD()
        C_Timer.After(0.2, function()
            ns:UpdateBattleEnemyBreedDisplay()
            if ns.UpdateBattleHUD then ns:UpdateBattleHUD() end
        end)

    elseif event == "PET_BATTLE_ACTION_SELECTED" then
        inRoundPlayback = true
        ns.ScriptEngine._lastExecTime = 0
        ns:UpdateBattleEnemyBreedDisplay()
        if ns.UpdateBattleHUD then ns:UpdateBattleHUD() end

    elseif event == "PET_BATTLE_PET_CHANGED" then
        local se = ns.ScriptEngine
        se._lastExecTime = 0
        battleOwners[1] = Enum.BattlePetOwner.Ally
        battleOwners[2] = Enum.BattlePetOwner.Enemy
        for i = 1, 2 do
            local owner = battleOwners[i]
            local curSlot = C_PetBattles.GetActivePet(owner)
            if curSlot then
                se.playedSlots[owner][curSlot] = true
                if curSlot ~= se.lastActiveSlot[owner] then
                    se.lastActiveSlot[owner] = curSlot
                    se.sideRound[owner] = 1
                    if inRoundPlayback then
                        se.swappedInRound[owner] = true
                    end
                end
            end
        end
        ns:UpdateBattleEnemyBreedDisplay()
        if ns.UpdateBattleHUD then ns:UpdateBattleHUD() end

    elseif event == "PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE" then
        local se = ns.ScriptEngine
        -- Opening playback (round 0) is not a completed combat turn.
        -- Process each positive round once; invalid or duplicate events must
        -- not advance either the global counter or the active pet's counter.
        local finishedRound = not ns:IsSecretValue(arg1) and tonumber(arg1) or nil
        se.lastRoundEvent = finishedRound
        if not finishedRound or finishedRound < 1 or finishedRound % 1 ~= 0
            or finishedRound <= (se.lastCompletedRound or 0) then
            se.ignoredRoundEvents = (se.ignoredRoundEvents or 0) + 1
            return
        end
        se.lastCompletedRound = finishedRound
        se.currentRound = finishedRound + 1
        se._lastExecTime = 0
        inRoundPlayback = false

        battleOwners[1] = Enum.BattlePetOwner.Ally
        battleOwners[2] = Enum.BattlePetOwner.Enemy
        for i = 1, 2 do
            local owner = battleOwners[i]
            local curSlot = C_PetBattles.GetActivePet(owner)
            if curSlot then
                se.playedSlots[owner][curSlot] = true
            end
            if se.swappedInRound[owner] then
                se.sideRound[owner] = 1
                se.swappedInRound[owner] = false
            else
                se.sideRound[owner] = (se.sideRound[owner] or 1) + 1
            end
        end

        ns:UpdateBattleEnemyBreedDisplay()
        if ns.UpdateBattleHUD then ns:UpdateBattleHUD() end

    elseif event == "PET_BATTLE_CLOSE" then
        inRoundPlayback = false
        ns.ScriptEngine.battleStateKnown = false
        ns.ScriptEngine.resumedBattle = false
        if ns.ShowBattleHUD then ns:ShowBattleHUD(false) end
        battleEndReportSerial = battleEndReportSerial + 1
        local reportSerial = battleEndReportSerial
        local previousTeam = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
        local previousPetIDs = CaptureBattleEndLoadout()
        ns._battleEndReportPending = true
        C_Timer.After(0.6, function()
            if reportSerial ~= battleEndReportSerial then return end
            if ns.InvalidatePetAndTeamCache then
                ns:InvalidatePetAndTeamCache()
            end
            RecordBattleEndStats()
            ns.Leveling:RefreshSelectedSlot()
            ns.AutoRouting:EnsurePreparedRouteAndTeam()
            if ns.RefreshAllUI then ns:RefreshAllUI() end
            C_Timer.After(0.55, function()
                if reportSerial ~= battleEndReportSerial then return end
                ns._battleEndReportPending = nil
                ShowBattleEndTeamReport(previousTeam, previousPetIDs)
                if ns.RefreshAllUI then ns:RefreshAllUI() end
            end)
        end)

    elseif event == "PET_JOURNAL_LIST_UPDATE" then
        local numTotal, numCol = C_PetJournal.GetNumPets()
        local colUnchanged = (numCol ~= nil and numCol == lastKnownCollectedCount)
            and (numTotal ~= nil and numTotal == lastKnownTotalCount)
        lastKnownCollectedCount = numCol or lastKnownCollectedCount
        lastKnownTotalCount = numTotal or lastKnownTotalCount

        local isSelfEquipping = (ns._equippingUntil ~= nil and GetTime() < ns._equippingUntil and colUnchanged)
        local uiVisible = (ns.MainFrame and ns.MainFrame:IsVisible()) or (ns.RoutingModal and ns.RoutingModal:IsVisible())
        if not isSelfEquipping then
            local now = GetTime()
            if not colUnchanged or (now - lastJournalInvalidateTime > 0.25) then
                lastJournalInvalidateTime = now
                if ns.InvalidatePetAndTeamCache then
                    ns:InvalidatePetAndTeamCache()
                end
            end
            if not InCombatLockdown() and not IsInRestrictedCombatInstance() and not (C_PetBattles and C_PetBattles.IsInBattle()) then
                local team = ns.db and ns.db.teams[ns.db.selectedTeamIdx]
                if team and team.hasLevelingSlot and ns.Leveling:GetManualQueueCount() == 0 then
                    ns.Leveling:RestoreSlotFallback(team, team.levelingSlot or ns.db.settings.levelingSlot or 2)
                end
                ThrottledEnsurePrepared(0.4)
            end
        end

        if uiVisible then
            journalRefreshNeedsFull = journalRefreshNeedsFull or not isSelfEquipping
            if not journalRefreshPending then
                journalRefreshPending = true
                C_Timer.After(0.15, RefreshAfterJournalUpdate)
            end
        end
    end
end)

function ns.AutoRouting:ProcessCurrentGossip()
    if GossipFrame and GossipFrame:IsShown() then
        engineFrame:GetScript("OnEvent")(engineFrame, "GOSSIP_SHOW")
    end
end
