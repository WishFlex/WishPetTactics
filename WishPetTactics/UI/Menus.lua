local ADDON_NAME, ns = ...
local Theme = ns.Theme

local BUILDER_BG_LV    = { 0.12, 0.09, 0.03, 0.95 }
local BUILDER_BG_PET   = { 0.123, 0.123, 0.123, 0.96 }
local BUILDER_BG_EMPTY = { 0.09, 0.09, 0.09, 0.92 }

-- 右键菜单使用独立的描边，避免覆盖行的悬停和选中状态。
local function ShowAnchoredContextMenu(menu, anchorRow, isSameTarget, belowAnchor)
    local outline = anchorRow.contextMenuOutline
    if not outline then
        outline = CreateFrame("Frame", nil, anchorRow)
        outline:SetAllPoints(anchorRow)
        outline:SetFrameLevel(anchorRow:GetFrameLevel() + 1)
        outline:EnableMouse(false)
        Theme:ApplyBackdrop(outline, { 0, 0, 0, 0 }, { 1.0, 0.75, 0.25, 1 }, false)
        anchorRow.contextMenuOutline = outline
    end

    if not menu.contextOutlineHooked then
        menu:HookScript("OnHide", function(self)
            if self.contextOutline then
                self.contextOutline:Hide()
                self.contextOutline = nil
            end
            self:SetScript("OnUpdate", nil)
        end)
        menu.contextOutlineHooked = true
    end

    menu.contextOutline = outline
    menu._anchorRow = anchorRow
    menu._isSameTarget = isSameTarget
    if not ns._AnchoredMenuOnUpdate then
        ns._AnchoredMenuOnUpdate = function(self)
            local row = self._anchorRow
            local check = self._isSameTarget
            if not row or not row:IsVisible() or (check and not check()) then
                self:Hide()
            end
        end
    end
    menu:SetScript("OnUpdate", ns._AnchoredMenuOnUpdate)
    menu:ClearAllPoints()
    if belowAnchor then
        menu:SetPoint("TOPRIGHT", anchorRow, "BOTTOMRIGHT", 0, -5)
    else
        menu:SetPoint("TOPLEFT", anchorRow, "TOPRIGHT", 4, 0)
    end
    outline:Hide()
    menu:Show()
    ns:EnablePopupClickCatcher(menu)
end

local function LMenu(zhCN, zhTW, enUS)
    if ns.locale == "zhTW" then return zhTW end
    if ns.locale ~= "zhCN" then return enUS end
    return zhCN
end

-- 统一刷新右侧宠物/练级队列抽屉与主监控舱
local function RefreshPetDrawerAndUI(resetScroll)
    if ns.PetPickerModal and ns.PetPickerModal:IsShown() then
        if resetScroll then ns.PetPickerModal.offset = 0 end
        if ns.PetPickerModal.Refresh then ns.PetPickerModal:Refresh() end
    end
    if ns.MainFrame and ns.MainFrame.minimalPicker and ns.MainFrame.minimalPicker:IsShown() then
        if resetScroll then ns.MainFrame.minimalPicker.page = 0 end
        ns:RefreshMinimalPicker()
    end
    if ns.RefreshLoadoutCabin then ns:RefreshLoadoutCabin() end
end

local function RefreshAfterFavoriteToggle()
    if ns.InvalidatePetAndTeamCache then ns:InvalidatePetAndTeamCache() end
    RefreshPetDrawerAndUI(false)
end

local function GetPetFilterState()
    if ns.db and type(ns.db.petFilterState) == "table" then
        ns.petFilterState = ns.db.petFilterState
        return ns.db.petFilterState
    end
    return ns.petFilterState
end

local function GetQueueFilterState()
    if ns.db and type(ns.db.queueFilterState) == "table" then
        ns.queueFilterState = ns.db.queueFilterState
        return ns.db.queueFilterState
    end
    return ns.queueFilterState
end

local function MarkTreeAndRoutesDirty()
    if ns.MarkRoutesDirty then
        ns:MarkRoutesDirty()
    elseif ns.TeamMatrixModal then
        ns.TeamMatrixModal._treeDirty = true
    end
end

local function AnchorSubMenuSmart(parentMenu, parentRow, subMenu, subWidth)
    local screenW = UIParent:GetRight() or GetScreenWidth() or 1920
    local pScale = parentMenu:GetEffectiveScale() or 1
    local uScale = UIParent:GetEffectiveScale() or 1
    local menuRight = (parentMenu:GetRight() or 0) * (pScale / uScale)

    subMenu:ClearAllPoints()
    if (menuRight + (subWidth or 184) + 10) > screenW then
        subMenu:SetPoint("TOPRIGHT", parentRow, "TOPLEFT", -3, 0)
    else
        subMenu:SetPoint("TOPLEFT", parentRow, "TOPRIGHT", 3, 0)
    end
end

local function OpenTeamStringExportModal(teamObj, teamIdx, overrideNpcID)
    if not teamObj then return end
    local isCur = (teamIdx ~= nil and ns.db and teamIdx == ns.db.selectedTeamIdx)
    local exportStr = ns:ExportSingleTeamString(teamObj, isCur, overrideNpcID)
    local tName = teamObj.name or ns:T("未命名队伍")
    local msg = string.format(LMenu(
        "|cff10b981已导出队伍 [%s] 字符串(含目标与脚本)，按 Ctrl+C 复制|r",
        "|cff10b981已匯出隊伍 [%s] 字串(含目標與腳本)，按 Ctrl+C 複製|r",
        "|cff10b981Exported team [%s] (with target & script). Press Ctrl+C to copy.|r"
    ), tName)
    ns:ShowExportModalWithText(exportStr, msg, "TEAM")
end

local function OpenTeamScriptExportModal(teamObj)
    if not teamObj then return end
    local scriptStr = ns:ExportSingleTeamScript(teamObj)
    if not scriptStr or scriptStr == "" then
        ns:PrintError(LMenu("该队伍暂无对战脚本可导出！", "該隊伍暫無對戰腳本可匯出！", "This team has no battle script to export!"))
        return
    end
    local tName = teamObj.name or ns:T("未命名队伍")
    local msg = string.format(LMenu(
        "|cff10b981已单独导出队伍 [%s] 的纯对战脚本，按 Ctrl+C 复制|r",
        "|cff10b981已單獨匯出隊伍 [%s] 的純對戰腳本，按 Ctrl+C 複製|r",
        "|cff10b981Exported battle script for [%s]. Press Ctrl+C to copy.|r"
    ), tName)
    ns:ShowExportModalWithText(scriptStr, msg, "SCRIPT")
end

-- ==================== 0.1 极简「新建分组 / 新建队伍 / 手动输入目标」快速弹窗（静态事件绑定） ====================
function ns:ShowQuickInputModal(mode, defaultGroup)
    local f = self.MainFrame
    if mode == "NEW_TEAM" and f and f:IsShown() and (f.compactDraft or self.staging.isDirty) then
        self:RequestHomeAction(function() self:ShowQuickInputModal(mode, defaultGroup) end)
        return
    end
    self:HideAllPopups()
    if not ns.QuickInputModal then
        local m = CreateFrame("Frame", "WishPetTacticsQuickInputModal", ns.MainFrame or UIParent, "BackdropTemplate")
        m:SetSize(360, 145)
        m:SetPoint("CENTER")
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(185)
        Theme:ApplyBackdrop(m, Theme.Colors.bgPopup, Theme.Colors.border, true)
        if ns.MakeModal then ns:MakeModal(m) end
        Theme:EnableDialogDrag(m)

        m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        m.title:SetPoint("TOPLEFT", 16, -14)
        Theme:HookLocalizedFontString(m.title)

        m.box = Theme:CreateFlatEditBox(m, 328, 28, "")
        m.box:SetPoint("TOPLEFT", 16, -46)

        local cancelBtn = Theme:CreateFlatButton(m, 80, 26, "取消")
        cancelBtn:SetPoint("BOTTOMRIGHT", -16, 14)
        cancelBtn:SetScript("OnClick", function() m:Hide() end)

        m.okBtn = Theme:CreateActionButton(m, 96, 26, "创建", "new-team", nil, "PRIMARY")
        m.okBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -8, 0)
        m.okBtn:SetScript("OnClick", function()
            local curMode = m.currentMode
            if curMode == "NEW_GROUP" then
                local gName = strtrim(m.box:GetText() or "")
                if gName ~= "" then
                    ns:EnsureTeamGroup(gName)
                    ns.teamFilterState.group = gName
                    if ns.db.expandedMatrixGroups then
                        ns.db.expandedMatrixGroups[gName] = true
                    end
                    MarkTreeAndRoutesDirty()
                    m:Hide()
                    ns:RefreshAllUI()
                end
            elseif curMode == "ADD_TARGET_ROUTE" then
                local rawInput = strtrim(m.box:GetText() or "")
                if rawInput == "" then
                    ns:PrintError("请输入有效的 NPC ID 或 NPC 名称！")
                    return
                end
                local route, rKey = ns:EnsureTargetRouteFromInput(rawInput)
                if route and rKey then
                    m:Hide()
                    if ns.RoutingModal then
                        ns.RoutingModal.pendingTargetID = nil
                        ns.RoutingModal.pendingTargetName = nil
                        ns.RoutingModal.selectedKey = rKey
                        ns.RoutingModal.teamOffset = 0
                        ns.RoutingModal:Show()
                        ns.RoutingModal:Refresh()
                    end
                    ns:RefreshAllUI()
                    if not route.teams or #route.teams == 0 then
                        ns:ShowTeamBuilderModal(rKey, nil)
                    end
                end
            else
                local targetGrp = m.targetGrp or "未分组队伍"
                local tName = strtrim(m.box:GetText() or "")
                if tName == "" then tName = ns:T("新建队伍 #") .. (#ns.db.teams + 1) end

                local mNpcID, mNpcName, mGroup = ns:FindExistingTargetInfoForImport(0, tName, nil)
                local finalGrp = (mGroup and mGroup ~= "") and mGroup or targetGrp

                local newTeam = {
                    name            = ns:GetUniqueTeamNameForImport(tName),
                    group           = ns:EnsureTeamGroup(finalGrp),
                    npcID           = mNpcID or 0,
                    npcName         = mNpcName or "",
                    gossipIndex     = 1,
                    pets            = { nil, nil, nil },
                    speciesLoadout  = { 0, 0, 0 },
                    abilities       = { {0,0,0}, {0,0,0}, {0,0,0} },
                    slotThresholds  = { [1] = 0, [2] = 0, [3] = 0 },
                    hasLevelingSlot = false,
                    levelingSlot    = 2,
                    script          = ns:GetDefaultBattleScript(),
                }
                for s = 1, 3 do
                    local petID, a1, a2, a3 = C_PetJournal.GetPetLoadOutInfo(s)
                    local spID = petID and C_PetJournal.GetPetInfoByPetID(petID) or 0
                    newTeam.pets[s] = petID
                    newTeam.speciesLoadout[s] = spID
                    newTeam.abilities[s] = ns.AutoRouting:ValidateAbilitiesForSpecies(spID, { a1 or 0, a2 or 0, a3 or 0 })
                end
                table.insert(ns.db.teams, newTeam)
                ns.db.selectedTeamIdx = #ns.db.teams
                ns.staging.isDirty = false
                MarkTreeAndRoutesDirty()

                if (newTeam.npcID and newTeam.npcID > 0) or (newTeam.npcName and newTeam.npcName ~= "") then
                    local tInput = (newTeam.npcID and newTeam.npcID > 0) and (tostring(newTeam.npcID) .. " " .. (newTeam.npcName or "")) or newTeam.npcName
                    ns:AssignTeamToTarget(newTeam, tInput, nil)
                end

                if ns.db.expandedMatrixGroups then
                    ns.db.expandedMatrixGroups[newTeam.group] = true
                end
                m:Hide()
                ns:RefreshAllUI()
            end
        end)

        m.box:SetScript("OnEnterPressed", function() m.okBtn:Click() end)
        ns.QuickInputModal = m
    end

    local m = ns.QuickInputModal
    m:SetParent(ns:GetRoutingDialogParent())
    m.currentMode = mode
    if mode == "NEW_GROUP" then
        m.title:SetText(ns:T("新建队伍分组"))
        m.box:SetText("")
        m.box.placeholder:SetText(ns:T("输入新的分组名称..."))
        m.box.placeholder:Show()
        m.okBtn.text:SetText(ns:T("创建"))
    elseif mode == "ADD_TARGET_ROUTE" then
        m.title:SetText(ns:T("添加目标（NPC ID 或名称）"))
        m.box:SetText("")
        m.box.placeholder:SetText(ns:T("例如: 172542 斯特兰 或 奥多格..."))
        m.box.placeholder:Show()
        m.okBtn.text:SetText(ns:T("确认添加"))
    else
        local targetGrp = defaultGroup or (ns.teamFilterState.group ~= "ALL" and ns.teamFilterState.group) or "未分组队伍"
        m.targetGrp = targetGrp
        m.title:SetText(ns:TF("在“%s”分组中新建队伍", targetGrp))
        m.box:SetText(ns:T("新建队伍 #") .. (#ns.db.teams + 1))
        m.box.placeholder:Hide()
        m.okBtn.text:SetText(ns:T("创建"))
    end

    m:Show()
    if ns.BringModalToFront then ns:BringModalToFront(m) end
    m.box:HighlightText()
    m.box:SetFocus()
end


-- A shared confirmation also counts scripts, drafts and target references.
local function RequestDestructiveDelete(teams, action)
    if InCombatLockdown() or (C_PetBattles and C_PetBattles.IsInBattle()) then
        ns:PrintError(ns:UXText("deleteInBattle"))
        return
    end
    local scriptCount, draftCount, routeCount, names = 0, 0, 0, {}
    local snapshots = {}
    for i, team in ipairs(teams) do
        snapshots[i] = {name=team.name, group=team.group, script=team.script,
            draft=ns.HasScriptDraft and ns:HasScriptDraft(team) or false}
        names[team.name] = true
        if team.script and team.script ~= "" then scriptCount = scriptCount + 1 end
        if ns.HasScriptDraft and ns:HasScriptDraft(team) then draftCount = draftCount + 1 end
    end
    for _, route in pairs((ns.db and ns.db.routeMappings) or {}) do
        for _, name in ipairs(route.teams or {}) do
            if names[name] then routeCount = routeCount + 1; break end
        end
    end
    local function ShowConfirmation()
        if not StaticPopupDialogs or not StaticPopup_Show then return end
        StaticPopupDialogs.WPT_CONFIRM_DELETE = {
            text = "%s", button1 = DELETE or YES, button2 = CANCEL or NO,
            timeout = 0, whileDead = true, hideOnEscape = true,
            OnAccept = function(_, data)
                if not data then return end
                if InCombatLockdown() or (C_PetBattles and C_PetBattles.IsInBattle()) then
                    ns:PrintError(ns:UXText("deleteInBattle")); return
                end
                -- Do not delete a newly replaced team under a stale confirmation.
                for i, expected in ipairs(data.teams) do
                    local saved = data.snapshots[i]
                    local draft = ns.HasScriptDraft and ns:HasScriptDraft(expected) or false
                    if expected.name ~= saved.name or expected.group ~= saved.group or expected.script ~= saved.script or draft ~= saved.draft then
                        ns:PrintError(ns:UXText("previewChanged")); return
                    end
                    local found = false
                    for _, current in ipairs((ns.db and ns.db.teams) or {}) do
                        if current == expected then found = true; break end
                    end
                    if not found then ns:PrintError(ns:UXText("previewChanged")); return end
                end
                data.action()
            end,
        }
        local message = ns:UXText("deleteDetails", #teams, scriptCount, routeCount, draftCount)
        StaticPopup_Show("WPT_CONFIRM_DELETE", message, nil, {teams=teams, snapshots=snapshots, action=action})
    end
    if ns.RequestHomeAction then ns:RequestHomeAction(ShowConfirmation) else ShowConfirmation() end
end


local function RequestGroupDeletion(groupName, deleteTeams)
    local teams, expected = {}, {}
    for _, team in ipairs(ns.db.teams or {}) do
        if (team.group or "未分组队伍") == groupName then
            teams[#teams + 1] = team
            expected[team] = true
        end
    end
    RequestDestructiveDelete(teams, function()
        local count = 0
        for _, team in ipairs(ns.db.teams or {}) do
            if (team.group or "未分组队伍") == groupName then
                count = count + 1
                if not expected[team] then ns:PrintError(ns:UXText("previewChanged")); return end
            end
        end
        if count ~= #teams then ns:PrintError(ns:UXText("previewChanged")); return end
        ns:DeleteTeamGroupAndTeams(groupName, deleteTeams)
    end)
end

-- ==================== 0.3 队伍管理矩阵分组右键菜单（支持导出分组全部队伍+脚本+目标） ====================
function ns:ShowMatrixGroupContextMenu(anchorRow, groupName)
    if not groupName then return end
    self:HideAllPopups()

    if not ns.MatrixGroupContextMenu then
        local gm = CreateFrame("Frame", "WishPetTacticsMatrixGroupContextMenu", UIParent, "BackdropTemplate")
        gm:SetSize(244, 128)
        gm:SetFrameStrata("FULLSCREEN_DIALOG")
        gm:SetFrameLevel(185)
        gm:SetClampedToScreen(true)
        gm:EnableMouse(true)
        Theme:ApplyBackdrop(gm, Theme.Colors.bgPopup, Theme.Colors.border, true)
        gm.items = {}

        for i = 1, 6 do
            local item = Theme:CreateMenuRow(gm, 236, 24, "")
            item:SetPoint("TOPLEFT", 4, -4 - ((i - 1) * 24))
            item:SetScript("OnClick", function(selfBtn)
                local act = selfBtn.actionID
                local gName = gm.groupName
                ns:HideAllPopups()
                if act == "NEW_TEAM" and gName then
                    ns:ShowTeamBuilderModal(nil, gName)
                elseif act == "QUEUE_GROUP" and gName then
                    ns:EnqueueGroupPets(gName)
                elseif act == "EXPORT_GROUP" and gName then
                    local exportStr, cnt = ns:ExportGroupTeamsString(gName)
                    if not exportStr or exportStr == "" or (cnt or 0) <= 0 then
                        ns:PrintError(LMenu("该分组下暂无可导出的队伍！", "該分組下暫無可匯出的隊伍！", "No teams in this group to export!"))
                        return
                    end
                    local dispGrp = ns:T(gName)
                    local msg = string.format(LMenu(
                        "|cff10b981已导出分组 [%s] 下全部 %d 支队伍(含目标与脚本)，按 Ctrl+C 复制|r",
                        "|cff10b981已匯出分組 [%s] 下全部 %d 支隊伍(含目標與腳本)，按 Ctrl+C 複製|r",
                        "|cff10b981Exported %d team(s) in group [%s] (with targets & scripts). Press Ctrl+C to copy.|r"
                    ), (ns.locale ~= "zhCN" and ns.locale ~= "zhTW") and cnt or dispGrp, (ns.locale ~= "zhCN" and ns.locale ~= "zhTW") and dispGrp or cnt)
                    ns:ShowExportModalWithText(exportStr, msg, "TEAM")
                elseif act == "DEL_ONLY" and gName then
                    RequestGroupDeletion(gName, false)
                elseif act == "DEL_ALL" and gName then
                    RequestGroupDeletion(gName, true)
                end
            end)
            gm.items[i] = item
        end
        ns.MatrixGroupContextMenu = gm
    end

    local gm = ns.MatrixGroupContextMenu
    gm.groupName = groupName
    if ns.MainFrame then
        gm:SetScale(ns.MainFrame:GetEffectiveScale() / UIParent:GetEffectiveScale())
    end

    local row1 = gm.items[1]
    row1.actionID = "NEW_TEAM"
    row1.text:SetText(ns:T("|cff38bdf8在此分组中新建队伍|r"))
    row1:SetSelected(false)
    row1:Show()

    local row2 = gm.items[2]
    row2.actionID = "EXPORT_GROUP"
    row2.text:SetText(ns:T("|cff10b981导出分组队伍（含脚本）|r"))
    row2:SetSelected(false)
    row2:Show()

    if groupName ~= "未分组队伍" then
        local row3 = gm.items[3]
        row3.actionID = "DEL_ONLY"
        row3.text:SetText(ns:T("删除分组（保留队伍）"))
        row3:SetSelected(false)
        row3:Show()

        local row4 = gm.items[4]
        row4.actionID = "DEL_ALL"
        row4.text:SetText(ns:T("|cffff4d4d删除分组及全部队伍|r"))
        row4:SetSelected(false)
        row4:Show()

        local row5 = gm.items[5]
        row5.actionID = "CANCEL"
        row5.text:SetText(ns:T("取消"))
        row5:SetSelected(false)
        row5:Show()
        gm:SetHeight(5 * 24 + 8)
    else
        local row3 = gm.items[3]
        row3.actionID = "CANCEL"
        row3.text:SetText(ns:T("取消"))
        row3:SetSelected(false)
        row3:Show()
        gm.items[4]:Hide()
        gm.items[5]:Hide()
        gm:SetHeight(3 * 24 + 8)
    end

    gm.items[6].actionID = "QUEUE_GROUP"
    gm.items[6].text:SetText(ns:ForumText("将本组未满级宠物加入队列", "將本組未滿級寵物加入佇列", "Queue this group's under-level pets"))
    gm.items[6]:ClearAllPoints()
    gm.items[6]:SetPoint("TOPLEFT", 4, -(gm:GetHeight() - 4))
    gm.items[6]:Show()
    gm:SetHeight(gm:GetHeight() + 24)
    ShowAnchoredContextMenu(gm, anchorRow, function()
        local node = anchorRow.node
        return node and node.nodeType == "GROUP" and node.groupName == groupName
    end)
end

function ns:FormatTargetInput(npcID, npcName)
    npcID = tonumber(npcID) or 0
    npcName = npcName or ""
    if npcID <= 0 then return npcName end
    if npcName == "" or npcName == tostring(npcID) then return tostring(npcID) end
    return npcID .. " " .. npcName
end

-- Display labels omit the editable input's ID/name prefix. Keep a known ID
-- only as a fallback when the target name has not been recorded yet.
function ns:GetTargetDisplayName(npcID, npcName)
    local name = type(npcName) == "string" and strtrim(npcName) or ""
    if name ~= "" then return name end
    local id = tonumber(npcID) or 0
    return id > 0 and tostring(id) or self:T("未绑定目标")
end

local function GetCurrentTargetInput()
    local npcID, npcName = ns.AutoRouting:GetManualTargetNPCID()
    return ns:FormatTargetInput(npcID, npcName)
end

local function ReportMissingCurrentTarget()
    ns:PrintError("无法读取目标 NPC 的名称或 ID。若已选中 NPC，请在输入框手动填写名称或 ID。")
end

-- ==================== 0.5 队伍更改所属目标弹窗 ====================
function ns:ShowChangeTeamTargetModal(teamObj, sourceRouteKey)
    if not teamObj then return end
    self:HideAllPopups()

    if not ns.ChangeTargetModal then
        local m = CreateFrame("Frame", "WishPetTacticsChangeTargetModal", ns.MainFrame or UIParent, "BackdropTemplate")
        m:Hide()
        m:SetSize(420, 104)
        m:SetPoint("CENTER")
        tinsert(UISpecialFrames, m:GetName())
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(185)
        Theme:ApplyBackdrop(m, Theme.Colors.bgPopup, Theme.Colors.border, true)
        if ns.MakeModal then ns:MakeModal(m) end
        Theme:EnableDialogDrag(m)

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("RIGHT", -48, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        m.title = title

        local close = Theme:CreateCloseIconButton(m, function() m:Hide() end)
        close:SetPoint("TOPRIGHT", -14, -14)

        local box = Theme:CreateFlatEditBox(m, 276, 26, "输入 NPC ID 或 NPC 名称...")
        box:SetPoint("TOPLEFT", 16, -39)
        m.box = box

        local current = Theme:CreateActionButton(m, 104, 26, "使用当前目标", "add-target")
        current:SetPoint("LEFT", box, "RIGHT", 8, 0)

        local hint = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -8)
        hint:SetText(ns:T("输入 NPC ID 或名称，回车确认，Esc 取消"))

        local function ApplyTarget(rawInput)
            local curTeamObj = m.editingTeamObj
            if not curTeamObj then
                m:Hide()
                return
            end
            rawInput = strtrim(rawInput or "")
            if rawInput == "" then
                ns:PrintError("请输入有效的 NPC ID 或 NPC 名称！")
                return
            end

            local ok, rKey, routeObj = ns:AssignTeamToTarget(curTeamObj, rawInput, m.sourceRouteKey)
            if not ok then return end

            local _, _, matchedGroup = ns:FindExistingTargetInfoForImport(routeObj and routeObj.npcID or 0, routeObj and routeObj.npcName or rawInput, nil)
            if matchedGroup and matchedGroup ~= "" then
                curTeamObj.group = ns:EnsureTeamGroup(matchedGroup)
            end
            MarkTreeAndRoutesDirty()
            m:Hide()
            if ns.RoutingModal and ns.RoutingModal:IsShown() then
                ns.RoutingModal.pendingTargetID = nil
                ns.RoutingModal.pendingTargetName = nil
                ns.RoutingModal.selectedKey = rKey
                ns.RoutingModal:Refresh()
            end
            ns:RefreshAllUI()
        end

        current:SetScript("OnClick", function(_, mouseButton)
            if mouseButton ~= "LeftButton" then return end
            local input = GetCurrentTargetInput()
            if input ~= "" then
                ApplyTarget(input)
            else
                ReportMissingCurrentTarget()
                box:SetFocus()
            end
        end)
        box:SetScript("OnEnterPressed", function(self) ApplyTarget(self:GetText()) end)
        box:SetScript("OnEscapePressed", function() m:Hide() end)
        m:HookScript("OnHide", function() box:ClearFocus() end)
        ns.ChangeTargetModal = m
    end

    local m = ns.ChangeTargetModal
    m:SetParent(ns:GetRoutingDialogParent())
    m.editingTeamObj = teamObj
    m.sourceRouteKey = sourceRouteKey
    m.title:SetText(ns:T("更改队伍所属目标 — ") .. "|cff3b82f6" .. (teamObj.name or ns:T("队伍")) .. "|r")

    local route = sourceRouteKey and ns.db.routeMappings[sourceRouteKey]
    m.box:SetText(ns:FormatTargetInput(route and route.npcID or teamObj.npcID, route and route.npcName or teamObj.npcName))
    m:Show()
    m.box:SetFocus()
    m.box:HighlightText()
end

-- ==================== 1. 出战槽位右键面板（静态事件 + 拖拽值变更短路防卡顿） ====================
function ns:ShowSlotThresholdMenu(anchorCard, slotIndex, targetTeam)
    if ns.SlotContextMenu and ns.SlotContextMenu:IsShown() and ns.SlotContextMenu.slotIndex == slotIndex and ns.SlotContextMenu.targetTeam == targetTeam then
        ns:HideAllPopups()
        return
    end
    self:HideAllPopups()

    if not ns.SlotContextMenu then
        local sm = CreateFrame("Frame", "WishPetTacticsSlotContextMenu", UIParent, "BackdropTemplate")
        sm:SetSize(232, 126)
        sm:SetFrameStrata("FULLSCREEN_DIALOG")
        sm:SetFrameLevel(185)
        sm:SetClampedToScreen(true)
        sm:EnableMouse(true)
        Theme:ApplyBackdrop(sm, Theme.Colors.bgPopup, Theme.Colors.border, true)

        sm.title = sm:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sm.title:SetPoint("TOPLEFT", 10, -10)
        Theme:HookLocalizedFontString(sm.title)

        sm.summonBtn = Theme:CreateFlatButton(sm, 212, 26, "召唤宠物", nil, "LEFT")
        sm.summonBtn._textLeftInset = 4
        sm.summonBtn.text:ClearAllPoints()
        sm.summonBtn.text:SetPoint("LEFT", sm.summonBtn, "LEFT", 4, 0)
        sm.summonBtn.text:SetJustifyH("LEFT")
        local summonLine = sm.summonBtn:CreateTexture(nil, "BORDER")
        summonLine:SetHeight(Theme:GetPixelScale())
        summonLine:SetPoint("BOTTOMLEFT", 2, 0)
        summonLine:SetPoint("BOTTOMRIGHT", -2, 0)
        summonLine:SetTexture("Interface\\Buttons\\WHITE8X8")
        summonLine:SetVertexColor(unpack(Theme.Colors.divider))
        sm.summonBtn:SetPoint("TOPLEFT", 10, -34)
        sm.summonBtn:SetScript("OnClick", function()
            local petID = sm.petID
            -- 菜单打开后宠物可能已换位，执行前核对当前槽位。
            if not petID or C_PetJournal.GetPetLoadOutInfo(sm.slotIndex) ~= petID
                or InCombatLockdown() or C_PetBattles.IsInBattle() then return end
            if C_PetJournal.GetSummonedPetGUID() ~= petID then
                C_PetJournal.SummonPetByGUID(petID)
            end
            ns:HideAllPopups()
        end)

        sm.lvSwitch = Theme:CreateToggleSwitch(sm, "设为经验槽", 212, false)
        sm.lvSwitch:SetPoint("TOPLEFT", 10, -62)

        sm.hpSwitch = Theme:CreateToggleSwitch(sm, "生命值不足时换宠", 212, false)
        sm.hpSwitch:SetPoint("TOPLEFT", 10, -90)

        local hpDrawer = CreateFrame("Frame", nil, sm)
        hpDrawer:SetSize(212, 46)
        hpDrawer:SetPoint("TOPLEFT", 10, -120)
        hpDrawer:EnableMouse(true)
        sm.hpDrawer = hpDrawer

        local dragBar = Theme:CreateFlatBar(hpDrawer, 142, 20, 0.92, 0.55, 0.08)
        dragBar:SetPoint("TOPLEFT", 0, 0)
        dragBar:EnableMouse(true)
        if dragBar.bar then dragBar.bar:EnableMouse(false) end
        sm.dragBar = dragBar

        local valBox = Theme:CreateFlatEditBox(hpDrawer, 64, 20, "40%")
        valBox:SetPoint("LEFT", dragBar, "RIGHT", 6, 0)
        valBox:SetJustifyH("CENTER")
        sm.valBox = valBox

        local tipTxt = hpDrawer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        tipTxt:SetPoint("TOPLEFT", dragBar, "BOTTOMLEFT", 0, -4)
        tipTxt:SetWidth(212)
        tipTxt:SetWordWrap(true)
        Theme:HookLocalizedFontString(tipTxt)
        tipTxt:SetText(ns:T("拖动生命条，或输入百分比（40%）／生命值（450）"))

        sm.backupBtn = Theme:CreateFlatButton(sm, 212, 24, ns.locale == "zhTW" and "指定備用寵物和技能" or ns.locale == "zhCN" and "指定备用宠物和技能" or "Configure backup pets and abilities", nil, "LEFT")
        sm.backupBtn:SetPoint("TOPLEFT", 10, -169)
        sm.backupBtn:SetScript("OnClick", function()
            local team = sm.targetTeam or (ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx])
            local slot = sm.slotIndex
            if team and slot and ns:GetSlotThreshold(team, slot) > 0 then
                ns:HideAllPopups()
                ns:ShowSlotBackups(team, slot)
            end
        end)
        sm.searchPetBtn = Theme:CreateFlatButton(sm, 212, 24, ns:ForumText("搜索同名宠物", "搜尋同名寵物", "Find pets of this species"), nil, "LEFT")
        sm.searchPetBtn:SetScript("OnClick", function()
            local team = sm.targetTeam or (ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx])
            if team then ns:SearchSameSpecies(team, sm.slotIndex) end
        end)

        local function MenuTeam()
            return sm.targetTeam or (ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx])
        end
        local function SetMenuThreshold(team, slot, value)
            local active = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
            if team and team ~= active then
                if not team.slotThresholds then
                    team.slotThresholds = {}
                    for i = 1, 3 do team.slotThresholds[i] = ns:GetSlotThreshold(team, i) end
                end
                team.slotThresholds[slot] = value
            else
                ns:SetHomeSlotThreshold(team, slot, value)
            end
        end

        function sm:UpdateThresholdVisuals()
            local f = ns.MainFrame
            local draft = not self.targetTeam and f and f.compactDraft
            local team = not draft and MenuTeam()
            local sIdx = self.slotIndex or 1
            local maxHP = self.maxHP or 1400
            local curTh = ns:GetSlotThreshold(team, sIdx)
            local isLv = false
            if draft then
                isLv = (draft.levelingSlot == sIdx)
            elseif team then
                isLv = (team.hasLevelingSlot and (team.levelingSlot or 2) == sIdx) and true or false
            else
                isLv = (ns.db and ns.db.settings and ns.db.settings.standaloneLevelingSlot == sIdx) and true or false
            end
            self.lvSwitch:SetState(isLv)

            local hpEnabled = (curTh and curTh > 0)
            self.hpSwitch:SetState(hpEnabled)
            local canConfigure = hpEnabled and team and not draft and not isLv and not (team.randomSlots and team.randomSlots[sIdx] ~= nil)
            self.backupBtn:SetShown(canConfigure and true or false)

            if hpEnabled then
                self.hpDrawer:Show()
                local height = canConfigure and 200 or 176
                if self._lastH ~= height then
                    self._lastH = height
                    self:SetHeight(height)
                end
                if curTh <= 100 then
                    local exactHP = math.floor(maxHP * (curTh / 100) + 0.5)
                    self.dragBar.bar:SetValue(curTh)
                    self.dragBar.text:SetText(ns:TF("<= %d%% (%d血)", curTh, exactHP))
                    if not self.valBox:HasFocus() then
                        self.valBox:SetText(curTh .. "%")
                        self.valBox.placeholder:Hide()
                    end
                else
                    local pct = math.max(1, math.min(100, math.floor((curTh / maxHP) * 100 + 0.5)))
                    self.dragBar.bar:SetValue(pct)
                    self.dragBar.text:SetText(ns:TF("<= %d血 (%d%%)", curTh, pct))
                    if not self.valBox:HasFocus() then
                        self.valBox:SetText(tostring(curTh))
                        self.valBox.placeholder:Hide()
                    end
                end
            else
                self.hpDrawer:Hide()
                if self._lastH ~= 126 then
                    self._lastH = 126
                    self:SetHeight(126)
                end
            end
            local baseHeight = hpEnabled and (canConfigure and 200 or 176) or 126
            self.searchPetBtn:ClearAllPoints()
            self.searchPetBtn:SetPoint("TOPLEFT", 10, -baseHeight)
            self.searchPetBtn:SetEnabled(team ~= nil and not isLv)
            self:SetHeight(baseHeight + 28)
        end

        sm.lvSwitch:SetScript("OnClick", function()
            local sIdx = sm.slotIndex
            if not sIdx or InCombatLockdown() or (C_PetBattles and C_PetBattles.IsInBattle()) then return end
            local active = ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]
            if sm.targetTeam and sm.targetTeam ~= active then
                local team = sm.targetTeam
                local oldSlot = team.hasLevelingSlot and (team.levelingSlot or 2)
                if oldSlot then
                    local fallback = team.levelingFallback
                    team.pets = team.pets or {}
                    team.speciesLoadout = team.speciesLoadout or {}
                    team.abilities = team.abilities or {}
                    team.pets[oldSlot] = fallback and fallback.petID or nil
                    team.speciesLoadout[oldSlot] = fallback and fallback.speciesID or 0
                    team.abilities[oldSlot] = fallback and fallback.abilities or {0, 0, 0}
                    team.hasLevelingSlot, team.levelingFallback = false, nil
                end
                if oldSlot ~= sIdx then
                    ns.Leveling:CaptureSlotFallback(team, sIdx, true)
                    team.hasLevelingSlot, team.levelingSlot = true, sIdx
                    team.pets = team.pets or {}
                    team.speciesLoadout = team.speciesLoadout or {}
                    team.pets[sIdx], team.speciesLoadout[sIdx] = "LEVELING", 0
                end
                sm:UpdateThresholdVisuals()
                if ns.RefreshAllUI then ns:RefreshAllUI() end
                return
            end
            local f = ns.MainFrame
            local draft = f and f.compactDraft
            if draft then
                if draft.levelingSlot == sIdx then
                    draft.levelingSlot = nil
                else
                    draft.levelingSlot = sIdx
                    if ns.db and ns.db.settings then ns.db.settings.levelingSlot = sIdx end
                    ns.Leveling:FillRandomUnleveledPetForSlot(sIdx, true)
                end
                sm:UpdateThresholdVisuals()
                RefreshPetDrawerAndUI(false)
                return
            end
            local team = MenuTeam()
            if not team and ns.db and ns.db.teams and #ns.db.teams > 0 then
                ns.db.selectedTeamIdx = 1
                team = ns.db.teams[1]
            end
            if not team then
                if ns.db and ns.db.settings then
                    if ns.db.settings.standaloneLevelingSlot == sIdx then
                        ns.db.settings.standaloneLevelingSlot = nil
                    else
                        ns.db.settings.standaloneLevelingSlot = sIdx
                        ns.db.settings.levelingSlot = sIdx
                        ns.Leveling:FillRandomUnleveledPetForSlot(sIdx, true)
                    end
                end
                sm:UpdateThresholdVisuals()
                RefreshPetDrawerAndUI(false)
                return
            end
            ns:EnsureTeamBackup()
            local oldSlot = team.hasLevelingSlot and (team.levelingSlot or 2)
            local oldFallback = team.levelingFallback
            if oldSlot == sIdx then
                ns.Leveling:RestoreSlotFallback(team, sIdx)
                team.hasLevelingSlot, team.levelingFallback = false, nil
            else
                local changed = ns.staging.changedSlots and ns.staging.changedSlots[sIdx]
                ns.Leveling:CaptureSlotFallback(team, sIdx, team.explicitSlots and not changed)
                if oldSlot then ns.Leveling:RestoreSlotFallback(team, oldSlot, oldFallback or {}) end
                team.hasLevelingSlot, team.levelingSlot = true, sIdx
                ns.db.settings.levelingSlot = sIdx
                ns.Leveling:FillRandomUnleveledPetForSlot(sIdx, true)
            end
            if oldSlot then ns:MarkHomeSlotChanged(oldSlot) end
            ns:MarkHomeSlotChanged(sIdx)
            ns.staging.isDirty = true
            sm:UpdateThresholdVisuals()
            RefreshPetDrawerAndUI(false)
        end)

        sm.hpSwitch:SetScript("OnClick", function()
            local team = MenuTeam()
            local sIdx = sm.slotIndex
            if not sIdx then return end
            local curTh = ns:GetSlotThreshold(team, sIdx)
            SetMenuThreshold(team, sIdx, (curTh and curTh > 0) and 0 or 40)
            sm:UpdateThresholdVisuals()
            if ns.RefreshLoadoutCabin then ns:RefreshLoadoutCabin() end
        end)

        local function UpdateBarFromCursor()
            if not IsMouseButtonDown("LeftButton") then
                dragBar:SetScript("OnUpdate", nil)
                return
            end
            local left, width = dragBar:GetLeft(), dragBar:GetWidth()
            local cx = GetCursorPosition() / dragBar:GetEffectiveScale()
            if left and width and width > 0 then
                local pct = math.floor(math.max(5, math.min(95, ((cx - left) / width) * 100)) + 0.5)
                local team = MenuTeam()
                if ns:GetSlotThreshold(team, sm.slotIndex) ~= pct then
                    SetMenuThreshold(team, sm.slotIndex, pct)
                    sm:UpdateThresholdVisuals()
                    if ns.RefreshLoadoutCabin then ns:RefreshLoadoutCabin() end
                end
            end
        end

        dragBar:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                UpdateBarFromCursor()
                self:SetScript("OnUpdate", UpdateBarFromCursor)
            end
        end)
        dragBar:SetScript("OnMouseUp", function(self)
            self:SetScript("OnUpdate", nil)
        end)
        dragBar:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
        end)

        local function CommitBoxInput(self)
            local team = MenuTeam()
            local sIdx = sm.slotIndex
            if not sIdx then return end
            local raw = strtrim(self:GetText() or "")
            local isPct = string.find(raw, "%%") ~= nil
            local num = tonumber((string.gsub(raw, "[^%d]", "")))
            if num and num > 0 then
                if isPct or num <= 100 then
                    SetMenuThreshold(team, sIdx, math.max(1, math.min(99, num)))
                else
                    SetMenuThreshold(team, sIdx, num)
                end
            else
                SetMenuThreshold(team, sIdx, 0)
            end
            self:ClearFocus()
            sm:UpdateThresholdVisuals()
            if ns.RefreshLoadoutCabin then ns:RefreshLoadoutCabin() end
        end

        valBox:SetScript("OnEnterPressed", CommitBoxInput)
        valBox:SetScript("OnEditFocusLost", CommitBoxInput)

        ns.SlotContextMenu = sm
    end

    local sm = ns.SlotContextMenu
    sm.slotIndex = slotIndex
    sm.targetTeam = targetTeam
    if ns.MainFrame then
        sm:SetScale(ns.MainFrame:GetEffectiveScale() / UIParent:GetEffectiveScale())
    end

    local pData = anchorCard and anchorCard.petData
    if targetTeam and not pData then
        local petID = targetTeam.pets and targetTeam.pets[slotIndex]
        if petID and petID ~= "LEVELING" then
            local _, custom, _, _, _, _, _, name = C_PetJournal.GetPetInfoByPetID(petID)
            local _, maxHealth = C_PetJournal.GetPetStats(petID)
            pData = { petID = petID, name = custom or name, maxHealth = maxHealth }
        end
    end
    sm.petID = pData and pData.petID
    sm.summonBtn:SetEnabled(sm.petID ~= nil and not InCombatLockdown() and not C_PetBattles.IsInBattle())
    sm.maxHP = (pData and pData.maxHealth and pData.maxHealth > 0) and pData.maxHealth or 1400
    sm.title:SetText(string.format(ns:T("%d号槽位设置") .. " — %s", slotIndex, pData and pData.name or ns:T("当前槽位")))

    sm:UpdateThresholdVisuals()
    sm:ClearAllPoints()
    -- 统一从槽位卡片右侧弹出菜单。
    sm:SetPoint("TOPLEFT", anchorCard, "TOPRIGHT", 6, 0)
    sm:Show()
    ns:EnablePopupClickCatcher(sm)
end

-- ==================== 2. 「所有已收集宠物」多维筛选菜单（存档直连 + 智能左右自适应子菜单） ====================
local FILTER_SOURCES = { "掉落", "任务", "商人", "专业", "宠物对战", "成就", "世界事件" }
local FILTER_EXPANSIONS = {
    { text = "全部资料片", val = -1 },
    { text = "地心之战 / 至暗之夜", val = 5 },
    { text = "暗影国度 / 巨龙时代", val = 4 },
    { text = "军团再临 / 争霸艾泽拉斯", val = 3 },
    { text = "熊猫人之谜 / 德拉诺", val = 2 },
    { text = "经典旧世 / 大灾变", val = 1 },
}
local FILTER_RARITIES = {
    { text = "全部品质", val = -1 },
    { text = "|cff0070dd稀有 (蓝色)|r", val = 4 },
    { text = "|cff1eff00优秀 (绿色)|r", val = 3 },
    { text = "|cffffffff普通 (白色)|r", val = 2 },
    { text = "|cff9d9d9d粗糙 (灰色)|r", val = 1 },
}
local FILTER_LEVELS = {
    { text = "全部等级", val = "ALL" },
    { text = "满级 (25级)", val = "MAX" },
    { text = "1级 (初始宠)", val = "LV1" },
    { text = "练级中 (2 ~ 24级)", val = "LV_MID" },
    { text = "所有未满级 (<25级)", val = "UNLEVELED" },
}
local FILTER_SCRIPTS = {
    { text = "不限脚本条件", val = "NONE" },
    { text = "拥有多只同种宠 (>=2只)", val = "MULTI_COUNT" },
    { text = "带有自定义备注的宠物", val = "NOTES" },
}
local FILTER_SORTS = {
    { text = "默认综合排序", val = "DEFAULT" },
    { text = "按名称排序", val = "NAME" },
    { text = "按等级降序", val = "LEVEL" },
    { text = "按品质降序", val = "RARITY" },
    { text = "按攻击力降序", val = "POWER" },
    { text = "按速度降序", val = "SPEED" },
    { text = "按最大生命降序", val = "HEALTH" },
}

local MAIN_FILTER_DEFS = {
    { id = "COLLECTED",   label = "已收集宠物",             isCheck = true },
    { id = "ONLY_FAV",    label = "仅显示收藏宠物",           isCheck = true },
    { id = "UNCOLLECTED", label = "未收集宠物",             isCheck = true },
    { id = "PET_TYPE",    label = "宠物类型",               subKey = "petType" },
    { id = "STRONG_VS",   label = "重击对方 (+50%)",        subKey = "strongVs" },
    { id = "TOUGH_VS",    label = "被对方轻击 (-33%)",      subKey = "toughVs" },
    { id = "SOURCE",      label = "获取来源",               subKey = "source" },
    { id = "EXPANSION",   label = "资料片",      subKey = "expansion" },
    { id = "RARITY",      label = "品质",               subKey = "rarity" },
    { id = "LEVEL",       label = "宠物等级",               subKey = "level" },
    { id = "MARKER",      label = "宠物标签",               subKey = "marker" },
    { id = "OTHER",       label = "其他条件",  subKey = "other" },
    { id = "SCRIPT",      label = "脚本条件",           subKey = "script" },
    { id = "SORT",        label = "排序方式",               subKey = "sort" },
    { id = "FAV_FILTER",  label = "已保存的筛选方案",         subKey = "fav" },
    { id = "EXPORT_LIST", label = "导出当前宠物列表" },
    { id = "RESET_ALL",   label = "|cff38bdf8重置全部筛选|r" },
}

function ns:TogglePetFilterMenu(anchorBtn)
    if ns.PetFilterMenu and ns.PetFilterMenu:IsShown() then
        ns:HideAllPopups()
        return
    end
    self:HideAllPopups()

    if not ns.PetFilterMenu then
        local menu = CreateFrame("Frame", "WishPetTacticsPetFilterMenu", UIParent, "BackdropTemplate")
        menu:SetSize(192, #MAIN_FILTER_DEFS * 24 + 32)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(190)
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        Theme:ApplyBackdrop(menu, Theme.Colors.bgPopup, Theme.Colors.border, true)

        local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", 10, -8)
        Theme:HookLocalizedFontString(title)
        title:SetText(ns:T("筛选"))

        local closeBtn = Theme:CreateCloseIconButton(menu, function() ns:HideAllPopups() end)
        closeBtn:SetPoint("TOPRIGHT", -10, -8)
        title:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)

        local subMenu = CreateFrame("Frame", "WishPetTacticsPetFilterSubMenu", menu, "BackdropTemplate")
        subMenu:SetSize(184, 260)
        subMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        subMenu:SetFrameLevel(200)
        subMenu:SetClampedToScreen(true)
        subMenu:EnableMouse(true)
        Theme:ApplyBackdrop(subMenu, Theme.Colors.bgPopup, Theme.Colors.border, true)
        subMenu:Hide()
        subMenu.rows = {}
        ns.PetFilterSubMenu = subMenu

        local MAX_PET_SUB_ROWS = 15

        local function BindSubRowVisual(idx, labelStr, checked, iconPath, optKey, optVal)
            local sr = subMenu.rows[idx]
            sr.optKey = optKey
            sr.optVal = optVal
            sr:SetSelected(checked == true)
            local iconTag = iconPath and string.format("|T%s:16:16:0:0|t ", iconPath) or ""
            local stateDot = checked and "|cff10b981●|r " or ""
            sr.text:SetText(stateDot .. iconTag .. ns:T(labelStr))
            sr:Show()
        end

        local function PopulateSubMenu(parentRow, subKey)
            if not subKey then
                subMenu:Hide()
                return
            end
            local st = GetPetFilterState()
            local count = 0

            if subKey == "petType" or subKey == "strongVs" or subKey == "toughVs" then
                count = 1
                BindSubRowVisual(1, "全部类型", ns.SearchFilter:IsPetFilterOptionSelected(st[subKey], -1), nil, subKey, -1)
                for t = 1, 10 do
                    local pt = Theme.PetTypes[t]
                    count = count + 1
                    BindSubRowVisual(count, pt.name, ns.SearchFilter:IsPetFilterOptionSelected(st[subKey], t), pt.icon, subKey, t)
                end
            elseif subKey == "source" then
                count = 1
                BindSubRowVisual(1, "全部来源", ns.SearchFilter:IsPetFilterOptionSelected(st.source, -1), nil, "source", -1)
                for idx = 1, #FILTER_SOURCES do
                    count = count + 1
                    BindSubRowVisual(count, FILTER_SOURCES[idx], ns.SearchFilter:IsPetFilterOptionSelected(st.source, idx), nil, "source", idx)
                end
            elseif subKey == "expansion" then
                for idx = 1, #FILTER_EXPANSIONS do
                    local info = FILTER_EXPANSIONS[idx]
                    count = count + 1
                    BindSubRowVisual(count, info.text, ns.SearchFilter:IsPetFilterOptionSelected(st.expansion, info.val), nil, "expansion", info.val)
                end
            elseif subKey == "rarity" then
                for idx = 1, #FILTER_RARITIES do
                    local info = FILTER_RARITIES[idx]
                    count = count + 1
                    BindSubRowVisual(count, info.text, ns.SearchFilter:IsPetFilterOptionSelected(st.rarity, info.val), nil, "rarity", info.val)
                end
            elseif subKey == "level" then
                for idx = 1, #FILTER_LEVELS do
                    local info = FILTER_LEVELS[idx]
                    count = count + 1
                    BindSubRowVisual(count, info.text, st.levelType == info.val, nil, "level", info.val)
                end
            elseif subKey == "marker" then
                count = 1
                BindSubRowVisual(1, "全部标签", ns.SearchFilter:IsPetFilterOptionSelected(st.marker, -1), nil, "marker", -1)
                for m = 1, 8 do
                    local mName = _G["RAID_TARGET_" .. m] or ("标签 " .. m)
                    count = count + 1
                    BindSubRowVisual(count, mName, ns.SearchFilter:IsPetFilterOptionSelected(st.marker, m), "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. m, "marker", m)
                end
            elseif subKey == "other" then
                BindSubRowVisual(1, "仅显示存活宠物",   st.healthMode == "ALIVE", nil, "other_alive",    nil)
                BindSubRowVisual(2, "仅显示受伤或阵亡宠物",  st.healthMode == "DEAD",  nil, "other_dead",     nil)
                BindSubRowVisual(3, "仅显示已编队宠物", st.onlyInTeam,            nil, "other_team",     nil)
                BindSubRowVisual(4, "仅显示可装笼宠物", st.onlyTradable,          nil, "other_tradable", nil)
                count = 4
            elseif subKey == "script" then
                for idx = 1, #FILTER_SCRIPTS do
                    local info = FILTER_SCRIPTS[idx]
                    local isChk = (info.val == "NOTES" and st.hasNotes) or (info.val ~= "NOTES" and st.scriptFilter == info.val)
                    count = count + 1
                    BindSubRowVisual(count, info.text, isChk, nil, "script", info.val)
                end
            elseif subKey == "sort" then
                for idx = 1, #FILTER_SORTS do
                    local info = FILTER_SORTS[idx]
                    count = count + 1
                    BindSubRowVisual(count, info.text, st.sortBy == info.val, nil, "sort", info.val)
                end
            elseif subKey == "fav" then
                ns.db.favoriteFilters = ns.db.favoriteFilters or {}
                count = 1
                BindSubRowVisual(1, "|cff10b981保存筛选方案|r", false, nil, "fav_save", nil)
                local maxFav = math.min(MAX_PET_SUB_ROWS - 1, #ns.db.favoriteFilters)
                for idx = 1, maxFav do
                    local fav = ns.db.favoriteFilters[idx]
                    count = count + 1
                    BindSubRowVisual(count, "应用：" .. fav.name, false, nil, "fav_apply", idx)
                end
            end

            for i = count + 1, MAX_PET_SUB_ROWS do
                subMenu.rows[i]:Hide()
            end

            subMenu.activeParentRow = parentRow
            subMenu.activeSubKey = subKey
            subMenu:SetSize(184, count * 23 + 8)
            AnchorSubMenuSmart(menu, parentRow, subMenu, 184)
            subMenu:SetFrameLevel(menu:GetFrameLevel() + 5)
            subMenu:Show()
        end

        for i = 1, MAX_PET_SUB_ROWS do
            local sr = Theme:CreateMenuRow(subMenu, 176, 23, "")
            sr:SetPoint("TOPLEFT", 4, -4 - ((i - 1) * 23))
            sr:SetScript("OnClick", function(selfBtn)
                local st = GetPetFilterState()
                local key = selfBtn.optKey
                local val = selfBtn.optVal
                local keepSubOpen = true

                if key == "petType" or key == "strongVs" or key == "toughVs" or key == "source" or key == "expansion" or key == "rarity" or key == "marker" then
                    ns.SearchFilter:TogglePetFilterOption(st, key, val)
                elseif key == "level" then
                    st.levelType = val
                elseif key == "other_alive" then
                    st.healthMode = (st.healthMode == "ALIVE") and "ALL" or "ALIVE"
                elseif key == "other_dead" then
                    st.healthMode = (st.healthMode == "DEAD") and "ALL" or "DEAD"
                elseif key == "other_team" then
                    st.onlyInTeam = not st.onlyInTeam
                elseif key == "other_tradable" then
                    st.onlyTradable = not st.onlyTradable
                elseif key == "script" then
                    if val == "NOTES" then
                        st.hasNotes = not st.hasNotes
                    else
                        st.scriptFilter = (st.scriptFilter == val) and "NONE" or val
                    end
                elseif key == "sort" then
                    st.sortBy = val
                elseif key == "fav_save" then
                    ns.db.favoriteFilters = ns.db.favoriteFilters or {}
                    local snap = CopyTable(st)
                    local name = ns:TF("筛选方案 #%d", #ns.db.favoriteFilters + 1)
                    table.insert(ns.db.favoriteFilters, { name = name, state = snap })
                elseif key == "fav_apply" then
                    local fav = ns.db.favoriteFilters and ns.db.favoriteFilters[val]
                    if fav and fav.state then
                        for k, v in pairs(CopyTable(fav.state)) do st[k] = v end
                    end
                    keepSubOpen = false
                end

                RefreshPetDrawerAndUI(true)
                menu:RefreshRows()
                if keepSubOpen and subMenu.activeParentRow and subMenu.activeSubKey then
                    PopulateSubMenu(subMenu.activeParentRow, subMenu.activeSubKey)
                else
                    subMenu:Hide()
                end
            end)
            subMenu.rows[i] = sr
        end

        menu.rows = {}
        for i = 1, #MAIN_FILTER_DEFS do
            local def = MAIN_FILTER_DEFS[i]
            local r = Theme:CreateMenuRow(menu, 184, 24, "")
            r:SetPoint("TOPLEFT", 4, -28 - ((i - 1) * 24))
            r.def = def

            r.arrow = Theme:CreateArrowTexture(r, 11, "RIGHT")
            r.arrow:SetPoint("RIGHT", -6, 0)
            r.arrow:SetVertexColor(0.38, 0.65, 0.98, 1)
            r.arrow:SetShown(def.subKey ~= nil)

            r:HookScript("OnEnter", function(selfBtn)
                local d = selfBtn.def
                if d and d.subKey then
                    PopulateSubMenu(selfBtn, d.subKey)
                else
                    subMenu:Hide()
                end
            end)

            r:SetScript("OnClick", function(selfBtn)
                local d = selfBtn.def
                if not d then return end
                local st = GetPetFilterState()
                local id = d.id

                if id == "COLLECTED" then
                    st.showCollected = not st.showCollected
                    RefreshPetDrawerAndUI(true)
                    menu:RefreshRows()
                elseif id == "ONLY_FAV" then
                    st.onlyFav = not st.onlyFav
                    RefreshPetDrawerAndUI(true)
                    menu:RefreshRows()
                elseif id == "UNCOLLECTED" then
                    st.showUncollected = not st.showUncollected
                    RefreshPetDrawerAndUI(true)
                    menu:RefreshRows()
                elseif id == "EXPORT_LIST" then
                    ns:HideAllPopups()
                    local pets = ns.SearchFilter:GetFilteredPets()
                    local lines = { ns:TF("-- 当前筛选宠物列表导出 (共 %d 只)", #pets) }
                    for idx = 1, math.min(100, #pets) do
                        local p = pets[idx]
                        lines[#lines + 1] = ns:TF("%s (%d级 %s) - 生命:%d 攻击:%d 速度:%d", p.name, p.level, p.breed, p.maxHealth, p.power, p.speed)
                    end
                    ns:ShowExportModalWithText(table.concat(lines, "\n"), nil, "TEAM")
                elseif id == "RESET_ALL" then
                    ns.SearchFilter:ResetPetFilters()
                    RefreshPetDrawerAndUI(true)
                    menu:RefreshRows()
                end
            end)

            menu.rows[i] = r
        end

        function menu:RefreshRows()
            local st = GetPetFilterState()
            for i = 1, #MAIN_FILTER_DEFS do
                local r = self.rows[i]
                local d = r.def
                local id = d.id
                local active = false

                if id == "COLLECTED" then active = st.showCollected
                elseif id == "ONLY_FAV" then active = st.onlyFav
                elseif id == "UNCOLLECTED" then active = st.showUncollected
                elseif id == "PET_TYPE" then active = ns.SearchFilter:IsPetFilterSelectionActive(st.petType)
                elseif id == "STRONG_VS" then active = ns.SearchFilter:IsPetFilterSelectionActive(st.strongVs)
                elseif id == "TOUGH_VS" then active = ns.SearchFilter:IsPetFilterSelectionActive(st.toughVs)
                elseif id == "SOURCE" then active = ns.SearchFilter:IsPetFilterSelectionActive(st.source)
                elseif id == "EXPANSION" then active = ns.SearchFilter:IsPetFilterSelectionActive(st.expansion)
                elseif id == "RARITY" then active = ns.SearchFilter:IsPetFilterSelectionActive(st.rarity)
                elseif id == "LEVEL" then active = (st.levelType ~= "ALL")
                elseif id == "MARKER" then active = ns.SearchFilter:IsPetFilterSelectionActive(st.marker)
                elseif id == "OTHER" then active = (st.healthMode ~= "ALL" or st.onlyInTeam or st.onlyTradable)
                elseif id == "SCRIPT" then active = (st.scriptFilter ~= "NONE" or st.hasNotes)
                elseif id == "SORT" then active = (st.sortBy ~= "DEFAULT")
                end

                r:SetSelected(active == true)
                local stateDot = active and "|cff10b981●|r " or ""
                r.text:SetText(stateDot .. ns:T(d.label))
            end
        end

        ns.PetFilterMenu = menu
    end

    if ns.PetFilterSubMenu then ns.PetFilterSubMenu:Hide() end
    if ns.MainFrame then
        ns.PetFilterMenu:SetScale(ns.MainFrame:GetEffectiveScale() / UIParent:GetEffectiveScale())
    end
    ns.PetFilterMenu:ClearAllPoints()
    ns.PetFilterMenu:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", -114, -4)
    ns.PetFilterMenu:RefreshRows()
    ns.PetFilterMenu:Show()
    ns:EnablePopupClickCatcher(ns.PetFilterMenu)
end

-- ==================== 3. 练级队列专属筛选与升级助手（SavedVariables 持久化 + 系别/属性子菜单） ====================
local QUEUE_DRAWER_DEFS = {
    { id = "BATCH_UNLEVELED", label = "|cff38bdf8导入未满级宠物|r",     noCheck = true },
    { id = "BATCH_RARE",      label = "|cff38bdf8导入未满级稀有宠物|r", noCheck = true },
    { id = "SET_LV_FILTER",   label = "设置筛选等级（1-25）" },
    { id = "SORT_RARITY",     label = "品质优先（稀有优先）" },
    { id = "SORT_ASC",        label = "等级升序（低等级优先）" },
    { id = "SORT_DESC",       label = "等级降序（高等级优先）" },
}

function ns:ToggleQueueFilterMenu(anchorBtn)
    if ns.QueueFilterDrawer and ns.QueueFilterDrawer:IsShown() then
        ns:HideAllPopups()
        return
    end
    self:HideAllPopups()

    if not ns.QueueFilterDrawer then
        local qd = CreateFrame("Frame", "WishPetTacticsQueueFilterDrawer", UIParent, "BackdropTemplate")
        qd:SetSize(258, #QUEUE_DRAWER_DEFS * 24.5 + 34)
        qd:SetFrameStrata("FULLSCREEN_DIALOG")
        qd:SetFrameLevel(190)
        qd:SetClampedToScreen(true)
        qd:EnableMouse(true)
        Theme:ApplyBackdrop(qd, Theme.Colors.bgPopup, Theme.Colors.border, true)

        local closeBtn = Theme:CreateCloseIconButton(qd, function() ns:HideAllPopups() end)
        closeBtn:SetPoint("TOPRIGHT", -10, -8)

        local title = qd:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", 10, -8)
        title:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        Theme:HookLocalizedFontString(title)
        title:SetText(ns:T("|cff3b82f6练级队列设置（自动保存）|r"))

        local qSub = CreateFrame("Frame", "WishPetTacticsQueueFilterSubMenu", qd, "BackdropTemplate")
        qSub:SetSize(176, 260)
        qSub:SetFrameStrata("FULLSCREEN_DIALOG")
        qSub:SetFrameLevel(200)
        qSub:SetClampedToScreen(true)
        qSub:EnableMouse(true)
        Theme:ApplyBackdrop(qSub, Theme.Colors.bgPopup, Theme.Colors.border, true)
        qSub:Hide()
        qSub.rows = {}
        qd.qSub = qSub

        local MAX_Q_SUB_ROWS = 12

        local function BindQueueSubRow(idx, labelStr, checked, iconPath, optKey, optVal)
            local sr = qSub.rows[idx]
            sr.optKey = optKey
            sr.optVal = optVal
            sr:SetSelected(checked == true)
            local iconTag = iconPath and string.format("|T%s:14:14:0:0:64:64:5:59:5:59|t ", iconPath) or ""
            local stateDot = checked and "|cff10b981●|r " or ""
            sr.text:SetText(stateDot .. iconTag .. ns:T(labelStr))
            sr:Show()
        end

        local function PopulateQueueSubMenu(parentRow, subKey)
            if not subKey then
                qSub:Hide()
                return
            end
            local st = GetQueueFilterState()
            local count = 0

            if subKey == "petType" then
                count = 1
                BindQueueSubRow(1, "全部类型", st.petType == -1, nil, "petType", -1)
                for t = 1, 10 do
                    local pt = Theme.PetTypes[t]
                    count = count + 1
                    BindQueueSubRow(count, pt.name, st.petType == t, pt.icon, "petType", t)
                end
            end

            for i = count + 1, MAX_Q_SUB_ROWS do
                qSub.rows[i]:Hide()
            end

            qSub.activeParentRow = parentRow
            qSub.activeSubKey = subKey
            qSub:SetSize(176, count * 23 + 8)
            AnchorSubMenuSmart(qd, parentRow, qSub, 176)
            qSub:SetFrameLevel(qd:GetFrameLevel() + 5)
            qSub:Show()
        end

        for i = 1, MAX_Q_SUB_ROWS do
            local sr = Theme:CreateMenuRow(qSub, 168, 23, "")
            sr:SetPoint("TOPLEFT", 4, -4 - ((i - 1) * 23))
            sr:SetScript("OnClick", function(selfBtn)
                local st = GetQueueFilterState()
                if selfBtn.optKey == "petType" then
                    local val = selfBtn.optVal
                    st.petType = (val == -1 or st.petType == val) and -1 or val
                end
                RefreshPetDrawerAndUI(true)
                qd:RefreshUI()
                if qSub.activeParentRow and qSub.activeSubKey then
                    PopulateQueueSubMenu(qSub.activeParentRow, qSub.activeSubKey)
                end
            end)
            qSub.rows[i] = sr
        end

        qd.rows = {}
        for i = 1, #QUEUE_DRAWER_DEFS do
            local def = QUEUE_DRAWER_DEFS[i]
            local r = Theme:CreateMenuRow(qd, 250, 24, "")
            r:SetPoint("TOPLEFT", 4, -28 - ((i - 1) * 24.5))
            r.def = def

            r.arrow = Theme:CreateArrowTexture(r, 11, "RIGHT")
            r.arrow:SetPoint("RIGHT", -6, 0)
            r.arrow:SetVertexColor(0.38, 0.65, 0.98, 1)
            r.arrow:SetShown(def.subKey ~= nil)

            r:HookScript("OnEnter", function(selfBtn)
                local d = selfBtn.def
                if d and d.subKey then
                    PopulateQueueSubMenu(selfBtn, d.subKey)
                else
                    qSub:Hide()
                end
            end)

            r:SetScript("OnClick", function(selfBtn)
                local st = GetQueueFilterState()
                local id = selfBtn.def.id
                if selfBtn.def.subKey then
                    PopulateQueueSubMenu(selfBtn, selfBtn.def.subKey)
                    return
                elseif id == "BATCH_UNLEVELED" then
                    ns.Leveling:BatchEnqueueByMode("UNLEVELED_ALL")
                elseif id == "BATCH_RARE" then
                    ns.Leveling:BatchEnqueueByMode("RARE_ALL")
                elseif id == "SET_LV_FILTER" then
                    ns:HideAllPopups()
                    StaticPopupDialogs["WISHPETTACTICS_QUEUE_LV_INPUT"] = StaticPopupDialogs["WISHPETTACTICS_QUEUE_LV_INPUT"] or {
                        text = ns:T("请输入筛选等级（如 1-25 或单个等级 1-25，留空显示全部）："),
                        button1 = ACCEPT or "OK",
                        button2 = CANCEL or "Cancel",
                        hasEditBox = 1,
                        maxLetters = 12,
                        OnShow = function(self)
                            local qSt = GetQueueFilterState()
                            local eb = self.editBox or self.GetEditBox and self:GetEditBox()
                            if eb then
                                if qSt.minLv or qSt.maxLv then
                                    local mn, mx = qSt.minLv or 1, qSt.maxLv or 25
                                    eb:SetText(mn == mx and tostring(mn) or (mn .. "-" .. mx))
                                else
                                    eb:SetText("")
                                end
                                eb:HighlightText()
                                eb:SetFocus()
                            end
                        end,
                        OnAccept = function(self)
                            local qSt = GetQueueFilterState()
                            local eb = self.editBox or self.GetEditBox and self:GetEditBox()
                            local raw = strtrim(eb and eb:GetText() or "")
                            qSt.levelRange = "ALL"
                            if raw == "" then
                                qSt.minLv, qSt.maxLv = nil, nil
                            else
                                local a, b = string.match(raw, "^(%d+)%s*[%-%~%s]+%s*(%d+)$")
                                if a and b then
                                    local n1, n2 = math.max(1, math.min(25, tonumber(a) or 1)), math.max(1, math.min(25, tonumber(b) or 25))
                                    qSt.minLv, qSt.maxLv = math.min(n1, n2), math.max(n1, n2)
                                else
                                    local single = tonumber(string.match(raw, "%d+"))
                                    if single then
                                        single = math.max(1, math.min(25, single))
                                        qSt.minLv, qSt.maxLv = single, single
                                    else
                                        qSt.minLv, qSt.maxLv = nil, nil
                                    end
                                end
                            end
                            RefreshPetDrawerAndUI(true)
                        end,
                        EditBoxOnEnterPressed = function(self)
                            local parent = self:GetParent()
                            local accept = StaticPopupDialogs["WISHPETTACTICS_QUEUE_LV_INPUT"].OnAccept
                            if accept then accept(parent) end
                            parent:Hide()
                        end,
                        timeout = 0,
                        whileDead = true,
                        hideOnEscape = true,
                        preferredIndex = 3,
                    }
                    ns.QueueLevelFilterPopup = StaticPopup_Show("WISHPETTACTICS_QUEUE_LV_INPUT")
                    return
                elseif id == "SORT_RARITY" or id == "SORT_ASC" or id == "SORT_DESC" then
                    local rule = ns.db.settings.levelingRule or "MANUAL"
                    local hasRarity = (rule == "RARITY_DESC" or rule == "RARITY_LEVEL_ASC" or rule == "RARITY_LEVEL_DESC")
                    local lvMode = (rule == "LEVEL_ASC" or rule == "RARITY_LEVEL_ASC") and "ASC"
                        or ((rule == "LEVEL_DESC" or rule == "RARITY_LEVEL_DESC") and "DESC" or "NONE")
                    if id == "SORT_RARITY" then
                        hasRarity = not hasRarity
                    elseif id == "SORT_ASC" then
                        lvMode = (lvMode == "ASC") and "NONE" or "ASC"
                    elseif id == "SORT_DESC" then
                        lvMode = (lvMode == "DESC") and "NONE" or "DESC"
                    end
                    if hasRarity and lvMode == "ASC" then
                        ns.db.settings.levelingRule = "RARITY_LEVEL_ASC"
                    elseif hasRarity and lvMode == "DESC" then
                        ns.db.settings.levelingRule = "RARITY_LEVEL_DESC"
                    elseif hasRarity then
                        ns.db.settings.levelingRule = "RARITY_DESC"
                    elseif lvMode == "ASC" then
                        ns.db.settings.levelingRule = "LEVEL_ASC"
                    elseif lvMode == "DESC" then
                        ns.db.settings.levelingRule = "LEVEL_DESC"
                    else
                        ns.db.settings.levelingRule = "MANUAL"
                    end
                end
                RefreshPetDrawerAndUI(true)
                if qd:IsShown() then qd:RefreshUI() end
            end)
            qd.rows[i] = r
        end

        function qd:RefreshUI()
            local st = GetQueueFilterState()
            local rule = ns.db.settings.levelingRule or "MANUAL"
            local hasRarity = (rule == "RARITY_DESC" or rule == "RARITY_LEVEL_ASC" or rule == "RARITY_LEVEL_DESC")
            local lvAsc     = (rule == "LEVEL_ASC" or rule == "RARITY_LEVEL_ASC")
            local lvDesc    = (rule == "LEVEL_DESC" or rule == "RARITY_LEVEL_DESC")
            for i = 1, #QUEUE_DRAWER_DEFS do
                local r = self.rows[i]
                local d = r.def
                local id = d.id
                local active = false
                if id == "SET_LV_FILTER" then
                    active = (st.minLv ~= nil or st.maxLv ~= nil)
                elseif id == "SORT_RARITY" then active = hasRarity
                elseif id == "SORT_ASC" then active = lvAsc
                elseif id == "SORT_DESC" then active = lvDesc
                end
                r:SetSelected(active)
                local stateDot = active and "|cff10b981●|r " or ""
                if id == "SET_LV_FILTER" then
                    local rangeStr = (st.minLv or st.maxLv) and ((st.minLv or 1) == (st.maxLv or 25) and tostring(st.minLv or 1) or ((st.minLv or 1) .. "-" .. (st.maxLv or 25))) or ns:T("全部未满级")
                    r.text:SetText(stateDot .. ns:TF("设置筛选等级：%s", rangeStr))
                else
                    r.text:SetText(stateDot .. ns:T(d.label))
                end
            end
        end

        ns.QueueFilterDrawer = qd
    end

    if ns.QueueFilterDrawer.qSub then ns.QueueFilterDrawer.qSub:Hide() end
    if ns.MainFrame then
        ns.QueueFilterDrawer:SetScale(ns.MainFrame:GetEffectiveScale() / UIParent:GetEffectiveScale())
    end
    ns.QueueFilterDrawer:ClearAllPoints()
    ns.QueueFilterDrawer:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", -182, -4)
    ns.QueueFilterDrawer:RefreshUI()
    ns.QueueFilterDrawer:Show()
    ns:EnablePopupClickCatcher(ns.QueueFilterDrawer)
end

-- ==================== 4. 宠物右键菜单（消除 HookScript 泄漏，静态事件分发） ====================
local PET_MENU_STATIC_LABELS = {
    [2] = "编辑宠物备注",
    [3] = "宠物标签",
    [4] = "查找相似宠物",
    [5] = "查找相同技能组",
    [6] = "查找相关队伍",
    [7] = "重命名",
    [9] = "加入队列首位",
    [10] = "放生宠物",
    [11] = "装入笼中",
    [12] = "取消",
}

function ns:ShowPetContextMenu(anchorRow, petData)
    if not petData then return end
    self:HideAllPopups()

    if not ns.PetContextMenu then
        local pm = CreateFrame("Frame", "WishPetTacticsPetContextMenu", UIParent, "BackdropTemplate")
        pm:SetSize(162, 272)
        pm:SetFrameStrata("FULLSCREEN_DIALOG")
        pm:SetFrameLevel(190)
        pm:SetClampedToScreen(true)
        pm:EnableMouse(true)
        Theme:ApplyBackdrop(pm, Theme.Colors.bgPopup, Theme.Colors.border, true)

        local headerTitle = pm:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        headerTitle:SetPoint("TOPLEFT", 12, -8)
        headerTitle:SetPoint("RIGHT", -8, 0)
        headerTitle:SetJustifyH("LEFT")
        headerTitle:SetWordWrap(false)
        headerTitle:SetTextColor(0.0, 0.80, 1.0, 1)
        Theme:HookLocalizedFontString(headerTitle)
        pm.headerTitle = headerTitle

        local markerSub = CreateFrame("Frame", "WishPetTacticsPetMarkerSubMenu", pm, "BackdropTemplate")
        markerSub:SetSize(148, 218)
        markerSub:SetPoint("TOPLEFT", pm, "TOPRIGHT", 3, -50)
        markerSub:SetFrameStrata("FULLSCREEN_DIALOG")
        markerSub:SetFrameLevel(200)
        markerSub:SetClampedToScreen(true)
        markerSub:EnableMouse(true)
        Theme:ApplyBackdrop(markerSub, Theme.Colors.bgPopup, Theme.Colors.border, true)
        markerSub:Hide()
        markerSub.btns = {}

        for m = 1, 9 do
            local mb = Theme:CreateMenuRow(markerSub, 140, 23, "")
            mb:SetPoint("TOPLEFT", 4, -4 - ((m - 1) * 23.5))
            mb.markerIndex = m
            mb:SetScript("OnClick", function(selfBtn)
                local pData = pm.petData
                local petID = pData and pData.petID
                if petID then
                    ns.db.petMarkers = ns.db.petMarkers or {}
                    local mIdx = selfBtn.markerIndex
                    if mIdx == 9 or ns.db.petMarkers[petID] == mIdx then
                        ns.db.petMarkers[petID] = nil
                    else
                        ns.db.petMarkers[petID] = mIdx
                    end
                    if ns.InvalidatePetListResults then ns:InvalidatePetListResults() end
                end
                ns:HideAllPopups()
                RefreshPetDrawerAndUI(false)
            end)
            markerSub.btns[m] = mb
        end
        markerSub.btns[9].text:SetText(ns:T("清除宠物标签"))
        ns.PetMarkerSubMenu = markerSub

        pm.items = {}
        for i = 1, 12 do
            local item = Theme:CreateMenuRow(pm, 154, 23, "")
            item:SetPoint("TOPLEFT", 4, -28 - ((i - 1) * 24))
            item.rowIdx = i

            item.arrow = Theme:CreateArrowTexture(item, 11, "RIGHT")
            item.arrow:SetPoint("RIGHT", -6, 0)
            item.arrow:SetVertexColor(0.38, 0.65, 0.98, 1)
            item.arrow:SetShown(i == 3)

            if PET_MENU_STATIC_LABELS[i] then
                item.text:SetText(ns:T(PET_MENU_STATIC_LABELS[i]))
            end

            item:HookScript("OnEnter", function(selfBtn)
                if selfBtn.rowIdx == 3 then
                    AnchorSubMenuSmart(pm, selfBtn, markerSub, 148)
                    markerSub:SetFrameLevel(pm:GetFrameLevel() + 5)
                    markerSub:Show()
                else
                    markerSub:Hide()
                end
            end)

            item:SetScript("OnClick", function(selfBtn)
                local pData = pm.petData
                if not pData then return end
                local idx = selfBtn.rowIdx
                local petID = pData.petID
                local speciesID = pData.speciesID

                if idx == 1 then
                    if petID then C_PetJournal.SummonPetByGUID(petID) end
                    ns:HideAllPopups()
                elseif idx == 2 then
                    ns:HideAllPopups()
                    if ns.ShowPetNoteModal then ns:ShowPetNoteModal(speciesID, pData.name) end
                elseif idx == 4 then
                    ns:HideAllPopups()
                    local st = GetPetFilterState()
                    ns.SearchFilter:ResetPetFilters()
                    st.similarSpecies = speciesID
                    if ns.PetPickerModal then ns.PetPickerModal.mode = "PETS" end
                    RefreshPetDrawerAndUI(true)
                elseif idx == 5 then
                    ns:HideAllPopups()
                    local st = GetPetFilterState()
                    ns.SearchFilter:ResetPetFilters()
                    st.movesetSpecies = speciesID
                    if ns.PetPickerModal then ns.PetPickerModal.mode = "PETS" end
                    RefreshPetDrawerAndUI(true)
                elseif idx == 6 then
                    ns:HideAllPopups()
                    ns:FindRelatedTeams(speciesID)
                elseif idx == 7 then
                    ns:HideAllPopups()
                    if petID and ns.ShowPetRenameModal then
                        ns:ShowPetRenameModal(petID, pData.customName or pData.name)
                    end
                elseif idx == 8 then
                    ns:HideAllPopups()
                    if petID then
                        C_PetJournal.SetFavorite(petID, pData.isFavorite and 0 or 1)
                        C_Timer.After(0.15, RefreshAfterFavoriteToggle)
                    end
                elseif idx == 9 then
                    ns:HideAllPopups()
                    if petID and ns.Leveling and ns.Leveling.IsPetInQueue and ns.Leveling:IsPetInQueue(petID) then
                        ns.Leveling:TogglePetInQueue(petID)
                        RefreshPetDrawerAndUI(true)
                    else
                        if ns.Leveling:MovePetToQueueFront(petID) then
                            RefreshPetDrawerAndUI(true)
                        else
                            ns:PrintError(ns:T("请选择已拥有且未满25级的可对战宠物。"))
                        end
                    end
                elseif idx == 10 then
                    ns:HideAllPopups()
                    if petID and C_PetJournal and C_PetJournal.PetCanBeReleased and C_PetJournal.PetCanBeReleased(petID) then
                        if not StaticPopupDialogs["WISH_PET_TACTICS_RELEASE_PET"] then
                            StaticPopupDialogs["WISH_PET_TACTICS_RELEASE_PET"] = {
                                text = ns:T("确定要放生宠物「%s」吗？放生后无法找回！"),
                                button1 = ACCEPT,
                                button2 = CANCEL,
                                OnAccept = function(self, data)
                                    if data and C_PetJournal and C_PetJournal.ReleasePetByID then
                                        C_PetJournal.ReleasePetByID(data)
                                        if ns.InvalidatePetListResults then ns:InvalidatePetListResults() end
                                        C_Timer.After(0.15, function() RefreshPetDrawerAndUI(true) end)
                                    end
                                end,
                                timeout = 0,
                                whileDead = true,
                                hideOnEscape = true,
                                preferredIndex = 3,
                            }
                        end
                        local petName = pData.customName or pData.name or ns:T("宠物")
                        local dlg = StaticPopup_Show("WISH_PET_TACTICS_RELEASE_PET", petName)
                        if dlg then dlg.data = petID end
                    end
                elseif idx == 11 then
                    ns:HideAllPopups()
                    if petID and C_PetJournal.PetIsTradable and C_PetJournal.PetIsTradable(petID)
                        and not InCombatLockdown() and not C_PetBattles.IsInBattle() then
                        if not StaticPopupDialogs["WISH_PET_TACTICS_CAGE_PET"] then
                            StaticPopupDialogs["WISH_PET_TACTICS_CAGE_PET"] = {
                                text = ns.locale == "zhTW" and "將寵物「%s」裝入籠中？" or ns.locale == "zhCN" and "将宠物「%s」装入笼中？" or "Put %s in a cage?",
                                button1 = ACCEPT, button2 = CANCEL,
                                OnAccept = function(_, id)
                                    if id and C_PetJournal.PetIsTradable(id) and not InCombatLockdown()
                                        and not C_PetBattles.IsInBattle() then
                                        C_PetJournal.CagePetByID(id)
                                    end
                                end,
                                timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
                            }
                        end
                        local dlg = StaticPopup_Show("WISH_PET_TACTICS_CAGE_PET", pData.customName or pData.name or ns:T("宠物"))
                        if dlg then dlg.data = petID end
                    end
                elseif idx == 12 then
                    ns:HideAllPopups()
                end
            end)

            pm.items[i] = item
        end
        ns.PetContextMenu = pm
    end

    local pm = ns.PetContextMenu
    pm.petData = petData
    if ns.MainFrame then
        pm:SetScale(ns.MainFrame:GetEffectiveScale() / UIParent:GetEffectiveScale())
    end
    local markerSub = ns.PetMarkerSubMenu
    markerSub:Hide()

    local petID = petData.petID
    local isSummoned = (petID and C_PetJournal.GetSummonedPetGUID() == petID)
    pm.headerTitle:SetText(petData.name or ns:T("宠物"))

    ns.db.petMarkers = ns.db.petMarkers or {}
    local curM = petID and ns.db.petMarkers[petID] or nil
    for m = 1, 8 do
        local mb = markerSub.btns[m]
        local mName = _G["RAID_TARGET_" .. m] or ("标签 " .. m)
        local isSel = (curM == m)
        mb:SetSelected(isSel)
        mb.text:SetText(string.format("%s|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:14:14|t %s", isSel and "|cff10b981●|r " or "", m, mName))
    end
    markerSub.btns[9]:SetSelected(false)

    pm.items[1].text:SetText(ns:T(isSummoned and "解散" or "召唤"))
    pm.items[8].text:SetText(ns:T(petData.isFavorite and "取消收藏" or "添加收藏"))
    local inQueue = petID and ns.Leveling and ns.Leveling.IsPetInQueue and ns.Leveling:IsPetInQueue(petID)
    pm.items[9].text:SetText(ns:T(inQueue and "移出练级队列" or "加入队列首位"))

    local visibleRows = 0
    for _, i in ipairs({1, 11, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12}) do
        local item = pm.items[i]
        local visible = true
        if i == 9 then
            visible = (petID ~= nil and (petData.level or 25) < 25)
        elseif i == 10 then
            visible = (petID ~= nil and C_PetJournal and C_PetJournal.PetCanBeReleased and C_PetJournal.PetCanBeReleased(petID)) and true or false
        elseif i == 11 then
            visible = (petID and C_PetJournal.PetIsTradable and C_PetJournal.PetIsTradable(petID)) and true or false
        end
        item:SetShown(visible)
        if visible then
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT", 4, -28 - visibleRows * 24)
            visibleRows = visibleRows + 1
        end
    end
    pm:SetHeight(32 + visibleRows * 24)

    ShowAnchoredContextMenu(pm, anchorRow, function()
        local item = anchorRow.itemData or anchorRow.pet
        return item and (item == petData or (petID and item.petID == petID))
    end)
end

-- ==================== 5. 队伍列表右键菜单（支持导出队伍字符串 / 单独导出纯脚本） ====================
local TEAM_MENU_LABELS = {
    [1]  = "|cff38bdf8编辑队伍|r",
    [2]  = "重命名",
    [3]  = "|cffc678dd编辑脚本|r",
    [4]  = "移动到分组",
    [5]  = "更改关联目标",
    [6]  = "|cff38bdf8新建队伍|r",
    [7]  = "|cff10b981新建分组|r",
    [8]  = "导出队伍（含脚本）",
    [9]  = ns:T("导出脚本"),
    [10] = "|cffff4d4d删除队伍|r",
    [11] = ns.locale == "zhTW" and "查看戰術備註" or ns.locale == "zhCN" and "查看战术备注" or "Strategy notes",
    [12] = ns:ForumText("本队未满级宠物加入队列", "本隊未滿級寵物加入佇列", "Queue under-level pets"),
    [13] = "取消",
}

function ns:ShowTeamContextMenu(anchorRow, teamIndex)
    self:HideAllPopups()
    local team = ns.db.teams[teamIndex]
    if not team then return end

    if not ns.ContextMenu then
        local cm = CreateFrame("Frame", "WishPetTacticsContextMenu", UIParent, "BackdropTemplate")
        cm:SetSize(212, #TEAM_MENU_LABELS * 24 + 8)
        cm:SetFrameStrata("FULLSCREEN_DIALOG")
        cm:SetFrameLevel(190)
        cm:SetClampedToScreen(true)
        cm:EnableMouse(true)
        Theme:ApplyBackdrop(cm, Theme.Colors.bgPopup, Theme.Colors.border, true)

        local grpSub = CreateFrame("Frame", "WishPetTacticsTeamGroupSubMenu", cm, "BackdropTemplate")
        grpSub:SetSize(166, 200)
        grpSub:SetPoint("TOPLEFT", cm, "TOPRIGHT", 3, -24)
        grpSub:SetFrameStrata("FULLSCREEN_DIALOG")
        grpSub:SetFrameLevel(200)
        grpSub:SetClampedToScreen(true)
        grpSub:EnableMouse(true)
        Theme:ApplyBackdrop(grpSub, Theme.Colors.bgPopup, Theme.Colors.border, true)
        grpSub:Hide()
        grpSub.rows = {}

        for g = 1, 12 do
            local gr = Theme:CreateMenuRow(grpSub, 158, 23, "")
            gr:SetPoint("TOPLEFT", 4, -4 - ((g - 1) * 23.5))
            gr:SetScript("OnClick", function(selfBtn)
                local tObj = cm.teamIndex and ns.db.teams[cm.teamIndex]
                if tObj and selfBtn.groupName then
                    tObj.group = selfBtn.groupName
                    MarkTreeAndRoutesDirty()
                end
                ns:HideAllPopups()
                ns:RefreshAllUI()
            end)
            grpSub.rows[g] = gr
        end
        cm.grpSub = grpSub

        cm.items = {}
        for i = 1, #TEAM_MENU_LABELS do
            local item = Theme:CreateMenuRow(cm, 204, 24, TEAM_MENU_LABELS[i])
            item:SetPoint("TOPLEFT", 4, -4 - ((i - 1) * 24))
            item.rowIdx = i

            item.arrow = Theme:CreateArrowTexture(item, 11, "RIGHT")
            item.arrow:SetPoint("RIGHT", -6, 0)
            item.arrow:SetVertexColor(0.38, 0.65, 0.98, 1)
            item.arrow:SetShown(i == 4)

            item:HookScript("OnEnter", function(selfBtn)
                if selfBtn.rowIdx == 4 then
                    AnchorSubMenuSmart(cm, selfBtn, grpSub, 166)
                    grpSub:SetFrameLevel(cm:GetFrameLevel() + 5)
                    grpSub:Show()
                else
                    grpSub:Hide()
                end
            end)

            item:SetScript("OnClick", function(selfBtn)
                local tIdx = cm.teamIndex
                local tObj = tIdx and ns.db.teams[tIdx]
                if not tObj then
                    ns:HideAllPopups()
                    return
                end
                local idx = selfBtn.rowIdx

                if idx == 1 then
                    ns:HideAllPopups()
                    ns:OpenCompactTeamEditor(tIdx)
                elseif idx == 2 then
                    ns:HideAllPopups()
                    if ns.ShowTeamEditModal then ns:ShowTeamEditModal(tIdx) end
                elseif idx == 3 then
                    ns:HideAllPopups()
                    ns:RequestCompactTeamSwitch(tIdx, function()
                        if ns.ToggleScriptWorkspace then ns:ToggleScriptWorkspace(true) end
                    end)
                elseif idx == 5 then
                    ns:HideAllPopups()
                    ns:ShowChangeTeamTargetModal(tObj, nil)
                elseif idx == 6 then
                    ns:HideAllPopups()
                    ns:BeginCompactTeamDraft()
                elseif idx == 7 then
                    ns:ShowQuickInputModal("NEW_GROUP")
                elseif idx == 8 then
                    ns:HideAllPopups()
                    OpenTeamStringExportModal(tObj, tIdx, nil)
                elseif idx == 9 then
                    ns:HideAllPopups()
                    OpenTeamScriptExportModal(tObj)
                elseif idx == 10 then
                    ns:HideAllPopups()
                    if #ns.db.teams > 1 then
                        RequestDestructiveDelete({tObj}, function()
                            if ns:DeleteTeamByName(tObj.name) then ns:RefreshAllUI() end
                        end)
                    end
                elseif idx == 11 then
                    ns:HideAllPopups()
                    ns:ShowTeamNotes(tObj)
                elseif idx == 12 then
                    ns:HideAllPopups()
                    ns:EnqueueTeamPets({tObj})
                elseif idx == 13 then
                    ns:HideAllPopups()
                end
            end)

            cm.items[i] = item
        end
        ns.ContextMenu = cm
    end

    local cm = ns.ContextMenu
    cm.teamIndex = teamIndex
    local grpSub = cm.grpSub
    grpSub:Hide()

    if ns.MainFrame then
        cm:SetScale(ns.MainFrame:GetEffectiveScale() / UIParent:GetEffectiveScale())
    end
    cm:SetFrameLevel(math.max(220, (anchorRow and anchorRow:GetFrameLevel() or 190) + 20))

    ns.db.teamGroups = ns.db.teamGroups or { "最爱队伍", "未分组队伍", "暗影界", "宠物地下城" }
    local gCount = math.min(12, #ns.db.teamGroups)
    grpSub:SetHeight(gCount * 23.5 + 8)
    for g = 1, 12 do
        local gr = grpSub.rows[g]
        local gName = ns.db.teamGroups[g]
        if gName then
            gr:Show()
            gr.groupName = gName
            local isCur = ((team.group or "未分组队伍") == gName)
            gr:SetSelected(isCur)
            gr.text:SetText((isCur and "|cff10b981●|r " or "") .. ns:T(gName))
        else
            gr.groupName = nil
            gr:Hide()
        end
    end

    local fromHeader = anchorRow == (ns.MainFrame and ns.MainFrame.teamHubBtn)
    local fromCurrentLink = anchorRow == (ns.MainFrame and ns.MainFrame.compactTeamLink)
        or anchorRow == (ns.MainFrame and ns.MainFrame.minimalTeamLink)
    grpSub:ClearAllPoints()
    if fromHeader then
        grpSub:SetPoint("TOPRIGHT", cm, "TOPLEFT", -3, -24)
    else
        grpSub:SetPoint("TOPLEFT", cm, "TOPRIGHT", 3, -24)
    end
    ShowAnchoredContextMenu(cm, anchorRow, function()
        if ns.db.teams[teamIndex] ~= team then return false end
        if fromHeader or fromCurrentLink then
            return (ns.db.selectedTeamIdx or 1) == teamIndex
        end
        local node = anchorRow.node
        if node then
            return node.nodeType == "TEAM" and node.team == team and node.teamIndex == teamIndex
        end
        return anchorRow.teamIndex == teamIndex
    end, fromHeader)
end

-- ==================== 6. 目标换队中心：左侧目标行右键菜单（导出目标队伍 / 单独导出脚本 / 跨目标删除保护） ====================
local ROUTE_TARGET_MENU_LABELS = {
    [1] = "加载目标队伍",
    [2] = "|cff38bdf8为目标新建队伍|r",
    [3] = ns:T("|cff10b981导出目标队伍（含脚本）|r"),
    [4] = ns:T("导出目标脚本"),
    [5] = "|cffff4d4d删除目标（保留队伍）|r",
    [6] = "|cffff4d4d删除目标及关联队伍|r",
    [7] = "取消",
    [8] = "移动到分组",
    [9] = ns:ForumText("目标未满级宠物加入队列", "目標未滿級寵物加入佇列", "Queue under-level pets"),
}

function ns:ShowRouteTargetContextMenu(anchorRow, routeKey, matrixTargetKey)
    local route = routeKey and ns.db.routeMappings[routeKey]
    if not route then return end
    self:HideAllPopups()

    if not ns.RouteTargetContextMenu then
        local rtm = CreateFrame("Frame", "WishPetTacticsRouteTargetContextMenu", UIParent, "BackdropTemplate")
        rtm:SetSize(224, #ROUTE_TARGET_MENU_LABELS * 24 + 8)
        rtm:SetFrameStrata("FULLSCREEN_DIALOG")
        rtm:SetFrameLevel(290)
        rtm:SetClampedToScreen(true)
        rtm:EnableMouse(true)
        Theme:ApplyBackdrop(rtm, Theme.Colors.bgPopup, Theme.Colors.border, true)
        rtm.items = {}
        local groupSub = CreateFrame("Frame", "WishPetTacticsTargetGroupSubMenu", rtm, "BackdropTemplate")
        groupSub:SetSize(180, 32)
        groupSub:SetFrameStrata("FULLSCREEN_DIALOG")
        groupSub:SetClampedToScreen(true)
        groupSub:EnableMouse(true)
        Theme:ApplyBackdrop(groupSub, Theme.Colors.bgPopup, Theme.Colors.border, true)
        groupSub.rows, groupSub.offset = {}, 0
        groupSub:Hide()
        function groupSub:Refresh()
            local groups = ns.db.teamGroups or {}
            self.offset = math.max(0, math.min(self.offset, math.max(0, #groups - 12)))
            self:SetHeight(math.min(12, #groups) * 24 + 8)
            for i, row in ipairs(self.rows) do
                row.groupName = groups[self.offset + i]
                if row.groupName then row.text:SetText(ns:T(row.groupName)); row:Show() else row:Hide() end
            end
        end
        for i = 1, 12 do
            local row = Theme:CreateMenuRow(groupSub, 172, 24, "")
            row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 24)
            row:SetScript("OnClick", function(selfBtn)
                local key, group = rtm.routeKey, selfBtn.groupName
                if key and group then ns:MoveTargetToGroup(key, group) end
                ns:HideAllPopups()
                if ns.RefreshAllUI then ns:RefreshAllUI() end
            end)
            groupSub.rows[i] = row
        end
        groupSub:EnableMouseWheel(true)
        groupSub:SetScript("OnMouseWheel", function(self, delta) self.offset = self.offset - delta; self:Refresh() end)
        rtm.groupSub = groupSub
        rtm:HookScript("OnHide", function() groupSub:Hide() end)

        for i = 1, #ROUTE_TARGET_MENU_LABELS do
            local item = Theme:CreateMenuRow(rtm, 216, 24, ROUTE_TARGET_MENU_LABELS[i])
            item:SetPoint("TOPLEFT", 4, -4 - ((i - 1) * 24))
            item.rowIdx = i
            if i == 8 then
                item.arrow = Theme:CreateArrowTexture(item, 11, "RIGHT")
                item.arrow:SetPoint("RIGHT", -6, 0)
            end
            item:HookScript("OnEnter", function(selfBtn)
                if selfBtn.rowIdx == 8 then
                    AnchorSubMenuSmart(rtm, selfBtn, groupSub, 180)
                    groupSub:SetFrameLevel(rtm:GetFrameLevel() + 5)
                    groupSub:Refresh()
                    groupSub:Show()
                else groupSub:Hide() end
            end)
            item:SetScript("OnClick", function(selfBtn)
                local rKey = rtm.routeKey
                local route = rKey and ns.db.routeMappings[rKey]
                local idx = selfBtn.rowIdx
                if idx == 8 then
                    AnchorSubMenuSmart(rtm, selfBtn, groupSub, 180)
                    groupSub:SetFrameLevel(rtm:GetFrameLevel() + 5)
                    groupSub:Refresh(); groupSub:Show()
                    return
                end
                ns:HideAllPopups()
                if not route then return end

                if idx == 9 then
                    ns:EnqueueTargetPets(route)
                elseif idx == 1 then
                    if route.teams and route.teams[1] then
                        ns.db.lastActiveRouteKey = rKey
                        ns.AutoRouting:LoadTeamWithFallbackChain(route.teams[1], route)
                    end
                elseif idx == 2 then
                    ns:ShowTeamBuilderModal(rKey, nil, nil)
                elseif idx == 3 then
                    local exportStr, cnt = ns:ExportTargetRouteTeamsString(rKey)
                    if not exportStr or exportStr == "" or (cnt or 0) <= 0 then
                        ns:PrintError(LMenu("该目标下暂无可导出的队伍！", "該目標下暫無可匯出的隊伍！", "No teams under this target to export!"))
                        return
                    end
                    local rLabel = (route.npcName and route.npcName ~= "") and route.npcName or tostring(rKey)
                    local msg = string.format(LMenu(
                        "|cff10b981已导出目标 [%s] 下全部 %d 支队伍(含目标与脚本)，按 Ctrl+C 复制|r",
                        "|cff10b981已匯出目標 [%s] 下全部 %d 支隊伍(含目標與腳本)，按 Ctrl+C 複製|r",
                        "|cff10b981Exported %d team(s) for target [%s] (with scripts). Press Ctrl+C to copy.|r"
                    ), (ns.locale ~= "zhCN" and ns.locale ~= "zhTW") and cnt or rLabel, (ns.locale ~= "zhCN" and ns.locale ~= "zhTW") and rLabel or cnt)
                    ns:ShowExportModalWithText(exportStr, msg, "TEAM")
                elseif idx == 4 then
                    local scriptStr, cnt = ns:ExportTargetRouteScripts(rKey)
                    if not scriptStr or scriptStr == "" or (cnt or 0) <= 0 then
                        ns:PrintError(LMenu("该目标下暂无对战脚本可导出！", "該目標下暫無對戰腳本可匯出！", "No battle scripts under this target to export!"))
                        return
                    end
                    local rLabel = (route.npcName and route.npcName ~= "") and route.npcName or tostring(rKey)
                    local msg = string.format(LMenu(
                        "|cff10b981已单独导出目标 [%s] 的对战脚本(%d队)，按 Ctrl+C 复制|r",
                        "|cff10b981已單獨匯出目標 [%s] 的對戰腳本(%d隊)，按 Ctrl+C 複製|r",
                        "|cff10b981Exported battle script(s) for target [%s] (%d). Press Ctrl+C to copy.|r"
                    ), rLabel, cnt)
                    ns:ShowExportModalWithText(scriptStr, msg, "SCRIPT")
                elseif idx == 5 then
                    ns:DeleteTargetRoute(rKey)
                    if ns.RoutingModal then
                        if ns.RoutingModal.selectedKey == rKey then
                            ns.RoutingModal.selectedKey = nil
                            local tNpcID, tNpcName = ns.AutoRouting:GetUnitNPCID("target")
                            ns.RoutingModal.pendingTargetID = tNpcID
                            ns.RoutingModal.pendingTargetName = tNpcName
                        end
                        ns.RoutingModal:Refresh()
                    end
                    ns:RefreshAllUI()
                elseif idx == 6 then
                    local teamsToDelete, teamObjects = {}, {}
                    local savedRoute = CopyTable(route)
                    if route.teams then
                        for _, tn in ipairs(route.teams) do
                            teamsToDelete[#teamsToDelete + 1] = tn
                            local obj = ns.AutoRouting:FindTeamByName(tn)
                            if obj then teamObjects[#teamObjects + 1] = obj end
                        end
                    end
                    RequestDestructiveDelete(teamObjects, function()
                        if ns.db.routeMappings[rKey] ~= route or route.npcID ~= savedRoute.npcID
                            or route.npcName ~= savedRoute.npcName or route.teamName ~= savedRoute.teamName
                            or #(route.teams or {}) ~= #(savedRoute.teams or {}) then
                            ns:PrintError(ns:UXText("previewChanged")); return
                        end
                        for i, name in ipairs(route.teams or {}) do
                            if name ~= savedRoute.teams[i] then ns:PrintError(ns:UXText("previewChanged")); return end
                        end
                        ns:DeleteTargetRoute(rKey)
                        for _, tn in ipairs(teamsToDelete) do
                            if not ns:FindRouteContainingTeam(tn) then ns:DeleteTeamByName(tn) end
                        end
                        if ns.RoutingModal then
                            if ns.RoutingModal.selectedKey == rKey then
                                ns.RoutingModal.selectedKey = nil
                                local tNpcID, tNpcName = ns.AutoRouting:GetUnitNPCID("target")
                                ns.RoutingModal.pendingTargetID = tNpcID
                                ns.RoutingModal.pendingTargetName = tNpcName
                            end
                            ns.RoutingModal:Refresh()
                        end
                        ns:RefreshAllUI()
                    end)
                end
            end)
            rtm.items[i] = item
        end
        ns.RouteTargetContextMenu = rtm
    end

    local rtm = ns.RouteTargetContextMenu
    rtm.routeKey = routeKey
    if ns.MainFrame then
        rtm:SetScale(ns.MainFrame:GetEffectiveScale() / UIParent:GetEffectiveScale())
    end
    rtm:SetFrameLevel(math.max(290, (anchorRow and anchorRow:GetFrameLevel() or 260) + 25))

    rtm.groupSub:Hide()
    rtm.groupSub.offset = 0
    local order = matrixTargetKey and {8, 9, 3, 4, 5, 6, 7} or {1, 2, 8, 9, 3, 4, 5, 6, 7}
    for _, item in ipairs(rtm.items) do item:Hide() end
    for row, idx in ipairs(order) do
        local item = rtm.items[idx]
        item:ClearAllPoints()
        item:SetPoint("TOPLEFT", 4, -4 - (row - 1) * 24)
        item:Show()
    end
    rtm:SetHeight(#order * 24 + 8)

    ShowAnchoredContextMenu(rtm, anchorRow, function()
        if ns.db.routeMappings[routeKey] ~= route then return false end
        if matrixTargetKey then
            local node = anchorRow.node
            return node and node.nodeType == "TARGET"
                and node.targetKey == matrixTargetKey and node.routeKey == routeKey
        end
        return anchorRow.routeKey == routeKey
    end)
end

-- ==================== 6.5 目标换队中心：右侧目标内队伍右键菜单（支持导出队伍字符串 / 单独导出脚本） ====================
local ROUTE_TEAM_MENU_LABELS = {
    [1]  = "|cff10b981加载队伍|r",
    [2]  = "|cff38bdf8编辑队伍|r",
    [3]  = "|cffc678dd编辑脚本|r",
    [4]  = "重命名队伍",
    [5]  = "更改关联目标",
    [6]  = "导出队伍（含脚本）",
    [7]  = ns:T("导出脚本"),
    [8]  = "|cffffb800解除当前目标关联|r",
    [9]  = "|cffff4d4d删除队伍|r",
    [10] = ns.locale == "zhTW" and "查看戰術備註" or ns.locale == "zhCN" and "查看战术备注" or "Strategy notes",
    [11] = ns:ForumText("本队未满级宠物加入队列", "本隊未滿級寵物加入佇列", "Queue under-level pets"),
    [12] = "取消",
}

function ns:ShowRouteTeamContextMenu(anchorRow, routeKey, teamName)
    if not teamName then return end
    self:HideAllPopups()

    local teamObj = ns.AutoRouting:FindTeamByName(teamName)
    if not teamObj then return end

    if not ns.RouteTeamContextMenu then
        local rcm = CreateFrame("Frame", "WishPetTacticsRouteTeamContextMenu", UIParent, "BackdropTemplate")
        rcm:SetSize(220, #ROUTE_TEAM_MENU_LABELS * 24 + 8)
        rcm:SetFrameStrata("FULLSCREEN_DIALOG")
        rcm:SetFrameLevel(290)
        rcm:SetClampedToScreen(true)
        rcm:EnableMouse(true)
        Theme:ApplyBackdrop(rcm, Theme.Colors.bgPopup, Theme.Colors.border, true)
        rcm.items = {}

        for i = 1, #ROUTE_TEAM_MENU_LABELS do
            local item = Theme:CreateMenuRow(rcm, 212, 24, ROUTE_TEAM_MENU_LABELS[i])
            item:SetPoint("TOPLEFT", 4, -4 - ((i - 1) * 24))
            item.rowIdx = i
            item:SetScript("OnClick", function(selfBtn)
                local idx = selfBtn.rowIdx
                local tName = rcm.teamName
                local rKey = rcm.routeKey
                local tObj, tIdx = ns.AutoRouting:FindTeamByName(tName)
                ns:HideAllPopups()

                if idx == 1 and tObj and tIdx then
                    ns:RequestCompactTeamSwitch(tIdx)
                elseif idx == 2 and tObj and tIdx then
                    ns:ShowTeamBuilderModal(rKey, tObj.group, tIdx)
                elseif idx == 3 and tObj and tIdx then
                    ns:RequestCompactTeamSwitch(tIdx, function()
                        if ns.ToggleScriptWorkspace then ns:ToggleScriptWorkspace(true) end
                    end)
                elseif idx == 4 and tIdx then
                    if ns.ShowTeamEditModal then ns:ShowTeamEditModal(tIdx) end
                elseif idx == 5 and tObj then
                    ns:ShowChangeTeamTargetModal(tObj, rKey)
                elseif idx == 6 and tObj then
                    local route = rKey and ns.db and ns.db.routeMappings and ns.db.routeMappings[rKey]
                    local overrideID = route and tonumber(route.npcID) or nil
                    OpenTeamStringExportModal(tObj, tIdx, overrideID)
                elseif idx == 7 and tObj then
                    OpenTeamScriptExportModal(tObj)
                elseif idx == 8 and tName then
                    ns:RemoveTeamFromTarget(tName, rKey)
                    if ns.RoutingModal and ns.RoutingModal:IsShown() then ns.RoutingModal:Refresh() end
                    ns:RefreshAllUI()
                elseif idx == 9 and tObj and #ns.db.teams > 1 then
                    RequestDestructiveDelete({tObj}, function()
                        ns:DeleteTeamByName(tObj.name)
                        if ns.RoutingModal and ns.RoutingModal:IsShown() then ns.RoutingModal:Refresh() end
                        ns:RefreshAllUI()
                    end)
                elseif idx == 10 and tObj then
                    ns:ShowTeamNotes(tObj)
                elseif idx == 11 and tObj then
                    ns:EnqueueTeamPets({tObj})
                end
            end)
            rcm.items[i] = item
        end
        ns.RouteTeamContextMenu = rcm
    end

    local rcm = ns.RouteTeamContextMenu
    rcm.routeKey = routeKey
    rcm.teamName = teamName
    if ns.MainFrame then
        rcm:SetScale(ns.MainFrame:GetEffectiveScale() / UIParent:GetEffectiveScale())
    end
    rcm:SetFrameLevel(math.max(290, (anchorRow and anchorRow:GetFrameLevel() or 260) + 25))

    ShowAnchoredContextMenu(rcm, anchorRow, function()
        return ns.RoutingModal.selectedKey == routeKey
            and anchorRow.teamName == teamName and anchorRow.tObj == teamObj
    end)
end

-- ==================== 6.8 独立新建/编辑队伍窗口的技能层数选择菜单（静态事件绑定 + 动态高层级） ====================
function ns:ShowBuilderAbilityMenu(anchorBtn, bm, slotIdx, abCol, speciesID)
    if ns.BuilderAbilityPopup and ns.BuilderAbilityPopup:IsShown() and ns.BuilderAbilityPopup.anchorBtn == anchorBtn then
        ns.BuilderAbilityPopup:Hide()
        ns.BuilderAbilityPopup.anchorBtn = nil
        return
    end
    if not speciesID or speciesID <= 0 then return end
    local sortedIDs, sortedLevels = ns:GetSortedPetAbilities(speciesID)
    if not sortedIDs or #sortedIDs < 6 then return end

    if not ns.BuilderAbilityPopup then
        local pop = CreateFrame("Frame", "WishPetTacticsBuilderAbilityPopup", UIParent, "BackdropTemplate")
        pop:SetSize(210, 66)
        pop:SetFrameStrata("FULLSCREEN_DIALOG")
        pop:SetFrameLevel(300)
        pop:EnableMouse(true)
        Theme:ApplyBackdrop(pop, Theme.Colors.bgPopup, Theme.Colors.border, true)
        pop.btns = {}

        for tier = 1, 2 do
            local b = Theme:CreateMenuRow(pop, 202, 26, "")
            b:SetPoint("TOPLEFT", 4, -4 - (tier - 1) * 28)
            b.icon = Theme:CreateCroppedIcon(b, 20)
            b.icon:SetPoint("LEFT", 6, 0)
            b.icon:EnableMouse(false)
            b.text:ClearAllPoints()
            b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
            b.text:SetPoint("RIGHT", -6, 0)

            b:SetScript("OnEnter", function(selfBtn)
                if selfBtn.abID then
                    ns:ShowAbilityTooltip(selfBtn, selfBtn.abID, 1400, 280, 280)
                end
            end)
            b:SetScript("OnLeave", function()
                ns:HideAbilityTooltip()
            end)
            b:SetScript("OnClick", function(selfBtn)
                local targetBM = pop.bm
                local slotState = targetBM and targetBM.builderState and targetBM.builderState.slots[pop.slotIdx]
                if slotState and pop.abCol and selfBtn.abID then
                    slotState.abilities[pop.abCol] = selfBtn.abID
                end
                pop:Hide()
                pop.anchorBtn = nil
                if targetBM and targetBM.RefreshBuilder then
                    targetBM:RefreshBuilder()
                end
            end)

            pop.btns[tier] = b
        end
        ns.BuilderAbilityPopup = pop
    end

    local pop = ns.BuilderAbilityPopup
    pop.anchorBtn = anchorBtn
    pop.bm = bm
    pop.slotIdx = slotIdx
    pop.abCol = abCol
    if ns.MainFrame then
        pop:SetScale(ns.MainFrame:GetEffectiveScale() / UIParent:GetEffectiveScale())
    end
    pop:SetFrameLevel(math.max(300, (bm and bm:GetFrameLevel() or 200) + 30))

    local slotState = bm.builderState and bm.builderState.slots[slotIdx]
    local curAbID = (slotState and slotState.abilities[abCol]) or sortedIDs[abCol] or 0

    for tier = 1, 2 do
        local idx = (tier == 1) and abCol or (abCol + 3)
        local abID = sortedIDs[idx]
        local unlockLv = sortedLevels and sortedLevels[idx] or (tier == 1 and 1 or 10)
        local abName, abIcon = C_PetJournal.GetPetAbilityInfo(abID)
        local btn = pop.btns[tier]

        btn.abID = abID
        btn.icon.icon:SetTexture(abIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local isSelected = (curAbID == abID)
        btn:SetSelected(isSelected)
        btn.text:SetText(string.format("%s%s|r |cff6b7280(Lv%d)|r", isSelected and "|cff10b981●|r |cff10b981" or "|cfff3f4f6", abName or ns:T("技能"), unlockLv))
    end

    pop:ClearAllPoints()
    pop:SetPoint("TOP", anchorBtn, "BOTTOM", 0, -4)
    pop:Show()
    ns:EnablePopupClickCatcher(pop)
end

local function GetBuilderDropSlot(builder)
    for index, card in ipairs(builder.slots) do
        if card:IsVisible() and card:IsMouseOver() then return index end
    end
end

local function UpdateBuilderDrag(builder)
    local source = builder.dragSource
    local target = GetBuilderDropSlot(builder)
    if builder.dragTarget == target then return end
    builder.dragTarget = target
    for index, card in ipairs(builder.slots) do
        local overlay = card.dragOverlay
        if index == source then
            overlay:SetBackdropColor(1, 0.65, 0.1, 0.22)
            overlay:SetBackdropBorderColor(1, 0.65, 0.1, 1)
            overlay.text:SetText(ns:TF("拖动 %d 号槽", source))
        elseif index == target then
            overlay:SetBackdropColor(0.1, 1, 0.6, 0.24)
            overlay:SetBackdropBorderColor(0.1, 1, 0.6, 1)
            overlay.text:SetText(ns:TF("松开：交换 %d ↔ %d", source, target))
        else
            overlay:SetBackdropColor(0.2, 0.6, 1, 0.12)
            overlay:SetBackdropBorderColor(0.2, 0.6, 1, 0.85)
            overlay.text:SetText(ns:T("拖到这里换位"))
        end
        overlay:Show()
    end
end

local function ClearBuilderDrag(builder)
    builder.dragSource, builder.dragTarget = nil, nil
    builder:SetScript("OnUpdate", nil)
    for _, card in ipairs(builder.slots) do card.dragOverlay:Hide() end
end

local function SwapBuilderSlots(builder, source, target)
    local state = builder.builderState
    state.slots[source], state.slots[target] = state.slots[target], state.slots[source]
    if state.activeSlot == source then
        state.activeSlot = target
    elseif state.activeSlot == target then
        state.activeSlot = source
    end
    if ns.PetPickerModal and ns.PetPickerModal:IsShown() then
        ns.PetPickerModal.lastSlot = state.activeSlot
    end
    if state.editingTeam and state.editingTeam.script and state.editingTeam.script ~= "" then
        builder.hint:SetText("|cffffc45c" .. ns:T("槽位已交换，请核对脚本中的槽位编号") .. "|r")
    end
    builder:RefreshBuilder()
end

-- ==================== 6.9 独立「新建 / 编辑队伍」3槽位配置弹出窗口 ====================
function ns:ShowTeamBuilderModal(routeKey, defaultGroup, editTeamIndex)
    local f = self.MainFrame
    if f and f:IsShown() and (f.compactDraft or self.staging.isDirty) then
        self:RequestHomeAction(function() self:ShowTeamBuilderModal(routeKey, defaultGroup, editTeamIndex) end)
        return
    end
    self:HideAllPopups()
    local parentFrame = ns:GetRoutingDialogParent()

    if not ns.TeamBuilderModal then
        local px = Theme:GetPixelScale()
        local bm = CreateFrame("Frame", "WishPetTacticsTeamBuilderModal", parentFrame, "BackdropTemplate")
        bm:Hide()
        bm:SetSize(480, 428)
        bm:SetPoint("CENTER", 0, 0)
        bm:SetFrameStrata("FULLSCREEN_DIALOG")
        bm:SetFrameLevel(280)
        bm:SetMovable(true)
        bm:SetClampedToScreen(true)
        bm:EnableMouse(true)
        bm:RegisterForDrag("LeftButton")
        bm:SetScript("OnDragStart", bm.StartMoving)
        bm:SetScript("OnDragStop", bm.StopMovingOrSizing)
        Theme:ApplyBackdrop(bm, { 0.073, 0.073, 0.073, 0.98 }, Theme.Colors.border, true)
        if ns.MakeModal then ns:MakeModal(bm) end
        Theme:EnableDialogDrag(bm)

        bm:HookScript("OnHide", function(selfModal)
            ClearBuilderDrag(selfModal)
            selfModal.nameBox:ClearFocus()
            selfModal.targetBox:ClearFocus()
            if selfModal.builderState then
                selfModal.builderState.editingTeamIndex = nil
                selfModal.builderState.editingTeam = nil
            end
            if ns.BuilderAbilityPopup and ns.BuilderAbilityPopup:IsShown() then
                ns.BuilderAbilityPopup:Hide()
                ns.BuilderAbilityPopup.anchorBtn = nil
            end
            if ns.PetPickerModal then
                if ns.RoutingModal and ns.RoutingModal:IsVisible() then
                    ns.PetPickerModal:Hide()
                    ns.PetPickerModal.lastSlot = nil
                end
                if ns.MainFrame then
                    ns.PetPickerModal:SetParent(ns.MainFrame)
                    ns.PetPickerModal:ClearAllPoints()
                    ns.PetPickerModal:SetPoint("TOPLEFT", ns.MainFrame, "TOPRIGHT", 6, 0)
                    ns.PetPickerModal:SetPoint("BOTTOMLEFT", ns.MainFrame, "BOTTOMRIGHT", 6, 0)
                    ns.PetPickerModal:SetFrameLevel(130)
                end
            end
            if ns.RoutingModal and ns.RoutingModal:IsShown() and ns.BringModalToFront then
                ns:BringModalToFront(ns.RoutingModal)
            end
        end)

        bm.builderState = {
            activeSlot = 1,
            routeKey = nil,
            defaultGroup = nil,
            editingTeamIndex = nil,
            slots = {
                [1] = { petID = nil, speciesID = 0, isLeveling = false, abilities = {0,0,0} },
                [2] = { petID = nil, speciesID = 0, isLeveling = false, abilities = {0,0,0} },
                [3] = { petID = nil, speciesID = 0, isLeveling = false, abilities = {0,0,0} },
            }
        }

        local title = bm:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 20, -16)
        Theme:HookLocalizedFontString(title)
        title:SetText(ns:T("|cff38bdf8NEW TEAM // 新建出战队伍|r"))
        bm.title = title

        local closeBtn = Theme:CreateCloseIconButton(bm, function() bm:Hide() end)
        closeBtn:SetPoint("TOPRIGHT", -18, -16)

        local hdrLine = bm:CreateTexture(nil, "BORDER")
        hdrLine:SetHeight(px)
        hdrLine:SetPoint("TOPLEFT", 20, -44)
        hdrLine:SetPoint("TOPRIGHT", -20, -44)
        hdrLine:SetTexture("Interface\\Buttons\\WHITE8X8")
        hdrLine:SetVertexColor(unpack(Theme.Colors.divider))

        local bNameLbl = bm:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bNameLbl:SetPoint("TOPLEFT", 20, -58)
        Theme:HookLocalizedFontString(bNameLbl)
        bNameLbl:SetText(ns:T("|cff38bdf8队伍名称:|r"))

        local bNameBox = Theme:CreateFlatEditBox(bm, 360, 26, "输入新队伍名称 (同名目标自动归类)...")
        bNameBox:SetPoint("LEFT", bNameLbl, "RIGHT", 10, 0)
        bm.nameBox = bNameBox

        local bTargetLbl = bm:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bTargetLbl:SetPoint("TOPLEFT", 20, -96)
        bTargetLbl:SetText(ns:T("关联目标"))

        local bTargetBox = Theme:CreateFlatEditBox(bm, 230, 26, "输入 NPC ID 或 NPC 名称...")
        bTargetBox:SetPoint("LEFT", bTargetLbl, "RIGHT", 10, 0)
        bTargetBox:SetPoint("RIGHT", bm, "RIGHT", -132, 0)
        bm.targetBox = bTargetBox

        local bCurrentTarget = Theme:CreateActionButton(bm, 108, 26, "使用当前目标", "add-target")
        bCurrentTarget:SetPoint("LEFT", bTargetBox, "RIGHT", 8, 0)
        bCurrentTarget:SetScript("OnClick", function(_, mouseButton)
            if mouseButton ~= "LeftButton" then return end
            local input = GetCurrentTargetInput()
            if input ~= "" then
                bTargetBox:SetText(input)
            else
                ReportMissingCurrentTarget()
                bTargetBox:SetFocus()
            end
        end)

        local bHintTxt = bm:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        bHintTxt:SetPoint("TOPLEFT", 20, -126)
        bHintTxt:SetPoint("TOPRIGHT", -20, -126)
        bHintTxt:SetJustifyH("LEFT")
        bHintTxt:SetWordWrap(false)
        Theme:HookLocalizedFontString(bHintTxt)
        bm.hint = bHintTxt

        bm.slots = {}
        local slotW = 136
        local slotH = 166
        local slotGap = 16

        function bm:AssignPetToSlot(slotIdx, petID)
            if not slotIdx or slotIdx < 1 or slotIdx > 3 or not petID then return end
            local st = self.builderState.slots[slotIdx]

            ClearCursor()
            ns.draggingPetID = nil
            ns.draggingQueuePetID = nil

            -- Only the slot's right-click action enables leveling. Selecting or
            -- dragging a pet from the queue must not change an ordinary slot.
            if st.isLeveling then
                st.randomType = nil
                for k = 1, 3 do
                    if k ~= slotIdx and self.builderState.slots[k].isLeveling then
                        self.builderState.slots[k].isLeveling = false
                        self.builderState.slots[k].petID = nil
                    end
                end
                st.isLeveling = true
                st.petID = "LEVELING"
                st.speciesID = 0
                st.abilities[1], st.abilities[2], st.abilities[3] = 0, 0, 0
            else
                local spID = C_PetJournal.GetPetInfoByPetID(petID) or 0
                if spID > 0 then
                    st.randomType = nil
                    st.isLeveling = false
                    st.petID = petID
                    st.speciesID = spID
                    local sortedIDs = ns:GetSortedPetAbilities(spID)
                    st.abilities[1] = (sortedIDs and sortedIDs[1]) or 0
                    st.abilities[2] = (sortedIDs and sortedIDs[2]) or 0
                    st.abilities[3] = (sortedIDs and sortedIDs[3]) or 0
                end
            end
            self:RefreshBuilder()
        end

        for s = 1, 3 do
            local sCard = CreateFrame("Button", nil, bm, "BackdropTemplate")
            sCard:SetSize(slotW, slotH)
            sCard:SetPoint("TOPLEFT", 20 + (s - 1) * (slotW + slotGap), -148)
            sCard:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            sCard:RegisterForDrag("LeftButton")
            Theme:ApplyBackdrop(sCard, BUILDER_BG_EMPTY, Theme.Colors.border, false)

            local iconHolder = CreateFrame("Frame", nil, sCard, "BackdropTemplate")
            iconHolder:SetSize(80, 80)
            iconHolder:SetPoint("TOP", sCard, "TOP", 0, -18)
            iconHolder:EnableMouse(false)
            Theme:ApplyBackdrop(iconHolder, Theme.Colors.bgInput, Theme.Colors.border, false)
            sCard.iconHolder = iconHolder

            local pTex = iconHolder:CreateTexture(nil, "ARTWORK")
            pTex:SetPoint("TOPLEFT", px, -px)
            pTex:SetPoint("BOTTOMRIGHT", -px, px)
            pTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            pTex:Hide()
            sCard.icon = pTex

            local plusTxt = iconHolder:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
            plusTxt:SetPoint("CENTER", 0, 0)
            local fPath = plusTxt:GetFont()
            if fPath then plusTxt:SetFont(fPath, 32, "OUTLINE") end
            plusTxt:SetText("|cff38bdf8+|r")
            sCard.plusTxt = plusTxt

            local nameLbl = sCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nameLbl:SetPoint("TOPLEFT", 6, -108)
            nameLbl:SetPoint("TOPRIGHT", -6, -108)
            nameLbl:SetJustifyH("CENTER")
            nameLbl:SetWordWrap(false)
            Theme:HookLocalizedFontString(nameLbl)
            sCard.nameLbl = nameLbl

            local stateLbl = sCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            stateLbl:SetPoint("TOP", nameLbl, "BOTTOM", 0, -4)
            Theme:HookLocalizedFontString(stateLbl)
            sCard.stateLbl = stateLbl

            local grip = sCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            grip:SetPoint("TOP", 0, -4)
            grip:SetText("|cff6ecbff" .. ns:TF("%d 号槽 · 拖动换位", s) .. "|r")

            local overlay = CreateFrame("Frame", nil, sCard, "BackdropTemplate")
            overlay:SetAllPoints(sCard)
            overlay:SetFrameLevel(sCard:GetFrameLevel() + 4)
            overlay:EnableMouse(false)
            overlay:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 3,
            })
            local banner = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
            banner:SetPoint("LEFT", 6, 0)
            banner:SetPoint("RIGHT", -6, 0)
            banner:SetHeight(28)
            banner:EnableMouse(false)
            Theme:ApplyBackdrop(banner, { 0.043, 0.043, 0.043, 0.96 }, Theme.Colors.borderBlue, false)
            overlay.text = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            overlay.text:SetPoint("LEFT", 4, 0)
            overlay.text:SetPoint("RIGHT", -4, 0)
            Theme:HookLocalizedFontString(overlay.text)
            overlay:Hide()
            sCard.dragOverlay = overlay

            sCard:SetScript("OnDragStart", function()
                if GetCursorInfo() or ns.draggingPetID or ns.draggingQueuePetID then return end
                if ns.BuilderAbilityPopup then
                    ns.BuilderAbilityPopup:Hide()
                    ns.BuilderAbilityPopup.anchorBtn = nil
                end
                ns:HideAllTooltips()
                bm.dragSource = s
                bm.dragTarget = false
                UpdateBuilderDrag(bm)
                bm:SetScript("OnUpdate", UpdateBuilderDrag)
            end)
            sCard:SetScript("OnDragStop", function()
                local source = bm.dragSource
                if source ~= s then return end
                local target = GetBuilderDropSlot(bm)
                ClearBuilderDrag(bm)
                if target and target ~= source then SwapBuilderSlots(bm, source, target) end
            end)

            sCard.abBtns = {}
            for abCol = 1, 3 do
                local abBtn = CreateFrame("Button", nil, bm, "BackdropTemplate")
                abBtn:SetSize(40, 40)
                abBtn:SetPoint("TOPLEFT", sCard, "BOTTOMLEFT", 2 + (abCol - 1) * 46, -8)
                Theme:ApplyBackdrop(abBtn, Theme.Colors.bgInput, Theme.Colors.border, false)

                local abTex = abBtn:CreateTexture(nil, "ARTWORK")
                abTex:SetPoint("TOPLEFT", px, -px)
                abTex:SetPoint("BOTTOMRIGHT", -px, px)
                abTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                abTex:Hide()
                abBtn.icon = abTex

                local abPlus = abBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                abPlus:SetPoint("CENTER", 0, 0)
                abPlus:SetText("+")
                abBtn.plus = abPlus

                abBtn:SetScript("OnEnter", function(self)
                    self:SetBackdropBorderColor(unpack(Theme.Colors.borderBlue))
                    if self.abID and self.abID > 0 then
                        ns:ShowAbilityTooltip(self, self.abID, 1400, 280, 280)
                    end
                end)
                abBtn:SetScript("OnLeave", function(self)
                    self:SetBackdropBorderColor(unpack(Theme.Colors.border))
                    ns:HideAbilityTooltip()
                end)
                abBtn:SetScript("OnClick", function(self)
                    local st = bm.builderState.slots[s]
                    if st and not st.isLeveling and st.speciesID and st.speciesID > 0 then
                        ns:ShowBuilderAbilityMenu(self, bm, s, abCol, st.speciesID)
                    end
                end)

                sCard.abBtns[abCol] = abBtn
            end

            sCard:SetScript("OnReceiveDrag", function()
                local cursorType, cursorPetID = GetCursorInfo()
                local dropID = (cursorType == "battlepet" and cursorPetID) or ns.draggingPetID or ns.draggingQueuePetID
                if cursorType == "battlepet" or dropID then
                    bm:AssignPetToSlot(s, dropID)
                end
            end)

            sCard:SetScript("OnClick", function(_, button)
                local st = bm.builderState.slots[s]
                if button == "RightButton" then
                    st.randomType = nil
                    for k = 1, 3 do
                        if k ~= s and bm.builderState.slots[k].isLeveling then
                            bm.builderState.slots[k].isLeveling = false
                            bm.builderState.slots[k].petID = nil
                        end
                    end
                    st.isLeveling = not st.isLeveling
                    if st.isLeveling then
                        st.petID = "LEVELING"
                        st.speciesID = 0
                        st.abilities[1], st.abilities[2], st.abilities[3] = 0, 0, 0
                    else
                        st.petID = nil
                    end
                    bm:RefreshBuilder()
                else
                    local cursorType, cursorPetID = GetCursorInfo()
                    local dropID = (cursorType == "battlepet" and cursorPetID) or ns.draggingPetID or ns.draggingQueuePetID
                    if dropID then
                        bm:AssignPetToSlot(s, dropID)
                        return
                    end
                    bm.builderState.activeSlot = s
                    bm:RefreshBuilder()

                    local wantTab = st.isLeveling and "QUEUE" or "PETS"
                    if not ns.PetPickerModal or not ns.PetPickerModal:IsShown() then
                        ns:TogglePetPickerDrawer(s, wantTab, false)
                    else
                        ns.PetPickerModal.lastSlot = s
                        ns.PetPickerModal.mode = wantTab
                        if ns.db and ns.db.settings then
                            ns.db.settings.lastPetDrawerTab = wantTab
                        end
                        ns.PetPickerModal:Refresh()
                    end
                    if ns.PetPickerModal then
                        ns.PetPickerModal:ClearAllPoints()
                        ns.PetPickerModal:SetPoint("TOPLEFT", bm, "TOPRIGHT", 6, 0)
                        ns.PetPickerModal:SetHeight(620)
                        ns.PetPickerModal:SetFrameStrata("FULLSCREEN_DIALOG")
                        ns.PetPickerModal:SetFrameLevel(bm:GetFrameLevel() + 10)
                        ns.PetPickerModal:Show()
                    end
                end
            end)

            bm.slots[s] = sCard
        end

        local bImportBtn = Theme:CreateActionButton(bm, 118, 30, "导入", "import", "导入队伍以快速创建")
        bImportBtn:SetPoint("BOTTOMLEFT", 20, 16)
        bImportBtn:SetScript("OnClick", function(_, button)
            if button ~= "LeftButton" then return end
            local state = bm.builderState
            if state.editingTeamIndex then return end
            local targetInput = strtrim(bm.targetBox:GetText() or "")
            local ctx
            if targetInput ~= "" then
                local npcID, npcName = 0, ""
                local pureID = string.match(targetInput, "^(%d+)$")
                local idPart, namePart = string.match(targetInput, "^(%d+)%s+(.+)$")
                if pureID then
                    npcID = tonumber(pureID) or 0
                elseif idPart then
                    npcID, npcName = tonumber(idPart) or 0, strtrim(namePart)
                else
                    npcName = targetInput
                end
                local _, rKey = ns:FindExistingRouteForNPC(npcID, npcName)
                ctx = { routeKey = rKey, npcID = npcID, npcName = npcName }
            end
            -- 转到现有导入流程，继续使用其脚本导入和重复队伍处理。
            bm:Hide()
            ns:ShowImportModal("TEAM", ctx)
        end)
        bm.importBtn = bImportBtn

        local bCancelBtn = Theme:CreateFlatButton(bm, 100, 30, "取消")
        bCancelBtn:SetPoint("BOTTOMRIGHT", -20, 16)
        bCancelBtn:SetScript("OnClick", function()
            bm:Hide()
        end)

        local bSaveBtn = Theme:CreateActionButton(bm, 148, 30, "创建队伍", "new-team", nil, "PRIMARY")
        bSaveBtn:SetPoint("RIGHT", bCancelBtn, "LEFT", -10, 0)
        bSaveBtn:SetScript("OnClick", function()
            local state = bm.builderState
            local editIdx = state.editingTeamIndex
            local editTeam = editIdx and ns.db.teams[editIdx]
            if editIdx and editTeam ~= state.editingTeam then
                bm:Hide()
                return
            end
            local targetInput = strtrim(bTargetBox:GetText() or "")
            local changedTarget = targetInput ~= state.initialTarget

            local function SelectAssignedTarget(key)
                if ns.RoutingModal then
                    ns.RoutingModal.pendingTargetID = nil
                    ns.RoutingModal.pendingTargetName = nil
                    ns.RoutingModal.selectedKey = key
                end
            end

            -- 分支 A：编辑现有队伍（更换宠物、切换技能、修改名称或经验槽）
            if editTeam then
                local rawName = strtrim(bNameBox:GetText() or "")
                if rawName ~= "" and rawName ~= editTeam.name then
                    ns:RenameTeam(editIdx, rawName, true)
                end

                local oldLevelingSlot = editTeam.hasLevelingSlot and editTeam.levelingSlot
                local oldFallback = editTeam.levelingFallback
                editTeam.levelingFallback = nil
                editTeam.pets            = { nil, nil, nil }
                editTeam.speciesLoadout  = { 0, 0, 0 }
                editTeam.abilities       = { {0,0,0}, {0,0,0}, {0,0,0} }
                editTeam.slotThresholds  = editTeam.slotThresholds or { [1] = 0, [2] = 0, [3] = 0 }
                editTeam.randomSlots     = {}
                editTeam.hasLevelingSlot = false

                for s = 1, 3 do
                    local st = bm.builderState.slots[s]
                    editTeam.slotThresholds[s] = st.threshold
                    if st.randomType ~= nil then
                        editTeam.randomSlots[s] = st.randomType
                    elseif st.isLeveling then
                        editTeam.hasLevelingSlot = true
                        editTeam.levelingSlot = s
                        if s == oldLevelingSlot then editTeam.levelingFallback = oldFallback end
                        if (editTeam.slotThresholds[s] or 0) <= 0 then
                            editTeam.slotThresholds[s] = 40
                        end
                        editTeam.pets[s] = "LEVELING"
                        editTeam.speciesLoadout[s] = 0
                        editTeam.abilities[s] = { 0, 0, 0 }
                    elseif st.speciesID and st.speciesID > 0 then
                        editTeam.pets[s] = st.petID
                        editTeam.speciesLoadout[s] = st.speciesID
                        editTeam.abilities[s] = ns.AutoRouting:ValidateAbilitiesForSpecies(st.speciesID, st.abilities)
                        ns.AutoRouting:RememberSlotSpeciesSkills(s, st.speciesID, editTeam.abilities[s])
                    end
                end

                editTeam.manualAbilities = true
                if changedTarget then
                    if targetInput ~= "" then
                        local ok, assignedKey = ns:AssignTeamToTarget(editTeam, targetInput, state.routeKey)
                        if ok then SelectAssignedTarget(assignedKey) end
                    elseif state.routeKey then
                        ns:RemoveTeamFromTarget(editTeam.name, state.routeKey)
                    else
                        for key in pairs(ns.db.routeMappings) do
                            ns:RemoveTeamFromTarget(editTeam.name, key)
                        end
                        editTeam.npcID, editTeam.npcName = 0, ""
                    end
                end
                MarkTreeAndRoutesDirty()

                if ns.db.selectedTeamIdx == editIdx then
                    ns.AutoRouting:ApplyTeamData(editTeam)
                end

                bm:Hide()
                if ns.RoutingModal and ns.RoutingModal:IsShown() then
                    ns.RoutingModal:Refresh()
                end
                ns:RefreshAllUI()
                return
            end

            -- 分支 B：新建队伍，优先应用显式输入的目标。
            local rKey = not changedTarget and state.routeKey
            local selRoute = rKey and ns.db.routeMappings[rKey]
            local rawName = strtrim(bNameBox:GetText() or "")
            if rawName == "" then
                rawName = (selRoute and selRoute.npcName and selRoute.npcName ~= "" and ns:TF("%s 新队", selRoute.npcName)) or (ns:T("新建队伍 #") .. (#ns.db.teams + 1))
            end

            local initNpcID = (selRoute and tonumber(selRoute.npcID)) or 0
            local initNpcName = (selRoute and selRoute.npcName) or ""

            local matchedNpcID, matchedNpcName, matchedGroup
            if not changedTarget then
                matchedNpcID, matchedNpcName, matchedGroup = ns:FindExistingTargetInfoForImport(
                    initNpcID, initNpcName ~= "" and initNpcName or rawName, nil
                )
            end

            local finalNpcID = selRoute and initNpcID or ((matchedNpcID and matchedNpcID > 0) and matchedNpcID or initNpcID)
            local finalNpcName = selRoute and initNpcName or ((matchedNpcName and matchedNpcName ~= "") and matchedNpcName or initNpcName)
            local finalGroup = matchedGroup
                or bm.builderState.defaultGroup
                or (ns.teamFilterState and ns.teamFilterState.group ~= "ALL" and ns.teamFilterState.group)
                or "未分组队伍"

            local newTeam = {
                name            = ns:GetUniqueTeamNameForImport(rawName),
                group           = ns:EnsureTeamGroup(finalGroup),
                npcID           = finalNpcID,
                npcName         = finalNpcName,
                gossipIndex     = 1,
                pets            = { nil, nil, nil },
                speciesLoadout  = { 0, 0, 0 },
                abilities       = { {0,0,0}, {0,0,0}, {0,0,0} },
                slotThresholds  = { [1] = 0, [2] = 0, [3] = 0 },
                hasLevelingSlot = false,
                levelingSlot    = 2,
                script          = ns:GetDefaultBattleScript(),
            }

            for s = 1, 3 do
                local st = bm.builderState.slots[s]
                if st.isLeveling then
                    newTeam.hasLevelingSlot = true
                    newTeam.levelingSlot = s
                    newTeam.slotThresholds[s] = 40
                    newTeam.pets[s] = "LEVELING"
                elseif st.speciesID and st.speciesID > 0 then
                    newTeam.pets[s] = st.petID
                    newTeam.speciesLoadout[s] = st.speciesID
                    newTeam.abilities[s] = ns.AutoRouting:ValidateAbilitiesForSpecies(st.speciesID, st.abilities)
                    ns.AutoRouting:RememberSlotSpeciesSkills(s, st.speciesID, newTeam.abilities[s])
                end
            end

            table.insert(ns.db.teams, newTeam)
            ns.db.selectedTeamIdx = #ns.db.teams

            local finalAssignedKey = nil
            if changedTarget and targetInput ~= "" then
                local ok, assignedKey = ns:AssignTeamToTarget(newTeam, targetInput, nil)
                if ok then
                    finalAssignedKey = assignedKey
                    SelectAssignedTarget(assignedKey)
                end
            elseif selRoute and rKey then
                finalAssignedKey = rKey
                selRoute.teams = selRoute.teams or {}
                local exists = false
                for _, tn in ipairs(selRoute.teams) do
                    if tn == newTeam.name then
                        exists = true
                        break
                    end
                end
                if not exists then
                    table.insert(selRoute.teams, newTeam.name)
                end
                selRoute.teamName = selRoute.teams[1] or newTeam.name
                newTeam.npcID = selRoute.npcID or finalNpcID or 0
                newTeam.npcName = selRoute.npcName or finalNpcName or ""
                ns.db.lastActiveRouteKey = rKey
                MarkTreeAndRoutesDirty()
                if ns.RegisterRouteInIndex then
                    ns:RegisterRouteInIndex(rKey, selRoute)
                end
                if ns.RoutingModal then
                    ns.RoutingModal.pendingTargetID = nil
                    ns.RoutingModal.pendingTargetName = nil
                    ns.RoutingModal.selectedKey = rKey
                end
            elseif finalNpcID > 0 or finalNpcName ~= "" then
                local targetArg = (finalNpcID > 0 and finalNpcName ~= "")
                    and (tostring(finalNpcID) .. " " .. finalNpcName)
                    or ((finalNpcID > 0) and tostring(finalNpcID) or finalNpcName)
                if targetArg ~= "" then
                    local ok, assignedKey = ns:AssignTeamToTarget(newTeam, targetArg, nil)
                    if ok then
                        finalAssignedKey = assignedKey
                        if ns.RoutingModal then
                            ns.RoutingModal.pendingTargetID = nil
                            ns.RoutingModal.pendingTargetName = nil
                            ns.RoutingModal.selectedKey = assignedKey
                        end
                    end
                end
            else
                MarkTreeAndRoutesDirty()
            end

            if ns.db.expandedMatrixGroups then
                ns.db.expandedMatrixGroups[newTeam.group] = true
            end
            if ns.db.expandedMatrixTargets then
                if finalAssignedKey then
                    ns.db.expandedMatrixTargets[newTeam.group .. "::route:" .. tostring(finalAssignedKey)] = true
                end
                if newTeam.npcName and newTeam.npcName ~= "" then
                    ns.db.expandedMatrixTargets[newTeam.group .. "::" .. newTeam.npcName] = true
                end
            end
            if ns.BumpTeamTreeRevision then ns:BumpTeamTreeRevision() end

            ns.AutoRouting:ApplyTeamData(newTeam)
            bm:Hide()
            if ns.RoutingModal and ns.RoutingModal:IsShown() then
                ns.RoutingModal:Refresh()
            end
            ns:RefreshAllUI()
        end)
        bm.saveBtn = bSaveBtn

        function bm:RefreshBuilder()
            if not self:IsShown() then return end
            for s = 1, 3 do
                local sCard = self.slots[s]
                local st = self.builderState.slots[s]
                local isFocused = (self.builderState.activeSlot == s)

                if st.isLeveling then
                    sCard:SetBackdropColor(unpack(BUILDER_BG_LV))
                    sCard:SetBackdropBorderColor(unpack(Theme.Colors.borderAmber))
                    sCard.icon:SetTexture("Interface\\Icons\\INV_Pet_Achievement_RaiseAPetLevel_25")
                    sCard.icon:Show()
                    sCard.plusTxt:Hide()
                    sCard.nameLbl:SetText(ns:T("|cffffb800[练级槽] 练级宠|r"))
                    sCard.stateLbl:SetText(ns:T("|cff9ca3af右键：取消练级槽|r"))
                    for abCol = 1, 3 do
                        local abBtn = sCard.abBtns[abCol]
                        abBtn.abID = nil
                        abBtn.icon:Hide()
                        abBtn.plus:SetText("|cffffb800Lv|r")
                        abBtn.plus:Show()
                    end
                elseif st.speciesID and st.speciesID > 0 then
                    sCard:SetBackdropColor(unpack(BUILDER_BG_PET))
                    sCard:SetBackdropBorderColor(unpack(isFocused and Theme.Colors.borderBlue or Theme.Colors.border))
                    local meta = ns:GetSpeciesMeta(st.speciesID)
                    local pData = st.petID and ns.SearchFilter:GetFullPetData(st.petID)
                    sCard.icon:SetTexture((pData and pData.icon) or (meta and meta.icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
                    sCard.icon:Show()
                    sCard.plusTxt:Hide()
                    sCard.nameLbl:SetText("|cffffffff" .. ((pData and pData.name) or (meta and meta.name) or ns:T("宠物")) .. "|r")
                    sCard.stateLbl:SetText(pData and string.format("|cff38bdf8Lv.%d [%s]|r", pData.level or 25, pData.breed or "B/B") or ns:T("|cff10b981点击更换|r"))

                    local sortedIDs = ns:GetSortedPetAbilities(st.speciesID)
                    for abCol = 1, 3 do
                        local abBtn = sCard.abBtns[abCol]
                        local abID = (st.abilities and st.abilities[abCol] and st.abilities[abCol] > 0 and st.abilities[abCol]) or (sortedIDs and sortedIDs[abCol]) or 0
                        st.abilities[abCol] = abID
                        if abID > 0 then
                            local _, abIcon = C_PetJournal.GetPetAbilityInfo(abID)
                            abBtn.abID = abID
                            abBtn.icon:SetTexture(abIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
                            abBtn.icon:Show()
                            abBtn.plus:Hide()
                        else
                            abBtn.abID = nil
                            abBtn.icon:Hide()
                            abBtn.plus:SetText("+")
                            abBtn.plus:Show()
                        end
                    end
                else
                    sCard:SetBackdropColor(unpack(BUILDER_BG_EMPTY))
                    sCard:SetBackdropBorderColor(unpack(isFocused and Theme.Colors.borderBlue or Theme.Colors.border))
                    sCard.icon:Hide()
                    sCard.plusTxt:Show()
                    if st.randomType ~= nil then
                        sCard.nameLbl:SetText("|cff38bdf8" .. ns:T("随机补位") .. "|r")
                    else
                        sCard.nameLbl:SetText(ns:TF("|cff9ca3af%d号槽位 (点击+)|r", s))
                    end
                    sCard.stateLbl:SetText(ns:T("|cff6b7280右键：设为经验槽|r"))
                    for abCol = 1, 3 do
                        local abBtn = sCard.abBtns[abCol]
                        abBtn.abID = nil
                        abBtn.icon:Hide()
                        abBtn.plus:SetText("+")
                        abBtn.plus:Show()
                    end
                end
            end
        end

        ns.TeamBuilderModal = bm
    end

    local bm = ns.TeamBuilderModal
    bm:SetParent(parentFrame)
    local editTeam = editTeamIndex and ns.db and ns.db.teams and ns.db.teams[editTeamIndex] or nil

    bm.importBtn:SetShown(editTeam == nil)
    bm.builderState.routeKey = routeKey
    bm.builderState.defaultGroup = (editTeam and editTeam.group) or defaultGroup
    bm.builderState.editingTeamIndex = editTeam and editTeamIndex or nil
    bm.builderState.editingTeam = editTeam
    local target = routeKey and ns.db.routeMappings[routeKey]
    if not target and editTeam then
        target = ns:FindExistingRouteForNPC(editTeam.npcID, editTeam.npcName)
            or ns:FindRouteContainingTeam(editTeam.name)
            or editTeam
    end
    local initialTarget = target and ns:FormatTargetInput(target.npcID, target.npcName) or ""
    bm.builderState.initialTarget = initialTarget
    bm.targetBox:SetText(initialTarget)
    bm.builderState.activeSlot = 1
    bm.hint:SetText(ns:T("点击选宠 · 右键设置练级槽 · 点击技能格更换技能"))

    if editTeam then
        bm.title:SetText(ns:T("|cff38bdf8EDIT TEAM // 编辑出战队伍|r"))
        bm.saveBtn.text:SetText(ns:T("保存修改"))
        bm.nameBox:SetText(editTeam.name or "")
        bm.nameBox.placeholder:Hide()

        local lvSlot = editTeam.levelingSlot or (ns.db and ns.db.settings and ns.db.settings.levelingSlot) or 2
        local usedPets = {}

        for s = 1, 3 do
            local st = bm.builderState.slots[s]
            st.randomType = editTeam.randomSlots and editTeam.randomSlots[s]
            st.threshold = ns:GetSlotThreshold(editTeam, s)
            local isLv = (editTeam.hasLevelingSlot and lvSlot == s) or (editTeam.pets and editTeam.pets[s] == "LEVELING")
            if isLv then
                st.randomType = nil
                st.isLeveling = true
                st.petID      = "LEVELING"
                st.speciesID  = 0
                st.abilities[1], st.abilities[2], st.abilities[3] = 0, 0, 0
            else
                local rawPetID = nil
                if editTeam.pets and type(editTeam.pets[s]) == "string" and editTeam.pets[s] ~= "LEVELING" and not string.find(editTeam.pets[s], "^RANDOM:") then
                    rawPetID = editTeam.pets[s]
                end
                local spID = (editTeam.speciesLoadout and tonumber(editTeam.speciesLoadout[s])) or 0
                if spID == 0 and rawPetID then
                    spID = C_PetJournal.GetPetInfoByPetID(rawPetID) or 0
                end
                if (not rawPetID or not C_PetJournal.GetPetInfoByPetID(rawPetID)) and spID > 0 then
                    rawPetID = ns.AutoRouting:FindAnyCollectedPetForSpecies(spID, usedPets)
                end
                if rawPetID then
                    usedPets[rawPetID] = true
                end

                st.isLeveling = false
                st.petID      = rawPetID
                st.speciesID  = spID
                if spID > 0 then
                    local validAbs = ns.AutoRouting:ValidateAbilitiesForSpecies(spID, editTeam.abilities and editTeam.abilities[s])
                    st.abilities[1] = validAbs[1] or 0
                    st.abilities[2] = validAbs[2] or 0
                    st.abilities[3] = validAbs[3] or 0
                else
                    st.abilities[1], st.abilities[2], st.abilities[3] = 0, 0, 0
                end
            end
        end
    else
        bm.title:SetText(ns:T("|cff38bdf8NEW TEAM // 新建出战队伍|r"))
        bm.saveBtn.text:SetText(ns:T("创建队伍"))

        for s = 1, 3 do
            local st = bm.builderState.slots[s]
            st.petID = nil
            st.speciesID = 0
            st.isLeveling = false
            st.randomType = nil
            st.threshold = nil
            st.abilities[1], st.abilities[2], st.abilities[3] = 0, 0, 0
        end

        local selRoute = routeKey and ns.db.routeMappings[routeKey]
        local baseTitle = (selRoute and selRoute.npcName and selRoute.npcName ~= "") and selRoute.npcName or ns:T("新建队伍")
        local nextSeq = (selRoute and selRoute.teams and (#selRoute.teams + 1)) or (#ns.db.teams + 1)
        bm.nameBox:SetText(string.format("%s (%d)", baseTitle, nextSeq))
        bm.nameBox.placeholder:Hide()
    end

    bm:Show()
    if ns.BringModalToFront then ns:BringModalToFront(bm) end
    bm:RefreshBuilder()

    if ns.PetPickerModal and ns.PetPickerModal:IsShown() then
        ns.PetPickerModal:ClearAllPoints()
        ns.PetPickerModal:SetPoint("TOPLEFT", bm, "TOPRIGHT", 6, 0)
        ns.PetPickerModal:SetHeight(620)
        ns.PetPickerModal:SetFrameStrata("FULLSCREEN_DIALOG")
        ns.PetPickerModal:SetFrameLevel(bm:GetFrameLevel() + 10)
    end
end
