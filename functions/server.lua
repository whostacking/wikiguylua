local http = require('http')
local json = require('json')

local function startServer()
    local port = os.getenv("PORT") or 3000

    http.createServer("0.0.0.0", port, function (req, res)
        if req.url == "/" then
            local body = [[
    <html>
      <head>
        <title>Orbital is orbiting</title>
        <style>
          body { font-family: "Arial", sans-serif; text-align: center; padding: 50px; background: #222222; color: white }
          h1 { color: #ff6600; }
        </style>
      </head>
      <body>
        <h1>Orbital Discord Bot</h1>
        <p>Bot is running (Lua/Discordia).</p>
      </body>
    </html>
]]
            res:finish(body)
        elseif req.url == "/status" then
            local data = {
                status = 'online',
                bot = 'Orbital Discord Bot',
                runtime = 'Lua/Discordia',
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }
            res:finish(json.encode(data))
        else
            res:finish("Not Found")
        end
    end):listen()

    print("Web server running on port " .. port)
end

return {
    startServer = startServer
}
