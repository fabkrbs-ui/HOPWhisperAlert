-- Simple, lightweight HoP whisper alert for 1.12.1

local HOP_ICON_PATH = "Interface\\Icons\\Spell_Holy_SealOfProtection"
local DISPLAY_TIME = 4  -- seconds to keep the icon visible after a trigger
local HOP_SOUND = "RaidWarning"  -- default client sound (lightweight)

-- Main frame for the icon
local HOPAlertFrame = CreateFrame("Frame", "HOPAlertFrame", UIParent)
HOPAlertFrame:SetWidth(64)   -- smaller icon
HOPAlertFrame:SetHeight(64)  -- smaller icon
HOPAlertFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
HOPAlertFrame:SetMovable(true)
HOPAlertFrame:EnableMouse(true)
HOPAlertFrame:RegisterForDrag("LeftButton")
HOPAlertFrame:SetClampedToScreen(true)
HOPAlertFrame:SetAlpha(0.9) -- more transparent

-- Drag handling
HOPAlertFrame:SetScript("OnDragStart", function()
    if not this.isLocked then
        this:StartMoving()
    end
end)

HOPAlertFrame:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
end)

-- Texture for the icon
local icon = HOPAlertFrame:CreateTexture(nil, "BACKGROUND")
icon:SetAllPoints(HOPAlertFrame)
icon:SetTexture(HOP_ICON_PATH)

-- Hide by default
HOPAlertFrame:Hide()

-- Timer for auto-hide
local remaining = 0

local function ShowHOPIcon()
    remaining = DISPLAY_TIME
    HOPAlertFrame:Show()
    -- Play lightweight built-in sound
    if PlaySound then
        PlaySound(HOP_SOUND)
    end
end

-- Separate frame to handle the timer OnUpdate
local timerFrame = CreateFrame("Frame")
timerFrame:SetScript("OnUpdate", function()
    -- In 1.12, elapsed time is in arg1
    if remaining > 0 and HOPAlertFrame:IsShown() then
        remaining = remaining - arg1
        if remaining <= 0 then
            remaining = 0
            HOPAlertFrame:Hide()
        end
    end
end)

-- Event frame to listen for whispers
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER")

eventFrame:SetScript("OnEvent", function()
    -- Vanilla 1.12 event args: arg1 = message, arg2 = author, etc.
    if event == "CHAT_MSG_WHISPER" then
        local msg = arg1
        if msg and type(msg) == "string" then
            local lowerMsg = string.lower(msg)
            if string.find(lowerMsg, "hand of protection", 1, true) or
               string.find(lowerMsg, "hop", 1, true) then
                ShowHOPIcon()
            end
        end
    end
end)

-- Optional: simple slash command to test the icon manually
SLASH_HOPALERT1 = "/hopalert"
SlashCmdList["HOPALERT"] = function()
    ShowHOPIcon()
end