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
}
