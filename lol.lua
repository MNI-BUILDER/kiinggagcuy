-- KING LEGACY - VERIFY: dump every entry exactly as read, with the shop OPEN.
-- Run this WHILE the Black Market window is open. Runs once, no loop.

local HttpService = game:GetService("HttpService")
local LocalPlayer = game.Players.LocalPlayer
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"

local lines = {}
local function log(s) print(s) table.insert(lines, tostring(s)) end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function cleanText(o)
    if not o then return "" end
    local ok, c = pcall(function() return o.ContentText end)
    if ok and c and c ~= "" then return trim(c) end
    return trim((tostring(o.Text or ""):gsub("<[^<>]*>", "")))
end

local function findLabel(e, n)
    local d = e:FindFirstChild(n)
    if d and (d:IsA("TextLabel") or d:IsA("TextButton")) then return d end
    d = e:FindFirstChild(n, true)
    if d and (d:IsA("TextLabel") or d:IsA("TextButton")) then return d end
    return nil
end

local sf = LocalPlayer.PlayerGui.MainGui.StarterFrame.FruitFrame:FindFirstChild("ScrollingFrame")
if not sf then log("!! no ScrollingFrame") return end

log("=== ENTRIES SORTED BY LAYOUTORDER (screen order) ===")

local entries = {}
for _, e in ipairs(sf:GetChildren()) do
    if e:IsA("GuiObject") then table.insert(entries, e) end
end
table.sort(entries, function(a, b)
    if a.LayoutOrder ~= b.LayoutOrder then return a.LayoutOrder < b.LayoutOrder end
    return a.Name < b.Name
end)

local shownCount = 0
for i, e in ipairs(entries) do
    local st  = findLabel(e, "Status")
    local nm  = cleanText(findLabel(e, "TextLabel"))
    local ti  = cleanText(findLabel(e, "Tier"))
    local sTx = cleanText(st)
    if e.Visible then shownCount = shownCount + 1 end

    log(string.format("%2d | vis=%-5s | ord=%-4s | %-14s | %-10s | STATUS=[[%s]]",
        i, tostring(e.Visible), tostring(e.LayoutOrder),
        (nm ~= "" and nm or e.Name), ti, sTx))
end

log("")
log("total entries: " .. #entries .. " | Visible=true: " .. shownCount)

-- every distinct status string we saw, so nothing gets parsed wrong silently
log("")
log("=== DISTINCT STATUS VALUES ===")
local seen = {}
for _, e in ipairs(entries) do
    local s = cleanText(findLabel(e, "Status"))
    seen[s] = (seen[s] or 0) + 1
end
for s, n in pairs(seen) do
    log("  [[" .. s .. "]]  x" .. n)
end

-- Ship
local full = table.concat(lines, "\n")
local CHUNK, part = 1800, 1
for i = 1, #full, CHUNK do
    pcall(function()
        request({
            Url = DISCORD_WEBHOOK, Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({
                content = "**VERIFY " .. part .. "**\n```\n" .. full:sub(i, i + CHUNK - 1) .. "\n```"
            })
        })
    end)
    part = part + 1
    wait(0.6)
end
print("✅ sent " .. (part - 1) .. " parts")
