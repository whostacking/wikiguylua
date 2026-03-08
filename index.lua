local discordia = require('discordia')
local client = discordia.Client()

-- Seed the RNG
math.randomseed(os.time())

local config = require('./config')
local presence = require('./functions/presence')
local interactions = require('./functions/interactions')
local commands_lib = require('./functions/commands')
local server = require('./functions/server')

-- Handle interactions (slash commands)
local has_slash, slash = pcall(require, 'discordia-slash')
local has_inter, inter = pcall(require, 'discordia-interactions')

if has_slash then
    -- Note: discordia-slash usually requires being called with the client
    -- or it patches the Client class.
    if type(slash) == "function" then
        slash(client)
    end
end

if client.useApplicationCommands then
    client:useApplicationCommands()
end

client:on('ready', function()
    print('Logged in as ' .. client.user.tag)
    presence.setRandomStatus(client)
    client:setInterval(function()
        presence.setRandomStatus(client)
    end, config.STATUS_INTERVAL_MS)

    -- Register slash commands
    print("Registering slash commands...")
    local success_count = 0
    local fail_count = 0
    for _, cmd in ipairs(commands_lib.commands) do
        local ok, err = pcall(function() return client:createGlobalApplicationCommand(cmd) end)
        if ok then
            success_count = success_count + 1
        else
            print("Failed to register command '" .. cmd.name .. "': " .. tostring(err))
            fail_count = fail_count + 1
        end
    end

    if fail_count == 0 then
        print("✅ Registered slash commands (" .. success_count .. " total).")
    else
        print("Registered slash commands with issues: " .. success_count .. " success, " .. fail_count .. " failures.")
    end

    server.startServer()
end)

client:on('interactionCreate', function(interaction)
    interactions.handleInteraction(interaction)
end)

-- Regular message handling for [[page]] syntax
local PREFIX_WIKI_MAP = {}
for key, wiki in pairs(config.WIKIS) do
    if wiki.prefix then
        PREFIX_WIKI_MAP[wiki.prefix] = key
    end
end

-- Helper to find [[prefix:page]] or [[page]] or {{prefix:page}} or {{page}}
local function match_syntax(content)
    -- try [[prefix:page]]
    local p, pg = content:match("%[%[(%w+)%:([^%]|]+)%|?.-%]%]")
    if p and pg then return p, pg end

    -- try [[page]]
    pg = content:match("%[%[([^%]|]+)%|?.-%]%]")
    if pg then return nil, pg end

    -- try {{prefix:page}}
    p, pg = content:match("{{(%w+)%:([^%]|]+)%|?.-}}")
    if p and pg then return p, pg end

    -- try {{page}}
    pg = content:match("{{([^%]|]+)%|?.-}}")
    if pg then return nil, pg end

    return nil, nil
end

client:on('messageCreate', function(message)
    if message.author.bot then return end

    local content = message.content
    local prefix, pageName = match_syntax(content)

    if pageName then
        pageName = pageName:gsub("^%s*(.-)%s*$", "%1") -- trim
        local wikiConfig
        if prefix and PREFIX_WIKI_MAP[prefix] then
            wikiConfig = config.WIKIS[PREFIX_WIKI_MAP[prefix]]
        else
            local channel = message.channel
            local categoryID = channel.categoryID
            local wikiKey = config.CATEGORY_WIKI_MAP[categoryID] or "superstar-racers"
            wikiConfig = config.WIKIS[wikiKey]
        end

        if wikiConfig then
            local response = interactions.handleUserRequest(wikiConfig, pageName, message)
            if response and response.id then
                interactions.trackResponse(message.id, response.id, message.author.id)
            end
        end
    end
end)

client:on('messageUpdate', function(message)
    if message.author.bot then return end

    local botMessageId = interactions.responseMap[message.id]
    if not botMessageId then return end

    local prefix, pageName = match_syntax(message.content)
    if pageName then
        pageName = pageName:gsub("^%s*(.-)%s*$", "%1")
        local wikiConfig
        if prefix and PREFIX_WIKI_MAP[prefix] then
            wikiConfig = config.WIKIS[PREFIX_WIKI_MAP[prefix]]
        else
            local wikiKey = config.CATEGORY_WIKI_MAP[message.channel.categoryID] or "superstar-racers"
            wikiConfig = config.WIKIS[wikiKey]
        end

        if wikiConfig then
            local botMsg = message.channel:getMessage(botMessageId)
            if botMsg then
                interactions.handleUserRequest(wikiConfig, pageName, message, botMsg)
            end
        end
    end
end)

client:on('reactionAdd', function(reaction, userId)
    if userId == client.user.id then return end

    local emoji = reaction.emojiName
    if emoji == "🗑️" or emoji == "wastebasket" then
        local message = reaction.message
        if message.author.id ~= client.user.id then return end

        local originalAuthorId = interactions.botToAuthorMap[message.id]
        if userId == originalAuthorId then
            message:delete()
        end
    end
end)

local token = os.getenv("DISCORD_TOKEN")
if token then
    client:run('Bot ' .. token)
else
    print("DISCORD_TOKEN not found in environment")
end
