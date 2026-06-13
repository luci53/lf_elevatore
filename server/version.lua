-- Lightweight update checker. Compares the local resource version against the
-- fxmanifest on GitHub and prints a one-line notice if a newer release exists.
-- Disable with:  setr lf_elevatore:versionCheck false

local REPO = 'luci53/lf_elevatore'
local MANIFEST_URL = ('https://raw.githubusercontent.com/%s/main/fxmanifest.lua'):format(REPO)

local resourceName = GetCurrentResourceName()
local localVersion = GetResourceMetadata(resourceName, 'version', 0)

---Parse "x.y.z" into a comparable list of numbers.
---@param v string
---@return number[]
local function parse(v)
    local parts = {}
    for n in tostring(v):gmatch('%d+') do
        parts[#parts + 1] = tonumber(n)
    end
    return parts
end

---@return number -1 if a<b, 0 if equal, 1 if a>b
local function compare(a, b)
    local pa, pb = parse(a), parse(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

CreateThread(function()
    if GetConvar('lf_elevatore:versionCheck', 'true') ~= 'true' then return end
    if not localVersion or localVersion == '' then return end

    PerformHttpRequest(MANIFEST_URL, function(status, body)
        if status ~= 200 or not body then return end

        local remote = body:match("version%s+'([%d%.]+)'") or body:match('version%s+"([%d%.]+)"')
        if not remote then return end

        local result = compare(localVersion, remote)
        if result < 0 then
            print(('^3[lf_elevatore]^0 A new version is available: ^2%s^0 (you have ^1%s^0) -> https://github.com/%s'):format(remote, localVersion, REPO))
        elseif result == 0 then
            print(('^2[lf_elevatore]^0 You are running the latest version (%s)'):format(localVersion))
        end
    end, 'GET')
end)
