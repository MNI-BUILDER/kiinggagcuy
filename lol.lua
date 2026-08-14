-- MATERIAL DEALER — REMOTE/MODULE PROBE (no UI needed)
-- Read-only: only invokes with harmless get-style args. Nothing named buy/purchase.
print("🔎 PROBE — reading DealerData / MaterialList / MaterialDealer remote")

local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"

local MAX_LINE, CHUNK_SIZE = 250, 1800
local MAX_DEPTH, MAX_KEYS  = 4, 80

local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")

local buffer = {}
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

-- table serializer that survives instances / weird keys
local function ser(v, depth, pad)
    depth, pad = depth or 1, pad or "  "
    local t = typeof(v)
    if t == "table" then
        if depth > MAX_DEPTH then out(pad .. "{...depth capped...}") return end
        local n = 0
        for k, val in pairs(v) do
            n = n + 1
            if n > MAX_KEYS then out(pad .. "... (" .. n .. "+ keys)") break end
            local kt = typeof(val)
            if kt == "table" then
                out(pad .. "[" .. tostring(k) .. "] = {")
                ser(val, depth + 1, pad .. "  ")
                out(pad .. "}")
            elseif kt == "Instance" then
                out(pad .. "[" .. tostring(k) .. "] = <" .. val.ClassName .. "> " .. val.Name)
            else
                out(pad .. "[" .. tostring(k) .. "] = " .. tostring(val) .. "  (" .. kt .. ")")
            end
        end
        if n == 0 then out(pad .. "(empty table)") end
    else
        out(pad .. tostring(v) .. "  (" .. t .. ")")
    end
end

local chest = RS:WaitForChild("Chest")

-- 1) Gui templates (find the dealer window template)
out("=== Chest.Gui children ===")
pcall(function()
    local gui = chest:FindFirstChild("Gui")
    if gui then
        for _, c in ipairs(gui:GetChildren()) do
            out(c.Name .. " (" .. c.ClassName .. ") kids=" .. #c:GetChildren())
        end
    else out("no Chest.Gui") end
end)

-- 2) DealerData module
out("=== DealerData ===")
local ok, data = pcall(function() return require(chest.Modules.DealerData) end)
if ok then ser(data, 1, "  ") else out("require failed: " .. tostring(data)) end
flush()

-- 3) MaterialList module
out("=== MaterialList ===")
local ok2, mats = pcall(function() return require(chest.Modules.MaterialList) end)
if ok2 then ser(mats, 1, "  ") else out("require failed: " .. tostring(mats)) end
flush()

-- 4) probe the remote (read-only style args)
local remote = chest.Remotes.Functions.MaterialDealer
out("=== MaterialDealer remote probe ===")
out("class=" .. remote.ClassName)

local ATTEMPTS = {
    {label = "no args",   args = {}},
    {label = '"Get"',     args = {"Get"}},
    {label = '"GetData"', args = {"GetData"}},
    {label = '"GetStock"',args = {"GetStock"}},
    {label = '"GetShop"', args = {"GetShop"}},
    {label = '"Info"',    args = {"Info"}},
    {label = '"Check"',   args = {"Check"}},
    {label = '"Refresh"', args = {"Refresh"}},
}

for _, a in ipairs(ATTEMPTS) do
    local ok3, res = pcall(function() return remote:InvokeServer(unpack(a.args)) end)
    out("--- invoke " .. a.label .. " -> " .. (ok3 and "OK" or "ERR"))
    if ok3 then ser(res, 1, "    ") else out("    " .. tostring(res)) end
    wait(0.4)
end

out("=== probe done ===")
flush()
print("✅ done — check Discord")
