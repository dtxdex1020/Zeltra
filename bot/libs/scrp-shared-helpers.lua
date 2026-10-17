--[[
	Shared helpers that background modules still call (erlcbansync uses banMember, application/message panels use
	export and import). They used to live inside old command files; moved here when those commands were removed.
]]


local function banMember(guild, violatorMember, violator, moderator, reason, nocase, seconds)
    if violatorMember and violatorMember.highestRole and moderator.highestRole and not isPrivileged(moderator) and
        (violatorMember.highestRole.position >= moderator.highestRole.position) then
        return nil, "That user has a role equal to or higher than you."
    end

    local config = sqldb:get(guild.id) or {}

    if violatorMember then
        local moderatable, err = canModerate(moderator, violatorMember)
        if not moderatable then
            return false, err
        end
    end

    local deleteSeconds = (seconds and tonumber(seconds) and math.min(tonumber(seconds), 604800)) or 0

    if not nocase and violatorMember then
        local config = sqldb:get(guild.id) or {}
        local appealLink = config.appealLinks and config.appealLinks.ban or nil

        pcall(function()
            dmStyle.send(violator, {
                guild = guild,
                icon = "🔨",
                title = "You were banned",
                intro = "A moderator banned you from **" .. dmStyle.serverName(guild) .. "**.",
                fields = {
                    { "Reason", reason },
                    { "Date", dmStyle.time(os.time()) }
                },
                note = (appealLink and "Think this was a mistake? Use the **Appeal Ban** button below.") or nil,
                buttons = (appealLink and { { label = "Appeal Ban", url = appealLink, emoji = "🔗" } }) or nil,
                footer = "Moderation"
            })
        end)
    end

    local success, err = guild:banUser(violator.id, reason, deleteSeconds)
    if not success then
        return nil, "Failed to ban " .. getUserString(violator) .. ": " .. tostring(err):usub(20)
    end

    if not nocase then
        local case = db:case(violator, moderator, "Ban", reason, nil, guild)

        if case then
            db:send(guild, "modlogchannel", {
                embed = {
                    author = author(moderator),
                    thumbnail = thumbnail(violator),
                    title = emojis.ban .. " Member Banned",
                    description = getUserString(violator) .. " was banned by " .. getUserString(moderator) .. ":\n" ..
                        emojis.right .. " **Reason:** " .. case.reason .. "\n" .. emojis.right .. " **Date:** <t:" ..
                        case.timestamp .. ">\n" .. emojis.right .. " **Case ID:** " .. case.caseID,
                    color = colors.heavyred
                }
            })

            return true, getUserString(violator) .. " has been banned for **" .. reason .. "**.\n-# " .. emojis.right .. " **Case ID:** `" .. case.caseID .. "`"
        else
            return false, getUserString(violator) .. " has been successfully banned, however a case could not be created."
        end
    else
        local success, err = guild:banUser(violator.id, reason, deleteSeconds)

        if not success then
            return nil, "Failed to ban " .. getUserString(violator) .. ": " .. tostring(err):usub(20)
        end

        return true, "" .. getUserString(violator) .. " has been banned for **" .. reason .. "**."
    end
end

_G.banMember = banMember


local function export(tbl, owner, exportableType, name)
    local code = "scrp_" .. junkStr(25)

    local value, char, err = json.encode(tbl)
    if not value then
        return nil, err
    end

    local exportables = sqldb:getAllExportables() or {}
    for _, v in pairs(exportables) do
        if v.data == value then
            return v.id
        end
    end

    local succ, err2 = sqldb:addExportable(
        code,
        owner.id,
        os.time(),
        0,
        exportableType,
        value,
        name or emojis.fail
    )

    if succ then
        return code
    else
        return nil, err2
    end
end

_G.export = export

local function import(code, type, full)
    local exportable = sqldb:getExportable(code)
    if not exportable then return nil, "Invalid exportable code." end

    local parse
    if type then
        if type == "panel" and exportable.type ~= "panel" then
            return nil, "The exportable must be a tickets panel."
        elseif type == "automation" and exportable.type ~= "automation" then
            return nil, "The exportable must be an automation."
        elseif type == "message" then
            if exportable.type == "embed" then
                parse = function(value) return {embeds = {value}} end
            elseif exportable.type == "embeds" then
                parse = function(value) return {embeds = value} end
            elseif exportable.type ~= "message" then
                return nil, "The exportable must be a message, embed, or embeds."
            end
        elseif type == "embed" then
            if exportable.type == "message" then
                parse = function(value) return (value.embeds and value.embeds[1]) or value.embed end
            elseif exportable.type == "embeds" then
                parse = function(value) return value[1] end
            elseif exportable.type ~= "embed" then
                return nil, "The exportable must be a message, embed, or embeds."
            end
        elseif type == "embeds" then
            if exportable.type == "message" then
                parse = function(value) return value.embeds or (value.embed and {value.embed}) end
            elseif exportable.type == "embed" then
                parse = function(value) return {value} end
            elseif exportable.type ~= "embeds" then
                return nil, "The exportable must be a message, embed, or embeds."
            end
        end
    end

    local value, char, err = json.decode(exportable.data)
    if not value then
        return nil, "Exportable data could not be decoded."
    end

    exportable.value = value
    exportable.lastImported = os.time()
    sqldb:setExportable(code, exportable)

    if parse then
        local parsedValue = parse(value)
        if not parsedValue then
            return nil, "This exportable does not contain the necessary data to be imported here."
        end
        exportable.value = parsedValue
        value = parsedValue
    end

    if full then
        return exportable
    else
        return value
    end
end

_G.import = import

return true
