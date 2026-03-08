return {
  name = "wikiguy",
  version = "1.0.0",
  description = "Wiki Guy bot ported to Lua",
  main = "main.lua",
  dependencies = {
    "SinisterRectus/discordia",
    "luvit/coro-http",
    "luvit/json",
    -- Note: Bilal2453/discordia-interactions and GitSparTV/discordia-slash
    -- are needed for slash commands but may need to be installed manually
    -- if not on lit.
  }
}
