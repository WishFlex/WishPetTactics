local ADDON_NAME, ns = ...
local Theme = ns.Theme

-- V4 同页布局。此文件在原 Home/View.lua 后加载：将原「全部管理 (TeamMatrixModal)」
-- 完整合并入左侧「队伍管理」标签页，并支持练级队列鼠标点击拖拽换序。
local PANEL_BG = { 0.062, 0.062, 0.062, 0.96 }
local ROW_BG = { 0.103, 0.103, 0.103, 0.92 }
local ROW_SELECTED = { 0.152, 0.152, 0.152, 0.98 }
local DOWN_CHEVRON = " |TInterface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Common\\down.tga:10:10:0:0|t"
local CARD_BG = { 0.088, 0.088, 0.088, 0.96 }
local MUTED = { 0.56, 0.66, 0.77 }
local CYAN = { 0.10, 0.87, 1.00 }
local AMBER = { 0.98, 0.68, 0.18 }
local MAX_VISIBLE = 8
local COLS = 2
local ROW_W, ROW_H, ROW_STEP, COL_STEP = 334, 94, 104, 344
local RIGHT_CARD_W, RIGHT_CARD_H = 320, 132
local RIGHT_CARD_STEP = 142
local EMPTY_PET_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local EMPTY_USED_PETS = {}
local QUALITY_NAMES = { "粗糙", "普通", "优秀", "精良", "史诗", "传说" }
local QUALITY_HEX_COLORS = { "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000" }
local LV_ICON = "Interface\\Icons\\INV_Pet_Achievement_RaiseAPetLevel_25"

local function T(text) return ns:T(text) end
local function IsInBattle()
    return InCombatLockdown() or (C_PetBattles and C_PetBattles.IsInBattle())
end

local HEADER_TEX_ROOT = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Header\\"
local ACTION_TEX_ROOT = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Actions\\"
local STATUS_TEX_ROOT = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Status\\"

local function MakeLink(parent, label, width, onClick, align, iconPath)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 24)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local effAlign = align or "LEFT"
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if iconPath then
        local ic = b:CreateTexture(nil, "ARTWORK")
        Theme:ConfigureButtonIcon(ic, iconPath)
        ic:SetAlpha(1)
        b.icon = ic
    else
        b.text:SetPoint("LEFT", 1, 0)
        b.text:SetPoint("RIGHT", -1, 0)
    end
    b.text:SetJustifyH(effAlign)
    b.text:SetWordWrap(false)
    b.text:SetText(T(label))
    b.text:SetTextColor(unpack(MUTED))
    Theme:HookLocalizedFontString(b.text)
    b.underline = b:CreateTexture(nil, "ARTWORK")
    b.underline:SetTexture("Interface\\Buttons\\WHITE8X8")
    b.underline:SetVertexColor(unpack(CYAN))
    b.underline:SetHeight(1)
    local function ShouldHideUnderline()
        return b._noUnderline or Theme:IsIconOrSymbolOnlyText(b.text:GetText())
    end
    local function SyncUnderlineWidth()
        if b.icon then Theme:LayoutLinkIcon(b, effAlign) end
        if ShouldHideUnderline() then
            b.underline:Hide()
            return
        end
        local extW = b.icon and (b.icon:GetWidth() + 4) or 0
        Theme:AnchorStandardUnderline(b.underline, b, b.text, effAlign, extW)
    end
    hooksecurefunc(b.text, "SetText", SyncUnderlineWidth)
    if b.icon then Theme:RegisterInlineIconMetrics(b, SyncUnderlineWidth)
    else SyncUnderlineWidth() end
    b.underline:Hide()
    b:SetScript("OnEnter", function(self)
        self.text:SetTextColor(0.95, 0.98, 1)
        if not ShouldHideUnderline() then
            SyncUnderlineWidth()
            self.underline:Show()
        else
            self.underline:Hide()
        end
    end)
    b:SetScript("OnLeave", function(self)
        if self.selected then return end
        self.text:SetTextColor(unpack(MUTED))
        self.underline:Hide()
    end)
    b:SetScript("OnClick", onClick)
    function b:SetActive(active)
        self.selected = active
        if ShouldHideUnderline() then
            self.underline:Hide()
        else
            SyncUnderlineWidth()
            self.underline:SetShown(active)
        end
        if active then self.text:SetTextColor(0.95, 0.98, 1)
        else self.text:SetTextColor(unpack(MUTED)) end
    end
    return b
end

local function SetLinkTip(button, message)
    button:HookScript("OnEnter", function(self)
        local label = message(self)
        if not label or label == "" then return end
        ns:ShowCustomTooltip(self, "ANCHOR_TOP", label)
    end)
    button:HookScript("OnLeave", function(self)
        ns:HideCustomTooltip(self)
    end)
end

local function MakeRule(parent, y)
    local tex = parent:CreateTexture(nil, "BORDER")
    tex:SetHeight(1)
    tex:SetPoint("TOPLEFT", 16, y)
    tex:SetPoint("TOPRIGHT", -16, y)
    tex:SetColorTexture(0.223, 0.223, 0.223, 0.88)
    return tex
end

local function MakeBar(parent, width)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(width, 2)
    bg:SetColorTexture(0.23, 0.23, 0.23, 0.85)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(width, 2)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    return bg, bar
end

local function SetBar(bar, pct, dead)
    bar:SetValue(math.max(0, math.min(100, pct or 0)))
    if ns.ApplyHealthBarColor then
        ns:ApplyHealthBarColor(bar, pct or 0, dead == true)
    end
end

local function ShowPetTip(owner, data, isPinned)
    if data and ns.ShowPetDetailTooltip then
        if ns.isReorderingQueueList then return end
        if isPinned and ns.PetCardModal then
            ns.PetCardModal.isPinned = false
        end
        ns:ShowPetDetailTooltip(owner, data, isPinned == true)
    end
end
local function HidePetTip(force)
    if ns.HidePetDetailTooltip then ns:HidePetDetailTooltip(force == true) end
end

local function GetRightPetData(petID)
    if not petID or type(petID) ~= "string" then return nil end
    local speciesID, customName, level, xp, maxXp, displayID, favorite, name, icon, petType = C_PetJournal.GetPetInfoByPetID(petID)
    if not speciesID then return nil end
    local hp, maxHp, power, speed, rarity = C_PetJournal.GetPetStats(petID)
    hp, maxHp = hp or 0, math.max(1, maxHp or 1)
    return {
        petID = petID, speciesID = speciesID, name = (customName and customName ~= "" and customName) or name or T("未知宠物"),
        level = level or 1, xp = xp or 0, maxXp = maxXp or 100, displayID = displayID,
        icon = icon or EMPTY_PET_ICON, petType = petType or 1, isFavorite = favorite and true or false,
        isCollected = true, health = hp, maxHealth = maxHp, hpPct = math.floor(hp / maxHp * 100),
        isDead = hp <= 0, power = power or 0, speed = speed or 0, rarity = rarity or 1,
        breed = ns.SearchFilter:GetPetBreed(petID, speciesID, maxHp, power or 0, speed or 0, level or 1, rarity or 1) or "B/B",
    }
end

-- O(1) 极速读取队伍槽位图标与系别水印
local function GetTeamSlotIconFast(team, slot, isCurrentTeam)
    local lvSlot = team.levelingSlot or (ns.db and ns.db.settings.levelingSlot) or 2
    if (team.hasLevelingSlot and lvSlot == slot) or (team.pets and team.pets[slot] == "LEVELING") then
        return true, LV_ICON, nil, false
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

local function GetTeamSlotPetData(team, slot, isCurrentTeam)
    local lvSlot = team.levelingSlot or (ns.db and ns.db.settings.levelingSlot) or 2
    if (team.hasLevelingSlot and lvSlot == slot) or (team.pets and team.pets[slot] == "LEVELING") then
        return true, LV_ICON, nil, nil, false
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

local function RefreshBoth()
    if ns.RefreshHomeView then ns:RefreshHomeView() end
    if ns.UpdateHeaderToolButtons then ns:UpdateHeaderToolButtons() end
end

local function AddOrRemoveQueuePet(petID)
    if not petID then return end
    ns.Leveling:TogglePetInQueue(petID)
    if ns.MainFrame then ns.MainFrame.compactQueueUndo = nil end
    ns.Leveling:RefreshSelectedSlot()
    RefreshBoth()
end

local function ClearSelection(f)
    f.compactSelectedPetID = nil
    ns.db.activeTargetSlot = nil
end

local function SetLeftMode(mode)
    local f = ns.MainFrame
    if not f or not f.compactLeft then return end
    if mode == "QUEUE" and ns.Leveling:GetManualQueueCount() == 0 then mode = "PETS" end
    if f.compactAbilityPopup then f.compactAbilityPopup:Hide() end
    local left = f.compactLeft
    if left.mode ~= mode then
        if mode == "TEAMS" then ClearSelection(f) end
        left.mode, left.offset = mode, 0
        left.searchBox._clearingSearch = true
        left.searchBox:SetText("")
        left.searchBox._clearingSearch = nil
        if left.searchPlaceholder then left.searchPlaceholder:Show() end
        left.searchBox:ClearFocus()
    end
    if mode == "TEAMS" then ns:RefreshLoadoutCabin()
    else ns:RefreshCompactLeftPanel() end
end

-- Allow the minimal team picker and external callers to open the embedded team-management tab.
function ns:SetCompactLeftMode(mode)
    SetLeftMode(mode)
end

function ns:ShowTeamMatrixModal()
    local f = self:CreateMainFrame()
    if self.HideAllPopups then self:HideAllPopups() end
    if not f:IsShown() then f:Show() end
    if self.SetMainUIStyle then self:SetMainUIStyle("FULL") end
    SetLeftMode("TEAMS")
end

function ns:ToggleTeamMatrixModal()
    local f = self.MainFrame
    if f and f:IsShown() and f.mainUIStyle ~= "MINIMAL" and f.compactLeft and f.compactLeft.mode == "TEAMS" then
        self:RequestMainFrameClose()
    else
        self:ShowTeamMatrixModal()
    end
end

-- ==================== 练级队列内嵌拖拽排序逻辑 ====================
function ns:UpdateCompactQueueDragVisuals()
    local f = self.MainFrame
    local left = f and f.compactLeft
    if not left or not left:IsShown() or left.mode ~= "QUEUE" then return end
    local srcPetID = ns.draggingQueuePetID
    local hoveredRow = nil
    if srcPetID then
        for i = 1, MAX_VISIBLE do
            local r = left.rows[i]
            if r and r:IsShown() and r.itemData and r:IsMouseOver() then
                hoveredRow = r
                break
            end
        end
    end
    for i = 1, MAX_VISIBLE do
        local r = left.rows[i]
        if r and r:IsShown() and r.itemData then
            local isSrc = srcPetID and r.itemData.petID == srcPetID
            local isTarget = hoveredRow == r and not isSrc
            if isSrc then
                r:SetAlpha(0.45)
                r:SetBackdropBorderColor(unpack(Theme.Colors.borderAmber))
            elseif isTarget then
                r:SetAlpha(1.0)
                r:SetBackdropBorderColor(unpack(Theme.Colors.borderBlue))
            else
                r:SetAlpha(1.0)
                if r.selected then
                    r:SetBackdropBorderColor(unpack(Theme.Colors.borderBlue))
                else
                    r:SetBackdropBorderColor(unpack(Theme.Colors.border))
                end
            end
        elseif r then
            r:SetAlpha(1.0)
        end
    end
end

function ns:FinishCompactQueueDrag(explicitTargetRow)
    local srcPetID = ns.draggingQueuePetID
    if not srcPetID then return false end
    local f = self.MainFrame
    local left = f and f.compactLeft
    if not left or not left:IsShown() or left.mode ~= "QUEUE" then return false end

    local targetRow = explicitTargetRow
    if not targetRow then
        for i = 1, MAX_VISIBLE do
            local r = left.rows[i]
            if r and r:IsShown() and r.itemData and r:IsMouseOver() then
                targetRow = r
                break
            end
        end
    end

    if not targetRow or not targetRow.itemData or not targetRow.itemData.petID then
        self:UpdateCompactQueueDragVisuals()
        return false
    end

    local dstPetID = targetRow.itemData.petID
    ns.isReorderingQueueList = false
    ns.draggingQueuePetID = nil
    ns.draggingPetID = nil
    if GetCursorInfo and GetCursorInfo() == "battlepet" then
        ClearCursor()
    end
    self:UpdateLoadoutSlotDragVisuals()

    if dstPetID ~= srcPetID then
        ns.Leveling:ReorderQueueByDrag(srcPetID, dstPetID, nil, left.searchBox:GetText() or "")
    end
    RefreshBoth()
    return true
end

local function PutDraftPet(draft, slot, petID)
    if draft.slots[slot] and draft.slots[slot].petID == petID then return true end
    for from, entry in pairs(draft.slots) do
        if entry.petID == petID then
            draft.slots[from], draft.slots[slot] = draft.slots[slot], entry
            return true
        end
    end
    local species, _, _, _, _, _, _, _, _, _, _, _, _, _, canBattle = C_PetJournal.GetPetInfoByPetID(petID)
    if canBattle == false then return false end
    local ids = ns:GetSortedPetAbilities(species)
    if not ids then return false end
    draft.slots[slot] = { petID = petID, abilities = {ids[1], ids[2], ids[3]} }
    return true
end

function ns:PutCompactPet(slot, petID, fromQueue)
    local f = self.MainFrame
    if not f or not petID or IsInBattle() then return false end
    if f.compactAbilityPopup then f.compactAbilityPopup:Hide() end
    local draft = f.compactDraft
    if draft then
        local _, _, _, _, locked = C_PetJournal.GetPetLoadOutInfo(slot)
        if locked or (fromQueue and not self.Leveling:IsPetInQueue(petID)) then
            self:PrintError(T("无法将此宠物放入该槽位"))
            return false
        end
        if not fromQueue and not PutDraftPet(draft, slot, petID) then return false end
        if fromQueue then draft.levelingSlot = slot
        elseif draft.levelingSlot == slot then draft.levelingSlot = nil end
    else
        if not self:DropPetIntoSlot(slot, petID, fromQueue, true) then return false end
    end
    ClearSelection(f)
    RefreshBoth()
    if self.ShowUIFeedback then
        if draft then
            self:ShowUIFeedback(self:UXText("petChosen"))
        else
            self:ShowUIFeedback(self:TF("队伍宠物已更新：第 %d 位", slot))
        end
    end
    return true
end

function ns:BeginCompactTeamDraft()
    local f = self.MainFrame
    if not f or not f:IsShown() then self:ShowTeamBuilderModal(nil, "未分组队伍"); return end
    self:RequestHomeAction(function()
        if IsInBattle() then self:PrintError(T("战斗中无法更改编组")); return end
        ClearSelection(f)
        if self.SetMainUIStyle then self:SetMainUIStyle("FULL") end
        if self.RoutingModal then self.RoutingModal:Hide() end
        f.compactDraft = { slots = {} }
        f.compactTeamLink:Hide()
        f.compactName:SetText("")
        f.compactName:Show()
        SetLeftMode("PETS")
        RefreshBoth()
        f.compactName:SetFocus()
    end)
end

local function EndDraft(f)
    f.compactDraft = nil
    f.compactName:ClearFocus()
    f.compactName:Hide()
    f.compactTeamLink:Show()
    ClearSelection(f)
    if f.compactAbilityPopup then f.compactAbilityPopup:Hide() end
end

local function SaveDraft(f)
    local draft = f.compactDraft
    local name = strtrim(f.compactName:GetText() or "")
    if name == "" then
        ns:PrintError(T("请输入队伍名称"))
        f.compactName:SetFocus()
        return false
    end
    local team = {
        name = ns:GetUniqueTeamNameForImport(name), group = ns:EnsureTeamGroup("未分组队伍"),
        npcID = 0, npcName = "", gossipIndex = 1, pets = {}, speciesLoadout = {0, 0, 0},
        abilities = {{0, 0, 0}, {0, 0, 0}, {0, 0, 0}}, slotThresholds = {0, 0, 0},
        hasLevelingSlot = draft.levelingSlot ~= nil, levelingSlot = draft.levelingSlot or 2,
        manualAbilities = true, explicitSlots = true, script = ns:GetDefaultBattleScript(),
    }
    for slot, entry in pairs(draft.slots) do
        local species = C_PetJournal.GetPetInfoByPetID(entry.petID)
        if not species then
            ns:PrintError(T("缺失宠物"))
            return false
        end
        team.pets[slot], team.speciesLoadout[slot] = entry.petID, species
        team.abilities[slot] = ns.AutoRouting:ValidateAbilitiesForSpecies(species, entry.abilities)
    end
    if team.hasLevelingSlot then
        ns.Leveling:CaptureSlotFallback(team, team.levelingSlot, true)
        team.pets[team.levelingSlot], team.speciesLoadout[team.levelingSlot] = "LEVELING", 0
    end
    table.insert(ns.db.teams, team)
    ns.db.selectedTeamIdx = #ns.db.teams
    EndDraft(f)
    ns:MarkRoutesDirty()
    if not IsInBattle() then ns.AutoRouting:ApplyTeamData(team) end
    RefreshBoth()
    if ns.ShowUIFeedback then ns:ShowUIFeedback(ns:UXText("created")) end
    return true
end

function ns:RequestHomeAction(action)
    local f = self.MainFrame
    if not f or not f:IsShown() or not (f.compactDraft or self.staging.isDirty) then
        action()
        return
    end
    local prompt = f.compactSwitchPrompt
    if not prompt:IsShown() then
        self:HideAllPopups()
        if f.compactAbilityPopup then f.compactAbilityPopup:Hide() end
        if f.compactName:HasFocus() then f.compactName:ClearFocus() end
        prompt.pendingAction = action
        prompt:Show()
    end
end

function ns:RequestCompactTeamSwitch(index, after)
    local team = self.db.teams[index]
    if not team then return end
    if not self.MainFrame or not self.MainFrame.compactDraft then
        if index == self.db.selectedTeamIdx then
            if after then after() end
            return
        end
    end
    self:RequestHomeAction(function()
        if IsInBattle() then self:PrintError(T("战斗中无法更改编组")); return end
        local previousIndex = self.db.selectedTeamIdx
        for currentIndex, currentTeam in ipairs(self.db.teams) do
            if currentTeam == team then
                if self.MainFrame then ClearSelection(self.MainFrame) end
                self.db.selectedTeamIdx = currentIndex
                self.AutoRouting:ApplyTeamData(team)
                if currentIndex ~= previousIndex and self.ShowUIFeedback then
                    self:ShowUIFeedback(self:TF("已切换队伍：%s", team.name or ""))
                end
                if after then after() end
                return
            end
        end
    end)
end

function ns:OpenCompactTeamEditor(index)
    local team = self.db.teams[index]
    if not team then return end
    if not self.MainFrame or not self.MainFrame:IsShown() then
        self:ShowTeamBuilderModal(nil, team.group, index)
        return
    end
    self:RequestCompactTeamSwitch(index, function()
        if IsInBattle() then self:PrintError(T("战斗中无法更改编组")); return end
        if self.SetMainUIStyle then self:SetMainUIStyle("FULL") end
        SetLeftMode("PETS")
        local f = self.MainFrame
        f.compactSelectedPetID = nil
        self.db.activeTargetSlot = 1
        RefreshBoth()
    end)
end

function ns:CancelCompactInteraction()
    local f = self.MainFrame
    if not f or not f.compactLeft then return false end
    if f.compactSwitchPrompt:IsShown() then
        f.compactSwitchPrompt:Hide()
    elseif f.compactAbilityPopup and f.compactAbilityPopup:IsShown() then
        f.compactAbilityPopup:Hide()
    elseif self.CancelMinimalInteraction and self:CancelMinimalInteraction() then
        return true
    elseif f.compactSelectedPetID or self.db.activeTargetSlot then
        ClearSelection(f)
        RefreshBoth()
    else
        return false
    end
    return true
end

local function MakePetRow(parent, index)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(ROW_W, ROW_H)
    row:SetPoint("TOPLEFT", 0 + ((index - 1) % COLS) * COL_STEP, -math.floor((index - 1) / COLS) * ROW_STEP)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:RegisterForDrag("LeftButton")
    Theme:ApplyBackdrop(row, ROW_BG, Theme.Colors.border, false)
    row:SetClipsChildren(true)
    row.typeBg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.typeBg:SetSize(ROW_H, ROW_H)
    row.typeBg:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.typeBg:SetAlpha(0.14)
    row.typeBg:Hide()
    row.groupArrow = row:CreateTexture(nil, "ARTWORK")
    row.groupArrow:SetSize(12, 12)
    row.groupArrow:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.groupArrow:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Common\\down.tga")
    row.groupArrow:SetVertexColor(0.22, 0.74, 0.97, 1)
    row.groupArrow:Hide()
    row.groupCount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.groupCount:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    row.groupCount:SetJustifyH("RIGHT")
    Theme:HookLocalizedFontString(row.groupCount)
    row.groupCount:Hide()

    -- 队伍管理模式下的 3 个等比 1:1 种类水印与 3 个可交互宠物图标
    row.typeWatermarks = {}
    for s = 1, 3 do
        local wm = Theme:CreateWatermarkPetTypeTex(row, 32, 32)
        wm:SetPoint("RIGHT", -6 - (3 - s) * 34, 0)
        wm:Hide()
        row.typeWatermarks[s] = wm
    end

    row.teamPetBtns = {}
    for s = 1, 3 do
        local pBtn = Theme:CreateCroppedIcon(row, 28)
        pBtn:SetPoint("RIGHT", -118 - (3 - s) * 32, 0)
        pBtn:EnableMouse(true)
        pBtn.slotIdx = s
        pBtn.parentRow = row

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
                if pData then ShowPetTip(selfBtn, pData, false) end
            end
        end)
        pBtn:SetScript("OnLeave", function()
            HidePetTip(false)
        end)
        pBtn:SetScript("OnMouseUp", function(selfBtn, button)
            local node = selfBtn.parentRow.node
            if button == "RightButton" and node and node.nodeType == "TEAM" then
                ns:ShowSlotThresholdMenu(selfBtn, selfBtn.slotIdx, node.team)
            end
        end)
        pBtn:Hide()
        row.teamPetBtns[s] = pBtn
    end

    row.icon = Theme:CreateCroppedIcon(row, 54)
    row.icon:SetPoint("TOPLEFT", 12, -12)
    row.icon:EnableMouse(false)

    row.queueRankBadge = row.icon:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.queueRankBadge:SetPoint("TOPLEFT", row.icon, "TOPLEFT", 2, -2)
    local qFont = row.queueRankBadge:GetFont()
    if qFont then row.queueRankBadge:SetFont(qFont, 11, "OUTLINE") end
    row.queueRankBadge:Hide()

    row.favBadge = row.icon:CreateTexture(nil, "OVERLAY")
    row.favBadge:SetSize(20, 20)
    row.favBadge:SetPoint("TOPRIGHT", row.icon, "TOPRIGHT", 4, 4)
    if row.favBadge.SetAtlas then
        row.favBadge:SetAtlas("PetJournal-FavoritesIcon")
    end
    row.favBadge:Hide()

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.title:SetPoint("TOPLEFT", 76, -15)
    row.title:SetPoint("RIGHT", -56, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    Theme:HookLocalizedFontString(row.title)

    row.underline = row:CreateTexture(nil, "ARTWORK")
    row.underline:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.underline:SetVertexColor(unpack(CYAN))
    row.underline:SetHeight(1)
    row.underline:SetPoint("BOTTOMLEFT", row.title, "BOTTOMLEFT", 0, -2)
    row.underline:Hide()
    local function SyncRowUnderlineWidth()
        Theme:AnchorStandardUnderline(row.underline, row, row.title, "LEFT", 0)
    end
    row._SyncUnderline = SyncRowUnderlineWidth
    row.title._wishOnTextChanged = function()
        if row.underline:IsShown() then SyncRowUnderlineWidth() end
    end

    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("TOPLEFT", 76, -38)
    row.detail:SetPoint("RIGHT", -8, 0)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    Theme:HookLocalizedFontString(row.detail)
    row.healthBg, row.health = MakeBar(row, 172)
    row.healthBg:SetPoint("TOPLEFT", 76, -70)
    row.health:SetPoint("TOPLEFT", 76, -70)
    row.action = MakeLink(row, "+", 30, function()
        local data = row.itemData
        if row.mode == "TEAMS" then
            ns:ShowTeamContextMenu(row, row.teamIndex)
            return
        end
        if not data or not data.petID then return end
        if row.mode == "QUEUE" then
            AddOrRemoveQueuePet(data.petID)
        elseif row.mode == "PETS" and data.isCollected and (data.level or 25) < 25 then
            AddOrRemoveQueuePet(data.petID)
        end
    end, "CENTER")
    row.action._noUnderline = true
    row.action:SetPoint("TOPRIGHT", -7, -9)
    SetLinkTip(row.action, function()
        if row.mode == "TEAMS" then return T("队伍操作") end
        if row.mode == "QUEUE" or (row.itemData and ns.Leveling:IsPetInQueue(row.itemData.petID)) then
            return T("移出练级队列")
        end
        return T("加入练级队列")
    end)
    row:SetScript("OnEnter", function(self)
        SyncRowUnderlineWidth()
        self.underline:Show()
        if self.mode == "TEAMS" then
            self:SetBackdropColor(0, 0, 0, 0)
            self:SetBackdropBorderColor(0, 0, 0, 0)
        else
            if self.mode == "QUEUE" and ns.draggingQueuePetID then
                ns:UpdateCompactQueueDragVisuals()
            end
            ShowPetTip(self, self.itemData, false)
        end
    end)
    row:SetScript("OnLeave", function(self)
        if self.mode == "TEAMS" then
            self:SetBackdropColor(0, 0, 0, 0)
            self:SetBackdropBorderColor(0, 0, 0, 0)
            if self.selected then
                SyncRowUnderlineWidth()
                self.underline:Show()
            else
                self.underline:Hide()
            end
        else
            self.underline:Hide()
            if self.mode == "QUEUE" and ns.draggingQueuePetID then
                ns:UpdateCompactQueueDragVisuals()
            elseif not self.selected then
                self:SetBackdropBorderColor(unpack(Theme.Colors.border))
            end
            HidePetTip(false)
        end
    end)
    row:SetScript("OnClick", function(self, mouseButton)
        if self.mode == "TEAMS" then
            local node = self.node
            if not node then return end
            if node.nodeType == "GROUP" then
                if mouseButton == "RightButton" then
                    if ns.ShowMatrixGroupContextMenu then
                        ns:ShowMatrixGroupContextMenu(self, node.groupName)
                    end
                else
                    ns.db.expandedMatrixGroups = ns.db.expandedMatrixGroups or {}
                    ns.db.expandedMatrixGroups[node.groupName] = not node.expanded
                    if ns.BumpTeamTreeRevision then ns:BumpTeamTreeRevision() end
                    ns:RefreshCompactLeftPanel()
                end
                return
            elseif node.nodeType == "TARGET" then
                if mouseButton == "RightButton" then
                    if node.routeKey and ns.ShowRouteTargetContextMenu then
                        ns:ShowRouteTargetContextMenu(self, node.routeKey, node.targetKey)
                    end
                else
                    ns.db.expandedMatrixTargets = ns.db.expandedMatrixTargets or {}
                    local nextExpanded = not node.expanded
                    ns.db.expandedMatrixTargets[node.targetKey] = nextExpanded
                    if node.legacyKey and node.legacyKey ~= node.targetKey then
                        ns.db.expandedMatrixTargets[node.legacyKey] = nextExpanded
                    end
                    if ns.BumpTeamTreeRevision then ns:BumpTeamTreeRevision() end
                    ns:RefreshCompactLeftPanel()
                end
                return
            end
            if mouseButton == "RightButton" then
                ns:ShowTeamContextMenu(self, self.teamIndex)
            else
                ns:RequestCompactTeamSwitch(self.teamIndex)
            end
            return
        end
        local item = self.itemData
        if not item or not item.petID then return end
        if mouseButton == "RightButton" then
            ns:ShowPetContextMenu(self, item)
        else
            if SpellIsTargeting and SpellIsTargeting() then
                C_PetJournal.SpellTargetBattlePet(item.petID)
                return
            end
            if IsInBattle() then ns:PrintError(T("战斗中无法更改编组")); return end
            if ns.draggingQueuePetID and self.mode == "QUEUE" and ns.draggingQueuePetID ~= item.petID then
                ns:FinishCompactQueueDrag(self)
                return
            end
            if ns.db.activeTargetSlot then
                ns:PutCompactPet(ns.db.activeTargetSlot, item.petID, false)
            else
                local f = ns.MainFrame
                f.compactSelectedPetID = f.compactSelectedPetID ~= item.petID and item.petID or nil
                ns:RefreshLoadoutCabin()
            end
        end
    end)
    row:SetScript("OnDoubleClick", function(self, mouseButton)
        if mouseButton and mouseButton ~= "LeftButton" then return end
        if self.mode ~= "PETS" then return end
        local item = self.itemData
        if not item or not item.petID or not item.isCollected then return end
        if InCombatLockdown() or IsInBattle() then return end
        if C_PetJournal and C_PetJournal.SummonPetByGUID then
            C_PetJournal.SummonPetByGUID(item.petID)
        end
    end)
    row:SetScript("OnDragStart", function(self)
        local item = self.itemData
        if not item or not item.petID or IsInBattle() then return end
        HidePetTip(true)
        if self.mode == "QUEUE" then
            ns.draggingQueuePetID = item.petID
            ns.isReorderingQueueList = true
        else
            ns.draggingQueuePetID = nil
            ns.isReorderingQueueList = false
        end
        ns.draggingPetID = item.petID
        C_PetJournal.PickupPet(item.petID)
        ns:UpdateLoadoutSlotDragVisuals()
        if self.mode == "QUEUE" then
            ns:UpdateCompactQueueDragVisuals()
        end
    end)
    row:SetScript("OnReceiveDrag", function(self)
        if self.mode == "QUEUE" and ns.draggingQueuePetID then
            ns:FinishCompactQueueDrag(self)
        end
    end)
    row:SetScript("OnDragStop", function()
        if ns.draggingQueuePetID then
            if not ns:FinishCompactQueueDrag() then
                ns.isReorderingQueueList = false
                ns:UpdateCompactQueueDragVisuals()
            end
        end
    end)
    return row
end

local function MakeRightSlot(parent, slot)
    local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
    card:SetSize(RIGHT_CARD_W, RIGHT_CARD_H)
    card:SetPoint("TOPLEFT", 16, -78 - (slot - 1) * RIGHT_CARD_STEP)
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    card:RegisterForDrag("LeftButton")
    Theme:ApplyBackdrop(card, CARD_BG, Theme.Colors.border, false)
    card.slot = slot
    card:SetClipsChildren(true)
    card.typeBg = card:CreateTexture(nil, "BACKGROUND", nil, 1)
    card.typeBg:SetSize(RIGHT_CARD_H, RIGHT_CARD_H)
    card.typeBg:SetPoint("RIGHT", card, "RIGHT", -2, 0)
    card.typeBg:SetAlpha(0.12)
    card.typeBg:Hide()
    card.icon = Theme:CreateCroppedIcon(card, 64)
    card.icon:SetPoint("TOPLEFT", 14, -16)
    card.icon:EnableMouse(false)
    local plusTxt = card.icon:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    plusTxt:SetPoint("CENTER", card.icon, "CENTER", 0, 0)
    local plusFont = plusTxt:GetFont()
    if plusFont then plusTxt:SetFont(plusFont, 28, "OUTLINE") end
    plusTxt:SetText("|cff38bdf8+|r")
    plusTxt:Hide()
    card.icon.plusTxt = plusTxt
    card.favBadge = card.icon:CreateTexture(nil, "OVERLAY")
    card.favBadge:SetSize(20, 20)
    card.favBadge:SetPoint("TOPLEFT", card.icon, "TOPLEFT", -4, 4)
    if card.favBadge.SetAtlas then
        card.favBadge:SetAtlas("PetJournal-FavoritesIcon")
    end
    card.favBadge:Hide()
    card.name = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.name:SetPoint("TOPLEFT", 96, -20)
    card.name:SetPoint("RIGHT", -52, 0)
    card.name:SetJustifyH("LEFT")
    card.name:SetWordWrap(false)
    Theme:HookLocalizedFontString(card.name)
    card.underline = card:CreateTexture(nil, "ARTWORK")
    card.underline:SetTexture("Interface\\Buttons\\WHITE8X8")
    card.underline:SetVertexColor(unpack(CYAN))
    card.underline:SetHeight(1)
    card.underline:SetPoint("BOTTOMLEFT", card.name, "BOTTOMLEFT", 0, -2)
    card.underline:Hide()
    local function SyncCardUnderlineWidth()
        Theme:AnchorStandardUnderline(card.underline, card, card.name, "LEFT", 0)
    end
    card._SyncUnderline = SyncCardUnderlineWidth
    card.name._wishOnTextChanged = function()
        if card.underline:IsShown() then SyncCardUnderlineWidth() end
    end
    card.breed = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.breed:SetPoint("TOPRIGHT", -14, -21)
    card.breed:SetWidth(46)
    card.breed:SetJustifyH("RIGHT")
    card.breed:SetTextColor(0.54, 0.76, 0.88)
    Theme:HookLocalizedFontString(card.breed)
    card.qualityLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.qualityLabel:SetPoint("TOPRIGHT", -12, -12)
    card.qualityLabel:SetWidth(65)
    card.qualityLabel:SetJustifyH("RIGHT")
    card.qualityLabel:Hide()
    Theme:HookLocalizedFontString(card.qualityLabel)
    card.levelBadge = CreateFrame("Frame", nil, card.icon)
    card.levelBadge:SetSize(24, 14)
    card.levelBadge:SetPoint("TOPRIGHT", card.icon, "TOPRIGHT", -2, -2)
    card.levelBadge:SetFrameLevel(card.icon:GetFrameLevel() + 5)
    card.levelBadge.text = card.levelBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.levelBadge.text:SetPoint("TOPRIGHT", 0, 0)
    local lvFont = card.levelBadge.text:GetFont()
    if lvFont then card.levelBadge.text:SetFont(lvFont, 11, "OUTLINE") end
    card.levelBadge.text:SetTextColor(1, 0.85, 0.25)
    Theme:HookLocalizedFontString(card.levelBadge.text)
    card.healthBg, card.syncBar = MakeBar(card, 192)
    card.healthBg:SetPoint("BOTTOMLEFT", 14, 18)
    card.syncBar:SetPoint("BOTTOMLEFT", 14, 18)
    card.abBtns = {}
    for col = 1, 3 do
        local ab = CreateFrame("Button", nil, card, "BackdropTemplate")
        ab:SetSize(30, 30)
        ab:SetPoint("TOPLEFT", 96 + (col - 1) * 38, -48)
        Theme:ApplyBackdrop(ab, { 0.147, 0.147, 0.147, 0.6 }, Theme.Colors.border, false)
        ab.icon = ab:CreateTexture(nil, "ARTWORK")
        ab.icon:SetPoint("TOPLEFT", 2, -2)
        ab.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        ab.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ab.icon:SetTexture(EMPTY_PET_ICON)
        ab.col = col
        ab:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(unpack(Theme.Colors.borderBlue))
            if card._SyncUnderline then card:_SyncUnderline() end
            if card.underline then card.underline:Show() end
            if card.isLevelingSlot and not ns.MainFrame.compactDraft then
                ns:ShowCustomTooltip(self, "ANCHOR_TOP", T("经验槽技能由当前练级宠物决定"))
            elseif self.abID and ns.ShowAbilityTooltip then
                local data = card.petData
                ns:ShowAbilityTooltip(self, self.abID, data and data.maxHealth or 1400, data and data.power or 280, data and data.speed or 280)
            end
        end)
        ab:SetScript("OnLeave", function(self)
            ns:HideCustomTooltip(self)
            self:SetBackdropBorderColor(unpack(Theme.Colors.border))
            if card.underline and not card:IsMouseOver() then card.underline:Hide() end
            if ns.HideAbilityTooltip then ns:HideAbilityTooltip() end
        end)
        ab:SetScript("OnClick", function(self)
            if not self.speciesID or not card.petData or IsInBattle() then return end
            if not ns.MainFrame.compactDraft and (card.isLevelingSlot or card.levelingPaused
                and C_PetJournal.GetPetLoadOutInfo(slot) ~= card.petData.petID) then return end
            ClearSelection(ns.MainFrame)
            ns:RefreshLoadoutCabin()
            ns:ShowCompactAbilityPicker(self, card, slot, col)
        end)
        card.abBtns[col] = ab
    end
    local function OpenSlotMenu(self)
        if IsInBattle() then return end
        ns:ShowSlotThresholdMenu(self, slot)
    end
    card.more = MakeLink(card, "···", 30, function() OpenSlotMenu(card) end, "CENTER")
    card.more._noUnderline = true
    card.more:SetPoint("TOPRIGHT", -7, -41)
    card.more:SetAlpha(0)
    SetLinkTip(card.more, function() return T("槽位设置") end)
    card.more:HookScript("OnEnter", function(self)
        self:SetAlpha(1)
        if card._SyncUnderline then card:_SyncUnderline() end
        if card.underline then card.underline:Show() end
    end)
    card.more:HookScript("OnLeave", function(self)
        self:SetAlpha(card:IsMouseOver() and 1 or 0)
        if card.underline and not card:IsMouseOver() then card.underline:Hide() end
    end)
    card:SetScript("OnEnter", function(self)
        self.more:SetAlpha(1)
        if self.underline then
            if not self.underline._synced and self._SyncUnderline then
                self:_SyncUnderline()
                self.underline._synced = true
            end
            self.underline:Show()
        end
        if self.isLevelingSlot or self.levelingPaused then
            ns:ShowCustomTooltip(self, "ANCHOR_CURSOR",
                "|cffffc34a" .. T("经验槽") .. "|r",
                "|cffbfdbfe" .. T(self.isLevelingSlot and "队列中的待练宠物自动上阵；右键可设置槽位"
                    or "点击槽位自动填入随机未满级宠物并开启练级队列") .. "|r"
            )
            if self.petData then
                ShowPetTip(self, self.petData, false)
            end
        elseif self.petData then
            ShowPetTip(self, self.petData, false)
        end
    end)
    card:SetScript("OnLeave", function(self)
        self.more:SetAlpha(self.more:IsMouseOver() and 1 or 0)
        if self.underline and not self:IsMouseOver() then
            self.underline:Hide()
        end
        HidePetTip(false)
        ns:HideCustomTooltip(self)
    end)
    card:SetScript("OnClick", function(self, button)
        local f = ns.MainFrame
        if button == "RightButton" then
            OpenSlotMenu(self)
        elseif IsInBattle() then
            ns:PrintError(T("战斗中无法更改编组"))
        elseif f.compactSelectedPetID then
            if ns:PutCompactPet(slot, f.compactSelectedPetID, false) and f.mainUIStyle == "MINIMAL" then
                ns:CloseMinimalPicker()
            end
        elseif self.isLevelingSlot or self.levelingPaused then
            if ns.Leveling and ns.Leveling.FillRandomUnleveledPetForSlot then
                local needFill = (ns.Leveling:GetManualQueueCount() == 0)
                    or not ns.Leveling:HasLivingQueuePet()
                    or not self.petData
                    or (self.petData.level or 25) >= 25
                if needFill then
                    ns.Leveling:FillRandomUnleveledPetForSlot(slot, true)
                    RefreshBoth()
                    return
                end
            end
            if f.mainUIStyle == "MINIMAL" then
                if card.isLevelingSlot and ns.Leveling:GetManualQueueCount() > 0 then
                    ns:OpenMinimalPicker("QUEUE", slot)
                else
                    ns:OpenMinimalPicker("PETS", slot)
                end
            else
                if f.compactLeft and ns.Leveling:GetManualQueueCount() > 0 then
                    SetLeftMode("QUEUE")
                end
                RefreshBoth()
            end
        elseif f.mainUIStyle == "MINIMAL" then
            ns:OpenMinimalPicker("PETS", slot)
        else
            ns.db.activeTargetSlot = ns.db.activeTargetSlot ~= slot and slot or nil
            if f.compactLeft.mode == "TEAMS" then SetLeftMode("PETS") end
            RefreshBoth()
        end
    end)
    card:SetScript("OnReceiveDrag", function()
        ns.isReorderingQueueList = false
        ns:DropPetIntoSlot(slot)
    end)
    card:SetScript("OnDragStart", function()
        if IsInBattle() or GetCursorInfo() then return end
        local draft = ns.MainFrame.compactDraft
        local petID
        if draft then
            local entry = draft.slots[slot]
            petID = entry and entry.petID
        else
            petID = C_PetJournal.GetPetLoadOutInfo(slot)
        end
        if not petID then return end
        C_PetJournal.PickupPet(petID)
        local cursorType, cursorPetID = GetCursorInfo()
        if cursorType == "battlepet" and cursorPetID == petID then
            ns.loadoutSlotDrag = { slot = slot, petID = petID }
            ns:UpdateLoadoutSlotDragVisuals()
        end
    end)
    local overlay = CreateFrame("Frame", nil, card, "BackdropTemplate")
    overlay:SetAllPoints(card)
    overlay:SetFrameLevel(card:GetFrameLevel() + 12)
    overlay:EnableMouse(false)
    overlay:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    overlay.text = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    overlay.text:SetPoint("CENTER", 0, 0)
    Theme:HookLocalizedFontString(overlay.text)
    overlay:Hide()
    card.dragOverlay = overlay
    return card
end

function ns:ShowCompactAbilityPicker(anchor, card, slot, col)
    local f = self.MainFrame
    if not f then return end
    if not f.compactAbilityPopup then
        local popup = CreateFrame("Frame", nil, f, "BackdropTemplate")
        popup:SetSize(96, 49)
        popup:EnableMouse(true)
        popup:SetClampedToScreen(true)
        popup:SetFrameStrata("DIALOG")
        popup:SetFrameLevel(200)
        Theme:ApplyBackdrop(popup, { 0.075, 0.075, 0.075, 0.99 }, Theme.Colors.border, false)
        popup.buttons = {}
        for i = 1, 2 do
            local btn = CreateFrame("Button", nil, popup, "BackdropTemplate")
            btn:SetSize(34, 34)
            btn:SetPoint("LEFT", 8 + (i - 1) * 41, 0)
            Theme:ApplyBackdrop(btn, ROW_BG, Theme.Colors.border, false)
            btn.icon = btn:CreateTexture(nil, "ARTWORK")
            btn.icon:SetPoint("TOPLEFT", 2, -2)
            btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
            btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn.marker = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            btn.marker:SetPoint("BOTTOMRIGHT", -2, 2)
            btn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(unpack(Theme.Colors.borderBlue))
                if self.locked then
                    ns:ShowCustomTooltip(self, "ANCHOR_TOP", ns:TF("%d 级解锁", self.requiredLevel))
                    return
                end
                if self.abID and ns.ShowAbilityTooltip then
                    local data = popup.petData
                    ns:ShowAbilityTooltip(self, self.abID, data and data.maxHealth or 1400, data and data.power or 280, data and data.speed or 280)
                end
            end)
            btn:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(unpack(self.current and Theme.Colors.borderBlue or Theme.Colors.border))
                ns:HideCustomTooltip(self)
                if ns.HideAbilityTooltip then ns:HideAbilityTooltip() end
            end)
            btn:SetScript("OnClick", function(self)
                if not self.abID or self.locked or IsInBattle() then return end
                local draft = f.compactDraft
                local slot, col = popup.slot, popup.col
                if draft ~= popup.draft or (not draft and ns.db.teams[ns.db.selectedTeamIdx] ~= popup.team) then
                    popup:Hide()
                    return
                end
                local entry = draft and draft.slots[slot]
                local livePetID = draft and entry and entry.petID or not draft and C_PetJournal.GetPetLoadOutInfo(slot)
                if not popup.petData or livePetID ~= popup.petData.petID then popup:Hide(); return end
                popup:Hide()
                if self.current then return end
                if entry then
                    entry.abilities[col] = self.abID
                elseif ns.AutoRouting:SetManualLoadoutAbility(slot, col, self.abID) then
                    ns.staging.isDirty = true
                    ns.staging.manualAbilities = true
                    ns:MarkHomeSlotChanged(slot)
                else
                    ns:PrintError(T("技能切换未生效"))
                end
                ns:RefreshLoadoutCabin()
            end)
            popup.buttons[i] = btn
        end
        popup:SetScript("OnHide", function(self)
            for _, button in ipairs(self.buttons) do
                ns:HideCustomTooltip(button)
            end
            if ns.HideAbilityTooltip then ns:HideAbilityTooltip() end
        end)
        f.compactAbilityPopup = popup
    end
    local popup = f.compactAbilityPopup
    if popup:IsShown() and popup.anchor == anchor then popup:Hide(); return end
    if anchor.abID == nil or not card.petData then return end
    local ids, levels = ns:GetSortedPetAbilities(anchor.speciesID)
    popup.slot, popup.col, popup.anchor, popup.petData = slot, col, anchor, card.petData
    popup.draft, popup.team = f.compactDraft, ns.db.teams[ns.db.selectedTeamIdx]
    for i = 1, 2 do
        local id = ids and ids[col + (i - 1) * 3]
        local b = popup.buttons[i]
        b.abID = id
        b:SetShown(id and id > 0)
        if id and id > 0 then
            local _, icon = C_PetJournal.GetPetAbilityInfo(id)
            b.icon:SetTexture(icon or EMPTY_PET_ICON)
            b.current = id == anchor.abID
            b.requiredLevel = (levels and levels[col + (i - 1) * 3]) or 1
            b.locked = b.requiredLevel > card.petData.level
            b.marker:SetText(b.locked and "|TInterface\\Buttons\\LockButton-Locked-Up:13|t" or b.current and "✓" or "")
            b.icon:SetDesaturated(b.locked)
            b:SetBackdropBorderColor(unpack(b.current and Theme.Colors.borderBlue or Theme.Colors.border))
        end
    end
    popup:ClearAllPoints()
    popup:SetPoint("BOTTOM", anchor, "TOP", 0, 6)
    popup:Show()
end

-- 构建完整的分组 -> 目标 -> 队伍三级分级管理树（原 TeamMatrixModal 全部管理功能）
local function BuildTeamsTreeItems(left, query)
    ns.db.expandedMatrixGroups  = ns.db.expandedMatrixGroups  or {}
    ns.db.expandedMatrixTargets = ns.db.expandedMatrixTargets or {}
    ns.db.teamGroups = ns.db.teamGroups or { "最爱队伍", "未分组队伍", "暗影界", "巨龙时代", "地心之战", "宠物地下城" }

    ns.AutoRouting:SyncTargetGroups()
    local routeByNpcID = {}
    local routeByTeamName = {}
    for routeKey, route in pairs(ns.db.routeMappings or {}) do
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

    for idx, t in ipairs(ns.db.teams or {}) do
        local gName = (t.group and t.group ~= "") and t.group or "未分组队伍"
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

        local tNpcID = tonumber(t.npcID) or 0
        local routeKey = routeByNpcID[tNpcID] or routeByTeamName[t.name]
        local route = routeKey and ns.db.routeMappings[routeKey]
        local routeName = route and strtrim(route.npcName or "") or ""
        local targetLabel = (routeName ~= "" and routeName)
            or (t.npcName and t.npcName ~= "" and t.npcName)
            or (tNpcID > 0 and ("NPC #" .. tNpcID))
            or ns:T("通用 / 未绑定目标")

        local pass = true
        if query ~= "" then
            pass = ns.FuzzySearch:MatchFields(query, t.name, targetLabel, gName)
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

    if left.checkMissingBtn then
        if left.mode == "TEAMS" and globalHasAnyMissing then
            left.checkMissingBtn.text:SetText(ns:TF("查看缺失宠物汇总 (%d)", globalUniqueMissingCount))
            left.checkMissingBtn:Show()
        else
            left.checkMissingBtn:Hide()
            if not globalHasAnyMissing and ns.MissingPetsModal and ns.MissingPetsModal:IsShown() then
                ns.MissingPetsModal:Hide()
            end
        end
    end

    local items = left.items or {}
    local pool = left._treeNodePool or {}
    left._treeNodePool = pool
    wipe(items)
    local poolIdx = 0
    local function AcquireNode()
        poolIdx = poolIdx + 1
        local node = pool[poolIdx]
        if not node then
            node = {}
            pool[poolIdx] = node
        else
            wipe(node)
        end
        return node
    end
    local forceExpand = (query ~= "")
    local expandAllPending = left._expandAllPending
    left._expandAllPending = nil

    for _, gName in ipairs(groupOrder) do
        local gObj = groupMap[gName]
        if gObj and (gObj.totalTeams > 0 or query == "") then
            if expandAllPending then
                ns.db.expandedMatrixGroups[gName] = true
            end
            local isGrpOpen = forceExpand or (ns.db.expandedMatrixGroups[gName] == true)
            local gNode = AcquireNode()
            gNode.nodeType     = "GROUP"
            gNode.groupName    = gName
            gNode.count        = gObj.totalTeams
            gNode.missingCount = gObj.missingTeams
            gNode.underLvCount = gObj.underLvTeams
            gNode.expanded     = isGrpOpen
            items[#items + 1]  = gNode

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
                    if expandAllPending then
                        ns.db.expandedMatrixTargets[tKey] = true
                        ns.db.expandedMatrixTargets[legacyKey] = true
                    end
                    local savedExpanded = ns.db.expandedMatrixTargets[tKey]
                    if savedExpanded == nil then
                        savedExpanded = ns.db.expandedMatrixTargets[legacyKey]
                    end
                    local isTargetOpen = forceExpand or savedExpanded == true
                    if bucket.routeKey and labelCounts[tLabel] > 1 then
                        tLabel = string.format("%s [%s]", tLabel, tostring(bucket.routeKey))
                    end
                    local tNode = AcquireNode()
                    tNode.nodeType      = "TARGET"
                    tNode.groupName     = gName
                    tNode.targetLabel   = tLabel
                    tNode.targetKey     = tKey
                    tNode.legacyKey     = legacyKey
                    tNode.routeKey      = bucket.routeKey
                    tNode.savedExpanded = savedExpanded
                    tNode.count         = #bucket.list
                    tNode.missingCount  = bucket.missingCount
                    tNode.underLvCount  = bucket.underLvCount
                    tNode.expanded      = isTargetOpen
                    items[#items + 1]   = tNode

                    if isTargetOpen then
                        for _, tItem in ipairs(bucket.list) do
                            local tmNode = AcquireNode()
                            tmNode.nodeType     = "TEAM"
                            tmNode.groupName    = gName
                            tmNode.targetLabel  = tLabel
                            tmNode.teamIndex    = tItem.teamIndex
                            tmNode.team         = tItem.team
                            tmNode.audit        = tItem.audit
                            tmNode.missingBadge = tItem.missingBadge
                            tmNode.underLvBadge = tItem.underLvBadge
                            items[#items + 1]   = tmNode
                        end
                    end
                end
            end
        end
    end

    return items
end

function ns:RefreshCompactLeftPanel()
    local f = self.MainFrame
    local left = f and f.compactLeft
    if not left or not left:IsShown() or not ns.db then return end
    local queueCount = ns.Leveling:GetManualQueueCount()
    if queueCount > 0 then f.compactQueueUndo = nil end
    if queueCount == 0 and left.mode == "QUEUE" then
        left.mode, left.offset = "PETS", 0
        left.searchBox:SetText("")
    end
    left.queueTab:SetShown(queueCount > 0)
    if queueCount > 0 and left.lastQueueCount == 0 then
        left.queuePulseAnim:Stop()
        left.queuePulseAnim:Play()
    end
    left.lastQueueCount = queueCount
    left.queueTab.text:SetText(T("练级队列") .. " (" .. queueCount .. ")")
    left.petTab:SetActive(left.mode == "PETS")
    left.teamTab:SetActive(left.mode == "TEAMS")
    left.queueTab:SetActive(left.mode == "QUEUE")

    local isTeamsMode = (left.mode == "TEAMS")
    left.clearLink:SetShown(left.mode == "QUEUE" and queueCount > 0)
    left.undoLink:SetShown(f.compactQueueUndo ~= nil and queueCount == 0 and left.mode == "PETS")
    left.filterLink:SetShown(not isTeamsMode)
    if left.collapseAllBtn then left.collapseAllBtn:SetShown(isTeamsMode) end
    if left.expandAllBtn then left.expandAllBtn:SetShown(isTeamsMode) end
    if left.teamNewBtn then left.teamNewBtn:SetShown(isTeamsMode) end
    if left.teamNewGroupBtn then left.teamNewGroupBtn:SetShown(isTeamsMode) end
    if left.teamSyncRematchBtn then left.teamSyncRematchBtn:SetShown(isTeamsMode) end
    if left.teamImportBtn then left.teamImportBtn:SetShown(isTeamsMode) end
    if left.teamExportBtn then left.teamExportBtn:SetShown(isTeamsMode) end
    if left.footer then left.footer:SetShown(not isTeamsMode) end

    if left._lastSearchTeamsMode ~= isTeamsMode then
        left._lastSearchTeamsMode = isTeamsMode
        left.searchBox:ClearAllPoints()
        if isTeamsMode then
            left.searchBox:SetSize(256, 24)
            left.searchBox:SetPoint("TOPRIGHT", -16, -51)
            if left.searchPlaceholder then
                left.searchPlaceholder:SetText(T("搜索队伍 / 目标 / 分组..."))
            end
        else
            left.searchBox:SetSize(555, 24)
            left.searchBox:SetPoint("TOPLEFT", 18, -51)
            if left.searchPlaceholder then
                left.searchPlaceholder:SetText(T("搜索宠名 / 技能 / 拼音 / 备注..."))
            end
        end
    end

    local query = strlower(strtrim(left.searchBox:GetText() or ""))
    local items = left.items or {}
    if left.mode == "PETS" then
        if left.checkMissingBtn then left.checkMissingBtn:Hide() end
        local list = ns.SearchFilter:GetFilteredPets(query)
        local revision = ns.SearchFilter:GetResultsRevision()
        if left._itemsMode ~= "PETS" or left._itemsQuery ~= query or left._itemsRevision ~= revision then
            wipe(items)
            for _, pet in ipairs(list) do
                items[#items + 1] = pet
            end
            left._itemsQuery, left._itemsRevision = query, revision
        end
    elseif isTeamsMode then
        local treeDirty = ns.TeamMatrixModal and ns.TeamMatrixModal._treeDirty
        local teamCount = ns.db.teams and #ns.db.teams or 0
        local groupCount = ns.db.teamGroups and #ns.db.teamGroups or 0
        local teamTreeRev = ns._teamTreeRevision or 0
        local petJournalRev = ns._petJournalRevision or 0
        local routeRev = ns._routeRevision or 0
        if treeDirty or left._itemsMode ~= "TEAMS" or left._itemsQuery ~= query
            or left._itemsTeamTreeRev ~= teamTreeRev or left._itemsPetJournalRev ~= petJournalRev
            or left._itemsRouteRev ~= routeRev or left._itemsTeamCount ~= teamCount
            or left._itemsGroupCount ~= groupCount then
            if ns.TeamMatrixModal then ns.TeamMatrixModal._treeDirty = false end
            items = BuildTeamsTreeItems(left, query)
            left._itemsQuery = query
            left._itemsTeamTreeRev = teamTreeRev
            left._itemsPetJournalRev = petJournalRev
            left._itemsRouteRev = routeRev
            left._itemsTeamCount = teamCount
            left._itemsGroupCount = groupCount
        end
    else
        if left.checkMissingBtn then left.checkMissingBtn:Hide() end
        local qList = ns.Leveling:GetQueue(query)
        local qRev = ns.Leveling.GetQueueRevision and ns.Leveling:GetQueueRevision() or 0
        if left._itemsMode ~= "QUEUE" or left._itemsQuery ~= query or left._itemsQueueRev ~= qRev then
            wipe(items)
            for rank, pet in ipairs(qList) do
                pet._queueDisplayRank = rank
                items[#items + 1] = pet
            end
            left._itemsQuery, left._itemsQueueRev = query, qRev
        end
    end
    left._itemsMode = left.mode
    left.items = items

    local effCols = isTeamsMode and 1 or COLS
    local maxVis = isTeamsMode and 11 or MAX_VISIBLE
    for i = #left.rows + 1, maxVis do
        left.rows[i] = MakePetRow(left.list, i)
    end
    local totalRows = math.ceil(#items / effCols)
    local visibleRows = math.ceil(maxVis / effCols)
    local maxOff = math.max(0, totalRows - visibleRows)
    left.offset = math.max(0, math.min(maxOff, left.offset or 0))
    left._maxOff = maxOff
    if left.scrollTrack and left.scrollThumb then
        if maxOff <= 0 then
            left.scrollTrack:Hide()
        else
            left.scrollTrack:Show()
            local trackH = left.scrollTrack:GetHeight() or 402
            local thumbH = math.max(28, math.floor(trackH * (visibleRows / math.max(1, totalRows))))
            left.scrollThumb:SetHeight(thumbH)
            local travel = math.max(1, trackH - thumbH)
            local topOffset = math.floor((left.offset / maxOff) * travel)
            left.scrollThumb:ClearAllPoints()
            left.scrollThumb:SetPoint("TOP", left.scrollTrack, "TOP", 0, -topOffset)
        end
    end

    for i = 1, #left.rows do
        local row = left.rows[i]
        if i > maxVis then
            row:Hide()
        else
            local wantLayout = isTeamsMode and "TEAMS" or "GRID"
            if row._layoutMode ~= wantLayout then
                row._layoutMode = wantLayout
                local rW = isTeamsMode and 676 or ROW_W
                local rH = isTeamsMode and 34 or ROW_H
                local rStep = isTeamsMode and 36 or ROW_STEP
                row:SetSize(rW, rH)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", ((i - 1) % effCols) * COL_STEP, -math.floor((i - 1) / effCols) * rStep)
            end
            local idx = left.offset * effCols + i
            local item = items[idx]
            row.itemData, row.mode, row.teamIndex, row.node = nil, left.mode, nil, nil
            for s = 1, 3 do
                row.teamPetBtns[s]:Hide()
                row.teamPetBtns[s].warnMark:Hide()
                row.teamPetBtns[s].lvBadge:Hide()
                row.typeWatermarks[s]:Hide()
            end
            if row.queueRankBadge then row.queueRankBadge:Hide() end
            if row.favBadge then row.favBadge:Hide() end

            if not item then
                row:Hide()
            else
                row:Show()
                if isTeamsMode then
                    row.node = item
                    if row.typeBg then row.typeBg:Hide() end
                    row.icon:Hide()
                    row.detail:Hide()
                    row.healthBg:Hide()
                    row.health:Hide()
                    row.action:Hide()

                    if item.nodeType == "GROUP" then
                        row.selected = false
                        row.groupArrow:ClearAllPoints()
                        row.groupArrow:SetPoint("LEFT", row, "LEFT", 8, 0)
                        row.groupArrow:SetRotation(item.expanded and 0 or math.rad(90))
                        row.groupArrow:SetVertexColor(0.38, 0.78, 1.0, 1)
                        row.groupArrow:Show()

                        local missTag = (item.missingCount and item.missingCount > 0) and ns:TF(" |cffff4040(%d队缺宠)|r", item.missingCount) or ""
                        local underTag = (item.underLvCount and item.underLvCount > 0) and ns:TF(" |cffff9900(%d队未满级)|r", item.underLvCount) or ""
                        row.groupCount:SetText(ns:TF("|cff9ca3af%d 支队伍|r", item.count))
                        row.groupCount:Show()

                        row.title:ClearAllPoints()
                        row.title:SetPoint("LEFT", row, "LEFT", 26, 0)
                        row.title:SetPoint("RIGHT", row.groupCount, "LEFT", -8, 0)
                        row.title:SetText(string.format("|cff38bdf8%s|r%s%s", T(item.groupName), missTag, underTag))

                    elseif item.nodeType == "TARGET" then
                        row.selected = false
                        row.groupArrow:ClearAllPoints()
                        row.groupArrow:SetPoint("LEFT", row, "LEFT", 26, 0)
                        row.groupArrow:SetRotation(item.expanded and 0 or math.rad(90))
                        row.groupArrow:SetVertexColor(0.06, 0.82, 0.65, 1)
                        row.groupArrow:Show()

                        local missTag = (item.missingCount and item.missingCount > 0) and ns:TF(" |cffff4040(%d队缺宠)|r", item.missingCount) or ""
                        local underTag = (item.underLvCount and item.underLvCount > 0) and ns:TF(" |cffff9900(%d队未满级)|r", item.underLvCount) or ""
                        row.groupCount:SetText(ns:TF("|cff9ca3af%d 队|r", item.count))
                        row.groupCount:Show()

                        row.title:ClearAllPoints()
                        row.title:SetPoint("LEFT", row, "LEFT", 44, 0)
                        row.title:SetPoint("RIGHT", row.groupCount, "LEFT", -8, 0)
                        row.title:SetText(ns:TF("|cff10b981目标: %s|r%s%s", item.targetLabel, missTag, underTag))

                    elseif item.nodeType == "TEAM" then
                        row.groupArrow:Hide()
                        row.groupCount:Hide()
                        local t = item.team
                        local audit = item.audit or ns:AuditTeamPets(t)
                        local isActive = (item.teamIndex == ns.db.selectedTeamIdx)
                        row.teamIndex = item.teamIndex
                        row.selected = isActive

                        row.title:ClearAllPoints()
                        row.title:SetPoint("LEFT", row, "LEFT", 48, 0)
                        row.title:SetPoint("RIGHT", row, "RIGHT", -224, 0)
                        row.title:SetText((isActive and ns:T("|cff10b981[当前] |r|cffffffff") or "|cfff3f4f6")
                            .. (t.name or T("未命名队伍")) .. "|r"
                            .. (item.underLvBadge or "") .. (item.missingBadge or ""))

                        for s = 1, 3 do
                            local pBtn = row.teamPetBtns[s]
                            local wm = row.typeWatermarks[s]
                            local isLv, iconTex, petType, isSlotMissing = GetTeamSlotIconFast(t, s, isActive)
                            local slotUnderLv = audit.underLvBySlot and audit.underLvBySlot[s]

                            if isLv or iconTex then
                                pBtn:Show()
                                local finalTex = iconTex or LV_ICON
                                if pBtn._lastTex ~= finalTex then
                                    pBtn._lastTex = finalTex
                                    pBtn.icon:SetTexture(finalTex)
                                end
                                pBtn.icon:SetDesaturated(isSlotMissing == true)

                                if isSlotMissing then
                                    pBtn:SetBackdropBorderColor(unpack(Theme.Colors.borderRed))
                                elseif slotUnderLv then
                                    pBtn:SetBackdropBorderColor(unpack(Theme.Colors.borderAmber))
                                    pBtn.warnMark:Show()
                                    pBtn.lvBadge:SetText("|cffff9900" .. slotUnderLv .. "|r")
                                    pBtn.lvBadge:Show()
                                else
                                    pBtn:SetBackdropBorderColor(unpack(Theme.Colors.border))
                                end
                            end
                            if petType then
                                Theme:SetPetTypeDecalTexture(wm, petType)
                            end
                        end
                    end

                    row:SetBackdropColor(0, 0, 0, 0)
                    row:SetBackdropBorderColor(0, 0, 0, 0)
                    if row._SyncUnderline then row._SyncUnderline() end
                    row.underline:SetShown(row.selected or row:IsMouseOver())
                else
                    if row.groupArrow then row.groupArrow:Hide() end
                    if row.groupCount then row.groupCount:Hide() end
                    row.icon:Show()
                    row.detail:Show()
                    row.action:ClearAllPoints()
                    row.action:SetPoint("TOPRIGHT", -7, -9)
                    row.title:ClearAllPoints()
                    row.title:SetPoint("TOPLEFT", 76, -15)
                    row.title:SetPoint("RIGHT", -56, 0)
                    local pet = item
                    row.itemData = pet
                    row.icon.icon:SetRotation(0)
                    row.icon.icon:SetTexture(pet.icon or EMPTY_PET_ICON)
                    row.icon.icon:SetDesaturated(pet.isDead or not pet.isCollected)
                    local qCol = pet.isCollected and (Theme.QualityColors[pet.rarity] or Theme.QualityColors[2]) or Theme.Colors.border
                    row.icon:SetBackdropBorderColor(qCol[1], qCol[2], qCol[3], 1)
                    if row.typeBg then
                        Theme:SetPetListTypeTexture(row.typeBg, pet.petType)
                        row.typeBg:SetVertexColor(1, 1, 1, 0.14)
                    end
                    if left.mode == "QUEUE" and row.queueRankBadge then
                        local qRank = pet._queueDisplayRank or idx
                        local rCol = (qRank == 1) and "|cff10b981#" or "|cffffd100#"
                        row.queueRankBadge:SetText(rCol .. qRank .. "|r")
                        row.queueRankBadge:Show()
                    end
                    if row.favBadge then row.favBadge:SetShown(pet.isFavorite == true) end
                    row.title:SetText((pet.name or T("未知宠物")) .. " |cffffd77a" .. (pet.level or 1) .. "|r " .. "|cff72b9d8" .. (pet.breed or "") .. "|r")
                    row.detail:SetText(T("攻") .. ": " .. (pet.power or 0) .. "  ·  " .. T("速") .. ": " .. (pet.speed or 0))
                    row.healthBg:Show()
                    row.health:Show()
                    SetBar(row.health, pet.hpPct or 0, pet.isDead)
                    local canQueue = pet.isCollected and pet.petID and (pet.level or 25) < 25
                    row.action:SetShown(canQueue)
                    if canQueue then
                        row.action.text:SetText(left.mode == "QUEUE" and "×" or (ns.Leveling:IsPetInQueue(pet.petID) and "✓" or "+"))
                    end
                    row.selected = pet.petID ~= nil and pet.petID == f.compactSelectedPetID
                    row.underline:SetShown(row:IsMouseOver())
                    if row.selected then
                        row:SetBackdropColor(unpack(ROW_SELECTED))
                        row:SetBackdropBorderColor(unpack(Theme.Colors.borderBlue))
                    else
                        row:SetBackdropColor(unpack(ROW_BG))
                        row:SetBackdropBorderColor(unpack(Theme.Colors.border))
                    end
                end
            end
        end
    end

    left.emptyText:SetShown(#items == 0)
    if #items == 0 then
        if isTeamsMode then
            left.emptyText:SetText(T(query == "" and "还没有队伍，点击左下方「新建队伍」开始。" or "没有符合条件的队伍。"))
        elseif left.mode == "QUEUE" then
            left.emptyText:SetText(T("队列中暂无符合当前筛选条件的宠物。"))
        else
            left.emptyText:SetText(T("没有符合条件的宠物。"))
        end
    end
    if not isTeamsMode then
        local hint
        if ns.db.activeTargetSlot then hint = T("点击宠物上阵 · 按住 Shift 查看详情 · Esc 取消")
        elseif f.compactSelectedPetID then hint = T("选择右侧槽位 · 按住 Shift 查看详情 · Esc 取消")
        elseif left.mode == "QUEUE" then hint = T("按住宠物拖动换序 · 按住 Shift 查看详情 · × 移出队列")
        elseif f.compactDraft then hint = T("选中宠物后点击右侧槽位 · 按住 Shift 查看详情")
        else hint = T("双击召唤宠物 · 按住 Shift 查看宠物详情")
        end
        left.footer:SetText(string.format("%d / %d%s", math.min(#items, (left.offset + 4) * 2), #items,
            hint and ("  ·  " .. hint) or ""))
    end
end

function ns:RefreshLoadoutCabin()
    local f = self.MainFrame
    if not f or not f.homeView or not f.loadoutCards then return end
    local draft = f.compactDraft
    local team = not draft and ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
    if f.compactAbilityPopup and f.compactAbilityPopup:IsShown() then
        local popup = f.compactAbilityPopup
        if popup.draft ~= draft or not draft and popup.team ~= team then popup:Hide() end
    end
    if f.compactTeamLink then
        f.compactTeamLink.text:SetText(team and (team.name or T("未命名队伍")) or T("选择或新建队伍"))
    end
    if f.cabinTargetBtn then
        local route = team and (ns:FindExistingRouteForNPC(team.npcID, team.npcName) or ns:FindRouteContainingTeam(team.name))
        local npcID = tonumber(route and route.npcID or team and team.npcID) or 0
        local npcName = route and route.npcName or team and team.npcName or ""
        f.cabinTargetBtn.text:SetText(draft and T("保存后可绑定目标") or
            ns:GetTargetDisplayName(npcID, npcName))
        f.cabinTargetBtn:EnableMouse(not draft)
    end
    local queueCount = ns.Leveling:GetManualQueueCount()
    local lvSlot = draft and draft.levelingSlot or team and team.hasLevelingSlot and
        (team.levelingSlot or ns.db.settings.levelingSlot or 2)
        or (not draft and not team and ns.db and ns.db.settings and ns.db.settings.standaloneLevelingSlot)
    local deadCount, missingCount, emptyCount, waitingCount, lockedCount = 0, 0, 0, 0, 0
    for slot = 1, 3 do
        local card = f.loadoutCards[slot]
        local isLvSlot = (lvSlot == slot)
        local leveling = isLvSlot and queueCount > 0
        local levelingPaused = isLvSlot and queueCount == 0
        local petID, a1, a2, a3, locked
        if draft then
            local entry = draft.slots[slot]
            if entry then petID = entry.petID; a1, a2, a3 = unpack(entry.abilities) end
            if isLvSlot and not petID and queueCount > 0 then
                local topItem = ns.Leveling:GetQueue()[1]
                if topItem and topItem.petID then petID = topItem.petID end
            end
        else
            petID, a1, a2, a3, locked = C_PetJournal.GetPetLoadOutInfo(slot)
        end
        if locked then lockedCount = lockedCount + 1 end
        local savedSp = team and team.speciesLoadout and tonumber(team.speciesLoadout[slot]) or 0
        local changed = ns.staging.changedSlots and ns.staging.changedSlots[slot]
        local isMissing = team and not changed and not leveling and not levelingPaused
            and savedSp > 0 and not ns:IsSpeciesCollected(savedSp)
        if levelingPaused then
            petID, a1, a2, a3 = nil, nil, nil
        elseif team and not changed and not leveling and not isMissing and savedSp > 0
            and (not petID or C_PetJournal.GetPetInfoByPetID(petID) ~= savedSp)
            and not (team.randomSlots and team.randomSlots[slot] ~= nil) then
            local savedPetID = team.pets and team.pets[slot]
            if savedPetID and savedPetID ~= "LEVELING" and C_PetJournal.GetPetInfoByPetID(savedPetID) == savedSp then
                petID = savedPetID
            else
                petID = ns.AutoRouting:FindAnyCollectedPetForSpecies(savedSp, EMPTY_USED_PETS)
            end
            a1, a2, a3 = nil, nil, nil
        elseif team and team.explicitSlots and not changed and not leveling and savedSp == 0
            and not (team.randomSlots and team.randomSlots[slot] ~= nil) then
            petID = nil
        end
        if isMissing then petID = nil end
        local data = GetRightPetData(petID)
        if data and data.isDead then deadCount = deadCount + 1 end
        if isMissing then missingCount = missingCount + 1 end
        if not data and not isMissing then
            if leveling or levelingPaused then waitingCount = waitingCount + 1
            else emptyCount = emptyCount + 1 end
        end
        card.petData = data
        card.isLevelingSlot = isLvSlot and true or false
        card.levelingPaused = levelingPaused
        local border = isLvSlot and Theme.Colors.borderAmber or isMissing and Theme.Colors.borderRed
            or data and data.isDead and Theme.Colors.borderRed or Theme.Colors.border
        if ns.db.activeTargetSlot == slot and not isLvSlot then border = Theme.Colors.borderBlue end
        card:SetBackdropColor(unpack(CARD_BG))
        card:SetBackdropBorderColor(unpack(border))
        if data then
            if card.icon.plusTxt then card.icon.plusTxt:Hide() end
            card.icon.icon:Show()
            card.icon.icon:SetTexture(data.icon)
            card.icon.icon:SetDesaturated(data.isDead)
            local qCol = Theme.QualityColors[data.rarity] or Theme.QualityColors[2]
            card.icon:SetBackdropBorderColor(qCol[1], qCol[2], qCol[3], 1)
            if card.typeBg then
                Theme:SetPetListTypeTexture(card.typeBg, data.petType)
                card.typeBg:SetVertexColor(1, 1, 1, 0.12)
            end
            if card.favBadge then card.favBadge:SetShown(data.isFavorite == true) end
            card.name:SetText(data.name)
            card.breed:SetText(data.breed or "")
            local quality = math.max(1, math.min(6, tonumber(data.rarity) or 1))
            local localizedQuality = _G["ITEM_QUALITY" .. quality - 1 .. "_DESC"] or T(QUALITY_NAMES[quality])
            card.qualityLabel:SetText("|cff" .. QUALITY_HEX_COLORS[quality] .. localizedQuality .. "|r")
            card.levelBadge.text:SetText(tostring(data.level))
            card.levelBadge:Show()
            SetBar(card.syncBar, data.hpPct, data.isDead)
        else
            if card.favBadge then card.favBadge:Hide() end
            if card.typeBg then card.typeBg:Hide() end
            local speciesIcon = isMissing and select(2, C_PetJournal.GetPetInfoBySpeciesID(savedSp)) or nil
            if isMissing and speciesIcon then
                if card.icon.plusTxt then card.icon.plusTxt:Hide() end
                card.icon.icon:Show()
                card.icon.icon:SetTexture(speciesIcon)
                card.icon.icon:SetDesaturated(true)
            else
                card.icon.icon:Hide()
                if card.icon.plusTxt then
                    card.icon.plusTxt:SetText(isLvSlot and "|cffffc34a+|r" or "|cff38bdf8+|r")
                    card.icon.plusTxt:Show()
                end
            end
            card.icon:SetBackdropBorderColor(unpack(isMissing and Theme.Colors.borderRed or (isLvSlot and Theme.Colors.borderAmber or Theme.Colors.border)))
            if isMissing then
                local spName = C_PetJournal.GetPetInfoBySpeciesID(savedSp)
                card.name:SetText("|cffff7777" .. (spName or T("未收集宠物")) .. "|r")
            elseif isLvSlot then
                card.name:SetText("|cffffc34a" .. T("经验槽 · 点击填入未满级宠物") .. "|r")
            else
                local emptyLabel = ns.db.activeTargetSlot == slot and "在左侧选择宠物" or "点击空槽选择宠物"
                if f.compactSelectedPetID then emptyLabel = "点击此处上阵" end
                card.name:SetText(T(emptyLabel))
            end
            card.breed:SetText("")
            card.qualityLabel:SetText("")
            card.levelBadge:Hide()
            SetBar(card.syncBar, 0, true)
        end
        if card._SyncUnderline then card:_SyncUnderline() end
        if card.underline then card.underline:SetShown(card:IsMouseOver()) end
        local spID = data and data.speciesID or (isMissing and savedSp or nil)
        local sorted = spID and ns:GetSortedPetAbilities(spID) or nil
        local saved = team and team.abilities and team.abilities[slot]
        for col = 1, 3 do
            local ab = card.abBtns[col]
            local selected = (col == 1 and (a1 or 0)) or (col == 2 and (a2 or 0)) or (a3 or 0)
            if (not selected or selected == 0) and saved then selected = saved[col] end
            local first = sorted and sorted[col] or nil
            local second = sorted and sorted[col + 3] or nil
            if selected ~= first and selected ~= second then selected = first end
            ab.abID = selected
            ab.speciesID = spID
            ab:SetShown(selected ~= nil and selected > 0)
            if selected and selected > 0 then
                local _, icon = C_PetJournal.GetPetAbilityInfo(selected)
                ab.icon:SetTexture(icon or EMPTY_PET_ICON)
                ab.icon:SetDesaturated(data and data.isDead or isMissing)
            end
        end
    end
    local dirty = draft or ns.staging.isDirty
    f.cabinSaveBtn:SetShown(dirty and true or false)
    f.cabinRevertBtn:SetShown(dirty and true or false)
    f.cabinSaveBtn.text:SetText(T(draft and "保存队伍" or "保存"))
    f.cabinRevertBtn.text:SetText(T(draft and "取消" or "撤销"))
    if dirty then
        f.cabinStatusBtn.text:SetText("|cffffc34a" .. T(draft and "新建队伍" or "未保存修改") .. "|r")
    elseif missingCount > 0 then
        f.cabinStatusBtn.text:SetText("|cffff6565●|r " .. T("缺失宠物"))
    elseif deadCount > 0 then
        f.cabinStatusBtn.text:SetText("|cffff6565●|r " .. T("宠物阵亡"))
    elseif lockedCount > 0 then
        f.cabinStatusBtn.text:SetText("|cffffc34a●|r " .. ns:UXText("lockedSlots", lockedCount))
    elseif waitingCount > 0 then
        f.cabinStatusBtn.text:SetText("|cffffc34a●|r " .. ns:UXText("waitingQueue"))
    elseif emptyCount > 0 then
        f.cabinStatusBtn.text:SetText("|cffffc34a●|r " .. ns:UXText("emptySlots", emptyCount))
    else
        f.cabinStatusBtn.text:SetText("|cff10b981●|r " .. T("就绪"))
    end
    self:RefreshCompactLeftPanel()
    if self.RefreshMinimalMode then self:RefreshMinimalMode() end
end

function ns:InitHomeView(f, header)
    local home = CreateFrame("Frame", nil, f)
    home:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    home:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f.homeView = home
    ns.db.activeTargetSlot = nil

    if f.petHubBtn then f.petHubBtn:Hide() end
    if f.teamHubBtn then f.teamHubBtn:Hide() end
    local left = CreateFrame("Frame", nil, home, "BackdropTemplate")
    left:SetPoint("TOPLEFT", 16, -12)
    left:SetSize(728, 540)
    Theme:ApplyBackdrop(left, PANEL_BG, Theme.Colors.border, false)
    left.mode, left.offset, left.rows = "PETS", 0, {}
    f.compactLeft = left
    left.petTab = MakeLink(left, "所有宠物", 104, function() SetLeftMode("PETS") end, "LEFT", HEADER_TEX_ROOT .. "pets.tga")
    left.petTab:SetPoint("TOPLEFT", 16, -12)
    left.teamTab = MakeLink(left, "队伍管理", 104, function() SetLeftMode("TEAMS") end, "LEFT", HEADER_TEX_ROOT .. "team.tga")
    left.teamTab:SetPoint("LEFT", left.petTab, "RIGHT", 12, 0)
    left.queueTab = MakeLink(left, "练级队列", 140, function() SetLeftMode("QUEUE") end, "LEFT", ACTION_TEX_ROOT .. "queue.tga")
    left.queueTab:SetPoint("LEFT", left.teamTab, "RIGHT", 12, 0)
    left.queuePulse = left.queueTab:CreateTexture(nil, "BACKGROUND")
    left.queuePulse:SetAllPoints()
    left.queuePulse:SetColorTexture(0.10, 0.62, 0.84, 0.24)
    left.queuePulse:SetAlpha(0)
    left.queuePulseAnim = left.queuePulse:CreateAnimationGroup()
    local fade = left.queuePulseAnim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(1.25)
    left.queuePulseAnim:SetScript("OnFinished", function() left.queuePulse:SetAlpha(0) end)

    left.clearLink = MakeLink(left, "清空队列", 94, function()
        local order = ns.db and ns.db.manualQueueOrder
        if not order or #order == 0 then return end
        f.compactQueueUndo = CopyTable(order)
        ns.Leveling:ClearManualQueue()
        ns.Leveling:RefreshSelectedSlot()
        SetLeftMode("PETS")
        RefreshBoth()
    end, "RIGHT", ACTION_TEX_ROOT .. "clear.tga")
    left.clearLink:SetPoint("TOPRIGHT", -16, -12)
    left.undoLink = MakeLink(left, "已清空 · 撤销", 160, function()
        if not f.compactQueueUndo or ns.Leveling:GetManualQueueCount() > 0 then return end
        ns.db.manualQueueOrder = f.compactQueueUndo
        f.compactQueueUndo = nil
        ns.Leveling:RefreshSelectedSlot()
        SetLeftMode("QUEUE")
        RefreshBoth()
    end, "RIGHT", ACTION_TEX_ROOT .. "restore.tga")
    left.undoLink:SetPoint("TOPRIGHT", -16, -12)

    -- 队伍管理顶部工具栏：全部展开 / 全部收纳 / 查看缺失宠物汇总（统一文本下划线按钮）
    local expandAllBtn = Theme:CreateActionButton(left, 82, 24, "全部展开", "expand", nil, nil, false, "LEFT")
    expandAllBtn:SetPoint("TOPLEFT", 16, -51)
    expandAllBtn:SetScript("OnClick", function()
        ns.db.expandedMatrixGroups  = ns.db.expandedMatrixGroups  or {}
        ns.db.expandedMatrixTargets = ns.db.expandedMatrixTargets or {}
        for _, gName in ipairs(ns.db.teamGroups or {}) do
            ns.db.expandedMatrixGroups[gName] = true
        end
        left._expandAllPending = true
        if ns.BumpTeamTreeRevision then ns:BumpTeamTreeRevision() end
        ns:RefreshCompactLeftPanel()
    end)
    expandAllBtn:Hide()
    left.expandAllBtn = expandAllBtn

    local collapseAllBtn = Theme:CreateActionButton(left, 82, 24, "全部收纳", "collapse", nil, nil, false, "LEFT")
    collapseAllBtn:SetPoint("LEFT", expandAllBtn, "RIGHT", 12, 0)
    collapseAllBtn:SetScript("OnClick", function()
        ns.db.expandedMatrixGroups  = ns.db.expandedMatrixGroups  or {}
        ns.db.expandedMatrixTargets = ns.db.expandedMatrixTargets or {}
        wipe(ns.db.expandedMatrixGroups)
        wipe(ns.db.expandedMatrixTargets)
        left._expandAllPending = nil
        left.offset = 0
        if ns.BumpTeamTreeRevision then ns:BumpTeamTreeRevision() end
        ns:RefreshCompactLeftPanel()
    end)
    collapseAllBtn:Hide()
    left.collapseAllBtn = collapseAllBtn

    local checkMissingBtn = Theme:CreateActionButton(left, 170, 24, "查看缺失宠物汇总", "missing", nil, "WARNING", false, "LEFT")
    checkMissingBtn:SetPoint("LEFT", collapseAllBtn, "RIGHT", 12, 0)
    checkMissingBtn:SetScript("OnClick", function()
        local report, uCount = ns:CollectMissingPetsForTeams(ns.db.teams or {})
        if #report > 0 and ns.ShowMissingPetsModal then
            ns:ShowMissingPetsModal(report, uCount)
        end
    end)
    checkMissingBtn:Hide()
    left.checkMissingBtn = checkMissingBtn

    local searchBox = CreateFrame("EditBox", nil, left, "BackdropTemplate")
    searchBox:SetSize(555, 24)
    searchBox:SetPoint("TOPLEFT", 18, -51)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject(GameFontHighlightSmall)
    searchBox:SetTextInsets(6, 22, 0, 0)
    searchBox:SetTextColor(0.85, 0.91, 0.96)
    Theme:ApplyBackdrop(searchBox, Theme.Colors.bgInput, Theme.Colors.border, false)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        ns:CancelCompactInteraction()
    end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local compactSearchTimer
    local function CancelCompactSearch()
        if compactSearchTimer then compactSearchTimer:Cancel(); compactSearchTimer = nil end
    end
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if self._clearingSearch then return end
        left.offset = 0
        CancelCompactSearch()
        if not userInput then
            ns:RefreshCompactLeftPanel()
            return
        end
        compactSearchTimer = C_Timer.NewTimer(0.15, function()
            compactSearchTimer = nil
            if left:IsShown() then ns:RefreshCompactLeftPanel() end
        end)
    end)
    left:HookScript("OnHide", CancelCompactSearch)
    left.searchBox = searchBox
    local placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", searchBox, "LEFT", 6, 0)
    placeholder:SetText(T("搜索宠名 / 技能 / 拼音 / 备注..."))
    left.searchPlaceholder = placeholder
    searchBox:HookScript("OnTextChanged", function(self) placeholder:SetShown(self:GetText() == "" and not self:HasFocus()) end)
    searchBox:HookScript("OnEditFocusGained", function()
        placeholder:Hide()
    end)
    searchBox:HookScript("OnEditFocusLost", function(self)
        placeholder:SetShown(self:GetText() == "")
    end)
    Theme:EnableSearchClearButton(searchBox, function()
        left.offset = 0
        CancelCompactSearch()
        placeholder:SetShown(not searchBox:HasFocus())
        ns:RefreshCompactLeftPanel()
    end)

    local filterBtn = CreateFrame("Button", nil, left)
    filterBtn:SetSize(24, 24)
    filterBtn:SetPoint("TOPRIGHT", -16, -51)
    filterBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local filterArrow = filterBtn:CreateTexture(nil, "ARTWORK")
    filterArrow:SetPoint("CENTER", 0, 0)
    Theme:ConfigureButtonIcon(filterArrow, ACTION_TEX_ROOT .. "filter.tga")
    filterArrow:SetVertexColor(1, 1, 1, 1)
    filterBtn.icon = filterArrow
    Theme:RegisterInlineIconMetrics(filterBtn, function(button)
        local size = Theme:GetButtonIconSize(button, 24)
        button.icon:SetSize(size, size)
    end)
    filterBtn:SetScript("OnEnter", function(self)
        filterArrow:SetVertexColor(0.22, 0.88, 1.0, 1)
        ns:ShowCustomTooltip(self, "ANCHOR_TOP", T("筛选"))
    end)
    filterBtn:SetScript("OnLeave", function(self)
        filterArrow:SetVertexColor(1, 1, 1, 1)
        ns:HideCustomTooltip(self)
    end)
    filterBtn:SetScript("OnClick", function(button)
        if left.mode == "QUEUE" then ns:ToggleQueueFilterMenu(button)
        else ns:TogglePetFilterMenu(button) end
    end)
    left.filterLink = filterBtn
    local function OnLeftWheel(_, delta)
        local currentOffset = left.offset or 0
        local nextOffset = math.max(0, currentOffset - delta)
        if nextOffset == currentOffset then return end
        left.offset = nextOffset
        ns:RefreshCompactLeftPanel()
    end
    left:EnableMouseWheel(true)
    left:SetScript("OnMouseWheel", OnLeftWheel)

    local list = CreateFrame("Frame", nil, left)
    list:SetPoint("TOPLEFT", 16, -94)
    list:SetSize(684, 402)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", OnLeftWheel)
    left.list = list

    local scrollTrack = CreateFrame("Button", nil, left, "BackdropTemplate")
    scrollTrack:SetPoint("TOPRIGHT", -12, -94)
    scrollTrack:SetSize(8, 402)
    Theme:ApplyBackdrop(scrollTrack, { 0.07, 0.07, 0.07, 0.85 }, Theme.Colors.border, false)
    scrollTrack:EnableMouseWheel(true)
    scrollTrack:SetScript("OnMouseWheel", OnLeftWheel)

    local scrollThumb = CreateFrame("Button", nil, scrollTrack, "BackdropTemplate")
    scrollThumb:SetSize(8, 60)
    scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, 0)
    Theme:ApplyBackdrop(scrollThumb, { 0.22, 0.48, 0.72, 0.9 }, Theme.Colors.borderBlue, false)
    scrollThumb:RegisterForDrag("LeftButton")
    local function UpdateScrollFromCursor()
        local maxOff = left._maxOff or 0
        if maxOff <= 0 then return end
        local scale = scrollTrack:GetEffectiveScale() or 1
        local _, cy = GetCursorPosition()
        cy = cy / scale
        local top = scrollTrack:GetTop()
        local bottom = scrollTrack:GetBottom()
        if not top or not bottom or top <= bottom then return end
        local thumbH = scrollThumb:GetHeight() or 40
        local ratio = (top - cy - thumbH * 0.5) / math.max(1, (top - bottom - thumbH))
        ratio = math.max(0, math.min(1, ratio))
        local nextOff = math.floor(ratio * maxOff + 0.5)
        if nextOff ~= left.offset then
            left.offset = nextOff
            ns:RefreshCompactLeftPanel()
        end
    end
    scrollThumb:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", UpdateScrollFromCursor) end)
    scrollThumb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    scrollThumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    scrollThumb:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    scrollTrack:SetScript("OnClick", UpdateScrollFromCursor)
    left.scrollTrack = scrollTrack
    left.scrollThumb = scrollThumb
    for i = 1, MAX_VISIBLE do left.rows[i] = MakePetRow(list, i) end
    left.emptyText = left:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    left.emptyText:SetPoint("CENTER", list, "CENTER", 0, 0)
    left.emptyText:SetWidth(620)
    left.emptyText:SetJustifyH("CENTER")
    Theme:HookLocalizedFontString(left.emptyText)
    left.footer = left:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    left.footer:SetPoint("BOTTOMRIGHT", -16, 14)
    left.footer:SetWidth(660)
    left.footer:SetJustifyH("RIGHT")
    Theme:HookLocalizedFontString(left.footer)

    -- 队伍管理底部 5 个独立核心操作按钮：新建队伍 | 新建队伍分组 | 同步 Rematch | 导入 | 导出
    local teamNewBtn = Theme:CreateActionButton(left, 114, 26, "新建队伍", "new-team", nil, "PRIMARY")
    teamNewBtn:SetPoint("BOTTOMLEFT", 24, 10)
    teamNewBtn:SetScript("OnClick", function()
        if ns.ShowTeamBuilderModal then
            ns:ShowTeamBuilderModal(nil, "未分组队伍")
        else
            ns:ShowQuickInputModal("NEW_TEAM", "未分组队伍")
        end
    end)
    teamNewBtn:Hide()
    left.teamNewBtn = teamNewBtn

    local teamNewGroupBtn = Theme:CreateActionButton(left, 126, 26, "新建队伍分组", "new-group")
    teamNewGroupBtn:SetPoint("LEFT", teamNewBtn, "RIGHT", 24, 0)
    teamNewGroupBtn:SetScript("OnClick", function()
        ns:ShowQuickInputModal("NEW_GROUP")
    end)
    teamNewGroupBtn:Hide()
    left.teamNewGroupBtn = teamNewGroupBtn

    local teamExportBtn = Theme:CreateActionButton(left, 104, 26, "导出", "export", "导出队伍或对战脚本")
    teamExportBtn:SetPoint("BOTTOMRIGHT", -24, 10)
    teamExportBtn:SetScript("OnClick", function()
        ns:ShowExportChoiceModal()
    end)
    teamExportBtn:Hide()
    left.teamExportBtn = teamExportBtn

    local teamImportBtn = Theme:CreateActionButton(left, 104, 26, "导入", "import", "导入队伍或对战脚本")
    teamImportBtn:SetPoint("RIGHT", teamExportBtn, "LEFT", -24, 0)
    teamImportBtn:SetScript("OnClick", function()
        ns:ShowImportModal("TEAM")
    end)
    teamImportBtn:Hide()
    left.teamImportBtn = teamImportBtn
    left.teamImportExportBtn = teamImportBtn

    local teamSyncRematchBtn = Theme:CreateActionButton(left, 122, 26, "同步 Rematch", "sync", nil, "WARNING")
    teamSyncRematchBtn:SetPoint("LEFT", teamNewGroupBtn, "RIGHT", 24, 0)
    teamSyncRematchBtn:SetScript("OnClick", function()
        local ok = ns:MigrateFromRematch(true)
        if ok then
            ns:RefreshCompactLeftPanel()
        end
    end)
    teamSyncRematchBtn:Hide()
    left.teamSyncRematchBtn = teamSyncRematchBtn

    -- 兼容旧代码对 ns.TeamMatrixModal 的引用，统一转发至内嵌队伍管理面板
    ns.TeamMatrixModal = {
        _treeDirty = false,
        searchBox = searchBox,
        IsShown = function()
            return f:IsShown() and f.mainUIStyle ~= "MINIMAL" and left.mode == "TEAMS"
        end,
        IsVisible = function()
            return f:IsVisible() and f.mainUIStyle ~= "MINIMAL" and left.mode == "TEAMS"
        end,
        Hide = function() end,
        Show = function() ns:ShowTeamMatrixModal() end,
        Refresh = function()
            if f:IsShown() then ns:RefreshCompactLeftPanel() end
        end,
    }

    local cabin = CreateFrame("Frame", nil, home, "BackdropTemplate")
    cabin:SetPoint("TOPLEFT", 756, -12)
    cabin:SetSize(348, 540)
    Theme:ApplyBackdrop(cabin, PANEL_BG, Theme.Colors.border, false)
    home.cabin = cabin
    f.compactTeamLink = MakeLink(cabin, "选择队伍", 300, function(button, mouseButton)
        if mouseButton == "RightButton" then
            ns:ShowTeamContextMenu(button, ns.db.selectedTeamIdx or 1)
        else
            SetLeftMode("TEAMS")
        end
    end, "LEFT", HEADER_TEX_ROOT .. "team.tga")
    f.compactTeamLink:SetPoint("TOPLEFT", 16, -10)
    f.compactTeamLink.text:SetTextColor(0.96, 0.98, 1)
    SetLinkTip(f.compactTeamLink, function() return T("打开队伍管理") end)
    f.compactName = CreateFrame("EditBox", nil, cabin, "BackdropTemplate")
    f.compactName:SetSize(310, 24)
    f.compactName:SetPoint("TOPLEFT", 16, -10)
    f.compactName:SetFontObject(GameFontHighlightSmall)
    f.compactName:SetTextInsets(4, 4, 0, 0)
    f.compactName:SetAutoFocus(false)
    f.compactName:SetMaxLetters(80)
    f.compactName:EnableMouse(true)
    f.compactName:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        ns.db.activeTargetSlot = ns.db.activeTargetSlot or 1
        RefreshBoth()
    end)
    f.compactName:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        ns:CancelCompactInteraction()
    end)
    Theme:ApplyBackdrop(f.compactName, CARD_BG, Theme.Colors.borderBlue, false)
    local namePlaceholder = f.compactName:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    namePlaceholder:SetPoint("LEFT", 5, 0)
    namePlaceholder:SetText(T("输入队伍名称"))
    Theme:HookLocalizedFontString(namePlaceholder)
    f.compactName:SetScript("OnTextChanged", function(self)
        namePlaceholder:SetShown(self:GetText() == "")
    end)
    f.compactName:Hide()
    f.cabinTargetBtn = MakeLink(cabin, "未绑定目标", 312, function()
        if ns.ShowRoutingModal then ns:ShowRoutingModal(false, true) end
    end, "LEFT", STATUS_TEX_ROOT .. "current-target.tga")
    f.cabinTargetBtn:SetPoint("TOPLEFT", 16, -39)
    SetLinkTip(f.cabinTargetBtn, function() return T("打开目标管理") end)
    MakeRule(cabin, -69)
    f.loadoutCards = {}
    for slot = 1, 3 do f.loadoutCards[slot] = MakeRightSlot(cabin, slot) end
    f.cabinStatusBtn = MakeLink(cabin, "就绪", 128, function() end)
    f.cabinStatusBtn:SetPoint("BOTTOMLEFT", 16, 9)
    f.cabinStatusBtn:EnableMouse(false)
    f.cabinSaveBtn = MakeLink(cabin, "保存", 106, function()
        if f.compactDraft then SaveDraft(f) else ns:SaveStagingToCurrentTeam() end
    end, "RIGHT", ACTION_TEX_ROOT .. "save.tga")
    f.cabinSaveBtn:SetPoint("BOTTOMRIGHT", -88, 9)
    f.cabinRevertBtn = MakeLink(cabin, "撤销", 68, function()
        if f.compactDraft then EndDraft(f); RefreshBoth()
        elseif ns:RevertCurrentTeamToDefault() then RefreshBoth() end
    end, "RIGHT", ACTION_TEX_ROOT .. "restore.tga")
    f.cabinRevertBtn:SetPoint("BOTTOMRIGHT", -16, 9)
    f.cabinSaveBtn:Hide()
    f.cabinRevertBtn:Hide()

    -- The unsaved-changes guard must also be visible while the full view is hidden.
    local prompt = CreateFrame("Frame", nil, f, "BackdropTemplate")
    prompt:Hide()
    prompt:SetSize(512, 148)
    prompt:SetPoint("CENTER", f, "CENTER", 0, 0)
    prompt:SetFrameStrata("FULLSCREEN_DIALOG")
    Theme:ApplyBackdrop(prompt, { 0.077, 0.077, 0.077, 0.99 }, Theme.Colors.borderAmber, true)
    ns:MakeModal(prompt)
    prompt:HookScript("OnHide", function(self) self.pendingAction = nil end)
    prompt.message = prompt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    prompt.message:SetPoint("TOP", 0, -22)
    prompt.message:SetText(T("当前队伍有未保存的修改"))
    Theme:HookLocalizedFontString(prompt.message)
    local save = MakeLink(prompt, "保存并继续", 112, function()
        local action = prompt.pendingAction
        if f.compactDraft then
            if strtrim(f.compactName:GetText() or "") == "" then
                prompt:Hide()
                SaveDraft(f)
                return
            end
            if not SaveDraft(f) then return end
        elseif not ns:SaveStagingToCurrentTeam() then return end
        prompt:Hide()
        if action then action() end
    end, "CENTER", ACTION_TEX_ROOT .. "save.tga")
    save:SetPoint("BOTTOMLEFT", 16, 22)
    local tempUse = MakeLink(prompt, "临时队伍", 112, function()
        local action = prompt.pendingAction
        ns.temporaryTeamActive = true
        if f.compactDraft then
            EndDraft(f)
        elseif ns.staging then
            ns.staging.isDirty = false
        end
        RefreshBoth()
        prompt:Hide()
        if action then action() end
    end, "CENTER", ACTION_TEX_ROOT .. "temp_team_clock.tga")
    tempUse:SetPoint("LEFT", save, "RIGHT", 10, 0)
    local discard = MakeLink(prompt, "放弃修改", 112, function()
        local action = prompt.pendingAction
        if f.compactDraft then EndDraft(f); RefreshBoth()
        elseif not ns:RevertCurrentTeamToDefault() then return end
        prompt:Hide()
        if action then action() end
    end, "CENTER", ACTION_TEX_ROOT .. "clear.tga")
    discard:SetPoint("LEFT", tempUse, "RIGHT", 10, 0)
    local cancel = MakeLink(prompt, "继续编辑", 112, function() prompt:Hide() end, "CENTER", ACTION_TEX_ROOT .. "restore.tga")
    cancel:SetPoint("LEFT", discard, "RIGHT", 10, 0)
    f.compactSwitchPrompt = prompt
end
