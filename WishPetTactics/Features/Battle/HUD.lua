local ADDON_NAME, ns = ...
local Theme = ns.Theme

local HUD_FULL_WIDTH = 780
-- Keep room for the in-HUD scale rail beside the 720px battle content.
local HUD_SINGLE_ENEMY_WIDTH = 672

ns.usedAllyAbilitySlot = nil

local COOLDOWN_BORDER_COLOR = { 0.90, 0.22, 0.22, 1 }
local SELECTED_BORDER_COLOR = { 0.00, 0.95, 1.00, 1 }

local KNOWN_GLOBAL_BARS = {
    "ElvUIPetBattleActionBar",
    "ElvUIPetBattleActionBarHolder",
    "NDui_PetBattleBar",
    "NDuiPetBattleActionBar",
    "DominosPetBattleBar",
    "BT4BarPetBattle",
    "AltzUI_PetBattleActionBar",
}

local function RecordPendingChargeAbility(abIdx)
    if not abIdx or abIdx < 1 or abIdx > 3 then return end
    if not C_PetBattles or not C_PetBattles.IsInBattle() then return end
    local ally = Enum and Enum.BattlePetOwner and Enum.BattlePetOwner.Ally or 1
    local activeSlot = C_PetBattles.GetActivePet(ally) or 1
    local abilityID, _, _, _, description, numTurns = C_PetBattles.GetAbilityInfo(ally, activeSlot, abIdx)
    if (not description or description == "") and abilityID and C_PetBattles.GetAbilityInfoByID then
        local _, _, _, _, fallbackDescription = C_PetBattles.GetAbilityInfoByID(abilityID)
        description = fallbackDescription
    end
    -- numTurns is the ability's duration, not proof that it charges before
    -- releasing. Only label real charge abilities whose localized description
    -- explicitly describes charging/preparing first.
    local isCharge = false
    if numTurns and numTurns > 1 and type(description) == "string" then
        local lowerDescription = strlower(description)
        isCharge = string.find(lowerDescription, "charge", 1, true) ~= nil
            or string.find(lowerDescription, "charging", 1, true) ~= nil
            or string.find(description, "蓄力", 1, true) ~= nil
            or string.find(description, "蓄能", 1, true) ~= nil
            or string.find(description, "准备", 1, true) ~= nil
    end
    if isCharge then
        ns.pendingChargeSlot = abIdx
        ns.pendingChargePetSlot = activeSlot
        ns.pendingChargeTurns = numTurns - 1
    else
        ns.pendingChargeSlot = nil
        ns.pendingChargePetSlot = nil
        ns.pendingChargeTurns = 0
    end
end

-- 监听我方施放技能动作：记录本回合使用的技能槽位 (1 / 2 / 3)
if C_PetBattles and C_PetBattles.UseAbility and not ns._useAbilityHooked then
    ns._useAbilityHooked = true
    hooksecurefunc(C_PetBattles, "UseAbility", function(abIdx)
        if abIdx and abIdx >= 1 and abIdx <= 3 then
            ns.usedAllyAbilitySlot = abIdx
            RecordPendingChargeAbility(abIdx)
            if ns.UpdateBattleHUD then
                ns:UpdateBattleHUD()
            end
        end
    end)
end

-- ==================== 0. 技能重击(+50%) / 轻击(-33%) 克制计算与角标渲染器 ====================
local function GetAttackModifierState(attackPetType, targetPetType, noHints)
    if noHints or not attackPetType or not targetPetType or attackPetType <= 0 or targetPetType <= 0 then
        return nil
    end

    if C_PetBattles and C_PetBattles.GetAttackModifier then
        local mult = C_PetBattles.GetAttackModifier(attackPetType, targetPetType)
        if mult then
            if mult > 1.05 then
                return "STRONG"
            elseif mult < 0.95 then
                return "WEAK"
            else
                return nil
            end
        end
    end

    if Theme.StrongAgainstMap and Theme.StrongAgainstMap[attackPetType] == targetPetType then
        return "STRONG"
    elseif Theme.ToughAgainstMap and Theme.ToughAgainstMap[targetPetType] == attackPetType then
        return "WEAK"
    end
    return nil
end

local function UpdateAbilityModifierBadge(btn, modState)
    if not btn or not btn.modBadge then return end
    if btn.modBadge._lastState == modState then return end
    btn.modBadge._lastState = modState

    if modState == "STRONG" then
        btn.modBadge.icon:SetTexture("Interface\\PetBattles\\BattleBar-AbilityBadge-Strong")
        btn.modBadge.icon:SetTexCoord(0, 1, 0, 1)
        btn.modBadge:Show()
    elseif modState == "WEAK" then
        btn.modBadge.icon:SetTexture("Interface\\PetBattles\\BattleBar-AbilityBadge-Weak")
        btn.modBadge.icon:SetTexCoord(0, 1, 0, 1)
        btn.modBadge:Show()
    else
        btn.modBadge:Hide()
    end
end

-- ==================== 1. 战斗脚本快捷键格式化与录制工具 ====================
local cachedRawHotKey = nil
local cachedHotKeyDisp = nil

function ns:GetBattleHotKey()
    if ns.db and ns.db.settings and ns.db.settings.battleHotKey and ns.db.settings.battleHotKey ~= "" then
        return ns.db.settings.battleHotKey
    end
    return "SPACE"
end

function ns:FormatHotKeyDisplay(keyStr)
    keyStr = keyStr or self:GetBattleHotKey()
    if keyStr == cachedRawHotKey and cachedHotKeyDisp then
        return cachedHotKeyDisp
    end
    local disp = keyStr
    disp = string.gsub(disp, "MOUSEWHEELUP", ns:T("滚轮向上"))
    disp = string.gsub(disp, "MOUSEWHEELDOWN", ns:T("滚轮向下"))
    disp = string.gsub(disp, "BUTTON3", ns:T("鼠标中键"))
    disp = string.gsub(disp, "BUTTON4", ns:T("鼠标侧键4"))
    disp = string.gsub(disp, "BUTTON5", ns:T("鼠标侧键5"))
    disp = string.gsub(disp, "SPACE", ns:T("空格键"))
    cachedRawHotKey = keyStr
    cachedHotKeyDisp = disp
    return disp
end

function ns:ApplyBattleHotKeyBinding()
    if InCombatLockdown() then return end
    if not ns.BattleHUD or not ns.BattleHUD.driverBtn then return end
    ClearOverrideBindings(ns.BattleHUD.driverBtn)
    if (ns.BattleHUD:IsShown() or ns._battleNativeMode)
        and not (ns.ScriptEditBox and ns.ScriptEditBox:HasFocus()) then
        local hk = self:GetBattleHotKey()
        if hk and hk ~= "" then
            SetOverrideBindingClick(ns.BattleHUD.driverBtn, true, hk, "WishPetTacticsBattleDriverBtn")
        end
        if GetBindingKey then
            local sKeys = { GetBindingKey("WISHPETTACTICS_TOGGLE_UI_STYLE") }
            for _, styleKey in ipairs(sKeys) do
                if styleKey and styleKey ~= "" and styleKey ~= hk then
                    if ns.BattleHUD.styleToggleBtn and SetOverrideBindingClick then
                        SetOverrideBindingClick(ns.BattleHUD.driverBtn, true, styleKey, "WishPetTacticsBattleStyleToggleBtn")
                    elseif SetOverrideBinding then
                        SetOverrideBinding(ns.BattleHUD.driverBtn, true, styleKey, "WISHPETTACTICS_TOGGLE_UI_STYLE")
                    end
                end
            end
            local tKeys = { GetBindingKey("WISHPETTACTICS_TOGGLE_TARGETS") }
            for _, targetKey in ipairs(tKeys) do
                if targetKey and targetKey ~= "" and targetKey ~= hk then
                    if ns.BattleHUD.targetToggleBtn and SetOverrideBindingClick then
                        SetOverrideBindingClick(ns.BattleHUD.driverBtn, true, targetKey, "WishPetTacticsBattleTargetToggleBtn")
                    elseif SetOverrideBinding then
                        SetOverrideBinding(ns.BattleHUD.driverBtn, true, targetKey, "WISHPETTACTICS_TOGGLE_TARGETS")
                    end
                end
            end
        end
    end
    local hkDisp = self:FormatHotKeyDisplay()
    if ns.BattleHUD and ns.BattleHUD.stepBtn and ns.BattleHUD._lastHkDisp ~= hkDisp then
        ns.BattleHUD._lastHkDisp = hkDisp
        ns.BattleHUD.stepBtn.text:SetText(ns:TF("执行脚本动作 [%s]", hkDisp))
    end
    if ns.RoutingModal and ns.RoutingModal.hotkeyBtn then
        ns.RoutingModal.hotkeyBtn.text:SetText(ns:TF("战斗键：|cff38bdf8%s|r", hkDisp))
    end
end

local TARGET_WINDOW_BINDING = "WISHPETTACTICS_TOGGLE_TARGETS"

function ns:GetTargetWindowKeyText()
    local key = GetBindingKey(TARGET_WINDOW_BINDING)
    return key and self:FormatHotKeyDisplay(key) or self:T("未绑定")
end

local function SaveTargetWindowKey(key)
    if InCombatLockdown() then
        return false, ns:T("战斗中无法修改窗口快捷键。")
    end
    local previousKeys = {GetBindingKey(TARGET_WINDOW_BINDING)}
    if key then
        local action = GetBindingAction(key, true)
        if action and action ~= "" and action ~= TARGET_WINDOW_BINDING then
            return false, ns:T("该按键已被占用，请选择其他按键。")
        end
        if not SetBinding(key, TARGET_WINDOW_BINDING) then
            return false, ns:T("无法修改窗口快捷键。")
        end
    end

    for _, previousKey in ipairs(previousKeys) do
        if previousKey ~= key and not SetBinding(previousKey) then
            if key then SetBinding(key, nil) end
            for _, originalKey in ipairs(previousKeys) do
                SetBinding(originalKey, TARGET_WINDOW_BINDING)
            end
            return false, ns:T("无法修改窗口快捷键。")
        end
    end
    SaveBindings(GetCurrentBindingSet())
    return true
end

function ns:StartKeybindCapture(targetWindow)
    if targetWindow and InCombatLockdown() then
        self:PrintError(self:T("战斗中无法修改窗口快捷键。"))
        return
    end
    if not ns.KeybindCapFrame then
        local cap = CreateFrame("Button", "WishPetTacticsKeybindCapFrame", UIParent, "BackdropTemplate")
        cap:SetSize(380, 130)
        cap:SetPoint("CENTER")
        cap:SetFrameStrata("FULLSCREEN_DIALOG")
        cap:SetFrameLevel(120)
        cap:EnableMouse(true)
        cap:EnableMouseWheel(true)
        cap:EnableKeyboard(true)
        cap:RegisterForClicks("AnyDown")
        Theme:ApplyBackdrop(cap, Theme.Colors.bgPopup, Theme.Colors.borderBlue, true)

        local title = cap:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -18)
        Theme:HookLocalizedFontString(title)
        cap.title = title

        local sub = cap:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sub:SetPoint("TOP", title, "BOTTOM", 0, -12)
        Theme:HookLocalizedFontString(sub)
        cap.sub = sub
        sub:SetWidth(354)
        sub:SetJustifyH("CENTER")
        sub:SetSpacing(4)

        local curTxt = cap:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        curTxt:SetPoint("BOTTOM", 0, 14)
        Theme:HookLocalizedFontString(curTxt)
        cap.curTxt = curTxt

        local function GetModifierPrefix()
            local mod = ""
            if IsShiftKeyDown() then mod = mod .. "SHIFT-" end
            if IsControlKeyDown() then mod = mod .. "CTRL-" end
            if IsAltKeyDown() then mod = mod .. "ALT-" end
            return mod
        end

        local function SaveCapturedKey(finalKey)
            if cap.targetWindow then
                local ok, message = SaveTargetWindowKey(finalKey)
                if ok then
                    cap:Hide()
                    ns.RoutingModal:RefreshWindowKey()
                elseif message then
                    cap.curTxt:SetText("|cffff6464" .. message .. "|r")
                end
                return
            end
            ns.db.settings.battleHotKey = finalKey
            cachedRawHotKey = nil
            cachedHotKeyDisp = nil
            cap:Hide()
            ns:ApplyBattleHotKeyBinding()
            ns:UpdateBattleHUDNow()
        end

        cap:SetScript("OnKeyDown", function(self, key)
            if self.targetWindow and InCombatLockdown() then
                self:Hide()
                return
            end
            self:SetPropagateKeyboardInput(false)
            if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" or key == "UNKNOWN" then
                return
            end
            if key == "ESCAPE" then
                if self.targetWindow then self:Hide() else SaveCapturedKey("SPACE") end
                return
            end
            if self.targetWindow and key == "DELETE" and GetModifierPrefix() == "" then
                SaveCapturedKey(nil)
                return
            end
            SaveCapturedKey(GetModifierPrefix() .. key)
        end)

        cap:SetScript("OnMouseWheel", function(_, delta)
            local wheelKey = (delta > 0) and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
            SaveCapturedKey(GetModifierPrefix() .. wheelKey)
        end)

        cap:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                self:Hide()
                return
            elseif button == "LeftButton" then
                return
            else
                SaveCapturedKey(GetModifierPrefix() .. strupper(button))
            end
        end)

        ns.KeybindCapFrame = cap
    end

    local cap = ns.KeybindCapFrame
    cap.targetWindow = targetWindow == true
    local keyText
    if targetWindow then
        cap:SetParent(ns.RoutingModal)
        cap.title:SetText(ns:T("请按下目标窗口快捷键"))
        cap.sub:SetText(ns:T("支持组合键、滚轮和鼠标侧键。Esc 取消，Delete 清除。"))
        self:BringModalToFront(cap)
        keyText = self:GetTargetWindowKeyText()
    else
        local inPetBattle = C_PetBattles and C_PetBattles.IsInBattle()
        cap:SetParent(inPetBattle and PetBattleFrame or UIParent)
        cap.title:SetText(ns:T("|cff3b82f6请按下要绑定的自动对战快捷键|r"))
        cap.sub:SetText(ns:T("支持：单键 / Shift·Ctrl·Alt 组合键 / 鼠标滚轮上下 / 鼠标中键与侧键\n|cff9ca3af(按 [ESC] 重置为默认空格键，点击右键取消设置)|r"))
        keyText = self:FormatHotKeyDisplay()
    end
    self:MatchMainUIScale(cap)
    cap.curTxt:SetText(ns:TF("当前已绑定：|cff10b981[%s]|r", keyText))
    cap:Show()
end

-- ==================== 2. 底部动作条精准接管器（绝不误伤顶部头像、种族图标与 Buff/Debuff 光环） ====================
local function IsProtectedBattleFrame(frame)
    if not frame then return true end
    if frame == UIParent or frame == WorldFrame or frame == PetBattleFrame or frame == ns.BattleHUD then
        return true
    end

    local cur = frame
    while cur do
        if cur == ns.BattleHUD or cur == ns.ScriptWorkspaceModal or cur == ns.AutoCompletePopup or cur == ns.KeybindCapFrame then
            return true
        end
        if PetBattleFrame then
            if cur == PetBattleFrame.ActiveAlly
                or cur == PetBattleFrame.ActiveEnemy
                or cur == PetBattleFrame.Ally2
                or cur == PetBattleFrame.Ally3
                or cur == PetBattleFrame.Enemy2
                or cur == PetBattleFrame.Enemy3
                or cur == PetBattleFrame.WeatherFrame
                or cur == PetBattleFrame.TopArtLeft
                or cur == PetBattleFrame.TopArtRight
                or cur == PetBattleFrame.TopVersus
                or cur == PetBattleFrame.TopVersusText
            then
                return true
            end
        end
        local name = cur.GetName and cur:GetName() or ""
        if name ~= "" then
            if string.find(name, "^WishPetTactics")
                or string.find(name, "Buff")
                or string.find(name, "Aura")
                or string.find(name, "Debuff")
                or string.find(name, "Weather")
                or string.find(name, "Tooltip")
            then
                return true
            end
        end
        cur = cur.GetParent and cur:GetParent() or nil
    end

    return false
end

local suppressedBattleFrames = {}

local function RememberBattleFrame(target)
    if not target or suppressedBattleFrames[target] then return end
    suppressedBattleFrames[target] = {
        alpha = target:GetAlpha(),
        scale = target.GetScale and target:GetScale() or 1,
        shown = target.IsShown and target:IsShown() or false,
        mouse = target.IsMouseEnabled and target:IsMouseEnabled() or false,
    }
end

local function ObliterateFrame(target)
    if not target or IsProtectedBattleFrame(target) then return end
    RememberBattleFrame(target)
    if target.backdrop then RememberBattleFrame(target.backdrop) end
    if target.bg then RememberBattleFrame(target.bg) end

    target:SetAlpha(0)
    if target.SetScale then target:SetScale(0.0001) end
    if target.EnableMouse then target:EnableMouse(false) end

    if target.backdrop then
        target.backdrop:SetAlpha(0)
        target.backdrop:Hide()
    end
    if target.bg then
        target.bg:SetAlpha(0)
        target.bg:Hide()
    end
    if not target._wishSuppressHooked then
        target._wishSuppressHooked = true
        hooksecurefunc(target, "Show", function(self)
            if ns._battleUISuppressed then
                if self:GetAlpha() > 0 then self:SetAlpha(0) end
                if self.SetScale and self:GetScale() > 0.001 then self:SetScale(0.0001) end
                if self.backdrop then self.backdrop:SetAlpha(0); self.backdrop:Hide() end
            end
        end)
        hooksecurefunc(target, "SetAlpha", function(self, alpha)
            if ns._battleUISuppressed and alpha > 0 then
                self:SetAlpha(0)
            end
        end)
    end
end

function ns:RestoreBlizzardBottomFrame()
    ns._battleUISuppressed = false
    for frame, state in pairs(suppressedBattleFrames) do
        if frame then
            if frame.SetScale then frame:SetScale(state.scale or 1) end
            if frame.EnableMouse then frame:EnableMouse(state.mouse) end
            frame:SetAlpha(state.alpha or 1)
            if state.shown then frame:Show() else frame:Hide() end
        end
    end
end

local function RestoreProtectedUnitElements(unitFrame)
    if not unitFrame then return end
    if unitFrame:GetAlpha() == 0 then unitFrame:SetAlpha(1) end
    if unitFrame.SetScale and unitFrame:GetScale() < 0.01 then unitFrame:SetScale(1) end
    if unitFrame.BuffFrame then
        if unitFrame.BuffFrame:GetAlpha() == 0 then unitFrame.BuffFrame:SetAlpha(1) end
        if unitFrame.BuffFrame.SetScale and unitFrame.BuffFrame:GetScale() < 0.01 then unitFrame.BuffFrame:SetScale(1) end
        unitFrame.BuffFrame:Show()
    end
end

function ns:SuppressBlizzardBottomFrame()
    ns._battleUISuppressed = true
    if PetBattleFrame then
        RestoreProtectedUnitElements(PetBattleFrame.ActiveAlly)
        RestoreProtectedUnitElements(PetBattleFrame.ActiveEnemy)
        RestoreProtectedUnitElements(PetBattleFrame.Ally2)
        RestoreProtectedUnitElements(PetBattleFrame.Ally3)
        RestoreProtectedUnitElements(PetBattleFrame.Enemy2)
        RestoreProtectedUnitElements(PetBattleFrame.Enemy3)
    end

    if PetBattleFrame and PetBattleFrame.BottomFrame then
        local bf = PetBattleFrame.BottomFrame
        ObliterateFrame(bf)

        ObliterateFrame(bf.SwitchPetButton)
        ObliterateFrame(bf.CatchButton)
        ObliterateFrame(bf.ForfeitButton)
        ObliterateFrame(bf.TurnTimer)
        ObliterateFrame(bf.FlowFrame)
        ObliterateFrame(bf.Delimiter)
        ObliterateFrame(bf.MicroButtonFrame)
        ObliterateFrame(bf.PetSelectionFrame)
        ObliterateFrame(bf.xpBar)

        if bf.TurnTimer then
            ObliterateFrame(bf.TurnTimer.SkipButton)
            ObliterateFrame(bf.TurnTimer.Bar)
            ObliterateFrame(bf.TurnTimer.ArtFrame)
            ObliterateFrame(bf.TurnTimer.ArtFrame2)
        end
        if bf.abilityButtons then
            for i = 1, #bf.abilityButtons do
                local abBtn = bf.abilityButtons[i]
                ObliterateFrame(abBtn)
                local p = abBtn and abBtn:GetParent()
                if p and p ~= bf and p ~= PetBattleFrame and not IsProtectedBattleFrame(p) then
                    ObliterateFrame(p)
                end
            end
        end
    end

    for i = 1, #KNOWN_GLOBAL_BARS do
        local bar = _G[KNOWN_GLOBAL_BARS[i]]
        if bar then
            ObliterateFrame(bar)
        end
    end

    if _G.ElvUI then
        local E = unpack(_G.ElvUI)
        if E then
            if E.PetBattle and E.PetBattle.Bar then
                ObliterateFrame(E.PetBattle.Bar)
            end
            local PB = E.GetModule and E:GetModule("PetBattles", true)
            if PB then
                if PB.bar then ObliterateFrame(PB.bar) end
                if PB.holder then ObliterateFrame(PB.holder) end
            end
        end
    end

    if not ns._layoutHooked and _G.PetBattleFrame_UpdateActionBarLayout then
        ns._layoutHooked = true
        hooksecurefunc("PetBattleFrame_UpdateActionBarLayout", function()
            if ns._battleUISuppressed and ns.db and ns.db.settings and ns.db.settings.battleHudEnabled ~= false
                and C_PetBattles and C_PetBattles.IsInBattle() then
                ns:SuppressBlizzardBottomFrame()
            end
        end)
    end
end

-- ==================== 3. 战斗主控台 UI 构建与实时渲染 ====================
local function FormatRemainTimeText(sec)
    if not sec or sec <= 0 then return "|cff10b981" .. ns:T("就绪") .. "|r" end
    if sec >= 60 then
        return string.format("|cffffd100%dm%02ds|r", math.floor(sec / 60), math.floor(sec % 60))
    else
        return string.format("|cffffd100%ds|r", math.ceil(sec))
    end
end

local function FormatEtaTime(totalSeconds)
    if not totalSeconds or totalSeconds <= 0 then return "0m" end
    totalSeconds = math.ceil(totalSeconds)
    if totalSeconds < 60 then
        return string.format("%ds", totalSeconds)
    elseif totalSeconds < 3600 then
        local m = math.floor(totalSeconds / 60)
        local s = totalSeconds % 60
        if s > 0 and m < 10 then
            return string.format("%dm%ds", m, s)
        end
        return string.format("%dm", m)
    else
        local h = math.floor(totalSeconds / 3600)
        local m = math.ceil((totalSeconds % 3600) / 60)
        return string.format("%dh%dm", h, m)
    end
end

local function FormatBattleElapsedTime(totalSeconds)
    totalSeconds = math.max(0, math.floor(tonumber(totalSeconds) or 0))
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = totalSeconds % 60
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, seconds)
    end
    return string.format("%02d:%02d", minutes, seconds)
end

local function CreateBattleIconBtn(parent, size, cdFontSize, keybindText, enableModBadge)
    local px = Theme:GetPixelScale()
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(size, size)
    btn:SetFrameLevel(parent:GetFrameLevel() + 2)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    Theme:ApplyBackdrop(btn, Theme.Colors.bgInput, Theme.Colors.border, false)

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", px, -px)
    tex:SetPoint("BOTTOMRIGHT", -px, px)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    tex:Show()
    btn.icon = tex

    local cdMask = btn:CreateTexture(nil, "OVERLAY", nil, 1)
    cdMask:SetAllPoints(tex)
    cdMask:SetTexture("Interface\\Buttons\\WHITE8X8")
    cdMask:SetVertexColor(0, 0, 0, 0.68)
    cdMask:Hide()
    btn.cdMask = cdMask

    local cdTxt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cdTxt:SetPoint("CENTER", 0, 0)
    local fPath = cdTxt:GetFont()
    if fPath then
        cdTxt:SetFont(fPath, cdFontSize or 20, "OUTLINE")
    end
    btn.cdTxt = cdTxt

    if keybindText and keybindText ~= "" then
        local kbTxt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        kbTxt:SetPoint("TOPLEFT", 3, -3)
        if fPath then
            kbTxt:SetFont(fPath, 11, "OUTLINE")
        end
        kbTxt:SetText("|cff9ca3af" .. keybindText .. "|r")
        btn.kbTxt = kbTxt
    end

    if enableModBadge then
        local badge = CreateFrame("Frame", nil, btn)
        badge:SetSize(22, 22)
        badge:SetPoint("TOPRIGHT", 2, 2)
        badge:SetFrameLevel(btn:GetFrameLevel() + 5)

        local bTex = badge:CreateTexture(nil, "OVERLAY", nil, 3)
        bTex:SetAllPoints(badge)
        badge.icon = bTex
        badge:Hide()
        btn.modBadge = badge
    end

    local bottomLbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bottomLbl:SetPoint("BOTTOM", 0, 2)
    if fPath then
        bottomLbl:SetFont(fPath, 10, "OUTLINE")
    end
    Theme:HookLocalizedFontString(bottomLbl)
    btn.bottomLbl = bottomLbl

    return btn
end

local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function IsKnownAbilityIcon(icon)
    if type(icon) == "number" then return icon > 0 and icon ~= 134400 end
    return type(icon) == "string" and icon ~= "" and not icon:lower():find("inv_misc_questionmark", 1, true)
end

local function ResolveHUDAbility(owner, petSlot, abilitySlot, fallbackID)
    local id, _, icon, _, _, _, petType, noHints = C_PetBattles.GetAbilityInfo(owner, petSlot, abilitySlot)
    if not id or id <= 0 then
        id, icon, petType, noHints = fallbackID, nil, nil, nil
    end
    if not id or id <= 0 then return end

    if (not IsKnownAbilityIcon(icon) or not petType or noHints == nil) and C_PetBattles.GetAbilityInfoByID then
        local _, _, byIDIcon, _, _, _, byIDType, byIDNoHints = C_PetBattles.GetAbilityInfoByID(id)
        if not IsKnownAbilityIcon(icon) then icon = byIDIcon end
        petType = petType or byIDType
        if noHints == nil then noHints = byIDNoHints end
    end
    if not IsKnownAbilityIcon(icon) or not petType or noHints == nil then
        local _, journalIcon, journalType, journalNoHints = C_PetJournal.GetPetAbilityInfo(id)
        if not IsKnownAbilityIcon(icon) then icon = journalIcon end
        petType = petType or journalType
        if noHints == nil then noHints = journalNoHints end
    end
    return id, IsKnownAbilityIcon(icon) and icon or QUESTION_ICON, petType, noHints
end

local function UpdateEnemySlotAbilities(cardWidget, pSlot, isDead, targetPetType)
    local enemy = (Enum and Enum.BattlePetOwner and Enum.BattlePetOwner.Enemy) or LE_BATTLE_PET_ENEMY or 2
    for abIdx = 1, 3 do
        local abBtn = cardWidget.abBtns[abIdx]
        local abID, finalIcon, abPetType, noHints = ResolveHUDAbility(enemy, pSlot, abIdx)
        if abID then
            abBtn:Show()
            abBtn.abID = abID

            if abBtn._lastIcon ~= finalIcon then
                abBtn._lastIcon = finalIcon
                abBtn.icon:SetTexture(finalIcon)
            end
            abBtn.icon:Show()

            if abBtn.modBadge then
                if not isDead and targetPetType then
                    local modState = GetAttackModifierState(abPetType, targetPetType, noHints)
                    UpdateAbilityModifierBadge(abBtn, modState)
                else
                    UpdateAbilityModifierBadge(abBtn, nil)
                end
            end

            local _, currentCD, currentLockdown = C_PetBattles.GetAbilityState(enemy, pSlot, abIdx)
            local remainTurns = math.max(tonumber(currentCD) or 0, tonumber(currentLockdown) or 0)

            if isDead then
                abBtn.icon:SetDesaturated(true)
                abBtn.icon:SetVertexColor(0.45, 0.45, 0.45)
                abBtn.cdMask:Show()
                abBtn.cdTxt:SetText("")
                abBtn.onCooldown = false
                if not abBtn:IsMouseOver() then
                    abBtn:SetBackdropBorderColor(unpack(Theme.Colors.border))
                end
            elseif remainTurns > 0 then
                abBtn.icon:SetDesaturated(true)
                abBtn.icon:SetVertexColor(0.55, 0.55, 0.55)
                abBtn.cdMask:Show()
                abBtn.cdTxt:SetText("|cffffd100" .. remainTurns .. "|r")
                abBtn.onCooldown = true
                if not abBtn:IsMouseOver() then
                    abBtn:SetBackdropBorderColor(unpack(COOLDOWN_BORDER_COLOR))
                end
            else
                abBtn.icon:SetDesaturated(false)
                abBtn.icon:SetVertexColor(1, 1, 1)
                abBtn.cdMask:Hide()
                abBtn.cdTxt:SetText("")
                abBtn.onCooldown = false
                if not abBtn:IsMouseOver() then
                    abBtn:SetBackdropBorderColor(unpack(Theme.Colors.border))
                end
            end
        else
            UpdateAbilityModifierBadge(abBtn, nil)
            abBtn:Hide()
            abBtn.abID = nil
        end
    end
end

function ns:AnchorBattleHUDToBottomFrame()
    if not ns.BattleHUD or ns.BattleHUD.userMoved then return end
    ns.BattleHUD:ClearAllPoints()
    ns.BattleHUD:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 18)
end

function ns:SetBattleHUDScale(delta)
    if not ns.db or not ns.db.settings then return end
    local settings = ns.db.settings
    local percent = math.floor((tonumber(settings.battleHudScale) or 1) * 100 + 0.5)
    percent = math.max(65, math.min(140, percent + delta))
    settings.battleHudScale = percent / 100
    local hud = ns.BattleHUD
    if hud then
        hud:SetScale(settings.battleHudScale)
        if hud.scaleValue then hud.scaleValue:SetText(percent .. "%") end
        if hud.scaleSidebar then hud.scaleSidebar:SetScale(settings.battleHudScale) end
    end
end

function ns:CreateBattleHUD()
    if ns.BattleHUD then return ns.BattleHUD end

    local px = Theme:GetPixelScale()
    local hud = CreateFrame("Frame", "WishPetTacticsBattleHUD", PetBattleFrame or UIParent, "BackdropTemplate")
    hud:SetSize(HUD_FULL_WIDTH, 124)
    hud:SetScale((ns.db and ns.db.settings and tonumber(ns.db.settings.battleHudScale)) or 1)
    hud._lastW, hud._lastH = HUD_FULL_WIDTH, 124
    hud:SetFrameStrata("HIGH")
    hud:SetClampedToScreen(true)
    hud:SetMovable(true)
    hud:EnableMouse(true)
    hud:RegisterForDrag("LeftButton")
    hud:SetScript("OnDragStart", function(self)
        self.userMoved = true
        self:StartMoving()
    end)
    hud:SetScript("OnDragStop", hud.StopMovingOrSizing)
    local hudSolidBg = { Theme.Colors.bgPopup[1], Theme.Colors.bgPopup[2], Theme.Colors.bgPopup[3], 1.0 }
    Theme:ApplyBackdrop(hud, hudSolidBg, Theme.Colors.border, false)
    hud:Hide()

    -- 0. 顶部浮动「我方换宠选择条」
    local swapBar = CreateFrame("Frame", nil, hud, "BackdropTemplate")
    swapBar:SetSize(420, 50)
    swapBar:SetPoint("BOTTOM", hud, "TOP", 0, 6)
    Theme:ApplyBackdrop(swapBar, hudSolidBg, Theme.Colors.borderBlue, false)
    swapBar:Hide()
    hud.swapBar = swapBar

    swapBar.petBtns = {}
    for s = 1, 3 do
        local pBtn = CreateFrame("Button", nil, swapBar, "BackdropTemplate")
        pBtn:SetSize(132, 38)
        pBtn:SetPoint("LEFT", 6 + (s - 1) * 138, 0)
        Theme:ApplyBackdrop(pBtn, Theme.Colors.bgCard, Theme.Colors.border, false)

        pBtn.icon = Theme:CreateCroppedIcon(pBtn, 30)
        pBtn.icon:SetPoint("LEFT", 4, 0)
        pBtn.icon:EnableMouse(false)

        pBtn.nameTxt = pBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pBtn.nameTxt:SetPoint("TOPLEFT", pBtn.icon, "TOPRIGHT", 6, -1)
        pBtn.nameTxt:SetPoint("RIGHT", -4, 0)
        pBtn.nameTxt:SetJustifyH("LEFT")
        pBtn.nameTxt:SetWordWrap(false)

        pBtn.hpBar = CreateFrame("StatusBar", nil, pBtn)
        pBtn.hpBar:SetPoint("BOTTOMLEFT", pBtn.icon, "BOTTOMRIGHT", 6, 2)
        pBtn.hpBar:SetPoint("RIGHT", -6, 0)
        pBtn.hpBar:SetHeight(8)
        pBtn.hpBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        pBtn.hpBar:SetStatusBarColor(0.10, 0.80, 0.45, 0.95)
        pBtn.hpBar:SetMinMaxValues(0, 100)
        pBtn.hpBar:SetValue(100)

        pBtn.hpTxt = pBtn.hpBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pBtn.hpTxt:SetPoint("CENTER", 0, 0)
        pBtn.hpTxt:SetScale(0.82)
        Theme:HookLocalizedFontString(pBtn.hpTxt)

        pBtn:SetScript("OnClick", function()
            if C_PetBattles.CanPetSwapIn and C_PetBattles.CanPetSwapIn(s) then
                C_PetBattles.ChangePet(s)
                hud.manualSwapOpen = false
                swapBar:Hide()
                ns:UpdateBattleHUD()
            end
        end)

        swapBar.petBtns[s] = pBtn
    end

    -- 1. 顶栏折叠/拖动区；右侧 controls are kept outside this hit area.
    local toggleBtn = CreateFrame("Button", nil, hud)
    toggleBtn:SetHeight(16)
    toggleBtn:SetPoint("TOPLEFT", hud, "TOPLEFT", 10, -2)
    toggleBtn:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -10, -2)
    toggleBtn:RegisterForDrag("LeftButton")
    toggleBtn:SetScript("OnDragStart", function()
        hud.userMoved = true
        hud:StartMoving()
    end)
    toggleBtn:SetScript("OnDragStop", function() hud:StopMovingOrSizing() end)

    local arrowTex = Theme:CreateArrowTexture(toggleBtn, 14, "UP")
    arrowTex:SetPoint("CENTER", 0, 0)
    arrowTex:SetVertexColor(0.38, 0.75, 1.0, 0.9)
    toggleBtn.arrow = arrowTex

    toggleBtn:SetScript("OnEnter", function()
        arrowTex:SetVertexColor(0.0, 0.95, 1.0, 1.0)
    end)
    toggleBtn:SetScript("OnLeave", function()
        arrowTex:SetVertexColor(0.38, 0.75, 1.0, 0.9)
    end)
    toggleBtn:SetScript("OnClick", function()
        ns.db.settings.hudMonitorExpanded = not ns.db.settings.hudMonitorExpanded
        ns:UpdateBattleHUDNow()
    end)
    hud.toggleBtn = toggleBtn

    -- This independent arrow remains clickable when the addon HUD is hidden.
    local scaleSidebar = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    scaleSidebar:SetSize(26, 26)
    scaleSidebar:SetFrameStrata("HIGH")
    scaleSidebar:SetFrameLevel(hud:GetFrameLevel() + 20)
    scaleSidebar:SetScale(hud:GetScale())
    scaleSidebar:SetClampedToScreen(true)
    scaleSidebar:Hide()
    hud.scaleSidebar = scaleSidebar

    local nativeBtn = Theme:CreateFlatButton(scaleSidebar, 24, 24, "")
    nativeBtn:SetPoint("CENTER", scaleSidebar, "CENTER", 0, 0)
    nativeBtn.icon = nativeBtn:CreateTexture(nil, "ARTWORK")
    nativeBtn.icon:SetSize(18, 18)
    nativeBtn.icon:SetPoint("CENTER", nativeBtn, "CENTER", 0, 0)
    nativeBtn.icon:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Common\\ui_hide.tga")
    nativeBtn:SetScript("OnClick", function()
        if ns._battleNativeMode then
            if ns.db and ns.db.settings then ns.db.settings.battleHudEnabled = true end
            ns:ShowBattleHUD(true)
        else
            if ns.db and ns.db.settings then ns.db.settings.battleHudEnabled = false end
            ns:ShowBattleHUD(false, true)
            ns:ShowCustomTooltip(nativeBtn, "ANCHOR_TOP", ns:T("点击图标显示 HUB"))
            C_Timer.After(1.5, function()
                ns:HideCustomTooltip(nativeBtn)
            end)
            if ns.ShowUIFeedback then ns:ShowUIFeedback(ns:T("已恢复游戏默认宠物对战界面")) end
        end
    end)
    nativeBtn:SetScript("OnEnter", function(self)
        local tip = ns._battleNativeMode and ns:T("显示 HUB") or ns:T("隐藏 HUB")
        ns:ShowCustomTooltip(self, "ANCHOR_LEFT", tip)
    end)
    nativeBtn:SetScript("OnLeave", function(self) ns:HideCustomTooltip(self) end)
    hud.nativeBtn = nativeBtn
    scaleSidebar.nativeBtn = nativeBtn
    function hud:SetVisibilityToggleIcon(hubVisible)
        local file = hubVisible and "ui_hide.tga" or "ui_show.tga"
        self.nativeBtn.icon:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Common\\" .. file)
    end

    -- 2. 可折叠战斗监控面板（仅保留角色升级监控 + 脚本日志/复活CD，最多 2 行）
    local monitorPanel = CreateFrame("Frame", nil, hud)
    monitorPanel:SetPoint("TOPLEFT", hud, "TOPLEFT", 12, -20)
    monitorPanel:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -12, -20)
    monitorPanel:SetHeight(38)
    monitorPanel._lastH = 38
    monitorPanel:Hide()
    hud.monitorPanel = monitorPanel

    hud.infoLines = {}
    for i = 1, 2 do
        local fs = monitorPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 0, -((i - 1) * 18))
        fs:SetPoint("TOPRIGHT", 0, -((i - 1) * 18))
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        Theme:HookLocalizedFontString(fs)
        fs:Hide()
        hud.infoLines[i] = fs
    end

    local sepLine = monitorPanel:CreateTexture(nil, "BORDER")
    sepLine:SetHeight(px)
    sepLine:SetPoint("BOTTOMLEFT", 0, 0)
    sepLine:SetPoint("BOTTOMRIGHT", 0, 0)
    sepLine:SetTexture("Interface\\Buttons\\WHITE8X8")
    sepLine:SetVertexColor(unpack(Theme.Colors.divider))
    monitorPanel.sepLine = sepLine

    -- 3. 中部核心对战区
    local combatRow = CreateFrame("Frame", nil, hud)
    combatRow:SetHeight(66)
    combatRow:SetPoint("BOTTOMLEFT", hud, "BOTTOMLEFT", 10, 36)
    combatRow:SetPoint("BOTTOMRIGHT", hud, "BOTTOMRIGHT", -10, 36)
    hud.combatRow = combatRow

    -- 3A. 左侧：我方当前宠物的 3 个 64x64 技能大图标
    hud.allyAbBtns = {}
    for abIdx = 1, 3 do
        local btn = CreateBattleIconBtn(combatRow, 64, 22, tostring(abIdx), true)
        btn:SetPoint("LEFT", (abIdx - 1) * 68, 0)
        btn:SetScript("OnClick", function()
            if C_PetBattles and C_PetBattles.IsInBattle() then
                ns.usedAllyAbilitySlot = abIdx
                C_PetBattles.UseAbility(abIdx)
            end
        end)
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(unpack(Theme.Colors.borderBlue))
            if self.abID and self.abID > 0 then
                ns:ShowAbilityTooltip(self, self.abID, self.maxHp or 1400, self.power or 280, self.speed or 280)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            ns:HideAbilityTooltip()
            self:SetBackdropBorderColor(unpack(self._normalBorder or Theme.Colors.border))
        end)
        hud.allyAbBtns[abIdx] = btn
    end

    -- 3B. 左侧中部：我方 4 个战术动作按钮（换宠 / 陷阱 / 待命 / 投降）
    local utilDefs = {
        {
            key = "SWAP", label = "换宠", kb = "4",
            icon = "Interface\\Icons\\INV_Pet_Achievement_RaiseAPetLevel_25",
            click = function()
                hud.manualSwapOpen = not hud.manualSwapOpen
                ns:UpdateBattleHUDNow()
            end,
            tip = "切换我方出战宠物",
        },
        {
            key = "TRAP", label = "陷阱", kb = "5",
            icon = "Interface\\Icons\\INV_Pet_PetTrap01",
            click = function()
                if C_PetBattles.IsTrapAvailable and C_PetBattles.IsTrapAvailable() then
                    C_PetBattles.UseTrap()
                end
            end,
            tip = "投掷捕宠陷阱",
        },
        {
            key = "PASS", label = "待命", kb = "6",
            icon = "Interface\\Icons\\Ability_Hibernation",
            click = function()
                if C_PetBattles.IsSkipAvailable and C_PetBattles.IsSkipAvailable() then
                    C_PetBattles.SkipTurn()
                end
            end,
            tip = "本回合原地待命 (跳过回合)",
        },
        {
            key = "FORFEIT", label = "投降", kb = "",
            icon = "Interface\\Icons\\INV_Pet_ExitBattle",
            click = function()
                if C_PetBattles and C_PetBattles.ForfeitGame then
                    C_PetBattles.ForfeitGame()
                end
            end,
            tip = "退出/认输当前宠物对战",
        },
    }

    hud.utilBtns = {}
    for uIdx, def in ipairs(utilDefs) do
        local uBtn = CreateBattleIconBtn(combatRow, 44, 15, def.kb, false)
        uBtn:SetPoint("LEFT", 208 + (uIdx - 1) * 47, 0)
        uBtn.icon:SetTexture(def.icon)
        uBtn.bottomLbl:SetText(def.label)
        uBtn._normalBorder = Theme.Colors.border
        uBtn:SetScript("OnClick", def.click)
        uBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(unpack(Theme.Colors.borderBlue))
            ns:ShowCustomTooltip(self, "ANCHOR_TOP", ns:T(def.tip))
        end)
        uBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(unpack(self._normalBorder or Theme.Colors.border))
            ns:HideCustomTooltip(self)
        end)
        hud.utilBtns[def.key] = uBtn
    end

    local vDiv = combatRow:CreateTexture(nil, "BORDER")
    vDiv:SetWidth(px)
    vDiv:SetPoint("TOPLEFT", combatRow, "TOPLEFT", 402, -2)
    vDiv:SetPoint("BOTTOMLEFT", combatRow, "BOTTOMLEFT", 402, 2)
    vDiv:SetTexture("Interface\\Buttons\\WHITE8X8")
    vDiv:SetVertexColor(unpack(Theme.Colors.divider))

    -- 3C. 右侧：敌方当前激活宠物的 3 个 64x64 大图标
    local activeEnemyCard = CreateFrame("Frame", nil, combatRow)
    activeEnemyCard:SetSize(200, 64)
    activeEnemyCard:SetPoint("LEFT", 412, 0)
    hud.activeEnemyCard = activeEnemyCard

    activeEnemyCard.abBtns = {}
    for abIdx = 1, 3 do
        local abBtn = CreateBattleIconBtn(activeEnemyCard, 64, 22, nil, true)
        abBtn:SetPoint("LEFT", (abIdx - 1) * 68, 0)
        abBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(unpack(Theme.Colors.borderBlue))
            if self.abID and self.abID > 0 then
                ns:ShowAbilityTooltip(self, self.abID, activeEnemyCard.maxHp or 1400, activeEnemyCard.power or 280, activeEnemyCard.speed or 280)
            end
        end)
        abBtn:SetScript("OnLeave", function(self)
            if self.onCooldown then
                self:SetBackdropBorderColor(unpack(COOLDOWN_BORDER_COLOR))
            else
                self:SetBackdropBorderColor(unpack(Theme.Colors.border))
            end
            ns:HideAbilityTooltip()
        end)
        activeEnemyCard.abBtns[abIdx] = abBtn
    end

    -- 右侧上下两排：敌方未激活的 2 号、3 号替补宠物技能 (30x30 图标)
    hud.backEnemyCards = {}
    for bIdx = 1, 2 do
        local bCard = CreateFrame("Frame", nil, combatRow)
        bCard:SetSize(98, 30)
        if bIdx == 1 then
            bCard:SetPoint("TOPLEFT", activeEnemyCard, "TOPRIGHT", 10, 0)
        else
            bCard:SetPoint("BOTTOMLEFT", activeEnemyCard, "BOTTOMRIGHT", 10, 0)
        end

        bCard.abBtns = {}
        for abIdx = 1, 3 do
            local abBtn = CreateBattleIconBtn(bCard, 30, 14, nil, false)
            abBtn:SetPoint("LEFT", (abIdx - 1) * 34, 0)
            abBtn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(unpack(Theme.Colors.borderBlue))
                if self.abID and self.abID > 0 then
                    ns:ShowAbilityTooltip(self, self.abID, bCard.maxHp or 1400, bCard.power or 280, bCard.speed or 280)
                end
            end)
            abBtn:SetScript("OnLeave", function(self)
                if self.onCooldown then
                    self:SetBackdropBorderColor(unpack(COOLDOWN_BORDER_COLOR))
                else
                    self:SetBackdropBorderColor(unpack(Theme.Colors.border))
                end
                ns:HideAbilityTooltip()
            end)
            bCard.abBtns[abIdx] = abBtn
        end

        hud.backEnemyCards[bIdx] = bCard
    end

    -- 4. 底部操作按钮行（执行脚本动作 | 编辑脚本 | 设快捷键）
    local initHk = self:FormatHotKeyDisplay()
    local stepBtn = Theme:CreateActionButton(hud, 508, 22, ns:TF("执行脚本动作 [%s]", initHk), "execute", nil, "PRIMARY")
    stepBtn:SetPoint("BOTTOMLEFT", hud, "BOTTOMLEFT", 10, 6)
    stepBtn:SetScript("OnClick", function()
        ns.ScriptEngine:ExecuteStep()
    end)
    hud.stepBtn = stepBtn
    hud._lastHkDisp = initHk

    local driverBtn = CreateFrame("Button", "WishPetTacticsBattleDriverBtn", UIParent)
    driverBtn:SetSize(1, 1)
    driverBtn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)
    driverBtn:SetFrameStrata("HIGH")
    driverBtn:SetAlpha(0)
    driverBtn:EnableMouse(false)
    driverBtn:Show()
    driverBtn:SetScript("OnClick", function() ns.ScriptEngine:ExecuteStep() end)
    hud.driverBtn = driverBtn

    local styleToggleBtn = CreateFrame("Button", "WishPetTacticsBattleStyleToggleBtn", UIParent)
    styleToggleBtn:SetSize(1, 1)
    styleToggleBtn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)
    styleToggleBtn:SetFrameStrata("HIGH")
    styleToggleBtn:SetAlpha(0)
    styleToggleBtn:EnableMouse(false)
    styleToggleBtn:Show()
    styleToggleBtn:RegisterForClicks("AnyUp", "AnyDown")
    styleToggleBtn:SetScript("OnClick", function(_, _, down)
        if down == true then return end
        if WishPetTactics_ToggleUIStyle then WishPetTactics_ToggleUIStyle() end
    end)
    hud.styleToggleBtn = styleToggleBtn

    local targetToggleBtn = CreateFrame("Button", "WishPetTacticsBattleTargetToggleBtn", UIParent)
    targetToggleBtn:SetSize(1, 1)
    targetToggleBtn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)
    targetToggleBtn:SetFrameStrata("HIGH")
    targetToggleBtn:SetAlpha(0)
    targetToggleBtn:EnableMouse(false)
    targetToggleBtn:Show()
    targetToggleBtn:RegisterForClicks("AnyUp", "AnyDown")
    targetToggleBtn:SetScript("OnClick", function(_, _, down)
        if down == true then return end
        if WishPetTactics_ToggleTargets then WishPetTactics_ToggleTargets() end
    end)
    hud.targetToggleBtn = targetToggleBtn

    local bindBtn = Theme:CreateActionButton(hud, 108, 22, "设快捷键", "hotkey")
    bindBtn:SetPoint("BOTTOMRIGHT", hud, "BOTTOMRIGHT", -10, 6)
    bindBtn:SetScript("OnClick", function()
        ns:StartKeybindCapture()
    end)
    hud.bindBtn = bindBtn
    scaleSidebar:ClearAllPoints()
    scaleSidebar:SetPoint("RIGHT", bindBtn, "LEFT", -4, 0)

    local editScriptBtn = Theme:CreateActionButton(hud, 104, 22, "编辑脚本", "script", nil, "PRIMARY")
    editScriptBtn:SetPoint("RIGHT", scaleSidebar, "LEFT", -4, 0)
    editScriptBtn:SetScript("OnClick", function()
        if ns.ToggleScriptWorkspace then
            ns:ToggleScriptWorkspace()
        end
    end)
    hud.editScriptBtn = editScriptBtn

    -- Keep scale controls directly beside the script action button.
    local scaleControls = CreateFrame("Frame", nil, hud)
    scaleControls:SetSize(78, 22)
    scaleControls:SetPoint("RIGHT", editScriptBtn, "LEFT", -4, 0)
    hud.scaleControls = scaleControls
    local scaleMinus = Theme:CreateFlatButton(scaleControls, 20, 20, "−")
    scaleMinus:SetPoint("LEFT", scaleControls, "LEFT", 0, 0)
    local scaleValue = scaleControls:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleValue:SetPoint("LEFT", scaleMinus, "RIGHT", 0, 0)
    scaleValue:SetSize(38, 20)
    scaleValue:SetJustifyH("CENTER")
    scaleValue:SetText(math.floor(((ns.db and ns.db.settings and tonumber(ns.db.settings.battleHudScale)) or 1) * 100 + 0.5) .. "%")
    hud.scaleValue = scaleValue
    local scalePlus = Theme:CreateFlatButton(scaleControls, 20, 20, "+")
    scalePlus:SetPoint("LEFT", scaleValue, "RIGHT", 0, 0)
    scaleMinus:SetScript("OnClick", function() ns:SetBattleHUDScale(-5) end)
    scalePlus:SetScript("OnClick", function() ns:SetBattleHUDScale(5) end)
    for _, button in ipairs({ scaleMinus, scalePlus }) do
        button:SetScript("OnEnter", function(self)
            ns:ShowCustomTooltip(self, "ANCHOR_TOP", ns:T("调节宠物对战HUD大小"))
        end)
        button:SetScript("OnLeave", function(self) ns:HideCustomTooltip(self) end)
    end

    local function UpdateBottomActionWidth()
        local actionWidth = math.max(80, (hud:GetWidth() - 20 - 78 - 26 - 18) / 3)
        stepBtn:SetWidth(actionWidth)
        editScriptBtn:SetWidth(actionWidth)
        bindBtn:SetWidth(actionWidth)
        stepBtn:ClearAllPoints()
        stepBtn:SetPoint("BOTTOMLEFT", hud, "BOTTOMLEFT", 10, 6)
        stepBtn:SetPoint("RIGHT", scaleControls, "LEFT", -6, 0)
    end
    hud:HookScript("OnSizeChanged", UpdateBottomActionWidth)
    UpdateBottomActionWidth()

    -- Event-driven full refresh; detach OnUpdate completely when monitor is collapsed.
    local monitorElapsed = 0
    local function HUDMonitorOnUpdate(self, elapsed)
        if not self._lastExpanded then
            monitorElapsed = 0
            self:SetScript("OnUpdate", nil)
            return
        end
        monitorElapsed = monitorElapsed + elapsed
        if monitorElapsed >= 0.8 then
            monitorElapsed = 0
            ns:UpdateBattleHUD(true)
        end
    end
    function hud:SyncMonitorTicker(expanded)
        local handler = expanded and HUDMonitorOnUpdate or nil
        if self:GetScript("OnUpdate") ~= handler then
            monitorElapsed = 0
            self:SetScript("OnUpdate", handler)
        end
    end

    ns.BattleHUD = hud
    self:AnchorBattleHUDToBottomFrame()
    return hud
end

function ns:ShowBattleHUD(show, keepSidebar)
    local hud = self:CreateBattleHUD()
    if show then
        if ns.db and ns.db.settings and ns.db.settings.battleHudEnabled == false then
            self:RestoreBlizzardBottomFrame()
            ns._battleNativeMode = true
            hud:Hide()
            hud.scaleSidebar:SetScale(hud:GetScale())
            hud:SetVisibilityToggleIcon(false)
            hud.scaleSidebar:Show()
            self:ApplyBattleHotKeyBinding()
            return
        end
        ns._battleNativeMode = false
        hud.scaleSidebar:SetScale(hud:GetScale())
        hud:SetVisibilityToggleIcon(true)
        hud.scaleSidebar:Show()
        if PetBattleFrame and hud:GetParent() ~= PetBattleFrame then
            hud:SetParent(PetBattleFrame)
            hud:SetFrameStrata("HIGH")
        end
        if ns.MainFrame and ns.MainFrame:IsShown() and self.SyncMainFrameBattleParent then
            self:SyncMainFrameBattleParent()
        end
        ns.usedAllyAbilitySlot = nil
        self:SuppressBlizzardBottomFrame()
        hud.manualSwapOpen = false
        self:AnchorBattleHUDToBottomFrame()
        hud:Show()
        self:ApplyBattleHotKeyBinding()
        self:UpdateBattleHUDNow()
        C_Timer.After(0.1, function()
            if ns._battleUISuppressed and ns.db and ns.db.settings and ns.db.settings.battleHudEnabled ~= false
                and C_PetBattles and C_PetBattles.IsInBattle() then
                ns:SuppressBlizzardBottomFrame()
                ns:ApplyBattleHotKeyBinding()
            end
        end)
        C_Timer.After(0.5, function()
            if ns._battleUISuppressed and ns.db and ns.db.settings and ns.db.settings.battleHudEnabled ~= false
                and C_PetBattles and C_PetBattles.IsInBattle() then
                ns:SuppressBlizzardBottomFrame()
                ns:ApplyBattleHotKeyBinding()
            end
        end)
    else
        self:RestoreBlizzardBottomFrame()
        ns.usedAllyAbilitySlot = nil
        local inBattle = C_PetBattles and C_PetBattles.IsInBattle()
        local showSidebar = keepSidebar == true or (inBattle and ns.db and ns.db.settings
            and ns.db.settings.battleHudEnabled == false)
        ns._battleNativeMode = showSidebar and true or false
        if showSidebar then
            hud.scaleSidebar:SetScale(hud:GetScale())
            hud:SetVisibilityToggleIcon(false)
            hud.scaleSidebar:Show()
        else
            hud.scaleSidebar:Hide()
        end
        if not InCombatLockdown() and not showSidebar then
            ClearOverrideBindings(hud.driverBtn)
        end
        if ns.ScriptWorkspaceModal and ns.ScriptWorkspaceModal:GetParent() == PetBattleFrame then
            if ns.ScriptEditBox then ns.ScriptEditBox:ClearFocus() end
            if ns.AutoCompletePopup then ns.AutoCompletePopup:Hide() end
            ns.ScriptWorkspaceModal:Hide()
            ns.ScriptWorkspaceModal:SetParent(UIParent)
        end
        if self.SyncMainFrameBattleParent then
            self:SyncMainFrameBattleParent()
        end
        for _, modal in ipairs({
            ns.RoutingModal, ns.ImportModal, ns.ExportModal, ns.ExportChoiceModal,
            ns.MissingPetsModal, ns.UIStyleKeyCapture, ns.CustomTextTooltip,
            ns.CustomAbilityTooltip, ns.PetCardModal
        }) do
            if modal and PetBattleFrame and modal:GetParent() == PetBattleFrame and not InCombatLockdown() then
                modal:SetParent(UIParent)
                if modal == ns.CustomTextTooltip then
                    modal:SetFrameStrata("TOOLTIP")
                    modal:SetFrameLevel(480)
                elseif modal == ns.CustomAbilityTooltip then
                    modal:SetFrameStrata("TOOLTIP")
                    modal:SetFrameLevel(350)
                else
                    modal:SetFrameStrata("FULLSCREEN_DIALOG")
                end
            end
        end
        hud.swapBar:Hide()
        hud:Hide()
        if showSidebar then self:ApplyBattleHotKeyBinding() end
    end
end

function ns:ShowEnemySkillHUD() end
function ns:UpdateEnemySkillHUD()
    if ns.UpdateBattleHUD then ns:UpdateBattleHUD() end
end

-- 构建单行角色升级监控（满级人物直接返回 nil 不显示）
function ns:BuildCompactPlayerLine()
    local st = ns.BattleStats
    local curXP = UnitXP("player") or 0
    local rawMaxXP = UnitXPMax("player") or 0
    local maxXP = math.max(1, rawMaxXP)
    local curLv = UnitLevel("player") or 1
    local maxPlayerLv = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 90
    local isMaxLevel = (rawMaxXP <= 0) or (curLv >= maxPlayerLv) or (curXP == 0 and rawMaxXP <= 1)

    if isMaxLevel then
        return nil
    end

    local xpPct = math.floor((curXP / maxXP) * 100)
    local avgDur = (st.lastBattleDuration and st.lastBattleDuration > 0) and st.lastBattleDuration or 45
    local avgXP = st.lastBattlePlayerXP or 0
    if avgXP <= 0 and (st.battlesCount or 0) > 0 and (st.totalPlayerXP or 0) > 0 then
        avgXP = math.floor(st.totalPlayerXP / st.battlesCount)
    end
    local estGain = avgXP > 0 and avgXP or math.max(150, math.floor(maxXP * 0.018))
    local remainXP = math.max(0, maxXP - curXP)
    local fightsNeeded = math.max(1, math.ceil(remainXP / estGain))
    local etaStr = FormatEtaTime(fightsNeeded * avgDur)

    return ns:TF("|cff38bdf8[人物]|r %d级(%d%%) 单场:|cff10b981+%d|r | 升%d级:|cffffd100%d场|r(|cff38bdf8~%s|r)", curLv, xpPct, estGain, curLv + 1, fightsNeeded, etaStr)
end

-- 刷新我方左侧技能图标（零临时表分配）
function ns:RefreshAllyCombatControls(hud)
    if not hud or not C_PetBattles or not C_PetBattles.IsInBattle() then return end

    local ally = (Enum and Enum.BattlePetOwner and Enum.BattlePetOwner.Ally) or LE_BATTLE_PET_ALLY or 1
    local enemy = (Enum and Enum.BattlePetOwner and Enum.BattlePetOwner.Enemy) or LE_BATTLE_PET_ENEMY or 2

    local numAllyPets = C_PetBattles.GetNumPets(ally) or 0
    local activeSlot = C_PetBattles.GetActivePet(ally) or 1
    if activeSlot < 1 or activeSlot > math.max(1, numAllyPets) then
        activeSlot = 1
    end

    local activeEnemySlot = C_PetBattles.GetActivePet(enemy) or 1
    local enemyPetType = C_PetBattles.GetPetType(enemy, activeEnemySlot)

    local activeHP = C_PetBattles.GetHealth(ally, activeSlot) or 0
    local maxHp = math.max(1, C_PetBattles.GetMaxHealth(ally, activeSlot) or 1)
    local power = C_PetBattles.GetPower(ally, activeSlot) or 200
    local speed = C_PetBattles.GetSpeed(ally, activeSlot) or 200

    local _, loadoutAb1, loadoutAb2, loadoutAb3 = C_PetJournal.GetPetLoadOutInfo(activeSlot)

    local selectedAbSlot = ns.usedAllyAbilitySlot
    if C_PetBattles.GetSelectedAction then
        local actionType, actionIndex = C_PetBattles.GetSelectedAction()
        local abilityActionEnum = (Enum and Enum.BattlePetAction and Enum.BattlePetAction.Ability) or LE_BATTLE_PET_ACTION_ABILITY or 2
        if actionType == abilityActionEnum and actionIndex and actionIndex >= 1 and actionIndex <= 3 then
            selectedAbSlot = actionIndex
            ns.usedAllyAbilitySlot = actionIndex
            if ns.pendingChargeSlot ~= actionIndex then
                RecordPendingChargeAbility(actionIndex)
            end
        end
    end

    if ns.activeChargeSlot then
        if ns.activeChargePetSlot ~= activeSlot or activeHP <= 0 or (ns.activeChargeTurns or 0) <= 0 then
            ns.activeChargeSlot, ns.activeChargePetSlot, ns.activeChargeTurns = nil, nil, 0
        else
            for checkIdx = 1, 3 do
                if checkIdx ~= ns.activeChargeSlot then
                    local usableOther = C_PetBattles.GetAbilityState(ally, activeSlot, checkIdx)
                    if usableOther == true then
                        ns.activeChargeSlot, ns.activeChargePetSlot, ns.activeChargeTurns = nil, nil, 0
                        break
                    end
                end
            end
        end
    end

    for abIdx = 1, 3 do
        local btn = hud.allyAbBtns[abIdx]
        local fallbackID
        if abIdx == 1 then fallbackID = loadoutAb1
        elseif abIdx == 2 then fallbackID = loadoutAb2
        else fallbackID = loadoutAb3 end
        local abID, finalIcon, abPetType, noHints = ResolveHUDAbility(ally, activeSlot, abIdx, fallbackID)

        if abID then
            btn:Show()
            btn.abID = abID
            btn.maxHp = maxHp
            btn.power = power
            btn.speed = speed

            if btn._lastIcon ~= finalIcon then
                btn._lastIcon = finalIcon
                btn.icon:SetTexture(finalIcon)
            end
            btn.icon:Show()

            if activeHP > 0 and enemyPetType then
                local modState = GetAttackModifierState(abPetType, enemyPetType, noHints)
                UpdateAbilityModifierBadge(btn, modState)
            else
                UpdateAbilityModifierBadge(btn, nil)
            end

            local isUsable, currentCD, currentLockdown = C_PetBattles.GetAbilityState(ally, activeSlot, abIdx)
            local remainTurns = math.max(tonumber(currentCD) or 0, tonumber(currentLockdown) or 0)
            local isChargingRelease = (ns.activeChargeSlot == abIdx and ns.activeChargePetSlot == activeSlot and (ns.activeChargeTurns or 0) > 0)
            local lockedByChannel = (ns.activeChargeSlot and ns.activeChargeSlot ~= abIdx) or ((isUsable == false) and remainTurns <= 0 and not isChargingRelease)
            local borderCol = Theme.Colors.border

            if selectedAbSlot and selectedAbSlot >= 1 and selectedAbSlot <= 3 then
                if abIdx == selectedAbSlot then
                    btn.icon:SetDesaturated(false)
                    btn.icon:SetVertexColor(1, 1, 1)
                    btn.cdMask:Hide()
                    btn.cdTxt:SetText(ns.pendingChargeSlot == abIdx and ("|cff38bdf8" .. ns:T("蓄力") .. "|r") or "")
                    btn.onCooldown = false
                    borderCol = SELECTED_BORDER_COLOR
                else
                    btn.icon:SetDesaturated(true)
                    btn.icon:SetVertexColor(0.40, 0.40, 0.40)
                    btn.cdMask:Show()
                    btn.cdTxt:SetText(remainTurns > 0 and ("|cffffd100" .. remainTurns .. "|r") or "")
                    btn.onCooldown = (remainTurns > 0)
                    borderCol = Theme.Colors.border
                end
            else
                if activeHP <= 0 then
                    btn.icon:SetDesaturated(true)
                    btn.icon:SetVertexColor(0.45, 0.45, 0.45)
                    btn.cdMask:Show()
                    btn.cdTxt:SetText("")
                    btn.onCooldown = false
                    borderCol = Theme.Colors.border
                elseif isChargingRelease then
                    btn.icon:SetDesaturated(false)
                    btn.icon:SetVertexColor(1, 1, 1)
                    btn.cdMask:Hide()
                    btn.cdTxt:SetText("|cffffd100" .. ns:T("释放") .. "|r")
                    btn.onCooldown = false
                    borderCol = SELECTED_BORDER_COLOR
                elseif remainTurns > 0 then
                    btn.icon:SetDesaturated(true)
                    btn.icon:SetVertexColor(0.55, 0.55, 0.55)
                    btn.cdMask:Show()
                    btn.cdTxt:SetText("|cffffd100" .. remainTurns .. "|r")
                    btn.onCooldown = true
                    borderCol = COOLDOWN_BORDER_COLOR
                elseif lockedByChannel then
                    btn.icon:SetDesaturated(true)
                    btn.icon:SetVertexColor(0.45, 0.45, 0.45)
                    btn.cdMask:Show()
                    btn.cdTxt:SetText("")
                    btn.onCooldown = true
                    borderCol = Theme.Colors.border
                else
                    btn.icon:SetDesaturated(false)
                    btn.icon:SetVertexColor(1, 1, 1)
                    btn.cdMask:Hide()
                    btn.cdTxt:SetText("")
                    btn.onCooldown = false
                    borderCol = Theme.Colors.borderBlue
                end
            end

            btn._normalBorder = borderCol
            if not btn:IsMouseOver() then
                btn:SetBackdropBorderColor(unpack(borderCol))
            end
        else
            UpdateAbilityModifierBadge(btn, nil)
            btn:Hide()
            btn.abID = nil
        end
    end

    local trapBtn = hud.utilBtns.TRAP
    if trapBtn then
        local trapOk = C_PetBattles.IsTrapAvailable and C_PetBattles.IsTrapAvailable()
        trapBtn.icon:SetDesaturated(not trapOk)
        trapBtn.cdMask:SetShown(not trapOk)
        local tBorder = trapOk and Theme.Colors.borderGreen or Theme.Colors.border
        trapBtn._normalBorder = tBorder
        if not trapBtn:IsMouseOver() then
            trapBtn:SetBackdropBorderColor(unpack(tBorder))
        end
    end

    local passBtn = hud.utilBtns.PASS
    if passBtn then
        local passOk = C_PetBattles.IsSkipAvailable and C_PetBattles.IsSkipAvailable()
        passBtn.icon:SetDesaturated(not passOk)
        passBtn.cdMask:SetShown(not passOk)
    end

    local mustSwap = (activeHP <= 0) or (C_PetBattles.ShouldShowPetSelect and C_PetBattles.ShouldShowPetSelect())
    if mustSwap or hud.manualSwapOpen then
        hud.swapBar:Show()
        for s = 1, 3 do
            local pBtn = hud.swapBar.petBtns[s]
            if s <= numAllyPets then
                pBtn:Show()
                local name, spName = C_PetBattles.GetName(ally, s)
                local icon = C_PetBattles.GetIcon(ally, s)
                local hp = C_PetBattles.GetHealth(ally, s) or 0
                local mHp = math.max(1, C_PetBattles.GetMaxHealth(ally, s) or 1)
                local lv = C_PetBattles.GetLevel(ally, s) or 25
                local canSwap = C_PetBattles.CanPetSwapIn and C_PetBattles.CanPetSwapIn(s)
                local isDead = (hp <= 0)

                pBtn.icon.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                pBtn.icon.icon:SetDesaturated(isDead)
                pBtn.nameTxt:SetText(string.format("|cffffd100%d|r %s", lv, name or spName or "Pet"))

                local hpPct = isDead and 0 or math.floor((hp / mHp) * 100)
                pBtn.hpBar:SetValue(hpPct)
                pBtn.hpTxt:SetText(isDead and "|cffff2020阵亡|r" or (hpPct .. "%"))

                if s == activeSlot then
                    pBtn:SetBackdropColor(unpack(Theme.Colors.bgCardActive))
                    pBtn:SetBackdropBorderColor(unpack(Theme.Colors.borderBlue))
                elseif canSwap then
                    pBtn:SetBackdropColor(unpack(Theme.Colors.bgCard))
                    pBtn:SetBackdropBorderColor(unpack(Theme.Colors.borderGreen))
                else
                    pBtn:SetBackdropColor(unpack(Theme.Colors.bgInput))
                    pBtn:SetBackdropBorderColor(unpack(Theme.Colors.border))
                end
            else
                pBtn:Hide()
            end
        end
    else
        hud.swapBar:Hide()
    end
end

-- 刷新右侧敌方技能与CD矩阵（零临时表分配）
function ns:RefreshEmbeddedEnemySkillStrip(hud)
    if not hud or not hud.combatRow then return end
    if not C_PetBattles or not C_PetBattles.IsInBattle() then return end

    local ally = (Enum and Enum.BattlePetOwner and Enum.BattlePetOwner.Ally) or LE_BATTLE_PET_ALLY or 1
    local enemy = (Enum and Enum.BattlePetOwner and Enum.BattlePetOwner.Enemy) or LE_BATTLE_PET_ENEMY or 2
    local numEnemyPets = C_PetBattles.GetNumPets(enemy) or 0
    -- Keep the complete enemy strip close to the HUD's right edge; the single-pet
    -- layout has no reserve cards and keeps the active card at the old position.
    local enemyCardOffset = (numEnemyPets > 1) and -112 or -40
    if hud._enemyCardOffset ~= enemyCardOffset then
        hud._enemyCardOffset = enemyCardOffset
        hud.activeEnemyCard:ClearAllPoints()
        hud.activeEnemyCard:SetPoint("RIGHT", hud.combatRow, "RIGHT", enemyCardOffset, 0)
    end
    local activeSlot = C_PetBattles.GetActivePet(enemy) or 1
    if activeSlot < 1 or activeSlot > math.max(1, numEnemyPets) then
        activeSlot = 1
    end

    local activeAllySlot = C_PetBattles.GetActivePet(ally) or 1
    local allyPetType = C_PetBattles.GetPetType(ally, activeAllySlot)

    local actCard = hud.activeEnemyCard
    if numEnemyPets >= 1 then
        actCard:Show()
        local hp = C_PetBattles.GetHealth(enemy, activeSlot) or 0
        local maxHp = math.max(1, C_PetBattles.GetMaxHealth(enemy, activeSlot) or 1)
        local power = C_PetBattles.GetPower(enemy, activeSlot) or 200
        local speed = C_PetBattles.GetSpeed(enemy, activeSlot) or 200
        local isDead = (hp <= 0)

        actCard.maxHp = maxHp
        actCard.power = power
        actCard.speed = speed

        UpdateEnemySlotAbilities(actCard, activeSlot, isDead, allyPetType)
    else
        actCard:Hide()
    end

    local back1, back2 = nil, nil
    for s = 1, numEnemyPets do
        if s ~= activeSlot then
            if not back1 then
                back1 = s
            elseif not back2 then
                back2 = s
            end
        end
    end

    for bIdx = 1, 2 do
        local bCard = hud.backEnemyCards[bIdx]
        local pSlot = (bIdx == 1) and back1 or back2
        if pSlot then
            bCard:Show()
            local hp = C_PetBattles.GetHealth(enemy, pSlot) or 0
            local maxHp = math.max(1, C_PetBattles.GetMaxHealth(enemy, pSlot) or 1)
            local power = C_PetBattles.GetPower(enemy, pSlot) or 200
            local speed = C_PetBattles.GetSpeed(enemy, pSlot) or 200
            local isDead = (hp <= 0)

            bCard.maxHp = maxHp
            bCard.power = power
            bCard.speed = speed

            UpdateEnemySlotAbilities(bCard, pSlot, isDead, nil)
        else
            bCard:Hide()
        end
    end
end

-- 立即刷新 HUD（内部实际渲染实现）
function ns:UpdateBattleHUDNow(monitorOnly)
    if not ns.BattleHUD or not ns.BattleHUD:IsShown() then return end
    if not C_PetBattles or not C_PetBattles.IsInBattle() then return end

    local hud = ns.BattleHUD
    local enemy = (Enum and Enum.BattlePetOwner and Enum.BattlePetOwner.Enemy) or LE_BATTLE_PET_ENEMY or 2
    -- Use total team size, not surviving pets. Unknown opening data retains the full layout.
    local numEnemyPets = C_PetBattles.GetNumPets(enemy) or 0
    local hudWidth = (numEnemyPets == 1) and HUD_SINGLE_ENEMY_WIDTH or HUD_FULL_WIDTH
    if not monitorOnly then
        local hkDisp = self:FormatHotKeyDisplay()

        if hud.stepBtn and hud._lastHkDisp ~= hkDisp then
            hud._lastHkDisp = hkDisp
            hud.stepBtn.text:SetText(ns:TF("执行脚本动作 [%s]", hkDisp))
        end

        self:RefreshAllyCombatControls(hud)
        self:RefreshEmbeddedEnemySkillStrip(hud)
    end

    local isExpanded = (ns.db and ns.db.settings and ns.db.settings.hudMonitorExpanded) and true or false
    if hud.toggleBtn and hud.toggleBtn.arrow and hud._lastExpanded ~= isExpanded then
        hud._lastExpanded = isExpanded
        hud.toggleBtn.arrow:SetRotation(isExpanded and 0 or math.rad(180))
    end
    if hud.SyncMonitorTicker then
        hud:SyncMonitorTicker(isExpanded)
    end

    if isExpanded then
        local lineCount = 0
        local l1, l2

        local playerLine = self:BuildCompactPlayerLine()
        if playerLine then
            lineCount = 1
            l1 = playerLine
        end

        local r = ns.ScriptEngine.currentRound or 1
        local remainCD = self:GetRevivePetCooldownRemain()
        local cdText = FormatRemainTimeText(remainCD)
        local rawLog = ns.ScriptEngine.logs[1] or "|cff9ca3af" .. ns:T("等待执行...") .. "|r"
        if hud._lastRawLog ~= rawLog then
            hud._lastRawLog = rawLog
            hud._cleanLog = string.gsub(rawLog, "^|cff6b7280%[.-%]|r%s*", "")
        end
        local battleStart = tonumber(ns.BattleStats and ns.BattleStats.battleStartTime) or GetTime()
        local battleElapsed = FormatBattleElapsedTime(GetTime() - battleStart)
        local logLine = string.format("|cffc678dd[R%d]|r %s%s  |  %s  |  %s%s", r,
            ns:T("战斗时间："), battleElapsed, hud._cleanLog or "", ns:T("复活:"), cdText)
        lineCount = lineCount + 1
        if lineCount == 1 then
            l1 = logLine
        else
            l2 = logLine
        end

        for i = 1, 2 do
            local fs = hud.infoLines[i]
            local lineStr = (i == 1) and l1 or l2
            if fs._lastMonitorLine ~= lineStr then
                fs._lastMonitorLine = lineStr
                fs:SetText(lineStr or "")
                fs:SetShown(lineStr ~= nil)
            end
        end

        local panelH = lineCount * 18 + 4
        if hud.monitorPanel._lastH ~= panelH then
            hud.monitorPanel._lastH = panelH
            hud.monitorPanel:SetHeight(panelH)
        end
        hud.monitorPanel:Show()

        local totalH = 124 + panelH + 4
        if hud._lastW ~= hudWidth or hud._lastH ~= totalH then
            hud._lastW, hud._lastH = hudWidth, totalH
            hud:SetSize(hudWidth, totalH)
        end
    else
        hud.monitorPanel:Hide()
        if hud._lastW ~= hudWidth or hud._lastH ~= 124 then
            hud._lastW, hud._lastH = hudWidth, 124
            hud:SetSize(hudWidth, 124)
        end
    end
end

-- 对外统一防抖刷新入口：同一帧内多次调用自动合并为 1 次
local hudRefreshQueued = false
local hudRefreshNeedsControls = false

local function RunQueuedHUDRefresh()
    local monitorOnly = not hudRefreshNeedsControls
    hudRefreshQueued = false
    hudRefreshNeedsControls = false
    ns:UpdateBattleHUDNow(monitorOnly)
end

function ns:UpdateBattleHUD(monitorOnly)
    if not ns.BattleHUD or not ns.BattleHUD:IsShown() then return end
    hudRefreshNeedsControls = hudRefreshNeedsControls or not monitorOnly
    if hudRefreshQueued then return end
    hudRefreshQueued = true
    C_Timer.After(0, RunQueuedHUDRefresh)
end

local hudEventWatcher = CreateFrame("Frame")
hudEventWatcher:RegisterEvent("PET_BATTLE_OPENING_START")
hudEventWatcher:RegisterEvent("PET_BATTLE_OPENING_DONE")
hudEventWatcher:RegisterEvent("PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE")
hudEventWatcher:RegisterEvent("PET_BATTLE_PET_CHANGED")
hudEventWatcher:RegisterEvent("PET_BATTLE_ACTION_SELECTED")
hudEventWatcher:RegisterEvent("UPDATE_BINDINGS")
hudEventWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
hudEventWatcher:SetScript("OnEvent", function(_, event, arg1)
    if event == "UPDATE_BINDINGS" or event == "PLAYER_REGEN_ENABLED" then
        ns:ApplyBattleHotKeyBinding()
    elseif event == "PET_BATTLE_OPENING_DONE" then
        ns.usedAllyAbilitySlot = nil
        ns._lastRoundCompleteAt = nil
        ns.pendingChargeSlot, ns.pendingChargePetSlot, ns.pendingChargeTurns = nil, nil, 0
        ns.activeChargeSlot, ns.activeChargePetSlot, ns.activeChargeTurns = nil, nil, 0
        if ns.db and ns.db.settings and ns.db.settings.battleHudEnabled ~= false then
            ns:SuppressBlizzardBottomFrame()
        else
            ns:RestoreBlizzardBottomFrame()
        end
        ns:ApplyBattleHotKeyBinding()
        ns:UpdateBattleHUD()
    elseif event == "PET_BATTLE_OPENING_START" then
        ns.usedAllyAbilitySlot = nil
        ns._lastRoundCompleteAt = nil
        ns.pendingChargeSlot, ns.pendingChargePetSlot, ns.pendingChargeTurns = nil, nil, 0
        ns.activeChargeSlot, ns.activeChargePetSlot, ns.activeChargeTurns = nil, nil, 0
        ns:UpdateBattleHUD()
    elseif event == "PET_BATTLE_PET_CHANGED" then
        local ally = Enum and Enum.BattlePetOwner and Enum.BattlePetOwner.Ally or 1
        local curAllySlot = C_PetBattles and C_PetBattles.GetActivePet and C_PetBattles.GetActivePet(ally)
        if arg1 == ally or (ns.pendingChargePetSlot and curAllySlot ~= ns.pendingChargePetSlot) or (ns.activeChargePetSlot and curAllySlot ~= ns.activeChargePetSlot) then
            ns.usedAllyAbilitySlot = nil
            ns.pendingChargeSlot, ns.pendingChargePetSlot, ns.pendingChargeTurns = nil, nil, 0
            ns.activeChargeSlot, ns.activeChargePetSlot, ns.activeChargeTurns = nil, nil, 0
        end
        ns:UpdateBattleHUD()
    elseif event == "PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE" then
        local now = GetTime()
        if (now - (ns._lastRoundCompleteAt or 0)) < 0.2 then
            ns:UpdateBattleHUD()
            return
        end
        ns._lastRoundCompleteAt = now
        ns.usedAllyAbilitySlot = nil
        if ns.pendingChargeSlot then
            ns.activeChargeSlot = ns.pendingChargeSlot
            ns.activeChargePetSlot = ns.pendingChargePetSlot
            ns.activeChargeTurns = ns.pendingChargeTurns
            ns.pendingChargeSlot, ns.pendingChargePetSlot, ns.pendingChargeTurns = nil, nil, 0
        elseif ns.activeChargeSlot then
            ns.activeChargeTurns = (ns.activeChargeTurns or 0) - 1
            if ns.activeChargeTurns <= 0 then
                ns.activeChargeSlot, ns.activeChargePetSlot, ns.activeChargeTurns = nil, nil, 0
            end
        end
        ns:UpdateBattleHUD()
    elseif event == "PET_BATTLE_ACTION_SELECTED" then
        ns:UpdateBattleHUD()
    end
end)
