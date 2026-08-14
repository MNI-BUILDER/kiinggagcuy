-- ═══════════════════════════════════════════════════════════════
--  KING LEGACY UNIFIED MONITOR  v3 — SINGLE MERGED PAYLOAD
--  One POST containing both shops. No record fighting.
--  Fruits stay top-level (frontend compat), materials under .materials
--  Read: http://204.12.233.39:3000/api/stocks/kinglegacy?key=status
-- ═══════════════════════════════════════════════════════════════
print("👑 KING LEGACY UNIFIED MONITOR v3 (merged payload)")

-- ══════════════ CONFIG ══════════════
local API_ENDPOINT    = "http://204.12.233.39:3000/api/stocks/kinglegacy"
local DELETE_ENDPOINT = "http://204.12.233.39:3000/api/stocks/kinglegacy"
local API_KEY         = "GAMERSBERGGAG"
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"

local ENABLE_MATERIALS   = true
local POST_INTERVAL      = 1      -- how often the merged payload goes out
local MAT_REFRESH        = 5      -- how often the material remote is polled
local HEARTBEAT_INTERVAL = 20
local STATUS_INTERVAL    = 600    -- 0 = off

local INCLUDE_OUT_OF_STOCK = true
local DISCORD_ON_CHANGE    = true
-- ════════════════════════════════════

local HttpService = game:GetService("HttpService")
local RS          = game:GetService("ReplicatedStorage")
local LocalPlayer = game.Players.LocalPlayer

local Session = {
    id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
    posts = 0, startedAt = os.time(),
    lastPost = 0, lastHeartbeat = 0, lastStatus = 0
}

-- ═══════════ HELPERS ═══════════
local function trim(s) return (tostring(s or ""):gsub("^%s+",""):gsub("%s+$","")) end

local function fmtTime(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    return string.format("%02d:%02d:%02d", math.floor(sec/3600), math.floor(sec%3600/60), sec%60)
end

local function comma(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    return ((s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")))
end

local function discord(title, desc, color)
    pcall(function()
        request({
            Url = DISCORD_WEBHOOK, Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({
                embeds = {{title = title, description = desc, color = color or 3447003,
                    footer = {text = "Session: " .. Session.id},
                    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")}}
            })
        })
    end)
end

local function cleanText(obj)
    if not obj then return "" end
    local ok, c = pcall(function() return obj.ContentText end)
    if ok and c and c ~= "" then return trim(c) end
    local s = tostring(obj.Text or ""):gsub("<[^<>]*>", "")
    return trim((s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")))
end

local function onScreen(obj)
    local cur = obj
    while cur and cur:IsA("GuiObject") do
        if not cur.Visible then return false end
        cur = cur.Parent
    end
    if cur and cur:IsA("ScreenGui") then return cur.Enabled == true end
    return false
end

-- ═══════════ BLACK MARKET ═══════════
local BM = {goodFruits = nil, goodAt = 0,
            goodRestock = {text = "", seconds = 0}, lastKey = nil}

local IGNORE_PATTERNS = {
    "_padding", "padding", "uilistlayout", "uigridlayout", "uipadding",
    "uicorner", "uistroke", "uigradient", "uiaspectratioconstraint",
    "u: ", "shadow", "bevel", "template", "example", "search"
}

local function shouldIgnore(n)
    local l = string.lower(n)
    for _, p in ipairs(IGNORE_PATTERNS) do if l:match(p) then return true end end
    return false
end

local function findLabel(entry, name)
    local d = entry:FindFirstChild(name)
    if d and (d:IsA("TextLabel") or d:IsA("TextButton")) then return d end
    d = entry:FindFirstChild(name, true)
    if d and (d:IsA("TextLabel") or d:IsA("TextButton")) then return d end
    return nil
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

local function getRestock(ff)
    if not ff then return "", 0 end
    local roots = {ff}
    if ff.Parent then table.insert(roots, ff.Parent) end
    for _, root in ipairs(roots) do
        for _, c in ipairs(root:GetDescendants()) do
            if c:IsA("TextLabel") or c:IsA("TextButton") then
                local t = cleanText(c)
                local low = t:lower()
                if (low:match("restock") or low:match("new fruit")) and onScreen(c) then
                    local h, m, s = t:match("(%d+):(%d+):(%d+)")
                    if h then return t, tonumber(h)*3600 + tonumber(m)*60 + tonumber(s) end
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
    if lower:match("out%s*of%s*stock") or lower:match("sold") then return clean, "out_of_stock", 0 end
    local price = tonumber((clean:gsub("[^%d]", "")))
    if price and price > 0 then return clean, "price", price end
    if lower:match("in%s*stock") then return clean, "in_stock", 0 end
    return clean, "unknown", 0
end

local function scrapeIfOpen()
    local container, ff = getContainer()
    if not container then return nil, "no container" end
    if not onScreen(container) then return nil, "shop closed" end

    local result, oos, priced, loading = {}, 0, 0, 0
    for _, entry in ipairs(container:GetChildren()) do
        if entry:IsA("GuiObject") and not shouldIgnore(entry.Name) then
            local status, state, price = parseStatus(findLabel(entry, "Status"))
            local displayName = cleanText(findLabel(entry, "TextLabel"))
            local tier = cleanText(findLabel(entry, "Tier"))

            if state == "out_of_stock" then oos = oos + 1
            elseif state == "price" then priced = priced + 1
            elseif state == "loading" then loading = loading + 1 end

            local inStock = (state == "price" or state == "in_stock")
            result[entry.Name] = {
                name = (displayName ~= "" and displayName or entry.Name),
                tier = tier, status = status, state = state, price = price,
                inStock = inStock, stock = inStock and 1 or 0, shown = entry.Visible
            }
        end
    end

    if oos == 0 and loading > 0 then
        return nil, "open but still loading (" .. loading .. ")"
    end

    local rt, rs = getRestock(ff)
    return {fruits = result, restock = {text = rt, seconds = rs}}
end

-- ═══════════ MATERIAL DEALER ═══════════
local MAT = {ok = false, remote = nil, list = nil, data = nil,
             cached = nil, cachedAt = 0, lastKey = nil,
             lastTime = nil, timerMode = "unknown", lastPoll = 0, lastError = ""}

if ENABLE_MATERIALS then
    local ok = pcall(function()
        local chest = RS:WaitForChild("Chest", 10)
        MAT.remote  = chest.Remotes.Functions.MaterialDealer
        MAT.list    = require(chest.Modules.MaterialList)
        MAT.data    = require(chest.Modules.DealerData)
    end)
    MAT.ok = ok and MAT.remote ~= nil
    if not MAT.ok then warn("⚠️ Material Dealer modules not found — materials disabled") end
end

local function enrichMaterial(name, qty)
    local info  = (MAT.list or {})[name] or {}
    local tier  = info.Tier or "Unknown"
    local price = MAT.data and MAT.data.Prices and MAT.data.Prices[tier]
    local stack = MAT.data and MAT.data.BuyStacks and MAT.data.BuyStacks[tier]
    return {
        name = name, tier = tier, stock = qty, stackSize = stack,
        priceValue = price and price.Value or 0,
        priceType  = price and price.Type or "",
        image = info.Image or "", info = info.Info or "",
        isFish = info.Fish == true, craftable = (info.CraftList ~= nil)
    }
end

-- refresh the cached material block; returns rotated flag
local function refreshMaterials()
    if not MAT.ok then return false end
    local ok, res = pcall(function() return MAT.remote:InvokeServer("Get") end)
    if not ok or type(res) ~= "table" or type(res.Stocks) ~= "table" then
        MAT.lastError = ok and "bad response" or tostring(res)
        return false
    end
    MAT.lastError = ""

    local t = tonumber(res.CurrentTime) or 0
    if MAT.lastTime then
        if t < MAT.lastTime then MAT.timerMode = "countdown"
        elseif t > MAT.lastTime then MAT.timerMode = "elapsed" end
    end
    MAT.lastTime = t

    local items, names = {}, {}
    for name, qty in pairs(res.Stocks) do
        table.insert(items, enrichMaterial(name, qty))
        table.insert(names, name)
    end
    table.sort(names)
    table.sort(items, function(a, b) return a.name < b.name end)

    local key = table.concat(names, "|")
    local rotated = (MAT.lastKey ~= nil and MAT.lastKey ~= key)
    MAT.lastKey = key

    MAT.cached = {
        live = true,
        currentTime = t, timerMode = MAT.timerMode, timerText = fmtTime(t),
        restockAtUnix = (MAT.timerMode ~= "elapsed") and (os.time() + t) or nil,
        itemCount = #items, itemList = names, items = items,
        scrapedAt = os.time()
    }
    MAT.cachedAt = os.time()
    return rotated
end

-- ═══════════ MERGED PAYLOAD ═══════════
local function buildPayload()
    -- fruits
    local fresh, reason = scrapeIfOpen()
    if fresh then
        BM.goodFruits  = fresh.fruits
        BM.goodAt      = os.time()
        BM.goodRestock = fresh.restock
    end

    local inStockList, outFruits, totalSeen = {}, {}, 0
    if BM.goodFruits then
        for key, f in pairs(BM.goodFruits) do
            totalSeen = totalSeen + 1
            if f.inStock then
                table.insert(inStockList, f.name)
                outFruits[key] = f
            elseif INCLUDE_OUT_OF_STOCK then
                outFruits[key] = f
            end
        end
        table.sort(inStockList)
    end

    local fruitKey = table.concat(inStockList, "|")
    local fruitsChanged = (BM.goodFruits ~= nil and BM.lastKey ~= nil and BM.lastKey ~= fruitKey)
    if BM.goodFruits then BM.lastKey = fruitKey end

    local age = BM.goodFruits and (os.time() - BM.goodAt) or -1

    -- materials block (cached, may be nil if never fetched)
    local mat = MAT.cached and {
        live          = (os.time() - MAT.cachedAt) <= (MAT_REFRESH * 3),
        scrapeAge     = os.time() - MAT.cachedAt,
        currentTime   = MAT.cached.currentTime,
        timerMode     = MAT.cached.timerMode,
        timerText     = MAT.cached.timerText,
        restockAtUnix = MAT.cached.restockAtUnix,
        itemCount     = MAT.cached.itemCount,
        itemList      = MAT.cached.itemList,
        items         = MAT.cached.items
    } or {live = false, itemCount = 0, itemList = {}, items = {},
          error = (MAT.lastError ~= "" and MAT.lastError or "no data yet")}

    return {
        -- identity
        sessionId  = Session.id,
        timestamp  = os.time(),
        playerName = LocalPlayer.Name,
        userId     = LocalPlayer.UserId,
        game       = "kinglegacy",
        shop       = "blackmarket",       -- kept for existing frontend
        shops      = {"blackmarket", "materialdealer"},

        -- BLACK MARKET (top level, unchanged shape)
        live        = (fresh ~= nil),
        stale       = (age < 0 or age > 5),
        scrapeAge   = age,
        restock     = BM.goodRestock,
        totalFruits = totalSeen,
        stockCount  = #inStockList,
        inStockList = inStockList,
        fruits      = outFruits,
        changed     = fruitsChanged,

        -- MATERIAL DEALER (nested)
        materials   = mat
    }, (fresh and "live" or reason)
end

local function sendPayload(data)
    return (pcall(function()
        Session.posts = Session.posts + 1
        data.updateNumber = Session.posts
        request({
            Url = API_ENDPOINT .. "?session=" .. Session.id .. "&t=" .. os.time(),
            Method = "POST",
            Headers = {["Content-Type"] = "application/json",
                ["Authorization"]       = API_KEY,
                ["Cache-Control"]       = "no-cache, no-store, must-revalidate",
                ["X-Session-ID"]        = Session.id,
                ["X-Update-Number"]     = tostring(Session.posts)},
            Body = HttpService:JSONEncode(data)
        })
    end))
end

local function sendHeartbeat(bmLive, matLive)
    pcall(function()
        request({
            Url = API_ENDPOINT .. "/heartbeat", Method = "POST",
            Headers = {["Authorization"] = API_KEY, ["X-Session-ID"] = Session.id},
            Body = HttpService:JSONEncode({sessionId = Session.id,
                status = "ALIVE", blackmarket = bmLive, materialdealer = matLive,
                timestamp = os.time(), uptime = os.time() - Session.startedAt})
        })
    end)
end

local function autoDeleteOnCrash()
    pcall(function()
        request({
            Url = DELETE_ENDPOINT, Method = "POST",
            Headers = {["Content-Type"] = "application/json",
                ["Authorization"] = API_KEY, ["X-Session-ID"] = Session.id},
            Body = HttpService:JSONEncode({action = "DELETE_ALL",
                sessionId = Session.id, playerName = LocalPlayer.Name,
                timestamp = os.time()})
        })
    end)
end

-- ═══════════ NOTIFY ═══════════
local function notifyFruits(d)
    local body = (#d.inStockList > 0)
        and ("**" .. table.concat(d.inStockList, "**\n**") .. "**")
        or  "_nothing in stock_"
    discord("🍎 Black Market — Stock Changed",
        body .. "\n\n" .. (d.restock.text ~= "" and d.restock.text or "no timer"), 16753920)
end

local function notifyMaterials()
    if not MAT.cached then return end
    local lines = {}
    for _, it in ipairs(MAT.cached.items) do
        local cost = (it.priceType == "Gem")
            and (it.priceValue .. " 💎") or ("$" .. comma(it.priceValue))
        table.insert(lines, string.format("**%s** — %s | x%d | %s",
            it.name, it.tier, it.stock, cost))
    end
    discord("⚒️ Material Dealer — New Stock",
        table.concat(lines, "\n") .. "\n\nResets in " .. MAT.cached.timerText, 3447003)
end

-- ═══════════ MAIN ═══════════
local function setupAntiAFK()
    local VirtualUser = game:GetService("VirtualUser")
    LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end

setupAntiAFK()
LocalPlayer.AncestryChanged:Connect(function()
    if not LocalPlayer.Parent then autoDeleteOnCrash() end
end)

if MAT.ok then refreshMaterials() end

print("═══════════════════════════════════════")
print("  ONE record, both shops merged")
print("  Fruits    -> top level (open the UI)")
print("  Materials -> payload.materials")
print("  POST -> " .. API_ENDPOINT)
print("  Session: " .. Session.id)
print("═══════════════════════════════════════")

Session.lastHeartbeat = os.time()
Session.lastStatus = os.time()

local lastReason = ""

while true do
    local now = os.time()

    -- refresh materials on its own slower cadence
    if MAT.ok and (now - MAT.lastPoll) >= MAT_REFRESH then
        MAT.lastPoll = now
        local ok, rotated = pcall(refreshMaterials)
        if ok and rotated and DISCORD_ON_CHANGE then
            print("🔄 MAT ROTATION")
            notifyMaterials()
        end
    end

    -- build + post merged payload
    if (now - Session.lastPost) >= POST_INTERVAL then
        Session.lastPost = now
        local ok, data, reason = pcall(buildPayload)

        if ok and data then
            local m = data.materials
            print(string.format("%s BM %d/%d [%s] | MAT %s %d [%s]",
                data.live and "🟢" or (data.scrapeAge < 0 and "⚪" or "🟡"),
                data.stockCount, data.totalFruits,
                table.concat(data.inStockList, ", "),
                m.live and "🟢" or "🔴", m.itemCount or 0,
                table.concat(m.itemList or {}, ", ")))

            if sendPayload(data) then
                print("   ✅ POST #" .. Session.posts)
            else
                print("   ❌ POST failed")
            end

            if data.changed and DISCORD_ON_CHANGE then
                print("   🔄 BM STOCK CHANGED")
                notifyFruits(data)
            end

            if not data.live and reason ~= lastReason then
                print("   ⏸️ fruits: " .. tostring(reason))
                lastReason = reason
            end

            if (now - Session.lastHeartbeat) >= HEARTBEAT_INTERVAL then
                sendHeartbeat(data.live, m.live)
                Session.lastHeartbeat = now
            end

            if STATUS_INTERVAL > 0 and (now - Session.lastStatus) >= STATUS_INTERVAL then
                discord("👑 King Legacy Monitor — Alive",
                    string.format("Posts: **%d**\nFruits: %s (%d in stock)\nMaterials: %s (%d)\nUptime: %s",
                        Session.posts,
                        data.live and "🟢 live" or "🔴 UI closed", data.stockCount,
                        m.live and "🟢 live" or "🔴 down", m.itemCount or 0,
                        fmtTime(now - Session.startedAt)), 65280)
                Session.lastStatus = now
            end
        else
            print("❌ build error: " .. tostring(data))
        end
    end

    wait(0.5)
end
