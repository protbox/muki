Slack = require "slack" # one global to rule them all

Slack.load_palette("res/img/colors.png")
Slack.load_assets("res")
Slack.scene_manager:add("Game", "scenes.Game")

def love.update(dt)
    Slack.scene_manager:update(dt)
end

def love.draw
    Slack.res.set(love.viewport.width, love.viewport.height)
    Slack.scene_manager:draw()
    Slack.res.unset()
end