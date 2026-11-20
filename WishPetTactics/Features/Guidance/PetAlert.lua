local _, ns = ...

local function OpenCollectedPet(petID)
    if not petID or InCombatLockdown() or (C_PetBattles and C_PetBattles.IsInBattle()) then return end
    local species, _, _, _, _, _, _, name = C_PetJournal.GetPetInfoByPetID(petID)
    if not species or not name then return end
    local main = ns:CreateMainFrame()
    ns:ShowMainFrame("HOME")
    if ns.SearchFilter and ns.SearchFilter.ResetPetFilters then ns.SearchFilter:ResetPetFilters() end
    if main.mainUIStyle == "MINIMAL" then
        local picker = main.minimalPicker
        if picker and picker:IsShown() then ns:CloseMinimalPicker() end
        ns:OpenMinimalPicker("ALL_PETS")
        if picker then
            picker.search:SetText(name)
            picker.selectedPetID = petID
            picker.page = 0
            ns:RefreshMinimalPicker()
        end
    elseif ns.SetCompactLeftMode and main.compactLeft then
        ns:SetCompactLeftMode("PETS")
        main.compactLeft.searchBox:SetText(name)
        main.compactSelectedPetID = petID
        main.compactLeft.offset = 0
        ns:RefreshCompactLeftPanel()
    end
end

local function AttachActivePetAlerts(system)
    local pool = system and system.alertFramePool
    if not pool or not pool.EnumerateActive then return end
    for frame in pool:EnumerateActive() do
        if not frame._wishPetAlertHooked then
            frame._wishPetAlertHooked = true
            frame:HookScript("OnClick", function(self, button, down)
                if button ~= "LeftButton" or down or IsModifiedClick() or DISALLOW_FRAME_TOGGLING then return end
                local petID = self.petID
                C_Timer.After(0, function() OpenCollectedPet(petID) end)
            end)
        end
    end
end

local alertWatcher = CreateFrame("Frame")
alertWatcher:RegisterEvent("PLAYER_LOGIN")
alertWatcher:RegisterEvent("NEW_PET_ADDED")
alertWatcher:SetScript("OnEvent", function()
    local system = NewPetAlertSystem
    if not system then return end
    if not system._wishPetAlertHooked and system.ShowAlert then
        system._wishPetAlertHooked = true
        hooksecurefunc(system, "ShowAlert", AttachActivePetAlerts)
    end
    C_Timer.After(0, function() AttachActivePetAlerts(system) end)
end)
