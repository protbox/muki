let EntityManager = require "lib.EntityManager"

class Scene
    def initialize
        @ent_mgr = EntityManager.new
    end

    def _ready(*args)
    end

    def update(dt)
        @ent_mgr ? @ent_mgr.update(@ent_mgr, dt)
    end

    def draw()
        @ent_mgr ? @ent_mgr.draw(@ent_mgr)
    end
end

return Scene