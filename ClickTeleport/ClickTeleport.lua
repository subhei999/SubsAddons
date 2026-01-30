-- ClickTeleport.lua
-- Data is loaded from ClickTeleport_Data.lua which defines ClickTeleport_ZoneData

function ClickTeleport_OnLoad()
    this:RegisterEvent("WORLD_MAP_UPDATE");
    
    DEFAULT_CHAT_FRAME:AddMessage("ClickTeleport: OnLoad fired!");

    -- Try hooking the widget directly for more reliability
    if (WorldMapButton) then
        local oldScript = WorldMapButton:GetScript("OnClick");
        WorldMapButton:SetScript("OnClick", function()
            -- Debug print for ANY click
            DEFAULT_CHAT_FRAME:AddMessage("ClickTeleport: Map Clicked!");
            
            if (IsControlKeyDown()) then
                ClickTeleport_OnClick();
            else
                if (oldScript) then
                    oldScript();
                end
            end
        end);
        DEFAULT_CHAT_FRAME:AddMessage("ClickTeleport: Hooked WorldMapButton via SetScript.");
    else
        DEFAULT_CHAT_FRAME:AddMessage("ClickTeleport Error: WorldMapButton frame not found!");
    end
end

function ClickTeleport_OnEvent(event)
    -- Potentially track current zone if needed, but GetZoneText() works usually if on map of current zone.
    -- If viewing another zone, we need GetMapInfo() or similar.
end

function ClickTeleport_OnClick()
    DEFAULT_CHAT_FRAME:AddMessage("ClickTeleport: ClickTeleport_OnClick Triggered!");
    -- Get Cursor Position relative to the map frame
    local x, y = GetCursorPosition();
    local centerX, centerY = WorldMapDetailFrame:GetCenter();
    local width = WorldMapDetailFrame:GetWidth();
    local height = WorldMapDetailFrame:GetHeight();
    local adjustedX = (x / WorldMapDetailFrame:GetEffectiveScale()) - (centerX - (width/2));
    local adjustedY = (centerY + (height/2)) - (y / WorldMapDetailFrame:GetEffectiveScale());
    
    -- Normalized 0-1 coordinates
    local mapX = adjustedX / width;
    local mapY = adjustedY / height; -- This might be inverted, verification needed. Usually Y grows down in UI.
    

    if (mapX < 0 or mapX > 1 or mapY < 0 or mapY > 1) then
        return; -- Clicked outside map
    end
    
    -- Current viewed Zone Name
    local zoneIndex = GetCurrentMapZone();
    local continentIndex = GetCurrentMapContinent();
    
    local data = nil;
    local nameForChat = "";

    -- Continent View (Zone 0)
    if (zoneIndex == 0) then
        
        local targetMapID = 0; -- Default EK
        if (continentIndex == 1) then targetMapID = 1; end -- If 1 is Kalimdor
        if (continentIndex == 2) then targetMapID = 0; end -- If 2 is EK
        
        -- Note: This is an assumption. Ideally we check the name.
        local continents = { GetMapContinents() };
        local contName = continents[continentIndex];
        
        if (contName == "Kalimdor") then targetMapID = 1; end
        if (contName == "Eastern Kingdoms") then targetMapID = 0; end
        
        data = { maxX=17066.6667, minX=-17066.6667, maxY=17066.6667, minY=-17066.6667, mapID=targetMapID };
        
        nameForChat = contName;
    else
        -- Regular Zone View
        local zones = { GetMapZones(continentIndex) };
        local zoneText = zones[zoneIndex];
        
        nameForChat = zoneText;
        
        -- Check global table
        if (ClickTeleport_ZoneData) then
            data = ClickTeleport_ZoneData[zoneText];
        end
    end
    
    if (not data) then
        DEFAULT_CHAT_FRAME:AddMessage("ClickTeleport: No data for " .. nameForChat);
        return;
    end
    
    -- Calculate World Coords
    -- WorldX (North-South) = MaxX - (mapY * (MaxX - MinX))
    local worldX = data.maxX - (mapY * (data.maxX - data.minX));
    
    -- WorldY (West-East) = MaxY - (mapX * (MaxY - data.minY))
    local worldY = data.maxY - (mapX * (data.maxY - data.minY));
    
    DEFAULT_CHAT_FRAME:AddMessage("Teleporting to " .. nameForChat .. ": " .. string.format("%.1f, %.1f", worldX, worldY) .. " (Map " .. data.mapID .. ")");
    SendChatMessage(".go xy " .. worldX .. " " .. worldY .. " " .. data.mapID);
end
