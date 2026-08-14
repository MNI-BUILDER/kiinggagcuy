-- KING LEGACY - SHOP CONTAINER SCANNER
-- Finds EVERY shop-style list in PlayerGui, not just the first FruitFrame.
-- OPEN THE BLACK MARKET UI IN GAME, THEN RUN THIS.

local HttpService = game:GetService("HttpService")
local LocalPlayer = game.Players.LocalPlayer
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"

local lines = {}
local function log(s)
    print(s)
    table.insert(lines, s)
end

local function pathOf(obj)
    local parts, cur = {}, obj
    while cur and cur ~= game do
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
    end
    return table.concat(parts, ".")
end

local function stripRich(s)
    return (tostring(s or ""):gsub("<[^<>]*>", ""))
end

-- Is this object actually on screen (every ancestor visible too)?
local function trulyVisible(obj)
    local cur = obj
    while cur and cur:IsA("GuiObject") do
        if not cur.Visible then return false end
        cur = cur.Parent
    end
    if cur and cur:IsA("ScreenGui") then return cur.Enabled end
    return true
end

local pg = LocalPlayer:FindFirstChild("PlayerGui")
if not pg then log("!! no PlayerGui") return end

-- 1) Find every container whose children look like shop entries (have Status + Tier)
local candidates = {}
for _, d in ipairs(pg:GetDescendants()) do
    if d:IsA("ScrollingFrame") or d:IsA("Frame") then
        local hits, total = 0, 0
        for _, c in ipairs(d:GetChildren()) do
            if c:IsA("GuiObject") then
                total = total + 1
                if c:FindFirstChild("Status", true) and c:FindFirstChild("Tier", true) then
                    hits = hits + 1
                end
            end
        end
        if hits >= 3 then
            table.insert(candidates, {obj = d, entries = hits, total = total})
        end
    end
end

log("========== FOUND " .. #candidates .. " SHOP CONTAINERS ==========")

for i, cand in ipairs(candidates) do
    local d = cand.obj
    log("")
    log("[" .. i .. "] " .. pathOf(d))
    log("    class=" .. d.ClassName
        .. " entries=" .. cand.entries
        .. " Visible=" .. tostring(d.Visible)
        .. " ON-SCREEN=" .. tostring(trulyVisible(d)))

    -- show first 6 entries with their real status text
    local shown = 0
    for _, c in ipairs(d:GetChildren()) do
        if c:IsA("GuiObject") and shown < 6 then
            local st = c:FindFirstChild("Status", true)
            local tl = c:FindFirstChild("TextLabel", true)
            local ti = c:FindFirstChild("Tier", true)
            if st then
                shown = shown + 1
                log("      - " .. c.Name
                    .. " | vis=" .. tostring(c.Visible)
                    .. " | name=" .. (tl and stripRich(tl.ContentText or tl.Text) or "?")
                    .. " | tier=" .. (ti and stripRich(ti.ContentText or ti.Text) or "?")
                    .. " | STATUS.Text=[[" .. tostring(st.Text) .. "]]"
                    .. " | STATUS.ContentText=[[" .. tostring(st.ContentText) .. "]]")
            end
        end
    end

    -- does this container contain the phrase we can see on screen?
    local oos = 0
    for _, sub in ipairs(d:GetDescendants()) do
        if sub:IsA("TextLabel") and stripRich(sub.Text):lower():match("out of stock") then
            oos = oos + 1
        end
    end
    log("    'Out of Stock' labels inside: " .. oos)
end

-- 2) Any label containing 'Out of Stock' ANYWHERE - tells us the real frame
log("")
log("========== 'OUT OF STOCK' LABELS IN PLAYERGUI ==========")
local n = 0
for _, d in ipairs(pg:GetDescendants()) do
    if (d:IsA("TextLabel") or d:IsA("TextButton"))
        and stripRich(d.Text):lower():match("out of stock") then
        n = n + 1
        if n <= 10 then log("  " .. pathOf(d) .. "  onscreen=" .. tostring(trulyVisible(d))) end
    end
end
log("  total: " .. n)

-- 3) Restock timer - search ALL of PlayerGui, not just MainGui
log("")
log("========== RESTOCK / TIMER LABELS ==========")
for _, d in ipairs(pg:GetDescendants()) do
    if d:IsA("TextLabel") or d:IsA("TextButton") then
        local t = stripRich(d.ContentText or d.Text)
        if t:lower():match("restock") or t:match("%d+:%d+:%d+") then
            log("  " .. pathOf(d) .. " = [[" .. t .. "]] onscreen=" .. tostring(trulyVisible(d)))
        end
    end
end

-- 4) All ScreenGuis, so we can see what else exists
log("")
log("========== SCREENGUIS ==========")
for _, g in ipairs(pg:GetChildren()) do
    log("  " .. g.Name .. " (" .. g.ClassName .. ") Enabled="
        .. tostring(g:IsA("ScreenGui") and g.Enabled or "n/a"))
end

-- Ship to Discord
local full = table.concat(lines, "\n")
print("\n=== DUMP LENGTH: " .. #full .. " chars ===")
local CHUNK, part = 1800, 1
for i = 1, #full, CHUNK do
    local piece = full:sub(i, i + CHUNK - 1)
    pcall(function()
        request({
            Url = DISCORD_WEBHOOK,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({
                content = "**SCAN part " .. part .. "**\n```\n" .. piece .. "\n```"
            })
        })
    end)
    part = part + 1
    wait(0.6)
end
print("✅ Scan sent to Discord in " .. (part - 1) .. " parts")
