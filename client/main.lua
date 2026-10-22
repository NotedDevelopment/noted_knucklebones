local last = false -- latest snapshot (or false), replayed when the app mounts

local function SendAppMessage(action, data)
    exports['lb-phone']:SendCustomAppMessage(Config.AppInfo.identifier, { action = action, data = data })
end

RegisterNetEvent('kbphone:message', function(action, data)
    if action == 'update' then last = data end
    if action == 'closed' then last = false end
    SendAppMessage(action, data)
end)

-- UI -> server. The page calls these through the phone's fetchNui, which targets this resource.
RegisterNUICallback('getData', function(_, cb)
    cb({ snapshot = last })
    TriggerServerEvent('kbphone:refresh')
end)
for _, name in ipairs({ 'ai', 'rooms', 'stopSpectating', 'leave' }) do
    RegisterNUICallback(name, function(_, cb)
        TriggerServerEvent('kbphone:' .. name)
        cb({ ok = true })
    end)
end
RegisterNUICallback('create', function(data, cb)
    TriggerServerEvent('kbphone:create', data.public == true)
    cb({ ok = true })
end)
RegisterNUICallback('join', function(data, cb)
    TriggerServerEvent('kbphone:join', tostring(data.code or ''))
    cb({ ok = true })
end)
RegisterNUICallback('spectate', function(data, cb)
    TriggerServerEvent('kbphone:spectate', tostring(data.code or ''))
    cb({ ok = true })
end)
RegisterNUICallback('nickname', function(data, cb)
    TriggerServerEvent('kbphone:nickname', tostring(data.nickname or ''))
    cb({ ok = true })
end)
RegisterNUICallback('action', function(data, cb)
    TriggerServerEvent('kbphone:action', {
        action = data.action, column = data.column, match = data.match, revision = data.revision,
    })
    cb({ ok = true })
end)

-- App registration, as in noted_fitbit: wait for lb-phone, re-add if it restarts.
CreateThread(function()
    while GetResourceState('lb-phone') ~= 'started' do Wait(500) end
    Wait(1000)
    local res = GetCurrentResourceName()
    local function AddApp()
        local added, err = exports['lb-phone']:AddCustomApp({
            identifier  = Config.AppInfo.identifier,
            name        = Config.AppInfo.name,
            description = Config.AppInfo.description,
            developer   = Config.AppInfo.developer,
            defaultApp  = Config.AppInfo.defaultApp,
            size        = Config.AppInfo.size,
            ui          = res .. '/ui/index.html',
            icon        = 'https://cfx-nui-' .. res .. '/ui/icon.svg',
            fixBlur     = true,
        })
        if not added then
            print(('^1[%s]^0 Could not add app: %s'):format(res, tostring(err)))
        end
    end
    AddApp()
    AddEventHandler('onResourceStart', function(r)
        if r == 'lb-phone' then AddApp() end
    end)
end)
