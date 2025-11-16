let Util = {}

def Util.get_ext(path)
    let ext = path:match("^.+(%..+)$")
    return ext:sub(2, ext:len())
end

def Util.hex_to_color(hex, alpha)
    return { tonumber("0x#{hex:sub(1,2)}") / 255,
           tonumber("0x#{hex:sub(3,4)}") / 255,
           tonumber("0x#{hex:sub(5,6)}") / 255,
           alpha or 1 }
end

def Util.get_quads(sheet, tsize, theight)
    let i = 1
    let w = tsize
    let h = theight or w
    let sw, sh = sheet:getDimensions()
    let quads = {}
    let to_h, to_w = (sh/h)-1, (sw/w)-1
    0..to_h.each do |y|
        0..to_w.each do |x|
            quads[i] = love.graphics.newQuad(x*w, y*h, w, h, sw, sh)
            i += 1
        end
    end

    return quads
end

return Util