local utils = require("./utils")
local config = require("../config")
local commands_lib = require("./commands")

local SB64_PER_LEVEL_CATEGORIES = {
    [commands_lib.SB64_LEVEL_IDS.W1_HUB] = true,
    [commands_lib.SB64_LEVEL_IDS.W2_HUB] = true,
    [commands_lib.SB64_LEVEL_IDS.W3_HUB] = true,
    [commands_lib.SB64_LEVEL_IDS.W4_HUB] = true,
    [commands_lib.SB64_LEVEL_IDS.W5_HUB] = true,
    [commands_lib.SB64_LEVEL_IDS.STARBURST_GALAXY] = true,
    [commands_lib.SB64_LEVEL_IDS.ALL_DELUXE] = true,
}

local GAMES = {
    sb64 = {
        id = "9d3wv0w1",
        name = "SUPER BLOX 64"
    },
    sr = {
        id = "o6gk4xn1",
        name = "Superstar Racers"
    }
}

local GAME_WIKI_MAP = {
    sb64 = 'super-blox-64',
    sr = 'superstar-racers'
}

local function formatTime(seconds, forceMinutes)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60

    local parts = {}
    if h > 0 then table.insert(parts, h .. "h") end
    if m > 0 or h > 0 or (forceMinutes and h == 0) then table.insert(parts, m .. "m") end

    table.insert(parts, string.format("%.3fs", s))

    return table.concat(parts, " ")
end

local function getLeaderboardData(gameId, categoryId, levelId, variables)
    local url = "https://www.speedrun.com/api/v1/leaderboards/" .. gameId
    if levelId then
        url = url .. "/level/" .. levelId .. "/" .. categoryId
    else
        url = url .. "/category/" .. categoryId
    end

    local params = {
        top = 10,
        embed = "players,category" .. (levelId and ",level" or "")
    }

    for k, v in pairs(variables) do
        if v then
            params["var-" .. k] = v
        end
    end

    url = url .. "?" .. utils.build_query(params)

    local res = utils.fetch(url)
    if not res.ok then
        local err_data = res.json()
        error(err_data and err_data.message or "Speedrun.com API error")
    end
    return res.json()
end

local function handleSpeedrunRequest(interaction, gameKey, categoryId, levelId, variables)
    local game = GAMES[gameKey]

    if gameKey == 'sb64' and not levelId then
        if SB64_PER_LEVEL_CATEGORIES[categoryId] then
            levelId = categoryId
            categoryId = commands_lib.SB64_CATEGORY_IDS.PER_LEVEL_OVERALL
        end
    end

    interaction:acknowledge()

    local success, responseJson = pcall(getLeaderboardData, game.id, categoryId, levelId, variables)
    if not success then
        interaction:reply({ content = "Error: " .. tostring(responseJson), ephemeral = true })
        return
    end

    local leaderboard = responseJson.data

    if not leaderboard.runs or #leaderboard.runs == 0 then
        interaction:reply({ content = "No runs found for this category.", ephemeral = true })
        return
    end

    local forceMinutes = false
    for _, runItem in ipairs(leaderboard.runs) do
        if runItem.run.times.primary_t >= 60 then
            forceMinutes = true
            break
        end
    end

    local playersMap = {}
    for _, p in ipairs(leaderboard.players.data) do
        if p.rel == "user" then
            playersMap[p.id] = p.names.international
        else
            playersMap[p.id] = p.name -- Guest
        end
    end

    local categoryName = leaderboard.category.data.name
    local levelName = leaderboard.level and leaderboard.level.data.name

    local mainTitle = levelName or game.name
    local description = "## " .. mainTitle .. "\n"
    description = description .. "-# " .. categoryName
    if levelName then
        description = description .. " @ " .. game.name
    end
    description = description .. "\n\n"

    for _, runItem in ipairs(leaderboard.runs) do
        local place = runItem.place
        local run = runItem.run
        local players = {}
        for _, p in ipairs(run.players) do
            if p.rel == "user" then
                table.insert(players, playersMap[p.id] or "Unknown")
            else
                table.insert(players, p.name or "Guest")
            end
        end
        local playerStr = table.concat(players, " @")
        local time = formatTime(run.times.primary_t, forceMinutes)
        description = description .. place .. ". <:flag:1477323785366540439> `" .. time .. "`    [**@" .. playerStr .. "**](" .. run.weblink .. ")\n"
    end

    interaction:reply({
        embed = {
            description = description,
            color = 0xff6600,
            footer = {
                text = "View full leaderboard: " .. leaderboard.weblink
            }
        }
    })
end

return {
    handleSpeedrunRequest = handleSpeedrunRequest
}
