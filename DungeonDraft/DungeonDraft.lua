-- DungeonDraft.lua (WoW 1.12)
-- Prototype UI for .draft command flow.

DungeonDraft_State = {
    phase = "idle",
    dungeon = nil,
    dungeonPage = 1,
    dungeonPageCount = 1,
    level = nil,
    options = {},
    lastSelectedSpec = nil,
    currentGearSlot = nil,
    gearRound = 0,
    gearTotalRounds = 0,
    statusText = "Idle",
}

local function DungeonDraft_Print(msg)
    if (DEFAULT_CHAT_FRAME) then
        DEFAULT_CHAT_FRAME:AddMessage("|cff7fd4ffDungeonDraft|r: " .. msg)
    end
end

local function DungeonDraft_Split(str, sep)
    local out = {}
    local from = 1
    local sepLen = string.len(sep)

    while true do
        local s, e = string.find(str, sep, from, true)
        if (not s) then
            table.insert(out, string.sub(str, from))
            break
        end
        table.insert(out, string.sub(str, from, s - 1))
        from = e + 1
    end

    return out
end

local function DungeonDraft_UpdateStaticTooltip(btn, opt)
    if (not btn or not btn.staticTooltip) then
        return
    end

    if (not opt or opt.kind ~= "GEAR" or not btn.itemId) then
        btn.staticTooltip:Hide()
        return
    end

    btn.staticTooltip:SetOwner(btn, "ANCHOR_NONE")
    btn.staticTooltip:ClearAllPoints()
    btn.staticTooltip:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -6)

    local shown = false
    local linkA = opt.itemString
    local linkB = btn.itemLink
    local linkC = "item:" .. btn.itemId .. ":0:0:0:0:0:0:0"

    if (linkA and linkA ~= "") then
        local ok = pcall(function() btn.staticTooltip:SetHyperlink(linkA) end)
        if (ok) then
            shown = true
        end
    end

    if ((not shown) and linkB and linkB ~= "") then
        local ok = pcall(function() btn.staticTooltip:SetHyperlink(linkB) end)
        if (ok) then
            shown = true
        end
    end

    if (not shown) then
        local ok = pcall(function() btn.staticTooltip:SetHyperlink(linkC) end)
        if (ok) then
            shown = true
        end
    end

    if (shown) then
        btn.staticTooltip:Show()
    else
        btn.staticTooltip:ClearLines()
        btn.staticTooltip:SetText(opt.name or "Item")
        btn.staticTooltip:AddLine("Loading item info...", 0.8, 0.8, 0.8, 1)
        btn.staticTooltip:Show()
    end
end

local function DungeonDraft_UpdateCards()
    if (not DungeonDraftFrame or not DungeonDraftFrame.cardButtons) then
        return
    end

    if (DungeonDraft_State.phase == "complete") then
        for i = 1, 3 do
            local btn = DungeonDraftFrame.cardButtons[i]
            if (btn.staticTooltip) then
                btn.staticTooltip:Hide()
            end
            btn:Hide()
        end
        DungeonDraftFrame.subtitle:SetText("Draft complete")
        DungeonDraftFrame.status:SetText(DungeonDraft_State.statusText or "Character created. Log out to character select and enter your draft character.")
        return
    end

    for i = 1, 3 do
        local btn = DungeonDraftFrame.cardButtons[i]
        local opt = DungeonDraft_State.options[i]
        if (opt) then
            btn.itemLink = nil
            btn.itemId = nil
            if (opt.kind == "GEAR") then
                btn.title:SetText("")
                btn.desc:SetText("")
                btn.icon:Hide()
                local itemId = tonumber(opt.id or "0")
                local itemString = opt.itemString
                if (itemId and itemId > 0) then
                    btn.itemId = itemId
                    local queryKey = itemString
                    if (not queryKey or queryKey == "") then
                        queryKey = itemId
                    end
                    local _, link, _, _, _, _, _, _, _, texture = GetItemInfo(queryKey)
                    if (texture) then
                        btn.icon:SetTexture(texture)
                    else
                        btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    end
                    if (itemString and itemString ~= "") then
                        btn.itemLink = itemString
                    elseif (link) then
                        btn.itemLink = link
                    else
                        btn.itemLink = "item:" .. itemId .. ":0:0:0:0:0:0:0"
                    end
                else
                    btn.itemLink = nil
                end

                DungeonDraft_UpdateStaticTooltip(btn, opt)
            else
                if (btn.staticTooltip) then
                    btn.staticTooltip:Hide()
                end
                btn.title:SetText(opt.name)
                btn.desc:SetText(opt.desc)
                btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                btn.icon:Show()
            end
            btn:Show()
        else
            btn.title:SetText("Waiting...")
            btn.desc:SetText("")
            btn.itemLink = nil
            btn.itemId = nil
            if (btn.staticTooltip) then
                btn.staticTooltip:Hide()
            end
            btn.icon:Hide()
            btn:Hide()
        end
    end

    local subtitle = "Phase: " .. (DungeonDraft_State.phase or "idle")
    if (DungeonDraft_State.dungeon and DungeonDraft_State.level) then
        subtitle = subtitle .. "  |  Dungeon: " .. DungeonDraft_State.dungeon .. "  |  Level: " .. DungeonDraft_State.level
    end
    if (DungeonDraft_State.phase == "dungeon") then
        subtitle = subtitle .. "  |  Page: " .. (DungeonDraft_State.dungeonPage or 1) .. "/" .. (DungeonDraft_State.dungeonPageCount or 1)
    end
    if (DungeonDraft_State.phase == "gear" and DungeonDraft_State.currentGearSlot) then
        subtitle = subtitle .. "  |  Slot: " .. DungeonDraft_State.currentGearSlot
    end
    DungeonDraftFrame.subtitle:SetText(subtitle)
    DungeonDraftFrame.status:SetText(DungeonDraft_State.statusText or "")

    if (DungeonDraftFrame.prevDungeonBtn and DungeonDraftFrame.nextDungeonBtn) then
        if (DungeonDraft_State.phase == "dungeon") then
            DungeonDraftFrame.prevDungeonBtn:Show()
            DungeonDraftFrame.nextDungeonBtn:Show()
        else
            DungeonDraftFrame.prevDungeonBtn:Hide()
            DungeonDraftFrame.nextDungeonBtn:Hide()
        end
    end
end

local function DungeonDraft_ResetOptions()
    DungeonDraft_State.options = {}
end

local function DungeonDraft_SetStatus(text)
    DungeonDraft_State.statusText = text or ""
    DungeonDraft_UpdateCards()
end

local function DungeonDraft_SetComplete(text)
    DungeonDraft_State.phase = "complete"
    DungeonDraft_State.currentGearSlot = nil
    DungeonDraft_State.gearRound = 0
    DungeonDraft_State.gearTotalRounds = 0
    DungeonDraft_State.options = {}
    DungeonDraft_State.statusText = text or "Character created. Log out to character select and enter your draft character."
    DungeonDraft_UpdateCards()
end

local function DungeonDraft_OnDraftMessage(msg)
    local payload = string.sub(msg, 7) -- remove "DRAFT:"
    local parts = DungeonDraft_Split(payload, "|")
    local kind = parts[1]

    if (kind == "BEGIN") then
        DungeonDraft_State.dungeon = parts[2]
        DungeonDraft_State.level = parts[4]
        if (parts[2] == "none") then
            DungeonDraft_State.phase = "dungeon"
            DungeonDraft_SetStatus("Draft started. Pick your dungeon.")
        end
        DungeonDraft_ResetOptions()
        DungeonDraft_UpdateCards()
        return
    end

    if (kind == "PHASE") then
        DungeonDraft_State.phase = parts[2] or "idle"
        DungeonDraft_ResetOptions()
        DungeonDraft_SetStatus("Phase changed: " .. DungeonDraft_State.phase)
        return
    end

    if (kind == "DUNGEON_PAGE") then
        DungeonDraft_State.dungeonPage = tonumber(parts[2] or "1") or 1
        DungeonDraft_State.dungeonPageCount = tonumber(parts[3] or "1") or 1
        DungeonDraft_ResetOptions()
        DungeonDraft_SetStatus("Pick your dungeon (" .. DungeonDraft_State.dungeonPage .. "/" .. DungeonDraft_State.dungeonPageCount .. ")")
        return
    end

    if (kind == "DUNGEON" or kind == "SPEC" or kind == "GEAR") then
        local idx = tonumber(parts[2] or "0")
        if (idx and idx >= 1 and idx <= 3) then
            DungeonDraft_State.options[idx] = {
                kind = kind,
                id = parts[3] or "",
                name = parts[4] or ("Option " .. idx),
                desc = parts[5] or "",
                itemString = parts[6] or ""
            }
            DungeonDraft_UpdateCards()
        end
        return
    end

    if (kind == "GEAR_SLOT") then
        DungeonDraft_State.currentGearSlot = parts[2] or "gear"
        DungeonDraft_State.gearRound = tonumber(parts[3] or "0") or 0
        DungeonDraft_State.gearTotalRounds = tonumber(parts[4] or "0") or 0
        DungeonDraft_SetStatus("Pick " .. DungeonDraft_State.currentGearSlot .. " (" .. DungeonDraft_State.gearRound .. "/" .. DungeonDraft_State.gearTotalRounds .. ")")
        return
    end

    if (kind == "SELECTED") then
        local selectionKind = parts[2] or ""
        local selectionName = parts[4] or parts[3] or "selection"
        if (selectionKind == "spec") then
            DungeonDraft_State.lastSelectedSpec = selectionName
            DungeonDraft_State.currentGearSlot = nil
            DungeonDraft_State.gearRound = 0
            DungeonDraft_State.gearTotalRounds = 0
        end
        if (selectionKind == "gear") then
            -- DRAFT:SELECTED|gear|slot|itemId|name
            local slotName = parts[3] or "gear"
            local itemName = parts[5] or selectionName
            DungeonDraft_SetStatus("Selected " .. slotName .. ": " .. itemName)
            return
        end
        DungeonDraft_SetStatus("Selected " .. selectionKind .. ": " .. selectionName)
        return
    end

    if (kind == "READY") then
        DungeonDraft_SetStatus(parts[2] or "Draft ready.")
        return
    end

    if (kind == "FINAL") then
        DungeonDraft_SetStatus("Finalized spec " .. (parts[4] or "?") .. " with " .. (parts[5] or "0") .. " gear picks")
        return
    end

    if (kind == "ERROR") then
        DungeonDraft_SetStatus("Error: " .. (parts[3] or "Unknown"))
        return
    end

    if (kind == "CHAR_CREATED") then
        local charName = parts[2] or "DraftChar"
        DungeonDraft_SetStatus("Character created: " .. charName)
        return
    end

    if (kind == "GEAR_APPLIED") then
        local applied = parts[2] or "0"
        local total = parts[3] or "0"
        DungeonDraft_SetStatus("Gear applied: " .. applied .. "/" .. total)
        return
    end

    if (kind == "SKILLS_PERSISTED") then
        DungeonDraft_SetStatus("Skills persisted: " .. (parts[2] or "0"))
        return
    end

    if (kind == "SPELLS") then
        DungeonDraft_SetStatus(parts[2] or "Spells updated.")
        return
    end

    if (kind == "NEXT") then
        DungeonDraft_SetComplete(parts[2] or "Character created. Log out to character select and enter your draft character.")
        return
    end

    if (kind == "CANCELLED") then
        DungeonDraft_State.phase = "idle"
        DungeonDraft_ResetOptions()
        DungeonDraft_SetStatus("Draft cancelled.")
        return
    end

    if (kind == "TODO") then
        DungeonDraft_SetStatus(parts[2] or "Server TODO step pending.")
    end
end

local function DungeonDraft_Send(command)
    SendChatMessage(command)
end

local function DungeonDraft_CreateUI()
    if (DungeonDraftFrame) then
        return
    end

    local f = CreateFrame("Frame", "DungeonDraftFrame", UIParent)
    f:SetWidth(820)
    f:SetHeight(420)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:SetScript("OnUpdate", function()
        if (not this:IsVisible()) then
            return
        end
        if (DungeonDraft_State.phase ~= "gear") then
            return
        end

        this.tooltipRefreshElapsed = (this.tooltipRefreshElapsed or 0) + (arg1 or 0)
        if (this.tooltipRefreshElapsed >= 0.75) then
            this.tooltipRefreshElapsed = 0
            DungeonDraft_UpdateCards()
        end
    end)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    })
    f:SetBackdropColor(0.07, 0.07, 0.10, 0.95)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.title:SetPoint("TOP", f, "TOP", 0, -18)
    f.title:SetText("Dungeon Draft")

    f.subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.subtitle:SetPoint("TOP", f.title, "BOTTOM", 0, -8)
    f.subtitle:SetText("Phase: idle")

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("TOP", f.subtitle, "BOTTOM", 0, -8)
    f.status:SetText("Use Start WC to begin a draft.")

    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    f.startBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.startBtn:SetWidth(92)
    f.startBtn:SetHeight(24)
    f.startBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 18)
    f.startBtn:SetText("Start")
    f.startBtn:SetScript("OnClick", function()
        DungeonDraft_Send(".draft start")
    end)

    f.statusBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.statusBtn:SetWidth(76)
    f.statusBtn:SetHeight(24)
    f.statusBtn:SetPoint("LEFT", f.startBtn, "RIGHT", 8, 0)
    f.statusBtn:SetText("Status")
    f.statusBtn:SetScript("OnClick", function()
        DungeonDraft_Send(".draft status")
    end)

    f.cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.cancelBtn:SetWidth(76)
    f.cancelBtn:SetHeight(24)
    f.cancelBtn:SetPoint("LEFT", f.statusBtn, "RIGHT", 8, 0)
    f.cancelBtn:SetText("Cancel")
    f.cancelBtn:SetScript("OnClick", function()
        DungeonDraft_Send(".draft cancel")
    end)

    f.prevDungeonBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.prevDungeonBtn:SetWidth(52)
    f.prevDungeonBtn:SetHeight(24)
    f.prevDungeonBtn:SetPoint("LEFT", f.cancelBtn, "RIGHT", 12, 0)
    f.prevDungeonBtn:SetText("Prev")
    f.prevDungeonBtn:SetScript("OnClick", function()
        DungeonDraft_Send(".draft page prev")
    end)
    f.prevDungeonBtn:Hide()

    f.nextDungeonBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.nextDungeonBtn:SetWidth(52)
    f.nextDungeonBtn:SetHeight(24)
    f.nextDungeonBtn:SetPoint("LEFT", f.prevDungeonBtn, "RIGHT", 6, 0)
    f.nextDungeonBtn:SetText("Next")
    f.nextDungeonBtn:SetScript("OnClick", function()
        DungeonDraft_Send(".draft page next")
    end)
    f.nextDungeonBtn:Hide()

    f.cardButtons = {}
    local cardTop = -96
    for i = 1, 3 do
        local b = CreateFrame("Button", nil, f)
        b:SetWidth(260)
        b:SetHeight(220)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 16 + ((i - 1) * 266), cardTop)
        b:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        b:SetBackdropColor(0.12, 0.14, 0.20, 0.92)
        b:SetBackdropBorderColor(0.35, 0.58, 1.0, 0.9)

        b.title = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.title:SetPoint("TOPLEFT", b, "TOPLEFT", 44, -10)
        b.title:SetPoint("TOPRIGHT", b, "TOPRIGHT", -8, -10)
        b.title:SetJustifyH("LEFT")
        b.title:SetText("Option " .. i)

        b.desc = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.desc:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -8)
        b.desc:SetPoint("RIGHT", b, "RIGHT", -8, 0)
        b.desc:SetJustifyH("LEFT")
        b.desc:SetJustifyV("TOP")
        b.desc:SetText("")

        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetWidth(28)
        b.icon:SetHeight(28)
        b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 10, -10)
        b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        b.icon:Hide()

        b.staticTooltip = CreateFrame("GameTooltip", "DungeonDraftCardTooltip" .. i, b, "GameTooltipTemplate")
        b.staticTooltip:SetOwner(b, "ANCHOR_NONE")
        b.staticTooltip:SetPoint("TOPLEFT", b, "TOPLEFT", 6, -6)
        b.staticTooltip:SetScale(0.80)
        b.staticTooltip:Hide()

        b.pickIndex = i
        b:SetScript("OnClick", function()
            DungeonDraft_Send(".draft pick " .. this.pickIndex)
        end)
        b:SetScript("OnEnter", function()
            this:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
        end)
        b:SetScript("OnLeave", function()
            this:SetBackdropBorderColor(0.35, 0.58, 1.0, 0.9)
            if (GameTooltip) then
                GameTooltip:Hide()
            end
        end)

        f.cardButtons[i] = b
    end

    DungeonDraftFrame = f
    DungeonDraft_UpdateCards()
end

local function DungeonDraft_OnEvent()
    if (event == "CHAT_MSG_SYSTEM" and arg1) then
        if (string.sub(arg1, 1, 6) == "DRAFT:") then
            DungeonDraft_OnDraftMessage(arg1)
        end
    end
end

local DungeonDraft_EventFrame = CreateFrame("Frame", "DungeonDraftEventFrame")
DungeonDraft_EventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
DungeonDraft_EventFrame:SetScript("OnEvent", DungeonDraft_OnEvent)

local function DungeonDraft_Toggle()
    DungeonDraft_CreateUI()
    if (DungeonDraftFrame:IsVisible()) then
        DungeonDraftFrame:Hide()
    else
        DungeonDraftFrame:Show()
    end
end

SLASH_DUNGEONDRAFT1 = "/dungeondraft"
SLASH_DUNGEONDRAFT2 = "/dd"
SlashCmdList["DUNGEONDRAFT"] = function(msg)
    msg = msg or ""
    if (msg == "start") then
        DungeonDraft_Send(".draft start")
        return
    end
    if (msg == "status") then
        DungeonDraft_Send(".draft status")
        return
    end
    DungeonDraft_Toggle()
end

DungeonDraft_Print("loaded. Use /dd to open draft panel.")
