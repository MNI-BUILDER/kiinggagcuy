Skip to content
MNI-BUILDER
kiinggagcuy
Repository navigation
Code
Issues
Pull requests
Agents
Actions
Projects
Wiki
Security and quality
Insights
Settings
kiinggagcuy
/
lol.lua
in
main

Edit

Preview
Indent mode

Spaces
Indent size

2
Line wrap mode

No wrap
Editing lol.lua file contents
  1
  2
  3
  4
  5
  6
  7
  8
  9
 10
 11
 12
 13
 14
 15
 16
 17
 18
 19
 20
 21
 22
 23
 24
 25
 26
 27
 28
 29
 30
 31
 32
 33
 34
 35
 36
 37
 38
 39
 40
 41
 42
 43
 44
 45
 46
 47
 48
 49
 50
 51
 52
 53
 54
 55
 56
 57
 58
 59
 60
 61
 62
 63
 64
 65
 66
 67
 68
 69
 70
 71
 72
 73
 74
 75
 76
 77
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
Use Control + Shift + m to toggle the tab key moving focus. Alternatively, use esc then tab to move to the next interactive element on the page.
 
