local ADDON_NAME, ns = ...
local Theme = ns.Theme
local TEXTURE_ROOT = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\Textures\\PetTypes\\"
-- WoW family IDs, independent of localized names and the external Rematch atlas.
local LIST_ICON_ALPHA = 0.20
local FAMILY_ASSETS = {
    "Humanoid", "Dragonkin", "Flying", "Undead", "Critter",
    "Magic", "Elemental", "Beast", "Aquatic", "Mechanical",
}

function Theme:GetPetTypeTexturePath(family)
    local asset = FAMILY_ASSETS[family or 1]
    return asset and (TEXTURE_ROOT .. asset .. ".tga") or nil
end

function Theme:CreatePetListTypeTexture(parent, size)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    texture:SetSize(size or 48, size or 48)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetVertexColor(1, 1, 1, LIST_ICON_ALPHA)
    self:SnapTextureToPixel(texture)
    return texture
end

function Theme:SetPetListTypeTexture(texture, family)
    if not texture then return end
    family = family or 1
    local asset = FAMILY_ASSETS[family]
    if not asset then
        texture._wishListFamily = nil
        texture:Hide()
        return
    end
    if texture._wishListFamily ~= family then
        texture:SetTexture(TEXTURE_ROOT .. asset .. ".tga", "CLAMP", "CLAMP", "LINEAR")
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetVertexColor(1, 1, 1, LIST_ICON_ALPHA)
        texture._wishListFamily = family
    end
    texture:Show()
end
