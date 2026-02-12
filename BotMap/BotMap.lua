-- BotMap.lua (WoW 1.12)
-- Requests bot positions from the server and draws pins on the world map.

BotMap_State = {
    enabled = true,
    debug = false,
    refreshSeconds = 60,
    timeSince = 0,
    awaiting = false,
    awaitingSince = 0,
    awaitingTimeoutSeconds = 10,
    currentZoneText = nil,
    pins = {},
    visiblePins = 0,
    chatFilterInstalled = false,
}

-- WoW 1.12 uses Lua 5.0: no string.match(). Use string.find() captures instead.
local function BotMap_Capture1(str, pattern)
    local _, _, cap1 = string.find(str, pattern)
    return cap1
end

local BOTMAP_CLASS_NAMES = {
    [1] = "Warrior",
    [2] = "Paladin",
    [3] = "Hunter",
    [4] = "Rogue",
    [5] = "Priest",
    [7] = "Shaman",
    [8] = "Mage",
    [9] = "Warlock",
    [11] = "Druid",
}

local BOTMAP_CLASS_COLORS = {
    [1] = "C79C6E", -- Warrior
    [2] = "F58CBA", -- Paladin
    [3] = "ABD473", -- Hunter
    [4] = "FFF569", -- Rogue
    [5] = "FFFFFF", -- Priest
    [7] = "0070DE", -- Shaman
    [8] = "69CCF0", -- Mage
    [9] = "9482C9", -- Warlock
    [11] = "FF7D0A", -- Druid
}

local function BotMap_ColorizeClassName(classId, className)
    local hex = BOTMAP_CLASS_COLORS[classId]
    if (not hex) then
        return className
    end
    return "|cff" .. hex .. className .. "|r"
end

local function BotMap_TeamName(teamId)
    -- In vanilla client API, we just present a friendly label.
    -- We treat 0 as Alliance, 1 as Horde (common server convention).
    if (teamId == 1) then
        return "Horde"
    end
    return "Alliance"
end

local function BotMap_ApplyTeamColor(pin, teamId)
    if (not pin or not pin.texture) then
        return
    end

    -- teamId convention from server: 0=Alliance, 1=Horde
    if (teamId == 1) then
        -- Horde red
        pin.texture:SetVertexColor(1.0, 0.2, 0.2)
    else
        -- Alliance blue
        pin.texture:SetVertexColor(0.2, 0.4, 1.0)
    end
end

local function BotMap_FormatTooltip(pin)
    if (not pin or not pin.bot) then
        return nil
    end

    local b = pin.bot
    local className = BOTMAP_CLASS_NAMES[b.classId] or ("Class " .. (b.classId or "?"))
    local classText = BotMap_ColorizeClassName(b.classId, className)
    local teamName = BotMap_TeamName(b.teamId)
    local lvl = b.level or "?"
    return b.name, lvl .. " " .. classText .. " - " .. teamName
end

local function BotMap_ShowPinTooltip(pin)
    local line1, line2 = BotMap_FormatTooltip(pin)
    if (not line1) then
        line1 = "BotMap"
        line2 = nil
    end

    local tt = WorldMapTooltip or GameTooltip
    if (not tt) then
        return
    end

    if (tt.ClearLines) then
        tt:ClearLines()
    end
    -- Questie-style: explicit world map tooltip with fixed anchor.
    tt:SetOwner(pin, "ANCHOR_NONE")
    tt:ClearAllPoints()
    tt:SetPoint("BOTTOMLEFT", pin, "TOPRIGHT", 10, 6)
    tt:AddLine(line1, 1, 1, 1)
    if (line2) then
        -- Tooltip header is naturally larger than body text in default UI.
        tt:AddLine(line2, 0.85, 0.85, 0.85)
    end
    if (tt.SetFrameStrata) then
        tt:SetFrameStrata("FULLSCREEN_DIALOG")
    end
    if (tt.SetFrameLevel and pin.GetFrameLevel) then
        tt:SetFrameLevel(pin:GetFrameLevel() + 100)
    end
    tt:Show()
end

local function BotMap_HidePinTooltip()
    local tt1 = WorldMapTooltip
    if (tt1) then tt1:Hide() end
    local tt2 = GameTooltip
    if (tt2 and tt2 ~= tt1) then tt2:Hide() end
end

local function BotMap_Print(msg)
    if (DEFAULT_CHAT_FRAME) then
        DEFAULT_CHAT_FRAME:AddMessage("BotMap: " .. msg)
    end
end

local function BotMap_Debug(msg)
    if (BotMap_State and BotMap_State.debug) then
        BotMap_Print(msg)
    end
end

local function BotMap_IsBotMapCommandMessage(msg)
    if (not msg) then
        return false
    end
    -- Message content for CHAT_MSG_* events is the raw text, not "You say:"
    return (string.sub(msg, 1, 7) == ".botmap")
end

local function BotMap_IsBotMapSystemMessage(msg)
    if (not msg) then
        return false
    end
    return (string.sub(msg, 1, 7) == "BOTMAP:")
end

local function BotMap_InstallChatFilter()
    if (BotMap_State.chatFilterInstalled) then
        return
    end

    -- Vanilla doesn't have ChatFrame_AddMessageEventFilter; hook ChatFrame_OnEvent to suppress display spam.
    local orig = ChatFrame_OnEvent
    if (type(orig) ~= "function") then
        return
    end

    ChatFrame_OnEvent = function(event)
        -- If debug enabled, don't suppress anything.
        if (BotMap_State and BotMap_State.debug) then
            return orig(event)
        end

        local msg = arg1

        -- Hide server dump lines in chat frames (we still parse them in BotMapFrame).
        if (event == "CHAT_MSG_SYSTEM" and BotMap_IsBotMapSystemMessage(msg)) then
            return
        end

        -- Hide our outgoing ".botmap ..." command echo in chat frames.
        if ((event == "CHAT_MSG_SAY" or event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" or event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_CHANNEL")
            and BotMap_IsBotMapCommandMessage(msg)) then
            return
        end

        return orig(event)
    end

    BotMap_State.chatFilterInstalled = true
end

local function BotMap_GetViewedZoneText()
    local zoneIndex = GetCurrentMapZone()
    local continentIndex = GetCurrentMapContinent()

    if (zoneIndex == nil or continentIndex == nil) then
        return nil
    end

    if (zoneIndex == 0) then
        return nil -- continent/world view: not supported yet
    end

    local zones = { GetMapZones(continentIndex) }
    local zoneText = zones[zoneIndex]
    return zoneText
end

local function BotMap_WorldToMapXY(zoneText, worldX, worldY)
    if (not BotMap_ZoneData or not zoneText) then
        return nil, nil
    end

    local data = BotMap_ZoneData[zoneText]
    if (not data) then
        return nil, nil
    end

    local mapY = (data.maxX - worldX) / (data.maxX - data.minX)
    local mapX = (data.maxY - worldY) / (data.maxY - data.minY)

    if (mapX < 0 or mapX > 1 or mapY < 0 or mapY > 1) then
        return nil, nil
    end

    return mapX, mapY
end

local function BotMap_ClearPins()
    BotMap_State.visiblePins = 0
    BotMap_HidePinTooltip()

    for _, pin in pairs(BotMap_State.pins) do
        pin.bot = nil
        pin:Hide()
        if (pin.texture) then
            -- reset to neutral in case reused
            pin.texture:SetVertexColor(1.0, 1.0, 1.0)
        end
    end
end

local function BotMap_GetOrCreatePin(i)
    local pin = BotMap_State.pins[i]
    if (pin) then
        return pin
    end

    local parent = WorldMapButton or WorldMapDetailFrame or WorldMapFrame
    -- Use a Button to ensure mouseover works reliably in 1.12
    pin = CreateFrame("Button", "BotMapPin" .. i, parent)
    pin:SetFrameStrata("TOOLTIP")
    pin:SetFrameLevel(1000)
    pin:SetWidth(16)
    pin:SetHeight(16)
    pin:EnableMouse(true)
    if (pin.SetHitRectInsets) then
        pin:SetHitRectInsets(-2, -2, -2, -2)
    end
    pin.texture = pin:CreateTexture(nil, "ARTWORK")
    pin.texture:SetAllPoints(pin)
    -- Use a known world map icon texture in 1.12
    pin.texture:SetTexture("Interface\\WorldMap\\WorldMapPartyIcon")
    pin.texture:SetVertexColor(1.0, 1.0, 1.0)
    pin:SetScript("OnEnter", function()
        BotMap_ShowPinTooltip(pin)
    end)
    pin:SetScript("OnLeave", function()
        BotMap_HidePinTooltip()
    end)
    pin:Hide()

    BotMap_State.pins[i] = pin
    return pin
end

local function BotMap_PlacePin(i, mapX, mapY)
    local pin = BotMap_GetOrCreatePin(i)
    pin:ClearAllPoints()

    local mapFrame = WorldMapButton or WorldMapDetailFrame
    if (not mapFrame) then
        return
    end

    local width = mapFrame:GetWidth()
    local height = mapFrame:GetHeight()
    if (not width or not height or width <= 0 or height <= 0) then
        return
    end

    pin:SetPoint("CENTER", mapFrame, "TOPLEFT", mapX * width, -mapY * height)
    pin:Show()
end

local function BotMap_RequestUpdate()
    local zoneText = BotMap_GetViewedZoneText()
    BotMap_State.currentZoneText = zoneText

    BotMap_ClearPins()

    if (not zoneText) then
        return
    end

    -- GM command; server should respond with BOTMAP:* lines
    BotMap_State.awaiting = true
    BotMap_State.awaitingSince = 0
    SendChatMessage(".botmap \"" .. zoneText .. "\"")
end

function BotMap_OnLoad()
    this:RegisterEvent("WORLD_MAP_UPDATE")
    this:RegisterEvent("CHAT_MSG_SYSTEM")
    BotMap_InstallChatFilter()
    BotMap_Print("loaded (refresh " .. BotMap_State.refreshSeconds .. "s)")
end

function BotMap_OnEvent(event, arg1)
    if (event == "WORLD_MAP_UPDATE") then
        -- Refresh immediately when entering a zone map view
        if (WorldMapFrame and WorldMapFrame:IsVisible()) then
            BotMap_State.timeSince = BotMap_State.refreshSeconds
        end
        return
    end

    if (event == "CHAT_MSG_SYSTEM" and arg1) then
        -- Parse server output
        if (string.sub(arg1, 1, 7) ~= "BOTMAP:") then
            return
        end

        if (string.sub(arg1, 1, 12) == "BOTMAP:BEGIN") then
            BotMap_ClearPins()
            BotMap_State.awaiting = true
            BotMap_State.awaitingSince = 0
            return
        end

        if (string.sub(arg1, 1, 10) == "BOTMAP:END") then
            BotMap_State.awaiting = false
            BotMap_State.awaitingSince = 0
            return
        end

        if (string.sub(arg1, 1, 10) == "BOTMAP:BOT") then
            local zoneText = BotMap_State.currentZoneText
            if (not zoneText) then
                return
            end

            -- Example:
            -- BOTMAP:BOT name=Bot map=0 x=-5000.00 y=1000.00 z=200.00 lvl=12 class=1 race=3 team=0
            local name = BotMap_Capture1(arg1, " name=([^%s]+)")
            local x = BotMap_Capture1(arg1, " x=([%-%.%d]+)")
            local y = BotMap_Capture1(arg1, " y=([%-%.%d]+)")
            local lvl = BotMap_Capture1(arg1, " lvl=(%d+)")
            local classId = BotMap_Capture1(arg1, " class=(%d+)")
            local teamId = BotMap_Capture1(arg1, " team=(%d+)")

            if (not name or not x or not y) then
                return
            end

            local worldX = tonumber(x)
            local worldY = tonumber(y)
            if (not worldX or not worldY) then
                return
            end

            local mapX, mapY = BotMap_WorldToMapXY(zoneText, worldX, worldY)
            if (not mapX or not mapY) then
                return
            end

            -- Place pin and attach metadata.
            BotMap_State.visiblePins = BotMap_State.visiblePins + 1
            local idx = BotMap_State.visiblePins
            BotMap_PlacePin(idx, mapX, mapY)

            local pin = BotMap_State.pins[idx]
            if (pin) then
                pin.bot = {
                    name = name,
                    level = tonumber(lvl) or nil,
                    classId = tonumber(classId) or nil,
                    teamId = tonumber(teamId) or 0,
                }
                BotMap_ApplyTeamColor(pin, pin.bot.teamId)
            end
        end
    end
end

function BotMap_OnUpdate(elapsed)
    if (not BotMap_State.enabled) then
        return
    end

    if (not WorldMapFrame or not WorldMapFrame:IsVisible()) then
        return
    end

    BotMap_State.timeSince = BotMap_State.timeSince + (elapsed or 0)
    if (BotMap_State.timeSince < BotMap_State.refreshSeconds) then
        -- Even if we aren't refreshing yet, make sure "awaiting" can recover.
        if (BotMap_State.awaiting) then
            BotMap_State.awaitingSince = BotMap_State.awaitingSince + (elapsed or 0)
            if (BotMap_State.awaitingSince >= BotMap_State.awaitingTimeoutSeconds) then
                BotMap_Debug("server response timed out; resuming requests")
                BotMap_State.awaiting = false
                BotMap_State.awaitingSince = 0
            end
        end
        return
    end

    BotMap_State.timeSince = 0

    -- avoid spamming requests if server hasn't answered
    if (BotMap_State.awaiting) then
        BotMap_State.awaitingSince = BotMap_State.awaitingSince + (elapsed or 0)
        if (BotMap_State.awaitingSince >= BotMap_State.awaitingTimeoutSeconds) then
            BotMap_Debug("server response timed out; resuming requests")
            BotMap_State.awaiting = false
            BotMap_State.awaitingSince = 0
        end
        return
    end

    BotMap_RequestUpdate()
end

-- Slash command:
-- /botmap debug   (toggle)
-- /botmap debug on|off
SLASH_BOTMAP1 = "/botmap"
SlashCmdList["BOTMAP"] = function(msg)
    msg = msg or ""
    -- trim
    while (string.sub(msg, 1, 1) == " ") do msg = string.sub(msg, 2) end
    while (string.sub(msg, -1) == " ") do msg = string.sub(msg, 1, -2) end

    if (msg == "debug") then
        BotMap_State.debug = not BotMap_State.debug
        BotMap_Print("debug " .. (BotMap_State.debug and "ON" or "OFF"))
        return
    end
    if (msg == "debug on") then
        BotMap_State.debug = true
        BotMap_Print("debug ON")
        return
    end
    if (msg == "debug off") then
        BotMap_State.debug = false
        BotMap_Print("debug OFF")
        return
    end

    BotMap_Print("commands: /botmap debug | /botmap debug on|off")
end
