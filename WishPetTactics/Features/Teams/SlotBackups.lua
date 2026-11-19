local _, ns = ...
local Theme = ns.Theme

local function L(cn, tw, en)
    if ns.locale == "zhCN" then return cn end
    if ns.locale == "zhTW" then return tw end
    return en
end

local panel
local function BuildPanel()
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(490, 275)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Theme:ApplyBackdrop(f, Theme.Colors.bgPopup, Theme.Colors.border, true)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 14, -13)
    local close = Theme:CreateFlatButton(f, 26, 22, "×")
    close:SetPoint("TOPRIGHT", -8, -7)
    close:SetScript("OnClick", function() f:Hide() end)
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 14, -38)
    hint:SetText(L("按顺序使用备用宠物；点击技能图标选择技能", "按順序使用備用寵物；點擊技能圖示選擇技能", "Backups are used in order; click an ability to choose it"))
    local abilityPopup = CreateFrame("Frame", nil, f, "BackdropTemplate")
    abilityPopup:SetSize(96, 49)
    abilityPopup:SetFrameStrata("FULLSCREEN_DIALOG")
    abilityPopup:SetClampedToScreen(true)
    abilityPopup:EnableMouse(true)
    Theme:ApplyBackdrop(abilityPopup, Theme.Colors.bgPopup, Theme.Colors.border, false)
    abilityPopup.buttons = {}
    for i = 1, 2 do
        local button = CreateFrame("Button", nil, abilityPopup, "BackdropTemplate")
        button:SetSize(34, 34)
        button:SetPoint("LEFT", 8 + (i - 1) * 41, 0)
        Theme:ApplyBackdrop(button, Theme.Colors.bgMain, Theme.Colors.border, false)
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("TOPLEFT", 2, -2)
        button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        button.marker = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.marker:SetPoint("BOTTOMRIGHT", -2, 2)
        button:SetScript("OnEnter", function(self)
            if self.locked then
                ns:ShowCustomTooltip(self, "ANCHOR_TOP", ns:TF("%d 级解锁", self.requiredLevel))
            elseif self.abilityID and ns.ShowAbilityTooltip then
                ns:ShowAbilityTooltip(self, self.abilityID, 1400, 280, 280)
            end
        end)
        button:SetScript("OnLeave", function(self)
            if ns.HideCustomTooltip then ns:HideCustomTooltip(self) end
            if ns.HideAbilityTooltip then ns:HideAbilityTooltip() end
        end)
        button:SetScript("OnClick", function(self)
            local entry = abilityPopup.entry
            if entry and f.list[abilityPopup.index] == entry and self.abilityID and not self.locked then
                entry.abilities[abilityPopup.col] = self.abilityID
                abilityPopup:Hide()
                f:Refresh()
            end
        end)
        abilityPopup.buttons[i] = button
    end
    abilityPopup:Hide()
    function f:OpenAbilityPicker(anchor, index, col)
        local entry = self.list[index]
        if not entry then return end
        if abilityPopup:IsShown() and abilityPopup.anchor == anchor then abilityPopup:Hide(); return end
        local ids, levels = ns:GetSortedPetAbilities(entry.speciesID)
        local _, _, level = C_PetJournal.GetPetInfoByPetID(entry.petID)
        abilityPopup.anchor, abilityPopup.entry, abilityPopup.index, abilityPopup.col = anchor, entry, index, col
        abilityPopup:SetFrameLevel(self:GetFrameLevel() + 30)
        for i, button in ipairs(abilityPopup.buttons) do
            local position = col + (i - 1) * 3
            local id = ids and ids[position]
            button.abilityID = id
            button:SetShown(id and id > 0)
            if id and id > 0 then
                local _, icon = C_PetJournal.GetPetAbilityInfo(id)
                button.icon:SetTexture(icon)
                button.requiredLevel = (levels and levels[position]) or 1
                button.locked = (level or 0) < button.requiredLevel
                button.icon:SetDesaturated(button.locked)
                button.marker:SetText(button.locked and "|TInterface\\Buttons\\LockButton-Locked-Up:13|t" or entry.abilities[col] == id and "✓" or "")
                button:SetBackdropBorderColor(unpack(entry.abilities[col] == id and Theme.Colors.borderBlue or Theme.Colors.border))
            end
        end
        abilityPopup:ClearAllPoints()
        abilityPopup:SetPoint("TOP", anchor, "BOTTOM", 0, -5)
        abilityPopup:Show()
    end
    f.rows = {}
    for i = 1, 4 do
        local row = CreateFrame("Frame", nil, f, "BackdropTemplate")
        row:SetSize(462, 43)
        row:SetPoint("TOPLEFT", 14, -55 - (i - 1) * 47)
        Theme:ApplyBackdrop(row, Theme.Colors.bgMain, Theme.Colors.border, false)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 8, 0)
        row.name:SetWidth(195)
        row.name:SetJustifyH("LEFT")
        row.skills = {}
        for col = 1, 3 do
            local col = col
            local b = CreateFrame("Button", nil, row, "BackdropTemplate")
            b:SetSize(31, 31)
            b:SetPoint("LEFT", 207 + (col - 1) * 35, 0)
            Theme:ApplyBackdrop(b, Theme.Colors.bgMain, Theme.Colors.border, false)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetPoint("TOPLEFT", 2, -2)
            b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
            b:SetScript("OnClick", function(self) f:OpenAbilityPicker(self, row.index, col) end)
            b:SetScript("OnEnter", function(self)
                local e = f.list[row.index]
                if e and ns.ShowAbilityTooltip then ns:ShowAbilityTooltip(self, e.abilities[col], 1400, 280, 280) end
            end)
            b:SetScript("OnLeave", function() if ns.HideAbilityTooltip then ns:HideAbilityTooltip() end end)
            row.skills[col] = b
        end
        row.remove = Theme:CreateFlatButton(row, 25, 25, "×")
        row.remove:SetPoint("RIGHT", -5, 0)
        row.remove:SetScript("OnClick", function() table.remove(f.list, row.index); f:Refresh() end)
        row.up = Theme:CreateFlatButton(row, 25, 25, "")
        row.up:SetPoint("RIGHT", row.remove, "LEFT", -3, 0)
        row.up.arrow = Theme:CreateArrowTexture(row.up, 12, "UP")
        row.up.arrow:SetPoint("CENTER")
        row.up:SetScript("OnClick", function()
            local n = row.index
            if n > 1 then f.list[n], f.list[n - 1] = f.list[n - 1], f.list[n]; f:Refresh() end
        end)
        row.down = Theme:CreateFlatButton(row, 25, 25, "")
        row.down:SetPoint("RIGHT", row.up, "LEFT", -3, 0)
        row.down.arrow = Theme:CreateArrowTexture(row.down, 12, "DOWN")
        row.down.arrow:SetPoint("CENTER")
        row.down:SetScript("OnClick", function()
            local n = row.index
            if n < #f.list then f.list[n], f.list[n + 1] = f.list[n + 1], f.list[n]; f:Refresh() end
        end)
        row.add = Theme:CreateFlatButton(row, 32, 31, "+")
        row.add:SetPoint("LEFT", 8, 0)
        row.add:SetScript("OnClick", function()
            ns:OpenBackupPetPicker(f, function(petID)
                if not f:IsShown() then return end
                local species = C_PetJournal.GetPetInfoByPetID(petID)
                local ids = species and ns:GetSortedPetAbilities(species)
                if ids then
                    f.list[#f.list + 1] = { petID = petID, speciesID = species, abilities = { ids[1] or 0, ids[2] or 0, ids[3] or 0 } }
                    f.offset = math.max(0, #f.list - 3)
                    f:Refresh()
                end
            end)
        end)
        f.rows[i] = row
    end
    f.prev = Theme:CreateFlatButton(f, 30, 22, "")
    f.prev.arrow = Theme:CreateArrowTexture(f.prev, 12, "UP")
    f.prev.arrow:SetPoint("CENTER")
    f.prev:SetPoint("TOPLEFT", 14, -245)
    f.prev:SetScript("OnClick", function() f.offset = math.max(0, f.offset - 1); f:Refresh() end)
    f.next = Theme:CreateFlatButton(f, 30, 22, "")
    f.next.arrow = Theme:CreateArrowTexture(f.next, 12, "DOWN")
    f.next.arrow:SetPoint("CENTER")
    f.next:SetPoint("LEFT", f.prev, "RIGHT", 4, 0)
    f.next:SetScript("OnClick", function() f.offset = math.min(#f.list, f.offset + 1); f:Refresh() end)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        f.offset = math.max(0, math.min(#f.list, f.offset - delta)); f:Refresh()
    end)
    f:HookScript("OnHide", function()
        local picker = ns.MainFrame and ns.MainFrame.minimalPicker
        if picker and picker.backupCallback then ns:CloseMinimalPicker() end
    end)
    function f:Refresh()
        abilityPopup:Hide()
        for i, row in ipairs(self.rows) do
            row.index = self.offset + i
            local e = self.list[row.index]
            local isAdd = row.index == #self.list + 1
            if e or isAdd then row:Show() else row:Hide() end
            row.name:SetShown(e ~= nil)
            row.remove:SetShown(e ~= nil)
            row.up:SetShown(e ~= nil)
            row.down:SetShown(e ~= nil)
            row.add:SetShown(isAdd)
            for col, b in ipairs(row.skills) do
                b:SetShown(e ~= nil)
                if e then local _, icon = C_PetJournal.GetPetAbilityInfo(e.abilities[col]); b.icon:SetTexture(icon) end
            end
            if e then
                local _, custom, _, _, _, _, _, name = C_PetJournal.GetPetInfoByPetID(e.petID)
                row.name:SetText(row.index .. ". " .. (custom or name or L("宠物不可用", "寵物不可用", "Unavailable pet")))
            end
        end
    end
    return f
end

function ns:ShowSlotBackups(team, slot)
    if not team or not slot then return end
    if team.hasLevelingSlot and (team.levelingSlot or 2) == slot or team.randomSlots and team.randomSlots[slot] ~= nil then
        self:ShowUIFeedback(L("经验槽和随机槽不能设置备用宠物", "經驗槽和隨機槽不能設定備用寵物", "Backups are unavailable for leveling or random slots"))
        return
    end
    panel = panel or BuildPanel()
    local picker = self.MainFrame and self.MainFrame.minimalPicker
    if picker and picker.backupCallback then self:CloseMinimalPicker() end
    team.slotBackups = team.slotBackups or {}
    team.slotBackups[slot] = team.slotBackups[slot] or {}
    panel.list = team.slotBackups[slot]
    panel.offset = 0
    panel.title:SetText((team.name or "") .. " · " .. L("槽位备用宠物", "欄位備用寵物", "Slot backups") .. " " .. slot)
    panel:Refresh()
    panel:Show()
    if self.BringModalToFront then self:BringModalToFront(panel) end
end
