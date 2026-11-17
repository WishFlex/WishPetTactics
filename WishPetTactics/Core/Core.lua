local ADDON_NAME, ns = ...

function ns:GetActiveUIParent()
    if C_PetBattles and C_PetBattles.IsInBattle() and PetBattleFrame then
        return PetBattleFrame
    end
    return UIParent
end

function ns:GetDefaultBattleScript()
    local comment = self.locale == "zhCN" and "默认顺序施法脚本"
        or self.locale == "zhTW" and "預設順序施法腳本" or "Default ability order"
    return "-- " .. comment .. "\nuse(1)\nuse(2)\nuse(3)\nchange(next)"
end

local DEFAULT_DB = {
    settings = {
        autoLoadTarget     = true,
        autoGossip         = true,
        battleEndTeamReport = true,
        autoSwapHealthyDup = true,
        levelingRule       = "MANUAL",
        levelingSlot       = 2,
        overrideJournal    = true,
        minimapAngle       = 205,
        uiScale            = 1.00,
        uiAutoScale        = true,
        bgAlpha            = 0.78,
        battleHotKey       = "SPACE",
        battleHudEnemySkillsVisible = false,
        battleHudSidebarOpen = true,
        petCardHover3D     = true,
        hudViewMode        = 1, -- 1:脚本日志 | 2:角色升级监控 | 3:宠物升级监控
        lastPetDrawerTab   = "PETS",
        mainUIStyle        = "FULL", -- FULL or MINIMAL; presentation only
        actionSidebarCollapsed = false,
        windowPos          = nil,
    },
    queueFilterState = {
        keyword    = "",
        levelRange = "ALL",
        rarity     = -1,
        petType    = -1,
        skipDead   = true,
        onlyFav      = false,
    },
    petFilterState = {
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
    },
    defaultSlotThresholds = { [1] = 0, [2] = 40, [3] = 0 },
    slotSpeciesMemory = { [1] = {}, [2] = {}, [3] = {} },
    petNotes = {},
    petMarkers = {},
    favoriteFilters = {},
    teamGroups = {
        "最爱队伍",
        "未分组队伍",
        "暗影界",
        "巨龙时代",
        "地心之战",
        "宠物地下城",
    },
    teams = {
        {
            name = ns:T("机械明火速刷队"),
            group = "最爱队伍",
            npcID = 0,
            npcName = "",
            gossipIndex = 1,
            pets = { nil, nil, nil },
            speciesLoadout = { 0, 0, 0 },
            abilities = { {0,0,0}, {0,0,0}, {0,0,0} },
            slotThresholds = { [1] = 0, [2] = 40, [3] = 0 },
            hasLevelingSlot = false,
            levelingSlot = 2,
            script = "-- " .. ns:T("机械明火自动化脚本") .. "\nif self(#1).active then\n    use(1)\nelseif self(#2).active then\n    if self(#2).hp <= 40 then\n        change(3)\n    else\n        use(2)\n    end\nelseif self(#3).active then\n    use(1)\nend",
        },
        {
            name = ns:T("野外日常带练队 (2号练级)"),
            group = "未分组队伍",
            npcID = 0,
            npcName = "",
            gossipIndex = 1,
            pets = { nil, "LEVELING", nil },
            speciesLoadout = { 0, 0, 0 },
            abilities = { {0,0,0}, {0,0,0}, {0,0,0} },
            slotThresholds = { [1] = 0, [2] = 40, [3] = 0 },
            hasLevelingSlot = true,
            levelingSlot = 2,
            script = "-- " .. ns:T("2号位练级登场混一回合自动换主力") .. "\nif self(#2).active then\n    change(3)\nelseif self(#1).active then\n    use(1)\nelse\n    use(1)\nend",
        },
    },
    routeMappings = {},
    manualQueueOrder = {},
    selectedTeamIdx = 1,
    activeTargetSlot = nil,
    lastActiveRouteKey = nil,
}

-- 用户集合型存档键：仅在首次初始化为 nil 时拷贝默认值，绝不向已有数组/字典递归塞回已删除项
local NON_RECURSIVE_DB_KEYS = {
    teams            = true,
    teamGroups       = true,
    manualQueueOrder = true,
    favoriteFilters  = true,
    routeMappings    = true,
    petNotes         = true,
    petMarkers       = true,
}

ns.queueFilterState = CopyTable(DEFAULT_DB.queueFilterState)
ns.petFilterState   = CopyTable(DEFAULT_DB.petFilterState)

ns.staging = {
    isDirty = false,
    hasLevelingSlot = false,
    levelingSlot = 2,
}

function ns:PrintError(msg)
    if msg and msg ~= "" then
        local prefix = (self.T and self:T("[Wish Pet Tactics 错误]")) or "[Wish Pet Tactics 错误]"
        local body = (self.T and self:T(tostring(msg))) or tostring(msg)
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040" .. prefix .. "|r " .. body)
    end
end

local function MergeDefaults(src, dst)
    if type(src) ~= "table" then return {} end
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            if dst[k] == nil then
                dst[k] = CopyTable(v)
            elseif not NON_RECURSIVE_DB_KEYS[k] and type(dst[k]) == "table" then
                dst[k] = MergeDefaults(v, dst[k])
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function ns:EnsureTeamGroup(groupName)
    if not groupName or strtrim(groupName) == "" then return "未分组队伍" end
    groupName = strtrim(groupName)
    ns.db.teamGroups = ns.db.teamGroups or { "最爱队伍", "未分组队伍", "暗影界", "宠物地下城" }
    for _, g in ipairs(ns.db.teamGroups) do
        if g == groupName then return groupName end
    end
    table.insert(ns.db.teamGroups, groupName)
    return groupName
end

-- ==================== 0. 极轻量图鉴缓存（整数位打包 + Breed 缓存 + 表池复用） ====================
ns._petCache = nil
ns._petCacheDirty = true
ns._petJournalRevision = 0
ns._petListResultRevision = 0

function ns:InvalidatePetListResults()
    self._petListResultRevision = (self._petListResultRevision or 0) + 1
end
ns._speciesMetaCache = {}
local speciesListPool = {}
local journalEntryPool = {}

ns._teamTreeRevision = 0
function ns:BumpTeamTreeRevision()
    self._teamTreeRevision = (self._teamTreeRevision or 0) + 1
    if ns.TeamMatrixModal then
        ns.TeamMatrixModal._treeDirty = true
    end
end

function ns:InvalidateTeamAudit(team)
    if team then
        team._auditRev = nil
        team._auditResult = nil
    end
    self:BumpTeamTreeRevision()
end

function ns:InvalidatePetAndTeamCache()
    self._petCacheDirty = true
    self._petJournalRevision = self._petJournalRevision + 1
    self:BumpTeamTreeRevision()
end

function ns:UnpackPetInfo(packed)
    if not packed then return nil, nil end
    local lv = packed % 64
    return (packed - lv) / 64, lv
end

function ns:GetPetJournalCache()
    local cache = self._petCache
    if not self._petCacheDirty and cache then
        return cache
    end

    if not cache then
        cache = {
            bySpecies      = {}, -- speciesID -> { petID1, petID2, ... }（池化复用数组）
            maxLvBySpecies = {}, -- speciesID -> 已收集同物种最高等级
            collected      = {}, -- speciesID -> boolean
            packedPet      = {}, -- petID -> (speciesID * 64 + level) 零表分配整数打包
            customNames    = {}, -- petID -> customName（仅改名宠物存入）
            breeds         = {}, -- petID -> breed 字符串缓存（避免每次筛选重复计算）
            entries        = {}, -- 池化复用的可对战宠物列表（供 SearchFilter 直接遍历，避免二次 C API 扫描）
            entryCount     = 0,
        }
        self._petCache = cache
    else
        for spID, list in pairs(cache.bySpecies) do
            wipe(list)
            speciesListPool[spID] = list
            cache.bySpecies[spID] = nil
        end
        wipe(cache.maxLvBySpecies)
        wipe(cache.collected)
        wipe(cache.packedPet)
        wipe(cache.customNames)
        wipe(cache.breeds)
    end

    local entries = cache.entries
    local entryCount = 0
    local numPets = C_PetJournal.GetNumPets() or 0
    for i = 1, numPets do
        local petID, speciesID, isCollected, customName, level, isFavorite, _, speciesName, icon, petType, _, sourceText, _, _, canBattle, isTradable = C_PetJournal.GetPetInfoByIndex(i)
        if speciesID and canBattle then
            entryCount = entryCount + 1
            local entry = journalEntryPool[entryCount]
            if not entry then
                entry = {}
                journalEntryPool[entryCount] = entry
            end
            entry.petID       = petID
            entry.speciesID   = speciesID
            entry.isCollected = isCollected and true or false
            entry.customName  = customName
            entry.level       = level or 1
            entry.isFavorite  = isFavorite and true or false
            entry.speciesName = speciesName
            entry.icon        = icon
            entry.petType     = petType or 1
            entry.sourceText  = sourceText or ""
            entry.isTradable  = isTradable and true or false
            entry._statsLoaded = false
            entries[entryCount] = entry

            if isCollected and petID then
                local lv = math.min(63, math.max(1, level or 1))
                cache.collected[speciesID] = true
                if lv > (cache.maxLvBySpecies[speciesID] or 0) then
                    cache.maxLvBySpecies[speciesID] = lv
                end

                local list = cache.bySpecies[speciesID]
                if not list then
                    list = speciesListPool[speciesID]
                    if not list then
                        list = {}
                        speciesListPool[speciesID] = list
                    end
                    cache.bySpecies[speciesID] = list
                end
                list[#list + 1] = petID

                cache.packedPet[petID] = speciesID * 64 + lv
                if customName and customName ~= "" then
                    cache.customNames[petID] = customName
                end
            end
        end
    end
    for k = entryCount + 1, #entries do
        entries[k] = nil
    end
    cache.entryCount = entryCount

    if numPets > 0 then
        self._petCacheDirty = false

        -- 每次登录图鉴就绪后执行一次原地瘦身：清理已满 25 级/已放生的队列项与失效对话映射
        if not self._svPrunedOnce and ns.db then
            self._svPrunedOnce = true
            local order = ns.db.manualQueueOrder
            if type(order) == "table" and #order > 0 then
                local seen = {}
                local writeIdx = 0
                for readIdx = 1, #order do
                    local pid = order[readIdx]
                    if type(pid) == "string" and not seen[pid] then
                        local spID, _, pLv = C_PetJournal.GetPetInfoByPetID(pid)
                        if spID and (pLv or 1) < 25 then
                            seen[pid] = true
                            writeIdx = writeIdx + 1
                            order[writeIdx] = pid
                        end
                    end
                end
                for k = writeIdx + 1, #order do
                    order[k] = nil
                end
            end
            if type(ns.db.gossipRouteMap) == "table" and type(ns.db.routeMappings) == "table" then
                for optID, rKey in pairs(ns.db.gossipRouteMap) do
                    if not ns.db.routeMappings[rKey] then
                        ns.db.gossipRouteMap[optID] = nil
                    end
                end
            end
        end
    end
    return cache
end

function ns:GetSpeciesMeta(speciesID)
    speciesID = tonumber(speciesID) or 0
    if speciesID <= 0 then return nil end
    local meta = self._speciesMetaCache[speciesID]
    if meta then return meta end

    local spName, spIcon, petType = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
    if spName then
        meta = {
            name    = spName,
            icon    = spIcon or "Interface\\Icons\\INV_Misc_QuestionMark",
            petType = petType or 1,
        }
        self._speciesMetaCache[speciesID] = meta
        return meta
    end
    return {
        name    = self:T("未知宠物") .. " #" .. speciesID,
        icon    = "Interface\\Icons\\INV_Misc_QuestionMark",
        petType = 1,
    }
end

function ns:IsSpeciesCollected(speciesID)
    speciesID = tonumber(speciesID) or 0
    if speciesID <= 0 then return true end
    local cache = self:GetPetJournalCache()
    local cachedOwned = cache.collected[speciesID]
    if cachedOwned ~= nil then
        return cachedOwned
    end
    local numCollected = C_PetJournal.GetNumCollectedInfo(speciesID)
    local owned = (numCollected and numCollected > 0) and true or false
    cache.collected[speciesID] = owned
    return owned
end

local EMPTY_READONLY_TABLE = {}
local CLEAN_AUDIT_RESULT = {
    hasMissing    = false,
    missingList   = EMPTY_READONLY_TABLE,
    hasUnderLv    = false,
    underLvList   = EMPTY_READONLY_TABLE,
    underLvBySlot = EMPTY_READONLY_TABLE,
}

-- 单次遍历 3 个槽位：正常队伍零表分配短路返回 CLEAN_AUDIT_RESULT，且按图鉴版本号缓存结果
function ns:AuditTeamPets(team)
    if not team then
        return CLEAN_AUDIT_RESULT
    end

    local cache = self:GetPetJournalCache()
    local lvSlot = team.levelingSlot or (ns.db and ns.db.settings and ns.db.settings.levelingSlot) or 2
    local effLv = team.hasLevelingSlot and lvSlot or 0
    local p1 = team.pets and team.pets[1] or ""
    local p2 = team.pets and team.pets[2] or ""
    local p3 = team.pets and team.pets[3] or ""
    local s1 = team.speciesLoadout and team.speciesLoadout[1] or 0
    local s2 = team.speciesLoadout and team.speciesLoadout[2] or 0
    local s3 = team.speciesLoadout and team.speciesLoadout[3] or 0
    if team._auditResult
        and team._auditRev == self._petJournalRevision
        and team._auditLv == effLv
        and team._auditP1 == p1 and team._auditP2 == p2 and team._auditP3 == p3
        and team._auditS1 == s1 and team._auditS2 == s2 and team._auditS3 == s3 then
        return team._auditResult
    end
    local missingList, underLvList, underLvBySlot = nil, nil, nil

    for s = 1, 3 do
        local isLv = (team.hasLevelingSlot and lvSlot == s) or (team.pets and team.pets[s] == "LEVELING")
        local isRandom = team.randomSlots and team.randomSlots[s] ~= nil

        if not isLv and not isRandom then
            local rawPetID = nil
            if team.pets and type(team.pets[s]) == "string" and team.pets[s] ~= "LEVELING" and not string.find(team.pets[s], "^RANDOM:") then
                rawPetID = team.pets[s]
            end
            local spID = (team.speciesLoadout and tonumber(team.speciesLoadout[s])) or 0

            local petSpID, petLv = nil, nil
            local packed = rawPetID and cache.packedPet[rawPetID] or nil
            if packed then
                petLv = packed % 64
                petSpID = (packed - petLv) / 64
            elseif rawPetID then
                local realSpID, customName, pLv = C_PetJournal.GetPetInfoByPetID(rawPetID)
                if realSpID then
                    petSpID = realSpID
                    petLv = math.min(63, math.max(1, pLv or 1))
                    cache.packedPet[rawPetID] = petSpID * 64 + petLv
                    if customName and customName ~= "" then
                        cache.customNames[rawPetID] = customName
                    end
                end
            end

            if spID == 0 and petSpID then
                spID = petSpID
            end

            if spID > 0 then
                if not self:IsSpeciesCollected(spID) then
                    local meta = self:GetSpeciesMeta(spID)
                    local _, _, _, _, sourceText, _, _, _, _, _, _, displayID = C_PetJournal.GetPetInfoBySpeciesID(spID)
                    if not missingList then missingList = {} end
                    missingList[#missingList + 1] = {
                        slot       = s,
                        speciesID  = spID,
                        name       = meta.name,
                        icon       = meta.icon,
                        petType    = meta.petType,
                        displayID  = displayID or 0,
                        sourceText = sourceText or "",
                    }
                else
                    local checkLv = nil
                    if petLv and (spID == 0 or petSpID == spID) then
                        checkLv = petLv
                    elseif cache.maxLvBySpecies[spID] ~= nil then
                        checkLv = cache.maxLvBySpecies[spID]
                    end

                    if checkLv and checkLv < 25 then
                        local checkName = (rawPetID and cache.customNames[rawPetID]) or nil
                        if not checkName then
                            local meta = self:GetSpeciesMeta(spID)
                            checkName = meta and meta.name
                        end
                        if not underLvList then
                            underLvList = {}
                            underLvBySlot = {}
                        end
                        underLvList[#underLvList + 1] = {
                            slot      = s,
                            speciesID = spID,
                            level     = checkLv,
                            name      = checkName or (self:T("未知宠物") .. " #" .. spID),
                        }
                        underLvBySlot[s] = checkLv
                    end
                end
            end
        end
    end

    local result
    if not missingList and not underLvList then
        result = CLEAN_AUDIT_RESULT
    else
        result = {
            hasMissing    = (missingList ~= nil),
            missingList   = missingList or EMPTY_READONLY_TABLE,
            hasUnderLv    = (underLvList ~= nil),
            underLvList   = underLvList or EMPTY_READONLY_TABLE,
            underLvBySlot = underLvBySlot or EMPTY_READONLY_TABLE,
        }
    end
    team._auditRev = self._petJournalRevision
    team._auditLv  = effLv
    team._auditP1, team._auditP2, team._auditP3 = p1, p2, p3
    team._auditS1, team._auditS2, team._auditS3 = s1, s2, s3
    team._auditResult = result
    return result
end

function ns:CheckTeamMissingPets(team)
    local audit = self:AuditTeamPets(team)
    return audit.hasMissing, audit.missingList
end

function ns:CheckTeamUnderleveledPets(team)
    local audit = self:AuditTeamPets(team)
    return audit.hasUnderLv, audit.underLvList, audit.underLvBySlot
end

function ns:CollectMissingPetsForTeams(teamsList)
    local report = {}
    local uniqueSpecies = {}
    local uniqueCount = 0

    for _, team in ipairs(teamsList or {}) do
        local hasMissing, mList = self:CheckTeamMissingPets(team)
        if hasMissing then
            table.insert(report, {
                teamName = team.name or self:T("未命名队伍"),
                group    = team.group or "未分组队伍",
                missing  = mList,
            })
            for _, m in ipairs(mList) do
                if not uniqueSpecies[m.speciesID] then
                    uniqueSpecies[m.speciesID] = m
                    uniqueCount = uniqueCount + 1
                end
            end
        end
    end

    return report, uniqueCount
end

-- ==================== O(1) 目标路由哈希索引与隔离管理核心工具 ====================
local baseTargetNameCache = {}
local baseTargetCacheCount = 0

function ns:ExtractBaseTargetName(rawName)
    if not rawName or rawName == "" then return "" end
    local cached = baseTargetNameCache[rawName]
    if cached ~= nil then return cached end

    local clean = strtrim(rawName)
    clean = string.gsub(clean, "%s*%(%d+%)$", "")
    clean = string.gsub(clean, "%s+#?%d+$", "")
    clean = strtrim(clean)

    if baseTargetCacheCount >= 800 then
        wipe(baseTargetNameCache)
        baseTargetCacheCount = 0
    end
    baseTargetNameCache[rawName] = clean
    baseTargetCacheCount = baseTargetCacheCount + 1
    return clean
end

ns._routesDirty         = true
ns._routeIndexDirty     = true
ns._lastSyncedTeamCount = -1
ns._lastIndexTeamCount  = -1
ns._routeByID           = {}
ns._routeByNameLower    = {}
ns._routeByTeamName     = {}

local routeEntryPool = {}
local routeEntryLen  = 0

function ns:MarkRoutesDirty()
    self._routeRevision = (self._routeRevision or 0) + 1
    self._routesDirty     = true
    self._routeIndexDirty = true
    self:BumpTeamTreeRevision()
end

function ns:RegisterRouteInIndex(rKey, route, appendedTeamName)
    if not rKey or not route then return end
    routeEntryLen = routeEntryLen + 1
    local entry = routeEntryPool[routeEntryLen]
    if not entry then
        entry = {}
        routeEntryPool[routeEntryLen] = entry
    end
    entry.key   = rKey
    entry.route = route

    local rID = tonumber(route.npcID) or tonumber(rKey) or 0
    if rID > 0 and not self._routeByID[rID] then
        self._routeByID[rID] = entry
    end

    local kLower = strlower(tostring(rKey))
    if kLower ~= "" and not self._routeByNameLower[kLower] then
        self._routeByNameLower[kLower] = entry
    end

    if route.npcName and route.npcName ~= "" then
        local nLower = strlower(strtrim(route.npcName))
        local bLower = strlower(self:ExtractBaseTargetName(route.npcName))
        if nLower ~= "" and not self._routeByNameLower[nLower] then
            self._routeByNameLower[nLower] = entry
        end
        if bLower ~= "" and not self._routeByNameLower[bLower] then
            self._routeByNameLower[bLower] = entry
        end
    end

    if appendedTeamName then
        if not self._routeByTeamName[appendedTeamName] then
            self._routeByTeamName[appendedTeamName] = entry
        end
    elseif route.teams then
        for i = 1, #route.teams do
            local tn = route.teams[i]
            if tn and tn ~= "" and not self._routeByTeamName[tn] then
                self._routeByTeamName[tn] = entry
            end
        end
    elseif route.teamName and route.teamName ~= "" and not self._routeByTeamName[route.teamName] then
        self._routeByTeamName[route.teamName] = entry
    end
end

function ns:EnsureRouteLookupIndex()
    if not ns.db or not ns.db.routeMappings then return end
    local curTeamCount = ns.db.teams and #ns.db.teams or 0
    if not self._routeIndexDirty and self._lastIndexTeamCount == curTeamCount then
        return
    end
    wipe(self._routeByID)
    wipe(self._routeByNameLower)
    wipe(self._routeByTeamName)
    local oldEntryLen = routeEntryLen
    routeEntryLen = 0
    for rKey, route in pairs(ns.db.routeMappings) do
        self:RegisterRouteInIndex(rKey, route)
    end
    -- Keep reusable entry tables, release deleted routes and their team data.
    for i = routeEntryLen + 1, oldEntryLen do
        routeEntryPool[i].key, routeEntryPool[i].route = nil, nil
    end
    self._routeIndexDirty    = false
    self._lastIndexTeamCount = curTeamCount
end

function ns:FindExistingRouteForNPC(npcID, npcName)
    if not ns.db or not ns.db.routeMappings then return nil, nil end
    npcID = tonumber(npcID) or 0
    npcName = npcName and strtrim(npcName) or ""
    if npcID <= 0 and npcName == "" then return nil, nil end

    local mappings = ns.db.routeMappings
    if npcID > 0 then
        local idKey = tostring(npcID)
        local direct = mappings[idKey]
        if direct then
            return direct, idKey
        end
    end
    if npcName ~= "" then
        local direct = mappings[npcName]
        if direct then
            local directID = tonumber(direct.npcID) or 0
            if npcID == 0 or directID == 0 or directID == npcID then
                return direct, npcName
            end
        end
    end

    self:EnsureRouteLookupIndex()

    if npcID > 0 then
        local hit = self._routeByID[npcID]
        if hit and mappings[hit.key] == hit.route then
            return hit.route, hit.key
        end
    end

    if npcName ~= "" then
        local lowerTarget = strlower(npcName)
        local hit = self._routeByNameLower[lowerTarget]
        if not hit then
            local baseTarget = strlower(self:ExtractBaseTargetName(npcName))
            if baseTarget ~= "" and baseTarget ~= lowerTarget then
                hit = self._routeByNameLower[baseTarget]
            end
        end
        if hit and mappings[hit.key] == hit.route then
            local hitID = tonumber(hit.route.npcID) or tonumber(hit.key) or 0
            if npcID == 0 or hitID == 0 or hitID == npcID then
                return hit.route, hit.key
            end
        end
    end

    return nil, nil
end

-- Import lookups are owned by one synchronous parse/commit, never SavedVariables.
-- Buckets hold records so a renamed/rebound team's stale entries can be ignored.
local function AddImportBucket(map, key, record)
    if key == nil then return end
    local bucket = map[key]
    if not bucket then bucket = {}; map[key] = bucket end
    local last = bucket[#bucket]
    if last and last.index > record.index then bucket.unordered = true end
    bucket[#bucket + 1] = record
end

local function ImportLoadoutKey(team)
    local parts = {}
    local levelingSlot = team.levelingSlot or 2
    for slot = 1, 3 do
        local leveling = team.hasLevelingSlot and levelingSlot == slot
        local random = team.randomSlots and team.randomSlots[slot] ~= nil
        if leveling or random then
            -- Match IsSamePetLoadout: random families are interchangeable,
            -- but the presence of a random slot and a leveling slot both matter.
            parts[slot] = leveling and (random and "LR" or "L") or "R"
        else
            local species = (team.speciesLoadout and team.speciesLoadout[slot]) or 0
            local petID = team.pets and team.pets[slot]
            if species == 0 and petID and petID ~= "LEVELING" then
                species = C_PetJournal.GetPetInfoByPetID(petID) or 0
            end
            parts[slot] = type(species) == "number" and string.format("%.17g", species) or "S" .. tostring(species)
        end
    end
    return table.concat(parts, ":")
end

local function IndexImportTeam(lookup, idx)
    local old = lookup.records[idx]
    if old and old.nameKey then
        local remaining = (lookup.usedNames[old.nameKey] or 1) - 1
        lookup.usedNames[old.nameKey] = remaining > 0 and remaining or nil
    end
    local team = lookup.teams[idx]
    if not team then lookup.records[idx] = nil; return end
    local nameKey = team.name and strlower(strtrim(team.name)) or nil
    local id = tonumber(team.npcID) or 0
    local npcLower = strlower(strtrim(team.npcName or ""))
    local npcBase = strlower(ns:ExtractBaseTargetName(team.npcName or ""))
    local nameBase = strlower(ns:ExtractBaseTargetName(team.name or ""))
    local record = { index = idx, team = team, nameKey = nameKey, id = id,
        npcLower = npcLower, npcBase = npcBase, nameBase = nameBase }
    lookup.records[idx] = record
    if nameKey then lookup.usedNames[nameKey] = (lookup.usedNames[nameKey] or 0) + 1 end
    if lookup.byLoadout then
        local key = ImportLoadoutKey(team)
        local index = lookup.byLoadout[key]
        if not index then
            index = { byName = {}, byID = {}, byBase = {}, byBaseNoID = {} }
            lookup.byLoadout[key] = index
        end
        local base = strlower(ns:ExtractBaseTargetName(team.npcName ~= "" and team.npcName or team.name or ""))
        AddImportBucket(index.byName, nameKey, record)
        if id > 0 then AddImportBucket(index.byID, id, record) end
        if base ~= "" then
            AddImportBucket(index.byBase, base, record)
            if id <= 0 then AddImportBucket(index.byBaseNoID, base, record) end
        end
    end
    AddImportBucket(lookup.byExactName, team.name, record)
    if id > 0 then AddImportBucket(lookup.byID, id, record) end
    AddImportBucket(lookup.byTargetAlias, npcLower, record)
    if npcBase ~= npcLower then AddImportBucket(lookup.byTargetAlias, npcBase, record) end
    if nameBase ~= npcLower and nameBase ~= npcBase then AddImportBucket(lookup.byTargetAlias, nameBase, record) end
end

local function CreateImportTeamLookup(teams, targetOnly)
    local lookup = { teams = teams or {}, records = {}, usedNames = {},
        byLoadout = not targetOnly and {} or nil,
        byExactName = {}, byID = {}, byTargetAlias = {} }
    for idx in ipairs(lookup.teams) do IndexImportTeam(lookup, idx) end
    return lookup
end

local function MatchImportBucket(self, lookup, bucket, newTeam, targetName, bestIdx, bestTeam)
    for _, record in ipairs(bucket or EMPTY_READONLY_TABLE) do
        local idx, team = record.index, record.team
        if bestIdx and not bucket.unordered and idx >= bestIdx then break end
        if lookup.records[idx] == record and (not bestIdx or idx < bestIdx) then
            local sameName = team.name and strlower(strtrim(team.name)) == targetName
            if (sameName or self:IsSameTargetRoute(team, newTeam)) and self:IsSamePetLoadout(team, newTeam) then
                bestIdx, bestTeam = idx, team
            end
        end
    end
    return bestIdx, bestTeam
end

local function TargetImportBucket(lookup, bucket, npcID, lowerBase, best)
    for _, record in ipairs(bucket or EMPTY_READONLY_TABLE) do
        if best and not bucket.unordered and record.index >= best.index then break end
        if lookup.records[record.index] == record and (not best or record.index < best.index) then
            local id = record.id
            local idMatch = npcID > 0 and id == npcID
            local aliasMatch = lowerBase ~= "" and (npcID == 0 or id == 0 or id == npcID)
                and ((record.npcLower ~= "" and (record.npcLower == lowerBase or record.npcBase == lowerBase))
                    or (record.nameBase ~= "" and record.nameBase == lowerBase))
            if idMatch or aliasMatch then best = record end
        end
    end
    return best
end

local function FindIndexedImportTarget(lookup, npcID, lowerBase)
    local best = TargetImportBucket(lookup, lookup.byID[npcID], npcID, lowerBase)
    best = TargetImportBucket(lookup, lookup.byTargetAlias[lowerBase], npcID, lowerBase, best)
    if not best then return nil, nil, nil end
    local team = best.team
    local label = (team.npcName and team.npcName ~= "") and team.npcName or ns:ExtractBaseTargetName(team.name)
    return (best.id > 0 and best.id or npcID), label, team.group
end

function ns:FindExistingTargetInfoForImport(npcID, teamName, candidateList, teamLookup, candidateLookup)
    npcID = tonumber(npcID) or 0
    local baseName = self:ExtractBaseTargetName(teamName)
    local lowerBase = strlower(baseName)

    local function SearchInTeamList(list, lookup)
        if not list then return nil, nil, nil end
        if lookup and lookup.teams == list then return FindIndexedImportTarget(lookup, npcID, lowerBase) end
        for _, t in ipairs(list) do
            local tID = tonumber(t.npcID) or 0
            if npcID > 0 and tID == npcID then
                local lbl = (t.npcName and t.npcName ~= "") and t.npcName or self:ExtractBaseTargetName(t.name)
                return tID, lbl, t.group
            end
            if lowerBase ~= "" and (npcID == 0 or tID == 0 or tID == npcID) then
                local tNpcLower = strlower(strtrim(t.npcName or ""))
                local tNpcBase  = strlower(self:ExtractBaseTargetName(t.npcName or ""))
                local tNameBase = strlower(self:ExtractBaseTargetName(t.name or ""))
                if (tNpcLower ~= "" and (tNpcLower == lowerBase or tNpcBase == lowerBase)) or (tNameBase ~= "" and tNameBase == lowerBase) then
                    local lbl = (t.npcName and t.npcName ~= "") and t.npcName or self:ExtractBaseTargetName(t.name)
                    return (tID > 0 and tID or npcID), lbl, t.group
                end
            end
        end
        return nil, nil, nil
    end

    local fID, fName, fGroup = SearchInTeamList(ns.db and ns.db.teams, teamLookup)
    if fID or fName or fGroup then
        return fID or npcID, (fName and fName ~= "" and fName or baseName), fGroup
    end

    if candidateList then
        local cID, cName, cGroup = SearchInTeamList(candidateList, candidateLookup)
        if cID or cName or cGroup then
            return cID or npcID, (cName and cName ~= "" and cName or baseName), cGroup
        end
    end

    local matchedRoute = self:FindExistingRouteForNPC(npcID, baseName)
    if matchedRoute then
        local routeGroup = nil
        if matchedRoute.teams and #matchedRoute.teams > 0 and ns.db and ns.db.teams then
            for _, tn in ipairs(matchedRoute.teams) do
                if teamLookup then
                    local best
                    for _, record in ipairs(teamLookup.byExactName[tn] or EMPTY_READONLY_TABLE) do
                        local t = record.team
                        if teamLookup.records[record.index] == record and t.name == tn and t.group and t.group ~= ""
                            and (not best or record.index < best.index) then best = record end
                    end
                    routeGroup = best and best.team.group
                else
                    for _, t in ipairs(ns.db.teams) do
                        if t.name == tn and t.group and t.group ~= "" then
                            routeGroup = t.group
                            break
                        end
                    end
                end
                if routeGroup then break end
            end
        end
        local rNpcName = (matchedRoute.npcName and matchedRoute.npcName ~= "") and matchedRoute.npcName or baseName
        return (tonumber(matchedRoute.npcID) or npcID), rNpcName, routeGroup
    end

    return npcID, (npcID > 0 and baseName or ""), nil
end

function ns:FindRouteContainingTeam(teamName)
    if not ns.db or not ns.db.routeMappings or not teamName or teamName == "" then
        return nil, nil
    end

    self:EnsureRouteLookupIndex()
    local hit = self._routeByTeamName[teamName]
    if hit and ns.db.routeMappings[hit.key] == hit.route then
        local r = hit.route
        if r.teams then
            for i = 1, #r.teams do
                if r.teams[i] == teamName then
                    return r, hit.key
                end
            end
        elseif r.teamName == teamName then
            return r, hit.key
        end
    end

    for k, route in pairs(ns.db.routeMappings) do
        if route.teams then
            for _, tn in ipairs(route.teams) do
                if tn == teamName then
                    self._routeByTeamName[teamName] = { route = route, key = k }
                    return route, k
                end
            end
        elseif route.teamName == teamName then
            self._routeByTeamName[teamName] = { route = route, key = k }
            return route, k
        end
    end
    return nil, nil
end

function ns:RemoveTeamFromTarget(teamName, routeKey)
    if not ns.db or not ns.db.routeMappings or not teamName then return false end
    local route = routeKey and ns.db.routeMappings[routeKey]
    if route and route.teams then
        for i = #route.teams, 1, -1 do
            if route.teams[i] == teamName then
                table.remove(route.teams, i)
            end
        end
        route.teamName = route.teams[1] or ""
    end

    local remainRoute = nil
    for _, r in pairs(ns.db.routeMappings) do
        if r.teams then
            for _, tn in ipairs(r.teams) do
                if tn == teamName then
                    remainRoute = r
                    break
                end
            end
        end
        if remainRoute then break end
    end

    if ns.db.teams then
        for _, t in ipairs(ns.db.teams) do
            if t.name == teamName then
                if remainRoute then
                    t.npcID = remainRoute.npcID or 0
                    t.npcName = remainRoute.npcName or ""
                else
                    t.npcID = 0
                    t.npcName = ""
                end
            end
        end
    end
    self:MarkRoutesDirty()
    return true
end

-- 仅创建或选中目标路由（绝不解绑或挪用其他目标现有的出战队伍）
function ns:EnsureTargetRoute(npcID, npcName)
    npcID = tonumber(npcID) or 0
    npcName = npcName and strtrim(npcName) or ""
    if npcID <= 0 and npcName == "" then
        return nil, nil
    end

    ns.db.routeMappings = ns.db.routeMappings or {}
    local route, rKey = self:FindExistingRouteForNPC(npcID, npcName)
    if not route then
        rKey = (npcID > 0) and tostring(npcID) or npcName
        local displayLabel = (npcName ~= "") and npcName or tostring(npcID)
        route = {
            npcID = npcID,
            npcName = displayLabel,
            teamName = "",
            teams = {},
            gossipIndex = 1,
            reviveLoadTeam1 = true,
        }
        ns.db.routeMappings[rKey] = route
    else
        if npcID > 0 and (not route.npcID or route.npcID == 0) then
            route.npcID = npcID
        end
        if npcName ~= "" and (not route.npcName or route.npcName == "" or route.npcName == tostring(route.npcID)) then
            route.npcName = npcName
        end
        if route.reviveLoadTeam1 == nil then
            route.reviveLoadTeam1 = true
        end
        route.teams = route.teams or {}
    end

    ns.db.lastActiveRouteKey = rKey
    self:MarkRoutesDirty()
    self:RegisterRouteInIndex(rKey, route)
    if ns.AutoRouting.TryLearnCurrentGossip then ns.AutoRouting:TryLearnCurrentGossip(rKey) end
    return route, rKey
end

function ns:EnsureTargetRouteFromInput(targetInput)
    targetInput = strtrim(targetInput or "")
    if targetInput == "" then
        return nil, nil
    end
    local npcID = 0
    local npcName = ""
    local pureID = string.match(targetInput, "^(%d+)$")
    local idPart, namePart = string.match(targetInput, "^(%d+)%s+(.+)$")
    if pureID then
        npcID = tonumber(pureID) or 0
    elseif idPart and namePart then
        npcID = tonumber(idPart) or 0
        npcName = strtrim(namePart)
    else
        npcName = targetInput
    end
    return self:EnsureTargetRoute(npcID, npcName)
end

function ns:MoveTargetToGroup(routeKey, groupName)
    local route = self.db and self.db.routeMappings and self.db.routeMappings[routeKey]
    if not route or type(groupName) ~= "string" or strtrim(groupName) == "" then return false, 0 end
    groupName = strtrim(groupName)
    local names = {}
    for _, name in ipairs(route.teams or {}) do names[name] = true end
    if route.teamName then names[route.teamName] = true end
    self:EnsureTeamGroup(groupName)
    local count = 0
    for _, team in ipairs(self.db.teams or {}) do
        if names[team.name] then team.group = groupName; count = count + 1 end
    end
    self.db.expandedMatrixGroups = self.db.expandedMatrixGroups or {}
    self.db.expandedMatrixGroups[groupName] = true
    self.db.expandedMatrixTargets = self.db.expandedMatrixTargets or {}
    self.db.expandedMatrixTargets[groupName .. "::route:" .. tostring(routeKey)] = true
    self:MarkRoutesDirty()
    return true, count
end

function ns:DeleteTargetRoute(routeKey)
    if not ns.db or not ns.db.routeMappings or not routeKey then return false end
    local route = ns.db.routeMappings[routeKey]
    if not route then return false end

    local affectedTeams = {}
    if route.teams then
        for _, tn in ipairs(route.teams) do
            affectedTeams[tn] = true
        end
    end
    ns.db.routeMappings[routeKey] = nil
    if ns.db.lastActiveRouteKey == routeKey then
        ns.db.lastActiveRouteKey = nil
    end
    if type(ns.db.gossipRouteMap) == "table" then
        for optID, mappedKey in pairs(ns.db.gossipRouteMap) do
            if mappedKey == routeKey then
                ns.db.gossipRouteMap[optID] = nil
            end
        end
    end

    for _, map in ipairs({ns.db.gossipExplicitRouteMap or {}, ns.db.gossipLearnedRouteMap or {}}) do
        for id, key in pairs(map) do if key == routeKey then map[id] = nil end end
    end

    for tName in pairs(affectedTeams) do
        self:RemoveTeamFromTarget(tName, nil)
    end
    self:MarkRoutesDirty()
    return true
end

function ns:DeleteTeamByName(teamName)
    if not ns.db or not ns.db.teams or not teamName then return false end
    if #ns.db.teams <= 1 then return false end
    local selected = ns.db.teams[ns.db.selectedTeamIdx]
    local deleteIndex
    for idx = #ns.db.teams, 1, -1 do
        if ns.db.teams[idx].name == teamName then deleteIndex = idx; break end
    end
    if not deleteIndex then return false end
    for k in pairs(ns.db.routeMappings or {}) do
        self:RemoveTeamFromTarget(teamName, k)
    end
    table.remove(ns.db.teams, deleteIndex)
    local selectedIndex
    for idx, team in ipairs(ns.db.teams) do
        if team == selected then selectedIndex = idx; break end
    end
    ns.db.selectedTeamIdx = selectedIndex or math.min(deleteIndex, #ns.db.teams)
    if not selectedIndex and ns.AutoRouting and ns.AutoRouting.ApplyTeamData then
        ns.AutoRouting:ApplyTeamData(ns.db.teams[ns.db.selectedTeamIdx])
    end
    self:MarkRoutesDirty()
    return true
end

-- ==================== 删除分组及下属全部队伍 ====================
function ns:DeleteTeamGroupAndTeams(groupName, deleteSubTeams)
    if not ns.db or not groupName or groupName == "未分组队伍" then return false end

    local selectedTeamObj = ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]

    if deleteSubTeams then
        local toDelete = {}
        for _, t in ipairs(ns.db.teams or {}) do
            if (t.group or "未分组队伍") == groupName then
                table.insert(toDelete, t.name)
            end
        end
        for _, tName in ipairs(toDelete) do
            for k in pairs(ns.db.routeMappings or {}) do
                self:RemoveTeamFromTarget(tName, k)
            end
        end
        for i = #(ns.db.teams or {}), 1, -1 do
            if (ns.db.teams[i].group or "未分组队伍") == groupName then
                table.remove(ns.db.teams, i)
            end
        end
        if #ns.db.teams == 0 then
            table.insert(ns.db.teams, {
                name = self:T("默认队伍 #1"),
                group = "未分组队伍",
                npcID = 0,
                npcName = "",
                gossipIndex = 1,
                pets = { nil, nil, nil },
                speciesLoadout = { 0, 0, 0 },
                abilities = { {0,0,0}, {0,0,0}, {0,0,0} },
                slotThresholds = { [1] = 0, [2] = 0, [3] = 0 },
                hasLevelingSlot = false,
                levelingSlot = 2,
                script = ns:GetDefaultBattleScript(),
            })
        end
    else
        for _, t in ipairs(ns.db.teams or {}) do
            if t.group == groupName then
                t.group = "未分组队伍"
            end
        end
    end

    if ns.db.teamGroups then
        for i = #ns.db.teamGroups, 1, -1 do
            if ns.db.teamGroups[i] == groupName then
                table.remove(ns.db.teamGroups, i)
            end
        end
    end

    if ns.teamFilterState and ns.teamFilterState.group == groupName then
        ns.teamFilterState.group = "ALL"
    end
    if ns.db.expandedMatrixGroups then
        ns.db.expandedMatrixGroups[groupName] = nil
    end

    local newSelIdx = 1
    for idx, t in ipairs(ns.db.teams) do
        if t == selectedTeamObj then
            newSelIdx = idx
            break
        end
    end
    ns.db.selectedTeamIdx = math.min(newSelIdx, #ns.db.teams)
    if deleteSubTeams and ns.db.teams[ns.db.selectedTeamIdx] ~= selectedTeamObj
        and ns.AutoRouting and ns.AutoRouting.ApplyTeamData then
        ns.AutoRouting:ApplyTeamData(ns.db.teams[ns.db.selectedTeamIdx])
    end

    self:MarkRoutesDirty()
    if ns.RefreshAllUI then ns:RefreshAllUI() end
    return true
end

-- ==================== 目标换队中心：上下箭头调整目标内队伍顺序 ====================
function ns:MoveTeamOrderInRoute(routeKey, teamIndex, direction)
    if not ns.db or not ns.db.routeMappings or not routeKey then return false end
    local route = ns.db.routeMappings[routeKey]
    if not route or not route.teams then return false end

    local targetIdx = teamIndex + direction
    if targetIdx < 1 or targetIdx > #route.teams then return false end

    route.teams[teamIndex], route.teams[targetIdx] = route.teams[targetIdx], route.teams[teamIndex]
    route.teamName = route.teams[1] or ""

    self:MarkRoutesDirty()
    -- Reordering teams only changes this route's presentation. A full UI
    -- refresh also rescans the home cabin, picker, matrix, and builder.
    if ns.RoutingModal and ns.RoutingModal:IsVisible() and ns.RoutingModal.Refresh then
        ns.RoutingModal:Refresh()
    end
    return true
end

local function ParseTargetAssignment(self, targetInput)
    if not targetInput then return nil, nil, self:T("输入内容为空") end
    targetInput = strtrim(targetInput)
    if targetInput == "" then return nil, nil, self:T("请输入有效的 NPC ID 或 NPC 名称") end

    local npcID = 0
    local npcName = ""

    local pureID = string.match(targetInput, "^(%d+)$")
    local idPart, namePart = string.match(targetInput, "^(%d+)%s+(.+)$")
    if pureID then
        npcID = tonumber(pureID) or 0
    elseif idPart and namePart then
        npcID = tonumber(idPart) or 0
        npcName = strtrim(namePart)
    else
        npcName = targetInput
    end

    return npcID, npcName
end

local function AssignTeamsToResolvedTarget(self, teams, npcID, npcName, deferRefresh)
    local route, rKey = self:FindExistingRouteForNPC(npcID, npcName)
    if not route then
        rKey = (npcID > 0) and tostring(npcID) or npcName
        local displayLabel = (npcName ~= "") and npcName or tostring(npcID)
        route = {
            npcID = npcID,
            npcName = displayLabel,
            teamName = "",
            teams = {},
            gossipIndex = 1,
            reviveLoadTeam1 = true,
        }
        ns.db.routeMappings[rKey] = route
    else
        if npcID > 0 and (not route.npcID or route.npcID == 0) then
            route.npcID = npcID
        end
        if npcName ~= "" and (not route.npcName or route.npcName == "" or route.npcName == tostring(route.npcID)) then
            route.npcName = npcName
        end
        if route.reviveLoadTeam1 == nil then
            route.reviveLoadTeam1 = true
        end
        route.teams = route.teams or {}
    end
    local members = {}
    for _, name in ipairs(route.teams) do members[name] = true end
    for _, team in ipairs(teams) do
        if not members[team.name] then
            table.insert(route.teams, team.name)
            members[team.name] = true
        end
        team.npcID = route.npcID or npcID or 0
        team.npcName = route.npcName or npcName or ""
    end
    route.teamName = route.teams[1] or ""
    ns.db.lastActiveRouteKey = rKey

    self:MarkRoutesDirty()
    self:RegisterRouteInIndex(rKey, route)
    if ns.AutoRouting.TryLearnCurrentGossip then ns.AutoRouting:TryLearnCurrentGossip(rKey) end
    if not deferRefresh and ns.RefreshAllUI then ns:RefreshAllUI() end
    return true, rKey, route
end

function ns:AssignTeamToTarget(team, targetInput, sourceRouteKey)
    if not team then return false, self:T("输入内容为空") end
    local npcID, npcName, err = ParseTargetAssignment(self, targetInput)
    if not npcID then return false, err end
    if sourceRouteKey then
        self:RemoveTeamFromTarget(team.name, sourceRouteKey)
    else
        for k in pairs(ns.db.routeMappings or {}) do
            self:RemoveTeamFromTarget(team.name, k)
        end
    end

    return AssignTeamsToResolvedTarget(self, { team }, npcID, npcName)
end

function ns:AssignImportedTeamsToTarget(importedTeams, targetInput)
    local npcID, npcName, err = ParseTargetAssignment(self, targetInput)
    if not npcID then return false, err end

    local current = {}
    for _, team in ipairs(ns.db.teams) do current[team] = true end
    local teams, movingNames = {}, {}
    for index, team in ipairs(importedTeams) do
        if current[team] and team.name then movingNames[team.name] = index end
    end
    for index, team in ipairs(importedTeams) do
        if team.name and movingNames[team.name] == index then
            teams[#teams + 1] = team
        end
    end
    if #teams == 0 then return false end

    for _, route in pairs(ns.db.routeMappings) do
        if route.teams then
            local count, kept = #route.teams, 0
            for i = 1, count do
                local name = route.teams[i]
                if not movingNames[name] then
                    kept = kept + 1
                    route.teams[kept] = name
                end
            end
            for i = kept + 1, count do route.teams[i] = nil end
            route.teamName = route.teams[1] or ""
        end
    end
    return AssignTeamsToResolvedTarget(self, teams, npcID, npcName, true)
end

-- ==================== 按解锁等级 (1,2,4,10,15,20) 严格稳定排序物种技能（零临时包装表） ====================
local sortedAbilityCache = {}
function ns:GetSortedPetAbilities(speciesID)
    if not speciesID or speciesID <= 0 then return nil, nil end
    local cached = sortedAbilityCache[speciesID]
    if cached then
        return cached.ids, cached.levels
    end

    local idTable, levelTable = C_PetJournal.GetPetAbilityList(speciesID)
    if not idTable or not levelTable or #idTable == 0 then
        return idTable, levelTable
    end

    for i = 2, #idTable do
        local curID = idTable[i]
        local curLv = levelTable[i] or i
        local j = i - 1
        while j >= 1 and (levelTable[j] or j) > curLv do
            idTable[j + 1] = idTable[j]
            levelTable[j + 1] = levelTable[j]
            j = j - 1
        end
        idTable[j + 1] = curID
        levelTable[j + 1] = curLv
    end

    sortedAbilityCache[speciesID] = { ids = idTable, levels = levelTable }
    return idTable, levelTable
end

-- ==================== Rematch Base-32 编解码与 PetTag 解析器 ====================
local BASE32_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUV"

function ns:FromBase32(str)
    if not str or str == "" then return nil end
    str = strupper(strtrim(str))
    local num = 0
    for i = 1, #str do
        local c = string.sub(str, i, i)
        local pos = string.find(BASE32_ALPHABET, c, 1, true)
        if not pos then return nil end
        num = num * 32 + (pos - 1)
    end
    return num
end

function ns:ToBase32(num)
    num = tonumber(num)
    if not num or num < 0 then return "0" end
    num = math.floor(num)
    if num == 0 then return "0" end
    local tmp = {}
    local len = 0
    while num > 0 do
        local d = (num % 32) + 1
        len = len + 1
        tmp[len] = string.sub(BASE32_ALPHABET, d, d)
        num = math.floor(num / 32)
    end
    for i = 1, math.floor(len / 2) do
        tmp[i], tmp[len - i + 1] = tmp[len - i + 1], tmp[i]
    end
    return table.concat(tmp, "")
end

function ns:ParseRematchPetTag(tag, scriptText)
    if not tag or strtrim(tag) == "" then return nil end
    tag = strtrim(tag)

    if tag == "L" or tag == "ZL" or tag == "Q" or tag == "0" then
        return { isLeveling = true }
    end

    local rndTypeHex = string.match(tag, "^Z?R([0-9A-V]*)$")
    if rndTypeHex then
        local pType = (rndTypeHex ~= "" and self:FromBase32(rndTypeHex)) or 0
        return { isRandom = true, randomPetType = pType or 0 }
    end

    if string.find(tag, "^Z?I") then
        return { isIgnored = true }
    end

    local a1, a2, a3, _, spBase32 = string.match(tag, "^([012])([012])([012])([0-9A-V])([0-9A-V]+)$")
    if a1 and spBase32 then
        local speciesID = self:FromBase32(spBase32)
        if speciesID and speciesID > 0 then
            local abilities = { 0, 0, 0 }
            local sortedIDs = self:GetSortedPetAbilities(speciesID)
            local tiers = { tonumber(a1) or 0, tonumber(a2) or 0, tonumber(a3) or 0 }

            local scriptAbilitySet = nil
            if scriptText and scriptText ~= "" then
                for idStr in string.gmatch(scriptText, ":(%d+)%)") do
                    local numID = tonumber(idStr)
                    if numID then
                        if not scriptAbilitySet then scriptAbilitySet = {} end
                        scriptAbilitySet[numID] = true
                    end
                end
            end

            if sortedIDs and #sortedIDs >= 3 then
                for s = 1, 3 do
                    local tier1ID = sortedIDs[s] or 0
                    local tier2ID = sortedIDs[s + 3] or tier1ID

                    if tiers[s] == 2 then
                        abilities[s] = tier2ID
                    elseif tiers[s] == 1 then
                        abilities[s] = tier1ID
                    else
                        if scriptAbilitySet and scriptAbilitySet[tier2ID] and not scriptAbilitySet[tier1ID] then
                            abilities[s] = tier2ID
                        else
                            abilities[s] = tier1ID
                        end
                    end

                    if scriptAbilitySet then
                        if scriptAbilitySet[tier2ID] and not scriptAbilitySet[tier1ID] then
                            abilities[s] = tier2ID
                        elseif scriptAbilitySet[tier1ID] and not scriptAbilitySet[tier2ID] then
                            abilities[s] = tier1ID
                        end
                    end
                end
            end

            return {
                isLeveling   = false,
                speciesID    = speciesID,
                abilityTiers = tiers,
                abilities    = abilities,
            }
        end
    end

    return nil
end

local function ReplaceLocalizedAbility(prefix, oldName, idStr, suffix)
    local abID = tonumber(idStr)
    if abID and abID > 0 then
        local localName = C_PetJournal.GetPetAbilityInfo(abID)
            or (C_PetBattles and C_PetBattles.GetAbilityInfoByID and select(2, C_PetBattles.GetAbilityInfoByID(abID)))
        if localName and localName ~= "" then
            return prefix .. localName .. ":" .. idStr .. suffix
        end
    end
    return prefix .. oldName .. ":" .. idStr .. suffix
end

function ns:LocalizeScriptAbilities(scriptText)
    if not scriptText or scriptText == "" then return "" end
    return (string.gsub(scriptText, "([%(,])([^:%(%)%[\r\n]+):(%d+)(%))", ReplaceLocalizedAbility))
end

-- ==================== 精准接管：Shift+P 打开自带藏品，点击「宠物手册」标签打开本插件 ====================
local tabClickHooked = false
local setTabHooked = false
local isHijackingTab = false

local function RedirectPetTabToWishPetTactics(allowToggleClose)
    if isHijackingTab then return end
    if not ns.db or not ns.db.settings.overrideJournal then return end
    isHijackingTab = true
    local wasMainShown = (ns.MainFrame and ns.MainFrame:IsShown()) and true or false
    if CollectionsJournal then
        if CollectionsJournal_SetTab then
            CollectionsJournal_SetTab(CollectionsJournal, 1)
        end
        HideUIPanel(CollectionsJournal)
    end
    if allowToggleClose and wasMainShown then
        ns:RequestMainFrameClose()
    else
        ns:ShowMainFrame()
    end
    isHijackingTab = false
end

function ns:SetupJournalHijack()
    if not ns.journalToggleHooked and ToggleCollectionsJournal then
        hooksecurefunc("ToggleCollectionsJournal", function(tabIndex)
            ns:SetupJournalHijack()
            if not ns.db or not ns.db.settings.overrideJournal or isHijackingTab then return end
            if CollectionsJournal and CollectionsJournal:IsShown() then
                local curTab = PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(CollectionsJournal)
                if curTab == 2 then
                    if tabIndex == 2 then
                        RedirectPetTabToWishPetTactics(true)
                    elseif CollectionsJournal_SetTab then
                        isHijackingTab = true
                        CollectionsJournal_SetTab(CollectionsJournal, 1)
                        isHijackingTab = false
                    end
                end
            end
        end)
        ns.journalToggleHooked = true
    end

    if not setTabHooked and CollectionsJournal_SetTab then
        hooksecurefunc("CollectionsJournal_SetTab", function(frame, tab)
            if tab == 2 and not isHijackingTab and frame == CollectionsJournal and CollectionsJournal:IsShown() then
                RedirectPetTabToWishPetTactics()
            end
        end)
        setTabHooked = true
    end

    local tab2 = _G.CollectionsJournalTab2 or (CollectionsJournal and CollectionsJournal.Tabs and CollectionsJournal.Tabs[2])
    if not tabClickHooked and tab2 then
        tab2:HookScript("OnClick", function()
            RedirectPetTabToWishPetTactics()
        end)
        tabClickHooked = true
    end
end

function ns:OpenBlizzardCollectionsTab(tabIndex)
    tabIndex = tabIndex or 1
    if ns.MainFrame and ns.MainFrame:IsShown() then
        self:RequestHomeAction(function()
            ns.MainFrame:Hide()
            self:OpenBlizzardCollectionsTab(tabIndex)
        end)
        return
    end
    if not C_AddOns.IsAddOnLoaded("Blizzard_Collections") then
        C_AddOns.LoadAddOn("Blizzard_Collections")
    end
    ns:SetupJournalHijack()
    if CollectionsJournal then
        isHijackingTab = true
        ShowUIPanel(CollectionsJournal)
        CollectionsJournal_SetTab(CollectionsJournal, tabIndex)
        isHijackingTab = false
    elseif ToggleCollectionsJournal then
        ToggleCollectionsJournal(tabIndex)
    end
end

function ns:OpenBlizzardMounts()
    self:OpenBlizzardCollectionsTab(1)
end

-- ==================== 轻量级小地图入口按钮（静止零 CPU，支持圆形/方形小地图拖拽） ====================
function ns:CreateMinimapButton()
    if ns.MinimapButton or not Minimap then return ns.MinimapButton end

    local btn = CreateFrame("Button", "WishPetTacticsMinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER", 0, 0)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Minimap\\icon.tga", "CLAMP", "CLAMP", "LINEAR")
    icon:SetTexCoord(0, 1, 0, 1)
    ns.Theme:SnapTextureToPixel(icon)

    if btn.CreateMaskTexture then
        local mask = btn:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
    end
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    function btn:UpdatePosition()
        local angle = (ns.db and ns.db.settings and tonumber(ns.db.settings.minimapAngle)) or 205
        local rad = math.rad(angle)
        local w = (Minimap:GetWidth() or 198) * 0.5 + 5
        local h = (Minimap:GetHeight() or 198) * 0.5 + 5
        local x, y = math.cos(rad), math.sin(rad)

        if GetMinimapShape and GetMinimapShape() == "SQUARE" then
            x = math.max(-w, math.min(w, x * w * 1.414))
            y = math.max(-h, math.min(h, y * h * 1.414))
        else
            x = x * w
            y = y * h
        end

        self:ClearAllPoints()
        self:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    local function UpdateDragAngle()
        local mx, my = Minimap:GetCenter()
        if not mx or not my then return end
        local scale = Minimap:GetEffectiveScale() or 1
        local cx, cy = GetCursorPosition()
        cx, cy = cx / scale, cy / scale
        local angle = math.deg(math.atan2(cy - my, cx - mx))
        if angle < 0 then angle = angle + 360 end
        if ns.db and ns.db.settings then
            ns.db.settings.minimapAngle = angle
        end
        btn:UpdatePosition()
    end

    btn:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", UpdateDragAngle)
    end)

    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if ns.ToggleTeamMatrixModal then
                ns:ToggleTeamMatrixModal()
            else
                ns:ToggleMainFrame()
            end
        else
            ns:ToggleMainFrame()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffffffffWish|r |cffc4a0ecPet Tactics|r " .. ns:T("宠物对战中心"))
        GameTooltip:AddLine(ns:T("左键点击：打开 / 关闭主界面"), 0.85, 0.90, 0.98)
        GameTooltip:AddLine(ns:T("右键点击：打开队伍管理"), 0.85, 0.90, 0.98)
        GameTooltip:AddLine(ns:T("按住拖动：调整图标位置"), 0.60, 0.68, 0.80)
        GameTooltip:AddLine(ns:T("斜杠命令：") .. "|cff10b981/wp help|r", 0.60, 0.68, 0.80)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    btn:UpdatePosition()
    ns.MinimapButton = btn
    ns.Theme:RefreshMinimapIconMetrics()
    return btn
end

function ns:RenameTeam(teamIndex, newName, deferRefresh, importLookup)
    local team = ns.db.teams[teamIndex]
    if not team or not newName then return false end
    newName = strtrim(newName)
    if newName == "" then return false end

    local lowerNew = strlower(newName)
    if importLookup then
        local ownName = team.name and strlower(strtrim(team.name))
        if (importLookup.usedNames[lowerNew] or 0) > (ownName == lowerNew and 1 or 0) then
            newName = self:GetUniqueTeamNameForImport(newName, importLookup)
        end
    else
        for idx, t in ipairs(ns.db.teams) do
            if idx ~= teamIndex and t.name and strlower(strtrim(t.name)) == lowerNew then
                newName = self:GetUniqueTeamNameForImport(newName)
                break
            end
        end
    end

    local oldName = team.name
    team.name = newName

    for _, route in pairs(ns.db.routeMappings) do
        if route.teamName == oldName then
            route.teamName = newName
        end
        if route.teams then
            local seen = {}
            local cleaned = {}
            for _, tName in ipairs(route.teams) do
                local mapped = (tName == oldName) and newName or tName
                if not seen[mapped] then
                    seen[mapped] = true
                    table.insert(cleaned, mapped)
                end
            end
            route.teams = cleaned
            route.teamName = cleaned[1] or ""
        end
    end

    self:MarkRoutesDirty()
    if not deferRefresh and ns.RefreshAllUI then ns:RefreshAllUI() end
    return true
end

-- ==================== 单队 / 纯脚本 / 分组 / 目标 / 全量导出引擎 ====================
function ns:ExportSingleTeamScript(teamOrIdx)
    local team = (type(teamOrIdx) == "number") and (ns.db and ns.db.teams and ns.db.teams[teamOrIdx]) or teamOrIdx
    if not team then
        team = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
    end
    if not team or not team.script then return "" end
    local clean = ns.Syntax and ns.Syntax:StripColors(team.script) or team.script
    return strtrim(clean)
end

function ns:FormatSingleTeamExportString(team, isCurrentSelected, overrideNpcID)
    if not team then return "" end
    local effNpcID = tonumber(overrideNpcID) or tonumber(team.npcID) or 0
    if effNpcID <= 0 and team.name then
        local r = self:FindRouteContainingTeam(team.name)
        if r and tonumber(r.npcID) and tonumber(r.npcID) > 0 then
            effNpcID = tonumber(r.npcID)
        end
    end

    local npcBase32 = (effNpcID > 0) and self:ToBase32(effNpcID) or ""
    local tags = {}

    for slot = 1, 3 do
        if team.hasLevelingSlot and (team.levelingSlot or ns.db.settings.levelingSlot or 2) == slot then
            tags[slot] = "ZL"
        elseif team.randomSlots and team.randomSlots[slot] ~= nil then
            tags[slot] = "ZR" .. self:ToBase32(team.randomSlots[slot] or 0)
        else
            local spID = (team.speciesLoadout and team.speciesLoadout[slot]) or 0
            if spID == 0 and team.pets and team.pets[slot] and team.pets[slot] ~= "LEVELING" then
                spID = C_PetJournal.GetPetInfoByPetID(team.pets[slot]) or 0
            end
            if spID == 0 and isCurrentSelected then
                local petID = C_PetJournal.GetPetLoadOutInfo(slot)
                spID = (petID and C_PetJournal.GetPetInfoByPetID(petID)) or 0
            end

            if spID and spID > 0 then
                local sortedIDs = self:GetSortedPetAbilities(spID)
                local curAb = (team.abilities and team.abilities[slot]) or { 0, 0, 0 }
                local t1, t2, t3 = 1, 1, 1
                if sortedIDs and #sortedIDs >= 6 then
                    if curAb[1] == sortedIDs[4] then t1 = 2 end
                    if curAb[2] == sortedIDs[5] then t2 = 2 end
                    if curAb[3] == sortedIDs[6] then t3 = 2 end
                end
                tags[slot] = string.format("%d%d%d0%s", t1, t2, t3, self:ToBase32(spID))
            else
                tags[slot] = "ZI"
            end
        end
    end

    local cleanScript = self:ExportSingleTeamScript(team)
    local out = string.format("%s:%s:%s:%s:%s:", team.name or "WishTeam", npcBase32, tags[1], tags[2], tags[3])
    if cleanScript ~= "" then
        out = out .. "N:\n-----BEGIN PET BATTLE SCRIPT-----\n" .. cleanScript .. "\n-----END PET BATTLE SCRIPT-----"
    end
    return out
end

function ns:ExportSingleTeamString(teamOrIdx, isCurrentSelected, overrideNpcID)
    local team
    if type(teamOrIdx) == "number" then
        team = ns.db and ns.db.teams and ns.db.teams[teamOrIdx]
    else
        team = teamOrIdx
    end
    if not team then return "" end
    if isCurrentSelected == nil and ns.db and ns.db.teams then
        isCurrentSelected = (team == ns.db.teams[ns.db.selectedTeamIdx])
    end
    local headerGroup = (team.group and team.group ~= "") and string.format("__ %s:1:0::: __\n\n", team.group) or ""
    return headerGroup .. self:FormatSingleTeamExportString(team, isCurrentSelected, overrideNpcID)
end

function ns:ExportCurrentTeamString()
    local team = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
    if not team then return "" end
    return self:ExportSingleTeamString(team, true)
end

-- 导出指定分组下的全部队伍（包含分组头、每支队伍的目标 NPC ID、宠物技能与各自脚本）
function ns:ExportGroupTeamsString(groupName)
    if not ns.db or not ns.db.teams or not groupName or groupName == "" then
        return "", 0
    end

    local blocks = { string.format("__ %s:1:1::: __", groupName) }
    local count = 0

    for idx, t in ipairs(ns.db.teams) do
        if (t.group or "未分组队伍") == groupName then
            count = count + 1
            blocks[#blocks + 1] = self:FormatSingleTeamExportString(t, idx == ns.db.selectedTeamIdx)
        end
    end

    if count == 0 then
        return "", 0
    end
    return table.concat(blocks, "\n\n"), count
end

-- 按出战顺序导出指定目标下的全部队伍（包含所属分组头、目标 NPC ID 与各自脚本）
function ns:ExportTargetRouteTeamsString(routeKey)
    if not ns.db or not ns.db.routeMappings or not routeKey then
        return "", 0
    end
    local route = ns.db.routeMappings[routeKey]
    if not route or not route.teams or #route.teams == 0 then
        return "", 0
    end

    local routeNpcID = tonumber(route.npcID) or 0
    local blocks = {}
    local lastGroup = nil
    local count = 0

    for _, tName in ipairs(route.teams) do
        local tObj, tIdx = ns.AutoRouting:FindTeamByName(tName)
        if tObj then
            local grp = tObj.group or "未分组队伍"
            if grp ~= lastGroup then
                blocks[#blocks + 1] = string.format("__ %s:1:0::: __", grp)
                lastGroup = grp
            end
            count = count + 1
            blocks[#blocks + 1] = self:FormatSingleTeamExportString(tObj, tIdx == ns.db.selectedTeamIdx, routeNpcID)
        end
    end

    if count == 0 then
        return "", 0
    end
    return table.concat(blocks, "\n\n"), count
end

-- 单独导出指定目标下队伍的纯对战脚本（单队直接输出纯脚本，多队带注释分隔头）
function ns:ExportTargetRouteScripts(routeKey)
    if not ns.db or not ns.db.routeMappings or not routeKey then
        return "", 0
    end
    local route = ns.db.routeMappings[routeKey]
    if not route or not route.teams or #route.teams == 0 then
        return "", 0
    end

    local validTeams = {}
    for _, tName in ipairs(route.teams) do
        local tObj = ns.AutoRouting:FindTeamByName(tName)
        if tObj then
            validTeams[#validTeams + 1] = tObj
        end
    end
    if #validTeams == 0 then
        return "", 0
    end
    if #validTeams == 1 then
        return self:ExportSingleTeamScript(validTeams[1]), 1
    end

    local parts = {}
    for i, tObj in ipairs(validTeams) do
        local s = self:ExportSingleTeamScript(tObj)
        parts[#parts + 1] = string.format("-- [%d] %s\n%s", i, tObj.name or ("Team " .. i), s)
    end
    return table.concat(parts, "\n\n"), #validTeams
end

function ns:ExportAllTeamsString()
    if not ns.db or not ns.db.teams or #ns.db.teams == 0 then return "" end

    local groupedTeams = {}
    local groupOrder = {}
    local seenGroup = {}

    if ns.db.teamGroups then
        for _, gName in ipairs(ns.db.teamGroups) do
            groupedTeams[gName] = {}
            table.insert(groupOrder, gName)
            seenGroup[gName] = true
        end
    end

    for idx, t in ipairs(ns.db.teams) do
        local g = t.group or "未分组队伍"
        if not seenGroup[g] then
            groupedTeams[g] = {}
            table.insert(groupOrder, g)
            seenGroup[g] = true
        end
        table.insert(groupedTeams[g], { team = t, isSel = (idx == ns.db.selectedTeamIdx) })
    end

    local blocks = {}
    for gIdx, gName in ipairs(groupOrder) do
        local list = groupedTeams[gName]
        if list and #list > 0 then
            table.insert(blocks, string.format("__ %s:1:%s::: __", gName, self:ToBase32(gIdx)))
            for _, item in ipairs(list) do
                table.insert(blocks, self:FormatSingleTeamExportString(item.team, item.isSel))
            end
        end
    end

    return table.concat(blocks, "\n\n")
end

function ns:AttachScriptToParsedTeam(teamObj, scriptBody, dryRun)
    if not teamObj then return end
    scriptBody = string.gsub(scriptBody or "", "\\n", "\n")
    scriptBody = strtrim(scriptBody)
    local finalScript = (scriptBody ~= "") and self:LocalizeScriptAbilities(scriptBody) or ns:GetDefaultBattleScript()
    if teamObj.inlineNote and teamObj.inlineNote ~= "" then
        teamObj.script = "-- " .. teamObj.inlineNote .. "\n\n" .. finalScript
    else
        teamObj.script = finalScript
    end

    if scriptBody ~= "" and teamObj.speciesLoadout and teamObj.abilities then
        local scriptAbSet = {}
        for idStr in string.gmatch(scriptBody, ":(%d+)%)") do
            local numID = tonumber(idStr)
            if numID then scriptAbSet[numID] = true end
        end
        for idStr in string.gmatch(scriptBody, "use%((%d+)%)") do
            local numID = tonumber(idStr)
            if numID and numID > 3 then scriptAbSet[numID] = true end
        end
        for idStr in string.gmatch(scriptBody, "ability%((%d+)%)") do
            local numID = tonumber(idStr)
            if numID and numID > 3 then scriptAbSet[numID] = true end
        end
        if next(scriptAbSet) then
            for s = 1, 3 do
                local spID = teamObj.speciesLoadout[s]
                if spID and spID > 0 then
                    local sortedIDs = self:GetSortedPetAbilities(spID)
                    if sortedIDs and #sortedIDs >= 6 then
                        for abIdx = 1, 3 do
                            local t1 = sortedIDs[abIdx]
                            local t2 = sortedIDs[abIdx + 3]
                            if scriptAbSet[t2] and not scriptAbSet[t1] then
                                teamObj.abilities[s][abIdx] = t2
                            elseif scriptAbSet[t1] and not scriptAbSet[t2] then
                                teamObj.abilities[s][abIdx] = t1
                            end
                        end
                        if not dryRun then ns.AutoRouting:RememberSlotSpeciesSkills(s, spID, teamObj.abilities[s]) end
                    end
                end
            end
        end
    end
end

function ns:ParseSingleRematchLine(line, currentGroup, embeddedScript, hasExplicitGroupHeader, parsedSoFar, targetContext, teamLookup, candidateLookup, dryRun)
    local tName, npcCode, tag1, tag2, tag3, tail = string.match(line, "^(.-):([^:]*):([^:]+):([^:]+):([^:]+):?(.*)$")
    if not tName or not tag1 then return nil end

    tName = strtrim(tName)
    if tName == "" then return nil end
    local npcID = (npcCode and npcCode ~= "" and self:FromBase32(npcCode)) or 0

    local ctxNpcID = targetContext and tonumber(targetContext.npcID) or 0
    local ctxNpcName = (targetContext and targetContext.npcName and strtrim(targetContext.npcName)) or ""
    local boundByCtx = false

    local resolvedNpcID, resolvedNpcName, matchedGroup
    if npcID <= 0 and (ctxNpcID > 0 or ctxNpcName ~= "") then
        boundByCtx = true
        resolvedNpcID, resolvedNpcName, matchedGroup = self:FindExistingTargetInfoForImport(
            ctxNpcID,
            (ctxNpcName ~= "" and ctxNpcName or tName),
            parsedSoFar, teamLookup, candidateLookup
        )
        if ctxNpcID > 0 then resolvedNpcID = ctxNpcID end
        if ctxNpcName ~= "" then resolvedNpcName = ctxNpcName end
    else
        resolvedNpcID, resolvedNpcName, matchedGroup = self:FindExistingTargetInfoForImport(npcID, tName, parsedSoFar, teamLookup, candidateLookup)
    end

    local finalGroup = currentGroup or "未分组队伍"
    if not hasExplicitGroupHeader and matchedGroup and matchedGroup ~= "" then
        finalGroup = matchedGroup
    end

    local inlineScript = embeddedScript
    if tail and tail ~= "" then
        local sBlock = string.match(tail, "%-%-%-%-%-BEGIN PET BATTLE SCRIPT%-%-%-%-%-(.-)%-%-%-%-%-END PET BATTLE SCRIPT%-%-%-%-%-")
        if sBlock then
            inlineScript = string.gsub(sBlock, "\\n", "\n")
            tail = string.gsub(tail, "%-%-%-%-%-BEGIN PET BATTLE SCRIPT%-%-%-%-%-.-%-%-%-%-%-END PET BATTLE SCRIPT%-%-%-%-%-", "")
        end
    end

    local newTeam = {
        name = tName,
        group = dryRun and finalGroup or self:EnsureTeamGroup(finalGroup),
        npcID = resolvedNpcID,
        npcName = resolvedNpcName,
        hasExplicitGroup = (hasExplicitGroupHeader == true),
        boundByContext = boundByCtx,
        gossipIndex = 1,
        pets = { nil, nil, nil },
        speciesLoadout = { 0, 0, 0 },
        abilities = { {0,0,0}, {0,0,0}, {0,0,0} },
        slotThresholds = { [1] = 0, [2] = 0, [3] = 0 },
        randomSlots = {},
        hasLevelingSlot = false,
        levelingSlot = 2,
        script = "",
    }

    local rawTags = { tag1, tag2, tag3 }
    for s = 1, 3 do
        local info = self:ParseRematchPetTag(rawTags[s], inlineScript)
        if info then
            if info.isLeveling then
                newTeam.hasLevelingSlot = true
                newTeam.levelingSlot = s
                newTeam.slotThresholds[s] = 40
                newTeam.pets[s] = "LEVELING"
            elseif info.isRandom then
                newTeam.randomSlots[s] = info.randomPetType or 0
            elseif info.speciesID and info.speciesID > 0 then
                newTeam.speciesLoadout[s] = info.speciesID
                newTeam.abilities[s] = ns.AutoRouting:ValidateAbilitiesForSpecies(info.speciesID, info.abilities)
                if not dryRun then ns.AutoRouting:RememberSlotSpeciesSkills(s, info.speciesID, newTeam.abilities[s]) end
            end
        end
    end

    local inlineNote = tail and string.match(tail, "N:(.+)$")
    if inlineNote then
        inlineNote = string.gsub(inlineNote, "\\n", " ")
        inlineNote = strtrim(inlineNote)
        if inlineNote ~= "" then
            newTeam.inlineNote = inlineNote
        end
    end

    self:AttachScriptToParsedTeam(newTeam, inlineScript, dryRun)
    return newTeam
end

-- ==================== 队伍特征比对器 ====================
function ns:IsSamePetLoadout(teamA, teamB)
    if not teamA or not teamB then return false end
    local lvSlotA = teamA.levelingSlot or 2
    local lvSlotB = teamB.levelingSlot or 2
    local hasAnyContent = false

    for s = 1, 3 do
        local isLvA = (teamA.hasLevelingSlot and lvSlotA == s) and true or false
        local isLvB = (teamB.hasLevelingSlot and lvSlotB == s) and true or false
        if isLvA ~= isLvB then return false end

        local rndA = teamA.randomSlots and teamA.randomSlots[s]
        local rndB = teamB.randomSlots and teamB.randomSlots[s]
        if (rndA ~= nil) ~= (rndB ~= nil) then return false end

        if not isLvA and rndA == nil then
            local spA = (teamA.speciesLoadout and teamA.speciesLoadout[s]) or 0
            if spA == 0 and teamA.pets and teamA.pets[s] and teamA.pets[s] ~= "LEVELING" then
                spA = C_PetJournal.GetPetInfoByPetID(teamA.pets[s]) or 0
            end
            local spB = (teamB.speciesLoadout and teamB.speciesLoadout[s]) or 0
            if spB == 0 and teamB.pets and teamB.pets[s] and teamB.pets[s] ~= "LEVELING" then
                spB = C_PetJournal.GetPetInfoByPetID(teamB.pets[s]) or 0
            end
            if spA ~= spB then
                return false
            end
            if spA > 0 then hasAnyContent = true end
        else
            hasAnyContent = true
        end
    end

    return hasAnyContent
end

function ns:IsSameTargetRoute(teamA, teamB)
    if not teamA or not teamB then return false end
    local idA = tonumber(teamA.npcID) or 0
    local idB = tonumber(teamB.npcID) or 0
    if idA > 0 and idB > 0 then
        return idA == idB
    end
    local nameA = strlower(self:ExtractBaseTargetName(teamA.npcName ~= "" and teamA.npcName or teamA.name or ""))
    local nameB = strlower(self:ExtractBaseTargetName(teamB.npcName ~= "" and teamB.npcName or teamB.name or ""))
    return (nameA ~= "" and nameA == nameB)
end

function ns:FindMatchingExistingTeamIndex(newTeam, lookup)
    if not newTeam or not ns.db or not ns.db.teams then return nil, nil end
    local targetName = strlower(strtrim(newTeam.name or ""))

    if lookup and lookup.teams == ns.db.teams then
        local index = lookup.byLoadout[ImportLoadoutKey(newTeam)]
        if not index then return nil, nil end
        local bestIdx, bestTeam = MatchImportBucket(self, lookup, index.byName[targetName], newTeam, targetName)
        local id = tonumber(newTeam.npcID) or 0
        if id > 0 then
            bestIdx, bestTeam = MatchImportBucket(self, lookup, index.byID[id], newTeam, targetName, bestIdx, bestTeam)
        end
        local base = strlower(self:ExtractBaseTargetName(newTeam.npcName ~= "" and newTeam.npcName or newTeam.name or ""))
        local baseMap = id > 0 and index.byBaseNoID or index.byBase
        return MatchImportBucket(self, lookup, baseMap[base], newTeam, targetName, bestIdx, bestTeam)
    end

    for idx, t in ipairs(ns.db.teams) do
        local sameName = (t.name and strlower(strtrim(t.name)) == targetName)
        local sameTarget = self:IsSameTargetRoute(t, newTeam)
        if (sameName or sameTarget) and self:IsSamePetLoadout(t, newTeam) then
            return idx, t
        end
    end

    return nil, nil
end

function ns:GetUniqueTeamNameForImport(baseName, lookup)
    baseName = strtrim(baseName or self:T("未命名队伍"))
    local existingNames = lookup and lookup.usedNames or {}
    if not lookup then
        for _, t in ipairs(ns.db.teams or {}) do
            if t.name then existingNames[strlower(strtrim(t.name))] = true end
        end
    end
    if not existingNames[strlower(baseName)] then
        return baseName
    end
    local cleanBase = self:ExtractBaseTargetName(baseName)
    local n = 2
    while existingNames[strlower(string.format("%s (%d)", cleanBase, n))] or existingNames[strlower(string.format("%s %d", cleanBase, n))] do
        n = n + 1
    end
    return string.format("%s (%d)", cleanBase, n)
end

function ns:OverwriteExistingTeamAt(existIdx, newTeam, deferRefresh, importLookup)
    local existTeam = ns.db.teams[existIdx]
    if not existTeam or not newTeam then return end

    local oldName = existTeam.name
    local finalName = strtrim(newTeam.name or oldName or self:T("未命名队伍"))

    if oldName and oldName ~= finalName then
        self:RenameTeam(existIdx, finalName, deferRefresh, importLookup)
        finalName = existTeam.name
    end

    existTeam.name            = finalName
    existTeam.group           = newTeam.group or existTeam.group or "未分组队伍"
    existTeam.npcID           = (newTeam.npcID and newTeam.npcID > 0) and newTeam.npcID or (existTeam.npcID or 0)
    existTeam.npcName         = (newTeam.npcName and newTeam.npcName ~= "") and newTeam.npcName or (existTeam.npcName or "")
    existTeam.gossipIndex     = newTeam.gossipIndex or existTeam.gossipIndex or 1
    existTeam.pets            = CopyTable(newTeam.pets or { nil, nil, nil })
    existTeam.speciesLoadout  = CopyTable(newTeam.speciesLoadout or { 0, 0, 0 })
    existTeam.abilities       = CopyTable(newTeam.abilities or { {0,0,0}, {0,0,0}, {0,0,0} })
    existTeam.slotThresholds  = CopyTable(newTeam.slotThresholds or existTeam.slotThresholds or { [1] = 0, [2] = 0, [3] = 0 })
    existTeam.randomSlots     = CopyTable(newTeam.randomSlots or {})
    existTeam.hasLevelingSlot = newTeam.hasLevelingSlot and true or false
    existTeam.levelingSlot    = newTeam.levelingSlot or 2
    existTeam.script          = newTeam.script or ""
    existTeam.resolvedPetIDs  = nil
    existTeam._syncedScriptAbilities = nil
    self:MarkRoutesDirty()
end

function ns:CommitImportedTeams(parsedTeams, conflictResolution, targetContext, importLookup)
    if not parsedTeams or #parsedTeams == 0 then
        return false, self:T("未能从文本中解析出有效的队伍数据")
    end

    importLookup = importLookup or CreateImportTeamLookup(ns.db.teams)
    if not conflictResolution then
        local conflicts, conflictSeen = {}, {}
        for _, newTeam in ipairs(parsedTeams) do
            local matchIdx, matchTeam = self:FindMatchingExistingTeamIndex(newTeam, importLookup)
            if matchIdx and matchTeam then
                local label = (matchTeam.name ~= newTeam.name) and (newTeam.name .. "(" .. self:T("同宠同目标:") .. matchTeam.name .. ")") or newTeam.name
                if not conflictSeen[label] then
                    conflictSeen[label] = true
                    table.insert(conflicts, label)
                end
            end
        end
        if #conflicts > 0 then return "CONFLICT", conflicts, parsedTeams end
    end

    local addedCount, overwrittenCount, skippedCount, matchedTargetCount = 0, 0, 0, 0
    local lastIdx = ns.db.selectedTeamIdx or 1
    local lastBoundRouteKey = nil
    local committedTeamsList, routeMembers = {}, {}

    local ctxRouteKey = targetContext and targetContext.routeKey or nil
    local ctxNpcID    = targetContext and tonumber(targetContext.npcID) or 0
    local ctxNpcName  = (targetContext and targetContext.npcName and strtrim(targetContext.npcName)) or ""

    for _, newTeam in ipairs(parsedTeams) do
        local hasExpGrp = newTeam.hasExplicitGroup
        local boundByCtx = newTeam.boundByContext
        newTeam.hasExplicitGroup = nil
        newTeam.boundByContext = nil
        newTeam.inlineNote = nil

        local existIdx = self:FindMatchingExistingTeamIndex(newTeam, importLookup)
        local committedTeam = nil

        if existIdx then
            if conflictResolution == "OVERWRITE" then
                newTeam.group = self:EnsureTeamGroup(newTeam.group)
                if ns.db.teams[existIdx].name ~= strtrim(newTeam.name or ns.db.teams[existIdx].name or "") then
                    -- A rename may replace route member arrays and update their names.
                    wipe(routeMembers)
                end
                self:OverwriteExistingTeamAt(existIdx, newTeam, true, importLookup)
                IndexImportTeam(importLookup, existIdx)
                local updatedIdx = self:FindMatchingExistingTeamIndex(newTeam, importLookup) or existIdx
                committedTeam = ns.db.teams[updatedIdx]
                overwrittenCount = overwrittenCount + 1
                lastIdx = updatedIdx
            else
                skippedCount = skippedCount + 1
            end
        else
            local baseTargetLabel = self:ExtractBaseTargetName(newTeam.name)
            local mNpcID, mNpcName, mGroup = self:FindExistingTargetInfoForImport(
                newTeam.npcID,
                (boundByCtx and ctxNpcName ~= "" and ctxNpcName or newTeam.name),
                nil, importLookup
            )

            if boundByCtx then
                if ctxNpcID > 0 then newTeam.npcID = ctxNpcID end
                if ctxNpcName ~= "" then newTeam.npcName = ctxNpcName end
            else
                if mNpcID and mNpcID > 0 then
                    newTeam.npcID = mNpcID
                end
                if mNpcName and mNpcName ~= "" then
                    newTeam.npcName = mNpcName
                elseif newTeam.npcID and newTeam.npcID > 0 and (not newTeam.npcName or newTeam.npcName == "") then
                    newTeam.npcName = baseTargetLabel
                end
            end

            if not hasExpGrp and mGroup and mGroup ~= "" then
                newTeam.group = self:EnsureTeamGroup(mGroup)
            end

            newTeam.group = self:EnsureTeamGroup(newTeam.group)
            newTeam.name = self:GetUniqueTeamNameForImport(newTeam.name, importLookup)
            local oldTeamCount = #ns.db.teams
            table.insert(ns.db.teams, newTeam)
            -- Appending a team changes route lookups only when its route is updated below.
            if not self._routeIndexDirty and self._lastIndexTeamCount == oldTeamCount then
                self._lastIndexTeamCount = oldTeamCount + 1
            end
            addedCount = addedCount + 1
            lastIdx = #ns.db.teams
            committedTeam = newTeam
        end

        if committedTeam then
            for slot = 1, 3 do
                local speciesID = committedTeam.speciesLoadout and committedTeam.speciesLoadout[slot]
                if speciesID and speciesID > 0 and committedTeam.abilities and committedTeam.abilities[slot] then
                    ns.AutoRouting:RememberSlotSpeciesSkills(slot, speciesID, committedTeam.abilities[slot])
                end
            end
            table.insert(committedTeamsList, committedTeam)
            local existingRoute, rKey = nil, nil

            if boundByCtx and ctxRouteKey and ns.db.routeMappings and ns.db.routeMappings[ctxRouteKey] then
                rKey = ctxRouteKey
                existingRoute = ns.db.routeMappings[ctxRouteKey]
            end

            local routeNpcName = (committedTeam.npcName and committedTeam.npcName ~= "") and committedTeam.npcName or self:ExtractBaseTargetName(committedTeam.name)
            if not existingRoute then
                existingRoute, rKey = self:FindExistingRouteForNPC(committedTeam.npcID, routeNpcName)
            end

            if not existingRoute and ((committedTeam.npcID and committedTeam.npcID > 0) or (committedTeam.npcName and committedTeam.npcName ~= "")) then
                rKey = (committedTeam.npcID and committedTeam.npcID > 0) and tostring(committedTeam.npcID) or routeNpcName
                existingRoute = {
                    npcID = committedTeam.npcID or 0,
                    npcName = routeNpcName,
                    teamName = committedTeam.name,
                    teams = { committedTeam.name },
                    gossipIndex = 1,
                    reviveLoadTeam1 = true,
                }
                ns.db.routeMappings[rKey] = existingRoute
                self:RegisterRouteInIndex(rKey, existingRoute, committedTeam.name)
                lastBoundRouteKey = rKey
                matchedTargetCount = matchedTargetCount + 1
            elseif existingRoute then
                existingRoute.teams = existingRoute.teams or (existingRoute.teamName and existingRoute.teamName ~= "" and { existingRoute.teamName } or {})
                if existingRoute.reviveLoadTeam1 == nil then
                    existingRoute.reviveLoadTeam1 = true
                end
                local members = routeMembers[existingRoute]
                if not members then
                    members = {}
                    for _, name in ipairs(existingRoute.teams) do members[name] = true end
                    routeMembers[existingRoute] = members
                end
                if not members[committedTeam.name] then
                    table.insert(existingRoute.teams, committedTeam.name)
                    members[committedTeam.name] = true
                end
                existingRoute.teamName = existingRoute.teams[1] or committedTeam.name
                if committedTeam.npcID and committedTeam.npcID > 0 and (not existingRoute.npcID or existingRoute.npcID == 0) then
                    existingRoute.npcID = committedTeam.npcID
                end
                committedTeam.npcID = existingRoute.npcID or committedTeam.npcID or 0
                committedTeam.npcName = existingRoute.npcName or routeNpcName
                self:RegisterRouteInIndex(rKey, existingRoute, committedTeam.name)
                lastBoundRouteKey = rKey
                matchedTargetCount = matchedTargetCount + 1
            end
            IndexImportTeam(importLookup, lastIdx)
        end
    end

    self:MarkRoutesDirty()
    ns.db.selectedTeamIdx = math.min(lastIdx, #ns.db.teams)
    ns.staging.isDirty = false

    if lastBoundRouteKey then
        ns.db.lastActiveRouteKey = lastBoundRouteKey
        if ns.RoutingModal and (targetContext ~= nil or not ns.RoutingModal.selectedKey) then
            ns.RoutingModal.pendingTargetID = nil
            ns.RoutingModal.pendingTargetName = nil
            ns.RoutingModal.selectedKey = lastBoundRouteKey
        end
    end

    if ns.db.teams[ns.db.selectedTeamIdx] then
        ns.AutoRouting:ApplyTeamData(ns.db.teams[ns.db.selectedTeamIdx], nil, nil, true)
    end
    if ns.RefreshAllUI then ns:RefreshAllUI() end

    local missingReport, missingSpeciesCount = self:CollectMissingPetsForTeams(committedTeamsList)
    if #missingReport > 0 and ns.ShowMissingPetsModal then
        C_Timer.After(0.25, function()
            ns:ShowMissingPetsModal(missingReport, missingSpeciesCount)
        end)
    end

    local uncollectedNote = (#missingReport > 0) and self:TF(" (发现 %d 只未收集宠物)", missingSpeciesCount) or ""
    local msg = self:TF("导入完成：新增 %d 支，覆盖 %d 支，跳过 %d 支，绑定目标 %d 支%s！",
        addedCount, overwrittenCount, skippedCount, matchedTargetCount, uncollectedNote)
    return true, msg, committedTeamsList
end

-- ==================== 一键同步 Rematch：先校验来源，再按队伍身份写入 ====================
local function CleanRematchName(value)
    if type(value) ~= "string" then return "" end
    return strtrim((value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
end

local function ReadRematchRecords(storage, iteratorName, accept)
    local records = {}
    if type(storage) ~= "table" then return records end
    if type(storage[iteratorName]) == "function" then
        local ok = pcall(function()
            for key, value in storage[iteratorName](storage) do
                if accept(key, value) then records[key] = value end
            end
        end)
        if ok then return records, true end
        wipe(records)
    end
    for key, value in pairs(storage) do
        if accept(key, value) then records[key] = value end
    end
    return records
end

local function ReadRematchNpcID(value)
    local id = type(value) == "number" and value
        or (type(value) == "string" and tonumber(value:match("^npc:(%d+)$") or value))
    return id and id > 0 and id % 1 == 0 and id or nil
end

local function ReadRematchScript(value)
    local code = type(value) == "table" and (value.code or value.script) or value
    return type(code) == "string" and strtrim(code) ~= "" and code or nil
end

local function IndexRematchScripts(root, scripts, seen, depth, namespaced)
    if type(root) ~= "table" or depth > 6 then return end
    local context = namespaced and 2 or 1
    if (seen[root] or 0) >= context then return end
    seen[root] = context
    for key, value in pairs(root) do
        local validKey = type(key) == "number" or type(key) == "string"
        local explicitTeamKey = type(key) == "string" and key:match("^team:[^:]+$")
        local code = validKey and (namespaced or explicitTeamKey) and ReadRematchScript(value)
        if code then
            local previous = scripts[key]
            if previous == nil then scripts[key] = code
            elseif previous ~= code then scripts[key] = false end
        elseif type(value) == "table" then
            IndexRematchScripts(value, scripts, seen, depth + 1,
                namespaced or (type(key) == "string" and strlower(key) == "rematch"))
        end
    end
end

local function ReadRematchSlot(self, team, slot, pet, tag, legacyAbilities, legacySpecies, decoder)
    local special = type(pet) == "string" and strlower(pet) or pet
    if special == 0 or special == "0" or special == "leveling" then tag = "L"
    elseif special == "ignored" then return false
    elseif type(special) == "string" and special:match("^random:%d+$") then
        local petType = tonumber(special:match(":(%d+)$"))
        if petType > 10 then return false end
        team.randomSlots[slot] = petType
        return true, true
    end

    if type(tag) ~= "string" or strtrim(tag) == "" then
        tag = type(pet) == "string" and not tonumber(pet) and not pet:match("^BattlePet%-") and pet or nil
    end
    local speciesID, abilities, tagInfo
    if tag then
        if decoder and type(decoder.GetSpecies) == "function" then
            local ok, id = pcall(decoder.GetSpecies, decoder, tag)
            if ok then speciesID = tonumber(id) end
        end
        if speciesID and speciesID > 0 and type(decoder.GetAbilities) == "function" then
            local ok, a, b, c = pcall(decoder.GetAbilities, decoder, tag)
            if ok and a and b and c then abilities = {a, b, c} end
        end
        tagInfo = self:ParseRematchPetTag(tag)
        if not speciesID or speciesID <= 0 then speciesID = tagInfo and tagInfo.speciesID end
        if not abilities then abilities = tagInfo and tagInfo.abilities end
        if tagInfo and tagInfo.isIgnored then return false end
        if tagInfo and tagInfo.isLeveling then
            if team.hasLevelingSlot then return false end
            team.hasLevelingSlot = true
            team.levelingSlot = slot
            team.pets[slot] = "LEVELING"
            return true, true
        end
        if tagInfo and tagInfo.isRandom then
            local petType = tagInfo.randomPetType
            if petType > 10 then return false end
            team.randomSlots[slot] = petType
            return true, true
        end
    end

    local guid = type(pet) == "string" and pet:match("^BattlePet%-") and pet or nil
    local ownedSpecies = guid and C_PetJournal.GetPetInfoByPetID(guid)
    speciesID = speciesID or legacySpecies or tonumber(pet) or ownedSpecies
    if not speciesID or speciesID <= 0 then
        return (pet == nil or pet == false or pet == "") and tag == nil
    end
    -- 有标签却无法读取其技能时，不能把默认技能写回为源队伍配置。
    abilities = abilities or legacyAbilities
    if tag and not abilities then return false end
    local sortedIDs = self:GetSortedPetAbilities(speciesID)
    if not sortedIDs or #sortedIDs < 3 then return false end
    if abilities then
        for col = 1, 3 do
            local value = abilities[col] or 0
            if value ~= 0 and value ~= 1 and value ~= 2 and value ~= sortedIDs[col] and value ~= sortedIDs[col + 3] then
                return false
            end
        end
    end
    team.speciesLoadout[slot] = speciesID
    team.abilities[slot] = ns.AutoRouting:ValidateAbilitiesForSpecies(speciesID, abilities)
    if guid and ownedSpecies == speciesID then team.pets[slot] = guid end
    return true, true
end

local function FindRematchRouteKeys(routes)
    local keys = {}
    for key, route in pairs(routes) do
        local id = ReadRematchNpcID(route.npcID) or ReadRematchNpcID(key)
        if id then
            local previous = keys[id]
            if not previous or key == tostring(id) or (previous ~= tostring(id) and tostring(key) < tostring(previous)) then
                keys[id] = key
            end
        end
    end
    return keys
end

local function IsSameLegacyRematchTeam(self, existing, incoming)
    if not existing or existing.rematchSourceKey or existing.group ~= incoming.group
        or (tonumber(existing.npcID) or 0) ~= incoming.npcID or not self:IsSamePetLoadout(existing, incoming) then
        return false
    end
    for slot = 1, 3 do
        local oldPet = existing.pets and existing.pets[slot]
        local newPet = incoming.pets[slot]
        if oldPet and newPet and oldPet ~= newPet then return false end
        if (existing.randomSlots and existing.randomSlots[slot]) ~= incoming.randomSlots[slot] then return false end
        if incoming.speciesLoadout[slot] > 0 then
            local oldAbilities = existing.abilities and existing.abilities[slot]
            for col = 1, 3 do
                if not oldAbilities or oldAbilities[col] ~= incoming.abilities[slot][col] then return false end
            end
        end
    end
    return true
end

local function CommitRematchTeams(self, parsed, targetOrder, targetNames, overwrite)
    local teams, routes = ns.db.teams, ns.db.routeMappings
    local bySource, byName, usedNames = {}, {}, {}
    for idx, team in ipairs(teams) do
        if team.rematchSourceKey then bySource[team.rematchSourceKey] = idx end
        local name = strlower(team.name or "")
        byName[name] = byName[name] == nil and idx or false
        usedNames[name] = true
    end

    local routeKeys = FindRematchRouteKeys(routes)
    local committed, orderByTarget, removeByTarget = {}, {}, {}
    local added, updated, skipped = 0, 0, 0

    for _, incoming in ipairs(parsed) do
        local sourceKey, sourceName = incoming.rematchSourceKey, incoming.name
        local idx = bySource[sourceKey] or (incoming.legacySourceKey and bySource[incoming.legacySourceKey])
        incoming.legacySourceKey = nil
        local legacyIdx = byName[strlower(sourceName)]
        local legacy = legacyIdx and teams[legacyIdx]
        if not idx and IsSameLegacyRematchTeam(self, legacy, incoming) then idx = legacyIdx end

        if idx and not overwrite then
            skipped = skipped + 1
        else
            local existing = idx and teams[idx]
            if existing then
                -- 保留 WishPetTactics 独有配置和用户已有的脚本，除非来源有明确脚本。
                incoming.slotThresholds = existing.slotThresholds or incoming.slotThresholds
                incoming.gossipIndex = existing.gossipIndex or 1
                incoming.script = incoming.script or existing.script
                incoming.name = existing.name
                if existing.rematchSourceName and existing.rematchSourceName ~= sourceName then
                    local lower = strlower(sourceName)
                    if not usedNames[lower] or lower == strlower(existing.name) then
                        local oldLower = strlower(existing.name)
                        self:RenameTeam(idx, sourceName, true)
                        if byName[oldLower] == idx then
                            byName[oldLower], usedNames[oldLower] = nil, nil
                        end
                        byName[lower], usedNames[lower] = idx, true
                        incoming.name = existing.name
                    end
                end
                local newTargets = {}
                for _, id in ipairs(incoming.rematchTargetIDs) do newTargets[id] = true end
                for _, id in ipairs(existing.rematchTargetIDs or {}) do
                    if not newTargets[id] then
                        removeByTarget[id] = removeByTarget[id] or {}
                        removeByTarget[id][incoming.name] = true
                    end
                end
                self:OverwriteExistingTeamAt(idx, incoming)
                existing.npcID, existing.npcName = incoming.npcID, incoming.npcName
                existing.manualAbilities = true
                existing.rematchSourceKey = sourceKey
                bySource[sourceKey] = idx
                existing.rematchSourceName = sourceName
                existing.rematchTargetIDs = incoming.rematchTargetIDs
                existing.rematchNotes = incoming.rematchNotes
                incoming = existing
                updated = updated + 1
            else
                local lower = strlower(sourceName)
                if usedNames[lower] then incoming.name = self:GetUniqueTeamNameForImport(sourceName) end
                usedNames[strlower(incoming.name)] = true
                incoming.rematchSourceName = sourceName
                incoming.script = incoming.script or ns:GetDefaultBattleScript()
                teams[#teams + 1] = incoming
                added = added + 1
            end
            self:EnsureTeamGroup(incoming.group)
            committed[#committed + 1] = incoming
            for _, id in ipairs(incoming.rematchTargetIDs) do
                orderByTarget[id] = orderByTarget[id] or {}
                orderByTarget[id][#orderByTarget[id] + 1] = incoming
            end
        end
    end

    local changedTargets = {}
    for id in pairs(orderByTarget) do changedTargets[id] = true end
    for id in pairs(removeByTarget) do changedTargets[id] = true end
    for id in pairs(changedTargets) do
        local synced = orderByTarget[id] or {}
        local oldRouteKey = routeKeys[id]
        local route = oldRouteKey and routes[oldRouteKey]
        if not route and #synced > 0 then
            route = {npcID = id, npcName = targetNames[id], gossipIndex = 1, reviveLoadTeam1 = true}
            routes[tostring(id)] = route
        end
        if route then
            local syncedNames, ordered, seen = {}, {}, {}
            for _, team in ipairs(synced) do
                syncedNames[team.name] = true
            end
            local positions = targetOrder[id] or {}
            table.sort(synced, function(a, b)
                local ap = positions[a.rematchSourceKey] or math.huge
                local bp = positions[b.rematchSourceKey] or math.huge
                if ap ~= bp then return ap < bp end
                return a.rematchSourceKey < b.rematchSourceKey
            end)
            local nextSynced = 1
            local removed = removeByTarget[id] or {}
            for _, name in ipairs(route.teams or {route.teamName}) do
                if syncedNames[name] then
                    local replacement = synced[nextSynced]
                    if replacement and not seen[name] then
                        ordered[#ordered + 1] = replacement.name
                        nextSynced = nextSynced + 1
                    end
                elseif not removed[name] and not seen[name] then
                    ordered[#ordered + 1] = name
                end
                seen[name] = true
            end
            for i = nextSynced, #synced do ordered[#ordered + 1] = synced[i].name end
            route.teams, route.teamName = ordered, ordered[1] or ""
        end
    end

    if #committed > 0 then
        self:MarkRoutesDirty()
        self:InvalidatePetAndTeamCache()
        if ns.RefreshAllUI then ns:RefreshAllUI() end
        local missing, missingCount = self:CollectMissingPetsForTeams(committed)
        if #missing > 0 and ns.ShowMissingPetsModal then
            C_Timer.After(0.25, function() ns:ShowMissingPetsModal(missing, missingCount) end)
        end
    end
    return added, updated, skipped
end

function ns:MigrateFromRematch(overwriteExisting)
    if not ns.db or not ns.db.teams or not ns.db.routeMappings then return false end
    if ns.staging and ns.staging.isDirty then
        self:PrintError("请先保存或还原当前队伍的修改，再同步 Rematch。")
        return false
    end
    if C_AddOns and C_AddOns.LoadAddOn then
        for _, addon in ipairs({"Rematch", "tdBattlePetScript", "tdBattlePetScript_Rematch", "PetBattleScripts"}) do
            if not C_AddOns.IsAddOnLoaded or not C_AddOns.IsAddOnLoaded(addon) then
                pcall(C_AddOns.LoadAddOn, addon)
            end
        end
    end

    local rematch = type(_G.Rematch) == "table" and _G.Rematch or {}
    local function IsR5Team(key, record)
        return (type(key) == "number" or type(key) == "string") and type(record) == "table"
            and type(record.name) == "string" and (type(record.pets) == "table" or type(record.tags) == "table")
    end
    local records, liveReadable = ReadRematchRecords(rematch.savedTeams, "AllTeams", IsR5Team)
    if not next(records) then records = ReadRematchRecords(_G.Rematch5SavedTeams, "AllTeams", IsR5Team) end
    local version = (next(records) or liveReadable or type(_G.Rematch5SavedTeams) == "table") and 5 or 4
    if version == 4 then
        local function IsR4Team(key, data)
            return (type(key) == "number" or type(key) == "string") and type(data) == "table"
                and (type(data[1]) == "table" or type(data[2]) == "table" or type(data[3]) == "table")
        end
        records = ReadRematchRecords(_G.RematchSaved, "AllTeams", IsR4Team)
        if not next(records) then records = ReadRematchRecords(_G.Rematch4Saved, "AllTeams", IsR4Team) end
    end
    if not next(records) then
        self:PrintError("未检测到 Rematch 队伍数据。请启用 Rematch、重新登录并确认其中已有队伍。")
        return false
    end

    local function SourceKey(key)
        local normalized = tostring(key)
        if version == 5 then normalized = normalized:gsub("^team:", "") end
        return version .. ":" .. normalized
    end
    local function IsTarget(key, value) return ReadRematchNpcID(key) and type(value) == "table" end
    local legacyKeys = {}
    local settings = type(rematch.settings) == "table" and rematch.settings or _G.Rematch5Settings
    local converted = type(settings) == "table" and settings.ConvertedTeams
    if version == 5 and type(converted) == "table" then
        for oldKey, newKey in pairs(converted) do
            if type(newKey) == "number" or type(newKey) == "string" then
                local source = SourceKey(newKey)
                if legacyKeys[source] == nil then legacyKeys[source] = oldKey
                elseif legacyKeys[source] ~= oldKey then legacyKeys[source] = false end
            end
        end
    end
    local targets = version == 5 and ReadRematchRecords(rematch.savedTargets, "AllTargets", IsTarget) or {}
    if version == 5 and not next(targets) then targets = ReadRematchRecords(_G.Rematch5SavedTargets, "AllTargets", IsTarget) end
    local targetOrder, indexedTargets = {}, {}
    for key, teamList in pairs(targets) do
        local id = ReadRematchNpcID(key)
        local ranks = targetOrder[id] or {}
        targetOrder[id] = ranks
        for rank, teamKey in ipairs(teamList) do
            if type(teamKey) == "number" or type(teamKey) == "string" then
                local source = SourceKey(teamKey)
                ranks[source] = math.min(ranks[source] or rank, rank)
                indexedTargets[source] = indexedTargets[source] or {}
                indexedTargets[source][id] = true
            end
        end
    end

    local scripts, seen = {}, {}
    IndexRematchScripts(_G.TD_DB_BATTLEPETSCRIPT_GLOBAL, scripts, seen, 0, false)
    IndexRematchScripts(_G.PetBattleScriptsDB, scripts, seen, 0, false)
    local routeKeys = FindRematchRouteKeys(ns.db.routeMappings)
    local targetNames = {}
    local function GetTargetName(id)
        if targetNames[id] then return targetNames[id] end
        local label
        if type(rematch.targetInfo) == "table" and type(rematch.targetInfo.GetNpcName) == "function" then
            local ok, result = pcall(rematch.targetInfo.GetNpcName, rematch.targetInfo, id, true)
            if ok then label = CleanRematchName(result) end
        end
        local route = routeKeys[id] and ns.db.routeMappings[routeKeys[id]]
        targetNames[id] = label and label ~= "" and label or (route and route.npcName) or tostring(id)
        return targetNames[id]
    end
    local groups = type(rematch.savedGroups) == "table" and rematch.savedGroups or {}
    local savedGroups = type(_G.Rematch5SavedGroups) == "table" and _G.Rematch5SavedGroups or {}

    local sortedKeys = {}
    for key in pairs(records) do sortedKeys[#sortedKeys + 1] = key end
    table.sort(sortedKeys, function(a, b)
        if SourceKey(a) ~= SourceKey(b) then return SourceKey(a) < SourceKey(b) end
        return type(a) .. tostring(a) < type(b) .. tostring(b)
    end)

    local parsed, invalid, duplicates = {}, {}, {}
    local usedKeys = {}
    local ambiguousScripts = 0
    local beginScript = "%-%-%-%-%-BEGIN PET BATTLE SCRIPT%-%-%-%-%-"
    local endScript = "%-%-%-%-%-END PET BATTLE SCRIPT%-%-%-%-%-"

    for _, key in ipairs(sortedKeys) do
        local data = records[key]
        local source = SourceKey(key)
        local name = CleanRematchName(data.teamName or data.name or tostring(key))
        local groupID = data.groupID
        local groupData = groupID and (groups[groupID] or savedGroups[groupID])
        local group = CleanRematchName(type(groupData) == "table" and groupData.name or groupData)
        if groupID == "group:none" or group == "Ungrouped Teams" or group == "Ungrouped" then group = "" end
        if groupID == "group:favorites" or group == "Favorite Teams" or group == "Favorites" or (group == "" and data.favorite) then
            group = "最爱队伍"
        end

        local ids, idSet = {}, {}
        local function AddTarget(value)
            local id = ReadRematchNpcID(value)
            if id and not idSet[id] then
                ids[#ids + 1], idSet[id] = id, true
            end
        end
        if version == 5 then
            if type(data.targets) == "table" then
                for _, value in ipairs(data.targets) do AddTarget(value) end
            else
                AddTarget(data.targetID)
                local fallback = {}
                for id in pairs(indexedTargets[source] or {}) do fallback[#fallback + 1] = id end
                table.sort(fallback)
                for _, id in ipairs(fallback) do AddTarget(id) end
            end
        else
            AddTarget(data.npcID or (type(key) == "number" and key))
        end

        local npcID = ids[1] or 0
        for _, id in ipairs(ids) do GetTargetName(id) end
        local npcName = targetNames[npcID] or ""

        local notes = type(data.notes) == "string" and data.notes or ""
        local embedded = notes:gsub("\\n", "\n"):match(beginScript .. "%s*(.-)%s*" .. endScript)
        local legacyKey = legacyKeys[source]
        local exact = scripts[key]
        local alias
        if version == 5 then alias = scripts["team:" .. source:sub(3)] end
        local conflicting = exact == false or alias == false or (exact and alias and exact ~= alias)
        local script = ReadRematchScript(data.script)
        if not script then
            if conflicting then
                ambiguousScripts = ambiguousScripts + 1
            else
                local legacyScript
                if legacyKey then legacyScript = scripts[legacyKey] end
                if not exact and not alias and legacyScript == false then ambiguousScripts = ambiguousScripts + 1 end
                script = exact or alias or legacyScript
            end
            script = script or ReadRematchScript(embedded)
        end
        local team = {
            name = name, group = group ~= "" and group or "未分组队伍",
            npcID = npcID, npcName = npcName, gossipIndex = 1,
            pets = {}, speciesLoadout = {0, 0, 0}, abilities = {{0, 0, 0}, {0, 0, 0}, {0, 0, 0}},
            slotThresholds = {0, 0, 0}, randomSlots = {}, hasLevelingSlot = false, levelingSlot = 2,
            manualAbilities = true, script = script, rematchSourceKey = source, rematchTargetIDs = ids,
            rematchNotes = notes ~= "" and notes or nil,
            legacySourceKey = legacyKey and ("4:" .. tostring(legacyKey)) or nil,
        }

        local valid, populated = name ~= "", false
        for slot = 1, 3 do
            local pet, tag, abilities, legacySpecies
            if version == 5 then
                pet = type(data.pets) == "table" and data.pets[slot]
                tag = type(data.tags) == "table" and data.tags[slot]
            else
                local entry = data[slot]
                if type(entry) == "table" then
                    pet = entry[1]
                    legacySpecies = ReadRematchNpcID(entry[5])
                    abilities = {tonumber(entry[2]) or 0, tonumber(entry[3]) or 0, tonumber(entry[4]) or 0}
                end
            end
            local ok, hasPet = ReadRematchSlot(self, team, slot, pet, tag, abilities, legacySpecies, rematch.petTags)
            valid, populated = valid and ok, populated or hasPet
        end
        if usedKeys[source] then
            duplicates[source] = true
        else
            usedKeys[source] = true
            if valid and populated then parsed[#parsed + 1] = team
            else invalid[#invalid + 1] = name ~= "" and name or source end
        end
    end

    for i = #parsed, 1, -1 do
        if duplicates[parsed[i].rematchSourceKey] then
            invalid[#invalid + 1] = parsed[i].name
            table.remove(parsed, i)
        end
    end
    if #invalid > 0 then
        local examples = table.concat(invalid, "、", 1, math.min(5, #invalid))
        self:PrintError(string.format(self:T("Rematch 有 %d 支队伍的槽位、技能或来源无法确认，已跳过：%s"), #invalid, examples))
    end
    if #parsed == 0 then return false end

    local added, updated, skipped = CommitRematchTeams(self, parsed, targetOrder, targetNames, overwriteExisting)
    local msg = string.format(self:T("Rematch %d 同步完成：新增 %d 支，更新 %d 支，跳过 %d 支，脚本来源冲突 %d 支。"),
        version, added, updated, skipped + #invalid, ambiguousScripts)
    DEFAULT_CHAT_FRAME:AddMessage("|cff10b981[Wish Pet Tactics]|r " .. msg)
    return true, msg
end

function ns:ImportTeamOrScript(rawText, importMode, conflictResolution, targetContext, preview)
    if not rawText or strtrim(rawText) == "" then return false, self:T("导入内容为空") end
    if not preview then preview = self:BuildImportPreview(rawText, importMode) end
    if not preview.valid then return false, preview.error or self:UXText("invalid") end
    if preview.raw and (preview.raw ~= rawText or preview.mode ~= importMode) then
        return false, self:UXText("previewChanged")
    end
    if importMode == "SCRIPT" then
        local team = ns.db.teams[ns.db.selectedTeamIdx]
        if not team or team ~= preview.team or (team.script or "") ~= preview.originalScript then
            return false, self:UXText("previewChanged")
        end
        if self.HasScriptDraft and self:HasScriptDraft(team) then return false, self:UXText("saveDraftFirst") end
        team.script = preview.script
        team.manualAbilities = nil
        if ns.RefreshAllUI then ns:RefreshAllUI() end
        return true, self:UXText("scriptImported", team.name or "")
    end
    local parsedTeams = {}
    local teamLookup = CreateImportTeamLookup(ns.db and ns.db.teams)
    local candidateLookup = CreateImportTeamLookup(parsedTeams, true)
    for _, entry in ipairs(preview.scan.entries) do
        local teamObj = self:ParseSingleRematchLine(entry.line, entry.group, nil, entry.explicitGroup,
            parsedTeams, targetContext, teamLookup, candidateLookup, true)
        if not teamObj then return false, self:UXText("invalid") end
        if entry.hasScript then self:AttachScriptToParsedTeam(teamObj, entry.script, true) end
        table.insert(parsedTeams, teamObj)
        IndexImportTeam(candidateLookup, #parsedTeams)
    end
    local function SameValue(a, b, seen)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        seen = seen or {}
        if seen[a] == b then return true end
        seen[a] = b
        for k, v in pairs(a) do if not SameValue(v, b[k], seen) then return false end end
        for k in pairs(b) do if a[k] == nil then return false end end
        return true
    end
    if conflictResolution and preview.conflictSnapshot then
        for i, incoming in ipairs(parsedTeams) do
            local _, match = self:FindMatchingExistingTeamIndex(incoming, teamLookup)
            local snapshot = preview.conflictSnapshot[i]
            if not snapshot or match ~= snapshot.team or (match and not SameValue(match, snapshot.data)) then
                return false, self:UXText("previewChanged")
            end
        end
    end
    local status, message, committed = self:CommitImportedTeams(parsedTeams, conflictResolution, targetContext, teamLookup)
    if status == "CONFLICT" then
        preview.conflictSnapshot = {}
        for i, incoming in ipairs(parsedTeams) do
            local _, match = self:FindMatchingExistingTeamIndex(incoming, teamLookup)
            preview.conflictSnapshot[i] = {team=match, data=match and CopyTable(match) or nil}
        end
    end
    return status, message, committed
end

local coreFrame = CreateFrame("Frame")
coreFrame:RegisterEvent("ADDON_LOADED")
coreFrame:RegisterEvent("PLAYER_LOGIN")
coreFrame:RegisterEvent("PLAYER_LOGOUT")
coreFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            local previous = WishRematchDB and WishRematchDB.settings
            if type(previous) == "table" and previous.uiAutoScale == nil then
                local manualScale = tonumber(previous.uiScale)
                if manualScale and manualScale ~= 1 then
                    previous.uiAutoScale = false
                end
            end
            WishRematchDB = MergeDefaults(DEFAULT_DB, WishRematchDB)
            ns.db = WishRematchDB
            if ns.ApplyUIStyleBinding then ns:ApplyUIStyleBinding() end

            ns:EnsureTeamGroup("未分组队伍")
            if #ns.db.teams == 0 then
                ns.db.teams[1] = CopyTable(DEFAULT_DB.teams[1])
            end
            if not ns.db.teams[ns.db.selectedTeamIdx] then
                ns.db.selectedTeamIdx = 1
            end

            -- 同引用绑定练级队列筛选状态至 SavedVariables 存档，确保 /rl 重载后完全保持不变
            ns.db.queueFilterState = MergeDefaults(DEFAULT_DB.queueFilterState, ns.db.queueFilterState)
            if type(ns.queueFilterState) == "table" and ns.queueFilterState ~= ns.db.queueFilterState then
                wipe(ns.queueFilterState)
                for k, v in pairs(ns.db.queueFilterState) do
                    ns.queueFilterState[k] = v
                end
                ns.db.queueFilterState = ns.queueFilterState
            else
                ns.queueFilterState = ns.db.queueFilterState
            end

            -- 同引用绑定所有宠物筛选状态至 SavedVariables 存档，避免跨页签筛选在 /rl 后丢失
            ns.db.petFilterState = MergeDefaults(DEFAULT_DB.petFilterState, ns.db.petFilterState)
            if type(ns.petFilterState) == "table" and ns.petFilterState ~= ns.db.petFilterState then
                wipe(ns.petFilterState)
                for k, v in pairs(ns.db.petFilterState) do
                    ns.petFilterState[k] = v
                end
                ns.db.petFilterState = ns.petFilterState
            else
                ns.petFilterState = ns.db.petFilterState
            end

            if ns.db.routeMappings then
                for k, route in pairs(ns.db.routeMappings) do
                    if route.npcName and string.find(route.npcName, "^NPC #%d+$") then
                        ns.db.routeMappings[k] = nil
                    elseif route.reviveLoadTeam1 == nil then
                        route.reviveLoadTeam1 = true
                    end
                end
            end

            local targetGroupMap = {}
            local targetNpcMap = {}
            for _, t in ipairs(ns.db.teams) do
                if not t.group or t.group == "" then
                    t.group = "未分组队伍"
                else
                    ns:EnsureTeamGroup(t.group)
                end
                t.fallbackTeam = nil
                t.resolvedPetIDs = nil
                t._syncedScriptAbilities = nil

                if t.npcName and (string.find(t.npcName, "^NPC #%d+$") or t.npcName == "通用" or t.npcName == "通用速刷" or t.npcName == "日常训练师" or t.npcName == "手动保存") then
                    t.npcName = ""
                end

                local baseKey = strlower(ns:ExtractBaseTargetName((t.npcName and t.npcName ~= "") and t.npcName or t.name or ""))
                local idKey = (t.npcID and tonumber(t.npcID) and tonumber(t.npcID) > 0) and ("ID:" .. tostring(t.npcID)) or nil
                if t.group ~= "未分组队伍" then
                    if idKey and not targetGroupMap[idKey] then targetGroupMap[idKey] = t.group end
                    if baseKey ~= "" and not targetGroupMap[baseKey] then targetGroupMap[baseKey] = t.group end
                end
                if (t.npcID and tonumber(t.npcID) and tonumber(t.npcID) > 0) or (t.npcName and t.npcName ~= "") then
                    local tInfo = { npcID = tonumber(t.npcID) or 0, npcName = (t.npcName and t.npcName ~= "") and t.npcName or ns:ExtractBaseTargetName(t.name) }
                    if idKey and not targetNpcMap[idKey] then targetNpcMap[idKey] = tInfo end
                    if baseKey ~= "" and not targetNpcMap[baseKey] then targetNpcMap[baseKey] = tInfo end
                end
            end

            for _, t in ipairs(ns.db.teams) do
                local baseKey = strlower(ns:ExtractBaseTargetName((t.npcName and t.npcName ~= "") and t.npcName or t.name or ""))
                local idKey = (t.npcID and tonumber(t.npcID) and tonumber(t.npcID) > 0) and ("ID:" .. tostring(t.npcID)) or nil
                if t.group == "未分组队伍" then
                    local matchedGrp = (idKey and targetGroupMap[idKey]) or (baseKey ~= "" and targetGroupMap[baseKey])
                    if matchedGrp then
                        t.group = matchedGrp
                    end
                end
                local matchedNpc = (idKey and targetNpcMap[idKey]) or (baseKey ~= "" and targetNpcMap[baseKey])
                if matchedNpc then
                    if (not t.npcID or t.npcID == 0) and matchedNpc.npcID > 0 then
                        t.npcID = matchedNpc.npcID
                    end
                    if (not t.npcName or t.npcName == "") and matchedNpc.npcName ~= "" then
                        t.npcName = matchedNpc.npcName
                    end
                end
            end

            ns:MarkRoutesDirty()
        elseif arg1 == "Blizzard_Collections" then
            ns:SetupJournalHijack()
            if tabClickHooked then
                self:UnregisterEvent("ADDON_LOADED")
            end
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        ns:SetupJournalHijack()
        if C_AddOns.IsAddOnLoaded("Blizzard_Collections") and tabClickHooked then
            self:UnregisterEvent("ADDON_LOADED")
        end
        ns:CreateMinimapButton()
        if ns.SetupTooltipHook then ns:SetupTooltipHook() end
        if ns.SetupBattleEnemyBreedHUD then ns:SetupBattleEnemyBreedHUD() end
    elseif event == "PLAYER_LOGOUT" then
        if ns.staging and ns.staging.isDirty and ns.RestoreHomeTeamBackup then
            ns:RestoreHomeTeamBackup()
        end
        if WishRematchDB then
            if type(ns.queueFilterState) == "table" then
                WishRematchDB.queueFilterState = ns.queueFilterState
            end
            if type(ns.petFilterState) == "table" then
                WishRematchDB.petFilterState = ns.petFilterState
            end
        end
    end
end)

SlashCmdList["WISHREMATCH"] = function()
    ns:ToggleMainFrame()
end
SLASH_WISHREMATCH1 = "/wp"
SLASH_WISHREMATCH2 = "/wishrematch"
