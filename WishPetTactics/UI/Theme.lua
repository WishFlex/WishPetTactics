local ADDON_NAME, ns = ...

local Theme = {}
ns.Theme = Theme
ns.modalFrames = ns.modalFrames or {}

local ARROW_TGA_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Common\\down.tga"
local TOGGLE_KNOB_COLOR = { 0.45, 0.50, 0.58, 1.0 }

Theme.Colors = {
    bgMain        = { 0.04, 0.04, 0.04, 0.94 },
    bgPanel       = { 0.06, 0.06, 0.06, 0.92 },
    bgCard        = { 0.08, 0.08, 0.08, 0.90 },
    bgCardHover   = { 0.13, 0.13, 0.13, 0.95 },
    bgCardActive  = { 0.16, 0.16, 0.16, 0.96 },
    bgInput       = { 0.03, 0.03, 0.03, 0.95 },
    bgPopup       = { 0.05, 0.05, 0.05, 0.98 },

    border        = { 0.253, 0.253, 0.253, 1.00 },
    borderBlue    = { 0.00, 0.78, 1.00, 1.00 },
    borderGreen   = { 0.06, 0.78, 0.50, 1.00 },
    borderAmber   = { 0.96, 0.62, 0.05, 1.00 },
    borderRed     = { 0.94, 0.26, 0.26, 1.00 },
    divider       = { 0.233, 0.233, 0.233, 0.85 },

    btnNormal     = { 0.12, 0.12, 0.12, 0.92 },
    btnHover      = { 0.18, 0.18, 0.18, 0.98 },
    btnPrimary    = { 0.02, 0.52, 0.88, 0.95 },
    btnPrimaryHov = { 0.06, 0.64, 1.00, 1.00 },
    btnDanger     = { 0.68, 0.14, 0.18, 0.92 },
    btnDangerHov  = { 0.86, 0.20, 0.24, 1.00 },
    btnWarning    = { 0.72, 0.44, 0.04, 0.92 },
    btnWarningHov = { 0.90, 0.56, 0.08, 1.00 },
}

local MENU_ROW_BG       = { 0.00, 0.00, 0.00, 0.0 }
local MENU_ROW_BD       = { 0.00, 0.00, 0.00, 0.0 }

Theme.QualityColors = {
    [1] = { 0.62, 0.62, 0.62, "|cff9d9d9d" .. ns:T("粗糙") .. "|r" },
    [2] = { 1.00, 1.00, 1.00, "|cffffffff" .. ns:T("普通") .. "|r" },
    [3] = { 0.12, 1.00, 0.00, "|cff1eff00" .. ns:T("优秀") .. "|r" },
    [4] = { 0.00, 0.44, 0.87, "|cff0070dd" .. ns:T("稀有") .. "|r" },
    [5] = { 0.64, 0.21, 0.93, "|cffa335ee" .. ns:T("史诗") .. "|r" },
    [6] = { 1.00, 0.50, 0.00, "|cffff8000" .. ns:T("传奇") .. "|r" },
}

local function GetLocalizedPetTypeName(index, zhCNDefault)
    if ns.locale ~= "zhCN" then
        local globalName = _G["BATTLE_PET_NAME_" .. tostring(index)]
        if type(globalName) == "string" and globalName ~= "" then
            return globalName
        end
    end
    return ns:T(zhCNDefault)
end

local PET_TYPE_TEX_ROOT = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\PetTypes\\"
Theme.PetTypes = {
    [1]  = { name = GetLocalizedPetTypeName(1,  "人型"),   suffix = "Humanoid",   icon = PET_TYPE_TEX_ROOT .. "Humanoid.tga" },
    [2]  = { name = GetLocalizedPetTypeName(2,  "龙类"),   suffix = "Dragon",     icon = PET_TYPE_TEX_ROOT .. "Dragonkin.tga" },
    [3]  = { name = GetLocalizedPetTypeName(3,  "飞行"),   suffix = "Flying",     icon = PET_TYPE_TEX_ROOT .. "Flying.tga" },
    [4]  = { name = GetLocalizedPetTypeName(4,  "亡灵"),   suffix = "Undead",     icon = PET_TYPE_TEX_ROOT .. "Undead.tga" },
    [5]  = { name = GetLocalizedPetTypeName(5,  "小动物"), suffix = "Critter",    icon = PET_TYPE_TEX_ROOT .. "Critter.tga" },
    [6]  = { name = GetLocalizedPetTypeName(6,  "魔法"),   suffix = "Magical",    icon = PET_TYPE_TEX_ROOT .. "Magic.tga" },
    [7]  = { name = GetLocalizedPetTypeName(7,  "元素"),   suffix = "Elemental",  icon = PET_TYPE_TEX_ROOT .. "Elemental.tga" },
    [8]  = { name = GetLocalizedPetTypeName(8,  "野兽"),   suffix = "Beast",      icon = PET_TYPE_TEX_ROOT .. "Beast.tga" },
    [9]  = { name = GetLocalizedPetTypeName(9,  "水栖"),   suffix = "Water",      icon = PET_TYPE_TEX_ROOT .. "Aquatic.tga" },
    [10] = { name = GetLocalizedPetTypeName(10, "机械"),   suffix = "Mechanical", icon = PET_TYPE_TEX_ROOT .. "Mechanical.tga" },
}

Theme.StrongAgainstMap = {
    [1] = 2, [2] = 6, [3] = 9, [4] = 1, [5] = 4,
    [6] = 3, [7] = 10, [8] = 5, [9] = 7, [10] = 8,
}

Theme.ToughAgainstMap = {
    [1] = 5, [2] = 3, [3] = 8, [4] = 9, [5] = 7,
    [6] = 9, [7] = 5, [8] = 1, [9] = 4, [10] = 6,
}

Theme.trackedFrames = setmetatable({}, { __mode = "k" })
Theme.alphaFrames   = setmetatable({}, { __mode = "k" })

-- ==================== 1. 严格物理 1 像素计算与零闭包共享边框引擎 ====================
local cachedScreenHeight = nil
local cachedRematchLoaded = nil
local scaleRefreshPending = false

local function RunDeferredBorderRefresh()
    scaleRefreshPending = false
    if not (ns.RefreshMainUIScale and ns:RefreshMainUIScale()) then
        Theme:RefreshAllPixelBorders()
    end
end

local screenWatcher = CreateFrame("Frame")
screenWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
screenWatcher:RegisterEvent("UI_SCALE_CHANGED")
screenWatcher:RegisterEvent("ADDON_LOADED")
screenWatcher:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Rematch" then
            cachedRematchLoaded = true
        end
    else
        cachedScreenHeight = nil
        if not scaleRefreshPending then
            scaleRefreshPending = true
            C_Timer.After(0, RunDeferredBorderRefresh)
        end
    end
end)

function Theme:GetPixelScale(region)
    if not cachedScreenHeight then
        local _, sh = GetPhysicalScreenSize()
        cachedScreenHeight = (sh and sh > 0) and sh or 1440
    end
    local effScale = (region and region.GetEffectiveScale and region:GetEffectiveScale())
        or (ns.MainFrame and ns.MainFrame:GetEffectiveScale())
        or UIParent:GetEffectiveScale()
        or 1
    if effScale <= 0 then effScale = 1 end
    return 768.0 / cachedScreenHeight / effScale
end

function Theme:SnapTextureToPixel(tex)
    if not tex then return end
    if tex.SetSnapToPixelGrid then
        tex:SetSnapToPixelGrid(true)
    end
    if tex.SetTexelSnappingBias then
        tex:SetTexelSnappingBias(0)
    end
end

local BORDER_KEYS = { "TOP", "BOTTOM", "LEFT", "RIGHT" }

local function SharedUpdatePixelBorders(self, force)
    local e = self._wishBorderEdges
    if not e then return end

    local targetLvl = (self:GetFrameLevel() or 1) + 1
    if self._wishBorderHolder and self._lastBorderLvl ~= targetLvl then
        self._lastBorderLvl = targetLvl
        self._wishBorderHolder:SetFrameLevel(targetLvl)
    end

    local px = Theme:GetPixelScale(self)
    if not force and self._lastBorderPx == px then
        return
    end
    self._lastBorderPx = px

    e.TOP:ClearAllPoints()
    e.TOP:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    e.TOP:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
    e.TOP:SetHeight(px)

    e.BOTTOM:ClearAllPoints()
    e.BOTTOM:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, 0)
    e.BOTTOM:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
    e.BOTTOM:SetHeight(px)

    e.LEFT:ClearAllPoints()
    e.LEFT:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -px)
    e.LEFT:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, px)
    e.LEFT:SetWidth(px)

    e.RIGHT:ClearAllPoints()
    e.RIGHT:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -px)
    e.RIGHT:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, px)
    e.RIGHT:SetWidth(px)
end

local function SharedSetBackdropColor(self, r, g, b, a)
    r, g, b, a = r or 0, g or 0, b or 0, a or 1
    local finalA = a
    if self._wishFollowAlpha and ns.db and ns.db.settings and ns.db.settings.bgAlpha then
        finalA = ns.db.settings.bgAlpha
    end
    if self._bgR == r and self._bgG == g and self._bgB == b and self._bgA == finalA then
        return
    end
    self._bgR, self._bgG, self._bgB, self._bgA = r, g, b, finalA
    if self._wishBgTex then
        self._wishBgTex:SetVertexColor(r, g, b, finalA)
    end
end

local function SharedSetBackdropBorderColor(self, r, g, b, a)
    r, g, b, a = r or 1, g or 1, b or 1, a or 1
    if self._bdR == r and self._bdG == g and self._bdB == b and self._bdA == a then
        return
    end
    self._bdR, self._bdG, self._bdB, self._bdA = r, g, b, a
    local ed = self._wishBorderEdges
    if ed then
        ed.TOP:SetVertexColor(r, g, b, a)
        ed.BOTTOM:SetVertexColor(r, g, b, a)
        ed.LEFT:SetVertexColor(r, g, b, a)
        ed.RIGHT:SetVertexColor(r, g, b, a)
    end
end

local function SharedBorderOnShow(self)
    self:UpdatePixelBorders()
end

local function EnsureCrisp1PxBorder(frame)
    if frame._wishBorderEdges then return frame._wishBorderEdges end

    local holder = CreateFrame("Frame", nil, frame)
    holder:SetAllPoints(frame)
    holder:SetFrameLevel((frame:GetFrameLevel() or 1) + 1)
    holder:EnableMouse(false)
    frame._wishBorderHolder = holder

    local edges = {}
    for i = 1, 4 do
        local k = BORDER_KEYS[i]
        local tex = holder:CreateTexture(nil, "BORDER", nil, 7)
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        Theme:SnapTextureToPixel(tex)
        edges[k] = tex
    end

    frame._wishBorderEdges      = edges
    frame.UpdatePixelBorders     = SharedUpdatePixelBorders
    frame.SetBackdropColor       = SharedSetBackdropColor
    frame.SetBackdropBorderColor = SharedSetBackdropBorderColor
    frame:HookScript("OnShow", SharedBorderOnShow)

    return edges
end

function Theme:ApplyBackdrop(frame, bgColor, borderColor, followAlpha)
    if not frame then return end
    bgColor = bgColor or self.Colors.bgPanel
    borderColor = borderColor or self.Colors.border

    if frame.SetBackdrop and not frame._wishBackdropCleared then
        frame._wishBackdropCleared = true
        frame:SetBackdrop(nil)
    end

    if not frame._wishBgTex then
        local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        bg:SetAllPoints(frame)
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        self:SnapTextureToPixel(bg)
        frame._wishBgTex = bg
    end

    EnsureCrisp1PxBorder(frame)

    frame._wishFollowAlpha = followAlpha and true or false
    if followAlpha then
        self.alphaFrames[frame] = bgColor
    end
    self.trackedFrames[frame] = true

    local alpha = bgColor[4] or 0.92
    if followAlpha and ns.db and ns.db.settings and ns.db.settings.bgAlpha then
        alpha = ns.db.settings.bgAlpha
    end

    frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], alpha)
    frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
    frame:UpdatePixelBorders()
end

function Theme:RefreshAllPixelBorders()
    for frame in pairs(self.trackedFrames) do
        if frame and frame.UpdatePixelBorders then
            frame:UpdatePixelBorders(true)
        end
    end
    if self.RefreshHeaderHubIconMetrics then self:RefreshHeaderHubIconMetrics() end
    if self.RefreshActionIconMetrics then self:RefreshActionIconMetrics() end
    if self.RefreshInlineIconMetrics then self:RefreshInlineIconMetrics() end
    if self.RefreshMinimapIconMetrics then self:RefreshMinimapIconMetrics() end
    -- Keep the dock's gap at two physical pixels when effective scale changes.
    if ns.RefreshActionSidebarLayout then ns:RefreshActionSidebarLayout() end
end

function Theme:UpdateAllFramesAlpha(newAlpha)
    newAlpha = math.max(0.35, math.min(1.0, tonumber(newAlpha) or 0.88))
    if ns.db and ns.db.settings then
        ns.db.settings.bgAlpha = newAlpha
    end
    for frame, baseCol in pairs(self.alphaFrames) do
        if frame and frame.SetBackdropColor and baseCol then
            frame:SetBackdropColor(baseCol[1], baseCol[2], baseCol[3], newAlpha)
        end
    end
end

function Theme:RefreshAllGlassAlpha()
    if ns.db and ns.db.settings and ns.db.settings.bgAlpha then
        self:UpdateAllFramesAlpha(ns.db.settings.bgAlpha)
    end
end

-- ==================== 2. 零闭包多语言字体钩子与常用基础组件 ====================
local function SharedSetTextZhCN(self, text)
    if self._wishLastRaw == text then return end
    self._wishLastRaw = text
    self:_wishOrigSetText(text)
    if self._wishOnTextChanged then self:_wishOnTextChanged() end
end

local function SharedSetTextLocalized(self, text)
    if self._wishLastRaw == text then return end
    self._wishLastRaw = text
    if ns.T and type(text) == "string" and text ~= "" then
        text = ns:T(text)
    end
    self:_wishOrigSetText(text)
    if self._wishOnTextChanged then self:_wishOnTextChanged() end
end

function Theme:HookLocalizedFontString(fs)
    if not fs or fs._wishLocHooked then return end
    fs._wishLocHooked = true
    fs._wishOrigSetText = fs.SetText
    fs.SetText = (ns.locale == "zhCN") and SharedSetTextZhCN or SharedSetTextLocalized
end

function Theme:CreateArrowTexture(parent, size, direction)
    size = size or 12
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetSize(size, size)
    tex:SetTexture(ARROW_TGA_PATH)
    self:SnapTextureToPixel(tex)
    if direction == "UP" then
        tex:SetRotation(math.rad(180))
    elseif direction == "LEFT" then
        tex:SetRotation(math.rad(-90))
    elseif direction == "RIGHT" then
        tex:SetRotation(math.rad(90))
    else
        tex:SetRotation(0)
    end
    return tex
end

local function SharedUpdateChildInset(holder)
    local child = holder._insetChild
    if not child then return end
    local px = Theme:GetPixelScale(holder)
    if holder._lastInsetPx == px then return end
    holder._lastInsetPx = px
    child:ClearAllPoints()
    child:SetPoint("TOPLEFT", holder, "TOPLEFT", px, -px)
    child:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -px, px)
end

function Theme:CreateCroppedIcon(parent, size)
    size = size or 28
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetSize(size, size)
    self:ApplyBackdrop(holder, self.Colors.bgInput, self.Colors.border, false)

    local tex = holder:CreateTexture(nil, "ARTWORK")
    holder._insetChild = tex
    SharedUpdateChildInset(holder)
    holder:HookScript("OnShow", SharedUpdateChildInset)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self:SnapTextureToPixel(tex)
    holder.icon = tex

    return holder
end

function Theme:SetPetTypeDecalTexture(tex, petType)
    if not tex then return end
    local pType = petType or 1
    local pt = self.PetTypes[pType]
    if not pt then
        tex:Hide()
        return
    end

    if cachedRematchLoaded == nil then
        cachedRematchLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Rematch")) and true or false
    end

    if tex._lastPetType == pType and tex._lastRematchMode == cachedRematchLoaded then
        tex:Show()
        return
    end
    tex._lastPetType = pType
    tex._lastRematchMode = cachedRematchLoaded

    tex:SetTexture(pt.icon, "CLAMP", "CLAMP", "LINEAR")
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetVertexColor(1, 1, 1, 0.16)
    tex:Show()
end

-- PetTypes/*.tga 均为 256x256 正方形纹理，保持 1:1 等比尺寸与完整 UV，防止拉伸变形
function Theme:CreateWatermarkPetTypeTex(parent, width, height)
    local size = height or width or 32
    if width and height and width ~= height then
        size = math.min(width, height)
    end
    if parent.SetClipsChildren then
        parent:SetClipsChildren(true)
    end
    local tex = parent:CreateTexture(nil, "BORDER", nil, 1)
    tex:SetSize(size, size)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetVertexColor(1, 1, 1, 0.16)
    self:SnapTextureToPixel(tex)
    return tex
end

local TRANSPARENT_COLOR = { 0, 0, 0, 0 }
local LINK_MUTED = { 0.62, 0.72, 0.84, 1 }
local LINK_PRIMARY = { 0.22, 0.78, 0.98, 1 }
local LINK_DANGER = { 0.96, 0.38, 0.42, 1 }
local LINK_WARNING = { 0.98, 0.72, 0.22, 1 }
local LINK_HOVER = { 0.96, 0.99, 1.00, 1 }

local HOME_CYAN = { 0.10, 0.87, 1.00, 1 }

local SYMBOL_ONLY_TEXTS = {
    ["×"] = true, ["+"] = true, ["−"] = true, ["-"] = true,
    ["✓"] = true, ["···"] = true, ["‹"] = true, ["›"] = true,
}

function Theme:IsIconOrSymbolOnlyText(rawText)
    if not rawText or rawText == "" then return true end
    local clean = string.gsub(tostring(rawText), "|c%x%x%x%x%x%x%x%x", "")
    clean = string.gsub(clean, "|r", "")
    clean = strtrim(clean)
    return clean == "" or SYMBOL_ONLY_TEXTS[clean] == true
end

local function ShouldSuppressFlatUnderline(btn)
    if not btn or btn._actionIconOnly or btn._noUnderline then
        return true
    end
    if not btn.text or not btn.text:IsShown() then
        return true
    end
    return Theme:IsIconOrSymbolOnlyText(btn.text:GetText())
end

-- Text-only links keep their 3-unit gap. Icon links clear the taller of the
-- centered label/icon by at least 4 units, including the one-pixel press travel.
function Theme:AnchorStandardUnderline(underline, ownerFrame, fontString, align, leftExtend)
    if not underline or not ownerFrame or not fontString then return end
    local px = self:GetPixelScale(ownerFrame)
    underline:SetHeight(px)
    self:SnapTextureToPixel(underline)
    local maxW = math.max(10, (ownerFrame:GetWidth() or 80) - 2)
    local tw = fontString:GetStringWidth() or 0
    local ext = leftExtend or 0
    local icon = ext > 0 and (ownerFrame.actionIcon or ownerFrame.icon)
    local gap = 3
    if icon then
        local textHeight = fontString:GetHeight() or 0
        local iconHeight = icon:GetHeight() or 0
        local pressTravel = ownerFrame.actionIcon and px or 0
        gap = math.ceil((4 + math.max(0, (iconHeight - textHeight) * 0.5) + pressTravel) / px) * px
    end
    local totalW = math.max(10, math.min(maxW, tw + ext))
    local effAlign = align or fontString:GetJustifyH() or "LEFT"
    underline:ClearAllPoints()
    if effAlign == "RIGHT" then
        underline:SetPoint("TOPRIGHT", fontString, "BOTTOMRIGHT", 0, -gap)
    elseif effAlign == "CENTER" then
        underline:SetPoint("TOP", fontString, "BOTTOM", -ext * 0.5, -gap)
    else
        underline:SetPoint("TOPLEFT", fontString, "BOTTOMLEFT", -ext, -gap)
    end
    underline:SetWidth(totalW)
end

local function UpdateFlatButtonUnderlineWidth(btn)
    if not btn.underline or not btn.text then return end
    if ShouldSuppressFlatUnderline(btn) then
        btn.underline:Hide()
        return
    end
    local align = btn._textAlign or btn.text:GetJustifyH() or "CENTER"
    local ext = (btn.actionIcon and not btn._actionIconOnly) and ((btn.actionIcon:GetWidth() or 14) + 4) or 0
    Theme:AnchorStandardUnderline(btn.underline, btn, btn.text, align, ext)
end

local function SharedFlatBtnSetSelected(self, isSel)
    local targetSel = isSel and true or false
    if self.isSelected == targetSel then return end
    self.isSelected = targetSel
    if self.underline then
        UpdateFlatButtonUnderlineWidth(self)
        self.underline:SetShown(targetSel and not ShouldSuppressFlatUnderline(self))
    end
    if targetSel then
        self.text:SetTextColor(unpack(LINK_HOVER))
    else
        self.text:SetTextColor(unpack(self._textColor or LINK_MUTED))
    end
end

local function SharedFlatBtnOnEnter(self)
    self.text:SetTextColor(unpack(LINK_HOVER))
    if self.underline then
        UpdateFlatButtonUnderlineWidth(self)
        if not ShouldSuppressFlatUnderline(self) then
            self.underline:Show()
        else
            self.underline:Hide()
        end
    end
end

local function SharedFlatBtnOnLeave(self)
    if not self.isSelected then
        self.text:SetTextColor(unpack(self._textColor or LINK_MUTED))
        if self.underline then self.underline:Hide() end
    else
        self.text:SetTextColor(unpack(LINK_HOVER))
        if self.underline then
            if not ShouldSuppressFlatUnderline(self) then
                self.underline:Show()
            else
                self.underline:Hide()
            end
        end
    end
end

local function SharedFlatBtnSetTextAlign(self, align)
    align = align or "CENTER"
    self._textAlign = align
    if not self.text then return end
    self.text:ClearAllPoints()
    if align == "LEFT" then
        self.text:SetPoint("LEFT", 0, 0)
        self.text:SetPoint("RIGHT", 0, 0)
        self.text:SetJustifyH("LEFT")
    elseif align == "RIGHT" then
        self.text:SetPoint("LEFT", 0, 0)
        self.text:SetPoint("RIGHT", 0, 0)
        self.text:SetJustifyH("RIGHT")
    else
        self.text:SetPoint("CENTER", 0, 0)
        self.text:SetJustifyH("CENTER")
    end
    UpdateFlatButtonUnderlineWidth(self)
end

function Theme:CreateFlatButton(parent, width, height, text, style, align)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 90, height or 26)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local txtCol = LINK_MUTED
    if style == "PRIMARY" then
        txtCol = LINK_PRIMARY
    elseif style == "DANGER" then
        txtCol = LINK_DANGER
    elseif style == "WARNING" then
        txtCol = LINK_WARNING
    end

    btn._baseBg = TRANSPARENT_COLOR
    btn._hovBg  = TRANSPARENT_COLOR
    btn._baseBd = TRANSPARENT_COLOR
    btn._hovBd  = TRANSPARENT_COLOR
    btn._textColor = txtCol
    btn._textAlign = align or "CENTER"

    self:ApplyBackdrop(btn, TRANSPARENT_COLOR, TRANSPARENT_COLOR, false)

    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self:HookLocalizedFontString(fs)
    fs:SetText(text or "")
    fs:SetTextColor(unpack(txtCol))
    btn.text = fs

    local ul = btn:CreateTexture(nil, "ARTWORK")
    ul:SetTexture("Interface\\Buttons\\WHITE8X8")
    ul:SetVertexColor(HOME_CYAN[1], HOME_CYAN[2], HOME_CYAN[3], 1)
    ul:SetHeight(1)
    ul:Hide()
    btn.underline = ul
    btn._UpdateUnderline = UpdateFlatButtonUnderlineWidth
    btn.SetTextAlign = SharedFlatBtnSetTextAlign
    btn:SetTextAlign(align or "CENTER")

    fs._wishOnTextChanged = function()
        if ul:IsShown() then UpdateFlatButtonUnderlineWidth(btn) end
    end

    btn.SetSelected = SharedFlatBtnSetSelected
    btn:SetScript("OnEnter", SharedFlatBtnOnEnter)
    btn:SetScript("OnLeave", SharedFlatBtnOnLeave)

    return btn
end

local function SharedEditBoxFocusGained(self)
    if self._isFramelessSearch then
        self:SetBackdropColor(0, 0, 0, 0)
        self:SetBackdropBorderColor(0, 0, 0, 0)
        if self.searchUnderline then
            self.searchUnderline:SetVertexColor(0.00, 0.92, 1.00, 1.0)
            self.searchUnderline:Show()
        end
    else
        self:SetBackdropBorderColor(unpack(Theme.Colors.borderBlue))
    end
    if self.placeholder then self.placeholder:Hide() end
end

local function SharedEditBoxFocusLost(self)
    if self._isFramelessSearch then
        self:SetBackdropColor(0, 0, 0, 0)
        self:SetBackdropBorderColor(0, 0, 0, 0)
        if self.searchUnderline then
            if self:IsMouseOver() then
                self.searchUnderline:SetVertexColor(0.22, 0.88, 1.00, 0.95)
                self.searchUnderline:Show()
            else
                self.searchUnderline:Hide()
            end
        end
    else
        self:SetBackdropBorderColor(unpack(Theme.Colors.border))
    end
    if self.placeholder and (self:GetText() or "") == "" then
        self.placeholder:Show()
    end
end

local function SharedEditBoxTextChanged(self)
    if not self.placeholder then return end
    if (self:GetText() or "") ~= "" or self:HasFocus() then
        self.placeholder:Hide()
    else
        self.placeholder:Show()
    end
end

local function SharedEditBoxEscape(self)
    self:ClearFocus()
end

function Theme:CreateFlatEditBox(parent, width, height, placeholderText)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width or 180, height or 26)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetTextInsets(8, 8, 0, 0)
    self:ApplyBackdrop(box, self.Colors.bgInput, self.Colors.border, false)

    local ph = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    ph:SetPoint("LEFT", 8, 0)
    ph:SetPoint("RIGHT", -8, 0)
    ph:SetJustifyH("LEFT")
    ph:SetWordWrap(false)
    self:HookLocalizedFontString(ph)
    ph:SetText(placeholderText or "")
    box.placeholder = ph

    box:HookScript("OnEditFocusGained", SharedEditBoxFocusGained)
    box:HookScript("OnEditFocusLost", SharedEditBoxFocusLost)
    box:HookScript("OnTextChanged", SharedEditBoxTextChanged)
    box:SetScript("OnEscapePressed", SharedEditBoxEscape)

    return box
end

-- 搜索框专属无框体样式：默认无边框线，仅在鼠标悬停或点击激活时显示底部青色下划线
function Theme:StyleSearchBox(box)
    if not box or box._isFramelessSearch then return end
    box._isFramelessSearch = true
    self:ApplyBackdrop(box, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, false)
    box:SetBackdropColor(0, 0, 0, 0)
    box:SetBackdropBorderColor(0, 0, 0, 0)
    if box._wishBorderHolder then box._wishBorderHolder:Hide() end
    if box._wishBgTex then box._wishBgTex:Hide() end
    box.UpdatePixelBorders = function(self)
        if self._wishBorderHolder then self._wishBorderHolder:Hide() end
        if self._wishBgTex then self._wishBgTex:Hide() end
    end

    local ul = box:CreateTexture(nil, "OVERLAY")
    ul:SetTexture("Interface\\Buttons\\WHITE8X8")
    ul:SetVertexColor(0.22, 0.88, 1.00, 0.95)
    ul:SetHeight(self:GetPixelScale(box))
    self:SnapTextureToPixel(ul)
    ul:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 2, 0)
    ul:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 0)
    ul:Hide()
    box.searchUnderline = ul

    box:HookScript("OnEnter", function(self)
        self:SetBackdropColor(0, 0, 0, 0)
        self:SetBackdropBorderColor(0, 0, 0, 0)
        if self.searchUnderline then
            if self:HasFocus() then
                self.searchUnderline:SetVertexColor(0.00, 0.92, 1.00, 1.0)
            else
                self.searchUnderline:SetVertexColor(0.22, 0.88, 1.00, 0.95)
            end
            self.searchUnderline:Show()
        end
    end)
    box:HookScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0)
        self:SetBackdropBorderColor(0, 0, 0, 0)
        if self.searchUnderline then
            if self:HasFocus() then
                self.searchUnderline:SetVertexColor(0.00, 0.92, 1.00, 1.0)
                self.searchUnderline:Show()
            else
                self.searchUnderline:Hide()
            end
        end
    end)
    box:HookScript("OnEditFocusGained", function(self)
        self:SetBackdropColor(0, 0, 0, 0)
        self:SetBackdropBorderColor(0, 0, 0, 0)
        if self.searchUnderline then
            self.searchUnderline:SetVertexColor(0.00, 0.92, 1.00, 1.0)
            self.searchUnderline:Show()
        end
    end)
    box:HookScript("OnEditFocusLost", function(self)
        self:SetBackdropColor(0, 0, 0, 0)
        self:SetBackdropBorderColor(0, 0, 0, 0)
        if self.searchUnderline then
            if self:IsMouseOver() then
                self.searchUnderline:SetVertexColor(0.22, 0.88, 1.00, 0.95)
                self.searchUnderline:Show()
            else
                self.searchUnderline:Hide()
            end
        end
    end)
end

-- Opt in for search fields only; ordinary name/ID editors keep their layout.
function Theme:EnableSearchClearButton(box, onClear)
    self:StyleSearchBox(box)
    if box.searchClearButton then
        box.searchClearButton.onClear = onClear or box.searchClearButton.onClear
        return box.searchClearButton
    end
    local button = CreateFrame("Button", nil, box)
    button:SetSize(18, 18)
    button:SetPoint("RIGHT", -3, 0)
    button:SetFrameLevel(box:GetFrameLevel() + 2)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")
    button.onClear = onClear
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER", 0, 0)
    label:SetText("×")
    label:SetTextColor(0.65, 0.70, 0.78, 1)
    button:SetScript("OnEnter", function() label:SetTextColor(1, 1, 1, 1) end)
    button:SetScript("OnLeave", function() label:SetTextColor(0.65, 0.70, 0.78, 1) end)
    button:SetScript("OnClick", function()
        box._clearingSearch = true
        box:SetText("")
        box._clearingSearch = nil
        if button.onClear then button.onClear() end
        button:Hide()
        box:SetFocus()
    end)
    box:SetTextInsets(8, 26, 0, 0)
    local function UpdateVisibility()
        button:SetShown((box:GetText() or "") ~= "")
    end
    box:HookScript("OnTextChanged", UpdateVisibility)
    box.searchClearButton = button
    UpdateVisibility()
    return button
end

-- 菜单行与列表行统一使用底部青色下划线交互，不显示矩形悬浮框体
local function UpdateMenuRowUnderlineWidth(row)
    if not row or not row.underline or not row.text then return end
    local raw = row.text:GetText()
    if not raw or raw == "" then
        row.underline:Hide()
        return
    end
    local align = row.text:GetJustifyH() or "LEFT"
    Theme:AnchorStandardUnderline(row.underline, row, row.text, align, 0)
end

local function SharedMenuRowSetSelected(self, isSel)
    local targetSel = isSel and true or false
    self.isSelected = targetSel
    self:SetBackdropColor(0, 0, 0, 0)
    self:SetBackdropBorderColor(0, 0, 0, 0)
    if self.underline then
        UpdateMenuRowUnderlineWidth(self)
        self.underline:SetShown(targetSel or self._isHovered == true)
    end
end

local function SharedMenuRowOnEnter(self)
    self._isHovered = true
    self:SetBackdropColor(0, 0, 0, 0)
    self:SetBackdropBorderColor(0, 0, 0, 0)
    if self.underline then
        UpdateMenuRowUnderlineWidth(self)
        self.underline:Show()
    end
end

local function SharedMenuRowOnLeave(self)
    self._isHovered = false
    self:SetBackdropColor(0, 0, 0, 0)
    self:SetBackdropBorderColor(0, 0, 0, 0)
    if self.underline then
        if self.isSelected then
            UpdateMenuRowUnderlineWidth(self)
            self.underline:Show()
        else
            self.underline:Hide()
        end
    end
end

function Theme:CreateMenuRow(parent, width, height, labelText)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(width or 180, height or 24)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    self:ApplyBackdrop(row, MENU_ROW_BG, MENU_ROW_BD, false)

    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", 8, 0)
    fs:SetPoint("RIGHT", -8, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    self:HookLocalizedFontString(fs)
    fs:SetText(labelText or "")
    row.text = fs

    local ul = row:CreateTexture(nil, "ARTWORK")
    ul:SetTexture("Interface\\Buttons\\WHITE8X8")
    ul:SetVertexColor(HOME_CYAN[1], HOME_CYAN[2], HOME_CYAN[3], 1)
    ul:SetHeight(1)
    ul:SetPoint("BOTTOMLEFT", fs, "BOTTOMLEFT", 0, -2)
    ul:SetWidth(math.max(12, fs:GetStringWidth() or 24))
    ul:Hide()
    row.underline = ul
    row._UpdateUnderline = UpdateMenuRowUnderlineWidth

    fs._wishOnTextChanged = function()
        if ul:IsShown() and row._UpdateUnderline then row:_UpdateUnderline() end
    end

    row.SetSelected = SharedMenuRowSetSelected
    row:SetScript("OnEnter", SharedMenuRowOnEnter)
    row:SetScript("OnLeave", SharedMenuRowOnLeave)

    return row
end

function Theme:CreateFlatBar(parent, width, height, r, g, b)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetSize(width or 120, height or 14)
    self:ApplyBackdrop(holder, self.Colors.bgInput, self.Colors.border, false)

    local bar = CreateFrame("StatusBar", nil, holder)
    holder._insetChild = bar
    SharedUpdateChildInset(holder)
    holder:HookScript("OnShow", SharedUpdateChildInset)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetStatusBarColor(r or 0.10, g or 0.75, b or 0.45, 0.95)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(100)
    holder.bar = bar

    local txt = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("CENTER", 0, 0)
    self:HookLocalizedFontString(txt)
    holder.text = txt

    return holder
end

local function SharedToggleSetState(self, isOn)
    local target = isOn and true or false
    if self._initialized and self.isOn == target then return end
    self._initialized = true
    self.isOn = target
    local track = self._track
    local knob = self._knob
    knob:ClearAllPoints()
    if target then
        track:SetBackdropColor(0.06, 0.48, 0.34, 1)
        track:SetBackdropBorderColor(unpack(Theme.Colors.borderGreen))
        knob:SetBackdropColor(0.10, 0.85, 0.58, 1)
        knob:SetPoint("RIGHT", track, "RIGHT", -2, 0)
    else
        track:SetBackdropColor(unpack(Theme.Colors.bgInput))
        track:SetBackdropBorderColor(unpack(Theme.Colors.border))
        knob:SetBackdropColor(unpack(TOGGLE_KNOB_COLOR))
        knob:SetPoint("LEFT", track, "LEFT", 2, 0)
    end
end

function Theme:CreateToggleSwitch(parent, labelText, width, compact)
    local holder = CreateFrame("Button", nil, parent)
    holder:SetSize(width or (compact and 482 or 212), compact and 24 or 26)
    holder:EnableMouse(true)
    holder:RegisterForClicks("AnyUp")

    local px = self:GetPixelScale()
    local line = holder:CreateTexture(nil, "BORDER")
    line:SetHeight(px)
    if compact then
        line:SetPoint("BOTTOMLEFT", 0, -2)
        line:SetPoint("BOTTOMRIGHT", 0, -2)
    else
        line:SetPoint("BOTTOMLEFT", 2, 0)
        line:SetPoint("BOTTOMRIGHT", -2, 0)
    end
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetVertexColor(unpack(self.Colors.divider))
    holder.dividerLine = line

    local lbl = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", compact and 2 or 4, compact and 1 or 0)
    self:HookLocalizedFontString(lbl)
    lbl:SetText(labelText or "")
    holder.label = lbl

    local track = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    track:SetSize(compact and 38 or 40, compact and 16 or 18)
    track:SetPoint("RIGHT", compact and -2 or -4, compact and 1 or 0)
    track:EnableMouse(false)
    self:ApplyBackdrop(track, self.Colors.bgInput, self.Colors.border, false)

    local knob = CreateFrame("Frame", nil, track, "BackdropTemplate")
    knob:SetSize(compact and 14 or 16, compact and 12 or 14)
    knob:EnableMouse(false)
    self:ApplyBackdrop(knob, TOGGLE_KNOB_COLOR, self.Colors.border, false)

    holder._track = track
    holder._knob  = knob
    holder.SetState = SharedToggleSetState
    holder:SetState(false)

    return holder
end

-- A dedicated title grip keeps dialogs draggable even when their body is full of controls.
function Theme:EnableDialogDrag(frame)
    if frame.dialogDragGrip then return end
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    local grip = CreateFrame("Frame", nil, frame)
    grip:SetPoint("TOPLEFT", 0, 0)
    grip:SetPoint("TOPRIGHT", -48, 0)
    grip:SetHeight(32)
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function() frame:StartMoving() end)
    grip:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    frame:HookScript("OnHide", function() frame:StopMovingOrSizing() end)
    frame.dialogDragGrip = grip
end
