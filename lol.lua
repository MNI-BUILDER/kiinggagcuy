-- UI FINDER → DISCORD — locate "Material Dealer: The Shallow" and dump structure
-- Run this, then OPEN the dealer UI. Output goes to the webhook, not the console.
print("🔎 UI FINDER — output goes to Discord. Open the Material Dealer UI now.")

local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"

local KEYWORDS = {"material dealer", "material", "shallow", "dealer"}
local SCAN_INTERVAL   = 2
local MAX_ENTRIES     = 3      -- entries fully expanded
local MAX_LINE        = 300    -- truncate monster lines
local MAX_MSGS        = 30     -- webhook safety cap per flush
local CHUNK_SIZE      = 1800

local HttpService = game:GetService("HttpService")
local LocalPlayer = game.Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local seen, buffer, msgCount = {}, {}, 0

local function trim(s) return (tostring(s or ""):gsub("^%s+",""):gsub("%s+$","")) end

local function out(s)
    s = tostring(s)
    if #s > MAX_LINE then s = s:sub(1, MAX_LINE) .. "…" end
    table.insert(buffer, s)
end

local function post(text)
    if msgCount >= MAX_MSGS then return end
    msgCount = msgCount + 1
    pcall(function()
        request({
            Url = DISCORD_WEBHOOK, Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({content = "```\n" .. text .. "\n```"})
        })
    end)
    wait(1.2) -- webhook ratelimit
end

local function flush()
    if #buffer == 0 then return end
    local chunk = ""
    for _, line in ipairs(buffer) do
        if #chunk + #line + 1 > CHUNK_SIZE then
            post(chunk)
            chunk = ""
        end
        chunk = chunk .. line .. "\n"
    end
    if trim(chunk) ~= "" then post(chunk) end
    buffer = {}
    msgCount = 0
end

local function cleanText(obj)
    if not obj then return "" end
    local ok, c = pcall(function() return obj.ContentText end)
    if ok and c and c ~= "" then return trim(c) end
    local s = tostring(obj.Text or ""):gsub("<[^<>]*>", "")
    return trim(s)
end

local function getPath(obj)
    local parts, cur = {}, obj
    while cur and cur ~= game do
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
    end
    return table.concat(parts, ".")
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

local function matches(str)
    local l = string.lower(str or "")
    for _, k in ipairs(KEYWORDS) do
        if l:find(k, 1, true) then return true end
    end
    return false
end

local function dumpTree(obj, depth, maxDepth)
    depth, maxDepth = depth or 1, maxDepth or 3
    if depth > maxDepth then return end
    for _, c in ipairs(obj:GetChildren()) do
        local txt = ""
        if c:IsA("TextLabel") or c:IsA("TextButton") or c:IsA("TextBox") then
            txt = ' | "' .. cleanText(c) .. '"'
        end
        local vis = ""
        if c:IsA("GuiObject") then vis = " | Vis=" .. tostring(c.Visible) end
        out(string.rep("  ", depth) .. "- " .. c.Name .. " (" .. c.ClassName .. ")" .. txt .. vis)
        dumpTree(c, depth + 1, maxDepth)
    end
end

local function reportHit(hit, why)
    local path = getPath(hit)
    if seen[path] then return end
    seen[path] = true

    out("========================================")
    out("HIT (" .. why .. "): " .. path)
    out("class=" .. hit.ClassName .. " onScreen=" .. tostring(onScreen(hit)))
    if hit:IsA("TextLabel") or hit:IsA("TextButton") then
        out('text: "' .. cleanText(hit) .. '"')
    end

    local cur, scroll, levels = hit.Parent, nil, 0
    while cur and cur ~= PlayerGui and levels < 8 do
        out("^ ancestor: " .. cur.Name .. " (" .. cur.ClassName .. ")")
        if not scroll then
            if cur:IsA("ScrollingFrame") then
                scroll = cur
            else
                for _, d in ipairs(cur:GetDescendants()) do
                    if d:IsA("ScrollingFrame") then scroll = d break end
                end
            end
        end
        cur = cur.Parent
        levels = levels + 1
    end

    if scroll then
        out(">>> LIST CONTAINER: " .. getPath(scroll))
        out(">>> children=" .. #scroll:GetChildren() .. " onScreen=" .. tostring(onScreen(scroll)))
        local n = 0
        for _, entry in ipairs(scroll:GetChildren()) do
            if entry:IsA("GuiObject") then
                n = n + 1
                if n <= MAX_ENTRIES then
                    out("--- ENTRY: " .. entry.Name .. " (" .. entry.ClassName .. ") Vis=" .. tostring(entry.Visible))
                    dumpTree(entry, 1, 3)
                else
                    out("(entry) " .. entry.Name)
                end
            end
        end
    else
        out("!!! no ScrollingFrame near hit — parent tree:")
        if hit.Parent then dumpTree(hit.Parent, 1, 2) end
    end
    out("========================================")
end

local function scan()
    for _, gui in ipairs(PlayerGui:GetDescendants()) do
        pcall(function()
            if matches(gui.Name) and (gui:IsA("Frame") or gui:IsA("ScrollingFrame") or gui:IsA("ScreenGui")) then
                reportHit(gui, "name")
            elseif (gui:IsA("TextLabel") or gui:IsA("TextButton")) and matches(cleanText(gui)) then
                reportHit(gui, "text")
            end
        end)
    end
end

-- initial: list ScreenGuis
out("--- ScreenGuis in PlayerGui ---")
for _, g in ipairs(PlayerGui:GetChildren()) do
    if g:IsA("ScreenGui") then
        out(g.Name .. " | Enabled=" .. tostring(g.Enabled))
    end
end
out("-------------------------------")
flush()

while true do
    pcall(scan)
    if #buffer > 0 then
        print("📤 sending dump to Discord…")
        flush()
    end
    wait(SCAN_INTERVAL)
end
