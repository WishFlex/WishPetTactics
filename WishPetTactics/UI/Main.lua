local ADDON_NAME, ns = ...
local Theme = ns.Theme

local MAIN_WIDTH, MAIN_HEIGHT = 1120, 620
local DEFAULT_OPACITY = 0.78

local REVIVE_SPELL_ID = 125439
local BANDAGE_ITEM_ID = 86143
local SAFARI_HAT_ID   = 92738
local SAFARI_BUFF_ID  = 158486

local HEADER_TEX_ROOT = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Header\\"
local PET_EXP_FOOD_ITEMS = {
    { itemID = 98114,  buffID = 142235, defaultIcon = HEADER_TEX_ROOT .. "treat.tga" },
    { itemID = 98112,  buffID = 142234, defaultIcon = HEADER_TEX_ROOT .. "treat-lesser.tga" },
    { itemID = 211457, buffID = 142235, defaultIcon = HEADER_TEX_ROOT .. "treat.tga" },
}

local cachedItemIcons = {}
local function GetCachedItemIcon(itemID, fallbackIcon)
    local tex = cachedItemIcons[itemID]
    if tex then return tex end
    if C_Item and C_Item.GetItemIconByID then
        tex = C_Item.GetItemIconByID(itemID)
    end
    if tex then
        cachedItemIcons[itemID] = tex
        return tex
    end
    return fallbackIcon
end

local function IsSecret(val)
    if val == nil then return false end
    if ns.IsSecretValue then return ns:IsSecretValue(val) end
    if issecretvalue and issecretvalue(val) then return true end
    if canaccessvalue and not canaccessvalue(val) then return true end
    return false
end

local function SafeHasPlayerAuraBySpellID(spellID)
    if not spellID or not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then
        return false
    end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if not ok or IsSecret(aura) then
        return false
    end
    return aura ~= nil
end

local function FormatCooldownTime(sec)
    if not sec or sec <= 0 then return "" end
    sec = math.ceil(sec)
    if sec >= 60 then
        return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
    else
        return string.format("%ds", sec)
    end
end

local function GetToolItemCooldown(itemID, available)
    if not available then return 0, 0 end
    local getCooldown = C_Container and C_Container.GetItemCooldown or GetItemCooldown
    if getCooldown then
        local ok, start, duration = pcall(getCooldown, itemID)
        if ok and not IsSecret(start) and not IsSecret(duration) then
            return start or 0, duration or 0
        end
    end
    return 0, 0
end

local function UpdateToolCooldown(button, start, duration)
    local remaining = start > 0 and duration > 1.5 and math.max(0, start + duration - GetTime()) or 0
    button._cooldownRemaining = remaining
    if remaining > 0 then
        if button._lastCdStart ~= start or button._lastCdDur ~= duration then
            button._lastCdStart, button._lastCdDur = start, duration
            button.cooldown:SetCooldown(start, duration)
        end
    elseif button._lastCdStart ~= 0 then
        button._lastCdStart, button._lastCdDur = 0, 0
        button.cooldown:Clear()
    end
    button.cdTxt:SetText(FormatCooldownTime(remaining))
    button.cdTxt:SetShown(remaining > 0)
    if remaining > 0 then ns.MainFrame._hasActiveCooldown = true end
    return remaining
end

local function GetBagItemCount(itemID)
    if C_Item and C_Item.GetItemCount then
        local ok, cnt = pcall(C_Item.GetItemCount, itemID)
        if ok and not IsSecret(cnt) then
            return tonumber(cnt) or 0
        end
        return 0
    elseif GetItemCount then
        local ok, cnt = pcall(GetItemCount, itemID)
        if ok and not IsSecret(cnt) then
            return tonumber(cnt) or 0
        end
        return 0
    end
    return 0
end

-- 背包道具数量缓存（仅在打开主界面与 BAG_UPDATE_DELAYED 时重扫背包，避免 GCD/光环事件高频扫包）
local bagCache = {
    dirty   = true,
    hasHat  = false,
    bandage = 0,
    foods   = { 0, 0, 0 },
}

local function EnsureBagCountsCached()
    if not bagCache.dirty then return end
    bagCache.dirty = false
    bagCache.hasHat = ((PlayerHasToy and PlayerHasToy(SAFARI_HAT_ID)) or (GetBagItemCount(SAFARI_HAT_ID) > 0)) and true or false
    bagCache.bandage = GetBagItemCount(BANDAGE_ITEM_ID)
    for idx = 1, #PET_EXP_FOOD_ITEMS do
        bagCache.foods[idx] = GetBagItemCount(PET_EXP_FOOD_ITEMS[idx].itemID)
    end
end

-- Only attach a per-frame handler while a drag or cooldown needs it.
local function MainFrameOnUpdate(self, elapsed)
    if ns.loadoutSlotDrag then
        local cursorType, cursorPetID = GetCursorInfo()
        if cursorType ~= "battlepet" or cursorPetID ~= ns.loadoutSlotDrag.petID then
            ns:FinishLoadoutSlotDrag()
        else
            ns:UpdateLoadoutSlotDragVisuals()
        end
    elseif ns.draggingQueuePetID then
        local cursorType = GetCursorInfo()
        if cursorType ~= "battlepet" and not IsMouseButtonDown("LeftButton") then
            ns.draggingQueuePetID, ns.draggingPetID = nil, nil
            ns.isReorderingQueueList = false
        end
        ns:UpdateLoadoutSlotDragVisuals()
        if ns.UpdateCompactQueueDragVisuals then
            ns:UpdateCompactQueueDragVisuals()
        end
    end
    if not self._hasActiveCooldown then return end
    self._cooldownElapsed = (self._cooldownElapsed or 0) + elapsed
    if self._cooldownElapsed >= 1.0 then
        self._cooldownElapsed = 0
        ns:UpdateHeaderToolButtons()
    end
end

function ns:UpdateMainFrameTicker()
    local f = self.MainFrame
    if not f then return end
    local active = f:IsShown() and (self.loadoutSlotDrag or self.draggingQueuePetID or f._hasActiveCooldown)
    local handler = active and MainFrameOnUpdate or nil
    if f:GetScript("OnUpdate") ~= handler then
        f:SetScript("OnUpdate", handler)
    end
    if not active then f._cooldownElapsed = 0 end
end

-- ==================== 0. 拖放宠物或练级队列项至槽位 ====================
function ns:UpdateLoadoutSlotDragVisuals()
    self:UpdateMainFrameTicker()
    local cards = self.MainFrame and self.MainFrame.loadoutCards
    if not cards then return end
    local drag = self.loadoutSlotDrag
    local queueDrag = not drag and self.draggingQueuePetID
    local target
    if drag or queueDrag then
        for index, card in ipairs(cards) do
            if card:IsVisible() and card:IsMouseOver() then target = index; break end
        end
    end
    for index, card in ipairs(cards) do
        local overlay = card.dragOverlay
        if overlay then
            local state = drag and ((index == drag.slot and "SOURCE") or (index == target and "TARGET") or "READY")
                or queueDrag and index == target and "QUEUE" or nil
            if overlay.dragState ~= state or overlay.targetSlot ~= target then
                overlay.dragState, overlay.targetSlot = state, target
                if state then
                    if state == "SOURCE" then
                        overlay:SetBackdropColor(1, 0.65, 0.1, 0.12)
                        overlay:SetBackdropBorderColor(1, 0.65, 0.1, 1)
                        overlay.text:SetText(self:TF("正在拖动 %d 号槽 · 拖到其他槽位换位", drag.slot))
                    elseif state == "QUEUE" then
                        overlay:SetBackdropColor(1, 0.65, 0.1, 0.15)
                        overlay:SetBackdropBorderColor(1, 0.65, 0.1, 1)
                        overlay.text:SetText(self:T("松开设为经验槽"))
                    elseif state == "TARGET" then
                        overlay:SetBackdropColor(0.1, 1, 0.6, 0.22)
                        overlay:SetBackdropBorderColor(0.1, 1, 0.6, 1)
                        overlay.text:SetText(self:TF("松开鼠标：%d 号槽与 %d 号槽换位", drag.slot, index))
                    else
                        overlay:SetBackdropColor(0.2, 0.6, 1, 0.06)
                        overlay:SetBackdropBorderColor(0.2, 0.6, 1, 0.65)
                        overlay.text:SetText(self:TF("拖到此处：与 %d 号槽换位", index))
                    end
                    overlay:Show()
                else
                    overlay:Hide()
                end
            end
        end
    end
end

local function ShowLoadoutPetChanged(slotIndex)
    if ns.ShowUIFeedback then
        ns:ShowUIFeedback(ns:TF("队伍宠物已更新：第 %d 位", slotIndex))
    end
end

function ns:FinishLoadoutSlotDrag(slot)
    local drag = self.loadoutSlotDrag
    if not drag then return false end
    self.loadoutSlotDrag = nil
    self:UpdateLoadoutSlotDragVisuals()
    local cursorType, cursorPetID = GetCursorInfo()
    if cursorType ~= "battlepet" or cursorPetID ~= drag.petID then return true end
    ClearCursor()
    if slot and slot ~= drag.slot then
        local draft = self.MainFrame and self.MainFrame.compactDraft
        if draft then
            local from = drag.slot
            draft.slots[from], draft.slots[slot] = draft.slots[slot], draft.slots[from]
            if draft.levelingSlot == from then draft.levelingSlot = slot
            elseif draft.levelingSlot == slot then draft.levelingSlot = from end
            self:RefreshHomeView()
        elseif self.AutoRouting:SwapLoadoutPets(drag.slot, slot, drag.petID) then
            self:RefreshHomeView()
            ShowLoadoutPetChanged(slot)
        end
    end
    return true
end

function ns:DropPetIntoSlot(slotIndex, explicitPetID, fromQueue, suppressFeedback)
    if not slotIndex or slotIndex < 1 or slotIndex > 3 then return false end
    if self:FinishLoadoutSlotDrag(slotIndex) then return true end
    local cursorType, cursorPetID = GetCursorInfo()
    local petID = explicitPetID or (cursorType == "battlepet" and cursorPetID) or ns.draggingPetID or ns.draggingQueuePetID
    if fromQueue == nil then
        fromQueue = ns.draggingQueuePetID ~= nil or
            (ns.PetPickerModal and ns.PetPickerModal:IsShown() and ns.PetPickerModal.mode == "QUEUE")
    end
    if cursorType == "battlepet" then ClearCursor() end
    ns.draggingPetID, ns.draggingQueuePetID = nil, nil
    ns.isReorderingQueueList = false
    self:UpdateLoadoutSlotDragVisuals()
    if self.UpdateCompactQueueDragVisuals then self:UpdateCompactQueueDragVisuals() end
    if not petID then return false end
    if InCombatLockdown() or (C_PetBattles and C_PetBattles.IsInBattle()) then
        ns:PrintError(ns:T("战斗中无法更改编组"))
        return false
    end
    if self.MainFrame and self.MainFrame.compactDraft then
        return self:PutCompactPet(slotIndex, petID, fromQueue)
    end

    local species, _, _, _, _, _, _, _, _, _, _, _, _, _, canBattle = C_PetJournal.GetPetInfoByPetID(petID)
    local oldPet, _, _, _, locked = C_PetJournal.GetPetLoadOutInfo(slotIndex)
    if not species or canBattle == false or locked then
        ns:PrintError(ns:T("无法将此宠物放入该槽位"))
        return false
    end
    local team = self.db.teams[self.db.selectedTeamIdx]
    local oldLevelingSlot = team and team.hasLevelingSlot and (team.levelingSlot or 2)
    if fromQueue and (not team or not self.Leveling:IsPetInQueue(petID)) then return false end
    if fromQueue then
        for other = 1, 3 do
            if other ~= slotIndex and other ~= oldLevelingSlot and C_PetJournal.GetPetLoadOutInfo(other) == petID then
                self:PrintError(self:T("这只宠物已在其他普通槽位"))
                return false
            end
        end
    end
    if oldPet == petID and not fromQueue and oldLevelingSlot ~= slotIndex
        and (not team or not team.explicitSlots or team.pets[slotIndex] == petID) then return true end
    if not fromQueue and oldLevelingSlot ~= slotIndex then
        for other = 1, 3 do
            if other ~= slotIndex and oldLevelingSlot ~= other and C_PetJournal.GetPetLoadOutInfo(other) == petID then
                local swapped = self.AutoRouting:SwapLoadoutPets(other, slotIndex, petID)
                if swapped then
                    self:RefreshHomeView()
                    if not suppressFeedback then ShowLoadoutPetChanged(slotIndex) end
                end
                return swapped
            end
        end
    end
    if not fromQueue and oldLevelingSlot and oldLevelingSlot ~= slotIndex and
        C_PetJournal.GetPetLoadOutInfo(oldLevelingSlot) == petID then
        self:PrintError(self:T("请先取消原槽位的经验槽设置"))
        return false
    end

    self:EnsureTeamBackup()
    local oldFallback = team and team.levelingFallback
    if fromQueue and oldLevelingSlot ~= slotIndex then
        self.Leveling:CaptureSlotFallback(team, slotIndex, team.explicitSlots and
            (not self.staging.changedSlots or not self.staging.changedSlots[slotIndex]))
    end
    local previousDirty = self.staging.isDirty
    self.staging.isDirty = true
    self.AutoRouting:EquipPetAndSyncSkills(slotIndex, petID)
    if C_PetJournal.GetPetLoadOutInfo(slotIndex) ~= petID then
        self.AutoRouting:CancelPendingSlotEquip(slotIndex)
        self.staging.isDirty = previousDirty
        if team then team.levelingFallback = oldFallback end
        self:PrintError(self:T("无法将此宠物放入该槽位"))
        return false
    end

    if fromQueue then
        if oldLevelingSlot and oldLevelingSlot ~= slotIndex then
            self.Leveling:RestoreSlotFallback(team, oldLevelingSlot, oldFallback or {})
            self:MarkHomeSlotChanged(oldLevelingSlot)
        end
        team.hasLevelingSlot, team.levelingSlot = true, slotIndex
    elseif oldLevelingSlot == slotIndex then
        team.hasLevelingSlot, team.levelingFallback = false, nil
    end
    if team and team.randomSlots then team.randomSlots[slotIndex] = nil end
    self:MarkHomeSlotChanged(slotIndex)
    if self.MainFrame then self.MainFrame.compactSelectedPetID = nil end
    self.db.activeTargetSlot = nil
    self:RefreshHomeView()
    self:UpdateHeaderToolButtons()
    if not suppressFeedback then ShowLoadoutPetChanged(slotIndex) end
    return true
end

-- ==================== 0.5 主界面缩放与背景不透明度 ====================
function ns:GetMainUIScale()
    local settings = self.db and self.db.settings
    local manualScale = math.max(0.65, math.min(1.40, tonumber(settings and settings.uiScale) or 1))
    if not settings or not settings.uiAutoScale then return manualScale end

    local width, height = UIParent:GetSize()
    if not width or not height or width <= 0 or height <= 0 then return manualScale end

    local pixel = Theme:GetPixelScale(UIParent)
    local screenHeight = height / pixel
    local preferred = math.max(10 / 12, math.min(2, (screenHeight / 1080) ^ 0.75))
    -- Fit the active view, not always the 1120px management window.
    local minimal = settings.mainUIStyle == "MINIMAL"
    local viewWidth, viewHeight = (minimal and 348 or MAIN_WIDTH) + Theme.ActionSidebar.width, minimal and 540 or MAIN_HEIGHT
    local fit = math.min(width / (viewWidth + 32), height / (viewHeight + 56)) / pixel
    -- Keep a 12-unit font close to a whole number of physical pixels.
    local steps = math.min(math.floor(preferred * 12 + 0.5), math.floor(fit * 12))
    local physicalScale = fit < 10 / 12 and fit or steps / 12
    return physicalScale * pixel
end

function ns:MatchMainUIScale(frame)
    local parentScale = frame:GetParent():GetEffectiveScale()
    frame:SetScale(self:GetMainUIScale() * UIParent:GetEffectiveScale() / parentScale)
end

local scaleCombatWatcher = CreateFrame("Frame")
scaleCombatWatcher:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    ns:RefreshMainUIScale()
    ns:UpdateHeaderToolButtons()
end)

function ns:RefreshMainUIScale()
    local frame = self.MainFrame
    if not frame then return end
    local settingsPanel = self.DisplaySettingsPanel
    if InCombatLockdown() then
        scaleCombatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        if settingsPanel and settingsPanel:IsShown() then settingsPanel:Refresh() end
        return
    end

    local newScale = self:GetMainUIScale()
    local changed = math.abs(frame:GetScale() - newScale) > 0.0001
    if changed then
        frame:SetScale(newScale)
    end
    -- These windows can open outside the main window.
    if self.RoutingModal and self.RoutingModal:IsShown() then
        self:MatchMainUIScale(self.RoutingModal)
    end
    if self.ScriptWorkspaceModal and self.ScriptWorkspaceModal:IsShown() then
        self:MatchMainUIScale(self.ScriptWorkspaceModal)
    end
    if self.KeybindCapFrame and self.KeybindCapFrame:IsShown() then
        self:MatchMainUIScale(self.KeybindCapFrame)
    end
    for _, modal in ipairs({ self.ImportModal, self.ExportModal, self.ExportChoiceModal }) do
        if modal and modal:IsShown() then
            self:MatchMainUIScale(modal)
        end
    end
    if changed then
        Theme:RefreshAllPixelBorders()
    end
    if settingsPanel and settingsPanel:IsShown() then settingsPanel:Refresh() end
    return changed
end

function ns:ToggleDisplaySettings(button)
    if ns.DisplaySettingsPanel and ns.DisplaySettingsPanel:IsShown() then
        ns.DisplaySettingsPanel:Hide()
        return
    end
    ns:HideAllPopups()
    if not ns.DisplaySettingsPanel then
        local panel = CreateFrame("Frame", "WishPetTacticsDisplaySettingsPanel", ns.MainFrame, "BackdropTemplate")
        panel:Hide()
        panel:SetSize(276, 316)
        panel:SetFrameStrata("FULLSCREEN_DIALOG")
        panel:SetClampedToScreen(true)
        panel:EnableMouse(true)
        Theme:ApplyBackdrop(panel, Theme.Colors.bgPopup, Theme.Colors.border, false)
        tinsert(UISpecialFrames, panel:GetName())

        local panelTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        panelTitle:SetPoint("TOPLEFT", 12, -12)
        panelTitle:SetText(ns:T("显示设置"))
        Theme:HookLocalizedFontString(panelTitle)

        local closeBtn = Theme:CreateCloseIconButton(panel, function() panel:Hide() end)
        closeBtn:SetPoint("TOPRIGHT", -12, -12)

        -- 设置项统一高度 26px、左对齐、等距步进 32px。
        local ROW_START_Y = -40
        local ROW_STEP_Y  = 32

        local function CreateSettingRow(label, rowIndex, change)
            local row = CreateFrame("Frame", nil, panel)
            row:SetSize(252, 26)
            row:SetPoint("TOPLEFT", 12, ROW_START_Y - (rowIndex - 1) * ROW_STEP_Y)
            row:EnableMouse(true)
            row:EnableMouseWheel(true)
            local function ScrollSetting(_, delta)
                if delta ~= 0 then change(delta > 0 and 5 or -5) end
            end
            row:SetScript("OnMouseWheel", ScrollSetting)
            local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            name:SetPoint("LEFT", 0, 0)
            name:SetJustifyH("LEFT")
            Theme:HookLocalizedFontString(name)
            name:SetText(ns:T(label))

            local plus = Theme:CreateFlatButton(row, 26, 24, "+")
            plus._noUnderline = true
            plus:SetPoint("RIGHT", 0, 0)
            local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            value:SetPoint("RIGHT", plus, "LEFT", -4, 0)
            value:SetWidth(56)
            value:SetJustifyH("CENTER")
            local minus = Theme:CreateFlatButton(row, 26, 24, "−")
            minus._noUnderline = true
            minus:SetPoint("RIGHT", value, "LEFT", -4, 0)
            for _, btn in ipairs({minus, plus}) do
                btn:EnableMouseWheel(true)
                btn:SetScript("OnMouseWheel", ScrollSetting)
            end
            plus:SetScript("OnClick", function(_, mouseButton)
                if mouseButton == "LeftButton" then change(5) end
            end)
            minus:SetScript("OnClick", function(_, mouseButton)
                if mouseButton == "LeftButton" then change(-5) end
            end)
            return value, minus, plus
        end

        -- 第 1 行：自动缩放
        local auto = Theme:CreateFlatButton(panel, 252, 26, "", nil, "LEFT")
        auto:SetPoint("TOPLEFT", 12, ROW_START_Y - 0 * ROW_STEP_Y)
        auto:SetScript("OnClick", function(_, mouseButton)
            if mouseButton ~= "LeftButton" then return end
            local settings = ns.db.settings
            settings.uiAutoScale = not settings.uiAutoScale
            ns:RefreshMainUIScale()
        end)

        -- 第 2 行：界面缩放
        local scaleValue, scaleMinus, scalePlus = CreateSettingRow("界面缩放", 2, function(delta)
            local settings = ns.db.settings
            if settings.uiAutoScale then return end
            local percent = math.floor(ns:GetMainUIScale() * 100 + 0.5)
            settings.uiScale = math.max(65, math.min(140, percent + delta)) / 100
            ns:RefreshMainUIScale()
        end)

        -- 第 3 行：背景不透明度
        local opacityValue, opacityMinus, opacityPlus = CreateSettingRow("背景不透明度", 3, function(delta)
            local percent = math.floor((tonumber(ns.db.settings.bgAlpha) or DEFAULT_OPACITY) * 100 + 0.5)
            Theme:UpdateAllFramesAlpha(math.max(40, math.min(100, percent + delta)) / 100)
            panel:Refresh()
        end)

        -- 第 4 行：界面切换快捷键
        local styleKey = Theme:CreateActionButton(panel, 252, 26, "", "hotkey", nil, nil, false, "LEFT")
        styleKey:SetPoint("TOPLEFT", 12, ROW_START_Y - 3 * ROW_STEP_Y)
        styleKey:HookScript("OnEnter", function(self)
            ns:ShowCustomTooltip(self, "ANCHOR_RIGHT", ns:T("点击设置界面切换快捷键"))
        end)
        styleKey:HookScript("OnLeave", function(self)
            ns:HideCustomTooltip(self)
        end)
        styleKey:SetScript("OnClick", function()
            if ns.StartUIStyleKeybindCapture then ns:StartUIStyleKeybindCapture() end
        end)
        panel.styleKey = styleKey

        local petCardHoverToggle = Theme:CreateFlatButton(panel, 252, 26, "", nil, "LEFT")
        petCardHoverToggle:SetPoint("TOPLEFT", 12, ROW_START_Y - 5 * ROW_STEP_Y)
        petCardHoverToggle:SetScript("OnClick", function(_, mouseButton)
            if mouseButton ~= "LeftButton" then return end
            local settings = ns.db.settings
            settings.petCardHover3D = settings.petCardHover3D == false
            if not settings.petCardHover3D then
                if ns.HidePetDetailTooltip then ns:HidePetDetailTooltip(true) end
            elseif ns.hoveredPetFrame and ns.hoveredPetData and ns.hoveredPetFrame:IsMouseOver() then
                ns:ShowPetDetailTooltip(ns.hoveredPetFrame, ns.hoveredPetData, false)
            end
            panel:Refresh()
        end)

        -- 第 8 行：恢复默认显示设置
        local reset = Theme:CreateActionButton(panel, 252, 26, "恢复默认显示设置", "restore", nil, nil, false, "LEFT")
        reset:SetPoint("TOPLEFT", 12, ROW_START_Y - 7 * ROW_STEP_Y)
        reset:SetScript("OnClick", function(_, mouseButton)
            if mouseButton ~= "LeftButton" then return end
            ns.db.settings.uiAutoScale = true
            ns.db.settings.uiScale = 1
            ns.db.settings.petCardHover3D = true
            Theme:UpdateAllFramesAlpha(DEFAULT_OPACITY)
            ns:RefreshMainUIScale()
            if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then
                ns:ShowBattleHUD(true)
            end
            panel:Refresh()
        end)

        function panel:Refresh()
            local settings = ns.db.settings
            auto:SetSelected(settings.uiAutoScale)
            auto.text:SetText(ns:T(settings.uiAutoScale and "自动缩放：开启" or "自动缩放：关闭"))
            petCardHoverToggle:SetSelected(settings.petCardHover3D ~= false)
            petCardHoverToggle.text:SetText(ns:T(settings.petCardHover3D ~= false
                and "宠物悬停3D详情：开启" or "宠物悬停3D详情：关闭（按住Shift）"))
            local scalePercent = math.floor(ns.MainFrame:GetScale() * 100 + 0.5)
            local opacityPercent = math.floor((tonumber(settings.bgAlpha) or DEFAULT_OPACITY) * 100 + 0.5)
            scaleValue:SetText(string.format("%d%%", scalePercent))
            opacityValue:SetText(string.format("%d%%", opacityPercent))
            local manualScale = tonumber(settings.uiScale) or 1
            scaleMinus:SetEnabled(not settings.uiAutoScale and manualScale > 0.65)
            scalePlus:SetEnabled(not settings.uiAutoScale and manualScale < 1.40)
            opacityMinus:SetEnabled(opacityPercent > 40)
            opacityPlus:SetEnabled(opacityPercent < 100)
            styleKey.text:SetText(ns:T("界面切换快捷键") .. ": |cff38bdf8"
                .. (ns.GetUIStyleKeyText and ns:GetUIStyleKeyText() or ns:T("未绑定")) .. "|r")
        end

        ns.DisplaySettingsPanel = panel
        local function RefreshDisplayIcon()
            ns:RefreshHeaderHubIconStates()
        end
        panel:HookScript("OnShow", RefreshDisplayIcon)
        panel:HookScript("OnHide", RefreshDisplayIcon)
    end
    local panel = ns.DisplaySettingsPanel
    panel:ClearAllPoints()
    if ns.MainFrame then
        panel:SetPoint("TOPLEFT", ns.MainFrame, "TOPRIGHT", 6, 0)
    elseif button then
        panel:SetPoint("TOPLEFT", button, "TOPRIGHT", 6, 0)
    end
    panel:Refresh()
    panel:Show()
    ns:EnablePopupClickCatcher(panel)
end

-- ==================== 1. 顶栏状态与右侧快捷工具刷新 ====================
-- The secure item buttons stay parented to this shared frame in both modes.
-- Only their anchors/visibility change, and only outside combat lockdown.
function ns:RefreshActionSidebarLayout()
    local f = self.MainFrame
    if not f or not f.actionSidebar or InCombatLockdown() then return end
    local sidebar, metrics = f.actionSidebar, Theme.ActionSidebar
    -- The full view's inner cabin ends before the main window's right border.
    -- Dock outside that outer border, at the main window's top, in both modes.
    local dockGap = metrics.dockGapPixels * Theme:GetPixelScale(f)
    if sidebar._layoutAnchor ~= f or sidebar._dockGap ~= dockGap then
        sidebar._layoutAnchor, sidebar._dockGap = f, dockGap
        sidebar:ClearAllPoints()
        sidebar:SetPoint("TOPLEFT", f, "TOPRIGHT", dockGap, 0)
    end
    local y = metrics.padding
    local function Place(button)
        if not button then return end
        if button._sidebarY ~= y then
            button._sidebarY = y
            button:ClearAllPoints()
            button:SetPoint("TOP", sidebar, "TOP", 0, -y)
        end
        y = y + metrics.iconSize + metrics.gap
    end
    local isMinimal = (f.mainUIStyle == "MINIMAL")
    if f.sidebarAllPetsBtn then
        f.sidebarAllPetsBtn:SetShown(isMinimal)
        if isMinimal then Place(f.sidebarAllPetsBtn) end
    end
    if f.sidebarQueueBtn then
        f.sidebarQueueBtn:SetShown(isMinimal)
        if isMinimal then Place(f.sidebarQueueBtn) end
    end
    Place(f.routeHubBtn)
    Place(f.scriptHubBtn)
    Place(f.displaySettingsBtn)
    Place(f.viewModeToggle)
    if sidebar._dividerY ~= y then
        sidebar._dividerY = y
        sidebar.divider:ClearAllPoints()
        sidebar.divider:SetPoint("TOPLEFT", sidebar, "TOPLEFT", metrics.padding, -y - 2)
        sidebar.divider:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -metrics.padding, -y - 2)
    end
    y = y + metrics.sectionGap
    for _, name in ipairs({"reviveBtn", "bandageBtn", "hatBtn"}) do
        local button = f[name]
        if button and button:IsShown() then Place(button) end
    end
    for _, button in ipairs(f.foodBtns or {}) do
        if button:IsShown() then Place(button) end
    end
    local height = y - metrics.gap + metrics.padding
    if sidebar:GetHeight() ~= height then sidebar:SetHeight(height) end
end

function ns:UpdateHeaderToolButtons()
    local f = ns.MainFrame
    if not f or not f:IsShown() then return end

    EnsureBagCountsCached()

    local team = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
    if f.teamHubBtn then
        if team then
            local grp = ns:T(team.group or "未分组队伍")
            local hasUnderLv = false
            if ns.staging and ns.staging.isDirty then
                local lvSlot = team.levelingSlot or (ns.db and ns.db.settings.levelingSlot) or 2
                for s = 1, 3 do
                    local isLv = (team.hasLevelingSlot and lvSlot == s)
                    if not isLv then
                        local pID = C_PetJournal.GetPetLoadOutInfo(s)
                        if pID then
                            local _, _, pLv = C_PetJournal.GetPetInfoByPetID(pID)
                            if pLv and pLv < 25 then
                                hasUnderLv = true
                                break
                            end
                        end
                    end
                end
            elseif ns.CheckTeamUnderleveledPets then
                hasUnderLv = select(1, ns:CheckTeamUnderleveledPets(team))
            end

            local warnPrefix = hasUnderLv and ("|cffff9900" .. ns:T("[未满级]") .. "|r ") or ""
            f.teamHubBtn.teamText = string.format("%s|cff38bdf8[%s]|r |cffffffff%s|r", warnPrefix, grp, team.name or ns:T("未命名队伍"))
        else
            f.teamHubBtn.teamText = "|cff9ca3af" .. ns:T("未选择队伍") .. "|r"
        end
    end

    if f.UpdatePetHubBtnState then
        f:UpdatePetHubBtnState()
    end

    local start, duration = 0, 0
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, REVIVE_SPELL_ID)
        if ok and cdInfo and not IsSecret(cdInfo.startTime) and not IsSecret(cdInfo.duration) then
            start = cdInfo.startTime or 0
            duration = cdInfo.duration or 0
        end
    elseif GetSpellCooldown then
        local ok, s, d = pcall(GetSpellCooldown, REVIVE_SPELL_ID)
        if ok and not IsSecret(s) and not IsSecret(d) then
            start = s or 0
            duration = d or 0
        end
    end
    f._hasActiveCooldown = false
    local locked = InCombatLockdown()
    if locked then scaleCombatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED") end

    if f.reviveBtn then
        local button = f.reviveBtn
        local reviveRemain = UpdateToolCooldown(button, start, duration)
        f._reviveRemain = reviveRemain
        button.icon:SetDesaturated(reviveRemain > 0)
        button:SetBackdropBorderColor(unpack(reviveRemain > 0 and Theme.Colors.border or Theme.Colors.borderGreen))
        if not locked then button:Show() end
    end
    if f.bandageBtn then
        local available = (bagCache.bandage or 0) > 0
        f.bandageBtn.countTxt:SetText(tostring(bagCache.bandage or 0))
        UpdateToolCooldown(f.bandageBtn, GetToolItemCooldown(BANDAGE_ITEM_ID, available))
        f.bandageBtn.icon:SetDesaturated(not available)
        f.bandageBtn:SetBackdropBorderColor(unpack(available and Theme.Colors.borderBlue or Theme.Colors.border))
        if not locked then f.bandageBtn:SetShown(available) end
    end
    if f.hatBtn then
        local active = SafeHasPlayerAuraBySpellID(SAFARI_BUFF_ID)
        UpdateToolCooldown(f.hatBtn, GetToolItemCooldown(SAFARI_HAT_ID, bagCache.hasHat))
        f.hatBtn.icon:SetDesaturated(false)
        local shade = active and 1 or 0.85
        f.hatBtn.icon:SetVertexColor(shade, shade, shade)
        f.hatBtn:SetBackdropBorderColor(unpack(active and Theme.Colors.borderGreen or Theme.Colors.borderAmber))
        if not locked then f.hatBtn:SetShown(bagCache.hasHat) end
    end
    for idx, foodDef in ipairs(PET_EXP_FOOD_ITEMS) do
        local button = f.foodBtns and f.foodBtns[idx]
        if button then
            local available = (bagCache.foods[idx] or 0) > 0
            button.countTxt:SetText(tostring(bagCache.foods[idx] or 0))
            button.icon:SetDesaturated(not available)
            local active = foodDef.buffID and SafeHasPlayerAuraBySpellID(foodDef.buffID)
            button:SetBackdropBorderColor(unpack(active and Theme.Colors.borderGreen or Theme.Colors.borderAmber))
            UpdateToolCooldown(button, GetToolItemCooldown(foodDef.itemID, available))
            if not locked then button:SetShown(available) end
        end
    end
    self:RefreshActionSidebarLayout()
    local owner = GameTooltip and GameTooltip:IsShown() and GameTooltip:GetOwner()
    if owner and owner.RefreshSidebarTooltip then
        if owner:IsVisible() then owner:RefreshSidebarTooltip() else GameTooltip:Hide() end
    end
    self:UpdateMainFrameTicker()
end

local headerUpdatePending = false
local function RunDeferredHeaderUpdate()
    headerUpdatePending = false
    if ns.MainFrame and ns.MainFrame:IsShown() then
        ns:UpdateHeaderToolButtons()
    end
end

local function RequestHeaderToolUpdate()
    if headerUpdatePending then return end
    if not ns.MainFrame or not ns.MainFrame:IsShown() then return end
    headerUpdatePending = true
    C_Timer.After(0.12, RunDeferredHeaderUpdate)
end

-- ==================== 2. 视图模式切换 ====================
function ns:SwitchMainViewMode(viewMode)
    local f = ns.MainFrame
    if not f then return end
    if ns.HideAllPopups then ns:HideAllPopups() end
    if ns.PetCardModal then
        ns.PetCardModal.isPinned = false
        ns.PetCardModal:Hide()
    end

    f.currentViewMode = "HOME"
    if f.homeView then f.homeView:Show() end
    if self.ApplyMainUIStyle then self:ApplyMainUIStyle() end

    self:UpdateHeaderToolButtons()
    if self.RefreshHomeView then self:RefreshHomeView() end

    local team = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
    if team and ns.ScriptEditBox and ns.ScriptEditBox:IsVisible() and ns.SyncScriptEditor then
        ns:SyncScriptEditor(team)
    end


    if viewMode == "TEAMS" and ns.ShowTeamMatrixModal then
        ns:ShowTeamMatrixModal()
    elseif viewMode == "SCRIPT" and ns.ToggleScriptWorkspace then
        ns:ToggleScriptWorkspace(true)
    end
end

-- ==================== 3. 创建主窗口（按需注册事件，关闭后零后台监听） ====================
local function RegisterMainFrameActiveEvents(f)
    f:RegisterEvent("GLOBAL_MOUSE_DOWN")
    f:RegisterEvent("GLOBAL_MOUSE_UP")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    f:RegisterEvent("BAG_UPDATE_COOLDOWN")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    if f.RegisterUnitEvent then
        f:RegisterUnitEvent("UNIT_AURA", "player")
    else
        f:RegisterEvent("UNIT_AURA")
    end
end

function ns:CreateMainFrame(startHidden)
    if ns.MainFrame then return ns.MainFrame end

    local function SaveMainFramePosition(frame)
        if not frame or not ns.db or not ns.db.settings then return end
        local point, _, relPoint, xOfs, yOfs = frame:GetPoint(1)
        if point and relPoint and xOfs and yOfs then
            ns.db.settings.windowPos = {
                point = point,
                relPoint = relPoint,
                x = xOfs,
                y = yOfs,
            }
        end
    end

    local function RestoreMainFramePosition(frame)
        if not frame then return end
        local anchorParent = frame:GetParent() or UIParent
        local pos = ns.db and ns.db.settings and ns.db.settings.windowPos
        if type(pos) == "table" and pos.point and pos.relPoint and pos.x and pos.y then
            frame:ClearAllPoints()
            frame:SetPoint(pos.point, anchorParent, pos.relPoint, pos.x, pos.y)
        elseif frame:GetNumPoints() == 0 then
            frame:SetPoint("CENTER", anchorParent, "CENTER", 0, 0)
        end
    end
    ns.SaveMainFramePosition = SaveMainFramePosition
    ns.RestoreMainFramePosition = RestoreMainFramePosition

    local f = CreateFrame("Frame", "WishPetTacticsMainFrame", UIParent, "BackdropTemplate")
    if startHidden then f:Hide() end
    f:SetSize(MAIN_WIDTH, MAIN_HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetScale(self:GetMainUIScale())
    RestoreMainFramePosition(f)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveMainFramePosition(self)
    end)
    Theme:ApplyBackdrop(f, Theme.Colors.bgMain, Theme.Colors.border, true)

    if f:IsShown() then RegisterMainFrameActiveEvents(f) end

    -- 不在主窗口启用 EnableKeyboard，确保打开插件时魔兽世界所有移动键、技能键与快捷键 100% 正常响应
    f:EnableKeyboard(false)
    if UISpecialFrames then
        local fname = f:GetName()
        local found = false
        for i = 1, #UISpecialFrames do
            if UISpecialFrames[i] == fname then found = true; break end
        end
        if not found then tinsert(UISpecialFrames, fname) end
    end
    local function UpdateEscapeInput() end

    f:HookScript("OnShow", function(self)
        if ns.SyncMainFrameBattleParent then ns:SyncMainFrameBattleParent() end
        if ns.RestoreMainFramePosition then ns.RestoreMainFramePosition(self) end
        UpdateEscapeInput()
        bagCache.dirty = true
        RegisterMainFrameActiveEvents(self)
        ns:UpdateHeaderToolButtons()
        ns.Leveling:RefreshSelectedSlot()
    end)

    f:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        self:SetScript("OnUpdate", nil)
        self._cooldownElapsed = 0
        ns:FinishLoadoutSlotDrag()
        if ns.draggingPetID or ns.draggingQueuePetID then
            if GetCursorInfo() == "battlepet" then ClearCursor() end
            ns.draggingPetID, ns.draggingQueuePetID = nil, nil
            ns.isReorderingQueueList = false
            ns:UpdateLoadoutSlotDragVisuals()
        end
        if ns.DisplaySettingsPanel then ns.DisplaySettingsPanel:Hide() end
        if self.compactAbilityPopup then self.compactAbilityPopup:Hide() end
        if self.minimalPicker then self.minimalPicker:Hide() end
        if ns.UIStyleKeyCapture then ns.UIStyleKeyCapture:Hide() end
        if self.compactSwitchPrompt then self.compactSwitchPrompt:Hide() end
        if ns.ExportChoiceModal then ns.ExportChoiceModal:Hide() end
        if ns.ExportModal then ns.ExportModal:Hide() end
        if ns.ImportModal then ns.ImportModal:Hide() end
        self.compactSelectedPetID = nil
        ns.db.activeTargetSlot = nil
        if ns.HidePetDetailTooltip then ns:HidePetDetailTooltip() end
        if ns.PetPickerModal then
            ns.PetPickerModal:Hide()
            ns.PetPickerModal.lastSlot = nil
        end
        if ns.QueueDragGhost then
            ns.QueueDragGhost:SetScript("OnUpdate", nil)
            ns.QueueDragGhost:Hide()
        end
    end)

    f:SetScript("OnEvent", function(self, event, arg1)
        if not self:IsShown() then return end
        if event == "GLOBAL_MOUSE_DOWN" then
            if self.compactLeft and self.compactLeft.searchBox and self.compactLeft.searchBox:HasFocus()
                and not self.compactLeft.searchBox:IsMouseOver() then
                self.compactLeft.searchBox:ClearFocus()
            end
            if self.minimalPicker and self.minimalPicker.search and self.minimalPicker.search:HasFocus()
                and not self.minimalPicker.search:IsMouseOver() then
                self.minimalPicker.search:ClearFocus()
            end
            if self.minimalPicker and self.minimalPicker:IsShown() and not self.minimalPicker:IsMouseOver() then
                local overCard = false
                for _, card in ipairs(self.loadoutCards or {}) do
                    if card:IsVisible() and card:IsMouseOver() then overCard = true; break end
                end
                local overMenuOrExport = (ns.ContextMenu and ns.ContextMenu:IsShown() and ns.ContextMenu:IsMouseOver())
                    or (ns.ExportChoiceModal and ns.ExportChoiceModal:IsShown() and ns.ExportChoiceModal:IsMouseOver())
                    or (ns.ExportModal and ns.ExportModal:IsShown() and ns.ExportModal:IsMouseOver())
                    or (ns.ImportModal and ns.ImportModal:IsShown() and ns.ImportModal:IsMouseOver())
                if not overCard and not overMenuOrExport and not (self.minimalTeamLink and self.minimalTeamLink:IsMouseOver()) then
                    ns:CloseMinimalPicker()
                end
            end
            local abilityPopup = self.compactAbilityPopup
            if abilityPopup and abilityPopup:IsShown() and not abilityPopup:IsMouseOver()
                and not (abilityPopup.anchor and abilityPopup.anchor:IsMouseOver()) then
                abilityPopup:Hide()
            end
            if ns.db and (ns.db.activeTargetSlot ~= nil or self.compactSelectedPetID) then
                local overAnyCard = false
                if self.loadoutCards then
                    for s = 1, 3 do
                        if self.loadoutCards[s] and self.loadoutCards[s]:IsVisible() and self.loadoutCards[s]:IsMouseOver() then
                            overAnyCard = true
                            break
                        end
                    end
                end
                local overBuilder = (ns.TeamBuilderModal and ns.TeamBuilderModal:IsShown() and ns.TeamBuilderModal:IsMouseOver())
                local overDrawer = (ns.PetPickerModal and ns.PetPickerModal:IsShown() and ns.PetPickerModal:IsMouseOver())
                local overSlotMenu = (ns.SlotContextMenu and ns.SlotContextMenu:IsShown() and ns.SlotContextMenu:IsMouseOver())
                local overCompactLeft = (self.compactLeft and self.compactLeft:IsShown() and self.compactLeft:IsMouseOver())
                local overMinimalPicker = (self.minimalPicker and self.minimalPicker:IsShown() and self.minimalPicker:IsMouseOver())
                local overPetCard = (ns.PetCardModal and ns.PetCardModal:IsShown() and ns.PetCardModal:IsMouseOver())
                if not overAnyCard and not overBuilder and not overDrawer and not overSlotMenu
                    and not overCompactLeft and not overMinimalPicker and not overPetCard then
                    if self.minimalPicker and self.minimalPicker:IsShown() then
                        ns:CloseMinimalPicker()
                    end
                    ns.db.activeTargetSlot = nil
                    self.compactSelectedPetID = nil
                    if ns.RefreshLoadoutCabin then ns:RefreshLoadoutCabin() end
                end
            end
        elseif event == "GLOBAL_MOUSE_UP" then
            if arg1 ~= "LeftButton" then return end
            if ns.loadoutSlotDrag then
                local slot
                for index, card in ipairs(self.loadoutCards) do
                    if card:IsVisible() and card:IsMouseOver() then
                        slot = index
                        break
                    end
                end
                ns:FinishLoadoutSlotDrag(slot)
                return
            end
            local activeDragPet = ns.draggingPetID or ns.draggingQueuePetID
            local cursorType, cursorPetID
            if not activeDragPet then
                cursorType, cursorPetID = GetCursorInfo()
                if cursorType == "battlepet" then
                    activeDragPet = cursorPetID
                end
            end

            if activeDragPet then
                if ns.TeamBuilderModal and ns.TeamBuilderModal:IsShown() and ns.TeamBuilderModal.slots then
                    for slot = 1, 3 do
                        local bSlot = ns.TeamBuilderModal.slots[slot]
                        if bSlot and bSlot:IsVisible() and bSlot:IsMouseOver() then
                            ns.queueDropHandledBySlot = true
                            ns.TeamBuilderModal:AssignPetToSlot(slot, activeDragPet)
                            return
                        end
                    end
                end

                if self.loadoutCards then
                    for slot = 1, 3 do
                        local card = self.loadoutCards[slot]
                        if card and card:IsVisible() and card:IsMouseOver() then
                            ns.queueDropHandledBySlot = true
                            ns:DropPetIntoSlot(slot, activeDragPet)
                            ns:RefreshHomeView()
                            return
                        end
                    end
                end

                if ns.draggingQueuePetID and ns.FinishCompactQueueDrag and ns:FinishCompactQueueDrag() then
                    return
                end

                if not (ns.PetPickerModal and ns.PetPickerModal:IsShown() and ns.PetPickerModal.draggingSourcePetID) then
                    ns.isReorderingQueueList = false
                    ns.draggingPetID = nil
                    ns.draggingQueuePetID = nil
                    if GetCursorInfo() == "battlepet" then ClearCursor() end
                    ns:UpdateLoadoutSlotDragVisuals()
                    if ns.UpdateCompactQueueDragVisuals then ns:UpdateCompactQueueDragVisuals() end
                end
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            UpdateEscapeInput()
            ns.Leveling:RefreshSelectedSlot()
            ns:RefreshHomeView()
        elseif event == "BAG_UPDATE_DELAYED" then
            bagCache.dirty = true
            RequestHeaderToolUpdate()
        elseif event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN"
            or (event == "UNIT_AURA" and not IsSecret(arg1) and arg1 == "player") then
            RequestHeaderToolUpdate()
        end
    end)

    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(48)
    Theme:ApplyBackdrop(header, Theme.Colors.bgPanel, Theme.Colors.border, true)
    f.header = header

    local wordmark = header:CreateTexture(nil, "ARTWORK")
    wordmark:SetPoint("LEFT", 20, 0)
    wordmark:SetSize(256, 44)
    wordmark:SetTexCoord(0, 1, 40 / 256, 216 / 256)
    wordmark:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Branding\\wordmark.tga", "CLAMP", "CLAMP", "LINEAR")
    Theme:SnapTextureToPixel(wordmark)
    f.wordmark = wordmark

    local versionText = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    -- The wordmark texture has transparent padding at its lower edge; lift
    -- the font baseline so the visible glyph bottoms align with the artwork.
    versionText:SetPoint("BOTTOMLEFT", wordmark, "BOTTOMRIGHT", 6, 13)
    versionText:SetJustifyH("LEFT")
    local version = C_AddOns and C_AddOns.GetAddOnMetadata
        and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "6.1.24"
    versionText:SetText("|cff8b95a5" .. string.gsub(version, "%.", " . ") .. "|r")
    f.versionText = versionText

    -- The header arrow stays next to Close while the separate dock is hidden.
    local sidebarToggle = CreateFrame("Button", nil, header, "SecureHandlerClickTemplate")
    sidebarToggle:SetSize(Theme.ActionSidebar.toggleSize, Theme.ActionSidebar.toggleSize)
    sidebarToggle:RegisterForClicks("LeftButtonUp")
    sidebarToggle.icon = sidebarToggle:CreateTexture(nil, "ARTWORK")
    sidebarToggle.icon:SetSize(12, 12)
    sidebarToggle.icon:SetPoint("CENTER", 0, 0)
    sidebarToggle.icon:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Common\\down.tga")
    sidebarToggle.icon:SetVertexColor(0.75, 0.83, 0.92, 1)
    Theme:SnapTextureToPixel(sidebarToggle.icon)
    f.actionSidebarToggle = sidebarToggle

    local sidebar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    sidebar:SetSize(Theme.ActionSidebar.width, 192)
    Theme:ApplyBackdrop(sidebar, Theme.Colors.bgPanel, Theme.Colors.border, true)
    sidebar.divider = sidebar:CreateTexture(nil, "BORDER")
    sidebar.divider:SetHeight(Theme:GetPixelScale(sidebar))
    sidebar.divider:SetColorTexture(unpack(Theme.Colors.divider))
    f.actionSidebar = sidebar

    local function SyncSidebarToggle()
        local collapsed = not sidebar:IsShown()
        sidebarToggle.icon:SetRotation(collapsed and math.pi / 2 or -math.pi / 2)
        if ns.db and ns.db.settings then ns.db.settings.actionSidebarCollapsed = collapsed end
    end
    local function ShowSidebarToggleTip(self)
        if ns.ShowCustomTooltip then
            ns:ShowCustomTooltip(self, "ANCHOR_RIGHT", ns:T(sidebar:IsShown() and "收起侧边栏" or "展开侧边栏"))
        end
    end
    -- Use the global API so creation does not depend on template helper methods.
    SecureHandlerSetFrameRef(sidebarToggle, "sidebar", sidebar)
    -- This click handler can show/hide secure item buttons during combat.
    sidebarToggle:SetAttribute("_onclick", [[
        local sidebar = self:GetFrameRef("sidebar")
        if sidebar:IsShown() then sidebar:Hide() else sidebar:Show() end
    ]])
    sidebarToggle:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(0.22, 0.74, 0.97, 1)
        ShowSidebarToggleTip(self)
    end)
    sidebarToggle:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(0.75, 0.83, 0.92, 1)
        if ns.HideCustomTooltip then ns:HideCustomTooltip(self) end
    end)
    sidebarToggle:HookScript("OnClick", function(self)
        SyncSidebarToggle()
        if self:IsMouseOver() then ShowSidebarToggleTip(self) end
    end)
    sidebar:HookScript("OnShow", function()
        SyncSidebarToggle()
        ns:UpdateHeaderToolButtons()
    end)
    sidebar:HookScript("OnHide", SyncSidebarToggle)
    sidebar:SetShown(not (ns.db and ns.db.settings and ns.db.settings.actionSidebarCollapsed))
    SyncSidebarToggle()

    local closeBtn = Theme:CreateCloseIconButton(header, function() ns:RequestMainFrameClose() end)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -20, 0)
    f.closeBtn = closeBtn
    sidebarToggle:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)

    local petHubBtn = Theme:CreateHeaderHubIcon(header, "pets", "宠物", "PetPickerModal", 0.39, 0.80, 1.00)
    petHubBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    petHubBtn:SetScript("OnClick", function()
        if ns.TogglePetPickerDrawer then
            ns:TogglePetPickerDrawer(nil, nil, true)
        end
    end)
    f.petHubBtn = petHubBtn

    function f:UpdatePetHubBtnState()
        ns:RefreshHeaderHubIconStates()
    end

    local teamHubBtn = Theme:CreateHeaderHubIcon(header, "team", "队伍管理", "TeamMatrixModal", 1.0, 0.78, 0.43)
    teamHubBtn:SetPoint("RIGHT", petHubBtn, "LEFT", -8, 0)
    teamHubBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    teamHubBtn:SetScript("OnClick", function(button, mouseButton)
        if mouseButton == "RightButton" then
            ns:ShowTeamContextMenu(button, ns.db.selectedTeamIdx or 1)
        else
            ns:ToggleTeamMatrixModal()
        end
    end)
    teamHubBtn._hubTooltip = function()
        return ns:T("队伍管理") .. "\n"
            .. (teamHubBtn.teamText or ns:T("未选择队伍")) .. "\n"
            .. ns:T("右键：当前队伍操作")
    end
    f.teamHubBtn = teamHubBtn

    local sidebarAllPetsBtn = Theme:CreateHeaderHubIcon(sidebar, "pets", "所有宠物", nil, 0.39, 0.80, 1.00, Theme.ActionSidebar.iconSize)
    sidebarAllPetsBtn._hubTooltipAnchor = "ANCHOR_RIGHT"
    sidebarAllPetsBtn._hubIsOpenFunc = function()
        return f.minimalPicker and f.minimalPicker:IsShown() and f.minimalPicker.mode == "ALL_PETS"
    end
    sidebarAllPetsBtn._hubTooltip = function()
        return ns:T("所有宠物") .. "\n" .. ns:T("点击打开简约宠物列表")
    end
    sidebarAllPetsBtn:SetScript("OnClick", function()
        if f.mainUIStyle == "MINIMAL" or (C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle()) then
            if f.minimalPicker and f.minimalPicker:IsShown() and f.minimalPicker.mode == "ALL_PETS" then
                ns:CloseMinimalPicker()
            else
                ns:OpenMinimalPicker("ALL_PETS")
            end
        else
            if ns.TogglePetPickerDrawer then
                ns:TogglePetPickerDrawer(nil, "PETS", true)
            end
        end
    end)
    f.sidebarAllPetsBtn = sidebarAllPetsBtn

    local sidebarQueueBtn = Theme:CreateHeaderHubIcon(sidebar, "queue", "练级队列", nil, 1.00, 0.78, 0.43, Theme.ActionSidebar.iconSize)
    sidebarQueueBtn._hubTooltipAnchor = "ANCHOR_RIGHT"
    sidebarQueueBtn._hubIsOpenFunc = function()
        return f.minimalPicker and f.minimalPicker:IsShown() and f.minimalPicker.mode == "QUEUE"
    end
    sidebarQueueBtn._hubTooltip = function()
        local count = ns.Leveling and ns.Leveling.GetManualQueueCount and ns.Leveling:GetManualQueueCount() or 0
        return ns:T("练级队列") .. "\n"
            .. ns:TF("当前队列宠物数：%d", count) .. "\n"
            .. ns:T("点击打开简约练级队列")
    end
    sidebarQueueBtn:SetScript("OnClick", function()
        if f.mainUIStyle == "MINIMAL" or (C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle()) then
            if f.minimalPicker and f.minimalPicker:IsShown() and f.minimalPicker.mode == "QUEUE" then
                ns:CloseMinimalPicker()
            else
                ns:OpenMinimalPicker("QUEUE")
            end
        else
            if ns.TogglePetPickerDrawer then
                ns:TogglePetPickerDrawer(nil, "QUEUE", true)
            end
        end
    end)
    f.sidebarQueueBtn = sidebarQueueBtn

    local routeHubBtn = Theme:CreateHeaderHubIcon(sidebar, "target", "目标", "RoutingModal", 0.24, 0.88, 0.69, Theme.ActionSidebar.iconSize)
    routeHubBtn._hubTooltipAnchor = "ANCHOR_RIGHT"
    routeHubBtn:SetScript("OnClick", function()
        if ns.ShowRoutingModal then ns:ShowRoutingModal() end
    end)
    f.routeHubBtn = routeHubBtn

    local scriptHubBtn = Theme:CreateHeaderHubIcon(sidebar, "script", "脚本", "ScriptWorkspaceModal", 0.73, 0.60, 1.00, Theme.ActionSidebar.iconSize)
    scriptHubBtn._hubTooltipAnchor = "ANCHOR_RIGHT"
    scriptHubBtn:SetScript("OnClick", function()
        if ns.ToggleScriptWorkspace then ns:ToggleScriptWorkspace() end
    end)
    f.scriptHubBtn = scriptHubBtn

    local displayBtn = Theme:CreateHeaderHubIcon(sidebar, "display", "显示设置", "DisplaySettingsPanel", 0.69, 0.83, 0.97, Theme.ActionSidebar.iconSize)
    displayBtn._hubTooltipAnchor = "ANCHOR_RIGHT"
    displayBtn:SetScript("OnClick", function(button, mouseButton)
        if mouseButton == "LeftButton" then ns:ToggleDisplaySettings(button) end
    end)
    f.displaySettingsBtn = displayBtn

    local function UpdateSecureIconInset(btn)
        local px = Theme:GetPixelScale(btn)
        if btn._lastInsetPx == px or not btn.icon then return end
        btn._lastInsetPx = px
        btn.icon:ClearAllPoints()
        btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", px, -px)
        btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -px, px)
    end

    local function HideGameTooltip(self)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end

    local function BeginSidebarTooltip(button)
        if ns.HideCustomTooltip then ns:HideCustomTooltip() end
        GameTooltip:SetOwner(button, "ANCHOR_NONE")
        ns:AnchorActionSidebarTooltip(GameTooltip, button)
    end

    local function FinishSidebarTooltip(button)
        if (button._cooldownRemaining or 0) > 0 then
            GameTooltip:AddLine(ns:TF("冷却剩余：%s", FormatCooldownTime(button._cooldownRemaining)), 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end

    local function CreateSecureSidebarIconBtn(name, defaultTex, showCount)
        local btn = CreateFrame("Button", name, sidebar, "SecureActionButtonTemplate,BackdropTemplate")
        btn:SetSize(Theme.ActionSidebar.iconSize, Theme.ActionSidebar.iconSize)
        btn:RegisterForClicks("AnyUp", "AnyDown")
        Theme:ApplyBackdrop(btn, Theme.Colors.bgInput, Theme.Colors.border, false)

        local tex = btn:CreateTexture(nil, "ARTWORK")
        Theme:ConfigureButtonIcon(tex, defaultTex)
        btn.icon = tex
        Theme:RegisterInlineIconMetrics(btn, UpdateSecureIconInset)

        local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cd:SetAllPoints(tex)
        cd:SetHideCountdownNumbers(true)
        btn.cooldown = cd

        -- Keep status text above the cooldown swipe, independent of the game's
        -- countdown-number setting. The buttons remain compact 32x32 icons.
        local status = CreateFrame("Frame", nil, btn)
        status:SetAllPoints(btn)
        status:SetFrameLevel(cd:GetFrameLevel() + 1)
        status:EnableMouse(false)
        btn.statusOverlay = status
        btn.cdTxt = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        local font, size = btn.cdTxt:GetFont()
        btn.cdTxt:SetFont(font, math.min(size, 11), "OUTLINE")
        btn.cdTxt:SetPoint("CENTER", btn, "CENTER", 0, 2)
        btn.cdTxt:SetTextColor(1, 0.82, 0)
        btn.cdTxt:Hide()
        if showCount then
            btn.countTxt = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.countTxt:SetFont(font, math.min(size, 10), "OUTLINE")
            btn.countTxt:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
            btn.countTxt:SetJustifyH("RIGHT")
            btn.countTxt:SetTextColor(1, 1, 1)
        end

        btn:SetScript("OnLeave", HideGameTooltip)
        btn:SetScript("OnHide", HideGameTooltip)
        return btn
    end

    local hatIcon = HEADER_TEX_ROOT .. "hat.tga"
    local hatBtn = CreateSecureSidebarIconBtn("WishPetTacticsSafariHatBtn", hatIcon)
    hatBtn:SetAttribute("type", "toy")
    hatBtn:SetAttribute("toy", SAFARI_HAT_ID)
    hatBtn.RefreshSidebarTooltip = function(self)
        BeginSidebarTooltip(self)
        GameTooltip:SetToyByItemID(SAFARI_HAT_ID)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ns:T("|cff10b981点击佩戴/取消狩猎帽（小宠物经验值提高 10%）|r"), 1, 1, 1, true)
        GameTooltip:AddLine(ns:T(SafeHasPlayerAuraBySpellID(SAFARI_BUFF_ID) and "生效" or "未戴"))
        FinishSidebarTooltip(self)
    end
    hatBtn:SetScript("OnEnter", hatBtn.RefreshSidebarTooltip)
    f.hatBtn = hatBtn

    local bandageIcon = HEADER_TEX_ROOT .. "bandage.tga"
    local bandageBtn = CreateSecureSidebarIconBtn("WishPetTacticsBandageBtn", bandageIcon, true)
    bandageBtn:SetAttribute("type", "item")
    bandageBtn:SetAttribute("item", "item:" .. BANDAGE_ITEM_ID)
    bandageBtn.RefreshSidebarTooltip = function(self)
        BeginSidebarTooltip(self)
        GameTooltip:SetItemByID(BANDAGE_ITEM_ID)
        local cnt = bagCache.bandage or GetBagItemCount(BANDAGE_ITEM_ID)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ns:TF("|cff3b82f6背包剩余数量：%d 个（点击立即恢复所有宠物）|r", cnt), 1, 1, 1, true)
        FinishSidebarTooltip(self)
    end
    bandageBtn:SetScript("OnEnter", bandageBtn.RefreshSidebarTooltip)
    f.bandageBtn = bandageBtn

    local reviveName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(REVIVE_SPELL_ID)) or ns:T("复活战斗宠物")
    local reviveSpellIcon = HEADER_TEX_ROOT .. "revive.tga"
    local reviveBtn = CreateSecureSidebarIconBtn("WishPetTacticsReviveBtn", reviveSpellIcon)
    reviveBtn:SetAttribute("type", "spell")
    reviveBtn:SetAttribute("spell", reviveName)
    reviveBtn.RefreshSidebarTooltip = function(self)
        BeginSidebarTooltip(self)
        GameTooltip:SetSpellByID(REVIVE_SPELL_ID)
        FinishSidebarTooltip(self)
    end
    reviveBtn:SetScript("OnEnter", reviveBtn.RefreshSidebarTooltip)
    f.reviveBtn = reviveBtn

    f.foodBtns = {}
    for idx, foodDef in ipairs(PET_EXP_FOOD_ITEMS) do
        local foodBtn = CreateSecureSidebarIconBtn("WishPetTacticsPetFoodBtn" .. idx, foodDef.defaultIcon, true)
        foodBtn:SetAttribute("type", "item")
        foodBtn:SetAttribute("item", "item:" .. foodDef.itemID)
        foodBtn.RefreshSidebarTooltip = function(self)
            BeginSidebarTooltip(self)
            GameTooltip:SetItemByID(foodDef.itemID)
            local cnt = bagCache.foods[idx] or GetBagItemCount(foodDef.itemID)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(ns:TF("|cff10b981背包剩余：%d 个（点击对当前召唤宠物使用经验食物）|r", cnt), 1, 1, 1, true)
            FinishSidebarTooltip(self)
        end
        foodBtn:SetScript("OnEnter", foodBtn.RefreshSidebarTooltip)
        foodBtn:Hide()
        f.foodBtns[idx] = foodBtn
    end

    f.collectionTabs = {}

    if self.InitScriptPanel then
        self:InitScriptPanel(f)
    end

    self:InitHomeView(f, header)
    if self.InitMinimalMode then self:InitMinimalMode(f, header) end

    function ns:RefreshMiddleCards()
        if ns.RefreshLoadoutCabin then
            ns:RefreshLoadoutCabin()
        end
    end

    ns.MainFrame = f
    self:SwitchMainViewMode("HOME")
    return f
end

function ns:RefreshAllUI(petHealthOnly)
    if ns.MainFrame and ns.MainFrame:IsVisible() then
        self:RefreshMainFrameUI()
    end
    if ns.PetPickerModal and ns.PetPickerModal:IsVisible() and ns.PetPickerModal.Refresh then
        ns.PetPickerModal:Refresh(petHealthOnly)
    end
    if ns.TeamMatrixModal and ns.TeamMatrixModal:IsVisible() and ns.TeamMatrixModal.Refresh then
        ns.TeamMatrixModal:Refresh()
    end
    if ns.RoutingModal and ns.RoutingModal:IsVisible() and ns.RoutingModal.Refresh then
        ns.RoutingModal:Refresh()
    end
    if ns.TeamBuilderModal and ns.TeamBuilderModal:IsVisible() and ns.TeamBuilderModal.RefreshBuilder then
        ns.TeamBuilderModal:RefreshBuilder()
    end
end

function ns:RefreshMainFrameUI()
    self:UpdateHeaderToolButtons()
    self:RefreshHomeView()

    local team = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
    if team and ns.ScriptEditBox and ns.ScriptEditBox:IsVisible() and ns.SyncScriptEditor then
        ns:SyncScriptEditor(team)
    end
end

function ns:SyncMainFrameBattleParent()
    local f = self.MainFrame
    if not f or InCombatLockdown() then return end
    local wantParent = (self.GetActiveUIParent and self:GetActiveUIParent()) or UIParent
    if f:GetParent() ~= wantParent then
        f:SetParent(wantParent)
        f:SetFrameStrata("HIGH")
        if wantParent ~= UIParent and self.MatchMainUIScale then
            self:MatchMainUIScale(f)
        else
            f:SetScale(self:GetMainUIScale())
        end
        if self.RestoreMainFramePosition then
            self.RestoreMainFramePosition(f)
        end
    end
end

function ns:ShowMainFrame(viewMode)
    local f = self:CreateMainFrame()
    self:SyncMainFrameBattleParent()
    f:Show()
    self:SwitchMainViewMode(viewMode or "HOME")
end

function ns:RequestMainFrameClose()
    local f = self.MainFrame
    if f then self:RequestHomeAction(function() f:Hide() end) end
end

function ns:ToggleMainFrame()
    local f = self:CreateMainFrame()
    self:SyncMainFrameBattleParent()
    if f:IsShown() and f:IsVisible() then
        self:RequestMainFrameClose()
    else
        f:Show()
        self:SwitchMainViewMode("HOME")
    end
end


-- ==================== 4. 登录后空闲分帧预热（消除首次打开主界面的卡顿） ====================
-- 首次打开时最重的工作：创建上千个控件 + 全量扫描宠物图鉴 + 首次筛选/计算品种。
-- 登录 3 秒后、非战斗/非宠物对战时，分 3 帧依次预热，打开时直接复用缓存。
local prewarmFrame = CreateFrame("Frame")
prewarmFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
prewarmFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    local function CanPrewarm()
        return ns.db and not InCombatLockdown()
            and not (C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle())
    end
    local function Step3()
        if not CanPrewarm() then return end
        if ns.SearchFilter and ns.SearchFilter.GetFilteredPets then
            ns.SearchFilter:GetFilteredPets()
        end
    end
    local function Step2()
        if not CanPrewarm() then return end
        if not ns.MainFrame then ns:CreateMainFrame(true) end
        C_Timer.After(0.5, Step3)
    end
    local function Step1()
        if not CanPrewarm() then
            C_Timer.After(5, Step1)
            return
        end
        if ns.GetPetJournalCache then ns:GetPetJournalCache() end
        C_Timer.After(0.5, Step2)
    end
    C_Timer.After(3, Step1)
end)
