let Scene = require "lib.Scene"
let lg = love.graphics

let rect = {:x => 24, :y => 24, :w => 48, :h => 32}

def rect.draw
    lg.setColor(Slack.col[8])
    lg.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
    lg.setColor(Slack.col[4])
end

class Game < Scene
    def initialize
        super
        @message = "Hello, World!"
        @ent_mgr:add(rect)
    end

    def draw
        lg.clear(Slack.col[10])
        lg.print(@message, 8, 8)
        super # draws objects in the entity manager
    end
end

return Game