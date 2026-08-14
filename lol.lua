-- KING LEGACY — MATERIAL DEALER MONITOR -> /api/stocks/kinglegacy?shop=materialdealer
-- No UI needed. Reads the MaterialDealer RemoteFunction directly.
-- View data in browser: http://204.12.233.39:3000/api/stocks/kinglegacy?key=status
print("⚒️ Material Dealer Monitor starting…")

local API_ENDPOINT    = "http://204.12.233.39:3000/api/stocks/kinglegacy"
local DELETE_ENDPOINT = "http://204.12.233.39:3000/api/stocks/kinglegacy"
local API_KEY         = "GAMERSBERGGAG"
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"

local SHOP_TAG            = "materialdealer"
local CHECK_INTERVAL      = 5
local HEARTBEAT_INTERVAL  = 30
local DISCORD_ON_ROTATION = true    -- ping Discord when the 6 items change

local HttpService = game:GetService("HttpService")
local RS          = game:GetService("ReplicatedStorage")
local LocalPlayer = game.Players.LocalPlayer

local Chest    = RS:WaitForChild("Chest")
local Remote   = Chest.Remotes.Functions.MaterialDealer
local MatList  = require(Chest.Modules.MaterialList)
local DealerDT = require(Chest.Modules.DealerData)

local Cache = {
    sessionId = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
    updateCounter = 0,
    lastHeartbeat = 0,
    lastKey = nil,
    lastTime = nil,
    timerMode = "unknown"   -- countdown | elapsed | unknown
}

local function fmt(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    return string.format("%02d:%02d:%02d", math.floor(sec/3600), math.floor(sec%3600/60), sec%60)
end

local function comma(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

local function getStock()
    local ok, res = pcall(function() return Remote:InvokeServer("Get") end)
    if not ok or type(res) ~= "table" or type(res.Stocks) ~= "table" then
        return nil, (ok and "bad response" or tostring(res))
    end
    return res, "ok"
end

local function enrich(name, qty)
    local info = MatList[name] or {}
    local tier = info.Tier or "Unknown"
    local price = DealerDT.Prices and DealerDT.Prices[tier]
    local stacks = DealerDT.BuyStacks and DealerDT.BuyStacks[tier]
    return {
        name       = name,
        tier       = tier,
        stock      = qty,
        stackSize  = stacks,
        priceValue = price and price.Value or 0,
        priceType  = price and price.Type or "",
        image      = info.Image or "",
        info       = info.Info or "",
        isFish     = info.Fish == true,
        craftable  = (info.CraftList ~= nil)
    }
end

local function buildPayload()
    local res, reason = getStock()
    if not res then return nil, reason end

    local t = tonumber(res.CurrentTime) or 0
    if Cache.lastTime then
        if t < Cache.lastTime then Cache.timerMode = "countdown"
        elseif t > Cache.lastTime then Cache.timerMode = "elapsed" end
    end
    Cache.lastTime = t

    local items, names = {}, {}
    for name, qty in pairs(res.Stocks) do
        table.insert(items, enrich(name, qty))
        table.insert(names, name)
    end
    table.sort(names)
    table.sort(items, function(a, b) return a.name < b.name end)

    local key = table.concat(names, "|")
    local rotated = (Cache.lastKey ~= nil and Cache.lastKey ~= key)
    Cache.lastKey = key

    return {
        sessionId     = Cache.sessionId,
        timestamp     = os.time(),
        updateNumber  = Cache.updateCounter + 1,
        playerName    = LocalPlayer.Name,
        userId        = LocalPlayer.UserId,
        game          = "kinglegacy",
        shop          = SHOP_TAG,
        live          = true,
        currentTime   = t,
        timerMode     = Cache.timerMode,
        timerText     = fmt(t),
        restockAtUnix = (Cache.timerMode ~= "elapsed") and (os.time() + t) or nil,
        itemCount     = #items,
        itemList      = names,
        items         = items,
        rotated       = rotated
    }, "ok"
end

local function sendToAPI(data)
    return (pcall(function()
        Cache.updateCounter = Cache.updateCounter + 1
        data.updateNumber = Cache.updateCounter
        request({
            Url = API_ENDPOINT .. "?shop=" .. SHOP_TAG
                .. "&session=" .. Cache.sessionId .. "&t=" .. os.time(),
            Method = "POST",
            Headers = {["Content-Type"] = "application/json",
                ["Authorization"] = API_KEY,
                ["Cache-Control"] = "no-cache, no-store, must-revalidate",
                ["X-Session-ID"] = Cache.sessionId,
                ["X-Shop"] = SHOP_TAG,
                ["X-Update-Number"] = tostring(Cache.updateCounter)},
            Body = HttpService:JSONEncode(data)
        })
    end))
end

local function sendHeartbeat()
    pcall(function()
        request({
            Url = API_ENDPOINT .. "/heartbeat?shop=" .. SHOP_TAG,
            Method = "POST",
            Headers = {["Authorization"] = API_KEY,
                ["X-Session-ID"] = Cache.sessionId,
                ["X-Shop"] = SHOP_TAG},
            Body = HttpService:JSONEncode({sessionId = Cache.sessionId,
                shop = SHOP_TAG, status = "ALIVE", timestamp = os.time()})
        })
    end)
end

local function autoDeleteOnCrash()
    pcall(function()
        request({
            Url = DELETE_ENDPOINT .. "?shop=" .. SHOP_TAG,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json",
                ["Authorization"] = API_KEY,
                ["X-Session-ID"] = Cache.sessionId,
                ["X-Shop"] = SHOP_TAG},
            Body = HttpService:JSONEncode({action = "DELETE_ALL",
                shop = SHOP_TAG, sessionId = Cache.sessionId,
                playerName = LocalPlayer.Name, timestamp = os.time()})
        })
    end)
end

local function discordRotation(data)
    pcall(function()
        local lines = {}
        for _, it in ipairs(data.items) do
            local cost = it.priceType == "Gem"
                and (it.priceValue .. " 💎")
                or  ("$" .. comma(it.priceValue))
            table.insert(lines, string.format("**%s** — %s | x%d | %s",
                it.name, it.tier, it.stock, cost))
        end
        request({
            Url = DISCORD_WEBHOOK, Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({
                embeds = {{
                    title = "⚒️ Material Dealer — New Stock",
                    description = table.concat(lines, "\n"),
                    color = 3447003,
                    footer = {text = "Resets in " .. data.timerText .. " | " .. Cache.sessionId},
                    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
                }}
            })
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
print("  Material Dealer Monitor — no UI needed")
print("  POST -> " .. API_ENDPOINT .. "?shop=" .. SHOP_TAG)
print("=====================================")

Cache.lastHeartbeat = os.time()
local lastReason = ""

while true do
    local ok, data, reason = pcall(buildPayload)

    if ok and data then
        print(string.format("🟢 %d items [%s] | timer %s (%s)",
            data.itemCount, table.concat(data.itemList, ", "),
            data.timerText, data.timerMode))

        if sendToAPI(data) then
            print("   ✅ POST #" .. Cache.updateCounter)
        else
            print("   ❌ POST failed")
        end

        if data.rotated and DISCORD_ON_ROTATION then
            print("   🔄 ROTATION DETECTED")
            discordRotation(data)
        end

        if (os.time() - Cache.lastHeartbeat) >= HEARTBEAT_INTERVAL then
            sendHeartbeat()
            Cache.lastHeartbeat = os.time()
        end
    else
        local r = tostring(reason or data)
        if r ~= lastReason then
            print("⏸️ " .. r)
            lastReason = r
        end
    end

    wait(CHECK_INTERVAL)
end
