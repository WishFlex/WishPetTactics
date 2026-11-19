local ADDON_NAME, ns = ...
BINDING_HEADER_WISHPETTACTICS = "Wish Pet Tactics"
BINDING_NAME_WISHPETTACTICS_TOGGLE_TARGETS = ns.locale == "zhCN" and "打开或关闭目标窗口"
    or ns.locale == "zhTW" and "開啟或關閉目標視窗"
    or "Toggle Target Window"
BINDING_NAME_WISHPETTACTICS_TOGGLE_UI_STYLE = ns.locale == "zhCN" and "切换完整界面 / 纵向极简模式"
    or ns.locale == "zhTW" and "切換完整介面 / 縱向極簡模式"
    or "Toggle Full / Vertical Minimal View"

function WishPetTactics_ToggleTargets()
    if not ns.db then return end
    if ns.RoutingModal and ns.RoutingModal:IsVisible() then
        ns.RoutingModal:Hide()
        return
    end
    local main = ns:CreateMainFrame(true)
    ns:ShowRoutingModal(not main:IsVisible())
end

-- Can be called by the native Key Bindings menu even while the UI is closed.
-- Switching presentation never saves or discards the current team draft.
function WishPetTactics_ToggleUIStyle()
    if not ns.db or not ns:ToggleMainUIStyle() then return end
    local main = ns:CreateMainFrame()
    if ns.SyncMainFrameBattleParent then
        ns:SyncMainFrameBattleParent()
    end
    if not main:IsShown() or not main:IsVisible() then
        ns:ShowMainFrame("HOME")
    end
end

local legacyMainCommand = SlashCmdList["WISHREMATCH"]
local HELP = {
    { "/wp", "打开或关闭主界面" },
    { "/wp mode", "切换完整界面和纵向极简模式" },
    { "/wp minimal|full", "切换到指定界面" },
    { "/wp bind-mode", "设置界面切换快捷键" },
    { "/wp teams", "打开队伍管理" },
    { "/wp targets", "打开目标管理" },
    { "/wp pets", "打开宠物列表" },
    { "/wp queue", "打开练级队列" },
    { "/wp script", "打开脚本编辑器" },
    { "/wp updates", "查看更新引导" },
    { "/wp learn on|off", "学习开关（旧命令：/wplearn）" },
    { "/wp gossip on|off", "对话诊断（旧命令：/wpgossip）" },
    { "/wp round", "回合诊断（旧命令：/wpround）" },
    { "/wp bind-dialog", "绑定对话（旧命令：/wpbinddialog）" },
    { "/wp help", "显示命令帮助" },
}

local function ShowCommandHelp()
    print("|cff63ccffWish Pet Tactics — " .. ns:T("命令帮助") .. "|r")
    for i = 1, #HELP do
        print("|cff63ccff" .. HELP[i][1] .. "|r — " .. ns:T(HELP[i][2]))
    end
end

local function OpenPetTab(mode)
    local main = ns:CreateMainFrame()
    main:Show()
    local drawer = ns.PetPickerModal
    if drawer and drawer:IsShown() then
        -- Use the existing tab callback to cancel searches and finish active drags.
        if drawer.mode ~= mode then
            local tab = mode == "QUEUE" and drawer.queueTabButton or drawer.petsTabButton
            local click = tab and tab:GetScript("OnClick")
            if click then click(tab) end
        end
        return
    end
    ns:TogglePetPickerDrawer(nil, mode, true)
end

function ns:RunSlashCommand(message)
    local raw = strtrim(message or "")
    if raw == "" then return legacyMainCommand() end
    local command, tail = raw:match("^(%S+)%s*(.-)$")
    command = string.lower(command)
    tail = string.lower(tail)
    if command == "help" and tail == "" then return ShowCommandHelp() end
    if command == "learn" or command == "gossip" then
        if tail ~= "on" and tail ~= "off" then
            self:PrintError(self:T("仅支持 on 或 off。"))
            return
        end
        local handler = command == "learn" and SlashCmdList["WISHLEARNING"] or SlashCmdList["WISHGOSSIPDEBUG"]
        return handler(tail)
    end
    if tail == "" then
        if command == "mode" then
            return WishPetTactics_ToggleUIStyle()
        elseif command == "minimal" or command == "full" then
            if self:SetMainUIStyle(command == "minimal" and "MINIMAL" or "FULL") then
                self:ShowMainFrame("HOME")
            end
            return
        elseif command == "bind-mode" then
            return self:StartUIStyleKeybindCapture()
        elseif command == "teams" then
            self:CreateMainFrame():Show()
            return self:ShowTeamMatrixModal()
        elseif command == "targets" then
            self:CreateMainFrame():Show()
            return self:ShowRoutingModal()
        elseif command == "pets" then
            return OpenPetTab("PETS")
        elseif command == "queue" then
            return OpenPetTab("QUEUE")
        elseif command == "script" then
            self:CreateMainFrame():Show()
            return self:ToggleScriptWorkspace(true)
        elseif command == "updates" then
            return self:ShowUpdateGuide()
        elseif command == "round" then
            return SlashCmdList["WISHROUNDDEBUG"]()
        elseif command == "bind-dialog" then
            return SlashCmdList["WISHBINDDIALOG"]()
        end
    end
    self:PrintError(self:TF("未知命令：%s。输入 /wp help 查看帮助。", raw))
end

SlashCmdList["WISHREMATCH"] = function(message) return ns:RunSlashCommand(message) end
