-- MATERIAL DEALER FINDER v3 — anchored on the "Avaliable Until" label
-- RUN THIS WHILE THE MATERIAL DEALER UI IS OPEN ON SCREEN.
print("🔎 FINDER v3 — keep the Material Dealer UI OPEN")

local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"

local ANCHORS = {
    "avaliable until", "available until",
    "dragon's orb", "essence of fire", "gunpowder",
    "bread crumbs", "fresh fish", "coral"
}

local CHUNK_SIZE = 1800
local MAX_LINE   = 250
local DUMP_DEPTH = 4

local HttpService = game:GetService("HttpService")
local LocalPlayer = game.Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local buffer, done = {}, {}

local function trim(s) return (tostring(s or ""):gsub("^%s+",""):gsub("%s+$","")) end

local function out(s)
    s = tostring(s)
    if #s > MAX_LINE then s = s:sub(1, MAX_LINE) .. "…" end
    table.insert(buffer, s)
end

local function post(t)
    pcall(function()
        request({Url = DISCORD_WEBHOOK, Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({content = "```\n" .. t .. "\n```"})})
    end)
    wait(1.2)
end

local function flush()
    if #buffer == 0 then return end
    local chunk = ""
    for _, l in ipairs(buffer) do
        if #chunk + #l + 1 > CHUNK_SIZE then post(chunk) chunk = "" end
        chunk = chunk .. l .. "\n"
    end
    if trim(chunk) ~= "" then post(chunk) end
    buffer = {}
end

local function cleanText(o)
    if not o then return "" end
    local ok, c = pcall(function() return o.ContentText end)
    if ok and c and c ~= "" then return trim(c) end
    return trim((tostring(o.Text or ""):gsub("<[^<>]*>", "")))
end

local function getPath(o)
    local p, cur = {}, o
    while cur and cur ~= game do table.insert(p, 1, cur.Name) cur = cur.Parent end
    return table.concat(p, ".")
end

local function onScreen(o)
    local cur = o
    while cur and cur:IsA("GuiObject") do
        if not cur.Visible then return false end
        cur = cur.Parent
    end
    if cur and cur:IsA("ScreenGui") then return cur.Enabled == true end
    return false
end

local function colorStr(c)
    if not c then return "" end
    return string.format("(%d,%d,%d)", math.floor(c.R*255+0.5), math.floor(c.G*255+0.5), math.floor(c.B*255+0.5))
end

local function describe(c)
    local s = "- " .. c.Name .. " (" .. c.ClassName .. ")"
    if c:IsA("TextLabel") or c:IsA("TextButton") or c:IsA("TextBox") then
        s = s .. ' | "' .. cleanText(c) .. '"'
    end
    if c:IsA("ImageLabel") or c:IsA("ImageButton") then
        s = s .. " | img=" .. tostring(c.Image)
        s = s .. " | imgColor=" .. colorStr(c.ImageColor3)
    end
    if c:IsA("Frame") or c:IsA("ImageLabel") or c:IsA("ImageButton") or c:IsA("TextLabel") then
        pcall(function() s = s .. " | bg=" .. colorStr(c.BackgroundColor3) end)
    end
    local st = c:FindFirstChildOfClass("UIStroke")
    if st then s = s .. " | stroke=" .. colorStr(st.Color) end
    if c:IsA("GuiObject") then s = s .. " | Vis=" .. tostring(c.Visible) end
    return s
end

local function dumpTree(o, d)
    d = d or 1
    if d > DUMP_DEPTH then return end
    for _, c in ipairs(o:GetChildren()) do
        out(string.rep("  ", d) .. describe(c))
        dumpTree(c, d + 1)
    end
end

local function matches(s)
    local l = string.lower(s or "")
    for _, a in ipairs(ANCHORS) do if l:find(a, 1, true) then return true end end
    return false
end

local function report(hit)
    -- climb to the shop root: highest ancestor still on screen under a ScreenGui
    local chain, cur = {}, hit
    while cur and cur:IsA("GuiObject") do
        table.insert(chain, cur)
        cur = cur.Parent
    end

    out("########################################")
    out("ANCHOR: " .. getPath(hit))
    out('text: "' .. cleanText(hit) .. '"  onScreen=' .. tostring(onScreen(hit)))
    out("--- ancestor chain (top = ScreenGui side) ---")
    for i = #chain, 1, -1 do
        out("  [" .. i .. "] " .. chain[i].Name .. " (" .. chain[i].ClassName ..
            ") children=" .. #chain[i]:GetChildren() .. " Vis=" .. tostring(chain[i].Visible))
    end

    -- the shop root = the ancestor 2-3 levels up that holds both timer and grid
    local root = chain[math.min(#chain, 3)]
    for i = 1, #chain do
        if #chain[i]:GetChildren() >= 4 then root = chain[i] break end
    end

    out("--- ROOT PICK: " .. getPath(root) .. " ---")
    dumpTree(root, 1)

    out("--- ALL ON-SCREEN TEXT UNDER ROOT ---")
    for _, d in ipairs(root:GetDescendants()) do
        if (d:IsA("TextLabel") or d:IsA("TextButton")) and onScreen(d) then
            local t = cleanText(d)
            if t ~= "" then out("   [" .. d.Name .. "] " .. t) end
        end
    end
    out("########################################")
end

local function scan()
    for _, g in ipairs(PlayerGui:GetDescendants()) do
        pcall(function()
            if (g:IsA("TextLabel") or g:IsA("TextButton")) and matches(cleanText(g)) then
                local p = getPath(g)
                if not done[p] then done[p] = true report(g) end
            end
        end)
    end
end

while true do
    pcall(scan)
    if #buffer > 0 then print("📤 sending…") flush() end
    wait(1)
end
