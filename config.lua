Config = {
    AppInfo = {
        identifier  = 'knucklebones',
        name        = 'Knucklebones',
        description = 'Roll, place, and knock out your opponent\'s dice. Play friends by code or the CPU.',
        developer   = 'NotedDevelopment',
        defaultApp  = true, -- installed on every phone, no app store visit needed
        size        = 24000, -- kB, cosmetic
    },
    AiThinkTime = 900,    -- ms between the CPU's roll and placement
    TurnTimeout = 180,    -- seconds per turn in games between people; none against the CPU
    RoomCodeLength = 6,

    -- The CPU opponent takes one of these names at random each game. Add as many as you like.
    CpuNames = { 'Boop', 'Dave', 'DJ', 'Catalina', 'Carmen', 'Thor' },

    -- Players show as their character's first name unless they set a nickname in the app.
    Nickname = {
        MinLength = 2,
        MaxLength = 16,
        Pattern = "^[%w][%w '%-]*$", -- letters, digits, spaces, apostrophes and hyphens
        Cooldown = 5,                -- seconds between changes per player
    },

    -- Where nickname changes are logged. Turn on any combination.
    -- The Discord webhook URL never goes in this file (it is sent to every player and is
    -- public on GitHub). Put it in server.cfg with `set`, not `setr`:
    --   set knucklebones_webhook "https://discord.com/api/webhooks/..."
    Logging = {
        Discord = true,  -- post an embed to the knucklebones_webhook convar, when it is set
        Console = true,  -- print to the server console, which txAdmin keeps
        File = false,    -- append to logs/nicknames.log inside this resource
        OxLib = false,   -- send to ox_lib's lib.logger, if ox:logger is set up in ox.cfg
    },
}
