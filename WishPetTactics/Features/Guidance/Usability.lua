local ADDON_NAME, ns = ...
local Theme = ns.Theme

-- V9: all new copy is explicitly localized; no permanent controls are added
-- to the compact pet cards or the minimal combat roster.
local COPY = {
    zhCN = {
        welcomeTitle = "欢迎使用 Wish Pet Tactics", welcomeSub = "选择一种开始方式。完成后可直接使用完整界面或极简模式。",
        import = "导入现成攻略", importDesc = "粘贴队伍或脚本，先检查再确认导入",
        create = "创建自己的队伍", createDesc = "在同一页命名、选择三只宠物和技能",
        migrate = "从 Rematch 迁移", migrateDesc = "读取已安装 Rematch 的队伍，默认不覆盖现有队伍",
        later = "暂时跳过", reopen = "再次打开引导：/wp guide", guideMenu = "重新查看使用引导",
        deleteInBattle = "战斗中无法删除队伍，请结束战斗后重试。",
        deleteDetails = "确认删除？可能影响 %d 支队伍、%d 个脚本、%d 个目标关联及 %d 份未保存脚本草稿。",
        scriptImported = "脚本已导入：%s", previewScript = "将保存的脚本 · %s", previewLimited = "预览内容过长，后续脚本未显示；可返回编辑查看原文。",
        discardDraft = "放弃草稿", discardDraftPrompt = "确定放弃此队伍尚未保存的脚本草稿吗？",
        unknownAt = "无法识别第 %s 行，请修正后重试。", saveDraftFirst = "请先保存脚本草稿，再导入脚本。",
        lockedSlots = "%d 个宠物槽位尚未解锁", waitingQueue = "等待可用的练级宠物", emptySlots = "还需选择 %d 只宠物", previewChanged = "导入内容或目标已变化，请重新预览。", draftConflict = "此队伍脚本已更改；草稿已保留，请复制后重新打开或处理。",
        preview = "预览导入", confirm = "确认导入", back = "返回编辑",
        previewTitle = "导入前检查", previewHint = "这里只读检查；确认后才写入队伍。最终以导入结果为准。",
        empty = "请先粘贴队伍字符串或脚本。", tooLong = "导入文本过长，请拆分后导入。",
        unrecognized = "没有识别到有效的队伍，请检查格式。", noTeam = "请先选择一个队伍。",
        invalid = "检查未通过，请修改文本后重试。", scriptInvalid = "脚本语法错误：%s",
        teams = "识别队伍：%d 支", owned = "已拥有宠物槽：%d 个", missing = "未收集物种：%d 种",
        duplicate = "名称可能重复：%d 支（最终按目标和阵容判重）",
        invalidTags = "无法识别的宠物槽：%d 个", scripts = "检测到脚本：%d 段",
        unknown = "无法识别的非空行：%d 行（请修改后重试）", scriptOK = "脚本语法检查通过",
        scriptCurrent = "将导入至当前队伍：%s", noScript = "没有检测到脚本。",
        notes = "注意：预检不修改收藏、队伍或技能记忆。", missingNames = "缺失示例：%s",
        summary = "战术说明", summaryTitle = "战术步骤 · 易读预览", summaryHint = "只解释常见动作；复杂条件请以原始脚本为准。",
        noActions = "未找到可解释的动作，请查看原始脚本。", syntaxProblem = "脚本未通过语法检查：%s",
        use = "使用技能 %s", next = "切换下一只可用宠物", slot = "切换至第 %s 只宠物",
        standby = "等待一回合", quit = "认输并退出当前对战", condition = "条件判断：%s", otherwise = "否则", endCond = "条件结束",
        advanced = "高级规则（查看原文）：%s", more = "还有 %d 行未展示", close = "关闭",
        saved = "队伍已保存", created = "队伍创建成功", scriptSaved = "脚本已保存", imported = "导入完成",
        petChosen = "已选择宠物，记得保存队伍", reopened = "已切换界面",
    },
    zhTW = {
        welcomeTitle = "歡迎使用 Wish Pet Tactics", welcomeSub = "選擇開始方式。完成後即可使用完整介面或極簡模式。",
        import = "匯入現成攻略", importDesc = "貼上隊伍或腳本，先檢查再確認匯入",
        create = "建立自己的隊伍", createDesc = "在同一頁命名、選擇三隻寵物與技能",
        migrate = "從 Rematch 遷移", migrateDesc = "讀取已安裝的 Rematch 隊伍，預設不覆蓋現有隊伍",
        later = "暫時略過", reopen = "再次開啟引導：/wp guide", guideMenu = "重新開啟使用引導",
        deleteInBattle = "戰鬥中無法刪除隊伍，請結束戰鬥後重試。",
        deleteDetails = "確認刪除？可能影響 %d 支隊伍、%d 個腳本、%d 個目標關聯及 %d 份未儲存的腳本草稿。",
        scriptImported = "腳本已匯入：%s", previewScript = "將儲存的腳本 · %s", previewLimited = "預覽內容過長，後續腳本未顯示；可返回編輯查看原文。",
        discardDraft = "放棄草稿", discardDraftPrompt = "確定放棄此隊伍尚未儲存的腳本草稿嗎？",
        unknownAt = "無法辨識第 %s 行，請修正後重試。", saveDraftFirst = "請先儲存腳本草稿，再匯入腳本。",
        lockedSlots = "%d 個寵物欄位尚未解鎖", waitingQueue = "等待可用的練級寵物", emptySlots = "還需選擇 %d 隻寵物", previewChanged = "匯入內容或目標已變更，請重新預覽。", draftConflict = "此隊伍腳本已變更；草稿已保留，請複製後重新開啟或處理。",
        preview = "預覽匯入", confirm = "確認匯入", back = "返回編輯",
        previewTitle = "匯入前檢查", previewHint = "這是唯讀檢查；確認後才會寫入隊伍。以實際匯入結果為準。",
        empty = "請先貼上隊伍字串或腳本。", tooLong = "匯入文字過長，請分批匯入。",
        unrecognized = "沒有辨識到有效隊伍，請檢查格式。", noTeam = "請先選擇一支隊伍。",
        invalid = "檢查未通過，請修改文字後重試。", scriptInvalid = "腳本語法錯誤：%s",
        teams = "辨識隊伍：%d 支", owned = "已擁有寵物欄位：%d 個", missing = "尚未收集物種：%d 種",
        duplicate = "名稱可能重複：%d 支（最終依目標與陣容判重）",
        invalidTags = "無法辨識的寵物欄位：%d 個", scripts = "偵測到腳本：%d 段",
        unknown = "無法辨識的非空行：%d 行（請修改後重試）", scriptOK = "腳本語法檢查通過",
        scriptCurrent = "將匯入至目前隊伍：%s", noScript = "沒有偵測到腳本。",
        notes = "注意：預檢不會修改收藏、隊伍或技能記憶。", missingNames = "缺失範例：%s",
        summary = "戰術說明", summaryTitle = "戰術步驟 · 易讀預覽", summaryHint = "僅解釋常見動作；複雜條件請以原始腳本為準。",
        noActions = "沒有找到可解釋的動作，請查看原始腳本。", syntaxProblem = "腳本語法檢查未通過：%s",
        use = "使用技能 %s", next = "切換下一隻可用寵物", slot = "切換至第 %s 隻寵物",
        standby = "等待一回合", quit = "認輸並退出目前對戰", condition = "條件判斷：%s", otherwise = "否則", endCond = "條件結束",
        advanced = "進階規則（查看原文）：%s", more = "還有 %d 行未顯示", close = "關閉",
        saved = "隊伍已儲存", created = "隊伍建立成功", scriptSaved = "腳本已儲存", imported = "匯入完成",
        petChosen = "已選擇寵物，記得儲存隊伍", reopened = "已切換介面",
    },
    enUS = {
        welcomeTitle = "Welcome to Wish Pet Tactics", welcomeSub = "Choose how to begin. Use Full or Minimal view whenever you like.",
        import = "Import a strategy", importDesc = "Paste a team or script; review before importing",
        create = "Create a team", createDesc = "Name a team and choose three pets and abilities on one page",
        migrate = "Migrate from Rematch", migrateDesc = "Read installed Rematch teams; keep existing teams by default",
        later = "Maybe later", reopen = "Open this guide again: /wp guide", guideMenu = "Open getting-started guide",
        deleteInBattle = "Teams cannot be deleted during combat. Try again afterwards.",
        deleteDetails = "Confirm deletion? This may affect %d team(s), %d script(s), %d target link(s), and %d unsaved script draft(s).",
        scriptImported = "Script imported: %s", previewScript = "Script to save · %s", previewLimited = "Preview truncated. Return to editing to inspect the full text.",
        discardDraft = "Discard draft", discardDraftPrompt = "Discard this team’s unsaved script draft?",
        unknownAt = "Unrecognized line(s): %s. Correct them and retry.", saveDraftFirst = "Save the script draft before importing a script.",
        lockedSlots = "%d pet slot(s) locked", waitingQueue = "Waiting for a leveling pet", emptySlots = "Choose %d more pet(s)", previewChanged = "Import content or target changed. Review again.", draftConflict = "The team script changed. Your draft is preserved; copy it before reopening or resolving the conflict.",
        preview = "Review import", confirm = "Confirm import", back = "Back to editing",
        previewTitle = "Pre-import check", previewHint = "Read-only check. No teams are changed until you confirm. Actual import results may differ.",
        empty = "Paste a team string or script first.", tooLong = "Import text is too long. Please split it.",
        unrecognized = "No valid teams found. Check the format.", noTeam = "Select a team first.",
        invalid = "Check failed. Edit the text and try again.", scriptInvalid = "Script syntax error: %s",
        teams = "Teams found: %d", owned = "Owned pet slots: %d", missing = "Uncollected species: %d",
        duplicate = "Possibly duplicate names: %d (final match uses target and pets)",
        invalidTags = "Unrecognized pet slots: %d", scripts = "Scripts detected: %d",
        unknown = "Unrecognized non-empty lines: %d (edit and retry)", scriptOK = "Script syntax check passed",
        scriptCurrent = "Import into current team: %s", noScript = "No script detected.",
        notes = "Preview does not change pets, teams, or ability memory.", missingNames = "Missing examples: %s",
        summary = "Strategy notes", summaryTitle = "Strategy steps · readable preview", summaryHint = "Common actions only. Refer to the original script for complex conditions.",
        noActions = "No recognizable actions. See the original script.", syntaxProblem = "Script validation failed: %s",
        use = "Use ability %s", next = "Switch to the next available pet", slot = "Switch to pet %s",
        standby = "Pass one turn", quit = "Forfeit the current battle", condition = "Condition: %s", otherwise = "Otherwise", endCond = "End condition",
        advanced = "Advanced rule (see source): %s", more = "%d more lines not shown", close = "Close",
        saved = "Team saved", created = "Team created", scriptSaved = "Script saved", imported = "Import complete",
        petChosen = "Pet selected; remember to save", reopened = "View switched",
    },
}

function ns:UXText(key, ...)
    local dict = COPY[self.locale] or COPY.enUS
    local value = dict[key] or COPY.enUS[key] or key
    if select('#', ...) > 0 then return string.format(value, ...) end
    return value
end

local function Trim(s)
    return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function StripScript(text)
    text = tostring(text or ''):gsub('\\n', '\n')
    text = text:match('%-%-%-%-%-BEGIN PET BATTLE SCRIPT%-%-%-%-%-%s*(.-)%s*%-%-%-%-%-END PET BATTLE SCRIPT%-%-%-%-%-') or text
    return ns.Syntax and ns.Syntax:StripColors(text) or text
end

-- A single read-only scanner is shared by preview and import. It keeps each
-- team's full script together and reports unsupported input with line numbers.
function ns:ScanTeamImport(raw)
    local result = { entries = {}, unknownLines = {}, malformed = false }
    local group = (self.teamFilterState and self.teamFilterState.group ~= "ALL" and self.teamFilterState.group) or "未分组队伍"
    local explicitGroup, current, inBlock = false, nil, false
    local commands = {use=true, ability=true, change=true, ["if"]=true, elseif_=true,
        ["else"]=true, ["end"]=true, endif=true, standby=true, pass=true, catch=true, trap=true, quit=true, test=true}
    commands["elseif"] = true
    raw = tostring(raw or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local number = 0
    for line in (raw .. "\n"):gmatch("(.-)\n") do
        number = number + 1
        local trimmed = Trim(line)
        if trimmed == "-----BEGIN PET BATTLE SCRIPT-----" then
            if inBlock or not current then result.malformed = true end
            inBlock = true
            if current then current.lines = {}; current.hasScript = true end
        elseif trimmed == "-----END PET BATTLE SCRIPT-----" then
            if not inBlock then result.malformed = true end
            inBlock = false
        elseif inBlock then
            if current then current.lines[#current.lines + 1] = line end
        elseif trimmed == "" or trimmed:match("^%-%-") or trimmed:match("^#") then
            if current then current.lines[#current.lines + 1] = line end
        else
            local groupHeader = trimmed:match("^__%s*([^:]+):.-__$") or trimmed:match("^__%s*(.-)%s*__$")
            local command, following = trimmed:match("^([%a_]+)(.*)$")
            command = command and string.lower(command)
            if groupHeader then
                group, explicitGroup, current = Trim(groupHeader), true, nil
            elseif current and command and commands[command]
                and (following == "" or following:match("^%s") or following:match("^%(") or following:match("^%[")) then
                current.hasScript = true
                current.lines[#current.lines + 1] = line
            else
                local name, _, a, b, c, tail = trimmed:match("^(.-):([^:]*):([^:]+):([^:]+):([^:]+):?(.*)$")
                if name and Trim(name) ~= "" then
                    current = {line=trimmed, lineNumber=number, group=group, explicitGroup=explicitGroup,
                        tags={a,b,c}, lines={}, hasScript=false}
                    local embedded = tail and tail:match("%-%-%-%-%-BEGIN PET BATTLE SCRIPT%-%-%-%-%-(.-)%-%-%-%-%-END PET BATTLE SCRIPT%-%-%-%-%-")
                    if embedded then current.inlineScript = StripScript(embedded) end
                    result.entries[#result.entries + 1] = current
                else
                    result.unknownLines[#result.unknownLines + 1] = number
                end
            end
        end
    end
    if inBlock then result.malformed = true end
    for _, entry in ipairs(result.entries) do
        if entry.hasScript then entry.script = Trim(table.concat(entry.lines, "\n"))
        else entry.script = entry.inlineScript end
    end
    return result
end

-- Pure preflight: never calls the mutating team importer, EnsureTeamGroup,
-- RememberSlotSpeciesSkills, or ApplyTeamData. Duplicate-name counts are
-- deliberately advisory, not a claim of the importer's exact match result.
function ns:BuildImportPreview(raw, mode)
    raw = tostring(raw or '')
    local result = { valid = false, mode = mode, teams = 0, owned = 0, missing = 0,
        duplicate = 0, invalidTags = 0, unknown = 0, scripts = 0, missingNames = {} }
    if Trim(raw) == '' then result.error = self:UXText('empty'); return result end
    if #raw > 1000000 then result.error = self:UXText('tooLong'); return result end
    if mode == 'SCRIPT' then
        local team = self.db and self.db.teams and self.db.teams[self.db.selectedTeamIdx]
        if not team then result.error = self:UXText('noTeam'); return result end
        local script = StripScript(Trim(raw))
        local ok, err = self.ScriptEngine:ValidateScript(script)
        result.scripts = 1
        result.valid = ok and true or false
        result.error = not ok and self:UXText('scriptInvalid', tostring(err)) or nil
        result.teamName = team.name or ''
        result.team = team
        result.originalScript = team.script or ''
        result.script = self:LocalizeScriptAbilities(script)
        if self.HasScriptDraft and self:HasScriptDraft(team) then result.valid = false; result.error = self:UXText('saveDraftFirst') end
        return result
    end

    local existingNames, seenMissing = {}, {}
    for _, team in ipairs((self.db and self.db.teams) or {}) do
        existingNames[string.lower(Trim(team.name))] = true
    end
    local scan = self:ScanTeamImport(raw)
    result.scan = scan
    result.unknown = #scan.unknownLines
    result.unknownLines = scan.unknownLines
    for _, entry in ipairs(scan.entries) do
        local name = Trim(entry.line:match("^(.-):") or "")
        result.teams = result.teams + 1
        if existingNames[string.lower(name)] then result.duplicate = result.duplicate + 1 end
        for _, tag in ipairs(entry.tags) do
            local info = self:ParseRematchPetTag(tag, entry.script)
            if not info then
                result.invalidTags = result.invalidTags + 1
            elseif info.speciesID and info.speciesID > 0 then
                local collected = C_PetJournal and C_PetJournal.GetNumCollectedInfo
                    and C_PetJournal.GetNumCollectedInfo(info.speciesID) or 0
                if collected and collected > 0 then
                    result.owned = result.owned + 1
                elseif not seenMissing[info.speciesID] then
                    seenMissing[info.speciesID] = true
                    result.missing = result.missing + 1
                    if #result.missingNames < 3 then
                        local speciesName = C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID
                            and C_PetJournal.GetPetInfoBySpeciesID(info.speciesID)
                        result.missingNames[#result.missingNames + 1] = speciesName or ('#' .. info.speciesID)
                    end
                end
            end
        end
        if entry.script and entry.script ~= '' then
            entry.script = self:LocalizeScriptAbilities(StripScript(entry.script))
            local ok, err = self.ScriptEngine:ValidateScript(entry.script)
            result.scripts = result.scripts + 1
            if not ok and not result.error then result.error = self:UXText('scriptInvalid', tostring(err)) end
        end
        -- Match the importer's note extraction after removing an embedded block.
        local _, _, _, _, _, rawTail = entry.line:match('^(.-):([^:]*):([^:]+):([^:]+):([^:]+):?(.*)$')
        rawTail = (rawTail or ''):gsub('%-%-%-%-%-BEGIN PET BATTLE SCRIPT%-%-%-%-%-.-%-%-%-%-%-END PET BATTLE SCRIPT%-%-%-%-%-', '')
        local note = rawTail:match('N:(.+)$')
        if note then note = Trim(note:gsub('\\n', ' ')) end
        local script = (entry.script and entry.script ~= '') and entry.script or ns:GetDefaultBattleScript()
        entry.savedScript = (note and note ~= '') and ('-- ' .. note .. '\n\n' .. script) or script
    end
    if scan.malformed then result.error = self:UXText('invalid') end
    if result.unknown > 0 then result.error = self:UXText('unknownAt', table.concat(scan.unknownLines, ', ')) end
    if result.teams == 0 then result.error = result.error or self:UXText('unrecognized') end
    if result.invalidTags > 0 then result.error = result.error or self:UXText('invalid') end
    result.valid = result.teams > 0 and result.invalidTags == 0 and not result.error
    return result
end

local function PreviewPrefix(text, limit)
    if #text <= limit then return text end
    local last = limit
    local first = last
    while first > 0 and text:byte(first) >= 128 and text:byte(first) < 192 do first = first - 1 end
    if first > 0 then
        local lead = text:byte(first)
        local width = lead >= 240 and 4 or lead >= 224 and 3 or lead >= 192 and 2 or 1
        if last - first + 1 < width then last = first - 1 end
    end
    return text:sub(1, last)
end

function ns:FormatImportPreview(result)
    local lines = { self:UXText('previewTitle'), self:UXText('previewHint'), '' }
    if result.mode == 'SCRIPT' then
        lines[#lines + 1] = self:UXText('scriptCurrent', result.teamName or '')
        lines[#lines + 1] = result.valid and self:UXText('scriptOK') or (result.error or self:UXText('invalid'))
    else
        for _, key in ipairs({'teams','owned','missing','duplicate','invalidTags','scripts','unknown'}) do
            if key == 'teams' or key == 'owned' or key == 'missing' or (result[key] or 0) > 0 then
                lines[#lines + 1] = self:UXText(key, result[key] or 0)
            end
        end
        if #result.missingNames > 0 then
            lines[#lines + 1] = self:UXText('missingNames', table.concat(result.missingNames, ', '))
        end
        if result.error then lines[#lines + 1] = '|cffff7777' .. result.error .. '|r' end
    end
    lines[#lines + 1] = ''
    lines[#lines + 1] = self:UXText('notes')
    local budget, truncated = 16000, false
    local function AddScript(name, script)
        if budget <= 0 then truncated = true; return end
        local heading = self:UXText('previewScript', name or '')
        local part = PreviewPrefix(script or '', budget)
        lines[#lines + 1] = ''
        lines[#lines + 1] = heading
        lines[#lines + 1] = part
        budget = budget - #part - #heading
        if #part < #(script or '') then truncated = true end
    end
    if result.mode == 'SCRIPT' and result.script then
        AddScript(result.teamName, result.script)
    elseif result.scan then
        for _, entry in ipairs(result.scan.entries) do
            if budget <= 0 then truncated = true; break end
            AddScript(entry.line:match('^(.-):'), entry.savedScript)
        end
    end
    if truncated then lines[#lines + 1] = self:UXText('previewLimited') end
    return table.concat(lines, '\n')
end

function ns:DescribeBattleScript(raw, limit)
    local script = StripScript(raw)
    local ok, err = self.ScriptEngine:ValidateScript(script)
    local lines = {}
    if not ok then lines[#lines + 1] = self:UXText('syntaxProblem', tostring(err)) end
    local total = 0
    limit = limit or 11
    for rawLine in (script .. '\n'):gmatch('(.-)\n') do
        local line = Trim(rawLine)
        if line ~= '' and not line:match('^%-%-') and not line:match('^#') then
            total = total + 1
            if #lines < limit then
                local clean = Trim(line:gsub('%s*%-%-.*$', ''))
                local ability = clean:match('^use%s*%(%s*([123])%s*%)')
                local switch = clean:match('^change%s*%(%s*#([123])%s*%)')
                local cond = clean:match('^if%s+(.+)') or clean:match('^elseif%s+(.+)')
                local label
                if ability then label = self:UXText('use', ability)
                elseif clean:match('^change%s*%(%s*next%s*%)') then label = self:UXText('next')
                elseif switch then label = self:UXText('slot', switch)
                elseif clean == 'standby' then label = self:UXText('standby')
                elseif clean == 'quit' then label = self:UXText('quit')
                elseif cond then label = self:UXText('condition', cond)
                elseif clean == 'else' then label = self:UXText('otherwise')
                elseif clean == 'end' or clean == 'endif' then label = self:UXText('endCond')
                else label = self:UXText('advanced', clean) end
                -- Bracketed conditions must remain visible, not silently erased.
                local suffix = (ability or switch or clean:match('^change%s*%(')) and clean:match('%b[]%s*$')
                if suffix then label = label .. ' ' .. suffix end
                lines[#lines + 1] = tostring(total) .. '. ' .. label
            end
        end
    end
    if total > limit then lines[#lines + 1] = self:UXText('more', total - limit) end
    if total == 0 then lines[#lines + 1] = self:UXText('noActions') end
    return table.concat(lines, '\n'), ok
end

function ns:ShowUIFeedback(message)
    if not self.centerToast then
        local toast = CreateFrame('Frame', 'WishPetTacticsCenterToast', UIParent, 'BackdropTemplate')
        toast:SetSize(320, 36)
        toast:SetPoint('TOP', UIParent, 'TOP', 0, -180)
        toast:SetFrameStrata('TOOLTIP')
        toast:SetFrameLevel(950)
        toast:EnableMouse(false)
        Theme:ApplyBackdrop(toast, {0, 0, 0, 0}, Theme.Colors.borderGreen, false)
        toast.text = toast:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
        toast.text:SetPoint('CENTER', 0, 0)
        Theme:HookLocalizedFontString(toast.text)
        self.centerToast = toast
    end
    local toast = self.centerToast
    if self.MainFrame then
        toast:SetScale(self.MainFrame:GetEffectiveScale() / UIParent:GetEffectiveScale())
    end
    toast.text:SetText('|cff6ee7b7' .. tostring(message) .. '|r')
    local tw = toast.text:GetStringWidth() or 180
    toast:SetWidth(math.max(220, tw + 48))
    toast:ClearAllPoints()
    toast:SetPoint('TOP', UIParent, 'TOP', 0, -180)
    toast:Show()
    local token = {}
    toast.token = token
    C_Timer.After(2.5, function()
        if toast.token == token then toast:Hide() end
    end)
end

function ns:ShowTacticsSummary(raw)
    local m = self.TacticsSummaryModal
    if not m then
        m = CreateFrame('Frame', 'WishPetTacticsStrategySummary', UIParent, 'BackdropTemplate')
        m:SetSize(520, 350)
        m:SetPoint('CENTER')
        m:SetFrameStrata('FULLSCREEN_DIALOG')
        m:SetFrameLevel(700)
        m:SetClampedToScreen(true)
        Theme:ApplyBackdrop(m, Theme.Colors.bgPopup, Theme.Colors.borderBlue)
        local title = m:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
        title:SetPoint('TOPLEFT', 22, -20)
        title:SetText(self:UXText('summaryTitle'))
        local closeBtn = Theme:CreateCloseIconButton(m, function() m:Hide() end)
        closeBtn:SetPoint('TOPRIGHT', -18, -18)
        local hint = m:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        hint:SetPoint('TOPLEFT', 22, -52)
        hint:SetWidth(474)
        hint:SetJustifyH('LEFT')
        hint:SetTextColor(0.64, 0.75, 0.87)
        hint:SetText(self:UXText('summaryHint'))
        local scroll = CreateFrame('ScrollFrame', nil, m, 'UIPanelScrollFrameTemplate')
        scroll:SetPoint('TOPLEFT', 22, -91)
        scroll:SetPoint('BOTTOMRIGHT', -40, 22)
        local content = CreateFrame('Frame', nil, scroll)
        content:SetWidth(455)
        content:SetHeight(1)
        scroll:SetScrollChild(content)
        local body = content:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        body:SetPoint('TOPLEFT', 0, 0)
        body:SetWidth(455)
        body:SetJustifyH('LEFT')
        body:SetJustifyV('TOP')
        body:SetWordWrap(true)
        m.body = body
        m.bodyContent = content
        m.bodyScroll = scroll
        m:Hide()
        self.TacticsSummaryModal = m
    end
    m.body:SetText(self:DescribeBattleScript(raw, 1000))
    m.bodyContent:SetHeight(math.max(1, m.body:GetStringHeight() + 12))
    m.bodyScroll:SetVerticalScroll(0)
    m:Show()
end

function ns:ShowWelcomeGuide() end
function ns:ShowWelcomeIfNeeded() end
