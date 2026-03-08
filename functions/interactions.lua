local parse_page = require("./parse_page")
local parse_file = require("./parse_file")
local contribscores = require("./contribscores")
local speedrun = require("./speedrun")
local config = require("../config")
local commands_lib = require("./commands")
local utils = require("./utils")

local responseMap = {}
local botToAuthorMap = {}

local function pruneMap(map, maxSize)
    maxSize = maxSize or 1000
    local count = 0
    local keys = {}
    for k in pairs(map) do
        count = count + 1
        table.insert(keys, k)
    end
    if count > maxSize then
        map[keys[1]] = nil
    end
end

local function fetchWikiChoices(wikiConfig, params, listKey, isFileSearch)
    local url = wikiConfig.apiEndpoint .. "?" .. utils.build_query(params)
    local res = utils.fetch(url)
    if not res.ok then return {} end

    local json = res.json()
    local items = json.query and json.query[listKey] or {}
    local results = {}

    for _, item in ipairs(items) do
        local title = item.title or item.name
        local value = title

        if isFileSearch and title:lower():find("^file:") then
            title = title:sub(6)
            value = value:sub(6)
        end

        if #title <= 100 then
            table.insert(results, { name = title, value = value })
        end
    end
    return results
end

local function getAutocompleteChoices(wikiConfig, listType, prefix)
    local isFileSearch = listType == 'allimages'
    local namespace = isFileSearch and '6' or '0'
    local searchPrefix = prefix:gsub("^%s*(.-)%s*$", "%1")

    if isFileSearch and searchPrefix:lower():find("^file:") then
        searchPrefix = searchPrefix:sub(6):gsub("^%s*(.-)%s*$", "%1")
    end

    if searchPrefix == '' then
        local params = {
            action = 'query',
            format = 'json',
            list = listType,
            [isFileSearch and 'aiprefix' or 'apprefix'] = '',
            [isFileSearch and 'ailimit' or 'aplimit'] = '25'
        }
        return fetchWikiChoices(wikiConfig, params, listType, isFileSearch)
    end

    local psParams = {
        action = 'query',
        format = 'json',
        list = 'prefixsearch',
        pssearch = searchPrefix,
        psnamespace = namespace,
        pslimit = '25'
    }

    local srParams = {
        action = 'query',
        format = 'json',
        list = 'search',
        srsearch = 'intitle:"' .. searchPrefix:gsub('"', '') .. '"',
        srnamespace = namespace,
        srlimit = '25'
    }

    local psResults = fetchWikiChoices(wikiConfig, psParams, 'prefixsearch', isFileSearch)
    local srResults = fetchWikiChoices(wikiConfig, srParams, 'search', isFileSearch)

    local seen = {}
    local finalChoices = {}

    for _, results in ipairs({psResults, srResults}) do
        for _, choice in ipairs(results) do
            local key = choice.value:lower()
            if not seen[key] then
                seen[key] = true
                table.insert(finalChoices, choice)
                if #finalChoices >= 25 then break end
            end
        end
        if #finalChoices >= 25 then break end
    end

    return finalChoices
end

local function buildPageEmbed(title, content, imageUrl, wikiConfig)
    local url = wikiConfig.articlePath .. title:gsub(" ", "_")
    return {
        title = title,
        description = content,
        url = url,
        color = 0xff6600,
        thumbnail = { url = imageUrl or "https://upload.wikimedia.org/wikipedia/commons/8/89/HD_transparent_picture.png" },
        footer = { text = wikiConfig.name, icon_url = "https://upload.wikimedia.org/wikipedia/commons/8/89/HD_transparent_picture.png" }
    }
end

local function handleUserRequest(wikiConfig, rawPageName, messageOrInteraction, botMessageToEdit)
    if rawPageName:lower():find("^file:") then
        return parse_file.handleFileRequest(wikiConfig, rawPageName:sub(6), messageOrInteraction)
    end

    local sectionName = nil
    if rawPageName:find("#") then
        local parts = {}
        for part in rawPageName:gmatch("[^#]+") do table.insert(parts, part) end
        rawPageName = parts[1]:gsub("^%s*(.-)%s*$", "%1")
        sectionName = parts[2] and parts[2]:gsub("^%s*(.-)%s*$", "%1")
    end

    local content = nil
    local displayTitle = nil
    local imageUrl = nil
    local canonical = nil

    if sectionName then
        canonical = parse_page.findCanonicalTitle(rawPageName, wikiConfig)
        if canonical then
            local sectionData = parse_page.getSectionContent(canonical, sectionName, wikiConfig)
            if sectionData then
                content = sectionData.content
                displayTitle = canonical .. " § " .. sectionData.displayTitle
            else
                content = "No content available."
                displayTitle = canonical .. "#" .. sectionName
            end
            local pageData = parse_page.getPageData(canonical, wikiConfig)
            imageUrl = pageData and pageData.imageUrl
        end
    else
        local pageData = parse_page.getPageData(rawPageName, wikiConfig)
        if pageData then
            canonical = pageData.canonical
            content = pageData.extract
            imageUrl = pageData.imageUrl
            displayTitle = canonical
        end
    end

    if canonical then
        content = content or "No content available."
        local embed = buildPageEmbed(displayTitle, content:sub(1, 1000), imageUrl, wikiConfig)

        if botMessageToEdit then
            return botMessageToEdit:edit({ embed = embed })
        end

        local response
        if messageOrInteraction.reply then
            response = messageOrInteraction:reply({
                embed = embed
            })
        end
        return response
    else
        local msg = 'Page "' .. rawPageName .. '" not found on [' .. wikiConfig.name .. ' Wiki](<' .. wikiConfig.baseUrl .. '>).'
        if messageOrInteraction.reply then
            messageOrInteraction:reply({ content = msg, ephemeral = true })
        end
    end
end

local function handleInteraction(interaction)
    if interaction.type == 4 then -- Autocomplete
        local commandName = interaction.data.name
        if commandName == 'parse' or commandName == 'wiki' then
            local focusedOption = nil
            local wikiKey = nil
            for _, opt in ipairs(interaction.data.options) do
                if opt.name == 'wiki' then wikiKey = opt.value end
                if opt.focused then focusedOption = opt end
            end

            if not wikiKey or not focusedOption then return end

            local wikiConfig = config.WIKIS[wikiKey]
            if not wikiConfig then return interaction:respond({}) end

            local listType = (focusedOption.name == 'page') and 'allpages' or (focusedOption.name == 'file' and 'allimages' or nil)
            if not listType then return interaction:respond({}) end

            local choices = getAutocompleteChoices(wikiConfig, listType, focusedOption.value)
            interaction:respond(choices)
        end
        return
    end

    if interaction.type == 2 then -- ApplicationCommand
        local commandName = interaction.data.name

        if commandName == 'lbwiki' then
            contribscores.handleContribScoresRequest(interaction)
        elseif commandName == 'lbspeedrun' then
            local subCommand = interaction.data.options[1].name
            local options = interaction.data.options[1].options
            if subCommand == 'sb64' then
                local categoryId, character, glitches
                for _, opt in ipairs(options) do
                    if opt.name == 'category' then categoryId = opt.value
                    elseif opt.name == 'character' then character = opt.value
                    elseif opt.name == 'glitches' then glitches = opt.value end
                end

                local variables = {}
                variables[commands_lib.SB64_VARIABLES.CHARACTER] = character or commands_lib.SB64_DEFAULTS.CHARACTER
                variables[commands_lib.SB64_VARIABLES.GLITCHES] = (glitches ~= nil) and (glitches and commands_lib.SB64_DEFAULTS.GLITCHES_ON or commands_lib.SB64_DEFAULTS.GLITCHES_OFF) or nil

                speedrun.handleSpeedrunRequest(interaction, 'sb64', categoryId, nil, variables)
            elseif subCommand == 'sr' then
                local categoryId, levelId, events
                for _, opt in ipairs(options) do
                    if opt.name == 'category' then categoryId = opt.value
                    elseif opt.name == 'level' then levelId = opt.value
                    elseif opt.name == 'events' then events = opt.value end
                end

                local variables = {}
                variables[commands_lib.SR_VARIABLES.EVENTS] = events or commands_lib.SR_DEFAULTS.EVENTS

                speedrun.handleSpeedrunRequest(interaction, 'sr', categoryId, levelId, variables)
            end
        elseif commandName == 'wiki' then
            local wikiKey = interaction.data.options[1].value
            local wikiConfig = config.WIKIS[wikiKey]
            if wikiConfig then
                interaction:reply(wikiConfig.baseUrl)
            end
        elseif commandName == 'parse' then
            local subCommand = interaction.data.options[1].name
            local options = interaction.data.options[1].options
            local wikiKey, pageName, fileName
            for _, opt in ipairs(options) do
                if opt.name == 'wiki' then wikiKey = opt.value
                elseif opt.name == 'page' then pageName = opt.value
                elseif opt.name == 'file' then fileName = opt.value end
            end

            local wikiConfig = config.WIKIS[wikiKey]
            if wikiConfig then
                if subCommand == 'page' then
                    handleUserRequest(wikiConfig, pageName, interaction)
                elseif subCommand == 'file' then
                    parse_file.handleFileRequest(wikiConfig, fileName, interaction)
                end
            end
        end
    end
end

return {
    handleInteraction = handleInteraction,
    handleUserRequest = handleUserRequest,
    buildPageEmbed = buildPageEmbed,
    responseMap = responseMap,
    botToAuthorMap = botToAuthorMap,
    pruneMap = pruneMap
}
