local config = require("../config")

local function setRandomStatus(client)
    if not client or not client.user then return end
    local status_options = config.STATUS_OPTIONS
    local newStatus = status_options[math.random(#status_options)]

    if not newStatus or not newStatus.text or not newStatus.type then return end

    pcall(function()
        client:setActivity({
            name = newStatus.text,
            type = newStatus.type
        })
    end)
end

return {
    setRandomStatus = setRandomStatus
}
