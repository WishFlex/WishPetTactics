local ADDON_NAME, ns = ...
local Theme = ns.Theme

local MODAL_LOCALE_TEXT = (ns.locale == "zhTW") and {
    missingSub       = "|cff9ca3af以下隊伍包含你尚未收集的寵物（按住 Shift 懸停可查看缺失寵物的技能與獲取途徑）：|r",
    missingRowFmt    = "|cffff4040[缺失] %s|r  |cff9ca3af(需求隊伍: |cffffffff%s|r - %d號位)|r",
    missingTitleFmt  = "|cffffb800缺失寵物提醒 — 共 %d 支隊伍缺失 %d 種未收集寵物|r",
    missingClean     = "|cff10b981所有隊伍寵物均已集齊，無任何缺失寵物！|r",
    importTitle      = "匯入 隊伍字串、分組/目標隊伍與對戰腳本",
    tabTeam          = "模式1：匯入隊伍或全量備份",
    tabScript        = "模式2：僅匯入純對戰腳本",
    exportTeamTitle  = "匯出隊伍字串 / 全量備份",
    exportScriptTitle= "匯出純對戰腳本",
    exportChoiceTitle= "選擇匯出類型",
    exportChoiceSub  = "請選擇要匯出隊伍還是對戰腳本（僅啟用對應匯出視窗）：",
    exportAllDoneFmt = "|cff10b981已匯出全部 %d 支隊伍(含分組與腳本)，按 Ctrl+C 複製備份|r",
    exportOneDone    = "|cff10b981已產生當前隊伍字串(含腳本)，按 Ctrl+C 複製|r",
    exportScriptDone = "|cff10b981已產生當前隊伍純對戰腳本，按 Ctrl+C 複製|r",
    etcSuffix        = " 等",
    conflictFmt      = "|cff38bdf8發現 %d 支同目標且同寵物隊伍（%s），是否覆蓋？|r",
    conflictHint     = "|cff38bdf8請選擇「精準覆蓋已有隊伍」或「跳過重複」以完成匯入|r",
    modeTeamHint     = "支援貼上匯入隊伍字串，或匯出當前隊 / 全量備份(含分組與腳本)",
    modeTeamCtxFmt   = "貼上隊伍字串匯入（未帶目標ID的隊伍將自動綁定至當前目標：|cff38bdf8%s|r）",
    modeScriptHint   = "直接貼上對戰腳本匯入至當前隊，或點擊下方匯出當前隊純腳本",
    editTeamTitle    = "重新命名隊伍 & 修改所屬分類",
    editTeamNamePh   = "輸入新的隊伍名稱...",
    editTeamGrpLbl   = "所屬分類 (可輸入新分類名)：",
    editTeamGrpPh    = "如：暗影之境 / 寵物地城",
    renamePetTitle   = "自訂重新命名寵物",
    renamePetPh      = "輸入自訂名字（留空恢復預設物種名）...",
    notePetTitle     = "設定寵物備註 — ",
    notePetPh        = "輸入該寵物的戰術備註或獲取說明...",
    addTargetTitle   = "手動新增目標（輸入 NPC ID 或 NPC 名稱）",
    addTargetSub     = "格式範例：|cff38bdf8172542|r 或 |cff10b981奧多格|r 或 |cff38bdf8172542 奧多格|r",
    addTargetPh      = "輸入目標的 NPC ID 或名稱...",
} or (ns.locale ~= "zhCN") and {
    missingSub       = "|cff9ca3afThe following teams require uncollected pets (hold Shift and hover to view abilities & source):|r",
    missingRowFmt    = "|cffff4040[Missing] %s|r  |cff9ca3af(Team: |cffffffff%s|r - Slot %d)|r",
    missingTitleFmt  = "|cffffb800Missing Pets — %d team(s) missing %d uncollected species|r",
    missingClean     = "|cff10b981All team pets are collected!|r",
    importTitle      = "Import Team Strings, Group/Target Backups & Battle Scripts",
    tabTeam          = "Mode 1: Import Teams / Backup",
    tabScript        = "Mode 2: Import Script Only",
    exportTeamTitle  = "Export Team Strings / Full Backup",
    exportScriptTitle= "Export Battle Script",
    exportChoiceTitle= "Choose Export Type",
    exportChoiceSub  = "Choose whether to export Team(s) or Script (opens a single window):",
    exportAllDoneFmt = "|cff10b981Exported all %d teams (with groups & scripts). Press Ctrl+C to copy.|r",
    exportOneDone    = "|cff10b981Generated current team string (with script). Press Ctrl+C to copy.|r",
    exportScriptDone = "|cff10b981Generated battle script of current team. Press Ctrl+C to copy.|r",
    etcSuffix        = ", etc.",
    conflictFmt      = "|cff38bdf8Found %d existing team(s) with same target & pets (%s). Overwrite?|r",
    conflictHint     = "|cff38bdf8Choose 'Overwrite Existing' or 'Skip Duplicates' to finish importing.|r",
    modeTeamHint     = "Paste team strings to import, or export current team / full backup",
    modeTeamCtxFmt   = "Paste team strings to import (unbound teams will bind to target: |cff38bdf8%s|r)",
    modeScriptHint   = "Paste pet battle script code directly, or export current team's script",
    editTeamTitle    = "Rename Team & Change Group",
    editTeamNamePh   = "Enter new team name...",
    editTeamGrpLbl   = "Group (or enter a new group name):",
    editTeamGrpPh    = "e.g. Shadowlands / Pet Dungeons",
    renamePetTitle   = "Rename Pet",
    renamePetPh      = "Enter custom name (leave blank to reset)...",
    notePetTitle     = "Set Pet Note — ",
    notePetPh        = "Enter tactical notes or source info for this pet...",
    addTargetTitle   = "Add Target Manually (NPC ID or Name)",
    addTargetSub     = "Example: |cff38bdf8172542|r or |cff10b981Audrey Burnhep|r or |cff38bdf8172542 Strap|r",
    addTargetPh      = "Enter target NPC ID or Name...",
} or {
    missingSub       = "|cff9ca3af以下队伍包含你尚未收集的宠物（按住 Shift 悬停可查看缺失宠物的技能与获取途径）：|r",
    missingRowFmt    = "|cffff4040[缺失] %s|r  |cff9ca3af(需求队伍: |cffffffff%s|r - %d号位)|r",
    missingTitleFmt  = "|cffffb800缺失宠物提醒 — 共 %d 支队伍缺失 %d 种未收集宠物|r",
    missingClean     = "|cff10b981所有队伍宠物均已集齐，无任何缺失宠物！|r",
    importTitle      = "导入 队伍字符串、分组/目标队伍与对战脚本",
    tabTeam          = "模式1：导入队伍或全量备份",
    tabScript        = "模式2：仅导入纯对战脚本",
    exportTeamTitle  = "导出队伍字符串 / 全量备份",
    exportScriptTitle= "导出纯对战脚本",
    exportChoiceTitle= "选择导出类型",
    exportChoiceSub  = "请选择要导出队伍还是对战脚本（仅启用对应导出窗口）：",
    exportAllDoneFmt = "|cff10b981已导出全部 %d 支队伍(含分组与脚本)，按 Ctrl+C 复制备份|r",
    exportOneDone    = "|cff10b981已生成当前队伍字符串(含脚本)，按 Ctrl+C 复制|r",
    exportScriptDone = "|cff10b981已提取当前队伍纯对战脚本，按 Ctrl+C 复制|r",
    etcSuffix        = " 等",
    conflictFmt      = "|cff38bdf8发现 %d 支同目标且同宠物队伍（%s），是否覆盖？|r",
    conflictHint     = "|cff38bdf8请选择「精准覆盖已有队伍」或「跳过重复」以完成导入|r",
    modeTeamHint     = "支持粘贴导入队伍字符串，或导出当前队 / 全量备份(含分组与脚本)",
    modeTeamCtxFmt   = "粘贴队伍字符串导入（未带目标ID的队伍将自动绑定至当前目标：|cff38bdf8%s|r）",
    modeScriptHint   = "直接粘贴对战脚本导入至当前队，或点击下方导出当前队纯脚本",
    editTeamTitle    = "重命名队伍 & 修改所属分类",
    editTeamNamePh   = "输入新的队伍名称...",
    editTeamGrpLbl   = "所属分类 (可输入新分类名)：",
    editTeamGrpPh    = "如：暗影界 / 地下城",
    renamePetTitle   = "自定义重命名宠物",
    renamePetPh      = "输入自定义名字（留空恢复默认物种名）...",
    notePetTitle     = "设定宠物备注 — ",
    notePetPh        = "输入该宠物的战术备注或获取说明...",
    addTargetTitle   = "手动添加目标（输入 NPC ID 或 NPC 名称）",
    addTargetSub     = "格式示例：|cff38bdf8172542|r 或 |cff10b981奥多格|r 或 |cff38bdf8172542 奥多格|r",
    addTargetPh      = "输入目标的 NPC ID 或名称...",
}

-- ==================== 0. 缺失宠物汇总提醒窗口（零闭包虚拟滚动） ====================
function ns:ShowMissingPetsModal(missingReport, uniqueMissingCount)
    if not missingReport then return end

    if not ns.MissingPetsModal then
        local m = CreateFrame("Frame", "WishPetTacticsMissingPetsModal", ns.MainFrame or UIParent, "BackdropTemplate")
        m:SetSize(520, 390)
        m:SetPoint("CENTER")
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(140)
        m:SetMovable(true)
        m:SetClampedToScreen(true)
        m:EnableMouse(true)
        m:RegisterForDrag("LeftButton")
        m:SetScript("OnDragStart", m.StartMoving)
        m:SetScript("OnDragStop", m.StopMovingOrSizing)
        Theme:ApplyBackdrop(m, Theme.Colors.bgPopup, Theme.Colors.borderAmber, true)
        ns:MakeModal(m)
        m.offset = 0

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 18, -16)
        Theme:HookLocalizedFontString(title)
        m.title = title

        local closeBtn = Theme:CreateCloseIconButton(m, function()
            ns:HidePetDetailTooltip(true)
            m:Hide()
        end)
        closeBtn:SetPoint("TOPRIGHT", -16, -16)

        local subTxt = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subTxt:SetPoint("TOPLEFT", 18, -42)
        Theme:HookLocalizedFontString(subTxt)
        subTxt:SetText(MODAL_LOCALE_TEXT.missingSub)
        m.subTxt = subTxt

        local listBox = CreateFrame("Frame", nil, m, "BackdropTemplate")
        listBox:SetPoint("TOPLEFT", 18, -64)
        listBox:SetPoint("BOTTOMRIGHT", -18, 48)
        listBox:EnableMouseWheel(true)
        Theme:ApplyBackdrop(listBox, Theme.Colors.bgInput, Theme.Colors.border, false)

        local scrollTrack = CreateFrame("Button", nil, listBox, "BackdropTemplate")
        scrollTrack:SetWidth(8)
        scrollTrack:SetPoint("TOPRIGHT", listBox, "TOPRIGHT", -4, -6)
        scrollTrack:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -4, 6)
        scrollTrack:SetFrameLevel(listBox:GetFrameLevel() + 5)
        Theme:ApplyBackdrop(scrollTrack, Theme.Colors.bgPanel, Theme.Colors.border, false)
        scrollTrack:EnableMouse(true)

        local scrollThumb = CreateFrame("Button", nil, scrollTrack, "BackdropTemplate")
        scrollThumb:SetWidth(6)
        scrollThumb:SetHeight(40)
        scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -1)
        scrollThumb:SetFrameLevel(scrollTrack:GetFrameLevel() + 2)
        Theme:ApplyBackdrop(scrollThumb, Theme.Colors.btnWarning, Theme.Colors.borderAmber, false)
        scrollThumb:EnableMouse(true)
        scrollThumb:RegisterForDrag("LeftButton")

        local MAX_ROWS = 7

        listBox:SetScript("OnMouseWheel", function(_, delta)
            local flatEntries = m.flatEntries
            local maxOff = math.max(0, (flatEntries and #flatEntries or 0) - MAX_ROWS)
            local nextOff = math.max(0, math.min(maxOff, m.offset - delta * 2))
            if nextOff ~= m.offset then
                m.offset = nextOff
                m:Refresh()
            end
        end)

        m.rows = {}
        for i = 1, MAX_ROWS do
            local r = Theme:CreateMenuRow(listBox, 462, 36, "")
            r:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 38)

            r.icon = Theme:CreateCroppedIcon(r, 28)
            r.icon:SetPoint("LEFT", 8, 0)
            r.icon:EnableMouse(false)

            r.text:ClearAllPoints()
            r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 2)
            r.text:SetPoint("RIGHT", -56, 0)

            -- Anchor the hover underline tightly (1px) under the top title line
            -- and place the source description 5px below the underline so they never collide.
            r._UpdateUnderline = function(selfRow)
                if not selfRow.underline or not selfRow.text then return end
                local raw = selfRow.text:GetText()
                if not raw or raw == "" then
                    selfRow.underline:Hide()
                    return
                end
                local px = Theme:GetPixelScale(selfRow)
                selfRow.underline:SetHeight(px)
                Theme:SnapTextureToPixel(selfRow.underline)
                local maxW = math.max(12, (selfRow:GetWidth() or 462) - 102)
                local tw = (selfRow.text.GetUnboundedStringWidth and selfRow.text:GetUnboundedStringWidth())
                    or selfRow.text:GetStringWidth() or 24
                selfRow.underline:ClearAllPoints()
                selfRow.underline:SetPoint("TOPLEFT", selfRow.text, "BOTTOMLEFT", 0, -1)
                selfRow.underline:SetWidth(math.max(12, math.min(maxW, tw)))
            end

            r.subTxt = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            r.subTxt:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 10, -2)
            r.subTxt:SetPoint("RIGHT", -56, 0)
            r.subTxt:SetJustifyH("LEFT")
            r.subTxt:SetWordWrap(false)
            Theme:HookLocalizedFontString(r.subTxt)

            r.typeIcon = Theme:CreateWatermarkPetTypeTex(r, 32, 32)
            r.typeIcon:SetPoint("RIGHT", -4, 0)

            r:SetScript("OnEnter", function(self)
                if not self.mockPetData then return end
                self._isHovered = true
                if self._UpdateUnderline then self:_UpdateUnderline() end
                if self.underline then
                    self.underline:SetVertexColor(0.22, 0.88, 1.0, 0.95)
                    self.underline:Show()
                end
                ns:ShowPetDetailTooltip(self, self.mockPetData, false)
            end)
            r:SetScript("OnLeave", function(self)
                self._isHovered = false
                if self.underline then self.underline:Hide() end
                ns:HidePetDetailTooltip(false)
            end)
            r:SetScript("OnClick", nil)

            m.rows[i] = r
        end

        local okBtn = Theme:CreateActionButton(m, 118, 28, "我知道了", "validate", nil, "PRIMARY")
        okBtn:SetPoint("BOTTOMRIGHT", -18, 12)
        okBtn:SetScript("OnClick", function()
            ns:HidePetDetailTooltip(true)
            m:Hide()
        end)

        local function SyncMissingScrollThumb(totalItems)
            local maxOff = math.max(0, totalItems - MAX_ROWS)
            local trackH = scrollTrack:GetHeight()
            if not trackH or trackH <= 0 then trackH = 266 end
            local thumbH, yOff, alpha
            if maxOff <= 0 then
                thumbH = math.max(24, trackH - 2)
                yOff = -1
                alpha = 0.30
            else
                thumbH = math.max(24, math.floor((MAX_ROWS / totalItems) * (trackH - 2)))
                local availMove = math.max(1, (trackH - 2) - thumbH)
                local ratio = math.max(0, math.min(1, m.offset / maxOff))
                yOff = -1 - math.floor(ratio * availMove)
                alpha = 1.0
            end
            if scrollThumb._lastH ~= thumbH then
                scrollThumb._lastH = thumbH
                scrollThumb:SetHeight(thumbH)
            end
            if scrollThumb._lastY ~= yOff then
                scrollThumb._lastY = yOff
                scrollThumb:ClearAllPoints()
                scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, yOff)
            end
            if scrollThumb._lastA ~= alpha then
                scrollThumb._lastA = alpha
                scrollThumb:SetAlpha(alpha)
            end
        end

        local function UpdateMissingScrollFromCursor()
            if not IsMouseButtonDown("LeftButton") then
                scrollThumb:SetScript("OnUpdate", nil)
                return
            end
            local flatEntries = m.flatEntries
            local maxOff = math.max(0, (flatEntries and #flatEntries or 0) - MAX_ROWS)
            if maxOff <= 0 then return end

            local trackTop = scrollTrack:GetTop()
            local trackH = scrollTrack:GetHeight()
            local thumbH = scrollThumb:GetHeight()
            local _, rawY = GetCursorPosition()
            local cy = rawY / scrollTrack:GetEffectiveScale()

            if trackTop and trackH and thumbH and (trackH - 2 - thumbH) > 0 then
                local grab = scrollThumb.grabOffset or (thumbH / 2)
                local availMove = (trackH - 2) - thumbH
                local ratio = (((trackTop - 1) - cy) - grab) / availMove
                ratio = math.max(0, math.min(1, ratio))
                local newOff = math.floor(ratio * maxOff + 0.5)
                if newOff ~= m.offset then
                    m.offset = newOff
                    m:Refresh()
                end
            end
        end

        scrollThumb:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                local _, rawY = GetCursorPosition()
                local cy = rawY / self:GetEffectiveScale()
                local top = self:GetTop() or cy
                self.grabOffset = math.max(2, math.min(self:GetHeight() - 2, top - cy))
                self:SetScript("OnUpdate", UpdateMissingScrollFromCursor)
            end
        end)
        scrollThumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
        scrollThumb:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", UpdateMissingScrollFromCursor) end)
        scrollThumb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
        scrollThumb:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

        scrollTrack:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then
                scrollThumb.grabOffset = scrollThumb:GetHeight() / 2
                UpdateMissingScrollFromCursor()
                scrollThumb:SetScript("OnUpdate", UpdateMissingScrollFromCursor)
            end
        end)
        scrollTrack:SetScript("OnMouseUp", function()
            scrollThumb:SetScript("OnUpdate", nil)
        end)

        function m:Refresh()
            local flatEntries = self.flatEntries or {}
            local maxOff = math.max(0, #flatEntries - MAX_ROWS)
            if self.offset > maxOff then self.offset = maxOff end
            SyncMissingScrollThumb(#flatEntries)

            for i = 1, MAX_ROWS do
                local r = self.rows[i]
                local item = flatEntries[self.offset + i]
                if item then
                    r:Show()
                    r.mockPetData = item.mockPetData
                    r.icon.icon:SetTexture(item.icon)
                    r.icon.icon:SetDesaturated(true)
                    r.icon:SetBackdropBorderColor(unpack(Theme.Colors.borderRed))

                    r.text:SetText(string.format(MODAL_LOCALE_TEXT.missingRowFmt, item.name, item.teamName, item.slot))
                    r.subTxt:SetText(item.cleanSrc)
                    Theme:SetPetTypeDecalTexture(r.typeIcon, item.petType or 1)
                else
                    r.mockPetData = nil
                    r:Hide()
                end
            end
        end

        ns.MissingPetsModal = m
    end

    local m = ns.MissingPetsModal
    m:SetParent(ns:GetRoutingDialogParent())
    local flat = {}
    local uncollectedLabel = ns:T("未收集")
    local speciesIdPrefix = ns:T("物种编号：")
    for _, tEntry in ipairs(missingReport) do
        for _, mPet in ipairs(tEntry.missing or {}) do
            local cleanSrc = (mPet.sourceText and mPet.sourceText ~= "") and string.gsub(mPet.sourceText, "\n", " ") or (speciesIdPrefix .. tostring(mPet.speciesID))
            flat[#flat + 1] = {
                teamName  = tEntry.teamName,
                group     = tEntry.group,
                slot      = mPet.slot,
                speciesID = mPet.speciesID,
                name      = mPet.name,
                icon      = mPet.icon,
                petType   = mPet.petType,
                cleanSrc  = cleanSrc,
                mockPetData = {
                    speciesID   = mPet.speciesID,
                    isCollected = false,
                    name        = mPet.name,
                    level       = 25,
                    rarity      = 1,
                    petType     = mPet.petType or 1,
                    icon        = mPet.icon,
                    breed       = uncollectedLabel,
                    health      = 0,
                    maxHealth   = 1400,
                    power       = 280,
                    speed       = 280,
                    note        = cleanSrc,
                },
            }
        end
    end

    m.flatEntries = flat
    m.offset = 0
    if #flat > 0 then
        m.title:SetText(string.format(MODAL_LOCALE_TEXT.missingTitleFmt, #missingReport, uniqueMissingCount or #flat))
    else
        m.title:SetText(MODAL_LOCALE_TEXT.missingClean)
    end
    m:Show()
    ns:BringModalToFront(m)
    m:Refresh()
end

-- ==================== 1. 导入/导出中心弹窗（支持目标上下文导入 + 分组/目标/单队/纯脚本一键导出） ====================
-- Only teams committed by this import are eligible; later selection changes are irrelevant.
function ns:ShowImportedTargetConfirmation(teams, npcID, npcName)
    if not teams or #teams == 0 or (not npcID and not npcName) then return end
    if not ns.ImportTargetConfirmModal then
        local m = CreateFrame("Frame", "WishPetTacticsImportTargetConfirmModal", UIParent, "BackdropTemplate")
        m:Hide()
        m:SetSize(440, 184)
        m:SetPoint("CENTER")
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        Theme:ApplyBackdrop(m, Theme.Colors.bgPopup, Theme.Colors.border, true)
        ns:MakeModal(m)
        Theme:EnableDialogDrag(m)
        tinsert(UISpecialFrames, m:GetName())
        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 16, -14)
        Theme:HookLocalizedFontString(title)
        title:SetText(ns.locale == "zhTW" and "匯入完成：關聯目前目標" or ns.locale == "zhCN" and "导入完成：关联当前目标" or "Import complete: assign target")
        m.message = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        m.message:SetPoint("TOPLEFT", 16, -44)
        m.message:SetWidth(408)
        m.message:SetJustifyH("LEFT")
        m.message:SetWordWrap(true)
        local no = Theme:CreateFlatButton(m, 128, 28, ns.locale == "zhTW" and "否，保留匯入結果" or ns.locale == "zhCN" and "否，保留导入结果" or "No, keep imported")
        no:SetPoint("BOTTOMRIGHT", -16, 16)
        no:SetScript("OnClick", function() m:Hide() end)
        local yes = Theme:CreateFlatButton(m, 128, 28, ns.locale == "zhTW" and "是，關聯此目標" or ns.locale == "zhCN" and "是，关联此目标" or "Yes, assign target", "PRIMARY")
        yes:SetPoint("RIGHT", no, "LEFT", -8, 0)
        yes:SetScript("OnClick", function()
            local ok, routeKey = ns:AssignImportedTeamsToTarget(m.importedTeams or {}, m.targetInput)
            if not ok then routeKey = nil end
            if routeKey and ns.RoutingModal then
                ns.RoutingModal.pendingTargetID = nil
                ns.RoutingModal.pendingTargetName = nil
                ns.RoutingModal.selectedKey = routeKey
                ns.RoutingModal.teamOffset = 0
            end
            m:Hide()
            if ns.RefreshAllUI then ns:RefreshAllUI() end
        end)
        m.yesButton = yes
        m.noButton = no
        m:HookScript("OnHide", function(self) self.importedTeams = nil; self.targetInput = nil end)
        ns.ImportTargetConfirmModal = m
    end
    local m = ns.ImportTargetConfirmModal
    m:SetParent(ns:GetRoutingDialogParent())
    m.importedTeams = teams
    m.targetInput = ns:FormatTargetInput(npcID, npcName)
    local fmt = ns.locale == "zhTW" and "是否將本次匯入的 %d 支隊伍目標設為：\n|cff38bdf8%s|r？\n\n選擇「是」會取代這些隊伍原有的目標關聯。"
        or ns.locale == "zhCN" and "是否将本次导入的 %d 支队伍目标设为：\n|cff38bdf8%s|r？\n\n选择「是」会替换这些队伍原有的目标关联。"
        or "Assign the selected target to all %d imported team(s)?\n|cff38bdf8%s|r\n\nYes replaces their existing target associations."
    m.message:SetText(string.format(fmt, #teams, m.targetInput))
    m:Show()
    ns:BringModalToFront(m)
end

local function BuildScrollableTextEditor(parentFrame, scrollFrameName, topOffset, bottomOffset)
    local editHolder = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
    editHolder:SetPoint("TOPLEFT", 16, topOffset)
    editHolder:SetPoint("BOTTOMRIGHT", -16, bottomOffset)
    editHolder:SetClipsChildren(true)
    Theme:ApplyBackdrop(editHolder, Theme.Colors.bgInput, Theme.Colors.border)

    local scrollFrame = CreateFrame("ScrollFrame", scrollFrameName, editHolder)
    scrollFrame:SetPoint("TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -20, 10)
    scrollFrame:EnableMouseWheel(true)
    parentFrame.scrollFrame = scrollFrame

    local scrollTrack = CreateFrame("Frame", nil, editHolder, "BackdropTemplate")
    scrollTrack:SetWidth(8)
    scrollTrack:SetPoint("TOPRIGHT", editHolder, "TOPRIGHT", -4, -6)
    scrollTrack:SetPoint("BOTTOMRIGHT", editHolder, "BOTTOMRIGHT", -4, 6)
    Theme:ApplyBackdrop(scrollTrack, Theme.Colors.bgPanel, Theme.Colors.border, false)
    scrollTrack:EnableMouse(true)

    local scrollThumb = CreateFrame("Button", nil, scrollTrack, "BackdropTemplate")
    scrollThumb:SetWidth(6)
    scrollThumb:SetHeight(40)
    scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -1)
    Theme:ApplyBackdrop(scrollThumb, Theme.Colors.btnPrimary, Theme.Colors.borderBlue, false)
    scrollThumb:RegisterForDrag("LeftButton")

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(514)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scrollFrame:SetScrollChild(editBox)
    parentFrame.editBox = editBox

    local syncingThumb = false
    local function SyncScrollThumb()
        syncingThumb = true
        scrollFrame:UpdateScrollChildRect()
        local maxScroll = math.max(0, scrollFrame:GetVerticalScrollRange())
        local curScroll = math.max(0, math.min(maxScroll, scrollFrame:GetVerticalScroll()))
        local trackH = scrollTrack:GetHeight()
        if not trackH or trackH <= 0 then trackH = 260 end
        local thumbH, yOff, alpha
        if maxScroll <= 2 then
            thumbH = math.max(24, trackH - 2)
            yOff = -1
            alpha = 0.30
        else
            local viewH = scrollFrame:GetHeight() or 260
            local contentH = viewH + maxScroll
            thumbH = math.max(24, math.floor((viewH / contentH) * (trackH - 2)))
            local availMove = (trackH - 2) - thumbH
            yOff = -1 - math.floor((curScroll / maxScroll) * availMove)
            alpha = 1.0
        end
        if scrollThumb._lastH ~= thumbH then
            scrollThumb._lastH = thumbH
            scrollThumb:SetHeight(thumbH)
        end
        if scrollThumb._lastY ~= yOff then
            scrollThumb._lastY = yOff
            scrollThumb:ClearAllPoints()
            scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, yOff)
        end
        if scrollThumb._lastA ~= alpha then
            scrollThumb._lastA = alpha
            scrollThumb:SetAlpha(alpha)
        end
        syncingThumb = false
    end
    parentFrame.SyncImportScrollThumb = SyncScrollThumb
    parentFrame.SyncScrollThumb = SyncScrollThumb

    local function ResetScrollTopDeferred()
        scrollFrame:SetVerticalScroll(0)
        SyncScrollThumb()
    end
    parentFrame.ResetScrollTopDeferred = ResetScrollTopDeferred

    local thumbSyncPending = false
    local function RunQueuedThumbSync()
        thumbSyncPending = false
        if parentFrame:IsShown() then
            SyncScrollThumb()
        end
    end

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        self:UpdateScrollChildRect()
        local maxScroll = math.max(0, self:GetVerticalScrollRange())
        local nextScroll = math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 36))
        self:SetVerticalScroll(nextScroll)
        SyncScrollThumb()
    end)

    local function QueueThumbSync()
        if not syncingThumb and not thumbSyncPending then
            thumbSyncPending = true
            C_Timer.After(0, RunQueuedThumbSync)
        end
    end

    scrollFrame:SetScript("OnScrollRangeChanged", QueueThumbSync)

    local function UpdateScrollFromCursor()
        if not IsMouseButtonDown("LeftButton") then
            scrollThumb:SetScript("OnUpdate", nil)
            return
        end
        scrollFrame:UpdateScrollChildRect()
        local maxScroll = math.max(0, scrollFrame:GetVerticalScrollRange())
        if maxScroll <= 0 then return end
        local trackTop = scrollTrack:GetTop()
        local trackHeight = scrollTrack:GetHeight()
        local thumbHeight = scrollThumb:GetHeight()
        local _, rawY = GetCursorPosition()
        local cy = rawY / scrollTrack:GetEffectiveScale()
        if trackTop and trackHeight and (trackHeight - thumbHeight) > 0 then
            local grab = scrollThumb.grabOffset or (thumbHeight / 2)
            local ratio = ((trackTop - cy) - grab) / (trackHeight - thumbHeight)
            ratio = math.max(0, math.min(1, ratio))
            scrollFrame:SetVerticalScroll(ratio * maxScroll)
            SyncScrollThumb()
        end
    end

    scrollThumb:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            local _, rawY = GetCursorPosition()
            local cy = rawY / self:GetEffectiveScale()
            local top = self:GetTop() or cy
            self.grabOffset = math.max(2, math.min(self:GetHeight() - 2, top - cy))
            self:SetScript("OnUpdate", UpdateScrollFromCursor)
        end
    end)
    scrollThumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    scrollThumb:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", UpdateScrollFromCursor) end)
    scrollThumb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    scrollThumb:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

    editBox:SetScript("OnTextChanged", QueueThumbSync)
    editBox:SetScript("OnCursorChanged", function(_, _, y, _, h)
        if parentFrame._suppressCursorJump then return end
        scrollFrame:UpdateScrollChildRect()
        local viewH = scrollFrame:GetHeight() or 260
        local curScroll = scrollFrame:GetVerticalScroll()
        local cursorTop = -(y or 0)
        local cursorBottom = cursorTop + (h or 14)
        if cursorTop < curScroll then
            scrollFrame:SetVerticalScroll(math.max(0, cursorTop - 8))
        elseif cursorBottom > (curScroll + viewH) then
            local maxScroll = math.max(0, scrollFrame:GetVerticalScrollRange())
            scrollFrame:SetVerticalScroll(math.min(maxScroll, cursorBottom - viewH + 8))
        end
        SyncScrollThumb()
    end)

    editHolder:EnableMouse(true)
    editHolder:SetScript("OnMouseDown", function() editBox:SetFocus() end)
    scrollFrame:EnableMouse(true)
    scrollFrame:SetScript("OnMouseDown", function() editBox:SetFocus() end)

    return editHolder, scrollFrame, editBox
end

-- ==================== 1A. 独立「导入」窗口（仅负责导入队伍字符串或对战脚本） ====================
function ns:ShowImportModal(defaultMode, targetContext, isExport)
    if isExport then
        return self:ShowExportModal(defaultMode or "TEAM", { targetContext = targetContext })
    end
    local f = self.MainFrame
    if f and f:IsShown() and (f.compactDraft or self.staging.isDirty) then
        self:RequestHomeAction(function() self:ShowImportModal(defaultMode, targetContext) end)
        return
    end
    local routing = ns.RoutingModal
    if not targetContext and (defaultMode or "TEAM") == "TEAM" and routing and routing:IsVisible() then
        local routeKey = routing.selectedKey
        local route = routeKey and ns.db and ns.db.routeMappings and ns.db.routeMappings[routeKey]
        if route then
            targetContext = { routeKey = routeKey, npcID = route.npcID, npcName = route.npcName }
        end
    end
    if self.HideTransientMenus then self:HideTransientMenus() else self:HideAllPopups() end
    if ns.ExportChoiceModal then ns.ExportChoiceModal:Hide() end
    if ns.ExportModal then ns.ExportModal:Hide() end

    if not ns.ImportModal then
        local m = CreateFrame("Frame", "WishPetTacticsImportModal", UIParent, "BackdropTemplate")
        m:SetSize(580, 440)
        m:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(130)
        m:SetMovable(true)
        m:SetClampedToScreen(true)
        m:RegisterForDrag("LeftButton")
        m:SetScript("OnDragStart", m.StartMoving)
        m:SetScript("OnDragStop", m.StopMovingOrSizing)
        Theme:ApplyBackdrop(m, Theme.Colors.bgPopup, Theme.Colors.border)
        ns:MakeModal(m)
        if UISpecialFrames then tinsert(UISpecialFrames, m:GetName()) end

        m:HookScript("OnHide", function(self)
            self.targetContext = nil
            self.importCompletionToken = nil
            if self.ResetPreview then self:ResetPreview() end
        end)

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 16, -14)
        Theme:HookLocalizedFontString(title)
        title:SetText(MODAL_LOCALE_TEXT.importTitle)
        m.title = title

        local closeBtn = Theme:CreateCloseIconButton(m, function() m:Hide() end)
        closeBtn:SetPoint("TOPRIGHT", -14, -14)
        m.closeBtn = closeBtn

        local tabTeam = Theme:CreateActionButton(m, 195, 26, MODAL_LOCALE_TEXT.tabTeam, "new-team")
        tabTeam:SetPoint("TOPLEFT", 16, -42)
        local tabScript = Theme:CreateActionButton(m, 185, 26, MODAL_LOCALE_TEXT.tabScript, "script")
        tabScript:SetPoint("LEFT", tabTeam, "RIGHT", 8, 0)
        m.tabTeam = tabTeam
        m.tabScript = tabScript

        local editHolder, scrollFrame, editBox = BuildScrollableTextEditor(
            m, "WishPetTacticsImportScrollFrame", -76, 72
        )

        local conflictBox = CreateFrame("Frame", nil, editHolder, "BackdropTemplate")
        conflictBox:SetPoint("BOTTOMLEFT", 4, 4)
        conflictBox:SetPoint("BOTTOMRIGHT", -14, 4)
        conflictBox:SetHeight(64)
        conflictBox:SetFrameLevel(editBox:GetFrameLevel() + 10)
        conflictBox:EnableMouse(true)
        Theme:ApplyBackdrop(conflictBox, { 0.133, 0.133, 0.133, 0.96 }, Theme.Colors.borderBlue)
        conflictBox:Hide()
        m.conflictBox = conflictBox

        local confTxt = conflictBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        confTxt:SetPoint("TOPLEFT", 10, -8)
        confTxt:SetPoint("TOPRIGHT", -10, -8)
        confTxt:SetJustifyH("LEFT")
        Theme:HookLocalizedFontString(confTxt)
        conflictBox.txt = confTxt

        local overwriteBtn = Theme:CreateActionButton(conflictBox, 130, 24, "精准覆盖已有队伍", "overwrite", nil, "WARNING")
        overwriteBtn:SetPoint("BOTTOMRIGHT", -148, 6)

        local skipDupBtn = Theme:CreateActionButton(conflictBox, 130, 24, "跳过重复(仅导新队)", "validate", nil, "PRIMARY")
        skipDupBtn:SetPoint("BOTTOMRIGHT", -10, 6)

        local statusTxt = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        statusTxt:SetPoint("TOPLEFT", editHolder, "BOTTOMLEFT", 2, -8)
        statusTxt:SetPoint("TOPRIGHT", editHolder, "BOTTOMRIGHT", -2, -8)
        statusTxt:SetJustifyH("LEFT")
        statusTxt:SetWordWrap(false)
        statusTxt:SetTextColor(0.6, 0.7, 0.9, 1)
        Theme:HookLocalizedFontString(statusTxt)
        m.statusTxt = statusTxt

        local previewPanel = CreateFrame("Frame", nil, m, "BackdropTemplate")
        previewPanel:SetPoint("TOPLEFT", editHolder, "TOPLEFT", 0, 0)
        previewPanel:SetPoint("BOTTOMRIGHT", editHolder, "BOTTOMRIGHT", 0, 0)
        previewPanel:SetFrameLevel(editHolder:GetFrameLevel() + 20)
        previewPanel:EnableMouse(true)
        Theme:ApplyBackdrop(previewPanel, Theme.Colors.bgInput, Theme.Colors.borderBlue)
        previewPanel:Hide()
        local previewScroll = CreateFrame("ScrollFrame", nil, previewPanel, "UIPanelScrollFrameTemplate")
        previewScroll:SetPoint("TOPLEFT", 16, -16)
        previewScroll:SetPoint("BOTTOMRIGHT", -35, 46)
        local previewContent = CreateFrame("Frame", nil, previewScroll)
        previewContent:SetWidth(470)
        previewContent:SetHeight(1)
        previewScroll:SetScrollChild(previewContent)
        local previewText = previewContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        previewText:SetPoint("TOPLEFT", 0, 0)
        previewText:SetWidth(470)
        previewText:SetJustifyH("LEFT")
        previewText:SetJustifyV("TOP")
        previewText:SetWordWrap(true)
        local backBtn = Theme:CreateActionButton(previewPanel, 115, 25, ns:UXText("back"), "restore")
        backBtn:SetPoint("BOTTOMLEFT", 12, 10)
        backBtn:SetScript("OnClick", function()
            previewPanel:Hide()
            m.previewData = nil
            if m.confirmBtn then m.confirmBtn.text:SetText(ns:UXText("preview")) end
            editBox:SetFocus()
        end)
        m.previewPanel = previewPanel
        m.previewText = previewText

        local function CompleteImport(committedTeams, npcID, npcName)
            if ns.ShowUIFeedback then ns:ShowUIFeedback(ns:UXText("imported")) end
            local mode = m.mode
            local token = {}
            m.importCompletionToken = token
            C_Timer.After(0.6, function()
                if m.importCompletionToken ~= token then return end
                m:Hide()
                if mode == "TEAM" and committedTeams and #committedTeams > 0 and (npcID or npcName) then
                    ns:ShowImportedTargetConfirmation(committedTeams, npcID, npcName)
                end
            end)
        end

        local function FinishImportWithResolution(resMode)
            local preview = m.previewData
            if not preview or not preview.valid or preview.raw ~= (editBox:GetText() or "") or preview.mode ~= m.mode then
                m:ResetPreview()
                statusTxt:SetText(ns:UXText("previewChanged"))
                return
            end
            conflictBox:Hide()
            previewPanel:Hide()
            local npcID, npcName = ns.AutoRouting:GetUnitNPCID("target")
            local ok, msg, committedTeams = ns:ImportTeamOrScript(preview.raw, preview.mode, resMode, preview.targetContext, preview)
            statusTxt:SetText(ok and ("|cff10b981" .. tostring(msg) .. "|r") or ("|cffef4444" .. tostring(msg) .. "|r"))
            if ok then
                CompleteImport(committedTeams, npcID, npcName)
            else
                ns:PrintError(msg)
            end
        end

        overwriteBtn:SetScript("OnClick", function() FinishImportWithResolution("OVERWRITE") end)
        skipDupBtn:SetScript("OnClick", function() FinishImportWithResolution("SKIP") end)

        local confirmBtn = Theme:CreateActionButton(m, 96, 28, ns:UXText("preview"), "import", ns:UXText("preview"), "PRIMARY")
        confirmBtn:SetPoint("BOTTOMRIGHT", -16, 12)
        m.confirmBtn = confirmBtn

        local function ResetPreview()
            m.previewData = nil
            conflictBox:Hide()
            previewPanel:Hide()
            confirmBtn.text:SetText(ns:UXText("preview"))
        end
        m.ResetPreview = ResetPreview
        editBox:HookScript("OnTextChanged", function()
            if m.previewData or conflictBox:IsShown() then ResetPreview() end
        end)

        confirmBtn:SetScript("OnClick", function()
            local currentText = editBox:GetText() or ""
            if not m.previewData or m.previewData.raw ~= currentText or m.previewData.mode ~= m.mode then
                conflictBox:Hide()
                local result = ns:BuildImportPreview(currentText, m.mode)
                result.raw, result.mode = currentText, m.mode
                if m.targetContext then
                    result.targetContext = {npcID=m.targetContext.npcID, npcName=m.targetContext.npcName, routeKey=m.targetContext.routeKey}
                end
                m.previewData = result
                previewText:SetText(ns:FormatImportPreview(result))
                previewContent:SetHeight(math.max(1, previewText:GetStringHeight() + 12))
                previewScroll:SetVerticalScroll(0)
                previewPanel:Show()
                confirmBtn.text:SetText(ns:UXText("confirm"))
                statusTxt:SetText(result.valid and ns:UXText("previewHint") or (result.error or ns:UXText("invalid")))
                return
            end
            if not m.previewData.valid then
                statusTxt:SetText(m.previewData.error or ns:UXText("invalid"))
                return
            end
            local npcID, npcName = ns.AutoRouting:GetUnitNPCID("target")
            local ok, msgOrConflicts, committedTeams = ns:ImportTeamOrScript(currentText, m.mode, nil, m.previewData.targetContext, m.previewData)
            if ok == "CONFLICT" then
                previewPanel:Hide()
                local cList = msgOrConflicts
                local sep = (ns.locale == "zhCN" or ns.locale == "zhTW") and "、" or ", "
                local preview = table.concat(cList, sep, 1, math.min(3, #cList))
                if #cList > 3 then preview = preview .. MODAL_LOCALE_TEXT.etcSuffix end
                conflictBox.txt:SetText(string.format(MODAL_LOCALE_TEXT.conflictFmt, #cList, preview))
                conflictBox:Show()
                statusTxt:SetText(MODAL_LOCALE_TEXT.conflictHint)
                return
            end
            statusTxt:SetText(ok and ("|cff10b981" .. tostring(msgOrConflicts) .. "|r") or ("|cffef4444" .. tostring(msgOrConflicts) .. "|r"))
            if ok then
                CompleteImport(committedTeams, npcID, npcName)
            else
                ResetPreview()
                ns:PrintError(msgOrConflicts)
            end
        end)

        function m:SetMode(mode)
            self:ResetPreview()
            self.importCompletionToken = nil
            self.mode = mode
            conflictBox:Hide()
            tabTeam:SetSelected(mode == "TEAM")
            tabScript:SetSelected(mode == "SCRIPT")
            self.editBox:SetText("")
            self.scrollFrame:SetVerticalScroll(0)
            self.SyncImportScrollThumb()

            if mode == "TEAM" then
                local ctx = self.targetContext
                local hasCtx = ctx and ((tonumber(ctx.npcID) or 0) > 0 or (ctx.npcName and ctx.npcName ~= ""))
                if hasCtx then
                    local tLbl = (ctx.npcName and ctx.npcName ~= "") and ctx.npcName or ("#" .. tostring(ctx.npcID))
                    self.statusTxt:SetText(string.format(MODAL_LOCALE_TEXT.modeTeamCtxFmt, tLbl))
                else
                    self.statusTxt:SetText(MODAL_LOCALE_TEXT.modeTeamHint)
                end
            else
                self.statusTxt:SetText(MODAL_LOCALE_TEXT.modeScriptHint)
            end
        end

        tabTeam:SetScript("OnClick", function() m:SetMode("TEAM") end)
        tabScript:SetScript("OnClick", function() m:SetMode("SCRIPT") end)
        ns.ImportModal = m
    end

    ns.ImportModal:SetParent((self.GetActiveUIParent and self:GetActiveUIParent()) or UIParent)
    if self.MatchMainUIScale then self:MatchMainUIScale(ns.ImportModal) end
    ns.ImportModal.targetContext = targetContext
    ns.ImportModal:SetMode(defaultMode or "TEAM")
    ns.ImportModal:Show()
    ns:BringModalToFront(ns.ImportModal)
end

-- ==================== 1B. 点击「导出」弹出的类型选择弹窗（选队伍还是脚本，选择其一只启用一个窗口） ====================
function ns:ShowExportChoiceModal(context)
    if self.HideTransientMenus then self:HideTransientMenus() else self:HideAllPopups() end
    if ns.ImportModal then ns.ImportModal:Hide() end
    if ns.ExportModal then ns.ExportModal:Hide() end

    if not ns.ExportChoiceModal then
        local m = CreateFrame("Frame", "WishPetTacticsExportChoiceModal", UIParent, "BackdropTemplate")
        m:SetSize(368, 152)
        m:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(160)
        m:SetMovable(true)
        m:SetClampedToScreen(true)
        m:RegisterForDrag("LeftButton")
        m:SetScript("OnDragStart", m.StartMoving)
        m:SetScript("OnDragStop", m.StopMovingOrSizing)
        Theme:ApplyBackdrop(m, Theme.Colors.bgPopup, Theme.Colors.borderBlue, true)
        ns:MakeModal(m)
        if UISpecialFrames then tinsert(UISpecialFrames, m:GetName()) end

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 18, -14)
        Theme:HookLocalizedFontString(title)
        title:SetText(MODAL_LOCALE_TEXT.exportChoiceTitle)
        m.title = title

        local closeBtn = Theme:CreateCloseIconButton(m, function() m:Hide() end)
        closeBtn:SetPoint("TOPRIGHT", -14, -14)
        m.closeBtn = closeBtn

        local subTxt = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subTxt:SetPoint("TOPLEFT", 18, -42)
        subTxt:SetPoint("TOPRIGHT", -18, -42)
        subTxt:SetJustifyH("LEFT")
        subTxt:SetWordWrap(true)
        Theme:HookLocalizedFontString(subTxt)
        subTxt:SetText(MODAL_LOCALE_TEXT.exportChoiceSub)
        m.subTxt = subTxt

        local teamBtn = Theme:CreateActionButton(m, 154, 34, "导出队伍", "export", "导出队伍配置字符串（含目标与脚本）", "PRIMARY")
        teamBtn:SetPoint("BOTTOMLEFT", 20, 20)
        teamBtn:SetScript("OnClick", function()
            local ctx = m.exportContext
            m:Hide()
            ns:ShowExportModal("TEAM", ctx)
        end)
        m.teamBtn = teamBtn

        local scriptBtn = Theme:CreateActionButton(m, 154, 34, "导出脚本", "script", "仅导出纯对战脚本", "PRIMARY")
        scriptBtn:SetPoint("BOTTOMRIGHT", -20, 20)
        scriptBtn:SetScript("OnClick", function()
            local ctx = m.exportContext
            m:Hide()
            ns:ShowExportModal("SCRIPT", ctx)
        end)
        m.scriptBtn = scriptBtn

        m:HookScript("OnHide", function(self)
            self.exportContext = nil
        end)

        ns.ExportChoiceModal = m
    end

    local m = ns.ExportChoiceModal
    m:SetParent((self.GetActiveUIParent and self:GetActiveUIParent()) or UIParent)
    if self.MatchMainUIScale then self:MatchMainUIScale(m) end
    m.exportContext = context
    m:Show()
    ns:BringModalToFront(m)
end

-- ==================== 1C. 独立单模式「导出」窗口（队伍导出窗口 / 脚本导出窗口，带明确导出按钮） ====================
function ns:ShowExportModal(mode, context, initialText, initialStatus)
    if not mode then
        return self:ShowExportChoiceModal(context)
    end
    if self.HideTransientMenus then self:HideTransientMenus() else self:HideAllPopups() end
    if ns.ImportModal then ns.ImportModal:Hide() end
    if ns.ExportChoiceModal then ns.ExportChoiceModal:Hide() end

    if not ns.ExportModal then
        local m = CreateFrame("Frame", "WishPetTacticsExportModal", UIParent, "BackdropTemplate")
        m:SetSize(580, 440)
        m:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(145)
        m:SetMovable(true)
        m:SetClampedToScreen(true)
        m:RegisterForDrag("LeftButton")
        m:SetScript("OnDragStart", m.StartMoving)
        m:SetScript("OnDragStop", m.StopMovingOrSizing)
        Theme:ApplyBackdrop(m, Theme.Colors.bgPopup, Theme.Colors.border)
        ns:MakeModal(m)
        if UISpecialFrames then tinsert(UISpecialFrames, m:GetName()) end

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 16, -14)
        Theme:HookLocalizedFontString(title)
        m.title = title

        local closeBtn = Theme:CreateCloseIconButton(m, function() m:Hide() end)
        closeBtn:SetPoint("TOPRIGHT", -14, -14)
        m.closeBtn = closeBtn

        local subTitle = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subTitle:SetPoint("TOPLEFT", 16, -44)
        subTitle:SetPoint("TOPRIGHT", -16, -44)
        subTitle:SetJustifyH("LEFT")
        subTitle:SetWordWrap(false)
        Theme:HookLocalizedFontString(subTitle)
        m.subTitle = subTitle

        local editHolder, scrollFrame, editBox = BuildScrollableTextEditor(
            m, "WishPetTacticsExportScrollFrame", -68, 72
        )

        local statusTxt = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        statusTxt:SetPoint("TOPLEFT", editHolder, "BOTTOMLEFT", 2, -8)
        statusTxt:SetPoint("TOPRIGHT", editHolder, "BOTTOMRIGHT", -2, -8)
        statusTxt:SetJustifyH("LEFT")
        statusTxt:SetWordWrap(false)
        statusTxt:SetTextColor(0.6, 0.7, 0.9, 1)
        Theme:HookLocalizedFontString(statusTxt)
        m.statusTxt = statusTxt

        local exportBtn = Theme:CreateActionButton(m, 136, 28, "导出当前队伍", "export", "导出当前队伍或对战脚本", "PRIMARY")
        exportBtn:SetPoint("BOTTOMRIGHT", -16, 12)
        m.exportBtn = exportBtn

        local exportAllBtn = Theme:CreateActionButton(m, 136, 28, "导出全部队伍", "export", "导出全部队伍（含脚本）")
        exportAllBtn:SetPoint("RIGHT", exportBtn, "LEFT", -10, 0)
        m.exportAllBtn = exportAllBtn

        function m:FillExportText(textStr, msgStr)
            self._suppressCursorJump = true
            self.editBox:SetText(textStr or "")
            self.scrollFrame:SetVerticalScroll(0)
            self.SyncScrollThumb()
            self.editBox:HighlightText()
            self.editBox:SetFocus()
            if msgStr and msgStr ~= "" then
                self.statusTxt:SetText(msgStr)
            end
            C_Timer.After(0.03, function()
                self._suppressCursorJump = false
                if self:IsShown() then
                    self.ResetScrollTopDeferred()
                end
            end)
        end

        function m:DoExportCurrent(silentIfEmpty)
            local ctx = self.exportContext or {}
            if self.mode == "SCRIPT" then
                if ctx.routeKey then
                    local scriptStr, cnt = ns:ExportTargetRouteScripts(ctx.routeKey)
                    if not scriptStr or scriptStr == "" or (cnt or 0) <= 0 then
                        local err = ns:T("该目标下暂无对战脚本可导出！")
                        self.statusTxt:SetText("|cffff6565" .. err .. "|r")
                        if not silentIfEmpty then ns:PrintError(err) end
                        return false
                    end
                    local rLbl = ctx.routeLabel or tostring(ctx.routeKey)
                    local msg = ns:TF("|cff10b981已单独导出目标 [%s] 的对战脚本(%d队)，按 Ctrl+C 复制|r", rLbl, cnt)
                    self:FillExportText(scriptStr, msg)
                    return true
                end
                local team = ctx.team or (ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx])
                if not team and ns.db and ns.db.teams and #ns.db.teams > 0 then
                    team = ns.db.teams[1]
                end
                local scriptStr = ""
                if ctx.fromScriptEditor and ctx.liveScript and ctx.liveScript ~= "" then
                    scriptStr = ctx.liveScript
                elseif ns.ScriptWorkspaceModal and ns.ScriptWorkspaceModal:IsShown() and ns.ScriptEditBox then
                    local raw = ns.ScriptEditBox:GetText() or ""
                    scriptStr = ns.Syntax and strtrim(ns.Syntax:StripColors(raw)) or strtrim(raw)
                elseif team then
                    scriptStr = ns:ExportSingleTeamScript(team) or ""
                end
                if not scriptStr or strtrim(scriptStr) == "" then
                    local err = ns:T("该队伍暂无对战脚本可导出！")
                    self.statusTxt:SetText("|cffff6565" .. err .. "|r")
                    if not silentIfEmpty then ns:PrintError(err) end
                    return false
                end
                local tName = team and team.name or ns:T("当前队伍")
                local msg = ns:TF("|cff10b981已单独导出队伍 [%s] 的纯对战脚本，按 Ctrl+C 复制|r", tName)
                self:FillExportText(scriptStr, msg)
                return true
            else
                if ctx.routeKey then
                    local exportStr, cnt = ns:ExportTargetRouteTeamsString(ctx.routeKey)
                    if not exportStr or exportStr == "" or (cnt or 0) <= 0 then
                        local err = ns:T("该目标下暂无可导出的队伍！")
                        self.statusTxt:SetText("|cffff6565" .. err .. "|r")
                        if not silentIfEmpty then ns:PrintError(err) end
                        return false
                    end
                    local rLbl = ctx.routeLabel or tostring(ctx.routeKey)
                    local msg = "|cff10b981" .. ns:TF("已导出 %d 支队伍（含目标与脚本），目标：%s。按 Ctrl+C 复制。", cnt, rLbl) .. "|r"
                    self:FillExportText(exportStr, msg)
                    return true
                end
                local team = ctx.team or (ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx])
                if not team and ns.db and ns.db.teams and #ns.db.teams > 0 then
                    team = ns.db.teams[1]
                end
                if not team then
                    local allStr, allCnt = ns:ExportAllTeamsString()
                    if allStr and allStr ~= "" and (allCnt or 0) > 0 then
                        self:FillExportText(allStr, string.format(MODAL_LOCALE_TEXT.exportAllDoneFmt, allCnt))
                        return true
                    end
                    self.statusTxt:SetText(ns:T("暂无可导出的队伍！"))
                    return false
                end
                local isCur = (team == (ns.db and ns.db.teams and ns.db.teams[ns.db.selectedTeamIdx]))
                local exportStr = ns:ExportSingleTeamString(team, isCur)
                local msg = ns:TF("|cff10b981已导出队伍 [%s] 字符串(含目标与脚本)，按 Ctrl+C 复制|r", team.name or ns:T("未命名队伍"))
                self:FillExportText(exportStr, msg)
                return true
            end
        end

        function m:DoExportAll()
            local exportStr, cnt = ns:ExportAllTeamsString()
            if not exportStr or exportStr == "" or (cnt or 0) <= 0 then
                local err = ns:T("暂无可导出的队伍！")
                self.statusTxt:SetText("|cffff6565" .. err .. "|r")
                ns:PrintError(err)
                return false
            end
            self:FillExportText(exportStr, string.format(MODAL_LOCALE_TEXT.exportAllDoneFmt, cnt))
            return true
        end

        exportBtn:SetScript("OnClick", function()
            m:DoExportCurrent(false)
        end)
        exportAllBtn:SetScript("OnClick", function()
            m:DoExportAll()
        end)

        function m:SetMode(targetMode, ctx)
            self.mode = (targetMode == "SCRIPT") and "SCRIPT" or "TEAM"
            self.exportContext = ctx
            self.editBox:SetText("")
            self.scrollFrame:SetVerticalScroll(0)
            self.SyncScrollThumb()
            if self.mode == "SCRIPT" then
                self.title:SetText(MODAL_LOCALE_TEXT.exportScriptTitle)
                self.subTitle:SetText(ns:T("|cff9ca3af单模式窗口：仅导出纯对战脚本（点击下方按钮生成并按 Ctrl+C 复制）|r"))
                self.exportBtn.text:SetText(ns:T("导出脚本"))
                self.exportAllBtn:Hide()
                self.statusTxt:SetText(MODAL_LOCALE_TEXT.exportScriptDone)
            else
                self.title:SetText(MODAL_LOCALE_TEXT.exportTeamTitle)
                self.subTitle:SetText(ns:T("|cff9ca3af单模式窗口：导出队伍配置字符串（含目标与脚本，点击下方按钮生成并按 Ctrl+C 复制）|r"))
                self.exportBtn.text:SetText(ns:T("导出队伍"))
                self.exportAllBtn.text:SetText(ns:T("导出全部队伍"))
                self.exportAllBtn:Show()
                self.statusTxt:SetText(MODAL_LOCALE_TEXT.exportOneDone)
            end
        end

        m:HookScript("OnHide", function(self)
            self.exportContext = nil
        end)

        ns.ExportModal = m
    end

    local m = ns.ExportModal
    m:SetParent((self.GetActiveUIParent and self:GetActiveUIParent()) or UIParent)
    if self.MatchMainUIScale then self:MatchMainUIScale(m) end
    m:SetMode(mode, context)
    m:Show()
    ns:BringModalToFront(m)
    if initialText ~= nil then
        m:FillExportText(initialText, initialStatus)
    else
        m:DoExportCurrent(true)
    end
end

-- 通用导出展示入口：使用独立单模式导出窗口自动填入内容、置顶滚动条并全选高亮以便 Ctrl+C
function ns:ShowExportModalWithText(exportText, statusMessage, tabMode)
    self:ShowExportModal(tabMode or "TEAM", nil, exportText or "", statusMessage)
end

-- ==================== 2. 纯净「队伍重命名 & 所属分类」弹窗（静态事件绑定） ====================
function ns:ShowTeamEditModal(teamIndex)
    self:HideAllPopups()
    local team = ns.db.teams[teamIndex]
    if not team then return end

    if not ns.TeamEditModal then
        local m = CreateFrame("Frame", "WishPetTacticsTeamEditModal", ns.MainFrame or UIParent, "BackdropTemplate")
        m:SetSize(440, 146)
        m:SetPoint("CENTER")
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(150)
        m:SetMovable(true)
        m:SetClampedToScreen(true)
        m:RegisterForDrag("LeftButton")
        m:SetScript("OnDragStart", m.StartMoving)
        m:SetScript("OnDragStop", m.StopMovingOrSizing)
        Theme:ApplyBackdrop(m, Theme.Colors.bgPopup, Theme.Colors.border)
        ns:MakeModal(m)

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 16, -14)
        Theme:HookLocalizedFontString(title)
        title:SetText(MODAL_LOCALE_TEXT.editTeamTitle)

        local nameLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameLbl:SetPoint("TOPLEFT", 16, -42)
        Theme:HookLocalizedFontString(nameLbl)
        nameLbl:SetText(ns:T("队伍名称："))

        local nameBox = Theme:CreateFlatEditBox(m, 240, 26, MODAL_LOCALE_TEXT.editTeamNamePh)
        nameBox:SetPoint("TOPLEFT", 16, -60)
        m.nameBox = nameBox

        local grpLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        grpLbl:SetPoint("TOPLEFT", 268, -42)
        Theme:HookLocalizedFontString(grpLbl)
        grpLbl:SetText(MODAL_LOCALE_TEXT.editTeamGrpLbl)

        local grpBox = Theme:CreateFlatEditBox(m, 156, 26, MODAL_LOCALE_TEXT.editTeamGrpPh)
        grpBox:SetPoint("TOPLEFT", 268, -60)
        m.grpBox = grpBox

        local cancelBtn = Theme:CreateFlatButton(m, 95, 28, "取消")
        cancelBtn:SetPoint("BOTTOMRIGHT", -16, 14)
        cancelBtn:SetScript("OnClick", function() m:Hide() end)

        local saveBtn = Theme:CreateActionButton(m, 120, 28, "保存", "save", "保存修改", "PRIMARY")
        saveBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -8, 0)
        saveBtn:SetScript("OnClick", function()
            local tIdx = m.editingTeamIndex
            local curTeam = tIdx and ns.db and ns.db.teams and ns.db.teams[tIdx]
            if not curTeam then
                m:Hide()
                return
            end
            local newName = strtrim(m.nameBox:GetText() or "")
            if newName ~= "" and newName ~= curTeam.name then
                ns:RenameTeam(tIdx, newName)
            end
            local newGrp = strtrim(m.grpBox:GetText() or "")
            if newGrp == "" or newGrp == ns:T("未分组队伍") then newGrp = "未分组队伍" end
            curTeam.group = ns:EnsureTeamGroup(newGrp)
            if ns.MarkRoutesDirty then
                ns:MarkRoutesDirty()
            elseif ns.TeamMatrixModal then
                ns.TeamMatrixModal._treeDirty = true
            end
            m:Hide()
            ns:RefreshAllUI()
        end)
        m.saveBtn = saveBtn

        nameBox:SetScript("OnEnterPressed", function() saveBtn:Click() end)
        grpBox:SetScript("OnEnterPressed", function() saveBtn:Click() end)

        ns.TeamEditModal = m
    end

    local m = ns.TeamEditModal
    m:SetParent(ns:GetRoutingDialogParent())
    m.editingTeamIndex = teamIndex
    m.nameBox:SetText(team.name or "")
    m.nameBox.placeholder:Hide()
    m.grpBox:SetText((not team.group or team.group == "" or team.group == "未分组队伍") and ns:T("未分组队伍") or team.group)
    m.grpBox.placeholder:Hide()

    m:Show()
    ns:BringModalToFront(m)
    m.nameBox:HighlightText()
    m.nameBox:SetFocus()
end

-- ==================== 3. 宠物重命名与设定备注弹窗（静态事件绑定） ====================
local function RefreshAfterPetRename()
    if ns.InvalidatePetAndTeamCache then ns:InvalidatePetAndTeamCache() end
    if ns.RefreshAllUI then ns:RefreshAllUI() end
end

function ns:ShowPetRenameModal(petID, currentName)
    self:HideAllPopups()
    if not petID then return end
    if not ns.PetRenameModal then
        local m = CreateFrame("Frame", "WishPetTacticsPetRenameModal", ns.MainFrame or UIParent, "BackdropTemplate")
        m:SetSize(360, 150)
        m:SetPoint("CENTER", ns.MainFrame or UIParent, "CENTER", 0, 0)
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(140)
        m:SetMovable(true)
        m:SetClampedToScreen(true)
        m:RegisterForDrag("LeftButton")
        m:SetScript("OnDragStart", m.StartMoving)
        m:SetScript("OnDragStop", m.StopMovingOrSizing)
        Theme:ApplyBackdrop(m, Theme.Colors.bgPopup, Theme.Colors.border)
        ns:MakeModal(m)

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 16, -14)
        Theme:HookLocalizedFontString(title)
        title:SetText(MODAL_LOCALE_TEXT.renamePetTitle)

        local box = Theme:CreateFlatEditBox(m, 328, 28, MODAL_LOCALE_TEXT.renamePetPh)
        box:SetPoint("TOPLEFT", 16, -48)
        m.box = box

        local closeBtn = Theme:CreateFlatButton(m, 80, 26, "取消")
        closeBtn:SetPoint("BOTTOMRIGHT", -16, 14)
        closeBtn:SetScript("OnClick", function() m:Hide() end)

        local resetBtn = Theme:CreateActionButton(m, 104, 26, "恢复默认名", "restore")
        resetBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
        resetBtn:SetScript("OnClick", function()
            if m.targetPetID then
                C_PetJournal.SetCustomName(m.targetPetID, "")
            end
            m:Hide()
            C_Timer.After(0.2, RefreshAfterPetRename)
        end)
        m.resetBtn = resetBtn

        local okBtn = Theme:CreateActionButton(m, 104, 26, "确认改名", "rename", nil, "PRIMARY")
        okBtn:SetPoint("RIGHT", resetBtn, "LEFT", -8, 0)
        okBtn:SetScript("OnClick", function()
            if m.targetPetID then
                C_PetJournal.SetCustomName(m.targetPetID, strtrim(m.box:GetText() or ""))
            end
            m:Hide()
            C_Timer.After(0.2, RefreshAfterPetRename)
        end)
        m.okBtn = okBtn

        box:SetScript("OnEnterPressed", function() okBtn:Click() end)

        ns.PetRenameModal = m
    end

    local m = ns.PetRenameModal
    m.targetPetID = petID
    m.box:SetText(currentName or "")
    m.box.placeholder:Hide()
    m:Show()
    ns:BringModalToFront(m)
end

function ns:ShowPetNoteModal(speciesID, petName)
    self:HideAllPopups()
    if not speciesID then return end
    if not ns.PetNoteModal then
        local m = CreateFrame("Frame", "WishPetTacticsPetNoteModal", ns.MainFrame or UIParent, "BackdropTemplate")
        m:SetSize(380, 180)
        m:SetPoint("CENTER", ns.MainFrame or UIParent, "CENTER", 0, 0)
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(140)
        m:SetMovable(true)
        m:SetClampedToScreen(true)
        m:RegisterForDrag("LeftButton")
        m:SetScript("OnDragStart", m.StartMoving)
        m:SetScript("OnDragStop", m.StopMovingOrSizing)
        Theme:ApplyBackdrop(m, Theme.Colors.bgPopup, Theme.Colors.border)
        ns:MakeModal(m)

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 16, -14)
        Theme:HookLocalizedFontString(title)
        m.title = title

        local box = Theme:CreateFlatEditBox(m, 348, 28, MODAL_LOCALE_TEXT.notePetPh)
        box:SetPoint("TOPLEFT", 16, -54)
        m.box = box

        local closeBtn = Theme:CreateFlatButton(m, 80, 26, "取消")
        closeBtn:SetPoint("BOTTOMRIGHT", -16, 14)
        closeBtn:SetScript("OnClick", function() m:Hide() end)

        local function ApplyNoteAndRefresh(newNote)
            if m.targetSpeciesID then
                ns.db.petNotes = ns.db.petNotes or {}
                ns.db.petNotes[m.targetSpeciesID] = newNote
                if ns.InvalidatePetListResults then ns:InvalidatePetListResults() end
            end
            m:Hide()
            if ns.PetPickerModal and ns.PetPickerModal:IsShown() and ns.PetPickerModal.Refresh then
                ns.PetPickerModal:Refresh()
            end
            if ns.RefreshAllUI then ns:RefreshAllUI() end
        end

        local clearBtn = Theme:CreateActionButton(m, 96, 26, "清空备注", "clear")
        clearBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
        clearBtn:SetScript("OnClick", function()
            ApplyNoteAndRefresh(nil)
        end)
        m.clearBtn = clearBtn

        local okBtn = Theme:CreateActionButton(m, 90, 26, "保存", "save", "保存备注", "PRIMARY")
        okBtn:SetPoint("RIGHT", clearBtn, "LEFT", -8, 0)
        okBtn:SetScript("OnClick", function()
            local txt = strtrim(m.box:GetText() or "")
            ApplyNoteAndRefresh(txt ~= "" and txt or nil)
        end)
        m.okBtn = okBtn

        box:SetScript("OnEnterPressed", function() okBtn:Click() end)

        ns.PetNoteModal = m
    end

    local m = ns.PetNoteModal
    m.targetSpeciesID = speciesID
    m.title:SetText(MODAL_LOCALE_TEXT.notePetTitle .. (petName or ""))
    ns.db.petNotes = ns.db.petNotes or {}
    m.box:SetText(ns.db.petNotes[speciesID] or "")
    m.box.placeholder:SetShown(m.box:GetText() == "")

    m:Show()
    ns:BringModalToFront(m)
end

-- ==================== 4. 手动输入 NPC ID 或名称添加新目标弹窗 ====================
function ns:ShowManualAddTargetModal()
    self:HideAllPopups()
    if not ns.ManualAddTargetModal then
        local m = CreateFrame("Frame", "WishPetTacticsManualAddTargetModal", ns.MainFrame or UIParent, "BackdropTemplate")
        m:SetSize(360, 150)
        m:SetPoint("CENTER")
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(150)
        m:SetMovable(true)
        m:SetClampedToScreen(true)
        m:RegisterForDrag("LeftButton")
        m:SetScript("OnDragStart", m.StartMoving)
        m:SetScript("OnDragStop", m.StopMovingOrSizing)
        Theme:ApplyBackdrop(m, Theme.Colors.bgPopup, Theme.Colors.border, true)
        ns:MakeModal(m)
        Theme:EnableDialogDrag(m)

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 16, -14)
        Theme:HookLocalizedFontString(title)
        title:SetText(MODAL_LOCALE_TEXT.addTargetTitle)

        local sub = m:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sub:SetPoint("TOPLEFT", 16, -38)
        Theme:HookLocalizedFontString(sub)
        sub:SetText(MODAL_LOCALE_TEXT.addTargetSub)

        m.box = Theme:CreateFlatEditBox(m, 328, 28, MODAL_LOCALE_TEXT.addTargetPh)
        m.box:SetPoint("TOPLEFT", 16, -58)

        local cancelBtn = Theme:CreateFlatButton(m, 80, 26, "取消")
        cancelBtn:SetPoint("BOTTOMRIGHT", -16, 14)
        cancelBtn:SetScript("OnClick", function() m:Hide() end)

        m.okBtn = Theme:CreateActionButton(m, 108, 26, "确认添加", "validate", nil, "PRIMARY")
        m.okBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -8, 0)
        m.okBtn:SetScript("OnClick", function()
            local raw = strtrim(m.box:GetText() or "")
            if raw == "" then return end

            local route, rKey = ns:EnsureTargetRouteFromInput(raw)
            m:Hide()
            if route and rKey and ns.RoutingModal and ns.RoutingModal:IsShown() then
                ns.RoutingModal.pendingTargetID = nil
                ns.RoutingModal.pendingTargetName = nil
                ns.RoutingModal.selectedKey = rKey
                ns.RoutingModal:Refresh()
            end
        end)

        m.box:SetScript("OnEnterPressed", function() m.okBtn:Click() end)

        ns.ManualAddTargetModal = m
    end

    local m = ns.ManualAddTargetModal
    m.box:SetText("")
    m.box.placeholder:Show()
    m:Show()
    ns:BringModalToFront(m)
    m.box:SetFocus()
end