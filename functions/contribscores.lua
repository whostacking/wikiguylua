local utils = require("./utils")
local config = require("../config")

local function getContributionScores(wikiConfig)
    local params = {
        action = "parse",
        format = "json",
        text = "{{Special:ContributionScores/10/7}}",
        prop = "text",
        disablelimitreport = "true"
    }

    local url = wikiConfig.apiEndpoint .. "?" .. utils.build_query(params)
    local res = utils.fetch(url)

    if not res.ok then
        return { error = "Failed to fetch leaderboard data." }
    end

    local json_data = res.json()
    local html = json_data.parse and json_data.parse.text and json_data.parse.text["*"]

    if not html then
        return {
            title = "Special:ContributionScores",
            result = "No content available."
        }
    end

    -- Basic parsing (Lua's regex is limited, so we do what we can)
    local userData = {}
    for row in html:gmatch('<tr class="">(.-)</tr>') do
        local user = row:match('<bdi>(.-)</bdi>') or "Unknown"

        local stats = {}
        for stat in row:gmatch('>([%d,]+)%s*</td>') do
            table.insert(stats, stat)
        end

        local score = stats[2] and stats[2]:gsub(",", "") or "0"
        local edits = stats[4] or "0"

        table.insert(userData, { user = user, score = score, edits = edits })
    end

    if #userData == 0 then
        return {
            title = "Special:ContributionScores",
            result = "No content available."
        }
    end

    local dataSummary = "## Edit leaderboard for [" .. wikiConfig.name .. " Wiki](" .. wikiConfig.articlePath .. "Special:ContributionScores) <:" .. wikiConfig.name .. ":" .. wikiConfig.emoji .. ">\n"
    dataSummary = dataSummary .. "-# Top 10 users over the past 7 days\n\n"

    local maxScoreLength = 1
    local maxEditLength = 1
    for _, d in ipairs(userData) do
        maxScoreLength = math.max(maxScoreLength, #d.score)
        maxEditLength = math.max(maxEditLength, #d.edits)
    end

    for i, data in ipairs(userData) do
        local paddedScore = string.rep(" ", maxScoreLength - #data.score) .. data.score
        local paddedEdits = string.rep(" ", maxEditLength - #data.edits) .. data.edits
        dataSummary = dataSummary .. i .. ". <:playerpoint:1472433775593000961> `" .. paddedScore .. "`    ✏️ `" .. paddedEdits .. "`    **[@" .. data.user .. "](" .. wikiConfig.articlePath .. "User:" .. data.user .. ")**\n"
        if i >= 10 then break end
    end

    return {
        title = "Special:ContributionScores",
        result = dataSummary
    }
end

local function handleContribScoresRequest(interaction, params)
    local wikiKey = interaction.data.options[1].options[1].value
    local wikiConfig = config.WIKIS[wikiKey]

    if not wikiConfig then
        interaction:reply({ content = 'Unknown wiki selection.', ephemeral = true })
        return
    end

    interaction:acknowledge()
    local result = getContributionScores(wikiConfig)

    if result.error then
        interaction:reply({ content = result.error })
    else
        -- Using a simple embed for now since Discordia doesn't have ContainerBuilder built-in
        interaction:reply({
            embed = {
                title = result.title,
                description = result.result,
                color = 0xff6600
            }
        })
    end
end

return {
    getContributionScores = getContributionScores,
    handleContribScoresRequest = handleContribScoresRequest
}
