-- KING LEGACY MONITOR - Black Market Fruit Stock -> /api/stocks/kinglegacy
-- CONFIRMED PATH: PlayerGui.MainGui.StarterFrame.FruitFrame.ScrollingFrame
print("👑 Starting King Legacy Monitor (Black Market Stock)...")

-- Configuration
local API_ENDPOINT     = "http://204.12.233.39:3000/api/stocks/kinglegacy"
local DELETE_ENDPOINT  = "http://204.12.233.39:3000/api/stocks/kinglegacy"
local API_KEY          = "GAMERSBERGGAG"
local DISCORD_WEBHOOK  = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"
local CHECK_INTERVAL   = 1
local HEARTBEAT_INTERVAL = 10
local DISCORD_UPDATE_INTERVAL = 300

-- Don't POST stock data until at least this fraction of entries have real status
local READY_THRESHOLD = 0.5

local HttpService = game:GetService("HttpService")
local LocalPlayer = game.Players.LocalPlayer

local Cache = {
    sessionId = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
    updateCounter = 0,
    lastHeartbeat = 0,
    lastDiscordUpdate = 0,
    fruits = {},
    wasReady = false
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

-- ContentText is Roblox's own tag-stripped text. Fall back to manual strip.
local function cleanText(obj)
    if not obj then return "" end
    local ok, content = pcall(function() return obj.ContentText end)
    if ok and content and content ~= "" then return trim(content) end
    local s = tostring(obj.Text or "")
    s = s:gsub("<[^<>]*>", "")
    s = s:gsub("&quot;", '"'):gsub("&apos;", "'")
    s = s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
    return trim(s)
end

local function findLabel(entry, childName)
    local direct = entry:FindFirstChild(childName)
    if direct and (direct:IsA("TextLabel") or direct:IsA("TextButton")) then
        return direct
    end
    local deep = entry:FindFirstChild(childName, true)
    if deep and (deep:IsA("TextLabel") or deep:IsA("TextButton")) then
        return deep
    end
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

-- ==== UI ACCESS ====

local function getMainGui()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    return pg and pg:FindFirstChild("MainGui")
end

-- Is the client past the loading screen?
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

-- FruitFrame is reused by more than one shop, so grab whatever title it's showing
local function getShopTitle(fruitFrame)
    if not fruitFrame then return "" end
    for _, c in ipairs(fruitFrame:GetChildren()) do
        if c:IsA("TextLabel") or c:IsA("TextButton") then
            local t = cleanText(c)
            if t ~= "" and #t < 40 then return t end
        end
    end
    return ""
end

-- ==== STATUS PARSER: four real states ====
-- "Loading..."    -> not populated yet, DO NOT trust
-- "Out of Stock"  -> not buyable
-- "In Stock"      -> buyable, no price shown
-- "$1,700,000"    -> buyable at that price
local function parseStatus(statusLabel)
    local clean = cleanText(statusLabel)
    local lower = string.lower(clean)

    if clean == "" or lower:match("loading") then
        return clean, "loading", nil, 0
    end
    if lower:match("out%s*of%s*stock") or lower:match("sold") or lower:match("unavailable") then
        return clean, "out_of_stock", false, 0
    end

    local digits = clean:gsub("[^%d]", "")
    local price = tonumber(digits)
    if price and price > 0 then
        return clean, "price", true, price
    end

    if lower:match("in%s*stock") or lower:match("available") then
        return clean, "in_stock", true, 0
    end

    return clean, "unknown", nil, 0
end

-- ==== SCRAPE ====

local function collectBlackMarket()
    local result, ready, total = {}, 0, 0
    local shopTitle = ""

    local ok = pcall(function()
        local container, fruitFrame = getContainer()
        if not container then return end
        shopTitle = getShopTitle(fruitFrame)

        for _, entry in ipairs(container:GetChildren()) do
            if entry:IsA("GuiObject") and not shouldIgnoreItem(entry.Name) then
                local statusLabel = findLabel(entry, "Status")
                local status, state, inStock, price = parseStatus(statusLabel)

                local displayName = cleanText(findLabel(entry, "TextLabel"))
                local tierText    = cleanText(findLabel(entry, "Tier"))

                total = total + 1
                if state ~= "loading" and state ~= "unknown" then ready = ready + 1 end

                result[entry.Name] = {
                    name    = (displayName ~= "" and displayName or entry.Name),
                    tier    = tierText,
                    status  = status,
                    state   = state,
                    price   = price,
                    inStock = inStock,
                    listed  = entry.Visible,
                    stock   = (inStock == true) and 1 or 0
                }
            end
        end
    end)

    if not ok then return {}, false, "", 0, 0 end
    local isReady = (total > 0) and ((ready / total) >= READY_THRESHOLD)
    return result, isReady, shopTitle, ready, total
end

local function collectAllData()
    local fruits, isReady, shopTitle, readyCount, total = collectBlackMarket()

    local data = {
        sessionId    = Cache.sessionId,
        timestamp    = os.time(),
        updateNumber = Cache.updateCounter + 1,
        playerName   = LocalPlayer.Name,
        userId       = LocalPlayer.UserId,
        game         = "kinglegacy",
        shop         = "blackmarket",
        shopTitle    = shopTitle,
        ready        = isReady,
        fruits       = fruits
    }

    local stocked, oos, loading = 0, 0, 0
    for _, info in pairs(fruits) do
        if info.state == "out_of_stock" then oos = oos + 1
        elseif info.state == "loading" or info.state == "unknown" then loading = loading + 1
        elseif info.inStock then stocked = stocked + 1 end
    end
    print("📊 " .. total .. " fruits | In stock: " .. stocked
        .. " | Out: " .. oos
        .. " | Loading: " .. loading
        .. " | READY: " .. tostring(isReady)
        .. (shopTitle ~= "" and (" | Shop: " .. shopTitle) or ""))

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
        if old.state ~= info.state or old.price ~= info.price
            or old.inStock ~= info.inStock or old.tier ~= info.tier then
            return true
        end
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
    print("👑 KING LEGACY MONITOR | /api/stocks/kinglegacy | Session: " .. Cache.sessionId)

    setupAntiAFK()
    setupCrashDetection()

    -- Wait out the loading screen before touching anything
    local waited = 0
    while not guiReady() and waited < 120 do
        if waited % 10 == 0 then print("⏳ Waiting for MainGui... " .. waited .. "s") end
        wait(1); waited = waited + 1
    end
    print(guiReady() and "✅ MainGui enabled" or "⚠️ MainGui still disabled, continuing anyway")

    -- Wait for the shop list to actually populate (past "Loading...")
    waited = 0
    while waited < 60 do
        local _, isReady = collectBlackMarket()
        if isReady then break end
        wait(1); waited = waited + 1
    end

    Cache.lastHeartbeat = os.time()
    Cache.lastDiscordUpdate = os.time()

    local initialData = collectAllData()
    if initialData.ready then
        Cache.fruits = initialData.fruits
        Cache.wasReady = true
        sendToAPI(initialData)
    else
        print("⚠️ Data not ready - holding first POST")
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
                    Cache.wasReady = true
                    if changes then print("🔄 STOCK CHANGED & SENT") end
                end
            else
                -- never overwrite good data with a screen full of "Loading..."
                print("⏸️ Skipping POST - data not ready")
            end

            if (now - Cache.lastHeartbeat) >= HEARTBEAT_INTERVAL then
                sendHeartbeat(currentData.ready); Cache.lastHeartbeat = now
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
