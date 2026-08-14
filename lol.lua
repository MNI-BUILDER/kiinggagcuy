-- MATERIAL DEALER FINDER v4 — StarterFrame map + wide "Avaliable" hunt
-- Run it, THEN open the dealer. Leave it open. Boss-drop noise is blacklisted.
print("🔎 FINDER v4 — mapping StarterFrame, then hunting 'Avaliable'")

local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"

local ANCHORS   = {"avaliable", "available until", "material dealer"}
local BLACKLIST = {"bosseshealthbar", "battlepass", "inventory_frame", "backpack", "topbar"}

local CHUNK_SIZE, MAX_LINE, DUMP_DEPTH = 1800, 250, 4

local HttpService = game:GetService("HttpService")
local RS          = game:GetService("ReplicatedStorage")
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
    if cur and (cur:IsA("ScreenGui") or cur:IsA("SurfaceGui") or cur:IsA("BillboardGui")) then
        return cur.Enabled == true
    end
    return false
end
local function blacklisted(p)
    local l = string.lower(p)
    for _, b in ipairs(BLACKLIST) do if l:find(b, 1, true) then return true end end
    return false
end
local function col(c)
    if not c then return "" end
    return string.format("(%d,%d,%d)", math.floor(c.R*255+.5), math.floor(c.G*255+.5), math.floor(c.B*255+.5))
end
local function describe(c)
    local s = "- " .. c.Name .. " (" .. c.ClassName .. ")"
    if c:IsA("TextLabel") or c:IsA("TextButton") then s = s .. ' | "' .. cleanText(c) .. '"' end
    if c:IsA("ImageLabel") or c:IsA("ImageButton") then s = s .. " | img=" .. tostring(c.Image) end
    local st = c:FindFirstChildOfClass("UIStroke")
    if st then s = s .. " | stroke=" .. col(st.Color) end
    pcall(function() if c:IsA("GuiObject") then s = s .. " | bg=" .. col(c.BackgroundColor3) end end)
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

local function report(hit, where)
    local p = getPath(hit)
    if done[p] then return end
    done[p] = true

    out("########################################")
    out("HIT [" .. where .. "]: " .. p)
    out('text: "' .. cleanText(hit) .. '"  onScreen=' .. tostring(onScreen(hit)))

    local chain, cur = {}, hit
    while cur and cur:IsA("GuiObject") do table.insert(chain, cur) cur = cur.Parent end
    for i = #chain, 1, -1 do
        out("  [" .. i .. "] " .. chain[i].Name .. " (" .. chain[i].ClassName ..
            ") kids=" .. #chain[i]:GetChildren() .. " Vis=" .. tostring(chain[i].Visible))
    end

    -- root = topmost GuiObject ancestor (the whole shop window)
    local root = chain[#chain] or hit
    out("--- FULL TREE OF ROOT: " .. getPath(root) .. " ---")
    dumpTree(root, 1)
    out("########################################")
end

-- 1) StarterFrame map (the likely answer)
out("=== StarterFrame children (39) ===")
local mg = PlayerGui:FindFirstChild("MainGui")
local sf = mg and mg:FindFirstChild("StarterFrame")
if sf then
    for _, c in ipairs(sf:GetChildren()) do
        local extra = ""
        if c:IsA("GuiObject") then extra = " Vis=" .. tostring(c.Visible) .. " kids=" .. #c:GetChildren() end
        out(c.Name .. " (" .. c.ClassName .. ")" .. extra)
    end
else
    out("!! StarterFrame missing")
end

-- 2) every ScreenGui/SurfaceGui/BillboardGui anywhere obvious
out("=== GUI CONTAINERS ===")
for _, g in ipairs(PlayerGui:GetDescendants()) do
    if g:IsA("ScreenGui") or g:IsA("SurfaceGui") or g:IsA("BillboardGui") then
        out("PG: " .. getPath(g) .. " Enabled=" .. tostring(g.Enabled))
    end
end
pcall(function()
    for _, g in ipairs(workspace:GetDescendants()) do
        if g:IsA("SurfaceGui") or g:IsA("BillboardGui") then
            out("WS: " .. getPath(g) .. " Enabled=" .. tostring(g.Enabled))
        end
    end
end)

-- 3) shop-ish templates in ReplicatedStorage (name only)
out("=== RS shop-ish objects ===")
pcall(function()
    for _, o in ipairs(RS:GetDescendants()) do
        local l = string.lower(o.Name)
        if l:find("dealer") or l:find("shop") or l:find("shallow") or l:find("material") then
            out("RS: " .. getPath(o) .. " (" .. o.ClassName .. ")")
        end
    end
end)
out("=== map done — NOW OPEN THE DEALER ===")
flush()

-- 4) live hunt across PlayerGui + workspace GUIs
local function scan()
    for _, g in ipairs(PlayerGui:GetDescendants()) do
        pcall(function()
            if (g:IsA("TextLabel") or g:IsA("TextButton")) and matches(cleanText(g)) then
                if not blacklisted(getPath(g)) then report(g, "PlayerGui") end
            end
        end)
    end
    pcall(function()
        for _, g in ipairs(workspace:GetDescendants()) do
            if g:IsA("TextLabel") or g:IsA("TextButton") then
                if matches(cleanText(g)) then report(g, "workspace") end
            end
        end
    end)
end

while true do
    pcall(scan)
    if #buffer > 0 then print("📤 sending…") flush() end
    wait(1.5)
end
