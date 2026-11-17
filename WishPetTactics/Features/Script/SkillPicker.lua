local ADDON_NAME, ns = ...
local Theme = ns.Theme
local function L(cn,tw,en)
    return ns.locale == "zhTW" and tw or ns.locale ~= "zhCN" and en or cn
end

function ns:CreateScriptSkillPicker(parent, accept, refocus)
    local picker = CreateFrame("Frame", nil, parent)
    picker:SetAllPoints()
    picker:EnableMouse(true)
    picker.slotIndex, picker.variantIndex, picker.column = 1, 1, 1
    picker.slots, picker.variants = {}, {}
    local widths, starts = {104, 238, 284}, {4, 112, 354}
    local titles = {
        L("技能槽位", "技能槽位", "Skill slot"),
        L("名称 / ID 写法", "名稱 / ID 寫法", "Name / ID forms"),
        L("插入预览", "插入預覽", "Insert preview"),
    }
    local panels = {}
    for i=1,3 do
        local panel = CreateFrame("Frame", nil, picker, "BackdropTemplate")
        panel:SetSize(widths[i], 148)
        panel:SetPoint("TOPLEFT", starts[i], -4)
        Theme:ApplyBackdrop(panel, {0.067,0.067,0.067,0.98}, Theme.Colors.border, false)
        local title = panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        title:SetPoint("TOPLEFT",8,-9)
        title:SetText(titles[i])
        panels[i] = panel
    end
    local preview = panels[3]:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    preview:SetPoint("TOPLEFT",10,-32)
    preview:SetPoint("TOPRIGHT",-10,-32)
    preview:SetJustifyH("LEFT")
    preview:SetWordWrap(true)
    picker.preview = preview
    local insert = Theme:CreateActionButton(panels[3], 264, 24, L("插入所选写法","插入所選寫法","Insert selected form"), "insert", nil, "PRIMARY")
    insert:SetPoint("BOTTOM",0,8)
    insert:SetScript("OnClick", function() accept() end)
    local hint = picker:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT",10,9)
    hint:SetText(L("↑↓ 选择  ·  ←→ 切换栏  ·  Tab / Enter 插入", "↑↓ 選擇  ·  ←→ 切換欄  ·  Tab / Enter 插入", "Up/Down select  ·  Left/Right column  ·  Tab/Enter insert"))

    function picker:GetSelectedItem()
        local skill=self.model and self.model.skills[self.slotIndex]
        return skill and skill.variants[self.variantIndex]
    end
    function picker:Refresh()
        local skill=self.model and self.model.skills[self.slotIndex]
        for i,row in ipairs(self.slots) do
            local entry=self.model and self.model.skills[i]
            row:SetShown(entry~=nil)
            if entry then
                row.text:SetText(L("技能 ","技能 ","Skill ")..entry.idx)
                row:SetSelected(i==self.slotIndex)
            end
        end
        for i,row in ipairs(self.variants) do
            local item=skill and skill.variants[i]
            row:SetShown(item~=nil)
            if item then
                row.text:SetText(item.desc)
                row:SetSelected(i==self.variantIndex)
            end
        end
        local item=self:GetSelectedItem()
        local info=skill and ((skill.name or L("技能信息未载入","技能資訊未載入","Skill details unavailable"))..(skill.id and (" · ID "..skill.id) or "")) or ""
        if skill and skill.usable~=nil then
            info=info.."\n"..(skill.usable and L("当前可用","目前可用","Usable now") or L("当前不可用","目前不可用","Not usable now"))
        end
        if skill and type(skill.cd)=="number" then info=info.." · CD "..skill.cd end
        preview:SetText(info.."\n\n|cff10b981"..(item and item.insertText or "").."|r")
        for i,panel in ipairs(panels) do
            panel:SetBackdropBorderColor(unpack(i==self.column and {0.58,0.32,0.96,1} or Theme.Colors.border))
        end
    end
    function picker:SetModel(model)
        local old=self.model
        local selected=old and old.skills[self.slotIndex]
        local selectedID=selected and selected.idx
        self.model=model
        if not old or old.key~=model.key then
            self.slotIndex,self.variantIndex,self.column=1,1,1
        else
            self.slotIndex=1
            for i,entry in ipairs(model.skills) do if entry.idx==selectedID then self.slotIndex=i;break end end
        end
        self.variantIndex=math.min(self.variantIndex,#model.skills[self.slotIndex].variants)
        self:Refresh()
    end
    function picker:Move(delta)
        if not self.model then return end
        if self.column==1 then
            self.slotIndex=(self.slotIndex-1+delta)%#self.model.skills+1
            self.variantIndex=1
        else
            local count=#self.model.skills[self.slotIndex].variants
            self.variantIndex=(self.variantIndex-1+delta)%count+1
        end
        self:Refresh()
    end
    function picker:ChangeColumn(delta)
        self.column=math.max(1,math.min(3,self.column+delta))
        self:Refresh()
    end
    for i=1,3 do
        local index=i
        local row=Theme:CreateMenuRow(panels[1],96,26,"")
        row:SetPoint("TOPLEFT",4,-28-(i-1)*30)
        row:SetScript("OnClick",function()
            picker.slotIndex,picker.variantIndex,picker.column=index,1,2
            picker:Refresh()
            if refocus then refocus() end
        end)
        picker.slots[i]=row
        local variant=Theme:CreateMenuRow(panels[2],230,26,"")
        variant:SetPoint("TOPLEFT",4,-28-(i-1)*30)
        variant.text:SetWordWrap(false)
        variant.text:SetPoint("RIGHT",-8,0)
        variant:SetScript("OnClick",function()
            picker.variantIndex,picker.column=index,2
            picker:Refresh()
            if refocus then refocus() end
        end)
        picker.variants[i]=variant
    end
    picker:EnableMouseWheel(true)
    picker:SetScript("OnMouseWheel",function(_,delta) if delta~=0 then picker:Move(delta>0 and -1 or 1) end end)
    picker:Hide()
    return picker
end
