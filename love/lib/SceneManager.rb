let lg = love.graphics

class SceneManager
    def initialize
        @current = nil  # the current scene
        @scenes = {}    # list of scene
        @transitioning = false # are we fading the screen
        @opening = false # transition is opening
        @closing = false # transition is closing
        @rect_speed = 180 # how fast the transition is
        @rects = {  # transition rectangles
            {
                # top
                :w => love.viewport.width,
                :h => 0,
                :y => 0
            },
            {
                # bottom
                :w => love.viewport.width,
                :h => 0,
                :y => love.viewport.height,
                :is_bottom => true
            }
        }
    end

    def add(name, scene)
        # if we don't have a scene by this name, add it
        not @scenes.name ? @scenes[name] = require(scene)()

        # no current scene yet? make it the new one
        if not @current
            \switch_to(name)
        end
    end

    # instant switch
    def switch_to(name, *args)
        if @scenes[name]
            @current = @scenes[name]
            @current._ready(@current, *args)
        else
            print("[Slack/WARNING] Attempted to switch to unknown scene '#{name}'")
        end
    end

    # switch_to, but with flair
    def fade_to(name, *args)
        if @scenes[name]
            @transitioning = true
            @opening = true
            @fade_args = {
                :name => name,
                :args => {*args}
            }
        end
    end

    def update(dt)
        not @current ? return nil

        if @transitioning
            if @opening
                # get the max height of each rectangle
                let max_height = love.viewport.height / 2
                @rects.each do |rect|
                    rect.h += math.min(@rect_speed * dt, max_height)
                    # if it's the bottom rectangle, we need to move it up
                    if rect.is_bottom
                        rect.y -= @rect_speed * dt
                    end

                    if rect.h >= max_height
                        @opening = false
                        @closing = true
                        @current = @scenes[@fade_args.name]
                        break
                    end
                end
            
            elsif @closing
                @rects.each do |rect|
                    rect.h -= math.max(@rect_speed * dt, 0)
                    # if it's the bottom rectangle, we need to move it down
                    if rect.is_bottom
                        rect.y += @rect_speed * dt
                    end

                    if rect.h <= 0
                        @closing = false
                        @transitioning = false
                        @current._ready(@current, unpack(@fade_args.args))
                        @fade_args = nil
                        @rects.each do |rect|
                            rect.h = 0
                            rect.y = rect.is_bottom ? love.viewport.height : 0
                        end

                        break
                    end
                end
            end

            return nil
        end

        @current:update(dt)
    end

    def draw
        not @current ? return
        @current:draw()

        if @transitioning
            lg.setColor(0, 0, 0)

            @rects.each do |rect|
                lg.rectangle("fill", 0, rect.y, rect.w, rect.h)
            end

            lg.setColor(1, 1, 1, 1)
        end
    end
end

return SceneManager