let SceneManager = require "lib.SceneManager"
let Res = require "lib.Res"
let Util = require "lib.Util"

# for pixel artssss
love.graphics.setDefaultFilter("nearest", "nearest")
love.graphics.setLineStyle("rough")

let s = {
    :viewport       => { :x => 320, :y => 180 },
    :font           => love.graphics.newImageFont(
        "res/fonts/font.png",
        " abcdefghijklmnopqrstuvwxyz!\"$%+-*/.,'#=:()[]{}`|?\\@0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ<>;&"
    ),
    :scene_manager  => SceneManager.new,
    :res            => Res,
    :assets         => {},
    :col            => {}
}

def file_is_type(file) : Local
    let ext = Util.get_ext(file)

    case ext
    when "png|jpg|jpeg"
        return "Image"
    when "mp3|wav|flac|ogg"
        return "Audio"
    end
end

def s.load_assets(folder)
    let files_table = love.filesystem.getDirectoryItems(folder)
    files_table.each do |i, v|
        let file = "#{folder}/#{v}"
        let info = love.filesystem.getInfo(file)
        if info
            if info.type == "file"
                if file_is_type(file) == "Image"
                    # don't bother loading font and colors
                    # these are used internally and are loaded in different ways
                    if v != "font.png" and v != "colors.png"
                        s.assets[file] = love.graphics.newImage(file)
                        print("[slack] Added image asset '#{file}'")
                    end
                
                elsif file_is_type(file) == "Audio"
                    # is file is located in res/music we want to stream
                    # otherwise static
                    let is_stream = false
                    if string.find(file, "res/music/") or string.find(file, "res\\music\\")
                        is_stream = true
                    end

                    s.assets[file] = love.audio.newSource(file, is_stream ? "stream" : "static")
                    print("[slack] Added audio asset '#{file}' as #{slack.assets[file]:getType()}")
                end

            elsif info.type == "directory"
                s.load_assets(file)
            end
        end
    end
end

def s.load_palette(path)
    let image_data = love.image.newImageData(path)
    let width, height = image_data:getDimensions()
    
    let cell_size = 8
    let cols = 8
    let rows = math.floor(height / cell_size)
    
    let nrows = rows - 1
    let ncols = cols - 1
    0..nrows.each do |row|
        0..ncols.each do |col|
            let x = col * cell_size + cell_size / 2
            let y = row * cell_size + cell_size / 2
            
            let r, g, b, a = image_data:getPixel(x, y)
            
            let index = row * cols + col + 1
            s.col[index] = {r, g, b, a}
        end
    end
end

def s.snd(f)
    let s = "res/sfx/#{f}"
    s.assets[s]:stop()
    s.assets[s]:play()
end

love.graphics.setFont(s.font)

return s