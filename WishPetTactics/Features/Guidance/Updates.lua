local ADDON_NAME, ns = ...
local Theme = ns.Theme

-- Update this version and the localized entries whenever an addon version is released.
local UPDATE_VERSION = "6.1.94"
local entries = {
    {
        title = {"批量加入练级队列", "批次加入練級佇列", "Batch leveling queue"},
        detail = {"分组、目标和队伍右键均可加入未满级宠物，自动去重。", "分組、目標與隊伍右鍵皆可加入未滿級寵物，自動去重。", "Right-click a group, target or team to queue its under-level pets without duplicates."},
        action = "targets",
    },
}
local history = {
    {
        title = {"新建队伍的经验槽", "新建隊伍的經驗欄位", "Leveling slots in new teams"},
        detail = {"放入未满级宠物保持普通槽位；右键手动设为经验槽。", "放入未滿級寵物維持普通欄位；右鍵手動設為經驗欄位。", "Under-level pets remain in ordinary slots. Use the slot's right-click action to enable leveling."},
        action = "slot",
    },

    {
        title = {"队伍宠物与练级", "隊伍寵物與練級", "Team pets and leveling"},
        detail = {"右键槽位搜索同名宠物；分组可批量加入练级队列；替换宠物继承槽位技能。", "右鍵欄位搜尋同名寵物；分組可批次加入練級佇列；替換寵物繼承欄位技能。", "Find same-species pets, queue a group's under-level pets, and retain slot abilities when replacing pets."},
        action = "slot",
    },
    {
        title = {"队伍查找与战术备注", "隊伍尋找與戰術備註", "Team search and strategy notes"},
        detail = {"相关队伍按宠物物种查找；队伍右键可查看导入备注；悬停查看未就绪原因。", "相關隊伍依寵物物種尋找；隊伍右鍵可查看匯入備註；懸停查看未就緒原因。", "Find teams by species, view imported notes, and hover a target team to see why it is not ready."},
        action = "targets",
    },
    {
        title = {"提示设置", "提示設定", "Notice settings"},
        detail = {"复活和换队提示移至上方，可在显示设置关闭；修正假死等状态引起的重复提示。", "復活與換隊提示移至上方，可在顯示設定關閉；修正假死等狀態引起的重複提示。", "Notices are higher on screen and can be disabled in display settings; usability changes no longer trigger revive alerts."},
        action = "display",
    },
    {
        title = {"极简模式筛选", "極簡模式篩選", "Minimal-mode filters"},
        detail = {"宠物列表与练级队列新增筛选按钮；装笼选项移到召唤下方。", "寵物列表與練級佇列新增篩選按鈕；裝籠選項移到召喚下方。", "Filter pets and leveling queues in minimal mode; the cage option is below Summon."},
        action = "pets",
    },
    {
        title = {"新宠物与更新引导", "新寵物與更新導覽", "New pet alerts and update guide"},
        detail = {"点击收集提示查看宠物；自动引导仅显示本次更新，历史内容可在更新日志中查看。", "點擊收集提示查看寵物；自動導覽僅顯示本次更新，歷史內容可在更新日誌中查看。", "Click a new-pet alert to find it; the automatic guide now shows current changes only."},
    },
    {
        title = {"宠物装笼与收藏数量", "寵物裝籠與收藏數量", "Pet cages and collection counts"},
        detail = {"右键可交易宠物可装入笼中；悬浮详情显示已收集数量和上限。", "右鍵可交易寵物可裝入籠中；懸浮詳情顯示已收集數量和上限。", "Right-click a tradable pet to cage it; details show collected count and limit."},
    },
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
    if action == "display" then
        if not ns.DisplaySettingsPanel or not ns.DisplaySettingsPanel:IsShown() then ns:ToggleDisplaySettings() end
    elseif action == "targets" then
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

function ns:ShowUpdateGuide(showHistory)
    if showHistory == nil then showHistory = true end
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
        panel.historyScroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        panel.historyScroll:SetPoint("TOPLEFT", 28, -68 - #entries * 73 - 8)
        panel.historyScroll:SetPoint("BOTTOMRIGHT", -35, 16)
        panel.historyChild = CreateFrame("Frame", nil, panel.historyScroll)
        panel.historyChild:SetSize(432, 1)
        panel.historyScroll:SetScrollChild(panel.historyChild)
        panel.history = panel.historyChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        panel.history:SetPoint("TOPLEFT")
        panel.history:SetWidth(432)
        panel.history:SetJustifyH("LEFT")
        panel.history:SetJustifyV("TOP")
        panel.history:SetWordWrap(true)
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
    local historicalLines = {}
    if showHistory then
        historicalLines[1] = Localized({"|cffffd100历史更新|r", "|cffffd100歷史更新|r", "|cffffd100Previous updates|r"})
        for _, item in ipairs(history) do
            historicalLines[#historicalLines + 1] = "\n|cff38bdf8" .. Localized(item.title) .. "|r\n" .. Localized(item.detail)
        end
    end
    self.UpdateGuide.history:SetText(table.concat(historicalLines, "\n"))
    self.UpdateGuide.historyChild:SetHeight(math.max(1, self.UpdateGuide.history:GetStringHeight() + 8))
    self.UpdateGuide.historyScroll:SetShown(showHistory)
    self.UpdateGuide.historyScroll:SetVerticalScroll(0)
    self.UpdateGuide:SetHeight(showHistory and 540 or (68 + #entries * 73 + 20))
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
    self:ShowUpdateGuide(false)
end
