local ADDON_NAME, ns = ...
local Theme = ns.Theme

-- Update this version and the localized entries whenever an addon version is released.
local UPDATE_VERSION = "6.1.87"
local entries = {
    {
        title = {"槽位备用宠物", "欄位備用寵物", "Backup pets per slot"},
        detail = {"右键宠物槽位，开启血量换宠后配置备用宠物和技能。", "右鍵寵物欄位，開啟血量換寵後設定備用寵物與技能。", "Right-click a slot and enable health-based swapping to configure backups."},
        action = "slot",
    },
    {
        title = {"组合搜索", "組合搜尋", "Combined search"},
        detail = {"用逗号分隔条件，例如：增压，召唤闪电。", "用逗號分隔條件，例如：增壓，召喚閃電。", "Separate search terms with commas to match them together."},
        action = "pets",
    },
    {
        title = {"备用宠物与复活", "備用寵物與復活", "Backups and revive cooldown"},
        detail = {"备用宠物按顺序上场；复活 CD 就绪后切回 1 队原始宠物。", "備用寵物按順序上場；復活冷卻就緒後切回 1 隊原始寵物。", "Backups are used in order; when revive is ready, restore team 1's original pets."},
        action = "targets",
    },
    {
        title = {"更新引导", "更新導覽", "Update guide"},
        detail = {"点击条目查看功能，引导保持打开；侧边栏图标可重新打开。", "點擊項目查看功能，導覽保持開啟；側邊欄圖示可重新開啟。", "Explore an item without closing this guide; reopen it from the sidebar."},
        action = "guide",
    },
}

local function Localized(values)
    return values[ns.locale == "zhCN" and 1 or ns.locale == "zhTW" and 2 or 3]
end

local function OpenUpdateAction(action)
    if action == "guide" then return end
    local main = ns:CreateMainFrame()
    ns:ShowMainFrame("HOME")
    if action == "targets" then
        ns:ShowRoutingModal(false, true)
    elseif action == "pets" then
        if main.mainUIStyle == "MINIMAL" then
            ns:OpenMinimalPicker("ALL_PETS")
        elseif ns.SetCompactLeftMode then
            ns:SetCompactLeftMode("PETS")
        else
            ns:TogglePetPickerDrawer(nil, "PETS", true)
        end
    elseif action == "slot" then
        local card = main.loadoutCards and main.loadoutCards[1]
        if card and card:IsVisible() then
            ns:ShowSlotThresholdMenu(card, 1)
        else
            ns:ShowRoutingModal(false, true)
        end
    end
end

function ns:ShowUpdateGuide()
    if not self.db or InCombatLockdown() or (C_PetBattles and C_PetBattles.IsInBattle()) then return false end
    local main = self:CreateMainFrame()
    if not main:IsShown() then self:ShowMainFrame("HOME") end
    if not self.UpdateGuide then
        local panel = CreateFrame("Frame", "WishPetTacticsUpdateGuide", UIParent, "BackdropTemplate")
        panel:Hide()
        panel:SetSize(500, 68 + #entries * 73 + 20)
        panel:SetPoint("CENTER")
        panel:SetClampedToScreen(true)
        panel:EnableMouse(true)
        panel:SetMovable(true)
        panel:RegisterForDrag("LeftButton")
        panel:SetScript("OnDragStart", panel.StartMoving)
        panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
        Theme:ApplyBackdrop(panel, Theme.Colors.bgPopup, Theme.Colors.border, false)
        if ns.MakeModal then ns:MakeModal(panel) end
        if UISpecialFrames then tinsert(UISpecialFrames, panel:GetName()) end
        panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        panel.title:SetPoint("TOPLEFT", 18, -16)
        local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subtitle:SetPoint("TOPLEFT", 18, -43)
        subtitle:SetText(Localized({"引导可持续查看，侧边栏可再次打开；点击条目体验", "導覽可持續查看，側邊欄可再次開啟；點擊項目體驗", "Guide stays open; reopen it from the sidebar. Select an item to explore."}))
        local close = Theme:CreateCloseIconButton(panel, function() panel:Hide() end)
        close:SetPoint("TOPRIGHT", -14, -14)
        panel.rows = {}
        for index, entry in ipairs(entries) do
            local entry = entry
            local row = CreateFrame("Button", nil, panel, "BackdropTemplate")
            row:SetSize(464, 68)
            row:SetPoint("TOPLEFT", 18, -68 - (index - 1) * 73)
            Theme:ApplyBackdrop(row, Theme.Colors.bgCard, Theme.Colors.border, false)
            row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.title:SetPoint("TOPLEFT", 10, -9)
            row.title:SetText(Localized(entry.title))
            row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.detail:SetPoint("TOPLEFT", 10, -29)
            row.detail:SetPoint("RIGHT", -28, 0)
            row.detail:SetJustifyH("LEFT")
            row.detail:SetWordWrap(true)
            row.detail:SetText(Localized(entry.detail))
            local arrow = Theme:CreateArrowTexture(row, 12, "RIGHT")
            arrow:SetPoint("RIGHT", -10, 0)
            row:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(Theme.Colors.borderBlue)) end)
            row:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(Theme.Colors.border)) end)
            row:SetScript("OnClick", function(self)
                self.title:SetText("|cff10b981✓|r " .. Localized(entry.title))
                panel:ClearAllPoints()
                panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -80)
                OpenUpdateAction(entry.action)
            end)
            panel.rows[index] = row
        end
        panel:HookScript("OnHide", function() if ns.db then ns.db.lastSeenUpdateVersion = UPDATE_VERSION end end)
        self.UpdateGuide = panel
    end
    self.UpdateGuide.title:SetText(Localized({"本次更新", "本次更新", "What's new"}) .. " · " .. UPDATE_VERSION)
    if self.UpdateGuide:IsShown() then
        if self.BringModalToFront then self:BringModalToFront(self.UpdateGuide) end
        return true
    end
    self.UpdateGuide:Show()
    if self.BringModalToFront then self:BringModalToFront(self.UpdateGuide) end
    return true
end

function ns:MaybeShowUpdateGuide()
    if not self.db or self.db.lastSeenUpdateVersion == UPDATE_VERSION then return end
    if InCombatLockdown() or (C_PetBattles and C_PetBattles.IsInBattle()) then return end
    if not self.MainFrame or not self.MainFrame:IsVisible() then return end
    for _, modal in ipairs(self.modalFrames or {}) do
        if modal ~= self.UpdateGuide and modal:IsVisible() then return end
    end
    self:ShowUpdateGuide()
end
