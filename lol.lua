-- KING LEGACY MONITOR - Black Market Stock -> /api/stocks/kinglegacy
--
-- HOW TO USE: run this, then OPEN THE BLACK MARKET UI IN GAME AND LEAVE IT OPEN.
-- It only reads the list while the frame is genuinely on screen (which is when
-- the game fills it with real stock). It caches the last good read and keeps
-- posting that if you close the shop, flagged as stale.
print("👑 King Legacy Monitor - OPEN THE BLACK MARKET UI")

local API_ENDPOINT    = "http://204.12.233.39:3000/api/stocks/kinglegacy"
local DELETE_ENDPOINT = "http://204.12.233.39:3000/api/stocks/kinglegacy"
local API_KEY         = "GAMERSBERGGAG"
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"
local CHECK_INTERVAL  = 1
local HEARTBEAT_INTERVAL = 10
local DISCORD_UPDATE_INTERVAL = 300

local HttpService = game:GetService("HttpService")
local LocalPlayer = game.Players.LocalPlayer

local Cache = {
    sessionId = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
    updateCounter = 0,
    lastHeartbeat = 0,
    lastDiscordUpdate = 0,
    goodFruits = nil,       -- last scrape taken while the UI was open
    goodAt = 0,
    goodRestock = {text = "", seconds = 0},
    wasOpen = false
}

local IGNORE_PATTERNS = {
    "_padding", "padding", "uilistlayout", "uigridlayout", "uipadding",
    "uicorner", "uistroke", "uigradient", "uiaspectratioconstraint",
    "u: ", "shadow", "bevel", "template", "example", "search"
}

local function shouldIgnoreItem(n)
    local l = string.lower(n)
    for _, p in ipairs(IGNORE_PATTERNS) do if l:match(p) then return true end end
    return false
end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function cleanText(obj)
    if not obj then return "" end
    local ok, c = pcall(function() return obj.ContentText end)
    if ok and c and c ~= "" then return trim(c) end
    local s = tostring(obj.Text or ""):gsub("<[^<>]*>", "")
    return trim((s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")))
end

local function findLabel(entry, name)
    local d = entry:FindFirstChild(name)
    if d and (d:IsA("TextLabel") or d:IsA("TextButton")) then return d end
    d = entry:FindFirstChild(name, true)
    if d and (d:IsA("TextLabel") or d:IsA("TextButton")) then return d end
    return nil
end

-- ==== THE KEY CHECK: is this thing actually rendered? ====
-- Visible on the frame itself is not enough - every ancestor must be visible
-- and the ScreenGui must be enabled. This is what we got wrong before.
local function onScreen(obj)
    local cur = obj
    while cur and cur:IsA("GuiObject") do
        if not cur.Visible then return false end
        cur = cur.Parent
    end
    if cur and cur:IsA("ScreenGui") then return cur.Enabled == true end
    return false
end

local function getContainer()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local mainGui = pg and pg:FindFirstChild("MainGui")
    if not mainGui then return nil end
    local starter = mainGui:FindFirstChild("StarterFrame")
    if not starter then return nil end
    local ff = starter:FindFirstChild("FruitFrame")
    if not ff then return nil end
    return ff:FindFirstChild("ScrollingFrame"), ff
end

local function sendToDiscord(content, isError)
    pcall(function()
        request({
            Url = DISCORD_WEBHOOK, Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({
                content = isError and "💥 **ERROR**" or "📊 **UPDATE**",
                embeds = {{description = content, color = isError and 16711680 or 65280,
                    footer = {text = "Session: " .. Cache.sessionId},
                    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")}}
            })
        })
    end)
end

local function autoDeleteOnCrash()
    pcall(function()
        request({
            Url = DELETE_ENDPOINT, Method = "POST",
            Headers = {["Content-Type"] = "application/json",
                ["Authorization"] = API_KEY, ["X-Session-ID"] = Cache.sessionId},
            Body = HttpService:JSONEncode({action = "DELETE_ALL",
                sessionId = Cache.sessionId, playerName = LocalPlayer.Name,
                timestamp = os.time()})
        })
    end)
end

local function getRestock(ff)
    if not ff then return "", 0 end
    for _, c in ipairs(ff:GetDescendants()) do
        if c:IsA("TextLabel") or c:IsA("TextButton") then
            local t = cleanText(c)
            if t:lower():match("fruit") or t:lower():match("restock") then
                local h, m, s = t:match("(%d+):(%d+):(%d+)")
                if h then
                    return t, tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
                end
            end
        end
    end
    return "", 0
end

local function parseStatus(label)
    local clean = cleanText(label)
    local lower = string.lower(clean)
    if clean == "" or lower:match("loading") then return clean, "loading", 0 end
    if lower:match("out%s*of%s*stock") or lower:match("sold") then
        return clean, "out_of_stock", 0
    end
    local price = tonumber((clean:gsub("[^%d]", "")))
    if price and price > 0 then return clean, "price", price end
    if lower:match("in%s*stock") then return clean, "in_stock", 0 end
    return clean, "unknown", 0
end

-- Scrape ONLY when the list is on screen. Returns nil otherwise.
local function scrapeIfOpen()
    local container, ff = getContainer()
    if not container then return nil, "no container" end
    if not onScreen(container) then return nil, "shop closed" end

    local result, oos, priced, loading = {}, 0, 0, 0

    for _, entry in ipairs(container:GetChildren()) do
        if entry:IsA("GuiObject") and not shouldIgnoreItem(entry.Name) then
            local status, state, price = parseStatus(findLabel(entry, "Status"))
            local displayName = cleanText(findLabel(entry, "TextLabel"))
            local tier = cleanText(findLabel(entry, "Tier"))

            if state == "out_of_stock" then oos = oos + 1
            elseif state == "price" then priced = priced + 1
            elseif state == "loading" then loading = loading + 1 end

            local inStock = (state == "price" or state == "in_stock")

            result[entry.Name] = {
                name    = (displayName ~= "" and displayName or entry.Name),
                tier    = tier,
                status  = status,
                state   = state,
                price   = price,
                inStock = inStock,
                stock   = inStock and 1 or 0,
                shown   = entry.Visible
            }
        end
    end

    -- If the shop is open and NOTHING says out of stock, the list is the stale
    -- catalog rather than live stock - don't trust it.
    if oos == 0 and loading > 0 then
        return nil, "open but still loading (" .. loading .. " entries)"
    end

    local restockText, restockSeconds = getRestock(ff)
    return {
        fruits = result,
        restock = {text = restockText, seconds = restockSeconds},
        counts = {outOfStock = oos, priced = priced, loading = loading}
    }
end

local function buildPayload()
    local fresh, reason = scrapeIfOpen()

    if fresh then
        Cache.goodFruits = fresh.fruits
        Cache.goodAt = os.time()
        Cache.goodRestock = fresh.restock
    end

    if not Cache.goodFruits then
        return nil, reason
    end

    local inStockList = {}
    for _, f in pairs(Cache.goodFruits) do
        if f.inStock then table.insert(inStockList, f.name) end
    end
    table.sort(inStockList)

    local age = os.time() - Cache.goodAt
    return {
        sessionId    = Cache.sessionId,
        timestamp    = os.time(),
        updateNumber = Cache.updateCounter + 1,
        playerName   = LocalPlayer.Name,
        userId       = LocalPlayer.UserId,
        game         = "kinglegacy",
        shop         = "blackmarket",
        live         = (fresh ~= nil),
        stale        = (age > 5),
        scrapeAge    = age,
        restock      = Cache.goodRestock,
        inStockList  = inStockList,
        fruits       = Cache.goodFruits
    }, (fresh and "live" or reason)
end

local function sendToAPI(data)
    local ok = pcall(function()
        Cache.updateCounter = Cache.updateCounter + 1
        data.updateNumber = Cache.updateCounter
        request({
            Url = API_ENDPOINT .. "?session=" .. Cache.sessionId .. "&t=" .. os.time(),
            Method = "POST",
            Headers = {["Content-Type"] = "application/json",
                ["Authorization"] = API_KEY,
                ["Cache-Control"] = "no-cache, no-store, must-revalidate",
                ["X-Session-ID"] = Cache.sessionId,
                ["X-Update-Number"] = tostring(Cache.updateCounter)},
            Body = HttpService:JSONEncode(data)
        })
    end)
    return ok
end

local function sendHeartbeat(live)
    pcall(function()
        request({
            Url = API_ENDPOINT .. "/heartbeat", Method = "POST",
            Headers = {["Authorization"] = API_KEY, ["X-Session-ID"] = Cache.sessionId},
            Body = HttpService:JSONEncode({sessionId = Cache.sessionId,
                status = live and "ALIVE" or "SHOP_CLOSED", timestamp = os.time()})
        })
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
setupAntiAFK()
LocalPlayer.AncestryChanged:Connect(function()
    if not LocalPlayer.Parent then autoDeleteOnCrash() end
end)

print("=====================================")
print("  GO OPEN THE BLACK MARKET NOW")
print("  Leave the shop window OPEN.")
print("=====================================")

Cache.lastHeartbeat = os.time()
Cache.lastDiscordUpdate = os.time()

local lastReason = ""

while true do
    local ok, data, reason = pcall(buildPayload)

    if ok then
        local now = os.time()

        if data then
            local c = data.counts or {}
            local n = 0
            for _ in pairs(data.fruits) do n = n + 1 end
            print((data.live and "🟢 LIVE  " or "🟡 CACHED(" .. data.scrapeAge .. "s) ")
                .. #data.inStockList .. "/" .. n .. " in stock ["
                .. table.concat(data.inStockList, ", ") .. "]")
            if sendToAPI(data) then
                print("   ✅ POST #" .. Cache.updateCounter)
            else
                print("   ❌ POST failed")
            end
        else
            if reason ~= lastReason then
                print("⏸️ " .. tostring(reason) .. " - open the Black Market UI")
                lastReason = reason
            end
        end

        if (now - Cache.lastHeartbeat) >= HEARTBEAT_INTERVAL then
            sendHeartbeat(data ~= nil and data.live)
            Cache.lastHeartbeat = now
        end
        if (now - Cache.lastDiscordUpdate) >= DISCORD_UPDATE_INTERVAL then
            sendToDiscord("👑 King Legacy Monitor - Update #" .. Cache.updateCounter, false)
            Cache.lastDiscordUpdate = now
        end
    else
        print("❌ ERROR:", data)
        autoDeleteOnCrash()
        break
    end

    wait(CHECK_INTERVAL)
end
