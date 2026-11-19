local ADDON_NAME, ns = ...
local Theme = ns.Theme

local tooltipWatcher = CreateFrame("Frame")
local watcherActive = false

local function IsWishPetTacticsFrame(frame)
    local cur = frame
    while cur do
        if cur == ns.MainFrame or cur == ns.BattleHUD or cur == ns.PetCardModal or cur == ns.PetPickerModal then
            return true
        end
        local name = cur.GetName and cur:GetName() or ""
        if name ~= "" and string.find(name, "^WishPetTactics") then
            return true
        end
        cur = cur.GetParent and cur:GetParent() or nil
    end
    return false
end

local function IsDescendantOf(frame, targetParent)
    if not frame or not targetParent then return false end
    local cur = frame
    while cur do
        if cur == targetParent then
            return true
        end
        cur = cur.GetParent and cur:GetParent() or nil
    end
    return false
end

local function SyncTooltipWatcherState()
    local needWatch = (ns.PetCardModal and ns.PetCardModal:IsShown())
        or (ns.CustomAbilityTooltip and ns.CustomAbilityTooltip:IsShown())
    if needWatch and not watcherActive then
        watcherActive = true
        tooltipWatcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
    elseif not needWatch and watcherActive then
        watcherActive = false
        tooltipWatcher:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    end
end

local petCardHideToken = 0
local petCardHoverToken = 0
local function PetCardHover3DEnabled()
    return not (ns.db and ns.db.settings and ns.db.settings.petCardHover3D == false)
end

local function CancelPetCardHide()
    petCardHideToken = petCardHideToken + 1
end

local function SchedulePetCardHide()
    CancelPetCardHide()
    local token = petCardHideToken
    C_Timer.After(0.12, function()
        if token ~= petCardHideToken then return end
        local card = ns.PetCardModal
        if not card or not card:IsShown() or card.isPinned then return end
        if card:IsMouseOver() then return end
        ns:HideAbilityTooltip()
        card:Hide()
    end)
end

tooltipWatcher:RegisterEvent("MODIFIER_STATE_CHANGED")
tooltipWatcher:SetScript("OnEvent", function(_, event, arg1)
    if event == "MODIFIER_STATE_CHANGED" then
        if arg1 == "LSHIFT" or arg1 == "RSHIFT" or arg1 == "SHIFT" then
            if IsShiftKeyDown() then
                if ns.hoveredPetFrame and ns.hoveredPetData and ns.hoveredPetFrame:IsVisible() and ns.hoveredPetFrame:IsMouseOver() then
                    if not (ns.PetCardModal and ns.PetCardModal:IsShown() and ns.PetCardModal.isPinned) then
                        ns:RenderPetCard(ns.hoveredPetFrame, ns.hoveredPetData, true)
                    end
                end
            else
                if ns.PetCardModal and ns.PetCardModal:IsShown() then
                    local card = ns.PetCardModal
                    card.isPinned = false
                    if PetCardHover3DEnabled()
                        and (card:IsMouseOver() or (ns.hoveredPetFrame and ns.hoveredPetFrame:IsMouseOver())) then
                        if card.closeBtn then card.closeBtn:Show() end
                    elseif PetCardHover3DEnabled() then
                        SchedulePetCardHide()
                    else
                        ns:HideAbilityTooltip()
                        card:Hide()
                    end
                end
                SyncTooltipWatcherState()
            end
        end
    elseif event == "GLOBAL_MOUSE_DOWN" and arg1 == "RightButton" then
        ns:HideAllTooltips()
        if ns.PetCardModal and ns.PetCardModal:IsShown() then
            ns.PetCardModal.isPinned = false
            ns.PetCardModal:Hide()
        end
        SyncTooltipWatcherState()
    end
end)

-- ==================== 1. 全局悬浮窗、模态层级置顶与点击拦截统一管理 ====================
ns._topModalLevel = 120
ns.modalFrames = ns.modalFrames or {}

function ns:BringModalToFront(frame)
    if not frame then return end
    local maxShownLevel = ns._topModalLevel or 120
    for i = 1, #ns.modalFrames do
        local mf = ns.modalFrames[i]
        if mf and mf ~= frame and mf:IsShown() and mf:GetFrameStrata() == "FULLSCREEN_DIALOG" then
            local lvl = mf:GetFrameLevel() or 0
            if lvl > maxShownLevel then
                maxShownLevel = lvl
            end
        end
    end
    ns._topModalLevel = maxShownLevel + 5
    if ns._topModalLevel > 800 and maxShownLevel <= 120 then
        ns._topModalLevel = 130
    end
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(ns._topModalLevel)
    if frame == ns.ScriptWorkspaceModal and ns.AutoCompletePopup then
        ns.AutoCompletePopup:SetFrameStrata("TOOLTIP")
        ns.AutoCompletePopup:SetFrameLevel(math.max(350, ns._topModalLevel + 50))
    end
end

function ns:HidePetDetailTooltip(forceClose)
    petCardHoverToken = petCardHoverToken + 1
    if ns.hoveredPetFrame and not ns.hoveredPetFrame:IsMouseOver() then
        ns.hoveredPetFrame = nil
        ns.hoveredPetData = nil
    end
    if ns.PetCardModal then
        if not forceClose and IsShiftKeyDown() and ns.PetCardModal.isPinned then
            return
        end
        if not forceClose and PetCardHover3DEnabled() and ns.PetCardModal:IsShown()
            and not ns.PetCardModal.isPinned then
            SchedulePetCardHide()
            return
        end
        CancelPetCardHide()
        ns.PetCardModal.isPinned = false
        ns:HideAbilityTooltip()
        ns.PetCardModal:Hide()
    end
    SyncTooltipWatcherState()
end

function ns:HideAllTooltips()
    petCardHoverToken = petCardHoverToken + 1
    ns.hoveredPetFrame = nil
    ns.hoveredPetData = nil
    if GameTooltip and GameTooltip:IsShown() then
        local owner = GameTooltip:GetOwner()
        if owner and IsWishPetTacticsFrame(owner) then
            GameTooltip:Hide()
        end
    end
    if FloatingPetBattleAbilityTooltip and FloatingPetBattleAbilityTooltip:IsShown() then
        FloatingPetBattleAbilityTooltip:Hide()
    end
    if ns.CustomTextTooltip and ns.CustomTextTooltip:IsShown() then
        ns.CustomTextTooltip:Hide()
    end
    if ns.CustomAbilityTooltip and ns.CustomAbilityTooltip:IsShown() then
        ns.CustomAbilityTooltip:Hide()
    end
    if ns.PetCardModal and ns.PetCardModal:IsShown() and not ns.PetCardModal.isPinned then
        ns.PetCardModal:Hide()
    end
    SyncTooltipWatcherState()
end

function ns:HideTransientMenus()
    self:HideAllTooltips()
    if ns.PopupClickCatcher then ns.PopupClickCatcher:Hide() end
    if ns.DisplaySettingsPanel then ns.DisplaySettingsPanel:Hide() end
    if ns.BuilderAbilityPopup then ns.BuilderAbilityPopup:Hide() end
    if ns.SlotContextMenu then ns.SlotContextMenu:Hide() end
    if ns.SlotAbilityTierPopup then ns.SlotAbilityTierPopup:Hide() end
    if ns.PetFilterMenu then ns.PetFilterMenu:Hide() end
    if ns.PetFilterSubMenu then ns.PetFilterSubMenu:Hide() end
    if ns.QueueFilterDrawer then ns.QueueFilterDrawer:Hide() end
    if ns.GroupSelectMenu then ns.GroupSelectMenu:Hide() end
    if ns.PetContextMenu then ns.PetContextMenu:Hide() end
    if ns.PetMarkerSubMenu then ns.PetMarkerSubMenu:Hide() end
    if ns.ContextMenu then ns.ContextMenu:Hide() end
    if ns.RouteAddTeamMenu then ns.RouteAddTeamMenu:Hide() end
    if ns.RouteTargetContextMenu then ns.RouteTargetContextMenu:Hide() end
    if ns.RouteTeamContextMenu then ns.RouteTeamContextMenu:Hide() end
    if ns.MatrixGroupContextMenu then ns.MatrixGroupContextMenu:Hide() end
end

function ns:HideAllPopups()
    self:HideTransientMenus()
    if ns.QuickInputModal then ns.QuickInputModal:Hide() end
    if ns.ChangeTargetModal then ns.ChangeTargetModal:Hide() end
    if ns.TeamEditModal then ns.TeamEditModal:Hide() end
    if ns.PetRenameModal then ns.PetRenameModal:Hide() end
    if ns.PetNoteModal then ns.PetNoteModal:Hide() end
    if ns.ManualAddTargetModal then ns.ManualAddTargetModal:Hide() end
    if ns.ImportTargetConfirmModal then ns.ImportTargetConfirmModal:Hide() end
    if ns.ImportModal then ns.ImportModal:Hide() end
    if ns.ExportChoiceModal then ns.ExportChoiceModal:Hide() end
    if ns.ExportModal then ns.ExportModal:Hide() end
    if ns.MissingPetsModal then ns.MissingPetsModal:Hide() end
    if ns.ScriptWorkspaceModal and not (C_PetBattles and C_PetBattles.IsInBattle()) then
        ns.ScriptWorkspaceModal:Hide()
    end
end

function ns:RefreshModalBlocker()
    local f = ns.MainFrame
    local isMinimal = (f and f.mainUIStyle == "MINIMAL")
        or (ns.db and ns.db.settings and ns.db.settings.mainUIStyle == "MINIMAL")
    if not f or not f:IsShown() or isMinimal then
        if ns.ModalBlocker then ns.ModalBlocker:Hide() end
        return
    end
    if not ns.ModalBlocker then
        local b = CreateFrame("Button", "WishPetTacticsModalBlocker", f, "BackdropTemplate")
        b:SetAllPoints(f)
        b:EnableMouse(true)
        b:EnableMouseWheel(true)
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetScript("OnMouseWheel", function() end)
        b:SetScript("OnClick", function() end)
        b:SetScript("OnEnter", function() ns:HideAllTooltips() end)
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        b:SetBackdropColor(0, 0, 0, 0.45)
        b:Hide()
        ns.ModalBlocker = b
    end

    local topModal = nil
    local topLevel = -1
    for i = 1, #ns.modalFrames do
        local mf = ns.modalFrames[i]
        if mf and mf:IsVisible() then
            local score = (mf:GetFrameStrata() == "FULLSCREEN_DIALOG" and 10000 or 0) + (mf:GetFrameLevel() or 0)
            if score >= topLevel then
                topLevel = score
                topModal = mf
            end
        end
    end

    if topModal then
        ns:HideAllTooltips()
        if ns.PetCardModal and ns.PetCardModal:IsShown() then
            ns.PetCardModal.isPinned = false
            ns.PetCardModal:Hide()
        end
        -- Keep the blocker strictly in MainFrame's own strata so it only dims the
        -- background full-view main window and NEVER covers any open modal dialog
        -- (RoutingModal, ScriptWorkspaceModal, ExportModal, ImportModal, etc.).
        ns.ModalBlocker:SetFrameStrata(f:GetFrameStrata() or "DIALOG")
        ns.ModalBlocker:SetFrameLevel(math.max(1, (f:GetFrameLevel() or 20) + 20))
        ns.ModalBlocker:Show()
    else
        ns.ModalBlocker:Hide()
    end
end

local function NoOpHandler() end

local function ModalOnShow(selfFrame)
    if selfFrame == ns.TeamMatrixModal then
        selfFrame:SetFrameStrata("DIALOG")
        selfFrame:SetFrameLevel(60)
    else
        ns:BringModalToFront(selfFrame)
    end
    ns:RefreshModalBlocker()
end

local function ModalOnHide()
    ns:RefreshModalBlocker()
end

function ns:MakeModal(frame)
    if not frame or frame._frontHooked then return end
    frame._frontHooked = true
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", NoOpHandler)
    frame:SetScript("OnMouseDown", NoOpHandler)
    table.insert(ns.modalFrames, frame)

    frame:HookScript("OnShow", ModalOnShow)
    frame:HookScript("OnHide", ModalOnHide)
end

local function ActiveMenuOnHide()
    if ns.PopupClickCatcher then
        ns.PopupClickCatcher:Hide()
    end
end

function ns:EnablePopupClickCatcher(activeMenu)
    if not ns.PopupClickCatcher then
        local catcher = CreateFrame("Button", "WishPetTacticsPopupClickCatcher", UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:EnableMouse(true)
        catcher:RegisterForClicks("AnyUp", "AnyDown")
        catcher:SetScript("OnClick", function(self)
            self:Hide()
            ns:HideAllPopups()
        end)
        catcher:Hide()
        ns.PopupClickCatcher = catcher
    end

    local catcher = ns.PopupClickCatcher
    if activeMenu then
        ns:BringModalToFront(activeMenu)
        local menuStrata = activeMenu:GetFrameStrata() or "FULLSCREEN_DIALOG"
        if menuStrata == "DIALOG" or menuStrata == "HIGH" then
            activeMenu:SetFrameStrata("FULLSCREEN_DIALOG")
            menuStrata = "FULLSCREEN_DIALOG"
        end
        local drawerLvl = (ns.PetPickerModal and ns.PetPickerModal:IsShown() and ns.PetPickerModal:GetFrameLevel()) or 0
        local menuLevel = math.max(180, activeMenu:GetFrameLevel() or 180, drawerLvl + 15)
        ns._topModalLevel = math.max(ns._topModalLevel or 120, menuLevel)
        activeMenu:SetFrameLevel(menuLevel)

        catcher:SetFrameStrata(menuStrata)
        catcher:SetFrameLevel(menuLevel - 1)
        catcher:Show()

        if not activeMenu._wishCatcherHooked then
            activeMenu._wishCatcherHooked = true
            activeMenu:HookScript("OnHide", ActiveMenuOnHide)
        end
    else
        catcher:Hide()
    end
end

-- ==================== 1.8 统一右键弹窗风格的 1px 悬浮文本提示框 ====================
function ns:AnchorActionSidebarTooltip(tip, owner)
    tip:ClearAllPoints()
    local main = self.MainFrame
    local sidebar = main and main.actionSidebar
    if sidebar and sidebar:IsShown() and owner:GetParent() == sidebar then
        -- Anchor beyond the panel border, not merely beyond its inset icon.
        tip:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 6, -(owner._sidebarY or 0))
    elseif sidebar and sidebar:IsShown() and owner == main.actionSidebarToggle then
        local y = (main.header:GetHeight() - owner:GetHeight()) / 2
        tip:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 6, -y)
    else
        tip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 6, 0)
    end
end

function ns:ShowCustomTooltip(owner, anchor, ...)
    if not owner then return end
    local n = select("#", ...)
    if n == 0 then return end

    if not ns.CustomTextTooltip then
        local tip = CreateFrame("Frame", "WishPetTacticsCustomTooltip", UIParent, "BackdropTemplate")
        tip:SetFrameStrata("TOOLTIP")
        tip:SetFrameLevel(480)
        tip:SetClampedToScreen(true)
        tip:EnableMouse(false)
        Theme:ApplyBackdrop(tip, Theme.Colors.bgPopup, Theme.Colors.border, true)
        tip.lines = {}
        tip:Hide()
        ns.CustomTextTooltip = tip
    end

    local tip = ns.CustomTextTooltip
    local activeTop = (self.GetActiveUIParent and self:GetActiveUIParent()) or UIParent
    if tip:GetParent() ~= activeTop then tip:SetParent(activeTop) end
    -- Calling SetParent resets FrameStrata/FrameLevel to the new parent's values,
    -- so always enforce TOOLTIP strata after parenting across UIParent/PetBattleFrame.
    local minLevel = 480
    if owner.GetFrameStrata and owner:GetFrameStrata() == "TOOLTIP" and owner.GetFrameLevel then
        minLevel = math.max(minLevel, (owner:GetFrameLevel() or 0) + 20)
    end
    if tip:GetFrameStrata() ~= "TOOLTIP" then tip:SetFrameStrata("TOOLTIP") end
    if tip:GetFrameLevel() ~= minLevel then tip:SetFrameLevel(minLevel) end
    tip.owner = owner
    if ns.MainFrame then
        local targetScale = ns.MainFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        if tip._lastScale ~= targetScale then
            tip._lastScale = targetScale
            tip:SetScale(targetScale)
        end
    end

    local lineCount = 0
    local maxW = 0
    for i = 1, n do
        local text = select(i, ...)
        if text and text ~= "" and text ~= " " then
            lineCount = lineCount + 1
            local fs = tip.lines[lineCount]
            if not fs then
                fs = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetJustifyH("LEFT")
                Theme:HookLocalizedFontString(fs)
                tip.lines[lineCount] = fs
            end
            fs:ClearAllPoints()
            if lineCount == 1 then
                fs:SetPoint("TOPLEFT", tip, "TOPLEFT", 10, -6)
            else
                fs:SetPoint("TOPLEFT", tip.lines[lineCount - 1], "BOTTOMLEFT", 0, -4)
            end
            -- A reused FontString must not measure against its previous width.
            -- Explicitly size it from the full text before enabling wrapping.
            fs:SetWidth(0)
            fs:SetHeight(0)
            fs:SetWordWrap(false)
            fs:SetText(tostring(text))
            fs:Show()
            local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth() or 0
            if w > maxW then maxW = w end
        end
    end

    for i = lineCount + 1, #tip.lines do
        tip.lines[i]:Hide()
    end

    if lineCount == 0 then
        tip:Hide()
        return
    end

    local contentWidth = math.max(1, math.ceil(maxW) + 2)
    local screenWidth = UIParent:GetWidth() * UIParent:GetEffectiveScale() / tip:GetEffectiveScale()
    if screenWidth > 40 then contentWidth = math.min(contentWidth, screenWidth - 40) end
    local totalH = 12
    for i = 1, lineCount do
        local fs = tip.lines[i]
        fs:SetWidth(contentWidth)
        fs:SetWordWrap(true)
        fs:SetNonSpaceWrap(true)
        fs:SetHeight(0)
        totalH = totalH + math.ceil(fs:GetStringHeight() or 14) + (i > 1 and 4 or 0)
    end
    tip:SetSize(contentWidth + 20, math.max(24, totalH))
    tip:ClearAllPoints()
    if anchor == "ANCHOR_RIGHT" or anchor == "ANCHOR_TOPRIGHT" then
        self:AnchorActionSidebarTooltip(tip, owner)
    elseif anchor == "ANCHOR_LEFT" then
        tip:SetPoint("TOPRIGHT", owner, "TOPLEFT", -6, 0)
    elseif anchor == "ANCHOR_BOTTOM" then
        tip:SetPoint("TOP", owner, "BOTTOM", 0, -4)
    elseif anchor == "ANCHOR_BOTTOMLEFT" then
        tip:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
    elseif anchor == "ANCHOR_BOTTOMRIGHT" then
        tip:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -4)
    else
        tip:SetPoint("BOTTOM", owner, "TOP", 0, 4)
    end
    tip:Show()
end

function ns:HideCustomTooltip(owner)
    local tip = ns.CustomTextTooltip
    if tip and tip:IsShown() and (not owner or tip.owner == owner) then
        tip.owner = nil
        tip:Hide()
    end
end

-- ==================== 2. 宠物 3D 悬浮卡：可选悬停显示或按住 Shift 显示 ====================
function ns:ShowPetDetailTooltip(anchorFrame, pData, pinNow)
    if not anchorFrame or not pData then return end
    ns.hoveredPetFrame = anchorFrame
    ns.hoveredPetData = pData

    if not PetCardHover3DEnabled() and not IsShiftKeyDown() then
        return
    end
    if ns.PetCardModal and ns.PetCardModal:IsShown() and ns.PetCardModal.isPinned then
        return
    end
    CancelPetCardHide()
    petCardHoverToken = petCardHoverToken + 1
    local token = petCardHoverToken
    if pinNow or IsShiftKeyDown() then
        self:RenderPetCard(anchorFrame, pData, true)
        return
    end
    C_Timer.After(0.25, function()
        if token ~= petCardHoverToken or not anchorFrame:IsVisible() or not anchorFrame:IsMouseOver() then return end
        if ns.PetCardModal and ns.PetCardModal:IsShown() and ns.PetCardModal.isPinned then return end
        ns:RenderPetCard(anchorFrame, pData, false)
    end)
end

-- ==================== 3. 1px 磨砂黑玻璃「自定义技能详情悬浮窗」 ====================
local WEAK_AGAINST_MAP = {
    [1]  = 4,  [2]  = 1,  [3]  = 2,  [4]  = 9,  [5]  = 8,
    [6]  = 10, [7]  = 5,  [8]  = 3,  [9]  = 6,  [10] = 7,
}

local abilityParseCache = {}
local abilityParseCacheCount = 0

function ns:ShowAbilityTooltip(anchorBtn, abilityID, maxHealth, power, speed)
    if not abilityID or abilityID <= 0 or not anchorBtn then return end

    if not ns.CustomAbilityTooltip then
        local tip = CreateFrame("Frame", "WishPetTacticsAbilityTooltip", UIParent, "BackdropTemplate")
        tip:SetSize(256, 180)
        tip:SetFrameStrata("TOOLTIP")
        tip:SetFrameLevel(350)
        tip:SetClampedToScreen(true)
        Theme:ApplyBackdrop(tip, Theme.Colors.bgPopup, Theme.Colors.border, true)
        tip:HookScript("OnShow", SyncTooltipWatcherState)
        tip:HookScript("OnHide", SyncTooltipWatcherState)
        tip:Hide()

        local topBar = CreateFrame("Frame", nil, tip, "BackdropTemplate")
        topBar:SetPoint("TOPLEFT", 1, -1)
        topBar:SetPoint("TOPRIGHT", -1, -1)
        topBar:SetHeight(42)
        Theme:ApplyBackdrop(topBar, Theme.Colors.bgCard, Theme.Colors.border)

        tip.abIcon = Theme:CreateCroppedIcon(topBar, 32)
        tip.abIcon:SetPoint("LEFT", 6, 0)
        tip.abIcon:EnableMouse(false)

        tip.typeIcon = topBar:CreateTexture(nil, "ARTWORK")
        tip.typeIcon:SetSize(26, 26)
        tip.typeIcon:SetPoint("RIGHT", -8, 0)
        tip.typeIcon:SetTexCoord(0, 1, 0, 1)

        tip.nameTxt = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tip.nameTxt:SetPoint("TOPLEFT", tip.abIcon, "TOPRIGHT", 8, -2)
        tip.nameTxt:SetPoint("RIGHT", tip.typeIcon, "LEFT", -4, 0)
        tip.nameTxt:SetJustifyH("LEFT")
        tip.nameTxt:SetWordWrap(false)

        tip.metaTxt = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tip.metaTxt:SetPoint("BOTTOMLEFT", tip.abIcon, "BOTTOMRIGHT", 8, 1)
        tip.metaTxt:SetJustifyH("LEFT")
        Theme:HookLocalizedFontString(tip.metaTxt)

        tip.decal = tip:CreateTexture(nil, "BORDER")
        tip.decal:SetSize(84, 84)
        tip.decal:SetPoint("RIGHT", -6, -6)
        tip.decal:SetTexCoord(0, 1, 0, 1)
        tip.decal:SetAlpha(0.14)

        tip.descTxt = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tip.descTxt:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 10, -10)
        tip.descTxt:SetWidth(234)
        tip.descTxt:SetJustifyH("LEFT")
        tip.descTxt:SetSpacing(3)

        local hintBar = CreateFrame("Frame", nil, tip, "BackdropTemplate")
        hintBar:SetPoint("BOTTOMLEFT", 1, 1)
        hintBar:SetPoint("BOTTOMRIGHT", -1, 1)
        hintBar:SetHeight(28)
        Theme:ApplyBackdrop(hintBar, Theme.Colors.bgPanel, Theme.Colors.border)
        tip.hintBar = hintBar

        tip.strongTxt = hintBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tip.strongTxt:SetPoint("TOPLEFT", 10, -7)
        tip.strongTxt:SetWidth(234)
        tip.strongTxt:SetJustifyH("LEFT")
        tip.strongTxt:SetWordWrap(true)
        Theme:HookLocalizedFontString(tip.strongTxt)

        tip.weakTxt = hintBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tip.weakTxt:SetPoint("TOPLEFT", 10, -31)
        tip.weakTxt:SetWidth(234)
        tip.weakTxt:SetJustifyH("LEFT")
        tip.weakTxt:SetWordWrap(true)
        Theme:HookLocalizedFontString(tip.weakTxt)

        ns.CustomAbilityTooltip = tip
        ns.AbilityTooltip = tip
    end

    local tip = ns.CustomAbilityTooltip
    local activeTop = (self.GetActiveUIParent and self:GetActiveUIParent()) or UIParent
    if tip:GetParent() ~= activeTop then
        tip:SetParent(activeTop)
        tip:SetFrameStrata("TOOLTIP")
        tip:SetFrameLevel(350)
    end
    if tip:GetFrameStrata() ~= "TOOLTIP" then tip:SetFrameStrata("TOOLTIP") end
    if tip:GetFrameLevel() ~= 350 then tip:SetFrameLevel(350) end
    if ns.MainFrame then
        local targetScale = ns.MainFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        if tip._lastScale ~= targetScale then
            tip._lastScale = targetScale
            tip:SetScale(targetScale)
        end
    end

    local _, name, icon, maxCooldown, unparsedDesc, numTurns, petType, noHints = C_PetBattles.GetAbilityInfoByID(abilityID)
    if not name then
        name, icon, petType = C_PetJournal.GetPetAbilityInfo(abilityID)
    end
    if not name then return end

    local mHp = maxHealth or 1400
    local pwr = power or 280
    local spd = speed or 280
    local parseKey = abilityID * 1e12 + mHp * 1e6 + pwr * 1e3 + spd

    local parsedDesc, durationText, cooldownText
    local cached = abilityParseCache[parseKey]
    if cached then
        parsedDesc, durationText, cooldownText = cached[1], cached[2], cached[3]
    else
        parsedDesc = unparsedDesc or ""
        if FloatingPetBattleAbility_Show and FloatingPetBattleAbilityTooltip then
            FloatingPetBattleAbility_Show(abilityID, mHp, pwr, spd)
            local blizzTip = FloatingPetBattleAbilityTooltip
            if blizzTip.Description and blizzTip.Description:GetText() then
                parsedDesc = blizzTip.Description:GetText()
            end
            if blizzTip.Duration and blizzTip.Duration:IsVisible() then
                durationText = blizzTip.Duration:GetText()
            end
            if blizzTip.MaxCooldown and blizzTip.MaxCooldown:IsVisible() then
                cooldownText = blizzTip.MaxCooldown:GetText()
            end
            blizzTip:Hide()
        end
        abilityParseCacheCount = abilityParseCacheCount + 1
        if abilityParseCacheCount > 400 then
            wipe(abilityParseCache)
            abilityParseCacheCount = 1
        end
        abilityParseCache[parseKey] = { parsedDesc, durationText, cooldownText }
    end

    local finalIcon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    if tip._lastIcon ~= finalIcon then
        tip._lastIcon = finalIcon
        tip.abIcon.icon:SetTexture(finalIcon)
    end
    tip.nameTxt:SetText("|cfff3f4f6" .. name .. "|r")

    local cdPart
    if cooldownText and cooldownText ~= "" then
        cdPart = "|cfff59e0b" .. cooldownText .. "|r"
    elseif maxCooldown and maxCooldown > 0 then
        cdPart = ns:TF("|cfff59e0b%d回合冷却|r", maxCooldown)
    else
        cdPart = "|cff10b981无冷却|r"
    end

    local durPart = nil
    if durationText and durationText ~= "" then
        durPart = durationText
    elseif numTurns and numTurns > 1 then
        durPart = ns:TF("持续%d轮", numTurns)
    end

    if durPart then
        tip.metaTxt:SetText(string.format("%s  %s  |cff6b7280#%d|r", cdPart, durPart, abilityID))
    else
        tip.metaTxt:SetText(string.format("%s  |cff6b7280#%d|r", cdPart, abilityID))
    end

    local resolvedType = petType or 1
    local typeTexture = Theme:GetPetTypeTexturePath(resolvedType)
    if typeTexture then
        if tip._lastPetType ~= resolvedType then
            tip._lastPetType = resolvedType
            tip.typeIcon:SetTexture(typeTexture, "CLAMP", "CLAMP", "LINEAR")
            tip.decal:SetTexture(typeTexture, "CLAMP", "CLAMP", "LINEAR")
        end
        tip.typeIcon:Show()
        tip.decal:Show()
    else
        tip._lastPetType = nil
        tip.typeIcon:Hide()
        tip.decal:Hide()
    end

    tip.descTxt:SetText(parsedDesc)
    local descHeight = math.max(24, tip.descTxt:GetStringHeight())

    local targetH
    if not noHints and petType and Theme.StrongAgainstMap[petType] then
        local strongTarget = Theme.PetTypes[Theme.StrongAgainstMap[petType]]
        local weakTarget = Theme.PetTypes[WEAK_AGAINST_MAP[petType]]
        local strongIcon = Theme:GetPetTypeTexturePath(Theme.StrongAgainstMap[petType])
        local weakIcon = Theme:GetPetTypeTexturePath(WEAK_AGAINST_MAP[petType])
        tip.strongTxt:SetText(strongTarget and ns:TF("|cff10b981重击(+50%%)：|r|T%s:16:16:0:0|t %s", strongIcon, strongTarget.name) or "")
        tip.weakTxt:SetText(weakTarget and ns:TF("|cffef4444轻击(-33%%)：|r|T%s:16:16:0:0|t %s", weakIcon, weakTarget.name) or "")
        -- Independent rows: a translated type name may wrap without crossing the other row.
        local strongHeight = math.max(18, tip.strongTxt:GetStringHeight())
        local weakHeight = math.max(18, tip.weakTxt:GetStringHeight())
        tip.weakTxt:ClearAllPoints()
        tip.weakTxt:SetPoint("TOPLEFT", tip.hintBar, "TOPLEFT", 10, -(7 + strongHeight + 5))
        local hintHeight = 7 + strongHeight + 5 + weakHeight + 7
        tip.hintBar:SetHeight(hintHeight)
        tip.hintBar:Show()
        targetH = 44 + descHeight + 20 + hintHeight

    else
        tip.hintBar:Hide()
        targetH = 44 + descHeight + 20
    end

    if tip._lastH ~= targetH then
        tip._lastH = targetH
        tip:SetHeight(targetH)
    end

    tip:ClearAllPoints()
    tip:SetPoint("TOPLEFT", anchorBtn, "TOPRIGHT", 6, 0)
    tip:Show()
end

function ns:HideAbilityTooltip()
    if FloatingPetBattleAbilityTooltip and FloatingPetBattleAbilityTooltip:IsShown() then
        FloatingPetBattleAbilityTooltip:Hide()
    end
    if ns.CustomAbilityTooltip and ns.CustomAbilityTooltip:IsShown() then
        ns.CustomAbilityTooltip:Hide()
    end
    SyncTooltipWatcherState()
end

-- ==================== 4. 3D 宠物详情卡 (Pet Card) ====================
function ns:RenderPetCard(anchorFrame, pData, pinNow)
    if not pData then return end

    if not ns.PetCardModal then
        local card = CreateFrame("Frame", "WishPetTacticsPetCardModal", UIParent, "BackdropTemplate")
        card:SetSize(296, 376)
        card:SetFrameStrata("FULLSCREEN_DIALOG")
        card:SetFrameLevel(210)
        card:SetClampedToScreen(true)
        card:SetMovable(true)
        card:RegisterForDrag("LeftButton")
        card:SetScript("OnDragStart", function(self) if self.isPinned then self:StartMoving() end end)
        card:SetScript("OnDragStop", card.StopMovingOrSizing)
        card:HookScript("OnShow", SyncTooltipWatcherState)
        card:HookScript("OnHide", SyncTooltipWatcherState)
        -- MODIFIER_STATE_CHANGED already closes the card on Shift release;
        -- avoid polling every 60ms while the detail card is visible.
        Theme:ApplyBackdrop(card, Theme.Colors.bgPopup, Theme.Colors.border, true)

        local top = CreateFrame("Frame", nil, card, "BackdropTemplate")
        top:SetPoint("TOPLEFT", 1, -1)
        top:SetPoint("TOPRIGHT", -1, -1)
        top:SetHeight(46)
        Theme:ApplyBackdrop(top, Theme.Colors.bgCard, { 0, 0, 0, 0 })

        card.icon = Theme:CreateCroppedIcon(top, 36)
        card.icon:SetPoint("LEFT", 6, 0)
        card.icon:EnableMouse(false)

        local favBadge = card.icon:CreateTexture(nil, "OVERLAY")
        favBadge:SetSize(18, 18)
        favBadge:SetPoint("TOPLEFT", card.icon, "TOPLEFT", -4, 4)
        if favBadge.SetAtlas then
            favBadge:SetAtlas("PetJournal-FavoritesIcon")
        end
        favBadge:Hide()
        card.favBadge = favBadge

        card.nameTxt = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.nameTxt:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 8, -2)
        card.nameTxt:SetJustifyH("LEFT")

        card.subTxt = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.subTxt:SetPoint("BOTTOMLEFT", card.icon, "BOTTOMRIGHT", 8, 2)
        card.subTxt:SetJustifyH("LEFT")
        Theme:HookLocalizedFontString(card.subTxt)

        local closeBtn = Theme:CreateCloseIconButton(top, function()
            CancelPetCardHide()
            card.isPinned = false
            ns.hoveredPetFrame = nil
            ns.hoveredPetData = nil
            ns:HideAbilityTooltip()
            card:Hide()
        end)
        closeBtn:SetPoint("TOPRIGHT", -8, -8)
        card.closeBtn = closeBtn
        card.nameTxt:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
        card.subTxt:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)

        local modelBox = CreateFrame("Frame", nil, card, "BackdropTemplate")
        modelBox:SetSize(156, 146)
        modelBox:SetPoint("TOPLEFT", 8, -54)
        Theme:ApplyBackdrop(modelBox, Theme.Colors.bgInput, Theme.Colors.border)
        card.modelBox = modelBox

        local model = CreateFrame("PlayerModel", nil, modelBox)
        model:SetPoint("TOPLEFT", 2, -2)
        model:SetPoint("BOTTOMRIGHT", -2, 2)
        model:SetRotation(0.35)
        model:HookScript("OnHide", function(self)
            -- Keep _lastDisplayID cached across hide/show to avoid reloading the same 3D mesh
        end)
        card.model = model

        local function StopCardModelRotation(self)
            self:SetScript("OnUpdate", nil)
        end

        local function RotateCardModel(self)
            if not IsMouseButtonDown("LeftButton") then
                StopCardModelRotation(self)
                return
            end
            local cx = GetCursorPosition()
            model:SetFacing(modelBox.startRot + (cx - modelBox.startX) * 0.015)
        end

        modelBox:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" and card.isPinned then
                self.startX = GetCursorPosition()
                self.startRot = model:GetFacing() or 0.35
                self:SetScript("OnUpdate", RotateCardModel)
            end
        end)
        modelBox:SetScript("OnMouseUp", StopCardModelRotation)
        modelBox:SetScript("OnHide", StopCardModelRotation)

        local statBox = CreateFrame("Frame", nil, card, "BackdropTemplate")
        statBox:SetSize(118, 146)
        statBox:SetPoint("TOPLEFT", modelBox, "TOPRIGHT", 6, 0)
        Theme:ApplyBackdrop(statBox, Theme.Colors.bgPanel, Theme.Colors.border)

        card.decal = statBox:CreateTexture(nil, "BORDER")
        card.decal:SetSize(64, 64)
        card.decal:SetPoint("BOTTOMRIGHT", -2, 2)
        card.decal:SetTexCoord(0, 1, 0, 1)
        card.decal:SetAlpha(0.22)

        card.statLines = statBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.statLines:SetPoint("TOPLEFT", 8, -8)
        card.statLines:SetWidth(104)
        card.statLines:SetJustifyH("LEFT")
        card.statLines:SetSpacing(5)
        Theme:HookLocalizedFontString(card.statLines)

        local abHeader = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        abHeader:SetPoint("TOPLEFT", 10, -208)
        Theme:HookLocalizedFontString(abHeader)
        card.abHeader = abHeader

        card.abBtns = {}
        for idx = 1, 6 do
            local b = CreateFrame("Button", nil, card, "BackdropTemplate")
            b:SetSize(90, 28)
            local col = (idx - 1) % 3
            local row = math.floor((idx - 1) / 3)
            b:SetPoint("TOPLEFT", 8 + col * 95, -224 - row * 32)
            Theme:ApplyBackdrop(b, Theme.Colors.bgCard, Theme.Colors.border)

            b.icon = Theme:CreateCroppedIcon(b, 20)
            b.icon:SetPoint("LEFT", 4, 0)
            b.icon:EnableMouse(false)

            b.txt = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.txt:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
            b.txt:SetPoint("RIGHT", -2, 0)
            b.txt:SetJustifyH("LEFT")
            b.txt:SetWordWrap(false)

            b:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(unpack(Theme.Colors.borderBlue))
                if self.abID and self.abID > 0 then
                    ns:ShowAbilityTooltip(self, self.abID, card.maxHealth or 1400, card.power or 280, card.speed or 280)
                end
            end)
            b:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(unpack(Theme.Colors.border))
                ns:HideAbilityTooltip()
            end)
            card.abBtns[idx] = b
        end

        card.sourceBox = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.sourceBox:SetPoint("TOPLEFT", 10, -294)
        card.sourceBox:SetPoint("BOTTOMRIGHT", -10, 8)
        card.sourceBox:SetJustifyH("LEFT")
        card.sourceBox:SetJustifyV("TOP")
        Theme:HookLocalizedFontString(card.sourceBox)

        ns.PetCardModal = card
        card:HookScript("OnEnter", CancelPetCardHide)
        card:HookScript("OnLeave", function()
            if PetCardHover3DEnabled() and not card.isPinned then SchedulePetCardHide() end
        end)
    end

    local card = ns.PetCardModal
    local drawerOpen = (ns.PetPickerModal and ns.PetPickerModal:IsShown()) and true or false
    local drawerLvl = drawerOpen and (ns.PetPickerModal:GetFrameLevel() or 130) or 0
    local targetLvl = math.max(210, (ns._topModalLevel or 120) + 30, drawerLvl + 20)

    card:SetFrameStrata("FULLSCREEN_DIALOG")
    card:SetFrameLevel(targetLvl)

    if ns.MainFrame then
        local targetScale = ns.MainFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        if card._lastScale ~= targetScale then
            card._lastScale = targetScale
            card:SetScale(targetScale)
        end
    end

    card.isPinned = pinNow == true
    card:EnableMouse(true)
    card.modelBox:EnableMouse(true)
    card.closeBtn:Show()
    card.abHeader:SetText(ns:T(card.isPinned
        and "全部 6 个技能池（按住 Shift 锁定，松开关闭）："
        or "全部 6 个技能池（悬停查看克制详情）："))
    for idx = 1, 6 do
        local btn = card.abBtns[idx]
        btn:SetFrameLevel(targetLvl + 10)
        btn:EnableMouse(true)
    end

    card._lastRenderKey = pData.petID or pData.speciesID
    card.currentSpeciesID = pData.speciesID
    card.currentPetID = pData.petID
    card.maxHealth = (pData.maxHealth and pData.maxHealth > 0) and pData.maxHealth or 1400
    card.power = (pData.power and pData.power > 0) and pData.power or 280
    card.speed = (pData.speed and pData.speed > 0) and pData.speed or 280

    local qCol = Theme.QualityColors[pData.rarity] or Theme.QualityColors[2]
    card.icon.icon:SetTexture(pData.icon)
    card.icon:SetBackdropBorderColor(qCol[1], qCol[2], qCol[3], 1)
    if card.favBadge then card.favBadge:SetShown(pData.isFavorite == true) end
    card.nameTxt:SetText(string.sub(qCol[4], 1, 10) .. (pData.name or ns:T("宠物")) .. "|r")

    local pType = Theme.PetTypes[pData.petType]
    card.subTxt:SetText(ns:TF("|cffffd100%d级|r  |cff38bdf8[%s]|r  %s", pData.level or 1, pData.breed or "B/B", pType and pType.name or ""))
    if pType then
        card.decal:SetTexture(pType.icon)
        card.decal:Show()
    else
        card.decal:Hide()
    end

    local displayID = pData.displayID
    if (not displayID or displayID == 0) and pData.petID then
        displayID = select(6, C_PetJournal.GetPetInfoByPetID(pData.petID))
        pData.displayID = displayID
    end
    if (not displayID or displayID == 0) and pData.speciesID then
        displayID = select(12, C_PetJournal.GetPetInfoBySpeciesID(pData.speciesID))
        pData.displayID = displayID
    end

    local anchorTarget = (drawerOpen and IsDescendantOf(anchorFrame, ns.PetPickerModal)) and ns.PetPickerModal or anchorFrame
    local offsetX = (anchorTarget == ns.PetPickerModal) and 6 or 8

    if not card:IsShown() then
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", anchorTarget, "TOPRIGHT", offsetX, 0)
        card:Show()
    elseif card._lastAnchor ~= anchorTarget then
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", anchorTarget, "TOPRIGHT", offsetX, 0)
    end
    card._lastAnchor = anchorTarget

    -- 异步延后 1 帧加载 3D 模型，彻底消除打开悬浮窗时的同步 CASC 资源加载卡顿
    if displayID and displayID > 0 then
        if not card.model:IsShown() then
            card.model:Show()
        end
        card._pendingDisplayID = displayID
        if card.model._lastDisplayID ~= displayID and not card._modelTimerPending then
            card._modelTimerPending = true
            C_Timer.After(0.02, function()
                card._modelTimerPending = false
                local wantID = card._pendingDisplayID
                if card:IsShown() and wantID and card.model:IsShown() and card.model._lastDisplayID ~= wantID then
                    card.model._lastDisplayID = wantID
                    card.model:SetDisplayInfo(wantID)
                end
            end)
        end
    else
        card._pendingDisplayID = nil
        card.model._lastDisplayID = nil
        card.model:Hide()
    end

    if pData.isCollected then
        local hpCol = pData.isDead and "|cffff3030" or "|cff10b981"
        card.statLines:SetText(ns:TF(
            "生命：%s%d/%d|r\n攻击：|cfff3f4f6%d|r\n速度：|cfff3f4f6%d|r\n品质：%s\n属性：|cff38bdf8%s|r\n编号：|cff6b7280#%d|r",
            hpCol, pData.health, pData.maxHealth, pData.power, pData.speed, qCol[4], pData.breed, pData.speciesID or 0
        ))
    else
        card.statLines:SetText(ns:TF("状态：|cffff4040未收集|r\n物种编号：#%d", pData.speciesID or 0))
    end

    local sortedIDs, sortedLevels = ns:GetSortedPetAbilities(pData.speciesID)
    for idx = 1, 6 do
        local btn = card.abBtns[idx]
        local abID = sortedIDs and sortedIDs[idx]
        local lv = sortedLevels and sortedLevels[idx] or idx
        btn.abID = abID
        if abID and abID > 0 then
            local abName, abIcon = C_PetJournal.GetPetAbilityInfo(abID)
            if btn._lastIcon ~= abIcon then
                btn._lastIcon = abIcon
                btn.icon.icon:SetTexture(abIcon)
            end
            btn.txt:SetText(string.format("|cff9ca3af%d|r %s", lv, abName or ns:T("技能")))
            btn:Show()
        else
            btn:Hide()
        end
    end

    local srcText = (pData.note and pData.note ~= "") and ("|cffffd100" .. ns:T("备注：") .. pData.note .. "|r\n" .. (pData.sourceText or "")) or (pData.sourceText or ns:T("暂无来源说明"))
    card.sourceBox:SetText(srcText)
end

function ns:TogglePetCard(anchorFrame, pData)
    if not pData then return end
    if ns.PetCardModal and ns.PetCardModal:IsShown() and ns.PetCardModal.isPinned and ns.PetCardModal.currentSpeciesID == pData.speciesID and ns.PetCardModal.currentPetID == pData.petID then
        ns.PetCardModal.isPinned = false
        ns.PetCardModal:Hide()
        return
    end
    self:RenderPetCard(anchorFrame, pData, true)
end
function ns:SetupTooltipHook()
    if self._gtSkinHooked or not GameTooltip then return end
    self._gtSkinHooked = true

    local function RestoreGameTooltip(tip)
        if not tip._wishSkinned then return end
        tip._wishSkinned = nil
        for _, texture in pairs(tip._wishSkinTextures) do texture:Hide() end
        if tip.NineSlice then tip.NineSlice:SetAlpha(tip._wishNativeNineSliceAlpha or 1) end
        tip:SetScale(tip._wishNativeScale or 1)
        tip._wishNativeScale, tip._wishNativeNineSliceAlpha = nil, nil
    end

    local function SkinGameTooltipIfOwned(tip)
        local owner = tip:GetOwner()
        if not owner or not IsWishPetTacticsFrame(owner) then
            RestoreGameTooltip(tip)
            return
        end
        if not tip._wishSkinned then
            tip._wishNativeScale = tip:GetScale()
            tip._wishNativeNineSliceAlpha = tip.NineSlice and tip.NineSlice:GetAlpha()
        end
        tip._wishSkinned = true
        if tip:GetFrameStrata() ~= "TOOLTIP" and not InCombatLockdown() then
            tip:SetFrameStrata("TOOLTIP")
        end
        if ns.MainFrame then
            local s = ns.MainFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
            if tip:GetScale() ~= s then tip:SetScale(s) end
        end
        if not tip._wishSkinTextures then
            -- Text belongs to GameTooltip itself. A full-size child frame can
            -- cover it, even when that child's texture uses BACKGROUND.
            local textures = {}
            for _, key in ipairs({"bg", "top", "bottom", "left", "right"}) do
                local texture = tip:CreateTexture(nil, key == "bg" and "BACKGROUND" or "BORDER", nil, -7)
                texture:SetColorTexture(unpack(key == "bg" and Theme.Colors.bgPopup or Theme.Colors.border))
                Theme:SnapTextureToPixel(texture)
                textures[key] = texture
            end
            textures.bg:SetAllPoints(tip)
            textures.top:SetPoint("TOPLEFT", tip, "TOPLEFT", 0, 0)
            textures.top:SetPoint("TOPRIGHT", tip, "TOPRIGHT", 0, 0)
            textures.bottom:SetPoint("BOTTOMLEFT", tip, "BOTTOMLEFT", 0, 0)
            textures.bottom:SetPoint("BOTTOMRIGHT", tip, "BOTTOMRIGHT", 0, 0)
            textures.left:SetPoint("TOPLEFT", tip, "TOPLEFT", 0, 0)
            textures.left:SetPoint("BOTTOMLEFT", tip, "BOTTOMLEFT", 0, 0)
            textures.right:SetPoint("TOPRIGHT", tip, "TOPRIGHT", 0, 0)
            textures.right:SetPoint("BOTTOMRIGHT", tip, "BOTTOMRIGHT", 0, 0)
            tip._wishSkinTextures = textures
        end
        local textures, px = tip._wishSkinTextures, Theme:GetPixelScale(tip)
        textures.top:SetHeight(px)
        textures.bottom:SetHeight(px)
        textures.left:SetWidth(px)
        textures.right:SetWidth(px)
        textures.bg:SetAlpha((ns.db and ns.db.settings and ns.db.settings.bgAlpha) or 1)
        for _, texture in pairs(textures) do texture:Show() end
        if tip.NineSlice then tip.NineSlice:SetAlpha(0) end
        -- Keep native font metrics so item/spell descriptions retain their
        -- calculated width and height, including asynchronously loaded lines.
    end

    GameTooltip:HookScript("OnShow", SkinGameTooltipIfOwned)
    hooksecurefunc(GameTooltip, "SetOwner", SkinGameTooltipIfOwned)
    GameTooltip:HookScript("OnHide", RestoreGameTooltip)
end
