local _, ns = ...
local Theme = ns.Theme
function ns:ForumText(cn, tw, en)
    return self.locale == "zhCN" and cn or self.locale == "zhTW" and tw or en
end

function ns:TeamContainsSpecies(team, species)
    for slot = 1, 3 do
        local id = team.speciesLoadout and team.speciesLoadout[slot]
        if not id or id == 0 then
            local pet = team.pets and team.pets[slot]
            if pet and pet ~= "LEVELING" then id = C_PetJournal.GetPetInfoByPetID(pet) end
        end
        if id == species then return true end
        for _, backup in ipairs(team.slotBackups and team.slotBackups[slot] or {}) do
            if backup.speciesID == species then return true end
        end
    end
    return false
end

function ns:SearchSameSpecies(team, slot)
    if team and self.db.teams[self.db.selectedTeamIdx] ~= team and self.RequestCompactTeamSwitch then
        for index, candidate in ipairs(self.db.teams) do
            if candidate == team then
                self:HideAllPopups()
                self:RequestCompactTeamSwitch(index, function() self:SearchSameSpecies(team, slot) end)
                return
            end
        end
    end
    local species = team and team.speciesLoadout and team.speciesLoadout[slot]
    local pet = team and team.pets and team.pets[slot]
    if (not species or species == 0) and pet and pet ~= "LEVELING" then species = C_PetJournal.GetPetInfoByPetID(pet) end
    if not species or species <= 0 then return end
    local name = self:GetSpeciesMeta(species).name
    self:HideAllPopups()
    self:ShowMainFrame("HOME")
    self.SearchFilter:ResetPetFilters()
    local main = self.MainFrame
    if main.mainUIStyle == "MINIMAL" then
        if main.minimalPicker:IsShown() then self:CloseMinimalPicker() end
        self:OpenMinimalPicker("ALL_PETS")
        main.minimalPicker.search:SetText(name)
    else
        self:SetCompactLeftMode("PETS")
        main.compactLeft.searchBox:SetText(name)
        self:RefreshCompactLeftPanel()
    end
end

function ns:FindRelatedTeams(species)
    self:ShowTeamMatrixModal()
    local left = self.MainFrame and self.MainFrame.compactLeft
    if not left then return end
    left.searchBox:SetText("")
    left.relatedSpecies = species
    left._itemsMode = nil
    self:RefreshCompactLeftPanel()
end

function ns:EnqueueTeamPets(teams)
    local seen, count = {}, 0
    self.Leveling:PruneManualQueue()
    local cache = self:GetPetJournalCache()
    for _, team in ipairs(teams or {}) do
            for slot = 1, 3 do
                local species = team.speciesLoadout and team.speciesLoadout[slot]
                local pet = team.pets and team.pets[slot]
                if (not species or species == 0) and pet and pet ~= "LEVELING" then species = C_PetJournal.GetPetInfoByPetID(pet) end
                local candidates = species and cache.bySpecies[species]
                for _, id in ipairs(candidates or {}) do
                    local _, _, level, _, _, _, _, _, _, _, _, _, _, _, canBattle = C_PetJournal.GetPetInfoByPetID(id)
                    if level and level < 25 and canBattle ~= false and not seen[id] and not self.Leveling:IsPetInQueue(id) then
                        seen[id] = true
                        self.db.manualQueueOrder = self.db.manualQueueOrder or {}
                        self.db.manualQueueOrder[#self.db.manualQueueOrder + 1] = id
                        count = count + 1
                    end
                end
            end
    end
    self.Leveling:PruneManualQueue()
    if self.RefreshAllUI then self:RefreshAllUI() end
    self:ShowUIFeedback(string.format(self:ForumText("已加入 %d 只未满级宠物", "已加入 %d 隻未滿級寵物", "Added %d under-level pets"), count))
end

function ns:EnqueueGroupPets(group)
    local teams = {}
    for _, team in ipairs(self.db.teams) do
        if (team.group or "未分组队伍") == group then teams[#teams + 1] = team end
    end
    self:EnqueueTeamPets(teams)
end

function ns:EnqueueTargetPets(route)
    local teams = {}
    for _, name in ipairs(route and route.teams or {}) do
        local team = self.AutoRouting:FindTeamByName(name)
        if team then teams[#teams + 1] = team end
    end
    self:EnqueueTeamPets(teams)
end

function ns:ShowTeamNotes(team)
    if not team then return end
    if not self.TeamNotesPanel then
        local frame = CreateFrame("Frame", "WishPetTacticsTeamNotes", UIParent, "BackdropTemplate")
        frame:Hide()
        frame:SetSize(480, 400)
        frame:SetPoint("CENTER")
        frame:SetClampedToScreen(true)
        Theme:ApplyBackdrop(frame, Theme.Colors.bgPopup, Theme.Colors.border, false)
        self:MakeModal(frame)
        local close = Theme:CreateCloseIconButton(frame, function() frame:Hide() end)
        close:SetPoint("TOPRIGHT", -12, -12)
        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.title:SetPoint("TOPLEFT", 14, -15)
        frame.title:SetWidth(420)
        frame.title:SetJustifyH("LEFT")
        local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -45)
        scroll:SetPoint("BOTTOMRIGHT", -34, 16)
        local text = CreateFrame("EditBox", nil, scroll)
        text:SetMultiLine(true)
        text:SetAutoFocus(false)
        text:SetFontObject(GameFontHighlight)
        text:SetWidth(420)
        text:SetScript("OnEscapePressed", function(self) self:ClearFocus(); frame:Hide() end)
        scroll:SetScrollChild(text)
        frame.text = text
        self.TeamNotesPanel = frame
        tinsert(UISpecialFrames, frame:GetName())
    end
    local frame = self.TeamNotesPanel
    frame.title:SetText(team.name or "")
    frame.text:SetText(team.rematchNotes or team.inlineNote or self:ForumText("此队伍没有战术备注", "此隊伍沒有戰術備註", "No strategy notes for this team"))
    frame.text:SetCursorPosition(0)
    frame.text:ClearFocus()
    frame:Show()
    self:BringModalToFront(frame)
end
