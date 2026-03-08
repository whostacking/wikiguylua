local http = require('coro-http')
local json = require('json')

local function fetch(url, options)
    local headers = {
        {"User-Agent", "DiscordBot/Orbital (Discordia)"}
    }
    if options and options.headers then
        for k, v in pairs(options.headers) do
            table.insert(headers, {k, v})
        end
    end

    local res, body = http.request("GET", url, headers)

    local success = res.code >= 200 and res.code < 300

    local function json_parse()
        return json.decode(body)
    end

    return {
        ok = success,
        status = res.code,
        json = json_parse,
        body = body
    }
end

-- For query/form values (spaces to '+')
local function url_encode(str)
    if str then
        str = tostring(str)
        str = str:gsub("\n", "\r\n")
        str = str:gsub("([^A-Za-z0-9%%-%%_%%.%%~])", function(c)
            return ("%%%02X"):format(string.byte(c))
        end)
        str = str:gsub(" ", "+")
    end
    return str
end

-- For URL path segments (spaces to '%20')
local function url_path_encode(str)
    if str then
        str = tostring(str)
        str = str:gsub("([^A-Za-z0-9%%-%%_%%.%%~])", function(c)
            return ("%%%02X"):format(string.byte(c))
        end)
        str = str:gsub(" ", "%%20")
    end
    return str
end

local function build_query(params)
    local query = ""
    for k, v in pairs(params) do
        if query ~= "" then query = query .. "&" end
        query = query .. url_encode(tostring(k)) .. "=" .. url_encode(tostring(v))
    end
    return query
end

return {
    fetch = fetch,
    url_encode = url_encode,
    url_path_encode = url_path_encode,
    build_query = build_query
}
