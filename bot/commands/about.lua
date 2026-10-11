-- about.lua

local slashCommand = tools.slashCommand("about", "View information on Tennessee State Roleplay!")

local aboutcomps = discordia.Components()
    :button({
        url = "https://discord.com/oauth2/authorize?client_id=" .. Client.user.id .. "&permissions=8&integration_type=0&scope=bot",
        label = "Invite",
        style = "link",
		emoji = resolvedEmojis.ducky
    })
    :button({
        url = _G.ZELTRA_SOURCE_URL,
        label = "Source code",
        style = "link",
		emoji = resolvedEmojis.document
    })
    :button({
        url = "https://github.com/dtxdex1020/Zeltra/issues",
        label = "Support",
        style = "link",
		emoji = resolvedEmojis.support
    })
    :button({
        url = "https://docs.duckybot.xyz/",
        label = "Ducky docs",
        style = "link",
		emoji = resolvedEmojis.book
    })

return {
    name = "about",
    description = "View information on Tennessee State Roleplay!",
    aliases = {"information", "info", "invite", "invitebot", "ducky", "zeltra", "source", "license", "credits"},
    category = "General",
    slashCommand = slashCommand,
    requiredPermissions = {},
    hybridCallback = function(interaction, args)
        local allLinks =  sqldb:getAllLinks()

        if not allLinks or type(allLinks) ~= "table" then
            allLinks = {}
        end
        
        local emb = {
            title = emojis.ducky .. " Tennessee State Roleplay",
            description = "> " .. emojis.ducky .. " **Tennessee State Roleplay** is a multipurpose bot focused on seamlessly integrating Discord and ERLC server automation for effortless management, run by [**Shark**](https://discord.com/users/1307878235383795732).\n\n"
                .. emojis.right .. " **Based on Ducky V1 by duckyerlc. Source: " .. _G.ZELTRA_SOURCE_URL .. "**\n"
                .. emojis.right .. " Tennessee State Roleplay is a modified version of [**Ducky V1**](https://github.com/duckyerlc/Ducky-opensource), originally developed by [**Troptop**](https://discord.com/users/598958193032560642) and [**bobbibones**](https://discord.com/users/782235114858872854) with [**Quackscordia**](https://github.com/DuckySupport/Quackscordia), a fork of [**Discordia**](https://github.com/SinisterRectus/Discordia).\n"
                .. emojis.right .. " Licensed under the [**GNU AGPL-3.0**](https://www.gnu.org/licenses/agpl-3.0.html). You can get the complete source code of this bot, including all modifications, at " .. _G.ZELTRA_SOURCE_URL .. ".\n"
                .. emojis.right .. " Found a bug or need help? [**Open an issue**](https://github.com/dtxdex1020/Zeltra/issues). Please read the [**Terms & Privacy**](https://github.com/dtxdex1020/Zeltra#terms-and-privacy) before using Tennessee State Roleplay.",
            fields = {
                {
                    name = emojis.chart .. " Statistics",
                    value = emojis.right .. " **Guilds:** " .. formatNumber(table.count(Client.guilds)) .. "\n" .. emojis.right .. " **Users:** " .. formatNumber(getTotalUserCount()) .. "\n" .. emojis.right .. " **Roblox Links:** " .. formatNumber(table.count(allLinks)) .. "\n" .. emojis.right .. " **Version:** " .. _G.version .. "\n" .. emojis.right .. " **Uptime:** " .. readable(os.time() - _G.uptime)
                }
            },
            color =  colors.duckyyellow,
            thumbnail = { url = Client.user.avatarURL },
            author = { name = "Tennessee State Roleplay", icon_url = Client.user.avatarURL }
        }
        return interaction:reply({
            embed = emb,
			components = aboutcomps:raw()
        })
    end
}