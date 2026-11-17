local ADDON_NAME, ns = ...
local Theme = ns.Theme
local ROWS = 7

function ns:ShowGossipLearningModal(optionID, session)
    if not ns.db or ns.db.settings.autoLearnGossip == false then return false end
    if not ns.GossipLearningModal then
        local f = CreateFrame("Frame", "WishPetTacticsGossipLearning", UIParent, "BackdropTemplate")
        f:SetSize(460, 390)
        f:SetPoint("CENTER", 250, 0)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        Theme:ApplyBackdrop(f, Theme.Colors.bgPopup, Theme.Colors.borderBlue, true)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOPLEFT", 16, -16)
        Theme:HookLocalizedFontString(f.title)
        f.title:SetText(ns:T("关联宠物对战目标"))
        f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        Theme:HookLocalizedFontString(f.hint)
        f.hint:SetPoint("TOPLEFT", 16, -43)
        f.hint:SetWidth(428)
        f.hint:SetJustifyH("LEFT")
        f.hint:SetText(ns:T("此 NPC 身份暂不可读。点选它对应的已配置目标，只需关联一次。以后自动加载队伍并对话。"))
        f.search = Theme:CreateFlatEditBox(f, 428, 25, "搜索目标或队伍名称...")
        f.search:SetPoint("TOPLEFT", 16, -84)
        f.rows = {}
        f.candidates = {}
        f.offset = 0
        function f:RefreshRows()
            local query = strlower(strtrim(self.search:GetText() or ""))
            local filtered = self.filtered or {}
            wipe(filtered)
            self.filtered = filtered
            for _, candidate in ipairs(self.candidates) do
                local ok, score = true, 0
                if query ~= "" then
                    ok, score = ns.FuzzySearch:Match(candidate.search, query)
                end
                if ok then
                    candidate._matchScore = score
                    filtered[#filtered + 1] = candidate
                end
            end
            if query ~= "" and #filtered > 1 then
                table.sort(filtered, function(a, b)
                    return (a._matchScore or 0) > (b._matchScore or 0)
                end)
            end
            self.offset = math.max(0, math.min(self.offset, math.max(0, #filtered - ROWS)))
            for i, row in ipairs(self.rows) do
                local candidate = filtered[self.offset + i]
                if candidate then
                    row.routeKey = candidate.key
                    row.text:SetText(candidate.label .. "  |cff9ca3af" .. candidate.team .. "|r")
                    row:Show()
                else row.routeKey = nil; row:Hide() end
            end
            self.status:SetText(#filtered == 0 and "没有匹配的目标。请先新建或导入队伍并设置目标。"
                or ns:TF("%d 个目标 · 滚轮翻页 · 请按 NPC 身份选择", #filtered))
        end
        f.search:SetScript("OnTextChanged", function() f.offset = 0; f:RefreshRows() end)
        Theme:EnableSearchClearButton(f.search, function()
            f.offset = 0
            f:RefreshRows()
        end)
        for i = 1, ROWS do
            local row = Theme:CreateMenuRow(f, 428, 28, "")
            row:SetPoint("TOPLEFT", 16, -116 - (i - 1) * 29)
            row:SetScript("OnClick", function(self)
                if f.session ~= ns.AutoRouting:GetGossipSession() then
                    f:Hide(); ns:PrintError("对话已经变化，请重新打开 NPC 对话。"); return
                end
                if not ns.AutoRouting:RememberGossipRoute(self.routeKey, f.optionID, true) then
                    ns:PrintError("当前选项或目标绑定已经变化，未保存关联。"); return
                end
                f:Hide()
                ns.AutoRouting:ProcessCurrentGossip()
            end)
            f.rows[i] = row
        end
        f:EnableMouseWheel(true)
        f:SetScript("OnMouseWheel", function(_, delta) f.offset = f.offset - delta; f:RefreshRows() end)
        f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        Theme:HookLocalizedFontString(f.status)
        f.status:SetPoint("TOPLEFT", 16, -325)
        f.status:SetWidth(428)
        f.status:SetJustifyH("LEFT")
        local later = Theme:CreateFlatButton(f, 90, 26, "稍后")
        later:SetPoint("BOTTOMRIGHT", -16, 14)
        later:SetScript("OnClick", function() f:Hide() end)
        local disable = Theme:CreateFlatButton(f, 150, 26, "关闭自动学习提示")
        disable:SetPoint("BOTTOMLEFT", 16, 14)
        disable:SetScript("OnClick", function()
            ns.db.settings.autoLearnGossip = false
            f:Hide()
            print(ns:T("[Wish] 已关闭学习提示；输入 /wplearn on 可重新开启。"))
        end)
        f:SetScript("OnHide", function(self)
            self.session, self.optionID = nil, nil
            wipe(self.candidates)
            if self.filtered then wipe(self.filtered) end
            for _, row in ipairs(self.rows) do row.routeKey = nil end
        end)
        if UISpecialFrames then table.insert(UISpecialFrames, "WishPetTacticsGossipLearning") end
        ns.GossipLearningModal = f
    end
    local f = ns.GossipLearningModal
    ns.AutoRouting:SyncTargetGroups()
    wipe(f.candidates)
    local stages = ns.AutoRouting:GetScenarioStageMatches()
    local stageKeys = {}
    for _, match in ipairs(stages) do stageKeys[match.key] = true end
    for key, route in pairs(ns.db.routeMappings or {}) do
        if route.teams and #route.teams > 0 then
            local label = route.npcName or tostring(key)
            f.candidates[#f.candidates + 1] = {key = key, label = label, team = route.teams[1],
                search = strlower(label .. " " .. table.concat(route.teams, " ")), stage = stageKeys[key] == true}
        end
    end
    table.sort(f.candidates, function(a, b)
        if a.stage ~= b.stage then return a.stage end
        if a.label ~= b.label then return a.label < b.label end
        return tostring(a.key) < tostring(b.key)
    end)
    f.optionID, f.session, f.offset = optionID, session, 0
    f.search:SetText("")
    f:RefreshRows()
    f:Show()
    return true
end

SlashCmdList["WISHLEARNING"] = function(msg)
    if not ns.db then return end
    ns.db.settings.autoLearnGossip = strlower(strtrim(msg or "")) ~= "off"
    if ns.db.settings.autoLearnGossip then
        print(ns:T("[Wish] 自动学习已开启。"))
        ns.AutoRouting:ProcessCurrentGossip()
    else
        if ns.GossipLearningModal then ns.GossipLearningModal:Hide() end
        print(ns:T("[Wish] 自动学习提示已关闭；已有的关联仍会生效。"))
    end
end
SLASH_WISHLEARNING1 = "/wplearn"
