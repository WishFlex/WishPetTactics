local ADDON_NAME, ns = ...
local Theme = ns.Theme

-- Native unit and aura widgets retain Blizzard's updates and tooltip handlers.
-- Layout and palette reference the user-provided NDui PetBattleUI.lua.
local skinReady = false
local units = {}

local function Border(texture)
    local parent = texture:GetParent()
    local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    border:SetFrameLevel(math.max(0, parent:GetFrameLevel() - 1))
    border:SetPoint("TOPLEFT", texture, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", texture, "BOTTOMRIGHT", 1, -1)
    border:EnableMouse(false)
    Theme:ApplyBackdrop(border, {0.12, 0.12, 0.14, 1}, {0, 0, 0, 1}, false)
    return border
end

local function HideArt(unit, keys)
    for _, key in ipairs(keys) do
        if unit[key] then unit[key]:SetAlpha(0) end
    end
end

local function UpdateUnit(unit)
    if not unit._wishNativeSkin or not unit.petOwner or not unit.petIndex then return end
    if not C_PetBattles.IsInBattle() or unit.petIndex > C_PetBattles.GetNumPets(unit.petOwner) then return end
    local ally = unit.petOwner == Enum.BattlePetOwner.Ally
    if ally then unit.Icon:SetTexCoord(.92, .08, .08, .92)
    else unit.Icon:SetTexCoord(.08, .92, .08, .92) end
    local quality = (C_PetBattles.GetBreedQuality(unit.petOwner, unit.petIndex) or 0) + 1
    local color = ITEM_QUALITY_COLORS[quality] or ITEM_QUALITY_COLORS[1]
    local dead = (C_PetBattles.GetHealth(unit.petOwner, unit.petIndex) or 0) <= 0
    unit.wishIconBorder:SetBackdropBorderColor(color.r, color.g, color.b, 1)
    if dead then unit.wishIconBorder:SetBackdropBorderColor(1, .12, .24, 1) end
    unit.wishDeadIcon:SetShown(dead)
    if unit.wishTypeIcon then
        local petType = C_PetBattles.GetPetType(unit.petOwner, unit.petIndex)
        local suffix = PET_TYPE_SUFFIX and PET_TYPE_SUFFIX[petType]
        unit.wishTypeIcon:SetTexture(suffix and ("Interface\\Icons\\Icon_PetFamily_" .. suffix))
    end
end

local function StyleHealthBar(unit, ally, main)
    local edge = ally and "LEFT" or "RIGHT"
    local opposite = ally and "RIGHT" or "LEFT"
    local bar = unit.ActualHealthBar
    bar:ClearAllPoints()
    bar:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetTexCoord(0, 1, 0, 1)
    bar:SetVertexColor(1, 1, 1, 1)
    if ally then
        bar:SetGradient("VERTICAL", CreateColor(.26, 1, .22, 1), CreateColor(.13, .5, .11, 1))
    else
        bar:SetGradient("VERTICAL", CreateColor(1, .12, .24, 1), CreateColor(.5, .06, .12, 1))
    end
    if main then
        bar:SetPoint("BOTTOM" .. edge, unit.Icon, "BOTTOM" .. opposite, ally and 8 or -8, 0)
        bar:SetHeight(38)
    else
        bar:SetPoint("TOPLEFT", unit.Icon, "BOTTOMLEFT", 1, -6)
    end
end

local function SkinUnit(unit, ally, main)
    units[#units + 1] = unit
    unit._wishNativeSkin = true
    local edge = ally and "LEFT" or "RIGHT"
    local opposite = ally and "RIGHT" or "LEFT"
    local sign = ally and 1 or -1
    HideArt(unit, {"HealthBarBG", "HealthBarFrame", "HealthDivider", "Border",
        "Border2", "BorderFlash", "BorderAlive", "BorderDead", "LevelUnderlay", "SpeedUnderlay"})
    unit.wishIconBorder = Border(unit.Icon)
    unit.wishDeadIcon = unit:CreateTexture(nil, "OVERLAY")
    unit.wishDeadIcon:SetAllPoints(unit.Icon)
    unit.wishDeadIcon:SetTexture("Interface\\PetBattles\\DeadPetIcon")
    unit.wishDeadIcon:Hide()
    unit.healthBarWidth = main and 250 or 36
    StyleHealthBar(unit, ally, main)
    local bar = unit.ActualHealthBar
    local background = Border(bar)
    background:SetBackdropColor(0.12, 0.12, 0.14, .18)
    background:ClearAllPoints()
    background:SetWidth(unit.healthBarWidth + 2)
    local barEdge = main and edge or "LEFT"
    background:SetPoint("TOP" .. barEdge, bar, "TOP" .. barEdge, barEdge == "LEFT" and -1 or 1, 1)
    background:SetPoint("BOTTOM" .. barEdge, bar, "BOTTOM" .. barEdge, barEdge == "LEFT" and -1 or 1, -1)
    if main then
        unit.HealthText:ClearAllPoints()
        unit.HealthText:SetPoint("CENTER", background)
        unit.wishTypeIcon = unit:CreateTexture(nil, "ARTWORK")
        unit.wishTypeIcon:SetSize(25, 25)
        unit.wishTypeIcon:SetPoint("BOTTOM" .. edge, bar, "TOP" .. edge, 0, 4)
        unit.wishTypeIcon:SetTexCoord(.08, .92, .08, .92)
        Border(unit.wishTypeIcon)
        unit.PetType:SetAlpha(0)
        unit.PetType:ClearAllPoints()
        unit.PetType:SetAllPoints(unit.wishTypeIcon)
        unit.Name:ClearAllPoints()
        unit.Name:SetPoint(edge, unit.wishTypeIcon, opposite, sign * 5, 0)
        unit.Level:SetFontObject(SystemFont_Shadow_Huge1)
        unit.Level:ClearAllPoints()
        unit.Level:SetPoint("BOTTOM" .. edge, unit.Icon, "BOTTOM" .. edge, 2, 2)
        if unit.SpeedIcon then
            unit.SpeedIcon:SetSize(30, 30)
            unit.SpeedIcon:ClearAllPoints()
            unit.SpeedIcon:SetPoint(edge, background, opposite, sign * 5, 0)
            if ally then unit.SpeedIcon:SetTexCoord(0, .5, .5, 1)
            else unit.SpeedIcon:SetTexCoord(.5, 0, .5, 1) end
        end
    end
    UpdateUnit(unit)
end

local function SkinAuras(holder)
    if not skinReady or not holder._wishBattleAuraHolder then return end
    for _, aura in ipairs(holder.frames or {}) do
        if not aura._wishIconBorder then
            aura.Icon:SetTexCoord(.08, .92, .08, .92)
            aura._wishIconBorder = Border(aura.Icon)
        end
        aura.DebuffBorder:SetAlpha(0)
    end
end

local function HideSelectionWidget(w)
    if not w then return end
    if w.SetAlpha then w:SetAlpha(0) end
    if w.Hide then w:Hide() end
end

local function IsModelWidget(child, unit)
    if not child then return false end
    if child == unit.ModelScene or child == unit.Model then return true end
    local objType = child.GetObjectType and child:GetObjectType() or ""
    return objType == "ModelScene" or objType == "Model" or objType == "PlayerModel" or objType == "DressUpModel"
end

local function SkinPetSelectionFrame(frame)
    local psf = frame and frame.BottomFrame and frame.BottomFrame.PetSelectionFrame
    if not psf then return end
    for _, region in ipairs({ psf:GetRegions() }) do
        if region and region.SetAlpha then region:SetAlpha(0) end
    end
    for _, k in ipairs({ "Bg", "Background", "Border", "NineSlice", "HideButton" }) do
        HideSelectionWidget(psf[k])
    end

    local hideKeys = {
        "Framing", "Icon", "Iconbg", "Name", "Level", "LevelUnderlay",
        "HealthBarBG", "ActualHealthBar", "HealthText", "HealthDivider",
        "wishSelectHealthBg", "SelectedTexture", "MouseoverHighlight",
        "Background", "Border", "PetType", "SpeedIcon", "SpeedUnderlay", "wishBreedText",
    }
    local numPets = NUM_BATTLE_PETS_IN_BATTLE or 3
    local allyOwner = (Enum and Enum.BattlePetOwner and Enum.BattlePetOwner.Ally) or 1
    for i = 1, numPets do
        local unit = psf["Pet" .. i]
        if unit then
            if unit.SetBackdropColor then unit:SetBackdropColor(0, 0, 0, 0) end
            if unit.SetBackdropBorderColor then unit:SetBackdropBorderColor(0, 0, 0, 0) end
            if unit.SetNormalTexture then unit:SetNormalTexture("") end
            if unit.SetPushedTexture then unit:SetPushedTexture("") end
            if unit.SetHighlightTexture then unit:SetHighlightTexture("") end
            if unit.SetDisabledTexture then unit:SetDisabledTexture("") end
            if not unit.wishSelectionDeadIcon then
                local iconHost = unit.ModelScene or unit.Model or unit
                local deadTex = iconHost:CreateTexture(nil, "OVERLAY", nil, 7)
                deadTex:SetSize(44, 44)
                deadTex:SetPoint("CENTER", iconHost, "CENTER", 0, -4)
                deadTex:SetTexture("Interface\\PetBattles\\DeadPetIcon")
                deadTex:Hide()
                unit.wishSelectionDeadIcon = deadTex
            end
            for _, region in ipairs({ unit:GetRegions() }) do
                if region and region ~= unit.wishSelectionDeadIcon and region.SetAlpha then
                    region:SetAlpha(0)
                end
            end
            for _, k in ipairs(hideKeys) do
                HideSelectionWidget(unit[k])
            end
            HideSelectionWidget(unit.DeadOverlay)
            for _, child in ipairs({ unit:GetChildren() }) do
                if IsModelWidget(child, unit) then
                    if child.SetAlpha then child:SetAlpha(1) end
                    if child.Show then child:Show() end
                else
                    HideSelectionWidget(child)
                end
            end
            if unit.ModelScene then
                unit.ModelScene:SetAlpha(1)
                unit.ModelScene:Show()
            end
            if unit.Model then
                unit.Model:SetAlpha(1)
                unit.Model:Show()
            end
            local isDead = C_PetBattles and C_PetBattles.IsInBattle()
                and i <= (C_PetBattles.GetNumPets(allyOwner) or 0)
                and ((C_PetBattles.GetHealth(allyOwner, i) or 1) <= 0)
            unit.wishSelectionDeadIcon:SetShown(isDead)
        end
    end
end

function ns:SkinPetSelectionFrame()
    if PetBattleFrame then
        SkinPetSelectionFrame(PetBattleFrame)
    end
end

function ns:SkinBattleUnitFrames()
    if skinReady or not PetBattleFrame or not PetBattleUnitFrame_UpdateDisplay then return end
    local frame = PetBattleFrame
    -- NDui may already own these native widgets. Reuse its completed skin.
    if frame.ActiveAlly.petIcon and frame.ActiveAlly.healthBg and frame.ActiveAlly.Iconbg then
        for index, unit in ipairs({frame.ActiveAlly, frame.ActiveEnemy, frame.Ally2, frame.Ally3, frame.Enemy2, frame.Enemy3}) do
            StyleHealthBar(unit, index == 1 or index == 3 or index == 4, index <= 2)
            if unit.healthBg then unit.healthBg:SetBackdropColor(0.12, 0.12, 0.14, .18) end
        end
        SkinPetSelectionFrame(frame)
        skinReady = true
        self:UpdateBattleEnemyBreedDisplay()
        return
    end
    SkinUnit(frame.ActiveAlly, true, true)
    SkinUnit(frame.ActiveEnemy, false, true)
    SkinUnit(frame.Ally2, true, false)
    SkinUnit(frame.Ally3, true, false)
    SkinUnit(frame.Enemy2, false, false)
    SkinUnit(frame.Enemy3, false, false)
    frame.Ally2:ClearAllPoints()
    frame.Ally2:SetPoint("BOTTOMRIGHT", frame.ActiveAlly, "BOTTOMLEFT", -10, 20)
    frame.Ally3:ClearAllPoints()
    frame.Ally3:SetPoint("BOTTOMRIGHT", frame.Ally2, "BOTTOMLEFT", -8, 0)
    frame.Enemy2:ClearAllPoints()
    frame.Enemy2:SetPoint("BOTTOMLEFT", frame.ActiveEnemy, "BOTTOMRIGHT", 10, 20)
    frame.Enemy3:ClearAllPoints()
    frame.Enemy3:SetPoint("BOTTOMLEFT", frame.Enemy2, "BOTTOMRIGHT", 8, 0)
    HideArt(frame, {"TopArtLeft", "TopArtRight", "TopVersus"})
    frame.TopVersusText:ClearAllPoints()
    frame.TopVersusText:SetPoint("TOP", frame, "TOP", 0, -45)
    local weather = frame.WeatherFrame
    weather:ClearAllPoints()
    weather:SetPoint("TOP", frame.TopVersusText, "BOTTOM", 0, -15)
    weather.Label:SetAlpha(0)
    weather.Name:SetAlpha(0)
    weather.Icon:ClearAllPoints()
    weather.Icon:SetPoint("TOP", frame.TopVersusText, "BOTTOM", 0, -15)
    weather.Icon:SetTexCoord(.08, .92, .08, .92)
    Border(weather.Icon)
    weather.BackgroundArt:ClearAllPoints()
    weather.BackgroundArt:SetPoint("TOP", UIParent, "TOP")
    weather.Duration:ClearAllPoints()
    weather.Duration:SetPoint("CENTER", weather.Icon, "CENTER", 1, 0)
    SkinPetSelectionFrame(frame)
    skinReady = true
    for _, key in ipairs({"AllyBuffFrame", "AllyDebuffFrame", "EnemyBuffFrame", "EnemyDebuffFrame",
        "AllyPadBuffFrame", "AllyPadDebuffFrame", "EnemyPadBuffFrame", "EnemyPadDebuffFrame"}) do
        local holder = frame[key]
        if holder then
            holder._wishBattleAuraHolder = true
            holder:SetAlpha(1)
            holder:SetScale(1)
            SkinAuras(holder)
        end
    end
    hooksecurefunc("PetBattleUnitFrame_UpdateDisplay", UpdateUnit)
    hooksecurefunc("PetBattleUnitFrame_UpdateHealthInstant", UpdateUnit)
    hooksecurefunc("PetBattleUnitFrame_UpdatePetType", UpdateUnit)
    hooksecurefunc("PetBattleAuraHolder_Update", SkinAuras)
    if _G.PetBattlePetSelectionFrame_Update then
        hooksecurefunc("PetBattlePetSelectionFrame_Update", function()
            SkinPetSelectionFrame(frame)
        end)
    end
    -- Recompute native fill widths after changing the full-health geometry.
    if C_PetBattles.IsInBattle() then
        for _, unit in ipairs(units) do
            if unit.petOwner and unit.petIndex
                and unit.petIndex <= C_PetBattles.GetNumPets(unit.petOwner) then
                PetBattleUnitFrame_UpdateHealthInstant(unit)
            end
        end
        self:UpdateBattleEnemyBreedDisplay()
    end
end
