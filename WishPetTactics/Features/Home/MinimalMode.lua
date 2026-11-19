local ADDON_NAME, ns = ...
local Theme = ns.Theme

-- V7: Two presentations of the SAME loadout cards and staging data.
-- The 348-unit roster and its 320x132 cards retain their original sizes.
-- The shared sidebar docks outside either window without widening its content.
local FULL_WIDTH, FULL_HEIGHT = 1120, 620
local MINI_CONTENT_WIDTH = 348
local MINI_WIDTH, MINI_HEIGHT = MINI_CONTENT_WIDTH, 540
local FULL_CARD_W, FULL_CARD_H = 320, 132
local MINI_CARD_W, MINI_CARD_H = 320, 132
local DOWN_CHEVRON = " |TInterface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Common\\down.tga:10:10:0:0|t"
local MINI_CARD_STEP = 142
local PICKER_ROWS, PICKER_COLS = 6, 1
local PICKER_ROW_W, PICKER_ROW_H = 328, 39
local PICKER_COL_STEP, PICKER_ROW_STEP = 0, 41
local BG = { 0.04, 0.04, 0.04, 0.98 }
local ROW_BG = { 0.07, 0.07, 0.07, 0.98 }
local BORDER = Theme.Colors.border
local CYAN = Theme.Colors.borderBlue
local ICON_UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"

local function T(str) return ns:T(str) end

local HEADER_TEX_ROOT = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Header\\"
local ACTION_TEX_ROOT = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Actions\\"
local STATUS_TEX_ROOT = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Status\\"

local function Link(parent, text, width, callback, alignment, iconPath)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 24)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local effAlign = alignment or "LEFT"
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
    b.text:SetText(T(text))
    b.text:SetTextColor(0.62, 0.76, 0.86)
    Theme:HookLocalizedFontString(b.text)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetColorTexture(0.1, 0.87, 1, 0.9)
    b.line:SetHeight(1)
    local function ShouldHideLine()
        return b._noUnderline or Theme:IsIconOrSymbolOnlyText(b.text:GetText())
    end
    local function SyncMiniLineWidth()
        if b.icon then Theme:LayoutLinkIcon(b, effAlign) end
        if ShouldHideLine() then
            b.line:Hide()
            return
        end
        local align = b.text:GetJustifyH() or effAlign
        local extW = b.icon and (b.icon:GetWidth() + 4) or 0
        Theme:AnchorStandardUnderline(b.line, b, b.text, align, extW)
    end
    b.text._wishOnTextChanged = function()
        if b.icon or b.line:IsShown() then SyncMiniLineWidth() end
    end
    if b.icon then Theme:RegisterInlineIconMetrics(b, SyncMiniLineWidth)
    else SyncMiniLineWidth() end
    b.line:Hide()
    b:SetScript("OnEnter", function(self)
        self.text:SetTextColor(0.96, 0.99, 1)
        if not ShouldHideLine() then
            SyncMiniLineWidth()
            self.line:Show()
        else
            self.line:Hide()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.text:SetTextColor(0.62, 0.76, 0.86)
        self.line:Hide()
    end)
    b:SetScript("OnClick", callback)
    return b
end

local function Tip(button, label)
    button:HookScript("OnEnter", function(self)
        local txt = T(type(label) == "function" and label() or label)
        if txt and txt ~= "" then
            ns:ShowCustomTooltip(self, "ANCHOR_TOP", txt)
        end
    end)
    button:HookScript("OnLeave", function(self)
        ns:HideCustomTooltip(self)
    end)
end

local function MakePickerRow(picker, index)
    local row = CreateFrame("Button", nil, picker, "BackdropTemplate")
    row:SetSize(PICKER_ROW_W, PICKER_ROW_H)
    row:SetPoint("TOPLEFT", 10 + ((index - 1) % PICKER_COLS) * PICKER_COL_STEP,
        -50 - math.floor((index - 1) / PICKER_COLS) * PICKER_ROW_STEP)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    Theme:ApplyBackdrop(row, ROW_BG, BORDER, false)
    row:SetClipsChildren(true)
    row.typeBg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.typeBg:SetSize(PICKER_ROW_H, PICKER_ROW_H)
    row.typeBg:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.typeBg:SetAlpha(0.14)
    row.typeBg:Hide()
    row.icon = Theme:CreateCroppedIcon(row, 29)
    row.icon:SetPoint("LEFT", 7, 0)
    row.icon:EnableMouse(false)
    row.favBadge = row.icon:CreateTexture(nil, "OVERLAY")
    row.favBadge:SetSize(15, 15)
    row.favBadge:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -3, 3)
    if row.favBadge.SetAtlas then
        row.favBadge:SetAtlas("PetJournal-FavoritesIcon")
    end
    row.favBadge:Hide()
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("TOPLEFT", 46, -5)
    row.name:SetPoint("RIGHT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    Theme:HookLocalizedFontString(row.name)
    row.underline = row:CreateTexture(nil, "ARTWORK")
    row.underline:SetColorTexture(0.1, 0.87, 1, 0.9)
    row.underline:SetHeight(1)
    row.underline:SetPoint("BOTTOMLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.underline:Hide()
    local function SyncRowUnderline()
        Theme:AnchorStandardUnderline(row.underline, row, row.name, "LEFT", 0)
    end
    row.name._wishOnTextChanged = function()
        if row.underline:IsShown() then SyncRowUnderline() end
    end
    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.info:SetPoint("TOPLEFT", 46, -23)
    row.info:SetPoint("RIGHT", -8, 0)
    row.info:SetJustifyH("LEFT")
    row.info:SetWordWrap(false)
    Theme:HookLocalizedFontString(row.info)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta)
        picker.page = math.max(0, (picker.page or 0) - delta)
        ns:RefreshMinimalPicker()
    end)
    row:SetScript("OnEnter", function(self)
        SyncRowUnderline()
        self.underline:Show()
        if self.pet and ns.ShowPetDetailTooltip then
            ns:ShowPetDetailTooltip(self, self.pet, false)
        end
    end)
    row:SetScript("OnLeave", function(self)
        if not self.selected then
            self.underline:Hide()
        end
        if ns.HidePetDetailTooltip then ns:HidePetDetailTooltip(false) end
    end)
    row:SetScript("OnClick", function(self, mouseButton)
        if picker.mode == "TEAMS" then
            if not self.teamIndex then return end
            if mouseButton == "RightButton" then
                ns:ShowTeamContextMenu(self, self.teamIndex)
                return
            end
            local indexToSelect = self.teamIndex
            ns:RequestCompactTeamSwitch(indexToSelect, function()
                ns:CloseMinimalPicker()
                ns:RefreshHomeView()
            end)
            return
        end
        if not self.pet or not self.pet.petID then return end
        if mouseButton == "LeftButton" and picker.backupCallback then
            local callback, petID = picker.backupCallback, self.pet.petID
            ns:CloseMinimalPicker()
            callback(petID)
            return
        end
        if mouseButton == "RightButton" then
            ns:ShowPetContextMenu(self, self.pet)
            return
        end
        if picker.slot and ns:PutCompactPet(picker.slot, self.pet.petID, picker.mode == "QUEUE") then
            ns:CloseMinimalPicker()
        else
            picker.selectedPetID = self.pet.petID
            ns:RefreshMinimalPicker()
        end
    end)
    row:SetScript("OnDoubleClick", function(self)
        if picker.backupCallback then return end
        if not self.pet or not self.pet.petID then return end
        if not InCombatLockdown() and not (C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle()) then
            if picker.slot and ns:PutCompactPet(picker.slot, self.pet.petID, picker.mode == "QUEUE") then
                ns:CloseMinimalPicker()
            elseif self.pet.isCollected and C_PetJournal.SummonPetByGUID then
                C_PetJournal.SummonPetByGUID(self.pet.petID)
            end
        end
    end)
    return row
end

function ns:RefreshMinimalPicker()
    local f = self.MainFrame
    local picker = f and f.minimalPicker
    if not picker or not picker:IsShown() or not self.db then return end
    local query = strlower(strtrim(picker.search:GetText() or ""))
    if picker.searchHint then
        if picker.mode == "TEAMS" then
            picker.searchHint:SetText(T("搜索队伍 / 分组..."))
        elseif picker.mode == "QUEUE" then
            picker.searchHint:SetText(T("搜索队列宠物..."))
        else
            picker.searchHint:SetText(T("搜索宠名 / 技能 / 拼音 / 备注..."))
        end
    end
    local items = picker.cachedItems or {}
    local pool = picker.itemPool or {}
    picker.itemPool = pool

    if picker.mode == "PETS" or picker.mode == "ALL_PETS" then
        local list = self.SearchFilter:GetFilteredPets(query) or {}
        local revision = self.SearchFilter:GetResultsRevision()
        if picker.cachedMode ~= picker.mode or picker.cachedQuery ~= query or picker.cachedRevision ~= revision then
            wipe(items)
            local count = 0
            for _, pet in ipairs(list) do
                if pet.petID and pet.isCollected and pet.canBattle ~= false then
                    count = count + 1
                    local entry = pool[count]
                    if not entry then
                        entry = {}
                        pool[count] = entry
                    end
                    entry.pet = pet
                    entry.team = nil
                    entry.teamIndex = nil
                    items[count] = entry
                end
            end
            picker.cachedQuery, picker.cachedRevision = query, revision
        end
    elseif picker.mode == "QUEUE" then
        local queueList = self.Leveling and self.Leveling.GetQueue and self.Leveling:GetQueue(query) or {}
        local queueRev = ((self.Leveling and self.Leveling.GetQueueRevision and self.Leveling:GetQueueRevision()) or 0) * 10000 + #(self.db.manualQueueOrder or {})
        if picker.cachedMode ~= "QUEUE" or picker.cachedQuery ~= query or picker.cachedQueueRev ~= queueRev then
            wipe(items)
            local count = 0
            for _, pet in ipairs(queueList) do
                if pet.petID then
                    count = count + 1
                    local entry = pool[count]
                    if not entry then
                        entry = {}
                        pool[count] = entry
                    end
                    entry.pet = pet
                    entry.team = nil
                    entry.teamIndex = nil
                    items[count] = entry
                end
            end
            picker.cachedQuery, picker.cachedQueueRev = query, queueRev
        end
    else
        local teamRev = (self._teamTreeRevision or 0) * 10000 + #(self.db.teams or {})
        if picker.cachedMode ~= "TEAMS" or picker.cachedQuery ~= query or picker.cachedTeamRev ~= teamRev then
            wipe(items)
            local poolIdx = 0
            for i, team in ipairs(self.db.teams or {}) do
                local ok, score = true, 0
                if query ~= "" then
                    ok, score = ns.FuzzySearch:MatchFields(query, team.name, team.group)
                end
                if ok then
                    poolIdx = poolIdx + 1
                    local entry = pool[poolIdx]
                    if not entry then
                        entry = {}
                        pool[poolIdx] = entry
                    end
                    entry.teamIndex = i
                    entry.team = team
                    entry.pet = nil
                    entry._matchScore = score
                    items[#items + 1] = entry
                end
            end
            if query ~= "" and #items > 1 then
                table.sort(items, function(a, b)
                    if (a._matchScore or 0) ~= (b._matchScore or 0) then
                        return (a._matchScore or 0) > (b._matchScore or 0)
                    end
                    return a.teamIndex < b.teamIndex
                end)
            end
            picker.cachedQuery, picker.cachedTeamRev = query, teamRev
        end
    end
    picker.cachedMode, picker.cachedItems = picker.mode, items
    local pages = math.max(1, math.ceil(#items / PICKER_ROWS))
    picker.page = math.max(0, math.min(pages - 1, picker.page or 0))
    for i = 1, PICKER_ROWS do
        local row = picker.rows[i]
        local item = items[picker.page * PICKER_ROWS + i]
        row.pet, row.teamIndex = nil, nil
        if not item then
            row:Hide()
        else
            row:Show()
            if item.team then
                if row.favBadge then row.favBadge:Hide() end
                if row.typeBg then row.typeBg:Hide() end
                local team = item.team
                row.teamIndex = item.teamIndex
                row.name:SetText(team.name or T("未命名队伍"))
                row.info:SetText(T(team.group or "未分组队伍") ..
                    (team.npcName and team.npcName ~= "" and (" · " .. team.npcName) or ""))
                local first = team.pets and team.pets[1]
                row.icon.icon:SetTexture(first and first ~= "LEVELING"
                    and (select(9, C_PetJournal.GetPetInfoByPetID(first)) or ICON_UNKNOWN)
                    or "Interface\\Icons\\INV_Misc_GroupLooking")
                row.icon:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 1)
                row.selected = item.teamIndex == self.db.selectedTeamIdx
            else
                local pet = item.pet
                row.pet = pet
                if row.favBadge then row.favBadge:SetShown(pet.isFavorite == true) end
                row.name:SetText(pet.name or T("未知宠物"))
                local infoText
                if picker.mode == "QUEUE" then
                    local statusStr = ""
                    if pet.isDead then
                        statusStr = " · |cffff4444" .. T("阵亡") .. "|r"
                    elseif pet.hpPct and pet.hpPct < 100 then
                        statusStr = string.format(" · |cffffcc00%d%%|r", pet.hpPct)
                    end
                    infoText = T("等级") .. " " .. tostring(pet.level or 1)
                        .. "   ·   " .. (pet.breed or "") .. statusStr
                else
                    infoText = T("等级") .. " " .. tostring(pet.level or 1)
                        .. "   ·   " .. (pet.breed or "")
                end
                row.info:SetText(infoText)
                row.icon.icon:SetTexture(pet.icon or ICON_UNKNOWN)
                local qCol = pet.isCollected and (Theme.QualityColors[pet.rarity] or Theme.QualityColors[2]) or BORDER
                row.icon:SetBackdropBorderColor(qCol[1], qCol[2], qCol[3], 1)
                if row.typeBg then
                    Theme:SetPetListTypeTexture(row.typeBg, pet.petType)
                    row.typeBg:SetVertexColor(1, 1, 1, 0.14)
                end
                row.selected = (picker.selectedPetID and pet.petID == picker.selectedPetID)
            end
            row:SetBackdropBorderColor(unpack(BORDER))
            if row.underline then row.underline:SetShown(row.selected) end
        end
    end
    picker.empty:SetShown(#items == 0)
    if #items == 0 then
        if picker.mode == "TEAMS" then
            picker.empty:SetText(T("没有符合条件的队伍。"))
        elseif picker.mode == "QUEUE" then
            picker.empty:SetText(T("练级队列中没有宠物。"))
        else
            picker.empty:SetText(T("没有符合条件的宠物。"))
        end
    end
    picker.pageInfo:SetText(string.format("%d / %d", picker.page + 1, pages))
    picker.prev:SetShown(picker.page > 0)
    picker.next:SetShown(picker.page + 1 < pages)
    picker.manage:SetShown(picker.mode == "TEAMS")
    picker.footer:SetShown(picker.mode ~= "TEAMS")
    if picker.mode == "QUEUE" or picker.mode == "ALL_PETS" then
        picker.footer:SetText(T("右键管理 · 滚轮翻页"))
    else
        picker.footer:SetText(T("左键选择 · 按住 Shift 详情"))
    end
    if picker.mode == "TEAMS" then
        picker.title:SetText(T("切换队伍"))
    elseif picker.mode == "QUEUE" then
        picker.title:SetText(T("练级队列"))
    elseif picker.mode == "ALL_PETS" then
        picker.title:SetText(T("所有宠物"))
    else
        picker.title:SetText(T("选择出战宠物"))
    end
end

function ns:CloseMinimalPicker()
    local f = self.MainFrame
    local picker = f and f.minimalPicker
    if not picker then return end
    picker:Hide()
    picker.search:ClearFocus()
    if picker.backupCallback then
        picker.backupCallback = nil
        picker:SetParent(f)
        picker:SetFrameStrata("DIALOG")
        picker:SetFrameLevel(f:GetFrameLevel() + 40)
        if picker.AnchorToFrame then picker:AnchorToFrame(f) end
    end
    picker.mode, picker.slot, picker.selectedPetID = nil, nil, nil
    if self.db then self.db.activeTargetSlot = nil end
    if f and f.loadoutCards then self:RefreshLoadoutCabin() end
    if self.RefreshHeaderHubIconStates then self:RefreshHeaderHubIconStates() end
end

function ns:OpenBackupPetPicker(anchor, callback)
    local f = self.MainFrame
    local picker = f and f.minimalPicker
    if not picker or not anchor or not callback then return false end
    if picker:IsShown() then self:CloseMinimalPicker() end
    picker:SetParent(UIParent)
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    local route = self.RoutingModal
    local routeLevel = route and route:IsVisible() and route:GetFrameLevel() or 0
    picker:SetFrameLevel(math.max(anchor:GetFrameLevel(), routeLevel, self._topModalLevel or 0) + 20)
    picker.backupCallback = callback
    picker.mode, picker.slot, picker.page, picker.selectedPetID = "ALL_PETS", nil, 0, nil
    picker.search:SetText("")
    picker.search:ClearFocus()
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 5, 0)
    picker:Show()
    picker:Raise()
    self:RefreshMinimalPicker()
    return true
end

function ns:CancelMinimalInteraction()
    local f = self.MainFrame
    if not f or f.mainUIStyle ~= "MINIMAL" then return false end
    if f.minimalPicker and f.minimalPicker:IsShown() then
        self:CloseMinimalPicker()
        return true
    end
    return false
end

function ns:OpenMinimalPicker(mode, slot)
    local f = self.MainFrame
    if not f or f.mainUIStyle ~= "MINIMAL" then return end
    if mode ~= "TEAMS" and mode ~= "QUEUE" and mode ~= "ALL_PETS" then
        mode = "PETS"
    end
    if mode == "PETS" and (not slot or slot < 1 or slot > 3) then
        mode = "ALL_PETS"
    end
    local picker = f.minimalPicker
    if not picker then return end
    if picker.backupCallback then self:CloseMinimalPicker() end
    if picker:IsShown() and picker.mode == mode and (mode ~= "PETS" or picker.slot == slot) then
        self:CloseMinimalPicker()
        return
    end
    if f.compactAbilityPopup then f.compactAbilityPopup:Hide() end
    f.compactSelectedPetID = nil
    picker.mode, picker.slot, picker.page = mode, slot, 0
    picker.selectedPetID = nil
    picker.search:SetText("")
    picker.search:ClearFocus()
    if self.db then self.db.activeTargetSlot = (mode == "PETS") and slot or nil end
    if picker.AnchorToFrame then picker:AnchorToFrame(f) end
    picker:Show()
    self:RefreshLoadoutCabin()
    self:RefreshMinimalPicker()
    if self.RefreshHeaderHubIconStates then self:RefreshHeaderHubIconStates() end
end

function ns:RefreshMinimalMode()
    local f = self.MainFrame
    if not f or not f.minimalView or not self.db then return end
    local team = self.db.teams and self.db.teams[self.db.selectedTeamIdx]
    if f.compactDraft then
        local name = strtrim(f.compactName:GetText() or "")
        f.minimalTeamLink.text:SetText(T("新建队伍") .. (name ~= "" and (" · " .. name) or ""))
    else
        f.minimalTeamLink.text:SetText(team and (team.name or T("未命名队伍"))
            or T("选择或新建队伍"))
    end
    f.minimalTargetLink.text:SetText(f.cabinTargetBtn.text:GetText())
    f.minimalStatus:SetText(f.cabinStatusBtn.text:GetText())
    local dirty = f.compactDraft or (self.staging and self.staging.isDirty)
    f.minimalSave:SetShown(dirty and true or false)
    f.minimalRevert:SetShown(dirty and true or false)
    f.minimalSave.text:SetText(T(f.compactDraft and "保存队伍" or "保存"))
    f.minimalRevert.text:SetText(T(f.compactDraft and "取消" or "撤销"))
    self:RefreshMinimalPicker()
end

-- Move and resize the EXISTING card children instead of building a second set.
-- Every point and size is restored on the way back to full mode.
local function LayoutLoadoutCard(card, slot, minimal, f)
    local parent = minimal and f.minimalView or f.homeView.cabin
    card:SetParent(parent)
    card:ClearAllPoints()
    card:SetSize(minimal and MINI_CARD_W or FULL_CARD_W,
        minimal and MINI_CARD_H or FULL_CARD_H)
    if minimal then
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -36 - (slot - 1) * MINI_CARD_STEP)
    else
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -78 - (slot - 1) * 142)
    end
    card.icon:ClearAllPoints()
    card.icon:SetSize(64, 64)
    card.icon:SetPoint("TOPLEFT", 14, -16)
    card.name:ClearAllPoints()
    card.name:SetPoint("TOPLEFT", 96, -20)
    card.name:SetPoint("RIGHT", -52, 0)
    card.breed:ClearAllPoints()
    card.breed:SetPoint("TOPRIGHT", -14, -21)
    if card.qualityLabel then card.qualityLabel:SetShown(false) end
    card.breed:SetShown(true)
    if card.typeBg then
        card.typeBg:SetSize(132, 132)
    end
    card.levelBadge:SetSize(24, 14)
    card.levelBadge:ClearAllPoints()
    card.levelBadge:SetPoint("TOPRIGHT", card.icon, "TOPRIGHT", -2, -2)
    card.healthBg:ClearAllPoints()
    card.syncBar:ClearAllPoints()
    card.healthBg:SetWidth(192)
    card.syncBar:SetWidth(192)
    card.healthBg:SetPoint("BOTTOMLEFT", 14, 18)
    card.syncBar:SetPoint("BOTTOMLEFT", 14, 18)
    for col, ability in ipairs(card.abBtns) do
        ability:SetSize(30, 30)
        ability:ClearAllPoints()
        ability:SetPoint("TOPLEFT", 96 + (col - 1) * 38, -48)
    end
    card.more:ClearAllPoints()
    card.more:SetPoint("TOPRIGHT", -7, -41)
    card:SetFrameLevel(parent:GetFrameLevel() + 3)
    card.levelBadge:SetFrameLevel(card:GetFrameLevel() + 8)
    card.dragOverlay:SetFrameLevel(card:GetFrameLevel() + 12)
end

local function LayoutHeader(f, minimal)
    if f.wordmark then
        f.wordmark:ClearAllPoints()
        f.wordmark:SetPoint("LEFT", minimal and 10 or 20, 0)
        f.wordmark:SetSize(minimal and 196 or 256, minimal and 34 or 44)
    end
    if f.closeBtn then
        f.closeBtn:ClearAllPoints()
        f.closeBtn:SetPoint("RIGHT", f.header, "RIGHT", minimal and -8 or -20, 0)
        f.closeBtn:SetSize(12, 12)
    end
    for _, name in ipairs({"petHubBtn", "teamHubBtn"}) do
        if f[name] then f[name]:Hide() end
    end
end

function ns:ApplyMainUIStyle()
    local f = self.MainFrame
    if not f or not f.minimalView or not f.homeView then return end
    local style = self.db and self.db.settings and self.db.settings.mainUIStyle == "MINIMAL" and "MINIMAL" or "FULL"
    local minimal = style == "MINIMAL"
    if f.versionText then f.versionText:SetShown(not minimal) end
    if f.mainUIStyle ~= style then
        if f.compactAbilityPopup then f.compactAbilityPopup:Hide() end
        if f.minimalPicker then f.minimalPicker:Hide() end
        if self.DisplaySettingsPanel then self.DisplaySettingsPanel:Hide() end
        if self.db then self.db.activeTargetSlot = nil end
        f.compactSelectedPetID = nil
        for slot, card in ipairs(f.loadoutCards or {}) do
            LayoutLoadoutCard(card, slot, minimal, f)
        end
        LayoutHeader(f, minimal)
        f.mainUIStyle = style
        f:SetSize(minimal and MINI_WIDTH or FULL_WIDTH,
            minimal and MINI_HEIGHT or FULL_HEIGHT)
    end
    -- SwitchMainViewMode always shows homeView first; enforce presentation
    -- even when reopening in the same mode (no card reparent needed).
    f.homeView:SetShown(not minimal)
    f.minimalView:SetShown(minimal)
    if f.collectionTabs then
        for _, tab in ipairs(f.collectionTabs) do tab:SetShown(not minimal) end
    end
    f.viewModeToggle._hubTitle = minimal and "完整界面" or "极简模式"
    Theme:ConfigureButtonIcon(f.viewModeToggle.icon, ACTION_TEX_ROOT .. (minimal and "expand.tga" or "collapse.tga"))
    f.minimalFullViewLink:SetShown(minimal)
    if self.RefreshModalBlocker then self:RefreshModalBlocker() end
    if self.UpdateHeaderToolButtons then self:UpdateHeaderToolButtons() end
    if self.RefreshActionSidebarLayout then self:RefreshActionSidebarLayout() end
end

function ns:SetMainUIStyle(style)
    if style ~= "FULL" and style ~= "MINIMAL" then return false end
    if InCombatLockdown() then
        self:PrintError(T("战斗中无法切换界面"))
        return false
    end
    if not self.db or not self.db.settings then return false end
    local f = self.MainFrame
    if style == "MINIMAL" and f and f.compactDraft
        and strtrim(f.compactName:GetText() or "") == "" then
        self:PrintError(T("请先输入队伍名称，再切换极简模式"))
        return false
    end
    if f and f.mainUIStyle ~= style then
        if self.loadoutSlotDrag and self.FinishLoadoutSlotDrag then
            self:FinishLoadoutSlotDrag()
        end
        if self.draggingPetID or self.draggingQueuePetID then
            if GetCursorInfo and GetCursorInfo() == "battlepet" then ClearCursor() end
            self.draggingPetID, self.draggingQueuePetID = nil, nil
        end
    end
    self.db.settings.mainUIStyle = style
    self:ApplyMainUIStyle()
    if self.RefreshHomeView then self:RefreshHomeView() end
    if self.RefreshMainUIScale then self:RefreshMainUIScale() end
    return true
end

function ns:ToggleMainUIStyle()
    local current = self.db and self.db.settings and self.db.settings.mainUIStyle
    return self:SetMainUIStyle(current == "MINIMAL" and "FULL" or "MINIMAL")
end

-- Store this preference in account-level SavedVariables and attach an override
-- on each character, since Blizzard's normal binding set can be character-specific.
local UI_STYLE_BINDING = "WISHPETTACTICS_TOGGLE_UI_STYLE"

function ns:GetUIStyleKeyText()
    local key = ns.db and ns.db.settings and ns.db.settings.uiStyleHotKey
    if key == nil then key = GetBindingKey and GetBindingKey(UI_STYLE_BINDING) end
    if key == "" then key = nil end
    return key and (self.FormatHotKeyDisplay and self:FormatHotKeyDisplay(key) or key)
        or self:T("未绑定")
end

function ns:ApplyUIStyleBinding()
    if InCombatLockdown() or not ns.db or not ns.db.settings then return false end
    local settings = ns.db.settings
    if settings.uiStyleHotKey == nil then
        local legacyKeys = { GetBindingKey(UI_STYLE_BINDING) }
        settings.uiStyleHotKey = legacyKeys[1] or ""
    end
    if not self.UIStyleBindingDriver then
        local driver = CreateFrame("Button", "WishPetTacticsUIStyleBindingDriver", UIParent)
        driver:SetSize(1, 1)
        driver:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)
        driver:SetFrameStrata("HIGH")
        driver:SetAlpha(0)
        driver:EnableMouse(false)
        driver:SetScript("OnClick", function()
            if WishPetTactics_ToggleUIStyle then WishPetTactics_ToggleUIStyle() end
        end)
        driver:Show()
        self.UIStyleBindingDriver = driver
    end
    local driver = self.UIStyleBindingDriver
    ClearOverrideBindings(driver)
    local key = settings.uiStyleHotKey
    if key ~= "" and SetOverrideBindingClick then
        SetOverrideBindingClick(driver, true, key, "WishPetTacticsUIStyleBindingDriver")
    end
    return true
end

local function SaveUIStyleBinding(key)
    if InCombatLockdown() then return false, T("战斗中无法设置切换快捷键") end
    local previousKeys = { GetBindingKey(UI_STYLE_BINDING) }
    if key then
        local assigned = GetBindingAction(key, true)
        if assigned and assigned ~= "" and assigned ~= UI_STYLE_BINDING then
            return false, T("该按键已被占用，请选择其他按键。")
        end
        if not SetBinding(key, UI_STYLE_BINDING) then
            return false, T("无法保存切换快捷键")
        end
    end
    for _, oldKey in ipairs(previousKeys) do
        if oldKey ~= key and not SetBinding(oldKey) then
            if key then SetBinding(key) end
            for _, restore in ipairs(previousKeys) do SetBinding(restore, UI_STYLE_BINDING) end
            return false, T("无法保存切换快捷键")
        end
    end
    if SaveBindings and GetCurrentBindingSet then
        pcall(SaveBindings, GetCurrentBindingSet())
    end
    ns.db.settings.uiStyleHotKey = key or ""
    if ns.ApplyUIStyleBinding then ns:ApplyUIStyleBinding() end
    if ns.ApplyBattleHotKeyBinding then ns:ApplyBattleHotKeyBinding() end
    return true
end

function ns:StartUIStyleKeybindCapture()
    if InCombatLockdown() then
        self:PrintError(T("战斗中无法设置切换快捷键"))
        return
    end
    if not self.UIStyleKeyCapture then
        local cap = CreateFrame("Button", "WishPetTacticsUIStyleKeyCapture", UIParent, "BackdropTemplate")
        cap:SetSize(356, 124)
        cap:SetPoint("CENTER")
        cap:SetFrameStrata("FULLSCREEN_DIALOG")
        cap:SetFrameLevel(200)
        cap:SetClampedToScreen(true)
        cap:EnableMouse(true)
        cap:EnableMouseWheel(true)
        cap:EnableKeyboard(true)
        cap:RegisterForClicks("AnyDown")
        Theme:ApplyBackdrop(cap, BG, BORDER, true)
        cap:Hide()
        local title = cap:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -17)
        title:SetText(T("设置界面切换快捷键"))
        Theme:HookLocalizedFontString(title)
        local hint = cap:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -13)
        hint:SetWidth(328)
        hint:SetJustifyH("CENTER")
        hint:SetText(T("按下按键或组合键 · Esc 取消 · Delete 清除"))
        Theme:HookLocalizedFontString(hint)
        cap.message = cap:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cap.message:SetPoint("BOTTOM", 0, 17)
        cap.message:SetWidth(332)
        cap.message:SetJustifyH("CENTER")
        Theme:HookLocalizedFontString(cap.message)

        local function ModifierPrefix()
            local prefix = ""
            if IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
            if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
            if IsAltKeyDown() then prefix = prefix .. "ALT-" end
            return prefix
        end
        local function Finish(key)
            local ok, message = SaveUIStyleBinding(key)
            if ok then
                cap:Hide()
                if ns.DisplaySettingsPanel and ns.DisplaySettingsPanel:IsShown() then
                    ns.DisplaySettingsPanel:Refresh()
                end
            else
                cap.message:SetText("|cffff6464" .. (message or T("无法保存切换快捷键")) .. "|r")
            end
        end
        cap:SetScript("OnKeyDown", function(self, key)
            self:SetPropagateKeyboardInput(false)
            if key == "ESCAPE" then self:Hide(); return end
            if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL"
                or key == "RCTRL" or key == "LALT" or key == "RALT"
                or key == "UNKNOWN" then return end
            if key == "DELETE" and ModifierPrefix() == "" then Finish(nil); return end
            Finish(ModifierPrefix() .. key)
        end)
        cap:SetScript("OnMouseWheel", function(_, delta)
            Finish(ModifierPrefix() .. (delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
        end)
        cap:SetScript("OnClick", function(self, button)
            if button == "RightButton" then self:Hide(); return end
            if button == "LeftButton" then return end
            Finish(ModifierPrefix() .. strupper(button))
        end)
        self.UIStyleKeyCapture = cap
    end
    local cap = self.UIStyleKeyCapture
    local activeParent = self.GetActiveUIParent and self:GetActiveUIParent() or UIParent
    if cap:GetParent() ~= activeParent then
        cap:SetParent(activeParent)
        cap:SetFrameStrata("FULLSCREEN_DIALOG")
        cap:SetFrameLevel(120)
    end
    if self.MatchMainUIScale then self:MatchMainUIScale(cap) end
    cap.message:SetText(T("当前快捷键") .. ": |cff10b981" .. self:GetUIStyleKeyText() .. "|r")
    cap:Show()
end

function ns:InitMinimalMode(f, header)
    local view = CreateFrame("Frame", nil, f)
    view:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    view:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    view:Hide()
    f.minimalView = view

    f.viewModeToggle = Theme:CreateHeaderHubIcon(f.actionSidebar, "display", "极简模式", nil,
        0.69, 0.83, 0.97, Theme.ActionSidebar.iconSize)
    f.viewModeToggle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.viewModeToggle:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns:StartUIStyleKeybindCapture()
        else
            ns:ToggleMainUIStyle()
        end
    end)
    f.viewModeToggle._hubTooltipAnchor = "ANCHOR_RIGHT"
    f.viewModeToggle._hubTooltip = function()
        return T(f.viewModeToggle._hubTitle) .. "\n"
            .. T("左键切换界面 · 右键设置快捷键") .. "\n"
            .. T("当前快捷键") .. ": " .. ns:GetUIStyleKeyText()
    end

    -- Always reachable in minimal mode, including while the sidebar is closed.
    f.minimalFullViewLink = Link(header, "完整界面", 82, function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns:StartUIStyleKeybindCapture()
        else
            ns:SetMainUIStyle("FULL")
        end
    end, "CENTER")
    f.minimalFullViewLink:SetPoint("RIGHT", f.actionSidebarToggle, "LEFT", -6, 0)
    f.minimalFullViewLink:Hide()
    Tip(f.minimalFullViewLink, function()
        return T("左键切换界面 · 右键设置快捷键") .. "\n"
            .. T("当前快捷键") .. ": " .. ns:GetUIStyleKeyText()
    end)

    -- 顶栏底边 (y = 0) 与 1号槽位框体顶边 (y = -36) 的正中间为 y = -18
    f.minimalTeamLink = Link(view, "选择队伍", 168, function(_, button)
        if f.compactDraft then
            ns:SetMainUIStyle("FULL")
            return
        end
        if button == "RightButton" then
            ns:ShowTeamContextMenu(f.minimalTeamLink, ns.db.selectedTeamIdx or 1)
        else
            ns:OpenMinimalPicker("TEAMS")
        end
    end, "LEFT", HEADER_TEX_ROOT .. "team.tga")
    f.minimalTeamLink:SetHeight(24)
    f.minimalTeamLink:SetPoint("LEFT", view, "TOPLEFT", 14, -18)
    Tip(f.minimalTeamLink, "点击切换队伍 · 右键管理 · 新建队伍请切回完整界面")
    f.minimalTargetLink = Link(view, "未绑定目标", 148, function()
        if f.compactDraft then return end
        ns:CloseMinimalPicker()
        if ns.ShowRoutingModal then ns:ShowRoutingModal(false, true) end
    end, "RIGHT", STATUS_TEX_ROOT .. "current-target.tga")
    f.minimalTargetLink:SetHeight(24)
    f.minimalTargetLink:SetPoint("RIGHT", view, "TOPRIGHT", -14, -18)
    Tip(f.minimalTargetLink, "点击打开目标窗口")

    f.minimalStatus = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.minimalStatus:SetPoint("BOTTOMLEFT", 14, 11)
    f.minimalStatus:SetWidth(158)
    f.minimalStatus:SetJustifyH("LEFT")
    Theme:HookLocalizedFontString(f.minimalStatus)
    f.minimalSave = Link(view, "保存", 92, function()
        local click = f.cabinSaveBtn:GetScript("OnClick")
        if click then click(f.cabinSaveBtn) end
        ns:RefreshHomeView()
    end, "RIGHT", ACTION_TEX_ROOT .. "save.tga")
    f.minimalSave:SetPoint("BOTTOMRIGHT", -118, 7)
    f.minimalRevert = Link(view, "撤销", 68, function()
        local click = f.cabinRevertBtn:GetScript("OnClick")
        if click then click(f.cabinRevertBtn) end
        ns:RefreshHomeView()
    end, "RIGHT", ACTION_TEX_ROOT .. "restore.tga")
    f.minimalRevert:SetPoint("BOTTOMRIGHT", -45, 7)
    f.minimalSave:Hide()
    f.minimalRevert:Hide()

    -- Detached, one-column picker: opens below the small roster and remains
    -- narrow enough to avoid covering a large part of the game viewport.
    local picker = CreateFrame("Frame", nil, f, "BackdropTemplate")
    picker:SetSize(MINI_CONTENT_WIDTH, 329)
    picker:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -5)
    picker:SetFrameStrata("DIALOG")
    picker:SetFrameLevel(f:GetFrameLevel() + 40)
    picker:SetClampedToScreen(true)
    picker:EnableMouse(true)
    picker:EnableMouseWheel(true)
    picker:SetScript("OnMouseWheel", function(self, delta)
        self.page = math.max(0, (self.page or 0) - delta)
        ns:RefreshMinimalPicker()
    end)
    Theme:ApplyBackdrop(picker, BG, BORDER, false)
    picker.AnchorToFrame = function(selfPicker, anchorTarget)
        selfPicker:ClearAllPoints()
        local target = anchorTarget or f
        local bottom = target:GetBottom() or 0
        local top = target:GetTop() or 0
        local screenH = GetScreenHeight() or 768
        local scale = target:GetEffectiveScale() or 1
        local scaledBottom = bottom * scale
        local needed = 340 * scale
        if scaledBottom < needed and ((screenH - (top * scale)) >= needed) then
            selfPicker:SetPoint("BOTTOMLEFT", target, "TOPLEFT", 0, 5)
        else
            selfPicker:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, -5)
        end
    end
    picker:AnchorToFrame(f)
    picker:Hide()
    f.minimalPicker = picker
    picker:HookScript("OnHide", function(selfPicker)
        if selfPicker.backupCallback then
            selfPicker.backupCallback = nil
            selfPicker:SetParent(f)
            selfPicker:SetFrameStrata("DIALOG")
            selfPicker:SetFrameLevel(f:GetFrameLevel() + 40)
            selfPicker:AnchorToFrame(f)
        end
    end)

    picker.title = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    picker.title:SetPoint("TOPLEFT", 10, -14)
    picker.title:SetWidth(96)
    picker.title:SetJustifyH("LEFT")
    Theme:HookLocalizedFontString(picker.title)
    picker.search = CreateFrame("EditBox", nil, picker, "BackdropTemplate")
    picker.search:SetSize(184, 23)
    picker.search:SetPoint("TOPLEFT", 110, -8)
    picker.search:SetFontObject(GameFontHighlightSmall)
    picker.search:SetAutoFocus(false)
    picker.search:SetTextInsets(3, 3, 0, 0)
    Theme:StyleSearchBox(picker.search)
    local minimalSearchTimer
    local function CancelMinimalSearch()
        if minimalSearchTimer then minimalSearchTimer:Cancel(); minimalSearchTimer = nil end
    end
    picker.search:SetScript("OnTextChanged", function(_, userInput)
        picker.page = 0
        CancelMinimalSearch()
        if not userInput then
            ns:RefreshMinimalPicker()
            return
        end
        minimalSearchTimer = C_Timer.NewTimer(0.15, function()
            minimalSearchTimer = nil
            if picker:IsShown() then ns:RefreshMinimalPicker() end
        end)
    end)
    picker:HookScript("OnHide", CancelMinimalSearch)
    picker.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    picker.search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        ns:CloseMinimalPicker()
    end)
    local searchHint = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", picker.search, "LEFT", 4, 0)
    searchHint:SetText(T("搜索宠名 / 技能 / 拼音 / 备注..."))
    picker.searchHint = searchHint
    Theme:HookLocalizedFontString(searchHint)
    picker.search:HookScript("OnTextChanged", function(self)
        searchHint:SetShown(self:GetText() == "" and not self:HasFocus())
    end)
    picker.search:HookScript("OnEditFocusGained", function() searchHint:Hide() end)
    picker.search:HookScript("OnEditFocusLost", function(self)
        searchHint:SetShown(self:GetText() == "")
    end)
    picker.manage = Link(picker, "队伍管理 / 新建", 146, function()
        ns:CloseMinimalPicker()
        if ns:SetMainUIStyle("FULL") and ns.SetCompactLeftMode then
            ns:SetCompactLeftMode("TEAMS")
        end
    end, "LEFT")
    picker.manage:SetPoint("BOTTOMLEFT", 10, 5)
    picker.close = Theme:CreateCloseIconButton(picker, function() ns:CloseMinimalPicker() end)
    picker.close:SetPoint("TOPRIGHT", -12, -14)
    picker.rows = {}
    for i = 1, PICKER_ROWS do picker.rows[i] = MakePickerRow(picker, i) end
    picker.empty = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    picker.empty:SetPoint("CENTER", 0, -22)
    picker.empty:SetWidth(300)
    picker.empty:SetJustifyH("CENTER")
    Theme:HookLocalizedFontString(picker.empty)
    picker.footer = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    picker.footer:SetPoint("BOTTOMLEFT", 10, 12)
    picker.footer:SetWidth(154)
    picker.footer:SetText(T("左键选择 · 按住 Shift 详情"))
    Theme:HookLocalizedFontString(picker.footer)
    picker.next = Link(picker, "›", 25, function()
        picker.page = (picker.page or 0) + 1
        ns:RefreshMinimalPicker()
    end, "RIGHT")
    picker.next:SetPoint("BOTTOMRIGHT", -9, 5)
    picker.pageInfo = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    picker.pageInfo:SetPoint("RIGHT", picker.next, "LEFT", -3, 0)
    picker.pageInfo:SetWidth(55)
    picker.pageInfo:SetJustifyH("CENTER")
    picker.prev = Link(picker, "‹", 25, function()
        picker.page = math.max(0, (picker.page or 0) - 1)
        ns:RefreshMinimalPicker()
    end, "RIGHT")
    picker.prev:SetPoint("RIGHT", picker.pageInfo, "LEFT", -3, 0)
end
