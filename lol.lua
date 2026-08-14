-- KING LEGACY - DEEP DATA EXTRACT
-- Goes after the stock TABLE in memory instead of scraping the UI.
-- Run once. It prints + sends to Discord, then stops.

local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local LocalPlayer = game.Players.LocalPlayer
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"

-- Fruits we KNOW are entry names - used to fingerprint the right table
local FINGERPRINT = {"DragonDragon", "SpinSpin", "BombBomb", "PterPter", "MagmaMagma",
                     "Dragon", "Spin", "Bomb", "Pter", "Magma", "Leopard", "Phoenix"}

local lines = {}
local function log(s)
    print(s)
    table.insert(lines, tostring(s))
end

local function ser(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local t = type(v)
    if t == "table" then
        if seen[v] then return "<cycle>" end
        if depth > 3 then return "<deep>" end
        seen[v] = true
        local out, n = {}, 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 50 then table.insert(out, "...") break end
            table.insert(out, "[" .. tostring(k) .. "]=" .. ser(val, depth + 1, seen))
        end
        return "{" .. table.concat(out, ", ") .. "}"
    elseif t == "userdata" then
        local ok, cls = pcall(function() return v.ClassName end)
        return ok and ("<" .. tostring(cls) .. ">") or "<userdata>"
    elseif t == "string" then
        return '"' .. v .. '"'
    end
    return tostring(v)
end

-- does this table mention fruits?
local function looksLikeStock(tbl)
    local hits = 0
    local ok = pcall(function()
        for k, v in pairs(tbl) do
            local ks, vs = tostring(k), tostring(v)
            for _, f in ipairs(FINGERPRINT) do
                if ks == f or vs == f then hits = hits + 1 break end
            end
            if hits >= 3 then return end
        end
    end)
    return ok and hits >= 3, hits
end

-- ==== 1. GC SCAN: find the stock table in memory ====
log("========== GC SCAN FOR STOCK TABLES ==========")
local scanned, found = 0, 0
local okgc = pcall(function()
    for _, obj in pairs(getgc(true)) do
        if type(obj) == "table" then
            scanned = scanned + 1
            local isStock, hits = looksLikeStock(obj)
            if isStock then
                found = found + 1
                if found <= 8 then
                    log("")
                    log(">>> TABLE #" .. found .. " (" .. hits .. " fruit keys)")
                    log("    " .. ser(obj):sub(1, 1500))
                end
            end
        end
    end
end)
if not okgc then log("!! getgc unavailable in this executor") end
log("")
log("scanned " .. scanned .. " tables, " .. found .. " look like stock")

-- ==== 2. THE LOCALSCRIPT THAT BUILDS THE LIST ====
log("")
log("========== FRUITFRAME SCRIPT ENV ==========")
pcall(function()
    local ff = LocalPlayer.PlayerGui.MainGui.StarterFrame:FindFirstChild("FruitFrame")
    if not ff then log("!! no FruitFrame") return end

    for _, s in ipairs(ff:GetDescendants()) do
        if s:IsA("LocalScript") or s:IsA("ModuleScript") then
            log("  script: " .. s:GetFullName() .. " (" .. s.ClassName .. ")")
            local okenv = pcall(function()
                local env = getsenv(s)
                for k, v in pairs(env) do
                    if type(v) == "table" then
                        local isStock, hits = looksLikeStock(v)
                        if isStock then
                            log("    ⭐ env." .. tostring(k) .. " (" .. hits .. " hits) = "
                                .. ser(v):sub(1, 1200))
                        end
                    end
                end
            end)
            if not okenv then log("    (getsenv failed - script may not be running)") end
        end
    end
end)

-- ==== 3. MODULES THAT HOLD FRUIT DATA ====
log("")
log("========== MODULESCRIPTS WITH FRUIT DATA ==========")
local modCount = 0
for _, d in ipairs(RS:GetDescendants()) do
    if d:IsA("ModuleScript") then
        local l = string.lower(d.Name)
        if l:find("fruit") or l:find("shop") or l:find("stock") or l:find("market") then
            modCount = modCount + 1
            log("  module: " .. d:GetFullName())
            pcall(function()
                local m = require(d)
                if type(m) == "table" then
                    log("    -> " .. ser(m):sub(1, 1200))
                end
            end)
        end
    end
end
log("  total: " .. modCount)

-- ==== 4. LIVE: watch a Status label actually change ====
log("")
log("========== WATCHING STATUS CHANGES (30s) ==========")
pcall(function()
    local sf = LocalPlayer.PlayerGui.MainGui.StarterFrame.FruitFrame.ScrollingFrame
    for _, entry in ipairs(sf:GetChildren()) do
        if entry:IsA("GuiObject") then
            local st = entry:FindFirstChild("Status", true)
            if st and st:IsA("TextLabel") then
                st:GetPropertyChangedSignal("Text"):Connect(function()
                    log("  CHANGE " .. entry.Name .. " -> [[" .. st.Text .. "]]")
                end)
            end
            entry:GetPropertyChangedSignal("Visible"):Connect(function()
                log("  VISIBLE " .. entry.Name .. " -> " .. tostring(entry.Visible))
            end)
        end
    end
end)
log("  (open the shop now - any change gets logged)")
wait(30)

-- ==== SHIP ====
local full = table.concat(lines, "\n")
print("\n=== LENGTH: " .. #full .. " ===")
local CHUNK, part = 1800, 1
for i = 1, #full, CHUNK do
    pcall(function()
        request({
            Url = DISCORD_WEBHOOK,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({
                content = "**DEEP part " .. part .. "**\n```\n" .. full:sub(i, i + CHUNK - 1) .. "\n```"
            })
        })
    end)
    part = part + 1
    wait(0.6)
end
print("✅ sent in " .. (part - 1) .. " parts")
