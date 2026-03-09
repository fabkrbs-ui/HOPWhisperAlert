-- HoP Whisper Alert for 1.12.1 (Turtle WoW) -- v3.3 Release

local HOP_ICON_PATH = "Interface\\Icons\\Spell_Holy_SealOfProtection"
local HOP_SPELL_NAME = "Hand of Protection"
local HOP_VERSION = "3.3"

local SOUND_OPTIONS = {
    { label = "Raid Warning", value = "RaidWarning" },
    { label = "Level Up",     value = "LevelUp" },
    { label = "Ready Check",  value = "ReadyCheck" },
    { label = "None",         value = "" },
}

local DEFAULTS = {
    displayTime = 4,
    allowedNames = "",
    alpha = 60,
    soundIndex = 1,
    customKeywords = "",
    locked = false,
    posX = 0,
    posY = 0,
    iconSize = 64,
    failExtend = 1,
    cdReplyOnly = false,
}

HOPAlertDB = nil

local function GetSetting(key)
    if HOPAlertDB and HOPAlertDB[key] ~= nil then
        return HOPAlertDB[key]
    end
    return DEFAULTS[key]
end

local function GetSoundValue()
    local idx = GetSetting("soundIndex")
    if SOUND_OPTIONS[idx] then return SOUND_OPTIONS[idx].value end
    return SOUND_OPTIONS[1].value
end

local function GetSoundLabel()
    local idx = GetSetting("soundIndex")
    if SOUND_OPTIONS[idx] then return SOUND_OPTIONS[idx].label end
    return SOUND_OPTIONS[1].label
end

-- ===== CACHED LOOKUPS =====
local cachedSpellIndex = nil
local cachedKeywords = nil
local cachedKeywordSource = nil
local cachedNames = nil
local cachedNameSource = nil
local lastSender = nil

local function GetSpellIndex()
    if cachedSpellIndex then return cachedSpellIndex end
    local i = 1
    while true do
        local name = GetSpellName(i, BOOKTYPE_SPELL)
        if not name then return nil end
        if name == HOP_SPELL_NAME then
            cachedSpellIndex = i
            return i
        end
        i = i + 1
    end
end

local function GetHOPCooldownRemaining()
    local idx = GetSpellIndex()
    if not idx then return nil end
    local start, duration = GetSpellCooldown(idx, BOOKTYPE_SPELL)
    if start and start > 0 and duration and duration > 1.5 then
        local rem = (start + duration) - GetTime()
        if rem > 0 then return rem end
    end
    return 0
end

local function SplitCommaList(str)
    local list = {}
    if not str or str == "" then return list end
    for entry in string.gfind(str, "[^,]+") do
        local trimmed = string.gsub(entry, "^%s+", "")
        trimmed = string.gsub(trimmed, "%s+$", "")
        if trimmed ~= "" then
            table.insert(list, string.lower(trimmed))
        end
    end
    return list
end

local function GetKeywordList()
    local src = GetSetting("customKeywords")
    if src ~= cachedKeywordSource then
        cachedKeywordSource = src
        if src ~= "" then
            cachedKeywords = SplitCommaList(src)
        else
            cachedKeywords = { "hand of protection", "hop" }
        end
    end
    return cachedKeywords
end

local function GetNameList()
    local src = GetSetting("allowedNames")
    if src ~= cachedNameSource then
        cachedNameSource = src
        cachedNames = SplitCommaList(src)
    end
    return cachedNames
end

local function WordMatch(lowerMsg, word)
    local padded = " " .. lowerMsg .. " "
    local search = " " .. word .. " "
    return string.find(padded, search, 1, true) ~= nil
end

local function MessageMatchesKeyword(lowerMsg, keywords)
    for _, word in ipairs(keywords) do
        if WordMatch(lowerMsg, word) then return true end
    end
    return false
end

local function MessageIsCooldownQuery(lowerMsg, keywords)
    if lowerMsg == "cd" then return true end
    local afterCD = string.gsub(lowerMsg, "^cd%s+", "", 1)
    if afterCD ~= lowerMsg then
        for _, word in ipairs(keywords) do
            if WordMatch(afterCD, word) or afterCD == word then return true end
        end
    end
    return false
end

local function SenderIsAllowed(sender)
    local list = GetNameList()
    if not list or table.getn(list) == 0 then return true end
    local lowerSender = string.lower(sender)
    for _, name in ipairs(list) do
        if lowerSender == name then return true end
    end
    return false
end

local function SavePosition()
    if HOPAlertDB then
        local _, _, _, x, y = HOPAlertFrame:GetPoint(1)
        HOPAlertDB.posX = x
        HOPAlertDB.posY = y
    end
end

local function FormatSeconds(sec)
    sec = math.floor(sec + 0.5)
    if sec >= 60 then
        local m = math.floor(sec / 60)
        local s = sec - (m * 60)
        if s > 0 then return m .. "m " .. s .. "s" end
        return m .. "m"
    end
    return sec .. "s"
end

local function SendCooldownReply(sender)
    local cd = GetHOPCooldownRemaining()
    local reply
    if cd == nil then
        reply = "[HoP CD] I don't have HoP on this character."
    elseif cd == 0 then
        reply = "[HoP CD] HoP is READY. Whisper me to request it!"
    else
        reply = "[HoP CD] " .. FormatSeconds(cd) .. " remaining."
    end
    SendChatMessage(reply, "WHISPER", nil, sender)
end

local iconTex
local remaining = 0

local function ApplyDesaturation()
    local cd = GetHOPCooldownRemaining()
    if cd and cd > 0 then
        if not iconTex:SetDesaturated(1) then
            iconTex:SetVertexColor(0.4, 0.4, 0.4)
        end
    else
        iconTex:SetDesaturated(nil)
        iconTex:SetVertexColor(1, 1, 1)
    end
end

local function ApplyIconSize()
    local sz = GetSetting("iconSize")
    HOPAlertFrame:SetWidth(sz)
    HOPAlertFrame:SetHeight(sz)
end

-- ===== TIMER (only active while icon is shown) =====
local timerFrame = CreateFrame("Frame")

local function TimerOnUpdate()
    remaining = remaining - arg1
    if remaining <= 0 then
        remaining = 0
        HOPAlertFrame:Hide()
        this:SetScript("OnUpdate", nil)
    end
end

-- ===== POST-CAST CHECKER (only active during pending check) =====
local postCastCheck = nil
local postCastFrame = CreateFrame("Frame")
local failTimeAdded = 0
local FAIL_TIME_CAP = 6

local function PostCastOnUpdate()
    if not postCastCheck then return end
    local elapsed = GetTime() - postCastCheck.time
    if elapsed < 0.3 then return end

    local cd = GetHOPCooldownRemaining()
    local sender = postCastCheck.sender
    postCastCheck = nil
    postCastFrame:SetScript("OnUpdate", nil)

    if cd and cd > 0 then
        SendChatMessage(">> PROTECTION ACTIVE ON YOU! <<", "WHISPER", nil, sender)
        remaining = 0
        failTimeAdded = 0
        HOPAlertFrame:Hide()
        timerFrame:SetScript("OnUpdate", nil)
    else
        remaining = GetSetting("displayTime")
        local ext = GetSetting("failExtend")
        if ext > 0 and failTimeAdded < FAIL_TIME_CAP then
            local space = FAIL_TIME_CAP - failTimeAdded
            if ext > space then ext = space end
            remaining = remaining + ext
            failTimeAdded = failTimeAdded + ext
        end
        timerFrame:SetScript("OnUpdate", TimerOnUpdate)
        ApplyDesaturation()
    end

    TargetLastTarget()
end

local function SafeCastHOP(sender)
    if postCastCheck then return end
    TargetByName(sender, true)

    local tName = UnitName("target")
    if not tName or string.lower(tName) ~= string.lower(sender) then
        TargetLastTarget()
        return
    end

    if UnitIsUnit("player", "target") then
        TargetLastTarget()
        return
    end

    if not UnitIsFriend("player", "target") then
        TargetLastTarget()
        return
    end

    if UnitIsDeadOrGhost("target") then
        TargetLastTarget()
        return
    end

    if not CheckInteractDistance("target", 4) then
        TargetLastTarget()
        return
    end

    local cd = GetHOPCooldownRemaining()
    if cd and cd > 0 then
        SendChatMessage("[HoP CD] " .. FormatSeconds(cd) .. " remaining.", "WHISPER", nil, sender)
        TargetLastTarget()
        return
    end

    postCastCheck = { sender = sender, time = GetTime() }
    postCastFrame:SetScript("OnUpdate", PostCastOnUpdate)
    CastSpellByName("Hand of Protection")
end

-- ===== ICON FRAME =====
local HOPAlertFrame = CreateFrame("Button", "HOPAlertFrame", UIParent)
HOPAlertFrame:SetWidth(64)
HOPAlertFrame:SetHeight(64)
HOPAlertFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
HOPAlertFrame:SetMovable(true)
HOPAlertFrame:EnableMouse(true)
HOPAlertFrame:RegisterForDrag("LeftButton")
HOPAlertFrame:RegisterForClicks("LeftButtonUp")
HOPAlertFrame:SetClampedToScreen(true)

local isDragging = false

HOPAlertFrame:SetScript("OnDragStart", function()
    if GetSetting("locked") then return end
    isDragging = true
    this:StartMoving()
end)

HOPAlertFrame:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    isDragging = false
    SavePosition()
end)

HOPAlertFrame:SetScript("OnClick", function()
    if isDragging then return end
    if lastSender and not GetSetting("cdReplyOnly") then
        SafeCastHOP(lastSender)
    end
end)

iconTex = HOPAlertFrame:CreateTexture(nil, "BACKGROUND")
iconTex:SetAllPoints(HOPAlertFrame)
iconTex:SetTexture(HOP_ICON_PATH)

local senderShadow = HOPAlertFrame:CreateFontString(nil, "ARTWORK")
senderShadow:SetPoint("CENTER", HOPAlertFrame, "CENTER", 1, -1)
senderShadow:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
senderShadow:SetTextColor(0, 0, 0, 1)
senderShadow:SetText("")

local senderText = HOPAlertFrame:CreateFontString(nil, "OVERLAY")
senderText:SetPoint("CENTER", HOPAlertFrame, "CENTER", 0, 0)
senderText:SetFont("Fonts\\FRIZQT__.TTF", 18, "THICKOUTLINE")
senderText:SetTextColor(1, 1, 0, 1)
senderText:SetText("")

HOPAlertFrame:Hide()

local function ShowHOPIcon(sender)
    remaining = GetSetting("displayTime")
    failTimeAdded = 0
    HOPAlertFrame:SetAlpha(GetSetting("alpha") / 100)
    ApplyIconSize()
    local displayName = sender or ""
    senderShadow:SetText(displayName)
    senderText:SetText(displayName)
    ApplyDesaturation()
    HOPAlertFrame:Show()
    timerFrame:SetScript("OnUpdate", TimerOnUpdate)
    local snd = GetSoundValue()
    if snd ~= "" and PlaySound then
        PlaySound(snd)
    end
end

-- ===== EVENT HANDLER =====
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("LEARNED_SPELL_IN_TAB")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "HOPWhisperAlert" then
        if type(HOPAlertDB) ~= "table" then
            HOPAlertDB = {}
        end
        HOPAlertFrame:ClearAllPoints()
        HOPAlertFrame:SetPoint("CENTER", UIParent, "CENTER", GetSetting("posX"), GetSetting("posY"))
        HOPAlertFrame:SetAlpha(GetSetting("alpha") / 100)
        ApplyIconSize()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffHoP Whisper Alert|r v" .. HOP_VERSION .. " loaded. Type |cfffff200/hop|r to open settings.")
        eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        return
    end
    if event == "LEARNED_SPELL_IN_TAB" then
        cachedSpellIndex = nil
        return
    end
    if event == "CHAT_MSG_WHISPER" then
        local msg = arg1
        local sender = arg2
        if not msg or type(msg) ~= "string" then return end
        if not SenderIsAllowed(sender) then return end
        local lowerMsg = string.lower(msg)
        local keywords = GetKeywordList()
        if MessageIsCooldownQuery(lowerMsg, keywords) then
            SendCooldownReply(sender)
            return
        end
        if MessageMatchesKeyword(lowerMsg, keywords) then
            lastSender = sender
            if GetSetting("cdReplyOnly") then
                SendCooldownReply(sender)
                return
            end
            local cd = GetHOPCooldownRemaining()
            if cd and cd > 0 then
                SendCooldownReply(sender)
            end
            ShowHOPIcon(sender)
        end
    end
end)

-- ===== SETTINGS PANEL =====
local settingsFrame = CreateFrame("Frame", "HOPAlertSettings", UIParent)
settingsFrame:SetWidth(280)
settingsFrame:SetHeight(530)
settingsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
settingsFrame:SetMovable(true)
settingsFrame:EnableMouse(true)
settingsFrame:RegisterForDrag("LeftButton")
settingsFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
})
settingsFrame:SetBackdropColor(0, 0, 0, 0.9)
settingsFrame:Hide()

settingsFrame:SetScript("OnDragStart", function() this:StartMoving() end)
settingsFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

local title = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", settingsFrame, "TOP", 0, -14)
title:SetText("HoP Alert Settings")

local closeBtn = CreateFrame("Button", nil, settingsFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", settingsFrame, "TOPRIGHT", -4, -4)

local cdOnlyCheck = CreateFrame("CheckButton", "HOPAlertCDOnlyCheck", settingsFrame, "UICheckButtonTemplate")
cdOnlyCheck:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 12, -40)
cdOnlyCheck:SetWidth(24)
cdOnlyCheck:SetHeight(24)
cdOnlyCheck:SetChecked(GetSetting("cdReplyOnly"))

local cdOnlyText = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
cdOnlyText:SetPoint("LEFT", cdOnlyCheck, "RIGHT", 2, 0)
cdOnlyText:SetText("CD reply only (no icon/cast)")

cdOnlyCheck:SetScript("OnClick", function()
    HOPAlertDB.cdReplyOnly = (this:GetChecked() == 1)
end)

local lockCheck = CreateFrame("CheckButton", "HOPAlertLockCheck", settingsFrame, "UICheckButtonTemplate")
lockCheck:SetPoint("TOPLEFT", cdOnlyCheck, "BOTTOMLEFT", 0, -4)
lockCheck:SetWidth(24)
lockCheck:SetHeight(24)
lockCheck:SetChecked(GetSetting("locked"))

local lockText = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
lockText:SetPoint("LEFT", lockCheck, "RIGHT", 2, 0)
lockText:SetText("Lock icon position")

lockCheck:SetScript("OnClick", function()
    HOPAlertDB.locked = (this:GetChecked() == 1)
end)

local durLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
durLabel:SetPoint("TOPLEFT", lockCheck, "BOTTOMLEFT", 4, -10)
durLabel:SetText("Display time (seconds):")

local durValue = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
durValue:SetPoint("LEFT", durLabel, "RIGHT", 6, 0)
durValue:SetText(tostring(GetSetting("displayTime")))

local durSlider = CreateFrame("Slider", "HOPAlertDurSlider", settingsFrame, "OptionsSliderTemplate")
durSlider:SetPoint("TOPLEFT", durLabel, "BOTTOMLEFT", 0, -12)
durSlider:SetWidth(245)
durSlider:SetHeight(16)
durSlider:SetMinMaxValues(1, 15)
durSlider:SetValueStep(1)
durSlider:SetValue(GetSetting("displayTime"))
getglobal(durSlider:GetName().."Low"):SetText("1")
getglobal(durSlider:GetName().."High"):SetText("15")
getglobal(durSlider:GetName().."Text"):SetText("")
durSlider:SetScript("OnValueChanged", function()
    local val = math.floor(this:GetValue() + 0.5)
    HOPAlertDB.displayTime = val
    durValue:SetText(tostring(val))
end)

local failLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
failLabel:SetPoint("TOPLEFT", durSlider, "BOTTOMLEFT", 0, -18)
failLabel:SetText("Added time per failed click (sec):")

local failValue = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
failValue:SetPoint("LEFT", failLabel, "RIGHT", 6, 0)
failValue:SetText(string.format("%.1f", GetSetting("failExtend")))

local failSlider = CreateFrame("Slider", "HOPAlertFailSlider", settingsFrame, "OptionsSliderTemplate")
failSlider:SetPoint("TOPLEFT", failLabel, "BOTTOMLEFT", 0, -12)
failSlider:SetWidth(245)
failSlider:SetHeight(16)
failSlider:SetMinMaxValues(5, 30)
failSlider:SetValueStep(5)
failSlider:SetValue(GetSetting("failExtend") * 10)
getglobal(failSlider:GetName().."Low"):SetText("0.5")
getglobal(failSlider:GetName().."High"):SetText("3.0")
getglobal(failSlider:GetName().."Text"):SetText("")
failSlider:SetScript("OnValueChanged", function()
    local raw = math.floor(this:GetValue() + 0.5)
    local val = raw / 10
    HOPAlertDB.failExtend = val
    failValue:SetText(string.format("%.1f", val))
end)

local sizeLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sizeLabel:SetPoint("TOPLEFT", failSlider, "BOTTOMLEFT", 0, -18)
sizeLabel:SetText("Icon size:")

local sizeValue = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
sizeValue:SetPoint("LEFT", sizeLabel, "RIGHT", 6, 0)
sizeValue:SetText(tostring(GetSetting("iconSize")) .. "px")

local sizeSlider = CreateFrame("Slider", "HOPAlertSizeSlider", settingsFrame, "OptionsSliderTemplate")
sizeSlider:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 0, -12)
sizeSlider:SetWidth(245)
sizeSlider:SetHeight(16)
sizeSlider:SetMinMaxValues(32, 128)
sizeSlider:SetValueStep(4)
sizeSlider:SetValue(GetSetting("iconSize"))
getglobal(sizeSlider:GetName().."Low"):SetText("32")
getglobal(sizeSlider:GetName().."High"):SetText("128")
getglobal(sizeSlider:GetName().."Text"):SetText("")
sizeSlider:SetScript("OnValueChanged", function()
    local val = math.floor(this:GetValue() + 0.5)
    HOPAlertDB.iconSize = val
    sizeValue:SetText(tostring(val) .. "px")
end)

local alphaLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
alphaLabel:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", 0, -18)
alphaLabel:SetText("Icon opacity:")

local alphaValue = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
alphaValue:SetPoint("LEFT", alphaLabel, "RIGHT", 6, 0)
alphaValue:SetText(tostring(GetSetting("alpha")) .. "%")

local alphaSlider = CreateFrame("Slider", "HOPAlertAlphaSlider", settingsFrame, "OptionsSliderTemplate")
alphaSlider:SetPoint("TOPLEFT", alphaLabel, "BOTTOMLEFT", 0, -12)
alphaSlider:SetWidth(245)
alphaSlider:SetHeight(16)
alphaSlider:SetMinMaxValues(10, 100)
alphaSlider:SetValueStep(5)
alphaSlider:SetValue(GetSetting("alpha"))
getglobal(alphaSlider:GetName().."Low"):SetText("10%")
getglobal(alphaSlider:GetName().."High"):SetText("100%")
getglobal(alphaSlider:GetName().."Text"):SetText("")
alphaSlider:SetScript("OnValueChanged", function()
    local val = math.floor(this:GetValue() + 0.5)
    HOPAlertDB.alpha = val
    alphaValue:SetText(tostring(val) .. "%")
end)

local soundLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
soundLabel:SetPoint("TOPLEFT", alphaSlider, "BOTTOMLEFT", 0, -18)
soundLabel:SetText("Alert sound:")

local soundDropdown = CreateFrame("Frame", "HOPAlertSoundDropdown", settingsFrame, "UIDropDownMenuTemplate")
soundDropdown:SetPoint("TOPLEFT", soundLabel, "BOTTOMLEFT", -16, -2)

local function SoundDropdown_OnClick()
    HOPAlertDB.soundIndex = this.value
    UIDropDownMenu_SetSelectedValue(soundDropdown, this.value)
    UIDropDownMenu_SetText(SOUND_OPTIONS[this.value].label, soundDropdown)
    local snd = SOUND_OPTIONS[this.value].value
    if snd ~= "" and PlaySound then PlaySound(snd) end
end

UIDropDownMenu_Initialize(soundDropdown, function()
    for i, opt in ipairs(SOUND_OPTIONS) do
        local info = {}
        info.text = opt.label
        info.value = i
        info.func = SoundDropdown_OnClick
        UIDropDownMenu_AddButton(info)
    end
end)
UIDropDownMenu_SetWidth(200, soundDropdown)
UIDropDownMenu_SetSelectedValue(soundDropdown, GetSetting("soundIndex"))
UIDropDownMenu_SetText(GetSoundLabel(), soundDropdown)

local kwLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
kwLabel:SetPoint("TOPLEFT", soundDropdown, "BOTTOMLEFT", 16, -8)
kwLabel:SetText("Keywords (comma separated, blank = HOP):")

local kwBox = CreateFrame("EditBox", "HOPAlertKWBox", settingsFrame, "InputBoxTemplate")
kwBox:SetPoint("TOPLEFT", kwLabel, "BOTTOMLEFT", 6, -4)
kwBox:SetWidth(230)
kwBox:SetHeight(24)
kwBox:SetAutoFocus(false)
kwBox:SetMaxLetters(120)
kwBox:SetText(GetSetting("customKeywords"))
kwBox:SetScript("OnEnterPressed", function()
    HOPAlertDB.customKeywords = this:GetText()
    cachedKeywordSource = nil
    this:ClearFocus()
end)
kwBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)

local nameLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
nameLabel:SetPoint("TOPLEFT", kwBox, "BOTTOMLEFT", -6, -12)
nameLabel:SetText("Players (comma separated, blank = anyone):")

local nameBox = CreateFrame("EditBox", "HOPAlertNameBox", settingsFrame, "InputBoxTemplate")
nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 6, -4)
nameBox:SetWidth(230)
nameBox:SetHeight(24)
nameBox:SetAutoFocus(false)
nameBox:SetMaxLetters(120)
nameBox:SetText(GetSetting("allowedNames"))
nameBox:SetScript("OnEnterPressed", function()
    HOPAlertDB.allowedNames = this:GetText()
    cachedNameSource = nil
    this:ClearFocus()
end)
nameBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)

local testBtn = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
testBtn:SetWidth(140)
testBtn:SetHeight(22)
testBtn:SetPoint("BOTTOM", settingsFrame, "BOTTOM", 0, 16)
testBtn:SetText("Test / Move Icon")
testBtn:SetScript("OnClick", function()
    lastSender = UnitName("player")
    ShowHOPIcon(UnitName("player"))
end)

settingsFrame:SetScript("OnHide", function()
    HOPAlertDB.allowedNames = nameBox:GetText()
    HOPAlertDB.customKeywords = kwBox:GetText()
    cachedKeywordSource = nil
    cachedNameSource = nil
end)

settingsFrame:SetScript("OnShow", function()
    cdOnlyCheck:SetChecked(GetSetting("cdReplyOnly"))
    lockCheck:SetChecked(GetSetting("locked"))
    durSlider:SetValue(GetSetting("displayTime"))
    durValue:SetText(tostring(GetSetting("displayTime")))
    failSlider:SetValue(GetSetting("failExtend") * 10)
    failValue:SetText(string.format("%.1f", GetSetting("failExtend")))
    sizeSlider:SetValue(GetSetting("iconSize"))
    sizeValue:SetText(tostring(GetSetting("iconSize")) .. "px")
    alphaSlider:SetValue(GetSetting("alpha"))
    alphaValue:SetText(tostring(GetSetting("alpha")) .. "%")
    nameBox:SetText(GetSetting("allowedNames"))
    kwBox:SetText(GetSetting("customKeywords"))
    UIDropDownMenu_SetSelectedValue(soundDropdown, GetSetting("soundIndex"))
    UIDropDownMenu_SetText(GetSoundLabel(), soundDropdown)
end)

-- ===== SLASH COMMANDS =====
local function ToggleSettings()
    if settingsFrame:IsShown() then
        settingsFrame:Hide()
    else
        settingsFrame:Show()
    end
end

SLASH_HOPALERT1 = "/hopalert"
SLASH_HOPALERT2 = "/hop"
SlashCmdList["HOPALERT"] = function(msg)
    if msg and string.lower(msg) == "test" then
        lastSender = UnitName("player")
        ShowHOPIcon(UnitName("player"))
    else
        ToggleSettings()
    end
end