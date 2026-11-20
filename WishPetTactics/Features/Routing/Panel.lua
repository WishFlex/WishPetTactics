local ADDON_NAME, ns = ...
local Theme = ns.Theme

local EMPTY_LIST = {}

local function LRoute(zhCN, zhTW, enUS)
    if ns.locale == "zhTW" then return zhTW end
    if ns.locale ~= "zhCN" then return enUS end
    return zhCN
end

local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local LEVELING_ICON = "Interface\\Icons\\INV_Pet_Achievement_RaiseAPetLevel_25"
local SWAP_DETAIL_ICON_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Common\\swap_detail.tga"
local UNUSED_PETS = {}
local routeAbilityInfo = {}
local routePetTip

local function RenderRoutePetDetails(owner, lines, count)
    if not routePetTip then
        routePetTip = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        routePetTip:SetClampedToScreen(true)
        routePetTip:EnableMouse(false)
        Theme:ApplyBackdrop(routePetTip, Theme.Colors.bgPopup, Theme.Colors.border, false)
        routePetTip.lines = {}
    end
    local tip = routePetTip
    local parent = ns:GetActiveUIParent()
    if tip:GetParent() ~= parent then tip:SetParent(parent) end
    tip:SetFrameStrata("TOOLTIP")
    tip:SetFrameLevel(math.max(480, owner:GetFrameLevel() + 20))
    tip:SetScale(owner:GetEffectiveScale() / parent:GetEffectiveScale())
    local y = 8
    for i = 1, count do
        local fs = tip.lines[i]
        if not fs then
            fs = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            tip.lines[i] = fs
        end
        local height = i == 1 and 28 or (lines[i]:find("|T", 1, true) and 22 or 16)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 10, -y)
        fs:SetSize(260, height)
        if fs._text ~= lines[i] then fs:SetText(lines[i]); fs._text = lines[i] end
        fs:Show()
        y = y + height
    end
    for i = count + 1, #tip.lines do tip.lines[i]:Hide() end
    tip:SetSize(280, y + 8)
    tip:ClearAllPoints()
    tip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 8, 0)
    tip.owner = owner
    tip:Show()
    tip:Raise()
end

local function GetRoutePetSlot(team, slot, cache)
    local petID = team.pets and team.pets[slot]
    local levelingSlot = team.levelingSlot or ns.db.settings.levelingSlot or 2
    if petID == "LEVELING" or (team.hasLevelingSlot and levelingSlot == slot) then
        return LEVELING_ICON, nil, ns:T("经验槽"), false, nil, nil, nil
    end

    local randomType = team.randomSlots and team.randomSlots[slot]
    if randomType ~= nil then
        local petType = Theme.PetTypes[randomType]
        return (petType and petType.icon) or "Interface\\Icons\\INV_Misc_Dice_02", nil, ns:T("随机槽位"), false, nil, randomType, nil
    end

    local speciesID = (team.speciesLoadout and tonumber(team.speciesLoadout[slot])) or 0
    local savedSpecies, level, name
    local packed = petID and cache.packedPet[petID]
    if packed then
        level = packed % 64
        savedSpecies = (packed - level) / 64
        name = cache.customNames[petID]
    elseif type(petID) == "string" then
        savedSpecies, name, level = C_PetJournal.GetPetInfoByPetID(petID)
    end
    if speciesID == 0 then speciesID = savedSpecies or 0 end
    if speciesID <= 0 then
        if petID then return QUESTION_ICON, nil, ns:T("未知宠物"), true, nil, nil, nil end
        return
    end

    local meta = ns:GetSpeciesMeta(speciesID)
    if savedSpecies ~= speciesID then
        petID = ns.AutoRouting:FindAnyCollectedPetForSpecies(speciesID, UNUSED_PETS)
        packed = petID and cache.packedPet[petID]
        level = packed and packed % 64
        name = petID and cache.customNames[petID]
    end
    return meta.icon, petID, (name and name ~= "" and name) or meta.name, not petID, level, meta.petType, speciesID
end

local function HideRoutePetTooltip(icon)
    if icon._hoverTimer then icon._hoverTimer:Cancel(); icon._hoverTimer = nil end
    if routePetTip and routePetTip.owner == icon then routePetTip.owner = nil; routePetTip:Hide() end
    if ns.HideCustomTooltip then ns:HideCustomTooltip(icon) end
end

local function ShowRoutePetTooltip(icon)
    if not icon.petName then return end
    if icon.petID and ns.SearchFilter and ns.SearchFilter.GetPetBreed then
        icon.breed = ns.SearchFilter:GetPetBreed(icon.petID, icon.speciesID, icon.maxHealth, icon.power, icon.speed, icon.level, icon.rarity)
    end
    local abilities = icon.abilities
    if icon.speciesID and icon.speciesID > 0 and ns.AutoRouting and ns.AutoRouting.ValidateAbilitiesForSpecies then
        local hasAny = abilities and ((tonumber(abilities[1]) or 0) > 0 or (tonumber(abilities[2]) or 0) > 0 or (tonumber(abilities[3]) or 0) > 0)
        if not hasAny then abilities = ns.AutoRouting:ValidateAbilitiesForSpecies(icon.speciesID, abilities) end
    end
    local quality = Theme.QualityColors[icon.rarity]
    local portrait = icon.petTexture or QUESTION_ICON
    local lines = {
        string.format("|T%s:24:24:0:0:64:64|t  |cfff3f4f6%s|r", portrait, icon.petName),
    }
    local lineCount = 1

    if icon.missing then
        lineCount = lineCount + 1
        lines[lineCount] = "|cffff6161" .. ns:T("未拥有此宠物") .. "|r"
    end
    local infoParts = {}
    if icon.speciesID and icon.speciesID > 0 then
        local count, limit = C_PetJournal.GetNumCollectedInfo(icon.speciesID)
        if count and limit then infoParts[#infoParts + 1] = string.format("%d/%d", count, limit) end
    end
    if icon.level then infoParts[#infoParts + 1] = ns:TF("%d级", icon.level) end
    if quality then infoParts[#infoParts + 1] = quality[4] end
    if icon.breed and icon.breed ~= "" then infoParts[#infoParts + 1] = "|cff38bdf8" .. icon.breed .. "|r" end
    local petType = Theme.PetTypes[icon.petType]
    if petType then infoParts[#infoParts + 1] = petType.name end
    if #infoParts > 0 then
        lineCount = lineCount + 1
        lines[lineCount] = table.concat(infoParts, "  |cff6b7280·|r  ")
    end
    if icon.health and icon.maxHealth and icon.maxHealth > 0 then
        lineCount = lineCount + 1
        lines[lineCount] = string.format("|cffff7070%d/%d|r  |cff6b7280·|r  攻%d  |cff6b7280·|r  速%d",
            math.max(0, icon.health), icon.maxHealth, icon.power or 0, icon.speed or 0)
    end

    local abilityParts = {}
    for idx = 1, 3 do
        local abilityID = abilities and tonumber(abilities[idx])
        if abilityID and abilityID > 0 then
            local info = routeAbilityInfo[abilityID]
            if not info then
                local name, texture = C_PetJournal.GetPetAbilityInfo(abilityID)
                if texture then info = { name, texture }; routeAbilityInfo[abilityID] = info end
            end
            local abilityName, abilityIcon = info and info[1], info and info[2]
            if abilityIcon then
                abilityParts[#abilityParts + 1] = string.format("|T%s:18:18:0:0:64:64|t %s", tostring(abilityIcon), abilityName or ns:T("技能"))
            end
        end
    end
    if #abilityParts > 0 then
        lineCount = lineCount + 1
        lines[lineCount] = table.concat(abilityParts, "  ")
    end

    RenderRoutePetDetails(icon, lines, lineCount)
end

local function ScheduleRoutePetTooltip(icon)
    HideRoutePetTooltip(icon)
    icon._hoverTimer = C_Timer.NewTimer(0.25, function()
        icon._hoverTimer = nil
        if icon:IsVisible() and icon:IsMouseOver() then ShowRoutePetTooltip(icon) end
    end)
end

local function RenderRoutePetIcon(icon, texture, petID, name, missing, level, petType, speciesID, abilities)
    if not texture then
        icon:Hide()
        return
    end
    local health, maxHealth, power, speed, rarity
    if petID then health, maxHealth, power, speed, rarity = C_PetJournal.GetPetStats(petID) end
    local dead = health ~= nil and health <= 0
    icon.petName, icon.missing, icon.level = name, missing, level
    icon.health, icon.maxHealth, icon.power, icon.speed, icon.rarity, icon.breed = health, maxHealth, power, speed, rarity, nil
    icon.petID, icon.petTexture, icon.petType, icon.speciesID, icon.abilities = petID, texture, petType, speciesID, abilities

    if icon._lastTex ~= texture then
        icon._lastTex = texture
        icon.icon:SetTexture(texture)
    end
    icon.icon:SetDesaturated(dead or missing == true)
    icon.mark:SetText(missing and "|cffff7777?|r" or dead and "|cffff5555×|r" or "")
    icon.levelText:SetText(level and level < 25 and ("|cffffcd56" .. level .. "|r") or "")

    local quality = Theme.QualityColors[rarity]
    local border = missing and Theme.Colors.borderRed or quality or Theme.Colors.border
    icon:SetBackdropBorderColor(border[1], border[2], border[3], 1)

    local hasHealth = health ~= nil and maxHealth and maxHealth > 0
    icon.healthBar:SetShown(hasHealth and true or false)
    if hasHealth then
        local ratio = math.max(0, math.min(1, health / maxHealth))
        icon.healthBar:SetValue(ratio)
        icon.healthTrack:SetColorTexture(dead and 0.55 or 0.14, 0.06, 0.09, 1)
        ns:ApplyHealthBarColor(icon.healthBar, ratio * 100, dead)
    end
    icon:Show()
    if routePetTip and routePetTip:IsShown() and routePetTip.owner == icon then ShowRoutePetTooltip(icon) end
end

local function UpdateDragGhostPosition(g)
    local cx, cy = GetCursorPosition()
    local scale = g:GetEffectiveScale()
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale + 12, cy / scale - 10)
end

-- ==================== TARGET ROUTING HUB // 目标自动换队中心（单目标聚焦 + 导入导出 + 队伍隔离） ====================
function ns:GetRoutingDialogParent()
    local activeTop = (self.GetActiveUIParent and self:GetActiveUIParent()) or UIParent
    local routing = self.RoutingModal
    if routing and routing:GetParent() == activeTop and routing:IsVisible() then
        return routing
    end
    return self.MainFrame or activeTop
end

function ns:ShowRoutingModal(standalone, preferTeam)
    local activeTop = (self.GetActiveUIParent and self:GetActiveUIParent()) or UIParent
    local parent = not standalone and ns.MainFrame or activeTop
    if self.HideAllPopups then self:HideAllPopups() end
    if ns.ScriptWorkspaceModal and ns.ScriptWorkspaceModal:IsShown() then
        ns.ScriptWorkspaceModal:Hide()
    end

    if not ns.RoutingModal then
        local px = Theme:GetPixelScale()
        local rm = CreateFrame("Frame", "WishPetTacticsRoutingModal", parent, "BackdropTemplate")
        rm:Hide()
        tinsert(UISpecialFrames, rm:GetName())
        rm:SetSize(860, 560)
        rm:SetPoint("CENTER", 0, 0)
        rm:SetFrameStrata("FULLSCREEN_DIALOG")
        rm:SetFrameLevel(260)
        rm:SetMovable(true)
        rm:SetClampedToScreen(true)
        rm:EnableMouse(true)
        rm:RegisterForDrag("LeftButton")
        rm:SetScript("OnDragStart", rm.StartMoving)
        rm:SetScript("OnDragStop", rm.StopMovingOrSizing)
        Theme:ApplyBackdrop(rm, { 0.07, 0.07, 0.07, 0.98 }, Theme.Colors.border, false)
        if ns.MakeModal then ns:MakeModal(rm) end

        rm:HookScript("OnShow", function(self)
            self:RegisterEvent("PLAYER_TARGET_CHANGED")
            self:RegisterEvent("UPDATE_BINDINGS")
            self:RefreshWindowKey()
        end)

        rm:HookScript("OnHide", function(self)
            self:UnregisterEvent("PLAYER_TARGET_CHANGED")
            self:UnregisterEvent("UPDATE_BINDINGS")
            if ns.KeybindCapFrame and ns.KeybindCapFrame:GetParent() == self then
                ns.KeybindCapFrame:Hide()
            end
            if self:GetParent() == UIParent then
                ns:HideAllPopups()
                if ns.TeamBuilderModal and ns.TeamBuilderModal:GetParent() == self then
                    if ns.PetPickerModal then ns.PetPickerModal:Hide() end
                    ns.TeamBuilderModal:Hide()
                end
                if ns.TeamEditModal and ns.TeamEditModal:GetParent() == self then
                    ns.TeamEditModal:Hide()
                end
            end
            ns.draggingRouteTeamIdx = nil
            ns.hoverRouteTeamIdx = nil
            if ns.RouteDragGhost then
                ns.RouteDragGhost:SetScript("OnUpdate", nil)
                ns.RouteDragGhost:Hide()
            end
        end)

        rm:SetScript("OnEvent", function(self, event)
            if event == "UPDATE_BINDINGS" then
                self:RefreshWindowKey()
            elseif event == "PLAYER_TARGET_CHANGED" and self:IsShown() then
                local tNpcID, tNpcName = ns.AutoRouting:GetUnitNPCID("target")
                if tNpcID or tNpcName then
                    self:FocusCurrentTeamRoute()
                    self:Refresh()
                elseif self.pendingTargetName or self.pendingTargetID then
                    self:FocusCurrentTeamRoute()
                    self:Refresh()
                end
            end
        end)

        rm.offset = 0
        rm.teamOffset = 0
        rm.selectedKey = nil
        rm.pendingTargetID = nil
        rm.pendingTargetName = nil
        rm.routesList = {}
        rm.teamSnapList = {}

        -- 1. 顶部标题与全局控制栏
        local title = rm:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 24, -18)
        Theme:HookLocalizedFontString(title)
        title:SetText(ns:T("|cff38bdf8TARGETS // 目标管理|r"))

        local closeBtn = Theme:CreateCloseIconButton(rm, function() rm:Hide() end)
        closeBtn:SetPoint("TOPRIGHT", -22, -20)

        -- 脚本编辑器按钮：改为与其他按钮一致的无框扁平下划线风格
        local scriptJumpBtn = Theme:CreateActionButton(rm, 108, 24, "|cffc084fc脚本编辑器|r", "script")
        scriptJumpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)
        scriptJumpBtn:SetScript("OnClick", function()
            rm:Hide()
            if ns.ToggleScriptWorkspace then ns:ToggleScriptWorkspace(true) end
        end)

        local hotkeyBtn = Theme:CreateActionButton(rm, 136, 24, ns:TF("战斗键：%s", "|cff38bdf8" .. ns:FormatHotKeyDisplay() .. "|r"), "hotkey")
        hotkeyBtn:SetPoint("RIGHT", scriptJumpBtn, "LEFT", -8, 0)
        hotkeyBtn:SetScript("OnClick", function()
            if ns.StartKeybindCapture then ns:StartKeybindCapture() end
        end)
        rm.hotkeyBtn = hotkeyBtn

        local toggleLoadBtn = Theme:CreateFlatButton(rm, 116, 24, "")
        toggleLoadBtn:SetPoint("RIGHT", hotkeyBtn, "LEFT", -8, 0)
        toggleLoadBtn:SetScript("OnClick", function()
            ns.db.settings.autoLoadTarget = not ns.db.settings.autoLoadTarget
            rm:RefreshTopControls()
        end)
        rm.toggleLoadBtn = toggleLoadBtn

        local windowKeyBtn = Theme:CreateFlatButton(rm, 134, 24, "")
        windowKeyBtn:SetPoint("RIGHT", toggleLoadBtn, "LEFT", -8, 0)
        windowKeyBtn.text:SetTextColor(0.77, 0.63, 0.93, 1)
        windowKeyBtn.text:SetWidth(124)
        windowKeyBtn.text:SetWordWrap(false)
        windowKeyBtn:SetScript("OnClick", function(_, button)
            if button == "LeftButton" then ns:StartKeybindCapture(true) end
        end)

        function rm:RefreshWindowKey()
            windowKeyBtn.text:SetText(ns:TF("窗口键：%s", "|cff38bdf8" .. ns:GetTargetWindowKeyText() .. "|r"))
        end

        local hdrLine = rm:CreateTexture(nil, "BORDER")
        hdrLine:SetHeight(px)
        hdrLine:SetPoint("TOPLEFT", 24, -48)
        hdrLine:SetPoint("TOPRIGHT", -24, -48)
        hdrLine:SetTexture("Interface\\Buttons\\WHITE8X8")
        hdrLine:SetVertexColor(unpack(Theme.Colors.divider))

        -- 2. 左侧：仅显示当前聚焦的单个目标（目标名称不再重复占用标题行）
        local leftBox = CreateFrame("Frame", nil, rm, "BackdropTemplate")
        leftBox:SetSize(310, 412)
        leftBox:SetPoint("TOPLEFT", 24, -86)
        Theme:ApplyBackdrop(leftBox, Theme.Colors.bgInput, Theme.Colors.border, false)
        rm.leftBox = leftBox

        local emptyTargetTxt = leftBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        emptyTargetTxt:SetPoint("CENTER", 0, 10)
        emptyTargetTxt:SetWidth(270)
        emptyTargetTxt:SetJustifyH("CENTER")
        Theme:HookLocalizedFontString(emptyTargetTxt)
        emptyTargetTxt:SetText(ns:T("当前激活队伍暂未绑定目标\n\n可点击下方按钮将当前选中 NPC 或指定 ID/名称绑定至本队伍"))
        emptyTargetTxt:Hide()
        rm.emptyTargetTxt = emptyTargetTxt

        local MAX_LEFT_ROWS = 12
        rm.leftRows = {}
        for i = 1, MAX_LEFT_ROWS do
            local lr = Theme:CreateMenuRow(leftBox, 294, 32, "")
            lr:SetPoint("TOPLEFT", 8, -6 - (i - 1) * 33)
            lr:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            lr:SetScript("OnClick", function(selfBtn, button)
                local rKey = selfBtn.routeKey
                if not rKey then return end
                if button == "RightButton" then
                    ns:ShowRouteTargetContextMenu(selfBtn, rKey)
                end
            end)
            rm.leftRows[i] = lr
        end

        local addCurrentBtn = Theme:CreateActionButton(rm, 114, 30, "+ 添加当前目标", "add-target", nil, "PRIMARY")
        addCurrentBtn:SetPoint("BOTTOMLEFT", 24, 16)
        addCurrentBtn:SetScript("OnClick", function()
            local npcID, npcName = ns.AutoRouting:GetManualTargetNPCID()
            if not npcID and not npcName then
                npcID, npcName = rm.pendingTargetID, rm.pendingTargetName
            end
            if not npcID and not npcName then
                ns:PrintError("无法读取目标 NPC 的名称或 ID。若已选中 NPC，请手动输入名称或 ID 添加。")
                ns:ShowQuickInputModal("ADD_TARGET_ROUTE")
                return
            end
            local route, rKey = ns:EnsureTargetRoute(npcID, npcName)
            if route and rKey then
                rm.pendingTargetID = nil
                rm.pendingTargetName = nil
                rm.selectedKey = rKey
                rm.teamOffset = 0
                rm:Refresh()
                if not route.teams or #route.teams == 0 then
                    ns:ShowTeamBuilderModal(rKey, nil)
                end
            end
        end)

        local addByIdBtn = Theme:CreateActionButton(rm, 140, 30, "按 ID 或名称添加", "search-add")
        addByIdBtn:SetPoint("LEFT", addCurrentBtn, "RIGHT", 8, 0)
        addByIdBtn:SetScript("OnClick", function()
            ns:ShowQuickInputModal("ADD_TARGET_ROUTE")
        end)

        local bindTargetBtn = Theme:CreateActionButton(rm, 66, 30, "目标", "target")
        bindTargetBtn:SetPoint("LEFT", addByIdBtn, "RIGHT", 8, 0)
        bindTargetBtn:HookScript("OnEnter", function(self)
            ns:ShowCustomTooltip(self, "ANCHOR_TOP", ns:T("将当前队伍目标设为目标加载队伍"))
        end)
        local function HideBindTargetTooltip(self)
            ns:HideCustomTooltip(self)
        end
        bindTargetBtn:HookScript("OnLeave", HideBindTargetTooltip)
        bindTargetBtn:HookScript("OnHide", HideBindTargetTooltip)
        bindTargetBtn:SetScript("OnClick", function(_, button)
            if button ~= "LeftButton" then return end
            local team = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
            if not team then
                ns:PrintError("请先加载一支队伍，再设置目标。")
                return
            end
            local npcID, npcName = ns.AutoRouting:GetUnitNPCID("target")
            if not npcID and not npcName then
                ns:PrintError("请先选中一个 NPC 目标，再设置当前队伍目标。")
                return
            end
            local ok, rKey = ns:AssignTeamToTarget(team, ns:FormatTargetInput(npcID, npcName))
            if not ok then
                ns:PrintError(rKey)
                return
            end
            rm.pendingTargetID = nil
            rm.pendingTargetName = nil
            rm.selectedKey = rKey
            rm.focusedRouteKey = rKey
            rm.teamOffset = 0
            rm:Refresh()
        end)
        rm.bindTargetBtn = bindTargetBtn

        -- 3. 右侧控制栏：自动对话项切换 + 删除目标
        local delTargetBtn = Theme:CreateActionButton(rm, 94, 24, "删除", "delete", "删除目标（保留队伍）", "DANGER")
        delTargetBtn:SetPoint("TOPRIGHT", -24, -56)
        delTargetBtn:SetScript("OnClick", function()
            if not rm.selectedKey then return end
            ns:DeleteTargetRoute(rm.selectedKey)
            rm.selectedKey = nil
            rm.teamOffset = 0
            local tNpcID, tNpcName = ns.AutoRouting:GetUnitNPCID("target")
            rm.pendingTargetID = tNpcID
            rm.pendingTargetName = tNpcName
            ns:RefreshAllUI()
        end)
        rm.delTargetBtn = delTargetBtn

        local toggleGossipBtn = Theme:CreateToggleSwitch(rm, "", 40, true)
        toggleGossipBtn:SetPoint("RIGHT", delTargetBtn, "LEFT", -6, 0)
        toggleGossipBtn:RegisterForClicks("LeftButtonUp")
        if toggleGossipBtn.label then toggleGossipBtn.label:Hide() end
        if toggleGossipBtn.dividerLine then toggleGossipBtn.dividerLine:Hide() end
        toggleGossipBtn:SetState(ns.db.settings.autoGossip)
        toggleGossipBtn:SetScript("OnClick", function(self)
            ns.db.settings.autoGossip = not ns.db.settings.autoGossip
            self:SetState(ns.db.settings.autoGossip)
        end)
        toggleGossipBtn:HookScript("OnEnter", function(self)
            ns:ShowCustomTooltip(self, "ANCHOR_TOP", ns:T("开启后，NPC 对话会自动选择当前配置的对话选项。"))
        end)
        local function HideAutoGossipTooltip(self)
            ns:HideCustomTooltip(self)
        end
        toggleGossipBtn:HookScript("OnLeave", HideAutoGossipTooltip)
        toggleGossipBtn:HookScript("OnHide", HideAutoGossipTooltip)
        rm.toggleGossipBtn = toggleGossipBtn

        local gossipOptBtn = Theme:CreateActionButton(rm, 148, 24, ns:TF("对话选项：%d", 1), "gossip")
        gossipOptBtn:SetPoint("RIGHT", toggleGossipBtn, "LEFT", -2, 0)
        gossipOptBtn:SetScript("OnClick", function()
            local selRoute = rm.selectedKey and ns.db.routeMappings[rm.selectedKey]
            if selRoute then
                local gIdx = tonumber(selRoute.gossipIndex) or 1
                selRoute.gossipIndex = (gIdx % 4) + 1
                gossipOptBtn.text:SetText(ns:TF("对话选项：%d", selRoute.gossipIndex))
            end
        end)
        rm.gossipOptBtn = gossipOptBtn

        local teamReportSwitch = Theme:CreateToggleSwitch(rm, ns:T("换队信息"), 136, true)
        teamReportSwitch:SetPoint("RIGHT", gossipOptBtn, "LEFT", -6, 0)
        if teamReportSwitch.label then
            teamReportSwitch.label:ClearAllPoints()
            teamReportSwitch.label:SetPoint("LEFT", 24, 1)
            teamReportSwitch.label:SetWidth(62)
            teamReportSwitch.label:SetWordWrap(false)
        end
        if teamReportSwitch.dividerLine then teamReportSwitch.dividerLine:Hide() end
        local teamReportIcon = teamReportSwitch:CreateTexture(nil, "ARTWORK")
        teamReportIcon:SetSize(18, 18)
        teamReportIcon:SetPoint("LEFT", 2, 0)
        teamReportIcon:SetTexture(SWAP_DETAIL_ICON_PATH)
        teamReportSwitch.icon = teamReportIcon
        teamReportSwitch:SetState(ns.db.settings.battleEndTeamReport ~= false)
        teamReportSwitch:SetScript("OnClick", function(self)
            ns.db.settings.battleEndTeamReport = not ns.db.settings.battleEndTeamReport
            self:SetState(ns.db.settings.battleEndTeamReport)
        end)
        teamReportSwitch:HookScript("OnEnter", function(self)
            ns:ShowCustomTooltip(self, "ANCHOR_TOP", ns:T("战斗结束时显示换队提示并写入本地聊天框，不会发送给其他玩家。"))
        end)
        local function HideTeamReportTooltip(self)
            ns:HideCustomTooltip(self)
        end
        teamReportSwitch:HookScript("OnLeave", HideTeamReportTooltip)
        teamReportSwitch:HookScript("OnHide", HideTeamReportTooltip)
        rm.teamReportSwitch = teamReportSwitch

        -- 4. 右侧主体：复活回 1 队开关 + 当前目标下专属队伍按序出战列表
        local rightBox = CreateFrame("Frame", nil, rm, "BackdropTemplate")
        rightBox:SetSize(486, 412)
        rightBox:SetPoint("TOPRIGHT", -24, -86)
        rightBox:EnableMouseWheel(true)
        Theme:ApplyBackdrop(rightBox, Theme.Colors.bgInput, Theme.Colors.border, false)
        rm.rightBox = rightBox

        local emptyTeamTxt = rightBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        emptyTeamTxt:SetPoint("CENTER", 0, -10)
        emptyTeamTxt:SetWidth(380)
        emptyTeamTxt:SetJustifyH("CENTER")
        Theme:HookLocalizedFontString(emptyTeamTxt)
        emptyTeamTxt:SetText(LRoute(
            "该目标下暂无出战队伍\n\n可点击右下角「导入队伍」或「新建队伍」为此目标配置专属出战阵容",
            "該目標下暫無出戰隊伍\n\n可點擊右下角「匯入隊伍」或「新建隊伍」為此目標配置專屬出戰陣容",
            "No teams bound to this target.\n\nClick 'Import Teams' or 'New Team' below to configure loadouts."
        ))
        emptyTeamTxt:Hide()
        rm.emptyTeamTxt = emptyTeamTxt

        local reviveSwitch = Theme:CreateToggleSwitch(rightBox, "当「复活战斗宠物」冷却就绪时，自动切回 1号主力队", 462, true)
        reviveSwitch:SetPoint("TOPLEFT", 12, -8)
        reviveSwitch:SetScript("OnClick", function(self)
            local selRoute = rm.selectedKey and ns.db.routeMappings[rm.selectedKey]
            if selRoute then
                selRoute.reviveLoadTeam1 = (selRoute.reviveLoadTeam1 == false) and true or false
                self:SetState(selRoute.reviveLoadTeam1 ~= false)
            end
        end)
        rm.reviveSwitch = reviveSwitch

        local MAX_RIGHT_ROWS = 9

        rightBox:SetScript("OnMouseWheel", function(_, delta)
            local maxTeamOff = math.max(0, #rm.teamSnapList - MAX_RIGHT_ROWS)
            local nextOff = math.max(0, math.min(maxTeamOff, (rm.teamOffset or 0) - delta))
            if nextOff ~= rm.teamOffset then
                rm.teamOffset = nextOff
                rm:RenderRightRows()
            end
        end)

        rm.teamRows = {}
        for i = 1, MAX_RIGHT_ROWS do
            local tr = CreateFrame("Button", nil, rightBox, "BackdropTemplate")
            tr:SetSize(462, 38)
            tr:SetPoint("TOPLEFT", 12, -42 - (i - 1) * 40)
            tr:EnableMouse(true)
            tr:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            tr:RegisterForDrag("LeftButton")
            Theme:ApplyBackdrop(tr, Theme.Colors.bgCard, Theme.Colors.border, false)

            tr.text = tr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            tr.text:SetPoint("LEFT", 10, 0)
            tr.text:SetPoint("RIGHT", -218, 0)
            tr.text:SetJustifyH("LEFT")
            tr.text:SetWordWrap(false)
            Theme:HookLocalizedFontString(tr.text)

            tr.underline = tr:CreateTexture(nil, "ARTWORK")
            tr.underline:SetTexture("Interface\\Buttons\\WHITE8X8")
            tr.underline:SetVertexColor(0.10, 0.87, 1.00, 1)
            tr.underline:SetHeight(1)
            tr.underline:SetPoint("BOTTOMLEFT", tr.text, "BOTTOMLEFT", 0, -2)
            tr.underline:Hide()
            local function SyncTrUnderline()
                local tw = math.max(12, math.min(220, tr.text:GetStringWidth() or 24))
                tr.underline:SetWidth(tw)
            end
            hooksecurefunc(tr.text, "SetText", SyncTrUnderline)

            tr.statusTxt = tr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            tr.statusTxt:SetPoint("RIGHT", -162, 0)
            Theme:HookLocalizedFontString(tr.statusTxt)

            tr.petIcons = {}
            for s = 1, 3 do
                local s = s
                local pIcon = Theme:CreateCroppedIcon(tr, 26)
                pIcon:SetPoint("RIGHT", -72 - (3 - s) * 29, 1)
                pIcon:EnableMouse(true)
                pIcon:SetMouseMotionEnabled(true)
                pIcon:SetScript("OnMouseUp", function(_, button)
                    if button == "RightButton" and tr.tObj then ns:ShowSlotThresholdMenu(pIcon, s, tr.tObj) end
                end)
                pIcon:SetScript("OnEnter", ScheduleRoutePetTooltip)
                pIcon:SetScript("OnLeave", HideRoutePetTooltip)
                pIcon:SetScript("OnHide", HideRoutePetTooltip)

                pIcon.mark = pIcon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                pIcon.mark:SetPoint("CENTER")
                pIcon.levelText = pIcon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                pIcon.levelText:SetPoint("BOTTOMRIGHT", -2, 1)

                local bar = CreateFrame("StatusBar", nil, pIcon)
                bar:SetPoint("TOPLEFT", pIcon, "BOTTOMLEFT", 0, -px)
                bar:SetPoint("TOPRIGHT", pIcon, "BOTTOMRIGHT", 0, -px)
                bar:SetHeight(2 * px)
                bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                bar:SetMinMaxValues(0, 1)
                pIcon.healthBar = bar
                pIcon.healthTrack = bar:CreateTexture(nil, "BACKGROUND")
                pIcon.healthTrack:SetAllPoints()
                tr.petIcons[s] = pIcon
            end

            local delBtn = Theme:CreateFlatButton(tr, 20, 20, "×", "DANGER")
            delBtn._noUnderline = true
            delBtn:SetPoint("RIGHT", tr, "RIGHT", -6, 0)
            delBtn:SetScript("OnClick", function()
                if not tr.teamName or not rm.selectedKey then return end
                ns:RemoveTeamFromTarget(tr.teamName, rm.selectedKey)
                ns:RefreshAllUI()
            end)
            tr.delBtn = delBtn

            local upBtn = CreateFrame("Button", nil, tr)
            upBtn:SetSize(18, 18)
            upBtn:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)
            upBtn.tex = Theme:CreateArrowTexture(upBtn, 12, "UP")
            upBtn.tex:SetPoint("CENTER", 0, 0)
            upBtn.tex:SetVertexColor(0.55, 0.78, 1.0, 0.9)
            upBtn:SetScript("OnEnter", function(self) self.tex:SetVertexColor(0.0, 0.95, 1.0, 1.0) end)
            upBtn:SetScript("OnLeave", function(self) self.tex:SetVertexColor(0.55, 0.78, 1.0, 0.9) end)
            upBtn:SetScript("OnClick", function()
                if tr.realIdx and rm.selectedKey then
                    ns:MoveTeamOrderInRoute(rm.selectedKey, tr.realIdx, -1)
                end
            end)
            tr.upBtn = upBtn

            local downBtn = CreateFrame("Button", nil, tr)
            downBtn:SetSize(18, 18)
            downBtn:SetPoint("RIGHT", upBtn, "LEFT", -2, 0)
            downBtn.tex = Theme:CreateArrowTexture(downBtn, 12, "DOWN")
            downBtn.tex:SetPoint("CENTER", 0, 0)
            downBtn.tex:SetVertexColor(0.55, 0.78, 1.0, 0.9)
            downBtn:SetScript("OnEnter", function(self) self.tex:SetVertexColor(0.0, 0.95, 1.0, 1.0) end)
            downBtn:SetScript("OnLeave", function(self) self.tex:SetVertexColor(0.55, 0.78, 1.0, 0.9) end)
            downBtn:SetScript("OnClick", function()
                if tr.realIdx and rm.selectedKey then
                    ns:MoveTeamOrderInRoute(rm.selectedKey, tr.realIdx, 1)
                end
            end)
            tr.downBtn = downBtn

            local dropLine = tr:CreateTexture(nil, "OVERLAY")
            dropLine:SetHeight(2)
            dropLine:SetPoint("BOTTOMLEFT", tr, "BOTTOMLEFT", 4, 0)
            dropLine:SetPoint("BOTTOMRIGHT", tr, "BOTTOMRIGHT", -4, 0)
            dropLine:SetTexture("Interface\\Buttons\\WHITE8X8")
            dropLine:SetVertexColor(0.0, 0.90, 1.0, 1.0)
            dropLine:Hide()
            tr.dropLine = dropLine

            tr:SetScript("OnClick", function(rowBtn, button)
                if not rowBtn.teamName then return end
                if button == "RightButton" then
                    ns:ShowRouteTeamContextMenu(rowBtn, rm.selectedKey, rowBtn.teamName)
                elseif rowBtn.tObj and rowBtn.tIdx then
                    ns:RequestCompactTeamSwitch(rowBtn.tIdx)
                end
            end)

            tr:SetScript("OnDragStart", function(selfBtn)
                if not selfBtn.realIdx or not selfBtn.teamName then return end
                ns.draggingRouteTeamIdx = selfBtn.realIdx
                selfBtn:SetAlpha(0.45)
                selfBtn:SetBackdropBorderColor(0.0, 0.95, 1.0, 1.0)

                if not ns.RouteDragGhost then
                    local ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
                    ghost:SetSize(240, 28)
                    ghost:SetFrameStrata("TOOLTIP")
                    Theme:ApplyBackdrop(ghost, { 0.193, 0.193, 0.193, 0.95 }, Theme.Colors.borderBlue, true)
                    ghost.text = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    ghost.text:SetPoint("LEFT", 10, 0)
                    Theme:HookLocalizedFontString(ghost.text)
                    ns.RouteDragGhost = ghost
                end
                ns.RouteDragGhost.text:SetText(ns:T("|cff00e5ff[拖动排序]|r ") .. selfBtn.teamName)
                ns.RouteDragGhost:SetScript("OnUpdate", UpdateDragGhostPosition)
                ns.RouteDragGhost:Show()
            end)

            tr:SetScript("OnDragStop", function(selfBtn)
                selfBtn:SetAlpha(1.0)
                if ns.RouteDragGhost then
                    ns.RouteDragGhost:SetScript("OnUpdate", nil)
                    ns.RouteDragGhost:Hide()
                end
                for idx = 1, MAX_RIGHT_ROWS do
                    local row = rm.teamRows[idx]
                    if row and row.dropLine then row.dropLine:Hide() end
                end
                local selRoute = rm.selectedKey and ns.db.routeMappings[rm.selectedKey]
                local teamsInRoute = selRoute and selRoute.teams
                if ns.draggingRouteTeamIdx and ns.hoverRouteTeamIdx and ns.draggingRouteTeamIdx ~= ns.hoverRouteTeamIdx and teamsInRoute then
                    local movingItem = table.remove(teamsInRoute, ns.draggingRouteTeamIdx)
                    if movingItem then
                        table.insert(teamsInRoute, ns.hoverRouteTeamIdx, movingItem)
                        selRoute.teamName = teamsInRoute[1] or ""
                        if ns.MarkRoutesDirty then ns:MarkRoutesDirty() end
                        ns.db.lastActiveRouteKey = rm.selectedKey
                        ns.AutoRouting:LoadTeamWithFallbackChain(selRoute.teams[1], selRoute, true)
                        if ns.RefreshAllUI then ns:RefreshAllUI() end
                    end
                end
                ns.draggingRouteTeamIdx = nil
                ns.hoverRouteTeamIdx = nil
            end)

            tr:SetScript("OnEnter", function(selfBtn)
                SyncTrUnderline()
                selfBtn.underline:Show()
                if ns.draggingRouteTeamIdx and selfBtn.realIdx and ns.draggingRouteTeamIdx ~= selfBtn.realIdx then
                    ns.hoverRouteTeamIdx = selfBtn.realIdx
                    if selfBtn.dropLine then selfBtn.dropLine:Show() end
                    selfBtn:SetBackdropBorderColor(0.0, 0.95, 1.0, 1.0)
                end
            end)

            tr:SetScript("OnLeave", function(selfBtn)
                selfBtn.underline:Hide()
                if selfBtn.dropLine then selfBtn.dropLine:Hide() end
                if selfBtn.isCurActive then
                    selfBtn:SetBackdropBorderColor(unpack(Theme.Colors.borderBlue))
                else
                    selfBtn:SetBackdropBorderColor(unpack(Theme.Colors.border))
                end
            end)

            rm.teamRows[i] = tr
        end

        -- 5. 右侧底部：导入队伍 | 导出目标队伍 | 新建队伍
        local importTeamBtn = Theme:CreateActionButton(rm, 118, 30, "导入", "import", "导入队伍并关联到当前目标")
        importTeamBtn:SetPoint("BOTTOMLEFT", 350, 16)
        importTeamBtn:SetScript("OnClick", function()
            ns:ShowImportModal("TEAM")
        end)
        rm.importTeamBtn = importTeamBtn

        local exportTeamBtn = Theme:CreateActionButton(rm, 130, 30, "导出", "export", "导出当前目标的队伍或对战脚本")
        exportTeamBtn:SetPoint("LEFT", importTeamBtn, "RIGHT", 8, 0)
        exportTeamBtn:SetScript("OnClick", function()
            local selRoute = rm.selectedKey and ns.db and ns.db.routeMappings and ns.db.routeMappings[rm.selectedKey]
            if not selRoute then
                ns:PrintError(LRoute("当前未绑定目标，暂无可导出的目标队伍！", "當前未綁定目標，暫無可匯出的目標隊伍！", "No bound target to export!"))
                return
            end
            ns:ShowExportChoiceModal({
                routeKey = rm.selectedKey,
                routeLabel = (selRoute.npcName and selRoute.npcName ~= "") and selRoute.npcName or tostring(rm.selectedKey),
            })
        end)
        rm.exportTeamBtn = exportTeamBtn

        local createTeamBtn = Theme:CreateActionButton(rm, 152, 30, "新建队伍", "new-team", nil, "PRIMARY")
        createTeamBtn:SetPoint("BOTTOMRIGHT", -24, 16)
        createTeamBtn:SetScript("OnClick", function()
            local targetKey = rm.selectedKey
            if not targetKey and (rm.pendingTargetID or rm.pendingTargetName) then
                local route, rKey = ns:EnsureTargetRoute(rm.pendingTargetID, rm.pendingTargetName)
                if route and rKey then
                    rm.pendingTargetID = nil
                    rm.pendingTargetName = nil
                    rm.selectedKey = rKey
                    rm:Refresh()
                    targetKey = rKey
                end
            end
            ns:ShowTeamBuilderModal(targetKey, nil)
        end)
        rm.createTeamBtn = createTeamBtn

        function rm:RefreshTopControls()
            if self.hotkeyBtn then
                self.hotkeyBtn.text:SetText(ns:TF("战斗键：%s", "|cff38bdf8" .. ns:FormatHotKeyDisplay() .. "|r"))
            end
            if self.toggleLoadBtn then
                self.toggleLoadBtn.text:SetText(ns.db.settings.autoLoadTarget and "|cff10b981自动换队：开启|r" or "|cff6b7280自动换队：关闭|r")
            end
            if self.toggleGossipBtn then
                self.toggleGossipBtn:SetState(ns.db.settings.autoGossip)
            end
            if self.teamReportSwitch then
                self.teamReportSwitch:SetState(ns.db.settings.battleEndTeamReport ~= false)
            end
        end

        function rm:FocusCurrentTeamRoute(preferTeam)
            ns.AutoRouting:SyncTargetGroups()
            self.pendingTargetID = nil
            self.pendingTargetName = nil
            self.teamOffset = 0

            local tNpcID, tNpcName = ns.AutoRouting:GetUnitNPCID("target")
            if not preferTeam and (tNpcID or tNpcName) then
                local matchedRoute, matchedKey = ns.AutoRouting:FindRouteForTarget(tNpcID, tNpcName)
                if matchedRoute and matchedKey then
                    self.focusedRouteKey = matchedKey
                    self.selectedKey = matchedKey
                else
                    self.focusedRouteKey = nil
                    self.selectedKey = nil
                    self.pendingTargetID = tNpcID
                    self.pendingTargetName = tNpcName
                end
                return
            end

            local curTeam = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
            local matchedRoute, matchedKey = nil, nil
            if curTeam then
                matchedRoute, matchedKey = ns:FindExistingRouteForNPC(curTeam.npcID, curTeam.npcName)
                if not matchedRoute then
                    matchedRoute, matchedKey = ns:FindRouteContainingTeam(curTeam.name)
                end
            end

            self.focusedRouteKey = matchedKey
            self.selectedKey = matchedKey
        end

        function rm:RebuildRightSnapshot()
            local selRoute = self.selectedKey and ns.db.routeMappings and ns.db.routeMappings[self.selectedKey]
            local curSelectedTeam = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]

            if selRoute then
                self.delTargetBtn:Show()
                self.gossipOptBtn:Show()
                self.toggleGossipBtn:Show()
                self.teamReportSwitch:Show()
                self.reviveSwitch:Show()
                self.reviveSwitch:SetState(selRoute.reviveLoadTeam1 ~= false)

                local gIdx = tonumber(selRoute.gossipIndex) or 1
                self.gossipOptBtn.text:SetText(ns:TF("对话选项：%d", gIdx))
            elseif self.pendingTargetName or self.pendingTargetID then
                self.delTargetBtn:Hide()
                self.gossipOptBtn:Hide()
                self.toggleGossipBtn:Hide()
                self.teamReportSwitch:Hide()
                self.reviveSwitch:Hide()
            else
                self.delTargetBtn:Hide()
                self.gossipOptBtn:Hide()
                self.toggleGossipBtn:Hide()
                self.teamReportSwitch:Hide()
                self.reviveSwitch:Hide()
            end

            local snaps = self.teamSnapList
            local snapPool = self.teamSnapPool
            if not snapPool then
                snapPool = {}
                self.teamSnapPool = snapPool
            end
            wipe(snaps)
            local teamsInRoute = (selRoute and selRoute.teams) or EMPTY_LIST
            for idx = 1, #teamsInRoute do
                local teamName = teamsInRoute[idx]
                local tObj, tIdx = ns.AutoRouting:FindTeamByName(teamName)
                local entry = snapPool[idx]
                if not entry then
                    entry = {}
                    snapPool[idx] = entry
                end
                entry.teamName    = teamName
                entry.tObj        = tObj
                entry.tIdx        = tIdx
                entry.isCurActive = (curSelectedTeam ~= nil and curSelectedTeam.name == teamName)
                snaps[idx] = entry
            end

            self.emptyTeamTxt:SetShown(selRoute ~= nil and #snaps == 0)
        end

        function rm:RenderLeftRows()
            local routesList = self.routesList
            for i = 1, MAX_LEFT_ROWS do
                local lr = self.leftRows[i]
                local item = routesList[i]
                if item then
                    lr:Show()
                    lr.routeKey = item.key
                    lr:SetSelected(true)
                    local label = item.route.npcName or tostring(item.key)
                    local idTag = (item.route.npcID and item.route.npcID > 0 and label ~= tostring(item.route.npcID))
                        and string.format("|cff38bdf8#%d|r ", item.route.npcID) or ""
                    local tCnt = item.route.teams and #item.route.teams or 0
                    lr.text:SetText(idTag .. label .. " |cff6b7280" .. ns:TF("(%d队)", tCnt) .. "|r")
                else
                    lr.routeKey = nil
                    lr:Hide()
                end
            end
        end

        function rm:RenderRightRows()
            local snaps = self.teamSnapList
            local totalTeams = #snaps
            local maxTeamOff = math.max(0, totalTeams - MAX_RIGHT_ROWS)
            if (self.teamOffset or 0) > maxTeamOff then self.teamOffset = maxTeamOff end

            local activeBadge = ns:T("[当前]")
            local cache = totalTeams > 0 and ns:GetPetJournalCache()
            local evaluation = self._evalScratch
            if not evaluation then
                evaluation = {}
                self._evalScratch = evaluation
            else
                wipe(evaluation)
            end

            for i = 1, MAX_RIGHT_ROWS do
                local tr = self.teamRows[i]
                local realIdx = (self.teamOffset or 0) + i
                local snap = snaps[realIdx]
                if snap then
                    tr:Show()
                    tr.realIdx     = realIdx
                    tr.teamName    = snap.teamName
                    tr.tObj        = snap.tObj
                    tr.tIdx        = snap.tIdx
                    tr.isCurActive = snap.isCurActive

                    if snap.isCurActive then
                        Theme:ApplyBackdrop(tr, Theme.Colors.bgCardActive, Theme.Colors.borderBlue, false)
                        tr.text:SetText(string.format("|cff10b981%d. %s|r |cffffffff%s|r", realIdx, activeBadge, snap.teamName))
                    else
                        Theme:ApplyBackdrop(tr, Theme.Colors.bgCard, Theme.Colors.border, false)
                        tr.text:SetText(string.format("|cffffffff%d.|r %s", realIdx, snap.teamName))
                    end

                    local status = "|cff6b7280● 未知|r"
                    if snap.tObj then
                        local ready = ns.AutoRouting:CanTeamFight(snap.tObj, true, evaluation)
                        status = ready and "|cff10b981● 就绪|r" or "|cffffb800● 未就绪|r"
                    end
                    tr.statusTxt:SetText(status)

                    for s = 1, 3 do
                        local pIcon = tr.petIcons[s]
                        if snap.tObj then
                            local texture, petID, petName, missing, level, petType, speciesID = GetRoutePetSlot(snap.tObj, s, cache)
                            local abilities = snap.tObj.abilities and snap.tObj.abilities[s]
                            RenderRoutePetIcon(pIcon, texture, petID, petName, missing, level, petType, speciesID, abilities)
                        else
                            pIcon:Hide()
                        end
                    end

                    local isFirst = (realIdx == 1)
                    local isLast  = (realIdx == totalTeams)
                    tr.upBtn:SetAlpha(isFirst and 0.25 or 1.0)
                    tr.upBtn:SetEnabled(not isFirst)
                    tr.downBtn:SetAlpha(isLast and 0.25 or 1.0)
                    tr.downBtn:SetEnabled(not isLast)
                else
                    tr.realIdx  = nil
                    tr.teamName = nil
                    tr.tObj     = nil
                    tr.tIdx     = nil
                    tr:Hide()
                end
            end
        end

        function rm:Refresh()
            ns.AutoRouting:SyncTargetGroups()
            self:RefreshTopControls()

            local routesList = self.routesList
            wipe(routesList)

            local selRoute = self.selectedKey and ns.db and ns.db.routeMappings and ns.db.routeMappings[self.selectedKey] or nil
            if selRoute then
                local item = self._singleRouteItem
                if not item then
                    item = {}
                    self._singleRouteItem = item
                end
                item.key = self.selectedKey
                item.route = selRoute
                routesList[1] = item
            else
                self.selectedKey = nil
            end

            if #routesList == 0 then
                if self.pendingTargetName or self.pendingTargetID then
                    local pLabel = self.pendingTargetName or ("NPC #" .. tostring(self.pendingTargetID))
                    if self.pendingTargetID and self.pendingTargetID > 0 and self.pendingTargetName then
                        pLabel = string.format("#%d %s", self.pendingTargetID, self.pendingTargetName)
                    end
                    self.emptyTargetTxt:SetText(string.format(LRoute(
                        "当前选中目标 [%s]\n暂未配置队伍\n\n点击下方「+ 添加当前目标」、「导入队伍」或「新建队伍」即可为其配置专属队伍",
                        "當前選中目標 [%s]\n暫無配置隊伍\n\n點擊下方「+ 新增當前目標」、「匯入隊伍」或「新建隊伍」即可為其配置專屬隊伍",
                        "Selected target [%s]\nhas no teams yet.\n\nClick '+ Add Target', 'Import Teams', or 'New Team' below."
                    ), pLabel))
                else
                    self.emptyTargetTxt:SetText(ns:T("当前激活队伍暂未绑定目标\n\n可点击下方按钮将当前选中 NPC 或指定 ID/名称绑定至本队伍"))
                end
                self.emptyTargetTxt:Show()
            else
                self.emptyTargetTxt:Hide()
            end

            self:RebuildRightSnapshot()
            self:RenderLeftRows()
            self:RenderRightRows()
        end

        ns.RoutingModal = rm
        ns:BindHeaderHubPanel(rm)
    end

    local routing = ns.RoutingModal
    if routing:GetParent() ~= parent then routing:SetParent(parent) end
    self:MatchMainUIScale(routing)
    routing:FocusCurrentTeamRoute(preferTeam)
    routing:Refresh()
    routing:Show()
    if ns.BringModalToFront then ns:BringModalToFront(routing) end
end
