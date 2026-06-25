-- AzerothCIMI: client bridge between AzerothCore mod-transmog and CanIMogIt.
-- mod-transmog sends collected item IDs via TRANSMOG_SYNC system messages (.transmog sync).

AzerothCIMICollection = AzerothCIMICollection or {}

local collection = AzerothCIMICollection
local syncInProgress = false
local syncEndPending = false

local function GetItemID(item)
    if type(item) == "number" then
        return item
    end
    if type(item) == "string" then
        return tonumber(item:match("item:(%d+)"))
    end
end

local function HasAppearance(itemID)
    return itemID and collection[itemID] == true
end

local function AddAppearance(itemID)
    itemID = tonumber(itemID)
    if not itemID or collection[itemID] then
        return false
    end
    collection[itemID] = true
    return true
end

local function InvalidateCanIMogItCache()
    if CanIMogIt and CanIMogIt.ResetCache then
        CanIMogIt:ResetCache()
    end
end

local function FinishSyncBatch()
    if not syncEndPending then
        return
    end
    syncEndPending = false
    syncInProgress = false
    InvalidateCanIMogItCache()
end

local function ScheduleSyncBatchEnd()
    syncEndPending = true
    C_Timer.After(1.5, FinishSyncBatch)
end

local function BeginSyncBatch()
    if not syncInProgress then
        wipe(collection)
        syncInProgress = true
    end
    ScheduleSyncBatchEnd()
end

local function OnSyncItem(itemID)
    BeginSyncBatch()
    collection[tonumber(itemID)] = true
    ScheduleSyncBatchEnd()
end

local function ParseItemIDFromChat(msg)
    return tonumber(msg:match("Hitem:(%d+)"))
end

-- Override CanIMogIt compat stubs with mod-transmog collection data.
local function InstallTransmogAPI()
    C_TransmogCollection = C_TransmogCollection or {}

    function C_TransmogCollection.GetItemInfo(item)
        local itemID = GetItemID(item)
        if not itemID then
            return
        end
        return itemID, itemID
    end

    function C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
        if not sourceID then
            return
        end
        local itemLink = "item:" .. sourceID .. ":0:0:0:0:0:0:0:0"
        return {
            itemLink = itemLink,
            itemAppearanceID = sourceID,
            sourceID = sourceID,
        }
    end

    function C_TransmogCollection.GetAppearanceInfoBySource(sourceID)
        if not sourceID then
            return
        end
        return {
            appearanceID = sourceID,
            sourceID = sourceID,
            isCollected = HasAppearance(sourceID),
        }
    end

    function C_TransmogCollection.GetAllAppearanceSources(appearanceID)
        if not appearanceID then
            return
        end
        return { appearanceID }
    end

    function C_TransmogCollection.GetAppearanceSources()
    end

    function C_TransmogCollection.PlayerHasTransmog(itemID)
        return HasAppearance(GetItemID(itemID))
    end

    function C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID)
        return HasAppearance(sourceID)
    end

    function C_TransmogCollection.PlayerCanCollectSource(sourceID)
        if not sourceID then
            return false, false
        end
        if HasAppearance(sourceID) then
            return true, false
        end
        return true, true
    end
end

local function RequestServerSync()
    SendChatMessage(".transmog sync")
end

local function OnPlayerEquipmentChanged(_, slot)
    local itemID = GetInventoryItemID("player", slot)
    if AddAppearance(itemID) then
        InvalidateCanIMogItCache()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        InstallTransmogAPI()
        C_Timer.After(3, RequestServerSync)
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        OnPlayerEquipmentChanged(nil, ...)
    end
end)

ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
    local syncItemID = msg:match("^TRANSMOG_SYNC:(%d+)$")
    if syncItemID then
        OnSyncItem(syncItemID)
        return true
    end

    if msg:find("appearance collection") then
        local itemID = ParseItemIDFromChat(msg)
        if itemID and AddAppearance(itemID) then
            InvalidateCanIMogItCache()
        end
    end
end)

SLASH_ACIMI1 = "/acimi"
SLASH_ACIMI2 = "/azerothcimi"
SlashCmdList["ACIMI"] = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$"):lower()
    if msg == "sync" or msg == "" then
        RequestServerSync()
        print("|cff33a6d2AzerothCIMI:|r синхронизация коллекции с сервером...")
    elseif msg == "count" then
        local count = 0
        for _ in pairs(collection) do
            count = count + 1
        end
        print("|cff33a6d2AzerothCIMI:|r изучено обликов: " .. count)
    else
        print("|cff33a6d2AzerothCIMI:|r /acimi sync — синхронизация, /acimi count — количество")
    end
end

InstallTransmogAPI()
