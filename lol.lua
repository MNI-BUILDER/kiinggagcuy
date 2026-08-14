-- UI FINDER — locate "Material Dealer: The Shallow" and dump its structure
-- Run this, then OPEN the dealer UI. It scans every 2s and prints new hits only.
print("🔎 UI FINDER — open the Material Dealer UI now")

local KEYWORDS = {"material dealer", "material", "shallow", "dealer"}
local SCAN_INTERVAL = 2
local MAX_ENTRIES_DUMPED = 3   -- how many shop entries to fully expand

local LocalPlayer = game.Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local seen = {}

local function trim(s) return (tostring(s or ""):gsub("^%s+",""):gsub("%s+$","")) end

local function cleanText(obj)
    if not obj then return "" end
    local ok, c = pcall(function() return obj.ContentText end)
    if ok and c and c ~= "" then return trim(c) end
    local s = tostring(obj.Text or ""):gsub("<[^<>]*>", "")
    return trim(s)
end

local function getPath(obj)
    local parts = {}
    local cur = obj
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

-- dump an object's children/descendants with class + text
local function dumpTree(obj, depth, maxDepth)
    depth = depth or 1
    maxDepth = maxDepth or 3
    if depth > maxDepth then return end
    for _, c in ipairs(obj:GetChildren()) do
        local txt = ""
        if c:IsA("TextLabel") or c:IsA("TextButton") or c:IsA("TextBox") then
            txt = " | text=\"" .. cleanText(c) .. "\""
        end
        local vis = ""
        if c:IsA("GuiObject") then vis = " | Visible=" .. tostring(c.Visible) end
        print(string.rep("   ", depth) .. "- " .. c.Name .. " (" .. c.ClassName .. ")" .. txt .. vis)
        dumpTree(c, depth + 1, maxDepth)
    end
end

-- from a hit, climb up looking for a container that holds the item list
local function reportHit(hit, why)
    local path = getPath(hit)
    if seen[path] then return end
    seen[path] = true

    print("=========================================")
    print("HIT (" .. why .. "): " .. path)
    print("  class: " .. hit.ClassName .. " | onScreen=" .. tostring(onScreen(hit)))
    if hit:IsA("TextLabel") or hit:IsA("TextButton") then
        print("  text: \"" .. cleanText(hit) .. "\"")
    end

    -- climb ancestors, report each + look for a ScrollingFrame
    local cur = hit.Parent
    local scroll = nil
    local levels = 0
    while cur and cur ~= PlayerGui and levels < 8 do
        print("  ^ ancestor: " .. cur.Name .. " (" .. cur.ClassName .. ")")
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
        print("  >>> LIST CONTAINER: " .. getPath(scroll))
        print("  >>> children: " .. #scroll:GetChildren() .. " | onScreen=" .. tostring(onScreen(scroll)))
        local n = 0
        for _, entry in ipairs(scroll:GetChildren()) do
            if entry:IsA("GuiObject") then
                n = n + 1
                if n <= MAX_ENTRIES_DUMPED then
                    print("  --- ENTRY: " .. entry.Name .. " (" .. entry.ClassName .. ") Visible=" .. tostring(entry.Visible))
                    dumpTree(entry, 1, 3)
                else
                    print("  --- (entry) " .. entry.Name)
                end
            end
        end
    else
        print("  !!! no ScrollingFrame found near this hit — dumping parent tree instead")
        if hit.Parent then dumpTree(hit.Parent, 1, 2) end
    end
    print("=========================================")
end

local function scan()
    for _, gui in ipairs(PlayerGui:GetDescendants()) do
        local ok = pcall(function()
            if matches(gui.Name) and (gui:IsA("Frame") or gui:IsA("ScrollingFrame") or gui:IsA("ScreenGui")) then
                reportHit(gui, "name")
            elseif (gui:IsA("TextLabel") or gui:IsA("TextButton")) and matches(cleanText(gui)) then
                reportHit(gui, "text")
            end
        end)
    end
end

-- also list every enabled ScreenGui once so we know what's loaded
print("--- ScreenGuis in PlayerGui ---")
for _, g in ipairs(PlayerGui:GetChildren()) do
    if g:IsA("ScreenGui") then
        print("  " .. g.Name .. " | Enabled=" .. tostring(g.Enabled))
    end
end
print("-------------------------------")

while true do
    pcall(scan)
    wait(SCAN_INTERVAL)
end
