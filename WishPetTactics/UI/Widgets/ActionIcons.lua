local ADDON_NAME, ns = ...
local Theme = ns.Theme
local floor = math.floor
local ACTION_ROOT = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Actions\\"
local buttons = setmetatable({}, { __mode = "k" })
local inlineButtons = setmetatable({}, { __mode = "k" })

-- The separate dock is 80% of the V15 sidebar; it does not widen the roster.
Theme.ActionSidebar = { iconSize = 32, width = 44.8, gap = 3.2, padding = 6.4, sectionGap = 6.4, dockGapPixels = 2, toggleSize = 16 }

-- The bundled action/header artwork has at least 10 transparent pixels on
-- each edge. Trim only 8 so the antialiased edges and sparkles stay intact.
function Theme:ConfigureButtonIcon(icon, texture)
    icon:SetTexture(texture, "CLAMP", "CLAMP", "LINEAR")
    icon:SetTexCoord(8 / 128, 120 / 128, 8 / 128, 120 / 128)
    self:SnapTextureToPixel(icon)
end

function Theme:GetButtonIconSize(button, preferred, padding)
    local px = self:GetPixelScale(button)
    local available = math.max(px, math.min(button:GetWidth(), button:GetHeight()) - (padding or 0))
    local desired = math.min(preferred or 28, available)
    local size = math.max(px, math.min(floor(desired / px + 0.5), floor(available / px)) * px)
    return size, px
end

-- Link buttons also resize after creation (drawers and full/minimal mode).
-- Refresh their texture and label together, including when UI scale changes.
local function RefreshInlineMetrics(button)
    button._refreshInlineIcon(button)
end

function Theme:RegisterInlineIconMetrics(button, refresh)
    button._refreshInlineIcon = refresh
    inlineButtons[button] = true
    button:HookScript("OnShow", RefreshInlineMetrics)
    button:HookScript("OnSizeChanged", RefreshInlineMetrics)
    RefreshInlineMetrics(button)
end

function Theme:RefreshInlineIconMetrics()
    for button in pairs(inlineButtons) do RefreshInlineMetrics(button) end
end

function Theme:LayoutLinkIcon(button, align)
    local icon, text = button.icon, button.text
    local size = self:GetButtonIconSize(button, 26)
    icon:SetSize(size, size)
    icon:ClearAllPoints()
    text:ClearAllPoints()
    text:SetWidth(0)
    if align == "LEFT" then
        icon:SetPoint("LEFT", button, "LEFT", 1, 0)
        text:SetPoint("LEFT", button, "LEFT", size + 5, 0)
        text:SetPoint("RIGHT", button, "RIGHT", -1, 0)
    else
        text:SetWidth(math.min(text:GetStringWidth() or 0, math.max(1, button:GetWidth() - size - 6)))
        if align == "RIGHT" then
            text:SetPoint("RIGHT", button, "RIGHT", -1, 0)
        else
            text:SetPoint("CENTER", button, "CENTER", (size + 4) * 0.5, 0)
        end
        icon:SetPoint("RIGHT", text, "LEFT", -4, 0)
    end
end

local function PositionActionIcon(button)
    local icon = button.actionIcon
    local px = button._actionPx or 1
    local shift = button._actionPressed and px or 0
    icon:ClearAllPoints()
    if button._actionIconOnly then
        icon:SetPoint("CENTER", button, "CENTER", shift, -shift)
    else
        icon:SetPoint("RIGHT", button.text, "LEFT", -4 + shift, -shift)
    end
end

local function RefreshActionMetrics(button)
    local size, px = Theme:GetButtonIconSize(button, 28)
    local inset = floor(4 / px + 0.5) * px
    button._actionPx, button._actionInset = px, inset
    button.actionIcon:SetSize(size, size)
    if button._actionIconOnly then
        if button.underline then button.underline:Hide() end
    else
        button.text:ClearAllPoints()
        -- Re-measure after label/locale changes and keep the icon + text group
        -- inside the hit area, including narrow translated buttons.
        button.text:SetWidth(0)
        local textWidth = math.min(button.text:GetStringWidth() or 0,
            math.max(1, button:GetWidth() - size - 8))
        if button._textAlign == "LEFT" then
            local leftInset = button._textLeftInset or 0
            button.text:SetPoint("LEFT", button, "LEFT", leftInset + size + 4, 0)
            button.text:SetPoint("RIGHT", button, "RIGHT", 0, 0)
            button.text:SetJustifyH("LEFT")
        elseif button._textAlign == "RIGHT" then
            button.text:SetWidth(textWidth)
            button.text:SetPoint("RIGHT", button, "RIGHT", -2, 0)
            button.text:SetJustifyH("RIGHT")
        else
            button.text:SetWidth(textWidth)
            button.text:SetPoint("CENTER", button, "CENTER", (size + 4) * 0.5, 0)
            button.text:SetJustifyH("CENTER")
        end
        button.text:SetWordWrap(false)
    end
    PositionActionIcon(button)
    if button._UpdateUnderline then button:_UpdateUnderline() end
end

local function ActionOnEnter(button)
    button.actionIcon:SetAlpha(1)
    if button._actionIconOnly then
        button.actionIcon:SetVertexColor(0.22, 0.88, 1.0, 1)
        if button.underline then button.underline:Hide() end
    end
    if button._actionTooltip and ns.ShowCustomTooltip then
        ns:ShowCustomTooltip(button, "ANCHOR_TOP", ns:T(button._actionTooltip))
    end
end

local function ActionOnLeave(button)
    button._actionPressed = false
    PositionActionIcon(button)
    button.actionIcon:SetAlpha(1)
    if button._actionIconOnly then
        button.actionIcon:SetVertexColor(1, 1, 1, 1)
        if button.underline then button.underline:Hide() end
    end
    if ns.HideCustomTooltip then ns:HideCustomTooltip(button) end
end

local function ActionOnDown(button, mouseButton)
    if mouseButton ~= "LeftButton" then return end
    button._actionPressed = true
    PositionActionIcon(button)
end

local function ActionOnUp(button)
    button._actionPressed = false
    PositionActionIcon(button)
end

local function SetActionMarked(button, marked)
    marked = marked and true or false
    if button._actionMarked == marked then return end
    button._actionMarked = marked
    if not button.actionMark then
        if not marked then return end
        local mark = button:CreateTexture(nil, "OVERLAY")
        mark:SetTexture("Interface\\Buttons\\WHITE8X8")
        mark:SetVertexColor(0.24, 0.88, 0.69, 1)
        mark:SetSize(4, 4)
        mark:SetPoint("TOPRIGHT", -3, -3)
        button.actionMark = mark
    end
    button.actionMark:SetShown(marked)
end

function Theme:AttachActionIcon(button, asset, tooltip, iconOnly)
    if button.actionIcon then return button end
    local icon = button:CreateTexture(nil, "ARTWORK")
    self:ConfigureButtonIcon(icon, ACTION_ROOT .. asset .. ".tga")
    icon:SetAlpha(1)
    button.actionIcon = icon
    button._actionIconOnly = iconOnly and true or false
    button._actionTooltip = tooltip
    button.SetActionMarked = SetActionMarked
    if iconOnly then
        button._noUnderline = true
        button.text:Hide()
        if button.underline then button.underline:Hide() end
    end
    button:HookScript("OnShow", RefreshActionMetrics)
    button:HookScript("OnSizeChanged", RefreshActionMetrics)
    button:HookScript("OnEnter", ActionOnEnter)
    button:HookScript("OnLeave", ActionOnLeave)
    button:HookScript("OnHide", ActionOnLeave)
    button:HookScript("OnMouseDown", ActionOnDown)
    button:HookScript("OnMouseUp", ActionOnUp)
    hooksecurefunc(button.text, "SetText", function() RefreshActionMetrics(button) end)
    hooksecurefunc(button, "SetTextAlign", function() RefreshActionMetrics(button) end)
    buttons[button] = true
    RefreshActionMetrics(button)
    return button
end

function Theme:CreateActionButton(parent, width, height, label, asset, tooltip, style, iconOnly, align)
    local button = self:CreateFlatButton(parent, width, height, label, style, align)
    return self:AttachActionIcon(button, asset, tooltip, iconOnly)
end

function Theme:RefreshActionIconMetrics()
    for button in pairs(buttons) do RefreshActionMetrics(button) end
end

function Theme:RefreshMinimapIconMetrics()
    local button = ns.MinimapButton
    if not button or not button.icon then return end
    local px = self:GetPixelScale(button)
    local size = math.max(px, floor(20 / px + 0.5) * px)
    button.icon:SetSize(size, size)
end
