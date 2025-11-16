class EntityManager
    def initialize
        @ents = {}
    end

    def add(ent)
        table.insert(@ents, ent)
        \sort_by_layer()
    end

    def remove(ent)
        @ents.each do |i, e|
            if e == ent
                table.remove(@ents, i)
                break
            end
        end
    end

    def sort_by_layer
        table.sort(@ents, def(ab)
            return (a.layer or 0) < (b.layer or 0)
        end)
    end

    def update(dt)
        @ents.each do |i, ent|
            if ent.remove
                ent._destroy ? ent._destroy(ent)
                table.remove(@ents, i)

            elsif ent.update
                ent.update(ent, dt)
            end
        end
    end

    def draw
        @ents.each do |ent|
            if ent.draw
                ent:draw()
            end
        end
    end
end

return EntityManager