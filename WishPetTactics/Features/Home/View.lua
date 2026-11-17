local ADDON_NAME, ns = ...
local Theme = ns.Theme

local function IsPetSpellTargeting()
    return SpellIsTargeting and SpellIsTargeting()
end

local function HandlePetSpellClick(button, petID)
    if not IsPetSpellTargeting() then return false end
    if button == "LeftButton" and petID then
        C_PetJournal.SpellTargetBattlePet(petID)
    end
    return true
end

local matrixSearchKw = ""
local EMPTY_USED_PETS = {}
local qualityPlainCache = {}

-- 静态背景颜色常量，消除 RefreshLoadoutCabin 每次刷新创建数十张临时颜色表
local CABIN_BG_DEAD     = { 0.16, 0.04, 0.05, 0.96 }
local CABIN_BG_LV       = { 0.077, 0.077, 0.077, 0.95 }
local CABIN_BG_MISSING  = { 0.12, 0.04, 0.06, 0.94 }
local CABIN_BG_UNDERLV  = { 0.13, 0.08, 0.02, 0.95 }
local CABIN_BG_FOCUSED  = { 0.09, 0.09, 0.09, 0.96 }
local CABIN_BG_NORMAL   = { 0.077, 0.077, 0.077, 0.92 }

local AB_BG_MISS_SEL    = { 0.20, 0.06, 0.08, 0.92 }
local AB_BG_MISS_UNSEL  = { 0.057, 0.057, 0.057, 0.80 }
local AB_BG_DEAD_SEL    = { 0.22, 0.06, 0.08, 0.94 }
local AB_BG_NORM_SEL    = { 0.153, 0.153, 0.153, 0.96 }
local AB_BG_NORM_UNSEL  = { 0.067, 0.067, 0.067, 0.85 }

-- 3 个出战槽位宠物数据复用池（单次调用同时提取 displayID，零重复表分配）
local cabinSlotPetPool = { {}, {}, {} }

local function PopulateCabinSlotPetData(slot, petID)
    if not petID or type(petID) ~= "string" then return nil end
    local speciesID, customName, level, xp, maxXp, displayID, isFavorite, name, icon, petType, _, sourceText, _, _, _, isTradable = C_PetJournal.GetPetInfoByPetID(petID)
    if not speciesID then return nil end

    local health, maxHealth, power, speed, rarity = C_PetJournal.GetPetStats(petID)
    health = health or 0
    maxHealth = (maxHealth and maxHealth > 0) and maxHealth or 100
    power = power or 0
    speed = speed or 0
    rarity = rarity or 1
    level = level or 1

    local isDead = (health <= 0)
    local hpPct = isDead and 0 or math.floor((health / maxHealth) * 100)
    local breed = ns.SearchFilter:GetPetBreed(petID, speciesID, maxHealth, power, speed, level, rarity)
    local fallbackName = name or ns:T("未知宠物")

    local d = cabinSlotPetPool[slot]
    d.petID       = petID
    d.speciesID   = speciesID
    d.displayID   = displayID or 0
    d.isCollected = true
    d.name        = (customName and customName ~= "" and customName) or fallbackName
    d.customName  = customName
    d.speciesName = fallbackName
    d.level       = level
    d.xp          = xp or 0
    d.maxXp       = (maxXp and maxXp > 0) and maxXp or 100
    d.isFavorite  = isFavorite and true or false
    d.icon        = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    d.petType     = petType or 1
    d.sourceText  = sourceText or ""
    d.isTradable  = isTradable and true or false
    d.health      = health
    d.maxHealth   = maxHealth
    d.hpPct       = hpPct
    d.isDead      = isDead
    d.isInjured   = (health < maxHealth)
    d.power       = power
    d.speed       = speed
    d.rarity      = rarity
    d.breed       = breed
    d.marker      = (ns.db and ns.db.petMarkers and ns.db.petMarkers[petID]) or nil
    d.note        = (ns.db and ns.db.petNotes and ns.db.petNotes[speciesID]) or nil
    return d
end

local function GetQualityPlainName(rarity)
    local cached = qualityPlainCache[rarity]
    if cached then return cached end
    local qCol = Theme.QualityColors[rarity] or Theme.QualityColors[4]
    local plain = string.gsub(qCol[4], "|c%x%x%x%x%x%x%x%x", "")
    plain = string.gsub(plain, "|r", "")
    qualityPlainCache[rarity] = plain
    return plain
end

local function SetModelDisplayCached(model, displayID)
    if not model then return end
    if displayID and displayID > 0 then
        if not model:IsShown() then
            model:Show()
            model._lastDisplayID = nil
        end
        if model._lastDisplayID ~= displayID then
            model._lastDisplayID = displayID
            model:SetDisplayInfo(displayID)
        end
    else
        model._lastDisplayID = nil
        model:Hide()
    end
end

local function SafeShowPetDetail(anchor, petData, isPinned)
    if not petData or not ns.ShowPetDetailTooltip then return end
    if ns.isReorderingQueueList then return end
    if isPinned and ns.PetCardModal then
        ns.PetCardModal.isPinned = false
    end
    ns:ShowPetDetailTooltip(anchor, petData, isPinned == true)
end

local function SafeHidePetDetail(force)
    if ns.HidePetDetailTooltip then
        ns:HidePetDetailTooltip(force == true)
    end
end

function ns:ApplyHealthBarColor(bar, hpPct, isDead)
    if isDead or hpPct <= 0 then
        bar:SetStatusBarColor(0.82, 0.12, 0.16, 0.92)
    elseif hpPct < 35 then
        bar:SetStatusBarColor(0.92, 0.22, 0.22, 0.95)
    elseif hpPct < 75 then
        bar:SetStatusBarColor(0.95, 0.62, 0.08, 0.95)
    else
        bar:SetStatusBarColor(0.06, 0.78, 0.50, 0.95)
    end
end

function ns:MarkHomeSlotChanged(slot)
    self.staging.changedSlots = self.staging.changedSlots or {}
    self.staging.changedSlots[slot] = true
end

function ns:SetHomeSlotThreshold(team, slot, value)
    if self:GetSlotThreshold(team, slot) == value then return end
    if team then
        self:EnsureTeamBackup()
        self.staging.isDirty = true
        self.staging.changedSlots = self.staging.changedSlots or {}
    end
    self:SetSlotThreshold(team, slot, value)
end

function ns:SaveStagingToCurrentTeam()
    local team = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
    if not team then return false end
    local inBattle = InCombatLockdown() or (C_PetBattles and C_PetBattles.IsInBattle())

    team.pets = team.pets or { nil, nil, nil }
    team.speciesLoadout = team.speciesLoadout or { 0, 0, 0 }
    team.abilities = team.abilities or { {0,0,0}, {0,0,0}, {0,0,0} }

    local lvSlot = team.levelingSlot or (ns.db and ns.db.settings.levelingSlot) or 2
    local changed = ns.staging.changedSlots or {}
    local queueActive = team.hasLevelingSlot and ns.Leveling:GetManualQueueCount() > 0
    for s = 1, 3 do
        if team.hasLevelingSlot and lvSlot == s then
            if not team.levelingFallback then ns.Leveling:CaptureSlotFallback(team, s, true) end
            if not queueActive and changed[s] and team.levelingFallback.petID then
                ns.Leveling:CaptureSlotFallback(team, s)
            end
            team.pets[s] = "LEVELING"
            team.speciesLoadout[s] = 0
        elseif changed[s] or not team.explicitSlots and not ns.staging.changedSlots then
            local pID, a1, a2, a3 = C_PetJournal.GetPetLoadOutInfo(s)
            if pID then
                local spID = C_PetJournal.GetPetInfoByPetID(pID) or 0
                team.pets[s] = pID
                team.speciesLoadout[s] = spID
                team.abilities[s] = ns.AutoRouting:ValidateAbilitiesForSpecies(spID, { a1 or 0, a2 or 0, a3 or 0 })
                ns.AutoRouting:RememberSlotSpeciesSkills(s, spID, team.abilities[s])
            else
                team.pets[s] = nil
                team.speciesLoadout[s] = 0
                team.abilities[s] = { 0, 0, 0 }
            end
        end
    end

    if ns.staging.manualAbilities then team.manualAbilities = true end
    ns.staging.isDirty = false
    ns.staging.teamBackup = nil
    ns.staging.backupTeamIdx = nil
    ns.staging.manualAbilities = nil
    ns.staging.changedSlots = nil
    ns.staging.backupSlotDefaults = nil
    ns.staging.backupLoadout = nil
    if team.hasLevelingSlot and not inBattle then ns.Leveling:AssignTopPetToLevelingSlot(lvSlot) end
    if ns.TeamMatrixModal then ns.TeamMatrixModal._treeDirty = true end
    if ns.RefreshAllUI then ns:RefreshAllUI() end
    if ns.ShowUIFeedback then ns:ShowUIFeedback(ns:UXText("saved")) end
    return true
end

function ns:RestoreHomeTeamBackup()
    local team = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
    if not team then return end
    if ns.staging and ns.staging.teamBackup and ns.staging.backupTeamIdx == ns.db.selectedTeamIdx then
        local b = ns.staging.teamBackup
        team.pets            = CopyTable(b.pets or { nil, nil, nil })
        team.speciesLoadout  = CopyTable(b.speciesLoadout or { 0, 0, 0 })
        team.abilities       = CopyTable(b.abilities or { {0,0,0}, {0,0,0}, {0,0,0} })
        team.randomSlots     = CopyTable(b.randomSlots or {})
        team.hasLevelingSlot = b.hasLevelingSlot and true or false
        team.levelingSlot    = b.levelingSlot or 2
        team.slotThresholds  = CopyTable(b.slotThresholds or { [1] = 0, [2] = 0, [3] = 0 })
        team.levelingFallback = b.levelingFallback and CopyTable(b.levelingFallback)
        ns.staging.revertLoadout = ns.staging.backupLoadout
        if ns.staging.backupSlotDefaults then
            ns.db.settings.levelingSlot = ns.staging.backupSlotDefaults.levelingSlot
            ns.db.defaultSlotThresholds = ns.staging.backupSlotDefaults.thresholds
        end
    end
    ns.staging.backupSlotDefaults = nil
    ns.staging.backupLoadout = nil
    ns.staging.manualAbilities = nil
    ns.staging.changedSlots = nil

    ns.staging.isDirty = false
    ns.staging.teamBackup = nil
    ns.staging.backupTeamIdx = nil
    if ns.TeamMatrixModal then ns.TeamMatrixModal._treeDirty = true end
    return team
end

function ns:RevertCurrentTeamToDefault()
    local team = self:RestoreHomeTeamBackup()
    if not team then return false end
    if not InCombatLockdown() and not (C_PetBattles and C_PetBattles.IsInBattle()) then
        ns.AutoRouting:ApplyTeamData(team)
    elseif ns.RefreshAllUI then
        ns:RefreshAllUI()
    end
    return true
end

-- 仅在首次脏改当前队伍槽位前执行单次快照，平时浏览与点击刷新零深拷贝
function ns:EnsureTeamBackup()
    local idx = ns.db and ns.db.selectedTeamIdx
    local team = idx and ns.db and ns.db.teams and ns.db.teams[idx]
    if team and (not ns.staging.isDirty or ns.staging.backupTeamIdx ~= idx or not ns.staging.teamBackup) then
        ns.staging.teamBackup = CopyTable(team)
        ns.staging.backupTeamIdx = idx
        local loadout = {}
        for slot = 1, 3 do
            local petID, a1, a2, a3 = C_PetJournal.GetPetLoadOutInfo(slot)
            loadout[slot] = {petID = petID, abilities = {a1 or 0, a2 or 0, a3 or 0}}
        end
        ns.staging.backupLoadout = loadout
        ns.staging.backupSlotDefaults = {
            levelingSlot = ns.db.settings.levelingSlot,
            thresholds = CopyTable(ns.db.defaultSlotThresholds or {}),
        }
    end
end

-- ==================== 1. 宠物与练级列表抽屉（支持自由拖拽排序 + 筛选持久化回填） ====================
function ns:UpdatePetDrawerAnchor()
    local pm = ns.PetPickerModal
    local f = ns.MainFrame
    if not pm or not f then return end

    pm:ClearAllPoints()
    if ns.TeamBuilderModal and ns.TeamBuilderModal:IsVisible() then
        pm:SetParent(ns.TeamBuilderModal)
        pm:SetPoint("TOPLEFT", ns.TeamBuilderModal, "TOPRIGHT", 6, 0)
        pm:SetHeight(620)
        pm:SetFrameStrata("FULLSCREEN_DIALOG")
        pm:SetFrameLevel((ns.TeamBuilderModal:GetFrameLevel() or 145) + 10)
    else
        pm:SetParent(f)
        pm:SetPoint("TOPLEFT", f, "TOPRIGHT", 6, 0)
        pm:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 6, 0)
        pm:SetFrameStrata("FULLSCREEN_DIALOG")
        pm:SetFrameLevel(130)
    end
end

local QUEUE_GHOST_BG = { 0.157, 0.157, 0.157, 0.96 }

local function EnsureQueueDragGhost()
    if ns.QueueDragGhost then return ns.QueueDragGhost end

    local ghost = CreateFrame("Frame", "WishPetTacticsQueueDragGhost", UIParent, "BackdropTemplate")
    ghost:SetSize(256, 44)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetFrameLevel(700)
    ghost:EnableMouse(false)
    Theme:ApplyBackdrop(ghost, QUEUE_GHOST_BG, Theme.Colors.borderBlue, false)
    ghost:Hide()

    ghost.icon = Theme:CreateCroppedIcon(ghost, 32)
    ghost.icon:SetPoint("LEFT", 7, 0)
    ghost.icon:EnableMouse(false)

    ghost.titleTxt = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ghost.titleTxt:SetPoint("TOPLEFT", ghost.icon, "TOPRIGHT", 8, -2)
    ghost.titleTxt:SetPoint("RIGHT", -8, 0)
    ghost.titleTxt:SetJustifyH("LEFT")
    ghost.titleTxt:SetWordWrap(false)
    Theme:HookLocalizedFontString(ghost.titleTxt)

    ghost.hintTxt = ghost:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ghost.hintTxt:SetPoint("BOTTOMLEFT", ghost.icon, "BOTTOMRIGHT", 8, 2)
    ghost.hintTxt:SetPoint("RIGHT", -8, 0)
    ghost.hintTxt:SetJustifyH("LEFT")
    ghost.hintTxt:SetWordWrap(false)
    Theme:HookLocalizedFontString(ghost.hintTxt)

    ns.QueueDragGhost = ghost
    return ghost
end

function ns:TogglePetPickerDrawer(targetSlot, defaultTab, fromHeaderBtn)
    local f = ns.MainFrame
    if not f then return end

    if targetSlot then
        ns.db.activeTargetSlot = targetSlot
    end

    local isBuilderOpen = (ns.TeamBuilderModal and ns.TeamBuilderModal:IsShown())
    if ns.PetPickerModal and ns.PetPickerModal:IsShown() and not isBuilderOpen then
        if fromHeaderBtn or ns.PetPickerModal.lastSlot == targetSlot then
            SafeHidePetDetail(true)
            ns.PetPickerModal:Hide()
            ns.PetPickerModal.lastSlot = nil
            if f.UpdatePetHubBtnState then f:UpdatePetHubBtnState() end
            return
        end
    end

    if not ns.PetPickerModal then
        local pm = CreateFrame("Frame", "WishPetTacticsPetPickerModal", f, "BackdropTemplate")
        pm:Hide() -- First Show must fire after the panel has finished construction.
        pm:SetSize(380, 620)
        pm:SetPoint("TOPLEFT", f, "TOPRIGHT", 6, 0)
        pm:SetFrameStrata("FULLSCREEN_DIALOG")
        pm:SetFrameLevel(130)
        pm:SetMovable(true)
        pm:SetClampedToScreen(true)
        pm:EnableMouse(true)
        pm:RegisterForDrag("LeftButton")
        pm:SetScript("OnDragStart", pm.StartMoving)
        pm:SetScript("OnDragStop", pm.StopMovingOrSizing)
        Theme:ApplyBackdrop(pm, Theme.Colors.bgPopup, Theme.Colors.border, true)
        pm.offset = 0
        pm.mode = (ns.db and ns.db.settings and ns.db.settings.lastPetDrawerTab) or "PETS"
        pm.selectedPetID = nil

        local title = pm:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 14, -14)
        Theme:HookLocalizedFontString(title)
        pm.title = title

        local closeBtn = Theme:CreateCloseIconButton(pm, function()
            SafeHidePetDetail(true)
            pm:Hide()
            pm.lastSlot = nil
        end)
        closeBtn:SetPoint("TOPRIGHT", -14, -14)

        local tabPets = Theme:CreateActionButton(pm, 108, 24, "宠物列表", "summon")
        tabPets:SetPoint("TOPLEFT", 14, -40)
        local tabQueue = Theme:CreateActionButton(pm, 108, 24, "练级队列", "queue")
        tabQueue:SetPoint("LEFT", tabPets, "RIGHT", 6, 0)
        local filterBtn = Theme:CreateActionButton(pm, 32, 24, "筛选", "filter", "筛选宠物或练级队列", nil, true)
        filterBtn:SetPoint("RIGHT", -14, 0)
        filterBtn:SetPoint("TOP", tabPets, "TOP", 0, 0)
        pm.filterBtn = filterBtn
        pm.petsTabButton, pm.queueTabButton = tabPets, tabQueue

        local searchBox = Theme:CreateFlatEditBox(pm, 352, 24, "搜索宠名 / 技能 / 拼音 / 备注...")
        searchBox:SetPoint("TOPLEFT", 14, -70)
        pm.searchBox = searchBox

        local listBox = CreateFrame("Frame", nil, pm, "BackdropTemplate")
        listBox:SetPoint("TOPLEFT", 14, -100)
        listBox:SetPoint("BOTTOMRIGHT", -14, 46)
        listBox:SetClipsChildren(true)
        listBox:EnableMouseWheel(true)
        Theme:ApplyBackdrop(listBox, Theme.Colors.bgInput, Theme.Colors.border, false)
        pm.listBox = listBox

        local scrollTrack = CreateFrame("Button", nil, listBox, "BackdropTemplate")
        scrollTrack:SetWidth(8)
        scrollTrack:SetPoint("TOPRIGHT", listBox, "TOPRIGHT", -4, -6)
        scrollTrack:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -4, 6)
        Theme:ApplyBackdrop(scrollTrack, Theme.Colors.bgPanel, Theme.Colors.border, false)
        scrollTrack:EnableMouse(true)
        pm.scrollTrack = scrollTrack

        local scrollThumb = CreateFrame("Button", nil, scrollTrack, "BackdropTemplate")
        scrollThumb:SetWidth(6)
        scrollThumb:SetHeight(44)
        scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -1)
        Theme:ApplyBackdrop(scrollThumb, Theme.Colors.btnPrimary, Theme.Colors.borderBlue, false)
        scrollThumb:RegisterForDrag("LeftButton")
        pm.scrollThumb = scrollThumb

        -- 练级队列拖拽高亮插入指示线
        local dropIndicator = CreateFrame("Frame", nil, listBox)
        dropIndicator:SetHeight(14)
        dropIndicator:SetPoint("LEFT", listBox, "LEFT", 6, 0)
        dropIndicator:SetPoint("RIGHT", listBox, "RIGHT", -16, 0)
        dropIndicator:SetFrameLevel(listBox:GetFrameLevel() + 25)
        dropIndicator:EnableMouse(false)
        dropIndicator:Hide()

        local glowTex = dropIndicator:CreateTexture(nil, "BACKGROUND")
        glowTex:SetHeight(9)
        glowTex:SetPoint("LEFT", 0, 0)
        glowTex:SetPoint("RIGHT", 0, 0)
        glowTex:SetTexture("Interface\\Buttons\\WHITE8X8")
        glowTex:SetVertexColor(0.00, 0.78, 1.00, 0.28)

        local coreLine = dropIndicator:CreateTexture(nil, "ARTWORK")
        coreLine:SetHeight(3)
        coreLine:SetPoint("LEFT", 0, 0)
        coreLine:SetPoint("RIGHT", 0, 0)
        coreLine:SetTexture("Interface\\Buttons\\WHITE8X8")
        coreLine:SetVertexColor(0.00, 0.96, 1.00, 1.00)
        Theme:SnapTextureToPixel(coreLine)

        local leftArr = Theme:CreateArrowTexture(dropIndicator, 12, "RIGHT")
        leftArr:SetPoint("LEFT", -3, 0)
        leftArr:SetVertexColor(1.00, 0.82, 0.00, 1.00)

        local rightArr = Theme:CreateArrowTexture(dropIndicator, 12, "LEFT")
        rightArr:SetPoint("RIGHT", 3, 0)
        rightArr:SetVertexColor(1.00, 0.82, 0.00, 1.00)

        local rankPill = CreateFrame("Frame", nil, dropIndicator, "BackdropTemplate")
        rankPill:SetSize(108, 18)
        rankPill:SetPoint("CENTER", 0, 0)
        rankPill:SetFrameLevel(dropIndicator:GetFrameLevel() + 2)
        Theme:ApplyBackdrop(rankPill, { 0.163, 0.163, 0.163, 0.98 }, Theme.Colors.borderBlue, false)
        rankPill.text = rankPill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rankPill.text:SetPoint("CENTER", 0, 0)
        Theme:HookLocalizedFontString(rankPill.text)
        dropIndicator.rankPill = rankPill

        pm.dropIndicator = dropIndicator

        local MAX_ROWS = 7
        local ROW_HEIGHT = 64
        local ROW_STEP = 66

        local function FinishQueueDrag()
            if not pm.draggingSourcePetID then return end
            local srcID = pm.draggingSourcePetID
            local dstID = pm.dragTargetPetID
            local insAfter = pm.dragInsertAfter
            local overList = listBox:IsVisible() and listBox:IsMouseOver()

            pm.draggingSourcePetID = nil
            pm._dragSourceIndex, pm._dragDataList, pm._dragDataRevision = nil, nil, nil
            pm._dragIndicatorRow, pm._dragIndicatorAfter = nil, nil
            pm._dragPreviewRank, pm._dragPreviewIsCurrent, pm._dragHintMode = nil, nil, nil
            pm.dragTargetPetID = nil
            pm.dragHoverRowIdx = nil
            pm.dragInsertAfter = false
            dropIndicator:Hide()

            if ns.QueueDragGhost then
                ns.QueueDragGhost:SetScript("OnUpdate", nil)
                ns.QueueDragGhost:Hide()
            end

            if overList then
                ns.isReorderingQueueList = false
                ns.draggingQueuePetID = nil
                ns.draggingPetID = nil
                ClearCursor()

                if srcID and dstID and srcID ~= dstID then
                    ns.Leveling:ReorderQueueByDrag(srcID, dstID, insAfter)
                    pm:Refresh()
                    ns:RefreshLoadoutCabin()
                else
                    pm:RenderRows()
                end
            else
                pm:RenderRows()
                C_Timer.After(0, function()
                    ns.isReorderingQueueList = false
                    ns.draggingQueuePetID = nil
                    ns.draggingPetID = nil
                    ns.queueDropHandledBySlot = false
                end)
            end
        end
        pm.FinishQueueDrag = FinishQueueDrag

        local autoScrollElapsed = 0
        local function UpdateQueueDragState(_, elapsed)
            if not pm.draggingSourcePetID or not IsMouseButtonDown("LeftButton") then
                FinishQueueDrag()
                return
            end

            local ghost = ns.QueueDragGhost
            local rawX, rawY = GetCursorPosition()
            if ghost then
                local gScale = ghost:GetEffectiveScale() or 1
                ghost:ClearAllPoints()
                ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (rawX / gScale) + 14, (rawY / gScale) - 10)
            end

            if listBox:IsVisible() and listBox:IsMouseOver() then
                local lScale = listBox:GetEffectiveScale() or 1
                local cy = rawY / lScale
                local boxTop = listBox:GetTop()
                local boxBottom = listBox:GetBottom()
                local totalItems = pm.totalDataCount or 0
                local maxOff = math.max(0, totalItems - MAX_ROWS)

                autoScrollElapsed = autoScrollElapsed + (elapsed or 0.016)
                if boxTop and (boxTop - cy) < 26 and pm.offset > 0 then
                    if autoScrollElapsed >= 0.13 then
                        autoScrollElapsed = 0
                        pm.offset = math.max(0, pm.offset - 1)
                        pm:RenderRows()
                    end
                elseif boxBottom and (cy - boxBottom) < 26 and pm.offset < maxOff then
                    if autoScrollElapsed >= 0.13 then
                        autoScrollElapsed = 0
                        pm.offset = math.min(maxOff, pm.offset + 1)
                        pm:RenderRows()
                    end
                else
                    autoScrollElapsed = 0.13
                end

                local matchedRowIdx = nil
                local insertAfter = false
                local lastValidRowIdx = nil

                for i = 1, MAX_ROWS do
                    local row = pm.rows[i]
                    if row:IsShown() and row.itemData then
                        lastValidRowIdx = i
                        local rTop = row:GetTop()
                        local rBot = row:GetBottom()
                        if rTop and rBot then
                            if i == 1 and cy > rTop then
                                matchedRowIdx = 1
                                insertAfter = false
                                break
                            elseif cy >= (rBot - 1) and cy <= (rTop + 1) then
                                matchedRowIdx = i
                                insertAfter = (cy < ((rTop + rBot) * 0.5))
                                break
                            end
                        end
                    end
                end

                if not matchedRowIdx and lastValidRowIdx then
                    matchedRowIdx = lastValidRowIdx
                    insertAfter = true
                end

                if matchedRowIdx then
                    local targetRow = pm.rows[matchedRowIdx]
                    local targetItem = targetRow and targetRow.itemData
                    pm.dragTargetPetID = targetItem and targetItem.petID or nil
                    pm.dragInsertAfter = insertAfter

                    if pm.dragHoverRowIdx ~= matchedRowIdx then
                        pm.dragHoverRowIdx = matchedRowIdx
                        pm:RenderRows()
                    end

                    local dstGlobalIdx = pm.offset + matchedRowIdx
                    local srcGlobalIdx = pm._dragSourceIndex
                    local dataList = pm.cachedDataList or {}
                    if pm._dragDataList ~= dataList or pm._dragDataRevision ~= pm._dataRevision
                        or (srcGlobalIdx and (not dataList[srcGlobalIdx] or dataList[srcGlobalIdx].petID ~= pm.draggingSourcePetID)) then
                        srcGlobalIdx = nil
                        for idx = 1, #dataList do
                            if dataList[idx] and dataList[idx].petID == pm.draggingSourcePetID then
                                srcGlobalIdx = idx
                                break
                            end
                        end
                        pm._dragSourceIndex, pm._dragDataList, pm._dragDataRevision = srcGlobalIdx, dataList, pm._dataRevision
                    end

                    local previewRank = dstGlobalIdx + (insertAfter and 1 or 0)
                    if srcGlobalIdx and srcGlobalIdx < previewRank then
                        previewRank = previewRank - 1
                    end
                    previewRank = math.max(1, math.min(math.max(1, #dataList), previewRank))

                    if pm._dragIndicatorRow ~= targetRow or pm._dragIndicatorAfter ~= insertAfter then
                        pm._dragIndicatorRow, pm._dragIndicatorAfter = targetRow, insertAfter
                        dropIndicator:ClearAllPoints()
                        dropIndicator:SetPoint("LEFT", listBox, "LEFT", 6, 0)
                        dropIndicator:SetPoint("RIGHT", listBox, "RIGHT", -16, 0)
                        if insertAfter then
                            dropIndicator:SetPoint("CENTER", targetRow, "BOTTOM", 0, -1)
                        else
                            dropIndicator:SetPoint("CENTER", targetRow, "TOP", 0, 1)
                        end
                    end

                    local isCurrent = pm.dragTargetPetID == pm.draggingSourcePetID or (srcGlobalIdx and previewRank == srcGlobalIdx) or false
                    if pm._dragPreviewRank ~= previewRank or pm._dragPreviewIsCurrent ~= isCurrent or pm._dragHintMode ~= "LIST" then
                        pm._dragPreviewRank, pm._dragPreviewIsCurrent, pm._dragHintMode = previewRank, isCurrent, "LIST"
                        if isCurrent then
                            dropIndicator.rankPill.text:SetText(ns:TF("|cff9ca3af当前第 %d 位|r", previewRank))
                            if ghost then
                                ghost.hintTxt:SetText(ns:TF("|cff9ca3af继续上下拖动可调整队列顺位 (#%d)|r", previewRank))
                            end
                        else
                            dropIndicator.rankPill.text:SetText(ns:TF("|cff00f2fe▶ 移至第 %d 位 ◀|r", previewRank))
                            if ghost then
                                ghost.hintTxt:SetText(ns:TF("|cff00f2fe松开鼠标：调整至练级队列第 %d 位|r", previewRank))
                            end
                        end
                    end
                    dropIndicator:Show()
                else
                    dropIndicator:Hide()
                end
            else
                if pm.dragHoverRowIdx ~= nil then
                    pm.dragHoverRowIdx = nil
                    pm:RenderRows()
                end
                pm.dragTargetPetID = nil
                dropIndicator:Hide()

                if ghost then
                    local overSlot = false
                    if ns.TeamBuilderModal and ns.TeamBuilderModal:IsShown() and ns.TeamBuilderModal.slots then
                        for s = 1, 3 do
                            if ns.TeamBuilderModal.slots[s] and ns.TeamBuilderModal.slots[s]:IsMouseOver() then
                                overSlot = true
                                break
                            end
                        end
                    end
                    if not overSlot and f.loadoutCards then
                        for s = 1, 3 do
                            if f.loadoutCards[s] and f.loadoutCards[s]:IsVisible() and f.loadoutCards[s]:IsMouseOver() then
                                overSlot = true
                                break
                            end
                        end
                    end
                    local hintMode = overSlot and "SLOT" or "OUTSIDE"
                    if pm._dragHintMode ~= hintMode then
                        pm._dragHintMode = hintMode
                        if overSlot then
                            ghost.hintTxt:SetText(ns:T("|cff10b981松开鼠标：挂载至该槽位并开启代练|r"))
                        else
                            ghost.hintTxt:SetText(ns:T("|cff9ca3af上下拖动调整顺位 · 拖入左侧槽位上阵|r"))
                        end
                    end
                end
            end
        end

        listBox:SetScript("OnMouseWheel", function(_, delta)
            local maxOff = math.max(0, (pm.totalDataCount or 0) - MAX_ROWS)
            local nextOff = math.max(0, math.min(maxOff, pm.offset - delta * 2))
            if nextOff ~= pm.offset then
                pm.offset = nextOff
                pm:RenderRows()
            end
        end)

        pm.rows = {}
        local gripBg = { 0.103, 0.103, 0.103, 0.85 }
        for i = 1, MAX_ROWS do
            local r = Theme:CreateMenuRow(listBox, 326, ROW_HEIGHT, "")
            r:SetPoint("TOPLEFT", 6, -6 - (i - 1) * ROW_STEP)
            r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            r:RegisterForDrag("LeftButton")
            r.rowSlotIdx = i

            local gripBox = CreateFrame("Frame", nil, r, "BackdropTemplate")
            gripBox:SetSize(24, 52)
            gripBox:SetPoint("LEFT", 4, 0)
            gripBox:EnableMouse(false)
            Theme:ApplyBackdrop(gripBox, gripBg, Theme.Colors.border, false)

            gripBox.gripSym = gripBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            gripBox.gripSym:SetPoint("TOP", 0, -5)
            gripBox.gripSym:SetText("|cff38bdf8≡|r")

            gripBox.rankTxt = gripBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            gripBox.rankTxt:SetPoint("BOTTOM", 0, 5)
            local gFont = gripBox.rankTxt:GetFont()
            if gFont then gripBox.rankTxt:SetFont(gFont, 10, "OUTLINE") end
            gripBox:Hide()
            r.gripBox = gripBox

            r.icon = Theme:CreateCroppedIcon(r, 46)
            r.icon:SetPoint("LEFT", 8, 0)
            r.icon:EnableMouse(false)

            r.text:ClearAllPoints()
            r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, -6)
            r.text:SetPoint("RIGHT", -60, 0)
            r.text:SetJustifyH("LEFT")
            r.text:SetWordWrap(false)

            r.subText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.subText:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 10, 6)
            r.subText:SetPoint("RIGHT", -60, 0)
            r.subText:SetJustifyH("LEFT")
            r.subText:SetWordWrap(false)
            Theme:HookLocalizedFontString(r.subText)

            r.typeIcon = Theme:CreatePetListTypeTexture(r, 48)
            r.typeIcon:SetPoint("RIGHT", -6, 0)

            r:SetScript("OnEnter", function(rowBtn)
                local item = rowBtn.itemData
                if not item then return end
                if pm.draggingSourcePetID then return end
                rowBtn._isHovered = true
                if rowBtn._UpdateUnderline then rowBtn:_UpdateUnderline() end
                if rowBtn.underline then
                    rowBtn.underline:SetVertexColor(0.22, 0.88, 1.0, 0.95)
                    rowBtn.underline:Show()
                end
                SafeShowPetDetail(rowBtn, item, false)
            end)
            r:SetScript("OnLeave", function(rowBtn)
                if pm.draggingSourcePetID then return end
                rowBtn._isHovered = false
                if rowBtn.isSelected then
                    if rowBtn._UpdateUnderline then rowBtn:_UpdateUnderline() end
                    if rowBtn.underline then
                        rowBtn.underline:SetVertexColor(0.00, 0.92, 1.00, 1.0)
                        rowBtn.underline:Show()
                    end
                elseif rowBtn.underline then
                    rowBtn.underline:Hide()
                end
                SafeHidePetDetail(false)
            end)
            r:SetScript("OnClick", function(rowBtn, button)
                local item = rowBtn.itemData
                if not item then return end
                if IsPetSpellTargeting() then
                    rowBtn.lastSpellTargetClick = GetTime()
                    HandlePetSpellClick(button, item.isCollected and item.petID)
                    return
                end
                if button == "RightButton" then
                    ns:ShowPetContextMenu(rowBtn, item)
                else
                    pm.selectedPetID = item.petID
                    pm:RenderRows()
                end
            end)
            r:SetScript("OnDoubleClick", function(rowBtn)
                if IsPetSpellTargeting() or (rowBtn.lastSpellTargetClick and GetTime() - rowBtn.lastSpellTargetClick < 0.5) then return end
                local item = rowBtn.itemData
                if not item or not item.petID then return end
                pm.selectedPetID = item.petID
                if ns.TeamBuilderModal and ns.TeamBuilderModal:IsShown() and ns.TeamBuilderModal.AssignPetToSlot then
                    local targetSlotIdx = (ns.TeamBuilderModal.builderState and ns.TeamBuilderModal.builderState.activeSlot) or pm.lastSlot or 1
                    if pm.mode == "QUEUE" then
                        ns.draggingQueuePetID = item.petID
                    else
                        ns.draggingQueuePetID = nil
                    end
                    ns.TeamBuilderModal:AssignPetToSlot(targetSlotIdx, item.petID)
                    if ns.TeamBuilderModal.builderState then
                        for nextS = 1, 3 do
                            local st = ns.TeamBuilderModal.builderState.slots[nextS]
                            if st and not st.isLeveling and (not st.speciesID or st.speciesID == 0) then
                                ns.TeamBuilderModal.builderState.activeSlot = nextS
                                pm.lastSlot = nextS
                                ns.TeamBuilderModal:RefreshBuilder()
                                break
                            end
                        end
                    end
                elseif pm.mode == "PETS" and not ns.db.activeTargetSlot then
                    if item.isCollected and not InCombatLockdown() and not (C_PetBattles and C_PetBattles.IsInBattle()) then
                        C_PetJournal.SummonPetByGUID(item.petID)
                    end
                else
                    local slotIdx = ns.db.activeTargetSlot or pm.lastSlot or 1
                    if pm.mode == "QUEUE" then
                        ns.draggingQueuePetID = item.petID
                    else
                        ns.draggingQueuePetID = nil
                    end
                    ns:DropPetIntoSlot(slotIdx, item.petID)
                    ns:RefreshLoadoutCabin()
                end
            end)
            r:SetScript("OnDragStart", function(rowBtn)
                if IsPetSpellTargeting() then return end
                local item = rowBtn.itemData
                SafeHidePetDetail(true)
                if not item or not item.petID then return end
                pm.selectedPetID = item.petID

                if pm.mode == "QUEUE" then
                    pm.draggingSourcePetID = item.petID
                    pm._dragSourceIndex = pm.offset + rowBtn.rowSlotIdx
                    pm._dragDataList, pm._dragDataRevision = pm.cachedDataList, pm._dataRevision
                    pm._dragIndicatorRow, pm._dragIndicatorAfter = nil, nil
                    pm._dragPreviewRank, pm._dragPreviewIsCurrent, pm._dragHintMode = nil, nil, nil
                    pm.dragTargetPetID = item.petID
                    pm.dragHoverRowIdx = rowBtn.rowSlotIdx
                    pm.dragInsertAfter = false
                    ns.isReorderingQueueList = true
                    ns.queueDropHandledBySlot = false
                    ns.draggingQueuePetID = item.petID
                    ns.draggingPetID = item.petID
                    autoScrollElapsed = 0.13

                    local ghost = EnsureQueueDragGhost()
                    ghost.icon.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    local qCol = Theme.QualityColors[item.rarity] or Theme.QualityColors[4]
                    ghost.icon:SetBackdropBorderColor(qCol[1], qCol[2], qCol[3], 1)
                    ghost.titleTxt:SetText(ns:TF("|cff00f2fe[拖动排序]|r |cffffd100Lv.%d|r |cffffffff%s|r", item.level or 1, item.name or ""))
                    ghost.hintTxt:SetText(ns:T("|cff00f2fe上下拖动调整顺位 · 拖至左侧槽位上阵|r"))
                    ghost:SetScript("OnUpdate", UpdateQueueDragState)
                    ghost:Show()
                    UpdateQueueDragState(ghost, 0)
                    pm:RenderRows()
                else
                    ns.isReorderingQueueList = false
                    ns.draggingPetID = item.petID
                    ns.draggingQueuePetID = nil
                    C_PetJournal.PickupPet(item.petID)
                end
            end)
            r:SetScript("OnDragStop", function()
                if pm.draggingSourcePetID then
                    FinishQueueDrag()
                end
            end)

            pm.rows[i] = r
        end

        pm:HookScript("OnShow", function()
            if f.UpdatePetHubBtnState then f:UpdatePetHubBtnState() end
        end)
        pm:HookScript("OnHide", function()
            if pm.draggingSourcePetID then
                FinishQueueDrag()
            end
            if f.UpdatePetHubBtnState then f:UpdatePetHubBtnState() end
        end)

        local function SyncDrawerScrollThumb(totalItems)
            local maxOff = math.max(0, totalItems - MAX_ROWS)
            local trackH = scrollTrack:GetHeight()
            if not trackH or trackH <= 0 then trackH = 460 end
            local thumbH, yOff, alpha
            if maxOff <= 0 then
                thumbH = math.max(28, trackH - 2)
                yOff = -1
                alpha = 0.30
            else
                thumbH = math.max(28, math.floor((MAX_ROWS / totalItems) * (trackH - 2)))
                local availMove = math.max(1, (trackH - 2) - thumbH)
                local ratio = math.max(0, math.min(1, pm.offset / maxOff))
                yOff = -1 - math.floor(ratio * availMove)
                alpha = 1.0
            end
            if scrollThumb._lastH ~= thumbH then
                scrollThumb._lastH = thumbH
                scrollThumb:SetHeight(thumbH)
            end
            if scrollThumb._lastY ~= yOff then
                scrollThumb._lastY = yOff
                scrollThumb:ClearAllPoints()
                scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, yOff)
            end
            if scrollThumb._lastA ~= alpha then
                scrollThumb._lastA = alpha
                scrollThumb:SetAlpha(alpha)
            end
        end

        local function UpdateDrawerScrollFromCursor()
            if not IsMouseButtonDown("LeftButton") then
                scrollThumb:SetScript("OnUpdate", nil)
                return
            end
            local totalItems = pm.totalDataCount or 0
            local maxOff = math.max(0, totalItems - MAX_ROWS)
            if maxOff <= 0 then return end
            local trackTop = scrollTrack:GetTop()
            local trackH = scrollTrack:GetHeight()
            local thumbH = scrollThumb:GetHeight()
            local _, rawY = GetCursorPosition()
            local cy = rawY / scrollTrack:GetEffectiveScale()
            if trackTop and trackH and (trackH - thumbH) > 0 then
                local grab = scrollThumb.grabOffset or (thumbH / 2)
                local ratio = ((trackTop - cy) - grab) / (trackH - thumbH)
                ratio = math.max(0, math.min(1, ratio))
                local newOff = math.floor(ratio * maxOff + 0.5)
                if newOff ~= pm.offset then
                    pm.offset = newOff
                    pm:RenderRows()
                end
            end
        end

        scrollThumb:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                local _, rawY = GetCursorPosition()
                local cy = rawY / self:GetEffectiveScale()
                local top = self:GetTop() or cy
                self.grabOffset = math.max(2, math.min(self:GetHeight() - 2, top - cy))
                self:SetScript("OnUpdate", UpdateDrawerScrollFromCursor)
            end
        end)
        scrollThumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
        scrollThumb:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", UpdateDrawerScrollFromCursor) end)
        scrollThumb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
        scrollThumb:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

        scrollTrack:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then
                scrollThumb.grabOffset = scrollThumb:GetHeight() / 2
                UpdateDrawerScrollFromCursor()
            end
        end)

        local btnW = 83
        local btnGap = 6
        local summonBtn = Theme:CreateActionButton(pm, btnW, 26, "召唤", "summon")
        summonBtn:SetPoint("BOTTOMLEFT", 14, 12)
        summonBtn:SetScript("OnClick", function()
            local pid = pm.selectedPetID
            if not pid then
                local slot = ns.db.activeTargetSlot or 1
                pid = C_PetJournal.GetPetLoadOutInfo(slot)
            end
            if pid and C_PetJournal.GetSummonedPetGUID() ~= pid then
                C_PetJournal.SummonPetByGUID(pid)
            end
        end)
        pm.summonBtn = summonBtn

        local dismissBtn = Theme:CreateActionButton(pm, btnW, 26, "解散", "dismiss")
        dismissBtn:SetPoint("LEFT", summonBtn, "RIGHT", btnGap, 0)
        dismissBtn:SetScript("OnClick", function()
            local curSummoned = C_PetJournal.GetSummonedPetGUID()
            if curSummoned then
                C_PetJournal.SummonPetByGUID(curSummoned)
            end
        end)
        pm.dismissBtn = dismissBtn

        function pm:RefreshDirtyHeader()
            local isDirty = (ns.staging and ns.staging.isDirty) and true or false
            if self.mode == "QUEUE" then
                self.title:SetText(isDirty and "|cff38bdf8练级自动队列|r |cffffb800(上下拖动调序 · 未保存)|r" or "|cff38bdf8练级自动队列|r |cff9ca3af(直接按住上下拖动调序)|r")
            else
                self.title:SetText(isDirty and "|cff38bdf8宠物与练级队列|r |cffffb800(双击/拖动 · 未保存)|r" or "|cff38bdf8宠物与练级队列|r |cff9ca3af(双击或拖动上阵)|r")
            end
        end

        function pm:SyncFilterControls()
            local qTbl = (ns.db and ns.db.queueFilterState) or ns.queueFilterState
            local pTbl = (ns.db and ns.db.petFilterState) or ns.petFilterState
            local wantKw = (self.mode == "QUEUE") and (qTbl and qTbl.keyword or "") or (pTbl and pTbl.keyword or "")
            if not self.searchBox:HasFocus() and (self.searchBox:GetText() or "") ~= wantKw then
                self._suppressSearch = true
                self.searchBox:SetText(wantKw)
                self._suppressSearch = false
            end

            local hasActiveFilter = false
            if self.mode == "QUEUE" and ns.SearchFilter.IsQueueFilterActive then
                hasActiveFilter = ns.SearchFilter:IsQueueFilterActive()
            elseif self.mode == "PETS" and ns.SearchFilter.IsPetFilterActive then
                hasActiveFilter = ns.SearchFilter:IsPetFilterActive()
            end
            self.filterBtn:SetSelected(hasActiveFilter)
            self.filterBtn:SetActionMarked(hasActiveFilter)
        end

        function pm:RenderRows()
            local dataList = self.cachedDataList or {}
            self.totalDataCount = #dataList
            local maxOff = math.max(0, #dataList - MAX_ROWS)
            if self.offset > maxOff then self.offset = maxOff end

            SyncDrawerScrollThumb(#dataList)
            local isQueueMode = (self.mode == "QUEUE")

            for i = 1, MAX_ROWS do
                local r = self.rows[i]
                local globalIdx = self.offset + i
                local item = dataList[globalIdx]
                r.itemData = item
                if item then
                    r:Show()

                    if isQueueMode then
                        if r._lastIconX ~= 32 then
                            r._lastIconX = 32
                            r.icon:ClearAllPoints()
                            r.icon:SetPoint("LEFT", 32, 0)
                        end
                        r.gripBox:Show()
                        local rankColor = (globalIdx == 1) and "|cff10b981" or "|cffffd100"
                        r.gripBox.rankTxt:SetText(rankColor .. globalIdx .. "|r")
                        if globalIdx == 1 then
                            r.gripBox:SetBackdropBorderColor(unpack(Theme.Colors.borderGreen))
                        else
                            r.gripBox:SetBackdropBorderColor(unpack(Theme.Colors.border))
                        end
                    else
                        if r._lastIconX ~= 8 then
                            r._lastIconX = 8
                            r.icon:ClearAllPoints()
                            r.icon:SetPoint("LEFT", 8, 0)
                        end
                        r.gripBox:Hide()
                    end

                    if r._lastTex ~= item.icon then
                        r._lastTex = item.icon
                        r.icon.icon:SetTexture(item.icon)
                    end
                    r.icon.icon:SetDesaturated(item.isDead or not item.isCollected)
                    local qCol = Theme.QualityColors[item.rarity] or Theme.QualityColors[4]
                    r.icon:SetBackdropBorderColor(qCol[1], qCol[2], qCol[3], 1)

                    local isDragSrc = (isQueueMode and self.draggingSourcePetID ~= nil and item.petID == self.draggingSourcePetID)
                    local isDragHov = (isQueueMode and self.draggingSourcePetID ~= nil and self.dragHoverRowIdx == i and not isDragSrc)

                    local dragTag = isDragSrc and "|cffffb800[拖动中]|r " or ""
                    local favStr = ""
                    local lvStr = item.isCollected and string.format("|cffffd100%d|r ", item.level or 1) or ""
                    local deadStr = item.isDead and " |cffff4040[阵亡]|r" or (not item.isCollected and " |cffff4040[未收集]|r" or "")
                    r.text:SetText(string.format("%s%s%s|cfff3f4f6%s|r%s", dragTag, favStr, lvStr, item.name or ns:T("未知宠物"), deadStr))

                    if r.subText then
                        if item.isCollected then
                            local breedTag = item.breed and string.format("|cff38bdf8[%s]|r ", item.breed) or ""
                            local hpTag = item.isDead and "|cffff4040生命: 0%|r" or ns:TF("|cff10b981生命:%d%%|r", item.hpPct or 100)
                            local statTag = ns:TF("|cff9ca3af攻:%d 速:%d|r  ", item.power or 0, item.speed or 0)
                            r.subText:SetText(breedTag .. statTag .. hpTag)
                        else
                            r.subText:SetText(ns:T("|cff6b7280未收集该宠物|r"))
                        end
                    end

                    if isDragSrc then
                        r:SetAlpha(0.45)
                        r:SetSelected(false)
                    else
                        r:SetAlpha(1.0)
                        if isDragHov then
                            r:SetSelected(true)
                        else
                            r:SetSelected(self.selectedPetID ~= nil and self.selectedPetID == item.petID)
                        end
                    end

                    Theme:SetPetListTypeTexture(r.typeIcon, item.petType or 1)
                else
                    r:SetAlpha(1.0)
                    r:Hide()
                end
            end
        end

        local drawerSearchTimer = nil

        function pm:Refresh(healthOnly)
            -- 高级宠物抽屉也遵守「队列空时隐藏」的统一规则。
            local manualCount = ns.Leveling:GetManualQueueCount()
            if manualCount == 0 and self.mode == "QUEUE" then self.mode = "PETS" end
            tabQueue:SetShown(manualCount > 0)
            self:RefreshDirtyHeader()
            self:SyncFilterControls()
            tabPets:SetSelected(self.mode == "PETS")
            tabQueue:SetSelected(self.mode == "QUEUE")

            local provider = (self.mode == "QUEUE") and ns.Leveling or ns.SearchFilter
            local canRefreshHealth = healthOnly and not drawerSearchTimer
                and self.petJournalRevision == ns._petJournalRevision
            if not (canRefreshHealth and provider:RefreshResultHealth(self.cachedDataList)) then
                self.cachedDataList = (self.mode == "QUEUE") and ns.Leveling:GetQueue() or ns.SearchFilter:GetFilteredPets()
                self.petJournalRevision = ns._petJournalRevision
            end
            self._dataRevision = (self._dataRevision or 0) + 1
            self:RenderRows()
        end

        local function CancelDrawerSearchTimer()
            if drawerSearchTimer then
                drawerSearchTimer:Cancel()
                drawerSearchTimer = nil
            end
        end

        tabPets:SetScript("OnClick", function()
            CancelDrawerSearchTimer()
            if pm.draggingSourcePetID then FinishQueueDrag() end
            SafeHidePetDetail(true)
            pm.mode = "PETS"
            if ns.db and ns.db.settings then ns.db.settings.lastPetDrawerTab = "PETS" end
            pm.offset = 0
            pm:Refresh()
        end)
        tabQueue:SetScript("OnClick", function()
            CancelDrawerSearchTimer()
            if pm.draggingSourcePetID then FinishQueueDrag() end
            SafeHidePetDetail(true)
            pm.mode = "QUEUE"
            if ns.db and ns.db.settings then ns.db.settings.lastPetDrawerTab = "QUEUE" end
            pm.offset = 0
            pm:Refresh()
        end)
        filterBtn:SetScript("OnClick", function(btn)
            if pm.mode == "QUEUE" then
                ns:ToggleQueueFilterMenu(btn)
            else
                ns:TogglePetFilterMenu(btn)
            end
        end)
        local function ApplyDrawerSearch(kw, immediate)
            if pm.mode == "QUEUE" then
                if ns.db and ns.db.queueFilterState then ns.db.queueFilterState.keyword = kw end
                ns.queueFilterState.keyword = kw
            else
                if ns.db and ns.db.petFilterState then ns.db.petFilterState.keyword = kw end
                ns.petFilterState.keyword = kw
            end
            pm.offset = 0
            CancelDrawerSearchTimer()
            pm:SyncFilterControls()
            if immediate then
                if pm:IsShown() then pm:Refresh() end
            else
                drawerSearchTimer = C_Timer.NewTimer(0.15, function()
                    drawerSearchTimer = nil
                    if pm:IsShown() then pm:Refresh() end
                end)
            end
        end
        searchBox:SetScript("OnTextChanged", function(self, userInput)
            if pm._suppressSearch or self._clearingSearch then return end
            if userInput then ApplyDrawerSearch(self:GetText() or "", false) end
        end)
        Theme:EnableSearchClearButton(searchBox, function() ApplyDrawerSearch("", true) end)

        ns.PetPickerModal = pm
        ns:BindHeaderHubPanel(pm)
    end

    local pm = ns.PetPickerModal
    pm.lastSlot = targetSlot
    if defaultTab then
        pm.mode = defaultTab
        if ns.db and ns.db.settings then
            ns.db.settings.lastPetDrawerTab = defaultTab
        end
    elseif ns.db and ns.db.settings and ns.db.settings.lastPetDrawerTab then
        pm.mode = ns.db.settings.lastPetDrawerTab
    end
    self:UpdatePetDrawerAnchor()
    pm:Refresh()
    pm:Show()
    if f.UpdatePetHubBtnState then f:UpdatePetHubBtnState() end
end

-- O(1) 极速读取列表槽位图标与系别水印（直接解包 packedPet 整数缓存，零 API 调用）
local function GetTeamSlotIconFast(team, slot, isCurrentTeam)
    local lvSlot = team.levelingSlot or (ns.db and ns.db.settings.levelingSlot) or 2
    if (team.hasLevelingSlot and lvSlot == slot) or (team.pets and team.pets[s or slot] == "LEVELING") then
        return true, "Interface\\Icons\\INV_Pet_Achievement_RaiseAPetLevel_25", nil, false
    end

    if team.randomSlots and team.randomSlots[slot] ~= nil then
        local rType = team.randomSlots[slot] or 0
        local ptInfo = (rType > 0) and Theme.PetTypes[rType] or nil
        local icon = (ptInfo and ptInfo.icon) or "Interface\\Icons\\INV_Misc_Dice_02"
        return false, icon, (rType > 0 and rType or nil), false
    end

    local targetSpID = (team.speciesLoadout and tonumber(team.speciesLoadout[slot])) or 0
    local petID = team.pets and team.pets[slot]

    if isCurrentTeam and (not petID or petID == "LEVELING") and targetSpID == 0 then
        petID = C_PetJournal.GetPetLoadOutInfo(slot)
    end

    if targetSpID == 0 and petID and type(petID) == "string" and petID ~= "LEVELING" then
        local cache = ns.GetPetJournalCache and ns:GetPetJournalCache() or nil
        local packed = cache and cache.packedPet and cache.packedPet[petID]
        if packed then
            targetSpID = (packed - (packed % 64)) / 64
        else
            targetSpID = C_PetJournal.GetPetInfoByPetID(petID) or 0
        end
    end

    if targetSpID > 0 then
        local isOwned = ns:IsSpeciesCollected(targetSpID)
        local meta = ns.GetSpeciesMeta and ns:GetSpeciesMeta(targetSpID)
        if meta then
            return false, meta.icon, meta.petType, (not isOwned)
        end
    end

    return false, nil, nil, false
end

-- 仅在鼠标悬停或点击宠物小图标时按需生成完整 3D 详情卡数据
local function GetTeamSlotPetData(team, slot, isCurrentTeam)
    local lvSlot = team.levelingSlot or (ns.db and ns.db.settings.levelingSlot) or 2
    if (team.hasLevelingSlot and lvSlot == slot) or (team.pets and team.pets[slot] == "LEVELING") then
        return true, "Interface\\Icons\\INV_Pet_Achievement_RaiseAPetLevel_25", nil, nil, false
    end

    if team.randomSlots and team.randomSlots[slot] ~= nil then
        local rType = team.randomSlots[slot] or 0
        local ptInfo = (rType > 0) and Theme.PetTypes[rType] or nil
        local icon = (ptInfo and ptInfo.icon) or "Interface\\Icons\\INV_Misc_Dice_02"
        local rndName
        if ptInfo then
            if ns.locale == "zhTW" then
                rndName = "隨機" .. ptInfo.name .. "系寵物"
            elseif ns.locale ~= "zhCN" then
                rndName = "Random " .. ptInfo.name .. " Pet"
            else
                rndName = "随机" .. ptInfo.name .. "系宠物"
            end
        else
            rndName = (ns.locale == "zhTW" and "任意滿級隨機寵物") or (ns.locale ~= "zhCN" and "Any Lv 25 Random Pet") or "任意满级随机宠物"
        end
        return false, icon, rType > 0 and rType or nil, {
            speciesID   = 0,
            name        = rndName,
            level       = 25,
            rarity      = 4,
            petType     = (rType > 0) and rType or 1,
            icon        = icon,
            breed       = ns:T("随机补位"),
            isCollected = true,
            health      = 1400,
            maxHealth   = 1400,
            power       = 280,
            speed       = 280,
        }, false
    end

    local targetSpID = (team.speciesLoadout and tonumber(team.speciesLoadout[slot])) or 0
    local petID = team.pets and team.pets[slot]

    if isCurrentTeam and (not petID or petID == "LEVELING") and targetSpID == 0 then
        petID = C_PetJournal.GetPetLoadOutInfo(slot)
    end

    if petID and type(petID) == "string" and petID ~= "LEVELING" then
        local pData = ns.SearchFilter:GetFullPetData(petID)
        if pData and (targetSpID == 0 or pData.speciesID == targetSpID) then
            return false, pData.icon, pData.petType, pData, false
        end
    end

    if targetSpID > 0 then
        local isOwned = ns:IsSpeciesCollected(targetSpID)
        if isOwned and ns.AutoRouting and ns.AutoRouting.FindAnyCollectedPetForSpecies then
            local bestPetID = ns.AutoRouting:FindAnyCollectedPetForSpecies(targetSpID, EMPTY_USED_PETS)
            if bestPetID then
                local pData = ns.SearchFilter:GetFullPetData(bestPetID)
                if pData then
                    return false, pData.icon, pData.petType, pData, false
                end
            end
        end

        local spName, icon, petType, _, sourceText = C_PetJournal.GetPetInfoBySpeciesID(targetSpID)
        if icon then
            return false, icon, petType, {
                speciesID   = targetSpID,
                isCollected = isOwned,
                name        = spName or (ns:T("未知宠物") .. " #" .. targetSpID),
                level       = 25,
                rarity      = isOwned and 4 or 1,
                petType     = petType or 1,
                icon        = icon,
                breed       = isOwned and ns:T("已收集") or ns:T("未收集"),
                health      = isOwned and 1400 or 0,
                maxHealth   = 1400,
                power       = 280,
                speed       = 280,
                note        = (not isOwned and sourceText and sourceText ~= "") and string.gsub(sourceText, "\n", " ") or nil,
            }, (not isOwned)
        end
    end

    return false, nil, nil, nil, false
end

-- ==================== 2. 队伍管理矩阵视窗（零闭包虚拟滚动 + 脏标记短路免重算） ====================
function ns:ShowTeamMatrixModal()
    local f = self:CreateMainFrame()
    if self.HideAllPopups then self:HideAllPopups() end

    ns.db.expandedMatrixGroups  = ns.db.expandedMatrixGroups  or {}
    ns.db.expandedMatrixTargets = ns.db.expandedMatrixTargets or {}

    if not ns.TeamMatrixModal then
        local px = Theme:GetPixelScale()
        local m = CreateFrame("Frame", "WishPetTacticsTeamMatrixModal", f, "BackdropTemplate")
        m:Hide()
        m:SetSize(760, 540)
        m:SetPoint("CENTER", f, "CENTER", 0, -6)
        m:SetFrameStrata("DIALOG")
        m:SetFrameLevel(60)
        m:SetMovable(true)
        m:SetClampedToScreen(true)
        m:EnableMouse(true)
        m:EnableMouseWheel(true)
        m:RegisterForDrag("LeftButton")
        m:SetScript("OnDragStart", m.StartMoving)
        m:SetScript("OnDragStop", m.StopMovingOrSizing)
        Theme:ApplyBackdrop(m, { 0.07, 0.07, 0.07, 0.98 }, Theme.Colors.border, true)
        if ns.MakeModal then ns:MakeModal(m) end
        m.offset = 0
        m._treeDirty = true
        m._lastBuiltKw = nil

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 24, -20)
        Theme:HookLocalizedFontString(title)
        title:SetText(ns:T("|cff38bdf8TEAM MANAGEMENT // 全局队伍分级管理 (分组 / 目标 / 队伍)|r"))

        local closeBtn = Theme:CreateCloseIconButton(m, function()
            SafeHidePetDetail(true)
            m:Hide()
        end)
        closeBtn:SetPoint("TOPRIGHT", -22, -20)

        local hdrLine = m:CreateTexture(nil, "BORDER")
        hdrLine:SetHeight(px)
        hdrLine:SetPoint("TOPLEFT", 24, -52)
        hdrLine:SetPoint("TOPRIGHT", -24, -52)
        hdrLine:SetTexture("Interface\\Buttons\\WHITE8X8")
        hdrLine:SetVertexColor(unpack(Theme.Colors.divider))

        local collapseAllBtn = Theme:CreateActionButton(m, 32, 26, "折叠全部分组", "collapse", "折叠全部分组和目标", nil, true)
        collapseAllBtn:SetPoint("TOPLEFT", 24, -64)
        collapseAllBtn:SetScript("OnClick", function()
            wipe(ns.db.expandedMatrixGroups)
            wipe(ns.db.expandedMatrixTargets)
            m.offset = 0
            m:RefreshTreeExpansion()
        end)

        local expandAllBtn = Theme:CreateActionButton(m, 32, 26, "展开全部分组", "expand", "展开全部分组", nil, true)
        expandAllBtn:SetPoint("LEFT", collapseAllBtn, "RIGHT", 8, 0)
        expandAllBtn:SetScript("OnClick", function()
            for _, gName in ipairs(ns.db.teamGroups or {}) do
                ns.db.expandedMatrixGroups[gName] = true
            end
            m:RefreshTreeExpansion()
        end)

        local checkMissingBtn = Theme:CreateActionButton(m, 152, 26, "查看缺失宠物汇总", "missing", nil, "WARNING")
        checkMissingBtn:SetPoint("LEFT", expandAllBtn, "RIGHT", 8, 0)
        checkMissingBtn:Hide()
        checkMissingBtn:SetScript("OnClick", function()
            local report, uCount = ns:CollectMissingPetsForTeams(ns.db.teams or {})
            if #report > 0 and ns.ShowMissingPetsModal then
                ns:ShowMissingPetsModal(report, uCount)
            end
        end)
        m.checkMissingBtn = checkMissingBtn

        local matrixSearchTimer = nil
        local searchBox = Theme:CreateFlatEditBox(m, 240, 26, "搜索队伍 / 目标 / 分组...")
        searchBox:SetPoint("TOPRIGHT", -24, -64)
        local function ApplyMatrixSearch(text, immediate, force)
            local newKw = strlower(strtrim(text or ""))
            if newKw == matrixSearchKw and not force then return end
            matrixSearchKw = newKw
            m._treeDirty = true
            m.offset = 0
            if matrixSearchTimer then
                matrixSearchTimer:Cancel()
                matrixSearchTimer = nil
            end
            if immediate then
                if m:IsShown() then m:Refresh() end
            else
                matrixSearchTimer = C_Timer.NewTimer(0.15, function()
                    matrixSearchTimer = nil
                    if m:IsShown() then m:Refresh() end
                end)
            end
        end
        searchBox:SetScript("OnTextChanged", function(self, userInput)
            if self._clearingSearch then return end
            ApplyMatrixSearch(self:GetText() or "", not userInput)
        end)
        Theme:EnableSearchClearButton(searchBox, function() ApplyMatrixSearch("", true, true) end)
        m.searchBox = searchBox

        local listBox = CreateFrame("Frame", nil, m, "BackdropTemplate")
        listBox:SetPoint("TOPLEFT", 24, -100)
        listBox:SetPoint("BOTTOMRIGHT", -24, 60)
        listBox:EnableMouseWheel(true)
        Theme:ApplyBackdrop(listBox, Theme.Colors.bgInput, Theme.Colors.border, false)
        m.listBox = listBox

        local scrollTrack = CreateFrame("Button", nil, listBox, "BackdropTemplate")
        scrollTrack:SetWidth(8)
        scrollTrack:SetPoint("TOPRIGHT", listBox, "TOPRIGHT", -4, -6)
        scrollTrack:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -4, 6)
        Theme:ApplyBackdrop(scrollTrack, Theme.Colors.bgPanel, Theme.Colors.border, false)
        scrollTrack:EnableMouse(true)

        local scrollThumb = CreateFrame("Button", nil, scrollTrack, "BackdropTemplate")
        scrollThumb:SetWidth(6)
        scrollThumb:SetHeight(44)
        scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -1)
        Theme:ApplyBackdrop(scrollThumb, Theme.Colors.btnPrimary, Theme.Colors.borderBlue, false)
        scrollThumb:RegisterForDrag("LeftButton")

        local MAX_TREE_ROWS = 10

        listBox:SetScript("OnMouseWheel", function(_, delta)
            local maxOff = math.max(0, (m.totalNodeCount or 0) - MAX_TREE_ROWS)
            local nextOff = math.max(0, math.min(maxOff, m.offset - delta * 2))
            if nextOff ~= m.offset then
                m.offset = nextOff
                m:RenderRows()
            end
        end)

        m.rows = {}
        for i = 1, MAX_TREE_ROWS do
            local r = Theme:CreateMenuRow(listBox, 682, 36, "")
            r:SetPoint("TOPLEFT", 8, -6 - (i - 1) * 37)
            r:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            r.arrow = Theme:CreateArrowTexture(r, 12, "RIGHT")
            r.arrow:SetPoint("LEFT", 10, 0)

            r.typeWatermarks = {}
            for s = 1, 3 do
                local wm = Theme:CreateWatermarkPetTypeTex(r, 32, 32)
                wm:SetPoint("RIGHT", -6 - (3 - s) * 36, 0)
                r.typeWatermarks[s] = wm
            end

            r.petIcons = {}
            for s = 1, 3 do
                local pBtn = Theme:CreateCroppedIcon(r, 28)
                pBtn:SetPoint("RIGHT", -126 - (3 - s) * 32, 0)
                pBtn:EnableMouse(true)
                pBtn.slotIdx = s
                pBtn.parentRow = r

                local warnMark = pBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                warnMark:SetPoint("TOPLEFT", 1, -1)
                local fPath = warnMark:GetFont()
                if fPath then warnMark:SetFont(fPath, 10, "OUTLINE") end
                warnMark:SetText("|cffff5500!|r")
                warnMark:Hide()
                pBtn.warnMark = warnMark

                local lvBadge = pBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                lvBadge:SetPoint("BOTTOMRIGHT", -1, 1)
                if fPath then lvBadge:SetFont(fPath, 10, "OUTLINE") end
                lvBadge:Hide()
                pBtn.lvBadge = lvBadge

                pBtn:SetScript("OnEnter", function(selfBtn)
                    local node = selfBtn.parentRow.node
                    if node and node.nodeType == "TEAM" then
                        local isActive = (node.teamIndex == ns.db.selectedTeamIdx)
                        local _, _, _, pData = GetTeamSlotPetData(node.team, selfBtn.slotIdx, isActive)
                        if pData then SafeShowPetDetail(selfBtn, pData, false) end
                    end
                end)
                pBtn:SetScript("OnLeave", function()
                    SafeHidePetDetail(false)
                end)
                pBtn:SetScript("OnMouseUp", function(selfBtn, button)
                    if button == "LeftButton" then
                        local node = selfBtn.parentRow.node
                        if node and node.nodeType == "TEAM" then
                            local isActive = (node.teamIndex == ns.db.selectedTeamIdx)
                            local _, _, _, pData = GetTeamSlotPetData(node.team, selfBtn.slotIdx, isActive)
                            if pData then SafeShowPetDetail(selfBtn, pData, true) end
                        end
                    end
                end)

                r.petIcons[s] = pBtn
            end

            r.rightBadge = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.rightBadge:SetPoint("RIGHT", -12, 0)
            Theme:HookLocalizedFontString(r.rightBadge)

            r:SetScript("OnClick", function(rowBtn, button)
                local node = rowBtn.node
                if not node then return end
                if node.nodeType == "GROUP" then
                    if button == "RightButton" then
                        if ns.ShowMatrixGroupContextMenu then
                            ns:ShowMatrixGroupContextMenu(rowBtn, node.groupName)
                        end
                    else
                        ns.db.expandedMatrixGroups[node.groupName] = not node.expanded
                        if ns.BumpTeamTreeRevision then ns:BumpTeamTreeRevision() end
                        m:RefreshTreeExpansion()
                    end
                elseif node.nodeType == "TARGET" then
                    if button == "RightButton" then
                        if node.routeKey then
                            ns:ShowRouteTargetContextMenu(rowBtn, node.routeKey, node.targetKey)
                        end
                    else
                        local nextExpanded = not node.expanded
                        ns.db.expandedMatrixTargets[node.targetKey] = nextExpanded
                        if node.legacyKey and node.legacyKey ~= node.targetKey then
                            ns.db.expandedMatrixTargets[node.legacyKey] = nextExpanded
                        end
                        if ns.BumpTeamTreeRevision then ns:BumpTeamTreeRevision() end
                        m:RefreshTreeExpansion()
                    end
                elseif node.nodeType == "TEAM" then
                    if button == "RightButton" then
                        ns:ShowTeamContextMenu(rowBtn, node.teamIndex)
                    elseif ns.db.selectedTeamIdx ~= node.teamIndex then
                        ns:RequestCompactTeamSwitch(node.teamIndex)
                    end
                end
            end)

            r:SetScript("OnDoubleClick", function(rowBtn)
                local node = rowBtn.node
                if not node or node.nodeType ~= "TEAM" then return end
                ns:RequestCompactTeamSwitch(node.teamIndex, function() m:Hide() end)
            end)

            m.rows[i] = r
        end

        local function SyncTreeScrollThumb(totalNodes)
            local maxOff = math.max(0, totalNodes - MAX_TREE_ROWS)
            local trackH = scrollTrack:GetHeight()
            if not trackH or trackH <= 0 then trackH = 360 end
            local thumbH, yOff, alpha
            if maxOff <= 0 then
                thumbH = math.max(28, trackH - 2)
                yOff = -1
                alpha = 0.30
            else
                thumbH = math.max(28, math.floor((MAX_TREE_ROWS / totalNodes) * (trackH - 2)))
                local availMove = math.max(1, (trackH - 2) - thumbH)
                local ratio = math.max(0, math.min(1, m.offset / maxOff))
                yOff = -1 - math.floor(ratio * availMove)
                alpha = 1.0
            end
            if scrollThumb._lastH ~= thumbH then
                scrollThumb._lastH = thumbH
                scrollThumb:SetHeight(thumbH)
            end
            if scrollThumb._lastY ~= yOff then
                scrollThumb._lastY = yOff
                scrollThumb:ClearAllPoints()
                scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, yOff)
            end
            if scrollThumb._lastA ~= alpha then
                scrollThumb._lastA = alpha
                scrollThumb:SetAlpha(alpha)
            end
        end

        local function UpdateTreeScrollFromCursor()
            if not IsMouseButtonDown("LeftButton") then
                scrollThumb:SetScript("OnUpdate", nil)
                return
            end
            local totalNodes = m.totalNodeCount or 0
            local maxOff = math.max(0, totalNodes - MAX_TREE_ROWS)
            if maxOff <= 0 then return end
            local trackTop = scrollTrack:GetTop()
            local trackH = scrollTrack:GetHeight()
            local thumbH = scrollThumb:GetHeight()
            local _, rawY = GetCursorPosition()
            local cy = rawY / scrollTrack:GetEffectiveScale()
            if trackTop and trackH and (trackH - thumbH) > 0 then
                local grab = scrollThumb.grabOffset or (thumbH / 2)
                local ratio = ((trackTop - cy) - grab) / (trackH - thumbH)
                ratio = math.max(0, math.min(1, ratio))
                local newOff = math.floor(ratio * maxOff + 0.5)
                if newOff ~= m.offset then
                    m.offset = newOff
                    m:RenderRows()
                end
            end
        end

        scrollThumb:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                local _, rawY = GetCursorPosition()
                local cy = rawY / self:GetEffectiveScale()
                local top = self:GetTop() or cy
                self.grabOffset = math.max(2, math.min(self:GetHeight() - 2, top - cy))
                self:SetScript("OnUpdate", UpdateTreeScrollFromCursor)
            end
        end)
        scrollThumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
        scrollThumb:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", UpdateTreeScrollFromCursor) end)
        scrollThumb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
        scrollThumb:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

        scrollTrack:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then
                scrollThumb.grabOffset = scrollThumb:GetHeight() / 2
                UpdateTreeScrollFromCursor()
                scrollThumb:SetScript("OnUpdate", UpdateTreeScrollFromCursor)
            end
        end)
        scrollTrack:SetScript("OnMouseUp", function()
            scrollThumb:SetScript("OnUpdate", nil)
        end)

        local newTeamBtn = Theme:CreateActionButton(m, 146, 32, "新建队伍", "new-team", nil, "PRIMARY")
        newTeamBtn:SetPoint("BOTTOMLEFT", 24, 16)
        newTeamBtn:SetScript("OnClick", function()
            if ns.ShowTeamBuilderModal then
                ns:ShowTeamBuilderModal(nil, "未分组队伍")
            else
                ns:ShowQuickInputModal("NEW_TEAM", "未分组队伍")
            end
        end)

        local newGroupBtn = Theme:CreateActionButton(m, 146, 32, "新建队伍分组", "new-group")
        newGroupBtn:SetPoint("LEFT", newTeamBtn, "RIGHT", 10, 0)
        newGroupBtn:SetScript("OnClick", function()
            ns:ShowQuickInputModal("NEW_GROUP")
        end)

        local exportBtn = Theme:CreateActionButton(m, 112, 32, "导出", "export", "导出队伍或对战脚本")
        exportBtn:SetPoint("BOTTOMRIGHT", -24, 16)
        exportBtn:SetScript("OnClick", function()
            m:Hide()
            ns:ShowExportChoiceModal()
        end)
        m.exportBtn = exportBtn

        local importBtn = Theme:CreateActionButton(m, 112, 32, "导入", "import", "导入队伍或对战脚本")
        importBtn:SetPoint("RIGHT", exportBtn, "LEFT", -10, 0)
        importBtn:SetScript("OnClick", function()
            m:Hide()
            ns:ShowImportModal("TEAM")
        end)
        m.importBtn = importBtn

        local syncRematchBtn = Theme:CreateActionButton(m, 146, 32, "同步 Rematch", "sync", nil, "WARNING")
        syncRematchBtn:SetPoint("RIGHT", importBtn, "LEFT", -10, 0)
        syncRematchBtn:SetScript("OnClick", function()
            local ok = ns:MigrateFromRematch(true)
            if ok and m.Refresh then
                m._treeDirty = true
                m:Refresh()
            end
        end)
        m.syncRematchBtn = syncRematchBtn

        function m:RebuildBuckets()
            local allTeams = ns.db and ns.db.teams or {}
            ns.db.teamGroups = ns.db.teamGroups or { "最爱队伍", "未分组队伍", "暗影界", "巨龙时代", "地心之战", "宠物地下城" }

            ns.AutoRouting:SyncTargetGroups()
            local routeByNpcID = {}
            local routeByTeamName = {}
            for routeKey, route in pairs(ns.db.routeMappings) do
                local npcID = tonumber(route.npcID) or 0
                if npcID > 0 and not routeByNpcID[npcID] then
                    routeByNpcID[npcID] = routeKey
                end
                for _, teamName in ipairs(route.teams or {}) do
                    routeByTeamName[teamName] = routeKey
                end
            end

            local groupOrder = {}
            local groupMap = {}
            for _, gName in ipairs(ns.db.teamGroups) do
                if not groupMap[gName] then
                    groupMap[gName] = { targets = {}, targetOrder = {}, totalTeams = 0, missingTeams = 0, underLvTeams = 0 }
                    groupOrder[#groupOrder + 1] = gName
                end
            end

            local globalUniqueMissingSpecies = {}
            local globalUniqueMissingCount = 0
            local globalHasAnyMissing = false

            for idx, t in ipairs(allTeams) do
                local gName = t.group or "未分组队伍"
                local audit = ns:AuditTeamPets(t)

                if audit.hasMissing then
                    globalHasAnyMissing = true
                    for _, mPet in ipairs(audit.missingList) do
                        if not globalUniqueMissingSpecies[mPet.speciesID] then
                            globalUniqueMissingSpecies[mPet.speciesID] = true
                            globalUniqueMissingCount = globalUniqueMissingCount + 1
                        end
                    end
                end

                local pass = true
                if matrixSearchKw ~= "" then
                    pass = ns.FuzzySearch:MatchFields(matrixSearchKw, t.name, t.npcName, gName)
                end

                if pass then
                    if not groupMap[gName] then
                        groupMap[gName] = { targets = {}, targetOrder = {}, totalTeams = 0, missingTeams = 0, underLvTeams = 0 }
                        groupOrder[#groupOrder + 1] = gName
                    end
                    local gObj = groupMap[gName]
                    gObj.totalTeams = gObj.totalTeams + 1
                    if audit.hasMissing then gObj.missingTeams = gObj.missingTeams + 1 end
                    if audit.hasUnderLv then gObj.underLvTeams = gObj.underLvTeams + 1 end

                    local tNpcID = tonumber(t.npcID) or 0
                    local routeKey = routeByNpcID[tNpcID] or routeByTeamName[t.name]
                    local route = routeKey and ns.db.routeMappings[routeKey]
                    local routeName = route and strtrim(route.npcName or "") or ""
                    local targetLabel = (routeName ~= "" and routeName)
                        or (t.npcName and t.npcName ~= "" and t.npcName)
                        or (tNpcID > 0 and ("NPC #" .. tNpcID))
                        or ns:T("通用 / 未绑定目标")

                    local bucketKey = routeKey and ("route:" .. tostring(routeKey)) or ("label:" .. targetLabel)
                    if not gObj.targets[bucketKey] then
                        gObj.targets[bucketKey] = {
                            label = targetLabel, routeKey = routeKey, list = {},
                            missingCount = 0, underLvCount = 0,
                        }
                        gObj.targetOrder[#gObj.targetOrder + 1] = bucketKey
                    end
                    local bucket = gObj.targets[bucketKey]
                    if audit.hasMissing then bucket.missingCount = bucket.missingCount + 1 end
                    if audit.hasUnderLv then bucket.underLvCount = bucket.underLvCount + 1 end

                    local missingBadge = ""
                    if audit.hasMissing then
                        local missingNames = {}
                        for _, mInfo in ipairs(audit.missingList) do
                            missingNames[#missingNames + 1] = mInfo.name
                        end
                        missingBadge = ns:TF(" |cffff4040[缺: %s]|r", table.concat(missingNames, " / "))
                    end

                    local underLvBadge = ""
                    if audit.hasUnderLv then
                        local underParts = {}
                        for _, uInfo in ipairs(audit.underLvList) do
                            underParts[#underParts + 1] = ns:TF("%s(%d级)", uInfo.name, uInfo.level)
                        end
                        underLvBadge = ns:TF(" |cffff9900[未满级: %s]|r", table.concat(underParts, "/"))
                    end

                    bucket.list[#bucket.list + 1] = {
                        teamIndex    = idx,
                        team         = t,
                        audit        = audit,
                        missingBadge = missingBadge,
                        underLvBadge = underLvBadge,
                    }
                end
            end

            if self.checkMissingBtn then
                if globalHasAnyMissing then
                    self.checkMissingBtn.text:SetText(ns:TF("查看缺失宠物汇总 (%d)", globalUniqueMissingCount))
                    self.checkMissingBtn:Show()
                else
                    self.checkMissingBtn:Hide()
                    if ns.MissingPetsModal and ns.MissingPetsModal:IsShown() then
                        ns.MissingPetsModal:Hide()
                    end
                end
            end

            self._cachedGroupOrder = groupOrder
            self._cachedGroupMap   = groupMap
            self._lastBuiltKw      = matrixSearchKw
            self._treeDirty        = false
        end

        function m:FlattenTree()
            if not self._cachedGroupOrder or not self._cachedGroupMap then
                self:RebuildBuckets()
            end

            local flatNodes = {}
            local forceExpand = (matrixSearchKw ~= "")

            for _, gName in ipairs(self._cachedGroupOrder) do
                local gObj = self._cachedGroupMap[gName]
                if gObj and (gObj.totalTeams > 0 or matrixSearchKw == "") then
                    local isGrpOpen = forceExpand or (ns.db.expandedMatrixGroups[gName] == true)
                    flatNodes[#flatNodes + 1] = {
                        nodeType     = "GROUP",
                        groupName    = gName,
                        count        = gObj.totalTeams,
                        missingCount = gObj.missingTeams,
                        underLvCount = gObj.underLvTeams,
                        expanded     = isGrpOpen,
                    }

                    if isGrpOpen then
                        local labelCounts = {}
                        for _, bucketKey in ipairs(gObj.targetOrder) do
                            local label = gObj.targets[bucketKey].label
                            labelCounts[label] = (labelCounts[label] or 0) + 1
                        end
                        for _, bucketKey in ipairs(gObj.targetOrder) do
                            local bucket = gObj.targets[bucketKey]
                            local tLabel = bucket.label
                            local legacyKey = gName .. "::" .. tLabel
                            local tKey = bucket.routeKey and (gName .. "::route:" .. tostring(bucket.routeKey)) or legacyKey
                            local savedExpanded = ns.db.expandedMatrixTargets[tKey]
                            if savedExpanded == nil then
                                savedExpanded = ns.db.expandedMatrixTargets[legacyKey]
                            end
                            local isTargetOpen = forceExpand or savedExpanded == true
                            if bucket.routeKey and labelCounts[tLabel] > 1 then
                                tLabel = string.format("%s [%s]", tLabel, tostring(bucket.routeKey))
                            end
                            flatNodes[#flatNodes + 1] = {
                                nodeType     = "TARGET",
                                groupName    = gName,
                                targetLabel  = tLabel,
                                targetKey    = tKey,
                                legacyKey    = legacyKey,
                                routeKey     = bucket.routeKey,
                                savedExpanded = savedExpanded,
                                count        = #bucket.list,
                                missingCount = bucket.missingCount,
                                underLvCount = bucket.underLvCount,
                                expanded     = isTargetOpen,
                            }

                            if isTargetOpen then
                                for _, tItem in ipairs(bucket.list) do
                                    flatNodes[#flatNodes + 1] = {
                                        nodeType     = "TEAM",
                                        groupName    = gName,
                                        targetLabel  = tLabel,
                                        teamIndex    = tItem.teamIndex,
                                        team         = tItem.team,
                                        audit        = tItem.audit,
                                        missingBadge = tItem.missingBadge,
                                        underLvBadge = tItem.underLvBadge,
                                    }
                                end
                            end
                        end
                    end
                end
            end

            self.flatNodes = flatNodes
            self.totalNodeCount = #flatNodes
        end

        function m:RebuildTree()
            self:RebuildBuckets()
            self:FlattenTree()
        end

        function m:RefreshTreeExpansion()
            if self._treeDirty or self._lastBuiltKw ~= matrixSearchKw or not self._cachedGroupMap then
                self:RebuildBuckets()
            end
            self:FlattenTree()
            self:RenderRows()
        end

        function m:RenderRows()
            local flatNodes = self.flatNodes or {}
            local maxOff = math.max(0, #flatNodes - MAX_TREE_ROWS)
            if self.offset > maxOff then self.offset = maxOff end
            SyncTreeScrollThumb(#flatNodes)

            for i = 1, MAX_TREE_ROWS do
                local r = self.rows[i]
                local node = flatNodes[self.offset + i]
                r.node = node
                if node then
                    r:Show()
                    for s = 1, 3 do
                        local pBtn = r.petIcons[s]
                        pBtn:Hide()
                        if pBtn.warnMark then pBtn.warnMark:Hide() end
                        if pBtn.lvBadge then pBtn.lvBadge:Hide() end
                        r.typeWatermarks[s]:Hide()
                    end

                    if node.nodeType == "GROUP" then
                        r:SetSelected(false)
                        r.arrow:Show()
                        if r._lastNodeType ~= "GROUP" then
                            r._lastNodeType = "GROUP"
                            r.arrow:ClearAllPoints()
                            r.arrow:SetPoint("LEFT", 10, 0)
                            r.arrow:SetVertexColor(0.38, 0.78, 1.0, 1)
                            r.text:ClearAllPoints()
                            r.text:SetPoint("LEFT", 28, 0)
                            r.text:SetPoint("RIGHT", -90, 0)
                        end
                        r.arrow:SetRotation(node.expanded and 0 or math.rad(90))

                        local missTag = (node.missingCount and node.missingCount > 0) and ns:TF(" |cffff4040(%d队缺宠)|r", node.missingCount) or ""
                        local underTag = (node.underLvCount and node.underLvCount > 0) and ns:TF(" |cffff9900(%d队未满级)|r", node.underLvCount) or ""
                        r.text:SetText(string.format("|cff38bdf8%s|r%s%s", ns:T(node.groupName), missTag, underTag))
                        r.rightBadge:SetText(ns:TF("|cff6b7280%d 支队伍|r", node.count))

                    elseif node.nodeType == "TARGET" then
                        r:SetSelected(false)
                        r.arrow:Show()
                        if r._lastNodeType ~= "TARGET" then
                            r._lastNodeType = "TARGET"
                            r.arrow:ClearAllPoints()
                            r.arrow:SetPoint("LEFT", 28, 0)
                            r.arrow:SetVertexColor(0.06, 0.82, 0.65, 1)
                            r.text:ClearAllPoints()
                            r.text:SetPoint("LEFT", 46, 0)
                            r.text:SetPoint("RIGHT", -90, 0)
                        end
                        r.arrow:SetRotation(node.expanded and 0 or math.rad(90))

                        local missTag = (node.missingCount and node.missingCount > 0) and ns:TF(" |cffff4040(%d队缺宠)|r", node.missingCount) or ""
                        local underTag = (node.underLvCount and node.underLvCount > 0) and ns:TF(" |cffff9900(%d队未满级)|r", node.underLvCount) or ""
                        r.text:SetText(ns:TF("|cff10b981目标: %s|r%s%s", node.targetLabel, missTag, underTag))
                        r.rightBadge:SetText(ns:TF("|cff6b7280%d 队|r", node.count))

                    elseif node.nodeType == "TEAM" then
                        local t = node.team
                        local audit = node.audit or ns:AuditTeamPets(t)
                        local isActive = (node.teamIndex == ns.db.selectedTeamIdx)
                        r:SetSelected(isActive)
                        r.arrow:Hide()

                        if r._lastNodeType ~= "TEAM" then
                            r._lastNodeType = "TEAM"
                            r.text:ClearAllPoints()
                            r.text:SetPoint("LEFT", 52, 0)
                            r.text:SetPoint("RIGHT", -235, 0)
                        end

                        r.text:SetText((isActive and ns:T("|cff10b981[当前] |r|cffffffff") or "|cfff3f4f6") .. (t.name or ns:T("未命名队伍")) .. "|r" .. (node.underLvBadge or "") .. (node.missingBadge or ""))
                        r.rightBadge:SetText("")

                        for s = 1, 3 do
                            local pBtn = r.petIcons[s]
                            local wm = r.typeWatermarks[s]
                            local isLv, iconTex, petType, isSlotMissing = GetTeamSlotIconFast(t, s, isActive)
                            local slotUnderLv = audit.underLvBySlot and audit.underLvBySlot[s]

                            if isLv or iconTex then
                                pBtn:Show()
                                local finalTex = iconTex or "Interface\\Icons\\INV_Pet_Achievement_RaiseAPetLevel_25"
                                if pBtn._lastTex ~= finalTex then
                                    pBtn._lastTex = finalTex
                                    pBtn.icon:SetTexture(finalTex)
                                end
                                pBtn.icon:SetDesaturated(isSlotMissing == true)

                                if isSlotMissing then
                                    pBtn:SetBackdropBorderColor(unpack(Theme.Colors.borderRed))
                                elseif slotUnderLv then
                                    pBtn:SetBackdropBorderColor(unpack(Theme.Colors.borderAmber))
                                    if pBtn.warnMark then pBtn.warnMark:Show() end
                                    if pBtn.lvBadge then
                                        pBtn.lvBadge:SetText("|cffff9900" .. slotUnderLv .. "|r")
                                        pBtn.lvBadge:Show()
                                    end
                                else
                                    pBtn:SetBackdropBorderColor(unpack(Theme.Colors.border))
                                end
                            end
                            if petType then
                                Theme:SetPetTypeDecalTexture(wm, petType)
                            end
                        end
                    end
                else
                    r:Hide()
                end
            end
        end

        function m:Refresh()
            if self._treeDirty or self._lastBuiltKw ~= matrixSearchKw or not self._cachedGroupOrder or not self.flatNodes then
                self:RebuildTree()
            end
            self:RenderRows()
        end

        ns.TeamMatrixModal = m
        ns:BindHeaderHubPanel(m)
    end

    ns.TeamMatrixModal:Refresh()
    ns.TeamMatrixModal:Show()
end

function ns:ToggleTeamMatrixModal()
    if ns.TeamMatrixModal and ns.TeamMatrixModal:IsShown() then
        ns.TeamMatrixModal:Hide()
    else
        self:ShowTeamMatrixModal()
    end
end

-- ==================== 3. 核心出战编组监控舱渲染（静态常量复用，零表分配） ====================
function ns:RefreshLoadoutCabin()
    local f = ns.MainFrame
    if not f or not f.homeView or not f.loadoutCards then return end

    local team = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
    if f.cabinTargetBtn then
        local route = team and (ns:FindExistingRouteForNPC(team.npcID, team.npcName) or ns:FindRouteContainingTeam(team.name))
        local npcID = tonumber(route and route.npcID or team and team.npcID) or 0
        local npcName = route and route.npcName or team and team.npcName or ""
        f.cabinTargetBtn.text:SetText(ns:GetTargetDisplayName(npcID, npcName))
        f.cabinTargetBtn:SetEnabled(team ~= nil)
        f.cabinTargetBtn:SetAlpha(team and 1 or 0.55)
    end
    local lvSlot = (team and team.levelingSlot) or (ns.db and ns.db.settings.levelingSlot) or 2
    local audit = team and ns:AuditTeamPets(team) or ns:AuditTeamPets(nil)
    local hasTeamMissing = audit.hasMissing
    local teamMissingList = audit.missingList
    local liveUnderLvCount = 0
    local deadSlotCount = 0

    for slot = 1, 3 do
        local card = f.loadoutCards[slot]
        local isLevelingSlot = (team and team.hasLevelingSlot and lvSlot == slot) and true or false
        local isRandomSlot   = (not (ns.staging and ns.staging.isDirty)) and (team and team.randomSlots and team.randomSlots[slot] ~= nil)
        local targetSpID     = (team and team.speciesLoadout and tonumber(team.speciesLoadout[slot])) or 0
        local isMissingSlot  = (not (ns.staging and ns.staging.isDirty)) and (not isLevelingSlot) and (not isRandomSlot) and (targetSpID > 0) and (not ns:IsSpeciesCollected(targetSpID))

        local petID, a1, a2, a3 = C_PetJournal.GetPetLoadOutInfo(slot)

        if isRandomSlot and not isLevelingSlot and petID ~= ns.AutoRouting:GetResolvedRandomPet(team, slot) then
            petID = nil
        end

        if not (ns.staging and ns.staging.isDirty) and not isLevelingSlot and not isRandomSlot and targetSpID > 0 then
            if isMissingSlot then
                petID = nil
            else
                local loadedSpID = petID and C_PetJournal.GetPetInfoByPetID(petID) or 0
                if loadedSpID ~= targetSpID then
                    local savedPetID = team and team.pets and team.pets[slot]
                    local savedSpID = (savedPetID and savedPetID ~= "LEVELING" and C_PetJournal.GetPetInfoByPetID(savedPetID)) or 0
                    if savedSpID == targetSpID then
                        petID = savedPetID
                    else
                        petID = ns.AutoRouting:FindAnyCollectedPetForSpecies(targetSpID, EMPTY_USED_PETS)
                    end
                end
            end
        end

        local pData = petID and PopulateCabinSlotPetData(slot, petID) or nil
        card.petData = pData
        card.isLevelingSlot = isLevelingSlot
        if card.underLvBanner then card.underLvBanner:Hide() end
        if card.deadOverlay then card.deadOverlay:Hide() end
        if card.deadBanner then card.deadBanner:Hide() end

        local slotThreshold = ns:GetSlotThreshold(team, slot)
        local thresholdBadge = card.thresholdBadge
        if thresholdBadge.value ~= slotThreshold then
            thresholdBadge.value = slotThreshold
            local enabled = slotThreshold > 0
            if enabled then
                thresholdBadge.label = slotThreshold .. (slotThreshold <= 100 and "%" or " HP")
                thresholdBadge.text:SetText("|cffffb800" .. thresholdBadge.label .. "|r")
            end
            thresholdBadge:SetShown(enabled)
            card.underLvBanner:ClearAllPoints()
            if enabled then
                card.underLvBanner:SetPoint("LEFT", thresholdBadge, "RIGHT", 6, 0)
            else
                card.underLvBanner:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -14)
            end
        end

        if isLevelingSlot then
            local isLvPetDead = (pData ~= nil and pData.isDead == true)
            if isLvPetDead then
                deadSlotCount = deadSlotCount + 1
                card:SetBackdropColor(unpack(CABIN_BG_DEAD))
                card:SetBackdropBorderColor(unpack(Theme.Colors.borderRed))
                if card.deadOverlay then card.deadOverlay:Show() end
                if card.deadBanner then card.deadBanner:Show() end
            else
                card:SetBackdropColor(unpack(CABIN_BG_LV))
                card:SetBackdropBorderColor(unpack(Theme.Colors.borderAmber))
            end

            local displayID = pData and pData.displayID or 0
            if displayID == 0 and pData and pData.speciesID then
                displayID = select(12, C_PetJournal.GetPetInfoBySpeciesID(pData.speciesID))
            end
            SetModelDisplayCached(card.model, displayID)

            local lvName = pData and pData.name or ns:T("待练小宠物")
            local lvNum = pData and pData.level or 1

            if isLvPetDead then
                card.titleTxt:SetText(ns:T("|cffff3030[已阵亡]|r |cffffffff[练级槽] 队列自动代练|r"))
                card.subTxt:SetText(ns:TF("|cffff4040当前挂载: %s (%d级 · 已阵亡)|r", lvName, lvNum))
                card.barLabel:SetText(ns:TF("|cffff4040生命条: 0 / %d (0%% · 请点击顶栏复活)|r", pData.maxHealth or 100))
                card.syncBar:SetStatusBarColor(0.82, 0.12, 0.16, 0.92)
                card.syncBar:SetValue(100)
            else
                card.titleTxt:SetText(ns:T("|cffffffff[练级槽] 队列自动代练|r"))
                card.subTxt:SetText(ns:TF("|cffffb800当前挂载: %s (%d级)|r", lvName, lvNum))

                local xp = pData and pData.xp or 0
                local maxXp = (pData and pData.maxXp and pData.maxXp > 0) and pData.maxXp or 100
                local xpPct = (lvNum >= 25) and 100 or math.floor((xp / maxXp) * 100)

                card.barLabel:SetText(ns:T("|cffffb800练级槽|r"))
                card.syncBar:SetStatusBarColor(0.96, 0.62, 0.05, 0.95)
                card.syncBar:SetValue(math.max(4, xpPct))
            end

            card.footerTxt:SetText(isLvPetDead and "|cffff6b6b当前队列练级宠已阵亡，请点击顶部复活或使用宠物绷带|r" or "|cffffb800已开启智能队列自动补充机制|r")

        elseif isMissingSlot then
            card:SetBackdropColor(unpack(CABIN_BG_MISSING))
            card:SetBackdropBorderColor(unpack(Theme.Colors.borderRed))

            local spName, _, petType, _, sourceText, _, _, _, _, _, _, displayID = C_PetJournal.GetPetInfoBySpeciesID(targetSpID)
            SetModelDisplayCached(card.model, displayID)

            local ptInfo = Theme.PetTypes[petType or 1]
            card.titleTxt:SetText(ns:TF("|cffff4040[缺失] %s|r", spName or (ns:T("未知宠物") .. " #" .. targetSpID)))
            card.subTxt:SetText(ns:TF("|cffff6b6b尚未收集该宠物 · 类型: %s (ID:%d)|r", ptInfo and ptInfo.name or ns:T("未知宠物"), targetSpID))

            card.barLabel:SetText(ns:T("|cffff4040状态: 未收集 (虚拟预览模式 — 无法出战)|r"))
            card.syncBar:SetStatusBarColor(0.88, 0.18, 0.22, 0.90)
            card.syncBar:SetValue(100)

            local sortedIDs = ns:GetSortedPetAbilities(targetSpID)
            local presetAbs = team and team.abilities and team.abilities[slot]

            for idx = 1, 6 do
                local abBtn = card.abBtns[idx]
                local col = ((idx - 1) % 3) + 1
                local abID = sortedIDs and sortedIDs[idx] or nil

                if abID and abID > 0 then
                    abBtn:Show()
                    local abName, abIcon = C_PetJournal.GetPetAbilityInfo(abID)
                    abBtn.abID = abID
                    abBtn.speciesID = targetSpID
                    abBtn.abCol = col
                    local finalTex = abIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
                    if abBtn._lastTex ~= finalTex then
                        abBtn._lastTex = finalTex
                        abBtn.icon:SetTexture(finalTex)
                    end
                    abBtn.icon:Show()

                    local activeColID = presetAbs and presetAbs[col]
                    if (not activeColID or activeColID == 0) and sortedIDs then
                        activeColID = sortedIDs[col]
                    end
                    local isSelected = (activeColID == abID)
                    abBtn.isSelected = isSelected

                    abBtn.icon:SetDesaturated(true)
                    if isSelected then
                        abBtn.icon:SetVertexColor(0.90, 0.70, 0.70)
                        abBtn.nameTxt:SetText("|cffffb4b4" .. (abName or "") .. "|r")
                        abBtn:SetBackdropColor(unpack(AB_BG_MISS_SEL))
                        abBtn:SetBackdropBorderColor(unpack(Theme.Colors.borderRed))
                    else
                        abBtn.icon:SetVertexColor(0.38, 0.38, 0.38)
                        abBtn.nameTxt:SetText("|cff6b7280" .. (abName or "") .. "|r")
                        abBtn:SetBackdropColor(unpack(AB_BG_MISS_UNSEL))
                        abBtn:SetBackdropBorderColor(unpack(Theme.Colors.border))
                    end
                else
                    abBtn.abID = nil
                    abBtn.speciesID = nil
                    abBtn:Hide()
                end
            end

            local cleanSrc = sourceText and string.gsub(sourceText, "\n", " ") or ns:T("请前往宠物手册查看获取途径，或拖入替代宠物")
            card.footerTxt:SetText("|cffff6b6b" .. cleanSrc .. "|r")

        else
            local isDeadPet = (pData ~= nil and pData.isDead == true)
            if isDeadPet then
                deadSlotCount = deadSlotCount + 1
            end

            local slotLv = (pData and pData.level) or (audit.underLvBySlot and audit.underLvBySlot[slot]) or 25
            local isUnder25Main = (not isRandomSlot) and (pData ~= nil or (audit.underLvBySlot and audit.underLvBySlot[slot] ~= nil)) and (slotLv < 25)
            if isUnder25Main then
                liveUnderLvCount = liveUnderLvCount + 1
            end

            local isFocused = (ns.db.activeTargetSlot == slot)
            if isDeadPet then
                card:SetBackdropColor(unpack(CABIN_BG_DEAD))
                card:SetBackdropBorderColor(unpack(Theme.Colors.borderRed))
                if card.deadOverlay then card.deadOverlay:Show() end
                if card.deadBanner then card.deadBanner:Show() end
                if isUnder25Main and card.underLvBanner then
                    card.underLvBanner.text:SetText(ns:TF("|cffff9900! 主力未满级 (Lv.%d)|r", slotLv))
                    card.underLvBanner:Show()
                end
            elseif isUnder25Main then
                card:SetBackdropColor(unpack(CABIN_BG_UNDERLV))
                card:SetBackdropBorderColor(unpack(isFocused and Theme.Colors.borderBlue or Theme.Colors.borderAmber))
                if card.underLvBanner then
                    card.underLvBanner.text:SetText(ns:TF("|cffff9900! 主力未满级 (Lv.%d)|r", slotLv))
                    card.underLvBanner:Show()
                end
            elseif isFocused then
                card:SetBackdropColor(unpack(CABIN_BG_FOCUSED))
                card:SetBackdropBorderColor(unpack(Theme.Colors.borderBlue))
            else
                card:SetBackdropColor(unpack(CABIN_BG_NORMAL))
                card:SetBackdropBorderColor(unpack(Theme.Colors.border))
            end

            if pData then
                local displayID = pData.displayID or 0
                if displayID == 0 and pData.speciesID then
                    displayID = select(12, C_PetJournal.GetPetInfoBySpeciesID(pData.speciesID))
                end
                SetModelDisplayCached(card.model, displayID)

                local deadPrefix = isDeadPet and "|cffff3030[已阵亡]|r " or ""
                local rndPrefix = isRandomSlot and "|cff10b981[随机位]|r " or ""
                local underPrefix = isUnder25Main and "|cffff9900[未满级!]|r " or ""
                local petQualityColor = Theme.QualityColors[pData.rarity] or Theme.QualityColors[2]
                local nameCol = string.sub(petQualityColor[4], 1, 10)
                card.titleTxt:SetText(deadPrefix .. underPrefix .. rndPrefix .. nameCol .. (pData.name or ns:T("未知宠物")) .. "|r")

                local qPlain = GetQualityPlainName(pData.rarity)
                local qualityColor = Theme.QualityColors[pData.rarity] or Theme.QualityColors[2]
                local qualityHex = string.sub(qualityColor[4], 1, 10)
                if isDeadPet then
                    card.subTxt:SetText(ns:TF("|cffff6b6b等级 %d · 品质: %s [%s] · 无法出战|r", pData.level or slotLv, qPlain, pData.breed or "B/B"))
                    card.barLabel:SetText(ns:TF("|cffff4040生命条: 0 / %d (0%% · 已阵亡，请点击顶部复活图标)|r", pData.maxHealth or 100))
                    ns:ApplyHealthBarColor(card.syncBar, 0, true)
                    card.syncBar:SetValue(100)
                else
                    if isUnder25Main then
                        card.subTxt:SetText(ns:TF("|cffff9900等级 %d (未满25级!) · 品质: %s [%s]|r", pData.level or slotLv, qPlain, pData.breed or "B/B"))
                    else
                        card.subTxt:SetText(ns:TF("%s等级 %d · 品质: %s [%s]|r", qualityHex, pData.level or 25, qPlain, pData.breed or "B/B"))
                    end
                    card.barLabel:SetText(ns:TF("|cff9ca3af生命条: %d / %d (%d%%)|r", pData.health or 0, pData.maxHealth or 100, pData.hpPct or 0))
                    ns:ApplyHealthBarColor(card.syncBar, pData.hpPct or 0, false)
                    card.syncBar:SetValue(pData.hpPct or 0)
                end
            else
                SetModelDisplayCached(card.model, nil)
                if isRandomSlot then
                    local rType = team.randomSlots[slot] or 0
                    local ptInfo = (rType > 0) and Theme.PetTypes[rType] or nil
                    if ptInfo then
                        local rndSlotTitle = (ns.locale == "zhTW" and ("|cff10b981[隨機" .. ptInfo.name .. "寵]|r"))
                            or (ns.locale ~= "zhCN" and ("|cff10b981[Random " .. ptInfo.name .. "]|r"))
                            or ("|cff10b981[随机" .. ptInfo.name .. "宠]|r")
                        card.titleTxt:SetText(rndSlotTitle)
                    else
                        card.titleTxt:SetText(ns:T("|cff10b981[任意随机宠]|r"))
                    end
                    card.subTxt:SetText(ns:T("优先选择满级存活宠物"))
                else
                    card.titleTxt:SetText(ns:TF("|cff6b7280%d号槽位：空|r", slot))
                    card.subTxt:SetText(ns:T("|cff4b5563点击右上角下拉箭头并将宠物拖入槽位|r"))
                end
                card.barLabel:SetText(ns:T("|cff6b7280生命条: 0 / 0 (0%)|r"))
                card.syncBar:SetStatusBarColor(0.25, 0.30, 0.38, 0.8)
                card.syncBar:SetValue(0)
            end


            if isDeadPet then
                card.footerTxt:SetText(ns:T("|cffff6b6b当前宠物已阵亡 (0% HP)，请点击顶部复活或绷带图标恢复|r"))
            else
                card.footerTxt:SetText(ns:T("|cff6b7280左键拖动换位 · 右键菜单：召唤 / 练级槽 / 血量换宠|r"))
            end
        end

        if not isMissingSlot then
            local isDeadPet = pData and pData.isDead == true
            local speciesID = (pData and pData.speciesID) or (not isLevelingSlot and targetSpID) or 0
            local sortedIDs = (speciesID > 0) and ns:GetSortedPetAbilities(speciesID) or nil
            local curAb1, curAb2, curAb3 = a1 or 0, a2 or 0, a3 or 0
            if not isLevelingSlot and not (ns.staging and ns.staging.isDirty) and team and team.abilities and team.abilities[slot] then
                local savedAbs = team.abilities[slot]
                if curAb1 == 0 and (savedAbs[1] or 0) > 0 then curAb1 = savedAbs[1] end
                if curAb2 == 0 and (savedAbs[2] or 0) > 0 then curAb2 = savedAbs[2] end
                if curAb3 == 0 and (savedAbs[3] or 0) > 0 then curAb3 = savedAbs[3] end
            end

            for idx = 1, 6 do
                local abBtn = card.abBtns[idx]
                local col = ((idx - 1) % 3) + 1
                local abID = sortedIDs and sortedIDs[idx] or nil

                if abID and abID > 0 then
                    abBtn:Show()
                    local abName, abIcon = C_PetJournal.GetPetAbilityInfo(abID)
                    abBtn.abID = abID
                    abBtn.speciesID = speciesID
                    abBtn.abCol = col
                    local finalTex = abIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
                    if abBtn._lastTex ~= finalTex then
                        abBtn._lastTex = finalTex
                        abBtn.icon:SetTexture(finalTex)
                    end
                    abBtn.icon:Show()

                    local activeColID = (col == 1 and curAb1) or (col == 2 and curAb2) or curAb3
                    if (not activeColID or activeColID == 0) and sortedIDs then
                        activeColID = sortedIDs[col]
                    end
                    local isSelected = (activeColID == abID)
                    abBtn.isSelected = isSelected

                    if isSelected then
                        abBtn.icon:SetDesaturated(isDeadPet)
                        if isDeadPet then
                            abBtn.icon:SetVertexColor(0.85, 0.55, 0.55)
                            abBtn.nameTxt:SetText("|cffffb4b4" .. (abName or "") .. "|r")
                            abBtn:SetBackdropColor(unpack(AB_BG_DEAD_SEL))
                            abBtn:SetBackdropBorderColor(unpack(Theme.Colors.borderRed))
                        else
                            abBtn.icon:SetVertexColor(1, 1, 1)
                            abBtn.nameTxt:SetText("|cffffffff" .. (abName or "") .. "|r")
                            abBtn:SetBackdropColor(unpack(AB_BG_NORM_SEL))
                            abBtn:SetBackdropBorderColor(unpack(Theme.Colors.borderBlue))
                        end
                    else
                        abBtn.icon:SetDesaturated(true)
                        abBtn.icon:SetVertexColor(0.45, 0.45, 0.45)
                        abBtn.nameTxt:SetText("|cff6b7280" .. (abName or "") .. "|r")
                        abBtn:SetBackdropColor(unpack(AB_BG_NORM_UNSEL))
                        abBtn:SetBackdropBorderColor(unpack(Theme.Colors.border))
                    end
                else
                    abBtn.abID = nil
                    abBtn.speciesID = nil
                    abBtn:Hide()
                end
            end
        end
    end

    if f.cabinStatusBtn then
        local isDirty = (ns.staging and ns.staging.isDirty) and true or false
        if isDirty then
            if f.cabinSaveBtn then f.cabinSaveBtn:Show() end
            if f.cabinRevertBtn then f.cabinRevertBtn:Show() end
            if f.cabinStatusBtn._lastDirtyMode ~= true then
                f.cabinStatusBtn._lastDirtyMode = true
                f.cabinStatusBtn:ClearAllPoints()
                f.cabinStatusBtn:SetPoint("RIGHT", f.cabinSaveBtn, "LEFT", -10, 0)
            end
            f.cabinStatusBtn.text:SetText(ns:T("|cffffb800[未保存] 编组已变更|r"))
        else
            if f.cabinSaveBtn then f.cabinSaveBtn:Hide() end
            if f.cabinRevertBtn then f.cabinRevertBtn:Hide() end
            if f.cabinStatusBtn._lastDirtyMode ~= false then
                f.cabinStatusBtn._lastDirtyMode = false
                f.cabinStatusBtn:ClearAllPoints()
                f.cabinStatusBtn:SetPoint("TOPRIGHT", f.homeView.cabin, "TOPRIGHT", -22, -14)
            end

            if hasTeamMissing then
                if ns.locale == "zhTW" then
                    f.cabinStatusBtn.text:SetText(ns:TF("|cffff4040[缺寵] 當前隊伍缺失 %d 隻寵物 (已虛擬展示)|r", #teamMissingList))
                else
                    f.cabinStatusBtn.text:SetText(ns:TF("|cffff4040[缺宠] 当前队伍缺失 %d 只宠物 (已虚拟展示)|r", #teamMissingList))
                end
            elseif deadSlotCount > 0 then
                if ns.locale == "zhTW" then
                    f.cabinStatusBtn.text:SetText(ns:TF("|cffff4040[陣亡警告] 當前出戰編組有 %d 隻寵物已陣亡！|r", deadSlotCount))
                else
                    f.cabinStatusBtn.text:SetText(ns:TF("|cffff4040[阵亡警告] 当前出战编组有 %d 只宠物已阵亡！|r", deadSlotCount))
                end
            elseif liveUnderLvCount > 0 or audit.hasUnderLv then
                local cnt = math.max(liveUnderLvCount, #audit.underLvList)
                if ns.locale == "zhTW" then
                    f.cabinStatusBtn.text:SetText(ns:TF("|cffff9900[注意] 非練級欄位包含 %d 隻未滿 25 級寵物！|r", cnt))
                else
                    f.cabinStatusBtn.text:SetText(ns:TF("|cffff9900[注意] 非练级槽包含 %d 只未满 25 级宠物！|r", cnt))
                end
            else
                f.cabinStatusBtn.text:SetText(ns:T("|cff10b981[就绪] 自动化执行就绪|r"))
            end
        end
    end

    if ns.PetPickerModal and ns.PetPickerModal:IsShown() and ns.PetPickerModal.RefreshDirtyHeader then
        ns.PetPickerModal:RefreshDirtyHeader()
    end
end

function ns:RefreshHomeView()
    self:RefreshLoadoutCabin()
end

local function RotateCabinSlotModel(self)
    local cx = GetCursorPosition()
    if self._model then
        self._model:SetFacing(self.startRot + (cx - self.startX) * 0.015)
    end
end

function ns:InitHomeView(f, header)
    local px = Theme:GetPixelScale()
    local homeView = CreateFrame("Frame", nil, f)
    homeView:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    homeView:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f.homeView = homeView

    ns.db.activeTargetSlot = nil

    local cabin = CreateFrame("Frame", nil, homeView, "BackdropTemplate")
    cabin:SetPoint("TOPLEFT", 20, -16)
    cabin:SetPoint("BOTTOMRIGHT", -20, 18)
    cabin:EnableMouse(true)
    cabin:SetScript("OnMouseDown", function()
        if ns.db.activeTargetSlot ~= nil then
            ns.db.activeTargetSlot = nil
            ns:RefreshLoadoutCabin()
        end
    end)
    Theme:ApplyBackdrop(cabin, { 0.067, 0.067, 0.067, 0.90 }, Theme.Colors.border, true)
    homeView.cabin = cabin

    -- Text-only target link: deliberately has no backdrop or button border.
    local cabinTargetBtn = CreateFrame("Button", nil, cabin)
    cabinTargetBtn:SetSize(420, 24)
    cabinTargetBtn:SetPoint("TOPLEFT", 22, -13)
    cabinTargetBtn:RegisterForClicks("LeftButtonUp")
    cabinTargetBtn.icon = cabinTargetBtn:CreateTexture(nil, "ARTWORK")
    cabinTargetBtn.icon:SetSize(24, 24)
    cabinTargetBtn.icon:SetPoint("LEFT", 0, 0)
    Theme:ConfigureButtonIcon(cabinTargetBtn.icon, "Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Status\\current-target.tga")
    cabinTargetBtn.icon:SetAlpha(1)
    cabinTargetBtn.text = cabinTargetBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Theme:HookLocalizedFontString(cabinTargetBtn.text)
    cabinTargetBtn.text:SetTextColor(0.58, 0.67, 0.77, 1)
    cabinTargetBtn.text:SetPoint("LEFT", cabinTargetBtn.icon, "RIGHT", 6, 0)
    cabinTargetBtn.text:SetPoint("RIGHT", -2, 0)
    cabinTargetBtn.text:SetJustifyH("LEFT")
    cabinTargetBtn.text:SetWordWrap(false)
    cabinTargetBtn:SetScript("OnClick", function(_, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        local index = ns.db.selectedTeamIdx
        local team = ns.db.teams[index]
        if team then ns:ShowTeamBuilderModal(nil, team.group, index) end
    end)
    cabinTargetBtn:HookScript("OnEnter", function(button)
        if not button:IsEnabled() then return end
        button.icon:SetAlpha(1)
        GameTooltip:SetOwner(button, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(button.text:GetText())
        GameTooltip:AddLine(ns:T("点击编辑当前队伍"), 0.70, 0.82, 0.95)
        GameTooltip:Show()
    end)
    cabinTargetBtn:HookScript("OnLeave", function(button)
        button.icon:SetAlpha(0.85)
        if GameTooltip:GetOwner() == button then GameTooltip:Hide() end
    end)
    f.cabinTargetBtn = cabinTargetBtn

    local cabinRevertBtn = Theme:CreateActionButton(cabin, 30, 22, "撤销修改", "restore", "撤销当前队伍未保存的修改", nil, true)
    cabinRevertBtn:SetPoint("TOPRIGHT", cabin, "TOPRIGHT", -22, -14)
    cabinRevertBtn:SetScript("OnClick", function()
        ns:RevertCurrentTeamToDefault()
    end)
    cabinRevertBtn:Hide()
    f.cabinRevertBtn = cabinRevertBtn

    local cabinSaveBtn = Theme:CreateActionButton(cabin, 80, 22, "保存", "save", "保存当前队伍的修改", "PRIMARY")
    cabinSaveBtn:SetPoint("RIGHT", cabinRevertBtn, "LEFT", -6, 0)
    cabinSaveBtn:SetScript("OnClick", function()
        ns:SaveStagingToCurrentTeam()
    end)
    cabinSaveBtn:Hide()
    f.cabinSaveBtn = cabinSaveBtn

    local cabinStatusBtn = CreateFrame("Button", nil, cabin)
    cabinStatusBtn:SetSize(320, 22)
    cabinStatusBtn:SetPoint("TOPRIGHT", cabin, "TOPRIGHT", -22, -14)
    cabinStatusBtn._lastDirtyMode = false
    cabinStatusBtn.text = cabinStatusBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cabinStatusBtn.text:SetPoint("RIGHT", 0, 0)
    Theme:HookLocalizedFontString(cabinStatusBtn.text)
    cabinStatusBtn.text:SetText(ns:T("|cff10b981[就绪] 自动化执行就绪|r"))
    f.cabinStatusBtn = cabinStatusBtn

    local divLine = cabin:CreateTexture(nil, "BORDER")
    divLine:SetHeight(px)
    divLine:SetPoint("TOPLEFT", 22, -46)
    divLine:SetPoint("TOPRIGHT", -22, -46)
    divLine:SetTexture("Interface\\Buttons\\WHITE8X8")
    divLine:SetVertexColor(unpack(Theme.Colors.divider))

    f.loadoutCards = {}
    local cardWidth = 332
    local cardHeight = 460
    local cardGap = 20

    for slot = 1, 3 do
        local card = CreateFrame("Button", nil, cabin, "BackdropTemplate")
        card:SetSize(cardWidth, cardHeight)
        card:SetPoint("TOPLEFT", 22 + (slot - 1) * (cardWidth + cardGap), -60)
        card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        Theme:ApplyBackdrop(card, CABIN_BG_NORMAL, Theme.Colors.border, false)

        local modelBox = CreateFrame("Button", nil, card)
        modelBox:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        modelBox:SetSize(300, 188)
        modelBox:SetPoint("TOP", card, "TOP", 0, -16)
        card.modelBox = modelBox

        local model = CreateFrame("PlayerModel", nil, modelBox)
        model:SetAllPoints(modelBox)
        model:SetRotation(0.35)
        model:HookScript("OnHide", function(self)
            self._lastDisplayID = nil
        end)
        modelBox._model = model
        card.model = model

        local deadOverlay = CreateFrame("Frame", nil, card)
        deadOverlay:SetAllPoints(modelBox)
        deadOverlay:SetFrameLevel(model:GetFrameLevel() + 3)
        deadOverlay:EnableMouse(false)
        local deadTint = deadOverlay:CreateTexture(nil, "ARTWORK")
        deadTint:SetAllPoints(deadOverlay)
        deadTint:SetTexture("Interface\\Buttons\\WHITE8X8")
        deadTint:SetVertexColor(0.20, 0.02, 0.03, 0.50)
        deadOverlay:Hide()
        card.deadOverlay = deadOverlay

        local deadBanner = CreateFrame("Frame", nil, card, "BackdropTemplate")
        deadBanner:SetSize(232, 46)
        deadBanner:SetPoint("CENTER", modelBox, "CENTER", 0, 0)
        deadBanner:SetFrameLevel(model:GetFrameLevel() + 8)
        deadBanner:EnableMouse(false)
        Theme:ApplyBackdrop(deadBanner, { 0.28, 0.03, 0.05, 0.96 }, Theme.Colors.borderRed, false)

        local deadTitle = deadBanner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        deadTitle:SetPoint("TOP", 0, -7)
        local dfPath = deadTitle:GetFont()
        if dfPath then deadTitle:SetFont(dfPath, 14, "OUTLINE") end
        Theme:HookLocalizedFontString(deadTitle)
        deadTitle:SetText(ns:T("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:15:15:0:0|t |cffff4040已 阵 亡  (0% HP)|r"))

        local deadSub = deadBanner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        deadSub:SetPoint("BOTTOM", 0, 6)
        Theme:HookLocalizedFontString(deadSub)
        deadSub:SetText(ns:T("|cffffb4b4点击顶栏复活或绷带恢复|r"))
        deadBanner:Hide()
        card.deadBanner = deadBanner

        local underLvBanner = CreateFrame("Frame", nil, card, "BackdropTemplate")
        underLvBanner:SetSize(156, 22)
        underLvBanner:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -14)
        underLvBanner:SetFrameLevel(model:GetFrameLevel() + 9)
        Theme:ApplyBackdrop(underLvBanner, { 0.24, 0.12, 0.02, 0.96 }, Theme.Colors.borderAmber, false)
        underLvBanner.text = underLvBanner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        underLvBanner.text:SetPoint("CENTER", 0, 0)
        Theme:HookLocalizedFontString(underLvBanner.text)
        underLvBanner:Hide()
        card.underLvBanner = underLvBanner

        local pickBtn = CreateFrame("Button", nil, card)
        pickBtn:SetSize(22, 22)
        pickBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -14)
        pickBtn:SetFrameLevel(model:GetFrameLevel() + 9)

        local pickArrow = Theme:CreateArrowTexture(pickBtn, 14, "DOWN")
        pickArrow:SetPoint("CENTER", 0, 0)
        pickArrow:SetVertexColor(0.55, 0.78, 1.0, 0.95)
        pickBtn.arrow = pickArrow

        pickBtn:SetScript("OnEnter", function()
            pickArrow:SetVertexColor(0.0, 0.95, 1.0, 1.0)
        end)
        pickBtn:SetScript("OnLeave", function()
            pickArrow:SetVertexColor(0.55, 0.78, 1.0, 0.95)
        end)
        pickBtn:SetScript("OnClick", function()
            ns.db.activeTargetSlot = slot
            ns:TogglePetPickerDrawer(slot, card.isLevelingSlot and "QUEUE" or "PETS", false)
            ns:RefreshLoadoutCabin()
        end)
        card.pickBtn = pickBtn

        local function ReceivePet()
            local cursorType = GetCursorInfo()
            if cursorType == "battlepet" or ns.draggingPetID or ns.draggingQueuePetID then
                ns.queueDropHandledBySlot = true
                ns:DropPetIntoSlot(slot)
            end
        end

        local function ClickSlot(_, button)
            local petID = card.petData and card.petData.petID
            if HandlePetSpellClick(button, petID) then return end

            ns.db.activeTargetSlot = slot
            ns:RefreshLoadoutCabin()
            if button == "RightButton" then
                ns:ShowSlotThresholdMenu(card, slot)
            elseif GetCursorInfo() == "battlepet" then
                ReceivePet()
            end
        end

        local function StartSlotDrag(self)
            if IsPetSpellTargeting() or GetCursorInfo() or InCombatLockdown() or C_PetBattles.IsInBattle() then return end
            if self == modelBox and IsShiftKeyDown() then
                self.startX = GetCursorPosition()
                self.startRot = model:GetFacing() or 0.35
                self:SetScript("OnUpdate", RotateCabinSlotModel)
                return
            end

            local petID = C_PetJournal.GetPetLoadOutInfo(slot)
            if not petID or not card.petData or card.petData.petID ~= petID then return end
            C_PetJournal.PickupPet(petID)
            local cursorType, cursorPetID = GetCursorInfo()
            if cursorType == "battlepet" and cursorPetID == petID then
                ns:HideAllPopups()
                ns.loadoutSlotDrag = { slot = slot, petID = petID }
                ns:UpdateLoadoutSlotDragVisuals()
            end
        end

        card:RegisterForDrag("LeftButton")
        modelBox:RegisterForDrag("LeftButton")
        card:SetScript("OnDragStart", StartSlotDrag)
        modelBox:SetScript("OnDragStart", StartSlotDrag)
        modelBox:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
        end)
        modelBox:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
        end)
        modelBox:SetScript("OnClick", ClickSlot)
        modelBox:SetScript("OnReceiveDrag", ReceivePet)

        local titleTxt = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        titleTxt:SetPoint("TOPLEFT", 16, -218)
        titleTxt:SetPoint("TOPRIGHT", -16, -218)
        titleTxt:SetJustifyH("LEFT")
        titleTxt:SetWordWrap(false)
        Theme:HookLocalizedFontString(titleTxt)
        card.titleTxt = titleTxt

        local subTxt = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        subTxt:SetPoint("TOPLEFT", titleTxt, "BOTTOMLEFT", 0, -6)
        subTxt:SetPoint("TOPRIGHT", -16, -242)
        subTxt:SetJustifyH("LEFT")
        subTxt:SetWordWrap(false)
        Theme:HookLocalizedFontString(subTxt)
        card.subTxt = subTxt

        local barLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        barLabel:SetPoint("TOPLEFT", 16, -276)
        Theme:HookLocalizedFontString(barLabel)
        card.barLabel = barLabel

        local barBg = CreateFrame("Frame", nil, card, "BackdropTemplate")
        barBg:SetSize(300, 10)
        barBg:SetPoint("TOPLEFT", 16, -296)
        Theme:ApplyBackdrop(barBg, { 0.13, 0.13, 0.13, 0.95 }, Theme.Colors.border, false)

        local syncBar = CreateFrame("StatusBar", nil, barBg)
        local function UpdateBarInset()
            local pScale = Theme:GetPixelScale(barBg)
            if barBg._lastInsetPx == pScale then return end
            barBg._lastInsetPx = pScale
            syncBar:ClearAllPoints()
            syncBar:SetPoint("TOPLEFT", barBg, "TOPLEFT", pScale, -pScale)
            syncBar:SetPoint("BOTTOMRIGHT", barBg, "BOTTOMRIGHT", -pScale, pScale)
        end
        UpdateBarInset()
        barBg:HookScript("OnShow", UpdateBarInset)
        syncBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        syncBar:SetMinMaxValues(0, 100)
        syncBar:SetValue(100)
        card.syncBar = syncBar

        card.abBtns = {}
        local abBtnW = 94
        local abBtnH = 38
        local abColGap = 9
        local abRowGap = 8

        for idx = 1, 6 do
            local row = math.floor((idx - 1) / 3)
            local col = (idx - 1) % 3
            local abBtn = CreateFrame("Button", nil, card, "BackdropTemplate")
            abBtn:SetSize(abBtnW, abBtnH)
            abBtn:SetPoint("TOPLEFT", 16 + col * (abBtnW + abColGap), -318 - row * (abBtnH + abRowGap))
            abBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            Theme:ApplyBackdrop(abBtn, AB_BG_NORM_UNSEL, Theme.Colors.border, false)

            local tex = abBtn:CreateTexture(nil, "ARTWORK")
            tex:SetSize(30, 30)
            tex:SetPoint("LEFT", 4, 0)
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            Theme:SnapTextureToPixel(tex)
            abBtn.icon = tex

            local nameTxt = abBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nameTxt:SetPoint("LEFT", tex, "RIGHT", 5, 0)
            nameTxt:SetPoint("RIGHT", -4, 0)
            nameTxt:SetJustifyH("LEFT")
            nameTxt:SetWordWrap(false)
            Theme:HookLocalizedFontString(nameTxt)
            abBtn.nameTxt = nameTxt

            abBtn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(unpack(Theme.Colors.borderBlue))
                if self.abID and self.abID > 0 then
                    local p = card.petData
                    ns:ShowAbilityTooltip(self, self.abID, p and p.maxHealth or 1400, p and p.power or 280, p and p.speed or 280)
                end
            end)
            abBtn:SetScript("OnLeave", function(self)
                if self.isSelected then
                    local isDead = (card.petData and card.petData.isDead == true)
                    self:SetBackdropBorderColor(unpack(isDead and Theme.Colors.borderRed or Theme.Colors.borderBlue))
                else
                    self:SetBackdropBorderColor(unpack(Theme.Colors.border))
                end
                ns:HideAbilityTooltip()
            end)
            abBtn:SetScript("OnClick", function(self, button)
                ns.db.activeTargetSlot = slot
                if button == "RightButton" and self.abID and ns.ScriptEditBox and ns.ScriptWorkspaceModal and ns.ScriptWorkspaceModal:IsShown() then
                    local abName = C_PetJournal.GetPetAbilityInfo(self.abID)
                    if abName then
                        ns.ScriptEditBox:Insert(string.format("use(%s:%d)\n", abName, self.abID))
                    end
                elseif self.abID and self.abCol then
                    ns:EnsureTeamBackup()
                    if not InCombatLockdown() and not (C_PetBattles and C_PetBattles.IsInBattle()) then
                        ns._equippingUntil = GetTime() + 0.35
                        C_PetJournal.SetAbility(slot, self.abCol, self.abID)
                    end
                    ns.staging.isDirty = true
                    C_Timer.After(0.05, function() ns:RefreshLoadoutCabin() end)
                    ns:RefreshLoadoutCabin()
                end
            end)

            card.abBtns[idx] = abBtn
        end

        local thresholdBadge = CreateFrame("Button", nil, card)
        thresholdBadge:SetSize(52, 22)
        thresholdBadge:SetPoint("TOPLEFT", 14, -14)
        thresholdBadge:SetFrameLevel(model:GetFrameLevel() + 9)
        thresholdBadge.text = thresholdBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        thresholdBadge.text:SetPoint("LEFT", 0, 0)
        Theme:HookLocalizedFontString(thresholdBadge.text)
        thresholdBadge:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
            GameTooltip:SetText(ns:T("生命值不足时换宠"), 1, 0.72, 0)
            GameTooltip:AddLine(ns:TF("生命值保护：<= %s 时换宠（右键修改）", self.label), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        local function HideThresholdTooltip(self)
            if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
        end
        thresholdBadge:SetScript("OnLeave", HideThresholdTooltip)
        thresholdBadge:SetScript("OnHide", HideThresholdTooltip)
        thresholdBadge:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        thresholdBadge:SetScript("OnClick", function()
            ns:ShowSlotThresholdMenu(card, slot)
        end)
        thresholdBadge:Hide()
        card.thresholdBadge = thresholdBadge

        local footerTxt = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        footerTxt:SetPoint("BOTTOMLEFT", 16, 18)
        footerTxt:SetPoint("BOTTOMRIGHT", -16, 18)
        footerTxt:SetJustifyH("LEFT")
        Theme:HookLocalizedFontString(footerTxt)
        card.footerTxt = footerTxt

        card:SetScript("OnReceiveDrag", ReceivePet)
        card:SetScript("OnClick", ClickSlot)

        -- 独立的非交互覆盖层，避免模型/技能按钮遮挡换位提示。
        local dragOverlay = CreateFrame("Frame", nil, card, "BackdropTemplate")
        dragOverlay:SetAllPoints(card)
        dragOverlay:SetFrameLevel(model:GetFrameLevel() + 20)
        dragOverlay:EnableMouse(false)
        dragOverlay:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 3,
        })
        local dragBanner = CreateFrame("Frame", nil, dragOverlay, "BackdropTemplate")
        dragBanner:SetSize(304, 46)
        dragBanner:SetPoint("CENTER", modelBox, "CENTER", 0, 0)
        dragBanner:EnableMouse(false)
        Theme:ApplyBackdrop(dragBanner, { 0.043, 0.043, 0.043, 0.96 }, Theme.Colors.borderBlue, false)
        dragOverlay.text = dragBanner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dragOverlay.text:SetPoint("LEFT", 8, 0)
        dragOverlay.text:SetPoint("RIGHT", -8, 0)
        Theme:HookLocalizedFontString(dragOverlay.text)
        dragOverlay:Hide()
        card.dragOverlay = dragOverlay

        f.loadoutCards[slot] = card
    end
end
