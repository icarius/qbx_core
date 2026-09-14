local config = require 'config.client'
local defaultSpawn = require 'config.shared'.defaultSpawn

if config.characters.useExternalCharacters then return end

local previewCam
local randomLocation = config.characters.locations[math.random(1, #config.characters.locations)]

local randomPeds = {
    {
        model = `mp_m_freemode_01`,
        headOverlays = {
            beard = {color = 0, style = 0, secondColor = 0, opacity = 1},
            complexion = {color = 0, style = 0, secondColor = 0, opacity = 0},
            bodyBlemishes = {color = 0, style = 0, secondColor = 0, opacity = 0},
            blush = {color = 0, style = 0, secondColor = 0, opacity = 0},
            lipstick = {color = 0, style = 0, secondColor = 0, opacity = 0},
            blemishes = {color = 0, style = 0, secondColor = 0, opacity = 0},
            eyebrows = {color = 0, style = 0, secondColor = 0, opacity = 1},
            makeUp = {color = 0, style = 0, secondColor = 0, opacity = 0},
            sunDamage = {color = 0, style = 0, secondColor = 0, opacity = 0},
            moleAndFreckles = {color = 0, style = 0, secondColor = 0, opacity = 0},
            chestHair = {color = 0, style = 0, secondColor = 0, opacity = 1},
            ageing = {color = 0, style = 0, secondColor = 0, opacity = 1},
        },
        components = {
            {texture = 0, drawable = 0, component_id = 0},
            {texture = 0, drawable = 0, component_id = 1},
            {texture = 0, drawable = 0, component_id = 2},
            {texture = 0, drawable = 0, component_id = 5},
            {texture = 0, drawable = 0, component_id = 7},
            {texture = 0, drawable = 0, component_id = 9},
            {texture = 0, drawable = 0, component_id = 10},
            {texture = 0, drawable = 15, component_id = 11},
            {texture = 0, drawable = 15, component_id = 8},
            {texture = 0, drawable = 15, component_id = 3},
            {texture = 0, drawable = 34, component_id = 6},
            {texture = 0, drawable = 61, component_id = 4},
        },
        props = {
            {prop_id = 0, drawable = -1, texture = -1},
            {prop_id = 1, drawable = -1, texture = -1},
            {prop_id = 2, drawable = -1, texture = -1},
            {prop_id = 6, drawable = -1, texture = -1},
            {prop_id = 7, drawable = -1, texture = -1},
        }
    },
    {
        model = `mp_f_freemode_01`,
        headBlend = {
            shapeMix = 0.3,
            skinFirst = 0,
            shapeFirst = 31,
            skinSecond = 0,
            shapeSecond = 0,
            skinMix = 0,
            thirdMix = 0,
            shapeThird = 0,
            skinThird = 0,
        },
        hair = {
            color = 0,
            style = 15,
            texture = 0,
            highlight = 0
        },
        headOverlays = {
            chestHair = {secondColor = 0, opacity = 0, color = 0, style = 0},
            bodyBlemishes = {secondColor = 0, opacity = 0, color = 0, style = 0},
            beard = {secondColor = 0, opacity = 0, color = 0, style = 0},
            lipstick = {secondColor = 0, opacity = 0, color = 0, style = 0},
            complexion = {secondColor = 0, opacity = 0, color = 0, style = 0},
            blemishes = {secondColor = 0, opacity = 0, color = 0, style = 0},
            moleAndFreckles = {secondColor = 0, opacity = 0, color = 0, style = 0},
            makeUp = {secondColor = 0, opacity = 0, color = 0, style = 0},
            ageing = {secondColor = 0, opacity = 1, color = 0, style = 0},
            eyebrows = {secondColor = 0, opacity = 1, color = 0, style = 0},
            blush = {secondColor = 0, opacity = 0, color = 0, style = 0},
            sunDamage = {secondColor = 0, opacity = 0, color = 0, style = 0},
        },
        components = {
            {drawable = 0, component_id = 0, texture = 0},
            {drawable = 0, component_id = 1, texture = 0},
            {drawable = 0, component_id = 2, texture = 0},
            {drawable = 0, component_id = 5, texture = 0},
            {drawable = 0, component_id = 7, texture = 0},
            {drawable = 0, component_id = 9, texture = 0},
            {drawable = 0, component_id = 10, texture = 0},
            {drawable = 15, component_id = 3, texture = 0},
            {drawable = 15, component_id = 11, texture = 3},
            {drawable = 14, component_id = 8, texture = 0},
            {drawable = 15, component_id = 4, texture = 3},
            {drawable = 35, component_id = 6, texture = 0},
        },
        props = {
            {prop_id = 0, drawable = -1, texture = -1},
            {prop_id = 1, drawable = -1, texture = -1},
            {prop_id = 2, drawable = -1, texture = -1},
            {prop_id = 6, drawable = -1, texture = -1},
            {prop_id = 7, drawable = -1, texture = -1},
        }
    }
}

NetworkStartSoloTutorialSession()

local nationalities = {}

if config.characters.limitNationalities then
    local nationalityList = lib.load('data.nationalities')

    CreateThread(function()
        for i = 1, #nationalityList do
            nationalities[#nationalities + 1] = { value = nationalityList[i] }
        end
    end)
end

local function setupPreviewCam()
    DoScreenFadeIn(1000)
    SetTimecycleModifier('hud_def_blur')
    SetTimecycleModifierStrength(1.0)
    FreezeEntityPosition(cache.ped, false)
    previewCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', randomLocation.camCoords.x, randomLocation.camCoords.y, randomLocation.camCoords.z, -6.0, 0.0, randomLocation.camCoords.w, 40.0, false, 0)
    SetCamActive(previewCam, true)
    SetCamUseShallowDofMode(previewCam, true)
    SetCamNearDof(previewCam, 0.4)
    SetCamFarDof(previewCam, 1.8)
    SetCamDofStrength(previewCam, 0.7)
    RenderScriptCams(true, false, 1, true, true)
    CreateThread(function()
        while DoesCamExist(previewCam) do
            SetUseHiDof()
            Wait(0)
        end
    end)
end

local function destroyPreviewCam()
    if not previewCam then return end

    SetTimecycleModifier('default')
    SetCamActive(previewCam, false)
    DestroyCam(previewCam, true)
    RenderScriptCams(false, false, 1, true, true)
    FreezeEntityPosition(cache.ped, false)
    DisplayRadar(true)
    previewCam = nil
end

local function randomPed()
    local ped = randomPeds[math.random(1, #randomPeds)]
    lib.requestModel(ped.model, config.loadingModelsTimeout)
    SetPlayerModel(cache.playerId, ped.model)
    pcall(function() exports['illenium-appearance']:setPedAppearance(PlayerPedId(), ped) end)
    SetModelAsNoLongerNeeded(ped.model)
end

---@param citizenId? string
local function previewPed(citizenId)
    if not citizenId then randomPed() return end

    local clothing, model = lib.callback.await('qbx_core:server:getPreviewPedData', false, citizenId)
    if model and clothing then
        lib.requestModel(model, config.loadingModelsTimeout)
        SetPlayerModel(cache.playerId, model)
        pcall(function() exports['illenium-appearance']:setPedAppearance(PlayerPedId(), json.decode(clothing)) end)
        SetModelAsNoLongerNeeded(model)
    else
        randomPed()
    end
end

---@param dialog string[]
---@param input integer
---@return boolean
local function checkStrings(dialog, input)
    local str = dialog[input]
    if config.characters.profanityWords[str:lower()] then return false end

    local split = {string.strsplit(' ', str)}
    if #split > 5 then return false end

    for i = 1, #split do
        local word = split[i]
        if config.characters.profanityWords[word:lower()] then return false end
    end

    return true
end

-- @param str string
-- @return string?
local function capString(str)
    return str:gsub("(%w)([%w']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

---@param coords vector4
local function spawnAt(coords)
    DoScreenFadeOut(500)

    while not IsScreenFadedOut() do
        Wait(0)
    end

    destroyPreviewCam()

    pcall(function() exports.spawnmanager:spawnPlayer({
        x = coords.x,
        y = coords.y,
        z = coords.z,
        heading = coords.w
    }) end)

    TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
    TriggerEvent('QBCore:Client:OnPlayerLoaded')
    TriggerServerEvent('qb-houses:server:SetInsideMeta', 0, false)
    TriggerServerEvent('qb-apartments:server:SetInsideMeta', 0, 0, false)

    while not IsScreenFadedIn() do
        Wait(0)
    end
end

local function spawnDefault() -- We use a callback to make the server wait on this to be done
    spawnAt(defaultSpawn)
    TriggerEvent('qb-clothes:client:CreateFirstCharacter')
end

local function spawnLastLocation()
    spawnAt(QBX.PlayerData.position)
end

local chooseCharacter -- forward declaration; playCharacterByCitizenId/deleteCharacterByCitizenId call back into it after a full-list refresh, same as the old onSelect handlers did

---Mirrors the old 'Play' context option's onSelect.
---@param citizenid string
local function playCharacterByCitizenId(citizenid)
    SetNuiFocus(false, false)
    DoScreenFadeOut(10)
    lib.callback.await('qbx_core:server:loadCharacter', false, citizenid)
    if GetResourceState('qbx_apartments'):find('start') then
        TriggerEvent('apartments:client:setupSpawnUI', citizenid)
    elseif GetResourceState('qbx_spawn'):find('start') then
        TriggerEvent('qb-spawn:client:setupSpawns', citizenid)
        TriggerEvent('qb-spawn:client:openUI', true)
    else
        spawnLastLocation()
    end
    destroyPreviewCam()
end

---Mirrors the old 'Delete Character' context option's onSelect (confirmation already happened
---in the NUI itself, so this only runs once the player has confirmed).
---@param citizenid string
---@return boolean success
local function deleteCharacterByCitizenId(citizenid)
    local success = lib.callback.await('qbx_core:server:deleteCharacter', false, citizenid)
    Notify(success and locale('success.character_deleted') or locale('error.character_delete_failed'), success and 'success' or 'error')

    if success then
        destroyPreviewCam()
        chooseCharacter()
    end

    return success
end

---@class CreateCharacterFormData
---@field cid integer
---@field firstname string
---@field lastname string
---@field nationality string
---@field gender integer
---@field birthdate string

---Mirrors the old createCharacter(cid) flow, minus the blocking lib.inputDialog — the form
---itself now lives in the NUI, this just validates and finishes the same way the old code did.
---@param data CreateCharacterFormData
---@return boolean success, string? errorMessage
local function submitNewCharacter(data)
    for _, str in ipairs({ data.firstname, data.lastname, data.nationality }) do
        if not checkStrings({ str }, 1) then
            return false, locale('error.no_match_character_registration')
        end
    end

    SetNuiFocus(false, false)
    DoScreenFadeOut(150)

    local newData = lib.callback.await('qbx_core:server:createCharacter', false, {
        firstname = capString(data.firstname),
        lastname = capString(data.lastname),
        nationality = capString(data.nationality),
        gender = data.gender,
        birthdate = data.birthdate,
        cid = data.cid
    })

    if not newData then
        -- Server refused (e.g. character limit reached between opening the form and
        -- submitting it) — restore input so the player isn't stuck on a black screen.
        SetNuiFocus(true, true)
        DoScreenFadeIn(150)
        return false, locale('error.no_match_character_registration')
    end

    if GetResourceState('qbx_spawn') == 'missing' then
        spawnDefault()
    else
        if config.characters.startingApartment then
            TriggerEvent('apartments:client:setupSpawnUI', newData)
        else
            TriggerEvent('qbx_core:client:spawnNoApartments')
        end
    end

    destroyPreviewCam()
    return true
end

RegisterNUICallback('qbx_core:multichar:preview', function(data, cb)
    previewPed(data.citizenid)
    cb(true)
end)

RegisterNUICallback('qbx_core:multichar:play', function(data, cb)
    playCharacterByCitizenId(data.citizenid)
    cb(true)
end)

RegisterNUICallback('qbx_core:multichar:delete', function(data, cb)
    local success = deleteCharacterByCitizenId(data.citizenid)
    cb({ success = success })
end)

RegisterNUICallback('qbx_core:multichar:create', function(data, cb)
    local success, errorMessage = submitNewCharacter(data)
    cb({ success = success, errorMessage = errorMessage })
end)

RegisterNUICallback('qbx_core:multichar:close', function(_, cb)
    SetNuiFocus(false, false)
    cb(true)
end)

---@param character PlayerEntity
---@return table
local function toCharacterCard(character)
    return {
        citizenid = character.citizenid,
        firstname = character.charinfo.firstname,
        lastname = character.charinfo.lastname,
        gender = character.charinfo.gender,
        birthdate = character.charinfo.birthdate,
        nationality = character.charinfo.nationality,
        accountNumber = character.charinfo.account,
        phoneNumber = character.charinfo.phone,
        cash = character.money.cash,
        bank = character.money.bank,
        jobLabel = character.job.label,
        jobGradeName = character.job.grade.name,
        gangLabel = character.gang.label,
        gangGradeName = character.gang.grade.name,
    }
end

function chooseCharacter()
    ---@type PlayerEntity[], integer
    local characters, amount = lib.callback.await('qbx_core:server:getCharacters')
    local firstCharacterCitizenId = characters[1] and characters[1].citizenid
    previewPed(firstCharacterCitizenId)

    randomLocation = config.characters.locations[math.random(1, #config.characters.locations)]
    SetFollowPedCamViewMode(2)
    DisplayRadar(false)

    DoScreenFadeOut(500)

    while not IsScreenFadedOut() and cache.ped ~= PlayerPedId()  do
        Wait(0)
    end

    FreezeEntityPosition(cache.ped, true)
    Wait(1000)
    SetEntityCoords(cache.ped, randomLocation.pedCoords.x, randomLocation.pedCoords.y, randomLocation.pedCoords.z, false, false, false, false)
    SetEntityHeading(cache.ped, randomLocation.pedCoords.w)

    NetworkStartSoloTutorialSession()

    while not NetworkIsInTutorialSession() do
        Wait(0)
    end

    Wait(1500)
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    setupPreviewCam()

    local cards = {}
    for i = 1, amount do
        cards[i] = characters[i] and toCharacterCard(characters[i]) or nil
    end

    SendNUIMessage({
        action = 'openMultichar',
        data = {
            characters = cards,
            config = {
                amount = amount,
                enableDeleteButton = config.characters.enableDeleteButton,
                limitNationalities = config.characters.limitNationalities,
                nationalities = (function()
                    local names = {}
                    for i = 1, #nationalities do names[i] = nationalities[i].value end
                    return names
                end)(),
                dateFormat = config.characters.dateFormat,
                dateMin = config.characters.dateMin,
                dateMax = config.characters.dateMax,
            },
            locale = {
                multicharTitle = locale('info.multichar_title'),
                newCharacter = locale('info.multichar_new_character'),
                charMale = locale('info.char_male'),
                charFemale = locale('info.char_female'),
                play = locale('info.play'),
                playDescription = locale('info.play_description'),
                deleteCharacter = locale('info.delete_character'),
                deleteCharacterDescription = locale('info.delete_character_description'),
                confirmDelete = locale('info.confirm_delete'),
                characterRegistrationTitle = locale('info.character_registration_title'),
                firstName = locale('info.first_name'),
                lastName = locale('info.last_name'),
                nationality = locale('info.nationality'),
                gender = locale('info.gender'),
                birthDate = locale('info.birth_date'),
                selectGender = locale('info.select_gender'),
                noMatchCharacterRegistration = locale('error.no_match_character_registration'),
            },
        },
    })

    SetTimecycleModifier('default')
    SetNuiFocus(true, true)
end

RegisterNetEvent('qbx_core:client:spawnNoApartments', function() -- This event is only for no starting apartments
    DoScreenFadeOut(500)
    Wait(2000)
    SetEntityCoords(cache.ped, defaultSpawn.x, defaultSpawn.y, defaultSpawn.z, false, false, false, false)
    SetEntityHeading(cache.ped, defaultSpawn.w)
    Wait(500)
    destroyPreviewCam()
    SetEntityVisible(cache.ped, true, false)
    Wait(500)
    DoScreenFadeIn(250)
    TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
    TriggerEvent('QBCore:Client:OnPlayerLoaded')
    TriggerServerEvent('qb-houses:server:SetInsideMeta', 0, false)
    TriggerServerEvent('qb-apartments:server:SetInsideMeta', 0, 0, false)
    TriggerEvent('qb-weathersync:client:EnableSync')
    TriggerEvent('qb-clothes:client:CreateFirstCharacter')
end)

RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    if GetInvokingResource() then return end -- Make sure this can only be triggered from the server
    chooseCharacter()
end)

CreateThread(function()
    while true do
        Wait(0)
        if NetworkIsSessionStarted() then
            pcall(function() exports.spawnmanager:setAutoSpawn(false) end)
            Wait(250)
            chooseCharacter()
            break
        end
    end
    -- since people apparently die during char select. Since SetEntityInvincible is notoriously unreliable, we'll just loop it to be safe. shrug
    while NetworkIsInTutorialSession() do
        SetEntityInvincible(PlayerPedId(), true)
        Wait(250)
    end
    SetEntityInvincible(PlayerPedId(), false)
end)
