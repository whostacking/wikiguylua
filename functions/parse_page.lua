local utils = require("./utils")
local config = require("../config")

-- --- CACHING ---
local CANONICAL_CACHE = {}
local PAGE_DATA_CACHE = {}
local MAX_CACHE_SIZE = 500

local function pruneCache(cache)
    local count = 0
    local keys = {}
    for k in pairs(cache) do
        count = count + 1
        table.insert(keys, k)
    end
    if count > MAX_CACHE_SIZE then
        cache[keys[1]] = nil
    end
end

-- --- UTILITIES ---
local function getFullSizeImageUrl(url)
    if not url or not url:find('/thumb/') then return url end

    -- Very simple replacement for MediaWiki thumbnail URLs
    local newUrl = url:gsub("/thumb/", "/")
    local lastSlash = newUrl:match(".*/()")
    if lastSlash then
        newUrl = newUrl:sub(1, lastSlash - 2)
    end
    return newUrl
end

-- Improved HTML to Markdown converter
local function htmlToMarkdown(html, baseUrl)
    if not html then return "" end

    local text = html

    -- Remove unwanted elements
    text = text:gsub("<style.-</style>", "")
    text = text:gsub("<script.-</script>", "")
    text = text:gsub("<table.-</table>", "")
    text = text:gsub("<div class=\"infobox\".-</div>", "")
    text = text:gsub("<div class=\"navbox\".-</div>", "")
    text = text:gsub("<sup class=\"reference\".-</sup>", "")

    -- Formatting
    text = text:gsub("<b>(.-)</b>", "**%1**")
    text = text:gsub("<strong>(.-)</strong>", "**%1**")
    text = text:gsub("<i>(.-)</i>", "*%1*")
    text = text:gsub("<em>(.-)</em>", "*%1*")

    -- Links
    text = text:gsub('<a.-href="([^"]+)".->(.-)</a>', function(href, content)
        if not href:find("^http") then
            if href:find("^/") then
                href = baseUrl:match("(https?://[^/]+)") .. href
            else
                href = baseUrl .. href
            end
        end
        local cleanContent = content:gsub("<[^>]+>", ""):gsub("%[", "\\["):gsub("%]", "\\]")
        return "[" .. cleanContent .. "](<" .. href .. ">)"
    end)

    -- Lists
    text = text:gsub("<li>(.-)</li>", "* %1\n")

    -- Headers
    text = text:gsub("<h2><span class=\"mw%-headline\".->(.-)</span>.-</h2>", "## %1\n")
    text = text:gsub("<h3><span class=\"mw%-headline\".->(.-)</span>.-</h3>", "### %1\n")

    -- Line breaks and paragraphs
    text = text:gsub("<br%s*/?>", "\n")
    text = text:gsub("</p>", "\n\n")
    text = text:gsub("</div>", "\n")

    -- Final cleanup of all remaining tags
    text = text:gsub("<[^>]+>", "")

    -- Entities
    text = text:gsub("&nbsp;", " ")
    text = text:gsub("&quot;", '"')
    text = text:gsub("&amp;", "&")
    text = text:gsub("&lt;", "<")
    text = text:gsub("&gt;", ">")

    -- Whitespace
    text = text:gsub("\n%s*\n%s*\n", "\n\n")
    text = text:gsub(" +", " ")

    return text:gsub("^%s*(.-)%s*$", "%1")
end

-- --- WIKI API FUNCTIONS ---

local function findCanonicalTitle(input, wikiConfig)
    if not input then return nil end
    local raw = input:gsub("^%s*(.-)%s*$", "%1")
    local wikiKey = wikiConfig.prefix or wikiConfig.baseUrl
    local cacheKey = wikiKey .. ":" .. raw:lower()

    if CANONICAL_CACHE[cacheKey] then return CANONICAL_CACHE[cacheKey] end

    local params = {
        action = "query",
        format = "json",
        titles = raw,
        redirects = "1",
        indexpageids = "1"
    }

    local url = wikiConfig.apiEndpoint .. "?" .. utils.build_query(params)
    local res = utils.fetch(url)
    if not res.ok then return nil end

    local json_data = res.json()
    local pageId = json_data.query and json_data.query.pageids and json_data.query.pageids[1]
    local page = json_data.query and json_data.query.pages and json_data.query.pages[pageId]

    if page and not page.missing then
        local canonical = page.title
        CANONICAL_CACHE[cacheKey] = canonical
        pruneCache(CANONICAL_CACHE)
        return canonical
    end

    -- Fallback search
    params = {
        action = "query",
        list = "search",
        srsearch = "intitle:" .. raw,
        srlimit = "1",
        format = "json"
    }
    url = wikiConfig.apiEndpoint .. "?" .. utils.build_query(params)
    res = utils.fetch(url)
    if res.ok then
        json_data = res.json()
        local topResult = json_data.query and json_data.query.search and json_data.query.search[1]
        if topResult then
            local canonical = topResult.title
            CANONICAL_CACHE[cacheKey] = canonical
            pruneCache(CANONICAL_CACHE)
            return canonical
        end
    end

    return nil
end

local function getPageData(input, wikiConfig)
    if not input then return nil end
    local raw = input:gsub("^%s*(.-)%s*$", "%1")
    local wikiKey = wikiConfig.prefix or wikiConfig.baseUrl
    local cacheKey = wikiKey .. ":" .. raw:lower()

    if CANONICAL_CACHE[cacheKey] then
        local canonical = CANONICAL_CACHE[cacheKey]
        local pageCacheKey = wikiKey .. ":" .. canonical
        if PAGE_DATA_CACHE[pageCacheKey] then
            local data = PAGE_DATA_CACHE[pageCacheKey]
            return { canonical = canonical, extract = data.extract, imageUrl = data.imageUrl }
        end
    end

    local params = {
        action = "query",
        format = "json",
        titles = raw,
        prop = "extracts|pageimages",
        exintro = "1",
        pithumbsize = "512",
        redirects = "1",
        indexpageids = "1"
    }

    local url = wikiConfig.apiEndpoint .. "?" .. utils.build_query(params)
    local res = utils.fetch(url)
    if not res.ok then return nil end

    local json_data = res.json()
    local pageId = json_data.query and json_data.query.pageids and json_data.query.pageids[1]
    local page = json_data.query and json_data.query.pages and json_data.query.pages[pageId]

    if not page or page.missing then
        local canonical = findCanonicalTitle(raw, wikiConfig)
        if canonical and canonical ~= raw then
            return getPageData(canonical, wikiConfig)
        end
        return nil
    end

    local canonical = page.title
    local extract = page.extract and htmlToMarkdown(page.extract, wikiConfig.baseUrl) or nil
    local imageUrl = getFullSizeImageUrl(page.thumbnail and page.thumbnail.source or nil)

    local data = { extract = extract, imageUrl = imageUrl }
    CANONICAL_CACHE[cacheKey] = canonical
    PAGE_DATA_CACHE[wikiKey .. ":" .. canonical] = data
    pruneCache(CANONICAL_CACHE)
    pruneCache(PAGE_DATA_CACHE)

    return { canonical = canonical, extract = extract, imageUrl = imageUrl }
end

local function getSectionIndex(pageTitle, sectionName, wikiConfig)
    local canonical = findCanonicalTitle(pageTitle, wikiConfig) or pageTitle
    local params = {
        action = "parse",
        format = "json",
        prop = "sections",
        page = canonical
    }

    local url = wikiConfig.apiEndpoint .. "?" .. utils.build_query(params)
    local res = utils.fetch(url)
    if not res.ok then return nil end

    local json_data = res.json()
    local sections = json_data.parse and json_data.parse.sections or {}

    for _, s in ipairs(sections) do
        local cleanLine = s.line:gsub("<[^>]+>", "")
        if cleanLine:lower() == sectionName:lower() then
            return {
                index = s.index,
                line = cleanLine
            }
        end
    end
    return nil
end

local function getSectionContent(pageTitle, sectionName, wikiConfig)
    local sectionInfo = getSectionIndex(pageTitle, sectionName, wikiConfig)
    if not sectionInfo then return nil end

    local params = {
        action = "parse",
        format = "json",
        prop = "text",
        page = pageTitle,
        section = sectionInfo.index
    }

    local url = wikiConfig.apiEndpoint .. "?" .. utils.build_query(params)
    local res = utils.fetch(url)
    if not res.ok then return nil end

    local json_data = res.json()
    local html = json_data.parse and json_data.parse.text and json_data.parse.text["*"]
    if not html then return nil end

    -- Gallery extraction would be here, but for now we skip to keep it manageable

    return {
        content = htmlToMarkdown(html, wikiConfig.baseUrl),
        displayTitle = sectionInfo.line
    }
end

local function getLeadSection(pageTitle, wikiConfig)
    local data = getPageData(pageTitle, wikiConfig)
    return data and data.extract or nil
end

local function parseWikiLinks(text, wikiConfig)
    if not text then return "" end
    -- [[Page|Label]] or [[Page]]
    return (text:gsub("%[%[([^%]|]+)%|?([^%]]*)%]%]", function(page, label)
        local display = (label ~= "" and label) or page
        local canonical = findCanonicalTitle(page, wikiConfig) or page
        local parts = {}
        for part in canonical:gmatch("[^:]+") do
            table.insert(parts, utils.url_path_encode(part:gsub(" ", "_")))
        end
        local url = wikiConfig.articlePath .. table.concat(parts, ":")
        return "[**" .. display .. "**](<" .. url .. ">)"
    end))
end

local function parseTemplates(text, wikiConfig)
    if not text then return "" end
    -- {{Template|Param}}
    return (text:gsub("{{([^%|%s}]+)%|?([^}]*)}}", function(templateName, param)
        local canonical = findCanonicalTitle(templateName, wikiConfig)
        if not canonical then return "I don't know." end

        local content = getLeadSection(canonical, wikiConfig)
        local parts = {}
        for part in canonical:gmatch("[^:]+") do
            table.insert(parts, utils.url_path_encode(part:gsub(" ", "_")))
        end
        local url = wikiConfig.articlePath .. table.concat(parts, ":")

        if content then
            return "**" .. templateName .. "** → " .. content:sub(1, 1000) .. "\n<" .. url .. ">"
        else
            return "I don't know."
        end
    end))
end

return {
    findCanonicalTitle = findCanonicalTitle,
    getPageData = getPageData,
    getSectionContent = getSectionContent,
    getLeadSection = getLeadSection,
    parseWikiLinks = parseWikiLinks,
    parseTemplates = parseTemplates,
    getFullSizeImageUrl = getFullSizeImageUrl
}
