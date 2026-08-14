-- KING LEGACY MONITOR - Black Market Fruit Stock -> /api/stocks/kinglegacy
-- PATH: PlayerGui.MainGui.StarterFrame.FruitFrame.ScrollingFrame
-- STOCK SIGNAL: entry.Visible (the list hides fruits that aren't stocked)
-- READY GATE:   the "Time Until New Fruits" label must show a real clock, not "???"
print("👑 Starting King Legacy Monitor (Black Market Stock)...")

local API_ENDPOINT     = "http://204.12.233.39:3000/api/stocks/kinglegacy"
local DELETE_ENDPOINT  = "http://204.12.233.39:3000/api/stocks/kinglegacy"
local API_KEY          = "GAMERSBERGGAG"
local DISCORD_WEBHOOK  = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"
local CHECK_INTERVAL   = 1
local HEARTBEAT_INTERVAL = 10
local DISCORD_UPDATE_INTERVAL = 300

-- The "Time Until New Fruits" label only resolves while the shop UI is open,
-- so it can't gate an AFK monitor. Visible-based stock works without it.
-- Set true only if you want to hard-require the timer.
local REQUIRE_TIMER = false

local HttpService = game:GetService("HttpService")
local LocalPlayer = game.Players.LocalPlayer

local Cache = {
    sessionId = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
    updateCounter = 0,
    lastHeartbeat = 0,
    lastDiscordUpdate = 0,
    fruits = {}
}

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

local function cleanText(obj)
    if not obj then return "" end
    local ok, content = pcall(function() return obj.ContentText end)
    if ok and content and content ~= "" then return trim(content) end
    local s = tostring(obj.Text or ""):gsub("<[^<>]*>", "")
    s = s:gsub("&quot;", '"'):gsub("&apos;", "'")
    s = s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
    return trim(s)
end

local function findLabel(entry, childName)
    local direct = entry:FindFirstChild(childName)
    if direct and (direct:IsA("TextLabel") or direct:IsA("TextButton")) then return direct end
    local deep = entry:FindFirstChild(childName, true)
    if deep and (deep:IsA("TextLabel") or deep:IsA("TextButton")) then return deep end
    return nil
end

local function sendToDiscord(content, isError)
    pcall(function()
        request({
            Url = DISCORD_WEBHOOK,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({
                content = isError and "💥 **ERROR**" or "📊 **UPDATE**",
                embeds = {{
                    description = content,
                    color = isError and 16711680 or 65280,
                    footer = {text = "Session: " .. Cache.sessionId},
                    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
                }}
            })
        })
    end)
end

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

-- ==== UI ====

local function getMainGui()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    return pg and pg:FindFirstChild("MainGui")
end

local function guiReady()
    local mainGui = getMainGui()
    if not mainGui then return false end
    if mainGui:IsA("ScreenGui") and mainGui.Enabled ~= true then return false end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local loading = pg and pg:FindFirstChild("LoadingGUI")
    if loading and loading:IsA("ScreenGui") and loading.Enabled == true then return false end
    return true
end

local function getContainer()
    local mainGui = getMainGui()
    if not mainGui then return nil end
    local starter = mainGui:FindFirstChild("StarterFrame")
    if not starter then return nil end
    local fruitFrame = starter:FindFirstChild("FruitFrame")
    if not fruitFrame then return nil end
    return fruitFrame:FindFirstChild("ScrollingFrame"), fruitFrame
end

-- "Time Until New Fruits: 03:16:04"  -> real
-- "Time Until New Fruits: ???"       -> shop data hasn't replicated, data is FAKE
local function getRestock(fruitFrame)
    local text, seconds, valid = "", 0, false
    if not fruitFrame then return text, seconds, valid end
    for _, c in ipairs(fruitFrame:GetDescendants()) do
        if c:IsA("TextLabel") or c:IsA("TextButton") then
            local t = cleanText(c)
            if t:lower():match("fruit") or t:lower():match("restock") then
                text = t
                local h, m, s = t:match("(%d+):(%d+):(%d+)")
                if h then
                    seconds = tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
                    valid = true
                    return text, seconds, valid
                end
            end
        end
    end
    return text, seconds, valid
end

local function parseStatus(statusLabel)
    local clean = cleanText(statusLabel)
    local lower = string.lower(clean)
    if clean == "" or lower:match("loading") then return clean, "loading", 0 end
    if lower:match("out%s*of%s*stock") or lower:match("sold") then return clean, "out_of_stock", 0 end
    local price = tonumber((clean:gsub("[^%d]", "")))
    if price and price > 0 then return clean, "price", price end
    if lower:match("in%s*stock") then return clean, "in_stock", 0 end
    return clean, "unknown", 0
end

-- ==== SCRAPE ====

local function collectBlackMarket()
    local result, listedCount, total = {}, 0, 0
    local restockText, restockSeconds, restockValid = "", 0, false

    local ok = pcall(function()
        local container, fruitFrame = getContainer()
        if not container then return end
        restockText, restockSeconds, restockValid = getRestock(fruitFrame)

        for _, entry in ipairs(container:GetChildren()) do
            if entry:IsA("GuiObject") and not shouldIgnoreItem(entry.Name) then
                local status, state, price = parseStatus(findLabel(entry, "Status"))
                local displayName = cleanText(findLabel(entry, "TextLabel"))
                local tierText    = cleanText(findLabel(entry, "Tier"))

                -- THE STOCK SIGNAL: hidden entries are not stocked this rotation.
                local listed = entry.Visible == true
                if state == "out_of_stock" then listed = false end

                total = total + 1
                if listed then listedCount = listedCount + 1 end

                result[entry.Name] = {
                    name         = (displayName ~= "" and displayName or entry.Name),
                    tier         = tierText,
                    inStock      = listed,
                    stock        = listed and 1 or 0,
                    catalogPrice = price,      -- base price from the list, NOT the shop price
                    status       = status,
                    state        = state
                }
            end
        end
    end)

    if not ok then return {}, false, 0, "", 0 end

    -- Ready = the list is built and at least one fruit is showing.
    -- The timer is reported but no longer required.
    local isReady = (total > 0) and (listedCount > 0)
    if REQUIRE_TIMER then isReady = isReady and restockValid end
    return result, isReady, listedCount, restockText, restockSeconds, restockValid
end

local function collectAllData()
    local fruits, isReady, listedCount, restockText, restockSeconds, restockValid = collectBlackMarket()

    local inStockNames = {}
    for _, info in pairs(fruits) do
        if info.inStock then table.insert(inStockNames, info.name) end
    end
    table.sort(inStockNames)

    local data = {
        sessionId    = Cache.sessionId,
        timestamp    = os.time(),
        updateNumber = Cache.updateCounter + 1,
        playerName   = LocalPlayer.Name,
        userId       = LocalPlayer.UserId,
        game         = "kinglegacy",
        shop         = "blackmarket",
        ready        = isReady,
        restock      = {text = restockText, seconds = restockSeconds, valid = restockValid or false},
        inStockList  = inStockNames,
        fruits       = fruits
    }

    print("📊 " .. listedCount .. "/" .. #inStockNames .. " stocked ["
        .. table.concat(inStockNames, ", ") .. "] | READY: " .. tostring(isReady)
        .. " | " .. (restockText ~= "" and restockText or "no timer"))

    return data
end

-- ==== NETWORK ====

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

local function sendHeartbeat(ready)
    pcall(function()
        request({
            Url = API_ENDPOINT .. "/heartbeat",
            Method = "POST",
            Headers = {["Authorization"] = API_KEY, ["X-Session-ID"] = Cache.sessionId},
            Body = HttpService:JSONEncode({
                sessionId = Cache.sessionId,
                status = ready and "ALIVE" or "WAITING",
                timestamp = os.time()
            })
        })
    end)
end

local function hasChanges(oldFruits, newFruits)
    for name, info in pairs(newFruits) do
        local old = oldFruits[name]
        if not old then return true end
        if old.inStock ~= info.inStock or old.state ~= info.state then return true end
    end
    for name in pairs(oldFruits) do
        if newFruits[name] == nil then return true end
    end
    return false
end

-- ==== SETUP ====

local function setupCrashDetection()
    LocalPlayer.AncestryChanged:Connect(function()
        if not LocalPlayer.Parent then autoDeleteOnCrash() end
    end)
end

local function setupAntiAFK()
    local VirtualUser = game:GetService("VirtualUser")
    LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end

-- ==== MAIN ====

local function startMonitoring()
    print("👑 KING LEGACY MONITOR | Session: " .. Cache.sessionId)

    setupAntiAFK()
    setupCrashDetection()

    local waited = 0
    while not guiReady() and waited < 120 do
        if waited % 10 == 0 then print("⏳ Waiting for MainGui... " .. waited .. "s") end
        wait(1); waited = waited + 1
    end

    -- Wait for the fruit list to build and show at least one stocked fruit
    waited = 0
    while waited < 90 do
        local _, isReady = collectBlackMarket()
        if isReady then print("✅ Fruit list populated") break end
        if waited % 10 == 0 then
            print("⏳ No stocked fruits visible yet (" .. waited .. "s)")
        end
        wait(1); waited = waited + 1
    end

    Cache.lastHeartbeat = os.time()
    Cache.lastDiscordUpdate = os.time()

    local initialData = collectAllData()
    if initialData.ready then
        Cache.fruits = initialData.fruits
        sendToAPI(initialData)
    else
        print("⚠️ NOT READY - no stocked fruits visible in the list yet.")
    end
    sendHeartbeat(initialData.ready)
    print("🚀 MONITORING LOOP STARTED")

    while true do
        local success, currentData = pcall(collectAllData)
        if success then
            local now = os.time()
            if currentData.ready then
                local changes = hasChanges(Cache.fruits, currentData.fruits)
                if sendToAPI(currentData) then
                    Cache.fruits = currentData.fruits
                    if changes then print("🔄 STOCK CHANGED & SENT") end
                end
            else
                print("⏸️ Skipping POST - no stocked fruits visible")
            end

            if (now - Cache.lastHeartbeat) >= HEARTBEAT_INTERVAL then
                sendHeartbeat(currentData.ready); Cache.lastHeartbeat = now
            end
            if (now - Cache.lastDiscordUpdate) >= DISCORD_UPDATE_INTERVAL then
                sendToDiscord("👑 King Legacy Monitor - Update #" .. Cache.updateCounter, false)
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
