local ADDON_NAME, ns = ...
local Theme = ns.Theme
local ICON_ROOT = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\Header\\"
local BUTTON_KEYS = { "petHubBtn", "teamHubBtn", "routeHubBtn", "scriptHubBtn", "displaySettingsBtn", "updateGuideBtn", "viewModeToggle", "closeBtn", "sidebarAllPetsBtn", "sidebarQueueBtn" }
local TRANSPARENT = { 0, 0, 0, 0 }
local CLOSE_ICON_SIZE = 12
local trackedCloseButtons = setmetatable({}, { __mode = "k" })

local function UpdateIconPoint(button)
    local offset = button._hubPressed and button._hubPixel or 0
    button.icon:ClearAllPoints()
    button.icon:SetPoint("CENTER", button, "CENTER", offset, -offset)
end

local function RefreshIconMetrics(button)
    local size, px = Theme:GetButtonIconSize(button, button._hubIconSize or 32)
    button._hubPixel = px
    button.icon:SetSize(size, size)
    UpdateIconPoint(button)
end

local function RefreshIconState(button)
    local isOpen
    if button._hubIsOpenFunc then
        isOpen = button._hubIsOpenFunc()
    else
        local panel = button._hubPanelKey and ns[button._hubPanelKey]
        isOpen = panel and panel:IsShown() or false
    end
    button._isOpen = isOpen
    local visual = button._hubPressed and "pressed"
        or button._hubHovered and "hovered" or isOpen and "open" or "normal"
    if button._hubVisual == visual then return end
    button._hubVisual = visual
    local r, g, b = button._hubR, button._hubG, button._hubB
    button:SetBackdropColor(0, 0, 0, 0)
    button:SetBackdropBorderColor(0, 0, 0, 0)
    if button._hubPressed then
        button.icon:SetVertexColor(r, g, b, 1)
        button.icon:SetAlpha(0.92)
    elseif button._hubHovered or isOpen then
        button.icon:SetVertexColor(r, g, b, 1)
        button.icon:SetAlpha(1)
    else
        button.icon:SetVertexColor(1, 1, 1, 1)
        button.icon:SetAlpha(0.92)
    end
end

local function HideIconTooltip(button)
    if ns.HideCustomTooltip then ns:HideCustomTooltip(button) end
end

local function IconOnEnter(button)
    button._hubHovered = true
    RefreshIconState(button)
    if ns.ShowCustomTooltip then
        local title = button._hubTooltip and button._hubTooltip() or ns:T(button._hubTitle)
        ns:ShowCustomTooltip(button, button._hubTooltipAnchor or "ANCHOR_BOTTOM", title)
    end
end

local function IconOnLeave(button)
    button._hubHovered = false
    button._hubPressed = false
    UpdateIconPoint(button)
    RefreshIconState(button)
    HideIconTooltip(button)
end

local function IconOnMouseDown(button, mouseButton)
    if mouseButton ~= "LeftButton" then return end
    button._hubPressed = true
    UpdateIconPoint(button)
    RefreshIconState(button)
end

local function IconOnMouseUp(button)
    button._hubPressed = false
    UpdateIconPoint(button)
    RefreshIconState(button)
end

local function IconOnShow(button)
    RefreshIconMetrics(button)
    RefreshIconState(button)
end

function Theme:CreateHeaderHubIcon(parent, asset, title, panelKey, r, g, b, iconSize)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button._hubIconSize = iconSize or 32
    button:SetSize(button._hubIconSize, button._hubIconSize)
    button:RegisterForClicks("LeftButtonUp")
    button._hubPanelKey = panelKey
    button._hubTitle = title
    button._hubR, button._hubG, button._hubB = r, g, b
    self:ApplyBackdrop(button, TRANSPARENT, TRANSPARENT, false)
    local icon = button:CreateTexture(nil, "ARTWORK")
    self:ConfigureButtonIcon(icon, ICON_ROOT .. asset .. ".tga")
    button.icon = icon
    button.RefreshHubIconState = RefreshIconState
    button:SetScript("OnEnter", IconOnEnter)
    button:SetScript("OnLeave", IconOnLeave)
    button:SetScript("OnMouseDown", IconOnMouseDown)
    button:SetScript("OnMouseUp", IconOnMouseUp)
    button:SetScript("OnHide", IconOnLeave)
    button:SetScript("OnShow", IconOnShow)
    button:SetScript("OnSizeChanged", RefreshIconMetrics)
    IconOnShow(button)
    return button
end

function Theme:CreateCloseIconButton(parent, onClick, tooltipText)
    local button = self:CreateHeaderHubIcon(parent, "close", tooltipText or "关闭", nil, 1.0, 0.39, 0.43, CLOSE_ICON_SIZE)
    button:SetHitRectInsets(-4, -4, -4, -4)
    trackedCloseButtons[button] = true
    if onClick then
        button:SetScript("OnClick", onClick)
    end
    return button
end

function Theme:RefreshHeaderHubIconMetrics()
    local main = ns.MainFrame
    if main then
        for i = 1, #BUTTON_KEYS do
            local button = main[BUTTON_KEYS[i]]
            if button then RefreshIconMetrics(button) end
        end
    end
    for button in pairs(trackedCloseButtons) do
        if button then RefreshIconMetrics(button) end
    end
end

function ns:RefreshHeaderHubIconStates()
    local main = self.MainFrame
    if not main then return end
    for i = 1, #BUTTON_KEYS do
        local button = main[BUTTON_KEYS[i]]
        if button then RefreshIconState(button) end
    end
end

-- Native single-shot alpha animation. Created with its panel and reused forever.
-- No SetAlpha override: on finish/stop the region returns to its underlying alpha.
local function HeaderPanelOnShow(panel)
    ns:RefreshHeaderHubIconStates()
    local fade = panel._wishHubFade
    fade:Stop()
    local targetAlpha = panel:GetAlpha()
    panel._wishHubFadeAlpha:SetFromAlpha(targetAlpha * 0.25)
    panel._wishHubFadeAlpha:SetToAlpha(targetAlpha)
    fade:Play()
end

local function HeaderPanelOnHide(panel)
    panel._wishHubFade:Stop()
    ns:RefreshHeaderHubIconStates()
end

function ns:BindHeaderHubPanel(panel)
    if panel._wishHubFade then return end
    local fade = panel:CreateAnimationGroup()
    local alpha = fade:CreateAnimation("Alpha")
    alpha:SetDuration(0.12)
    alpha:SetSmoothing("OUT")
    panel._wishHubFade = fade
    panel._wishHubFadeAlpha = alpha
    panel:HookScript("OnShow", HeaderPanelOnShow)
    panel:HookScript("OnHide", HeaderPanelOnHide)
end
