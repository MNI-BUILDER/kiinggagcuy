-- KING LEGACY MONITOR - Black Market Fruit Stock -> /api/stocks/kinglegacy
-- Path: PlayerGui.MainGui -> (recursive) FruitFrame -> ScrollingFrame -> <FruitName>
print("👑 Starting King Legacy Monitor (Black Market Stock)...")

-- Configuration
local API_ENDPOINT     = "http://204.12.233.39:3000/api/stocks/kinglegacy"
local DELETE_ENDPOINT  = "http://204.12.233.39:3000/api/stocks/kinglegacy"
local API_KEY          = "GAMERSBERGGAG"
local DISCORD_WEBHOOK  = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"
local CHECK_INTERVAL   = 1
local HEARTBEAT_INTERVAL = 10
local DISCORD_UPDATE_INTERVAL = 300

local HttpService = game:GetService("HttpService")
local LocalPlayer = game.Players.LocalPlayer

-- Session and Cache
local Cache = {
    sessionId = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
    updateCounter = 0,
    lastHeartbeat = 0,
    lastDiscordUpdate = 0,
    fruits = {},
    restock = ""
}

-- UI element patterns to ignore
local IGNORE_PATTERNS = {
    "_padding", "padding", "uilistlayout", "uigridlayout", "uipadding",
    "uicorner", "uistroke", "uigradient", "uiaspectratioconstraint",
    "u: ", "shadow", "bevel", "template", "example", "search"
}

local function shouldIgnoreItem(itemName)
    local lowerName = string.lower(itemName)
    for _, pattern in ipairs(IGNORE_PATTERNS) do
        if lowerName:match(pattern) then return true end
    end
    return false
end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- STRIP ROBLOX RICH TEXT: <font size='15'>$</font>1,700,000 -> $1,700,000
-- This is the fix: without it, the "15" inside size='15' gets read as the stock.
local function stripRichText(s)
    s = tostring(s or "")
    s = s:gsub("<[^<>]*>", "")            -- kill every tag
    s = s:gsub("&quot;", '"'):gsub("&apos;", "'")
    s = s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
    return trim(s)
end

-- Grab a named TextLabel/TextButton's text from an item entry (RAW, tags intact)
local function readText(entry, childName)
    local direct = entry:FindFirstChild(childName)
    if direct and (direct:IsA("TextLabel") or direct:IsA("TextButton")) then
        return trim(direct.Text)
    end
    for _, d in ipairs(entry:GetDescendants()) do
        if d.Name == childName and (d:IsA("TextLabel") or d:IsA("TextButton")) then
            return trim(d.Text)
        end
    end
    return ""
end

-- Discord notification
local function sendToDiscord(content, isError)
    pcall(function()
        local message = {
            content = isError and "💥 **ERROR**" or "📊 **UPDATE**",
            embeds = {{
                description = content,
                color = isError and 16711680 or 65280,
                footer = {text = "Session: " .. Cache.sessionId},
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }}
        }
        request({
            Url = DISCORD_WEBHOOK,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode(message)
        })
    end)
end

-- AUTO-DELETE function
local function autoDeleteOnCrash()
    pcall(function()
        request({
            Url = DELETE_ENDPOINT,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = API_KEY,
                ["X-Session-ID"] = Cache.sessionId
            },
            Body = HttpService:JSONEncode({
                action = "DELETE_ALL",
                sessionId = Cache.sessionId,
                playerName = LocalPlayer.Name,
                timestamp = os.time()
            })
        })
    end)
end

local function getMainGui()
    return LocalPlayer:FindFirstChild("PlayerGui")
        and LocalPlayer.PlayerGui:FindFirstChild("MainGui")
end

-- Locate the black market ScrollingFrame, wherever MainGui hides it.
local function findFruitContainer()
    local mainGui = getMainGui()
    if not mainGui then return nil end

    local fruitFrame = mainGui:FindFirstChild("FruitFrame", true)
    if fruitFrame then
        local scroll = fruitFrame:FindFirstChildWhichIsA("ScrollingFrame")
        if scroll then return scroll end
        for _, d in ipairs(fruitFrame:GetDescendants()) do
            if d:IsA("ScrollingFrame") then return d end
        end
        return fruitFrame
    end

    for _, d in ipairs(mainGui:GetDescendants()) do
        if d:IsA("ScrollingFrame") then
            local pname = string.lower(d.Parent and d.Parent.Name or "")
            if pname:match("fruit") or pname:match("market") or pname:match("shop") then
                return d
            end
        end
    end
    return nil
end

-- RESTOCK TIMER: "Time Until Restock: 03:16:04"
local function getRestockTimer()
    local timerText, seconds = "", 0
    pcall(function()
        local mainGui = getMainGui()
        if not mainGui then return end
        for _, d in ipairs(mainGui:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                local clean = stripRichText(d.Text)
                if string.lower(clean):match("restock") then
                    local h, m, s = clean:match("(%d+):(%d+):(%d+)")
                    if h then
                        timerText = h .. ":" .. m .. ":" .. s
                        seconds = tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
                        return
                    end
                    local m2, s2 = clean:match("(%d+):(%d+)")
                    if m2 then
                        timerText = m2 .. ":" .. s2
                        seconds = tonumber(m2) * 60 + tonumber(s2)
                        return
                    end
                end
            end
        end
    end)
    return timerText, seconds
end

-- STATUS PARSER
-- King Legacy has no quantities. Status is either a price ($1,700,000) or "Out of Stock".
-- So: inStock = a price is present. price = the number. stock = 1/0 for API compatibility.
local function parseStatus(rawStatus)
    local clean = stripRichText(rawStatus)
    local lower = string.lower(clean)

    if lower:match("out%s*of%s*stock") or lower:match("sold")
        or lower:match("unavailable") or lower == "" then
        return clean, false, 0
    end

    -- strip $ and commas, then read the number: "$1,700,000" -> 1700000
    local digits = clean:gsub("[^%d]", "")
    local price = tonumber(digits)

    if price and price > 0 then
        return clean, true, price
    end

    return clean, false, 0
end

-- SINGLE-PASS scrape of the black market list
local function collectBlackMarket()
    local result = {}
    local ok = pcall(function()
        local container = findFruitContainer()
        if not container then return end

        for _, entry in ipairs(container:GetChildren()) do
            if entry:IsA("GuiObject") and not shouldIgnoreItem(entry.Name) then
                local rawStatus  = readText(entry, "Status")
                local statusText, inStock, price = parseStatus(rawStatus)
                local displayName = stripRichText(readText(entry, "TextLabel"))
                local tierText    = stripRichText(readText(entry, "Tier"))

                result[entry.Name] = {
                    name    = (displayName ~= "" and displayName or entry.Name),
                    tier    = tierText,
                    status  = statusText,      -- "Out of Stock" or "$1,700,000"
                    price   = price,           -- 0 when out of stock
                    inStock = inStock,
                    listed  = entry.Visible,   -- is it shown in this restock's list
                    stock   = inStock and 1 or 0
                }
            end
        end
    end)
    if not ok then return {} end
    return result
end

-- COLLECT ALL DATA
local function collectAllData()
    local fruits = collectBlackMarket()
    local restockText, restockSeconds = getRestockTimer()

    local data = {
        sessionId    = Cache.sessionId,
        timestamp    = os.time(),
        updateNumber = Cache.updateCounter + 1,
        playerName   = LocalPlayer.Name,
        userId       = LocalPlayer.UserId,
        game         = "kinglegacy",
        shop         = "blackmarket",
        restock      = {text = restockText, seconds = restockSeconds},
        fruits       = fruits
    }

    local total, stocked, listed = 0, 0, 0
    for _, info in pairs(fruits) do
        total = total + 1
        if info.inStock then stocked = stocked + 1 end
        if info.listed then listed = listed + 1 end
    end
    print("📊 BLACK MARKET: " .. (total > 0 and (total .. " fruits") or "NONE")
        .. " | Listed: " .. listed
        .. " | In stock: " .. stocked
        .. " | Restock: " .. (restockText ~= "" and restockText or "?"))

    return data
end

-- SEND TO API
local function sendToAPI(data)
    local success = pcall(function()
        Cache.updateCounter = Cache.updateCounter + 1
        data.updateNumber = Cache.updateCounter
        request({
            Url = API_ENDPOINT .. "?session=" .. Cache.sessionId .. "&t=" .. os.time(),
            Method = "POST",
            Headers = {
                ["Content-Type"]  = "application/json",
                ["Authorization"] = API_KEY,
                ["Cache-Control"] = "no-cache, no-store, must-revalidate",
                ["X-Session-ID"]  = Cache.sessionId,
                ["X-Update-Number"] = tostring(Cache.updateCounter)
            },
            Body = HttpService:JSONEncode(data)
        })
    end)
    print(success and ("✅ API UPDATE #" .. Cache.updateCounter)
                  or ("❌ API FAILED #" .. Cache.updateCounter))
    return success
end

-- HEARTBEAT
local function sendHeartbeat()
    pcall(function()
        request({
            Url = API_ENDPOINT .. "/heartbeat",
            Method = "POST",
            Headers = {["Authorization"] = API_KEY, ["X-Session-ID"] = Cache.sessionId},
            Body = HttpService:JSONEncode({
                sessionId = Cache.sessionId,
                status = "ALIVE",
                timestamp = os.time()
            })
        })
    end)
end

-- CHANGE DETECTION
local function hasChanges(oldFruits, newFruits)
    for name, info in pairs(newFruits) do
        local old = oldFruits[name]
        if not old then return true end
        if old.inStock ~= info.inStock or old.price ~= info.price
            or old.listed ~= info.listed or old.tier ~= info.tier then
            return true
        end
    end
    for name in pairs(oldFruits) do
        if newFruits[name] == nil then return true end
    end
    return false
end

-- SETUP
local function setupCrashDetection()
    LocalPlayer.AncestryChanged:Connect(function()
        if not LocalPlayer.Parent then
            autoDeleteOnCrash()
        end
    end)
end

local function setupAntiAFK()
    local VirtualUser = game:GetService("VirtualUser")
    LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end

-- MAIN
local function startMonitoring()
    print("👑 KING LEGACY MONITOR STARTED | /api/stocks/kinglegacy | Session: " .. Cache.sessionId)

    setupAntiAFK()
    setupCrashDetection()

    local waited = 0
    while not findFruitContainer() and waited < 30 do
        wait(1); waited = waited + 1
    end
    if waited >= 30 then
        print("⚠️ FruitFrame not found after 30s - starting anyway, will retry each loop")
    end

    local initialData = collectAllData()
    Cache.fruits = initialData.fruits
    Cache.restock = initialData.restock.text
    Cache.lastHeartbeat = os.time()
    Cache.lastDiscordUpdate = os.time()

    sendToAPI(initialData)
    sendHeartbeat()
    print("🚀 MONITORING LOOP STARTED")

    while true do
        local success, currentData = pcall(collectAllData)
        if success then
            local now = os.time()
            local changes = hasChanges(Cache.fruits, currentData.fruits)

            if sendToAPI(currentData) then
                Cache.fruits = currentData.fruits
                Cache.restock = currentData.restock.text
                if changes then print("🔄 STOCK CHANGED & SENT") end
            end

            if (now - Cache.lastHeartbeat) >= HEARTBEAT_INTERVAL then
                sendHeartbeat(); Cache.lastHeartbeat = now
            end
            if (now - Cache.lastDiscordUpdate) >= DISCORD_UPDATE_INTERVAL then
                sendToDiscord("👑 King Legacy Monitor running - Update #" .. Cache.updateCounter, false)
                Cache.lastDiscordUpdate = now
            end
        else
            print("❌ ERROR:", currentData)
            autoDeleteOnCrash()
            break
        end
        wait(CHECK_INTERVAL)
    end
end

startMonitoring()
