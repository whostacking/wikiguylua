local utils = require("./utils")
local config = require("../config")

local function handleFileRequest(wikiConfig, fileName, interaction)
    local searchTitle = fileName
    if not fileName:lower():find("^file:") then
        searchTitle = "File:" .. fileName
    end

    local params = {
        action = "query",
        titles = searchTitle,
        prop = "imageinfo",
        iiprop = "url|mime",
        format = "json",
        redirects = 1
    }

    interaction:acknowledge()

    local url = wikiConfig.apiEndpoint .. "?" .. utils.build_query(params)
    local res = utils.fetch(url)

    if not res.ok then
        interaction:reply({ content = "Error fetching file info.", ephemeral = true })
        return
    end

    local json_data = res.json()
    local pages = json_data.query and json_data.query.pages
    if not pages then
        interaction:reply({ content = "File not found.", ephemeral = true })
        return
    end

    local _, page = next(pages)
    if page.missing then
        interaction:reply({ content = 'File "' .. fileName .. '" not found on [' .. wikiConfig.name .. '](<' .. wikiConfig.baseUrl .. '>).', ephemeral = true })
        return
    end

    local info = page.imageinfo and page.imageinfo[1]
    if not info then
        interaction:reply({ content = "Could not retrieve file information.", ephemeral = true })
        return
    end

    local fileUrl = info.url
    local mime = info.mime or ""
    local title = page.title

    local isPictureOrVideo = mime:find("^image/") or mime:find("^video/")

    local parts = {}
    for part in title:gmatch("[^:]+") do
        table.insert(parts, utils.url_path_encode(part:gsub(" ", "_")))
    end
    local pageLink = wikiConfig.articlePath .. table.concat(parts, ":")

    local embed = {
        title = title,
        url = pageLink,
        color = 0xff6600
    }

    if isPictureOrVideo then
        embed.image = { url = fileUrl }
    else
        embed.description = "[Download File](" .. fileUrl .. ")"
    end

    interaction:reply({
        embed = embed
    })
end

return {
    handleFileRequest = handleFileRequest
}
