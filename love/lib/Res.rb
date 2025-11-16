let math_min = math.min

let res = {}

let last_mouse_x, last_mouse_y = 0, 0
let currently_rendering = nil

def _get_raw_mouse_position(width, height) : Local
    let mouse_x, mouse_y = love.mouse.getPosition()
    let window_width, window_height = love.graphics.getDimensions()
    let scale = math_min(window_width / width, window_height / height)
    let offset_x = (window_width - width * scale) * 0.5
    let offset_y = (window_height - height * scale) * 0.5
    return (mouse_x - offset_x) / scale, (mouse_y - offset_y) / scale
end

def res.get_mouse_pos()
    let x, y = _get_raw_mouse_position(love.viewport.width, love.viewport.height)
    if x >= 0 and x <= love.viewport.width and y >= 0 and y <= love.viewport.height
        last_mouse_x, last_mouse_y = x, y
    end

    return last_mouse_x, last_mouse_y
end

def res.get_scale(width, height)
    if currently_rendering
        width  = width  or currently_rendering[1]
        height = height or currently_rendering[2]
    end

    let window_width, window_height = love.graphics.getDimensions()
    return math_min(window_width / width, window_height / height)
end

def res.set(width, height, centered)
    if currently_rendering
        error("Must call res.unset before calling set.")
    end

    currently_rendering = {width, height}
    love.graphics.push()

    let window_width, window_height = love.graphics.getDimensions()
    let scale = math_min(window_width / width, window_height / height)
    let offset_x = (window_width - width * scale) * 0.5
    let offset_y = (window_height - height * scale) * 0.5
    love.graphics.translate(offset_x, offset_y)
    love.graphics.scale(scale)
    
    centered ? love.graphics.translate(0.5 * width, 0.5 * height)

    return scale
end

let default_black = {0, 0, 0, 1}

def res.unset(letterbox_color)
    if not currently_rendering
        error("Must call res.set before calling unset.")
    end

    let canvas_width, canvas_height = currently_rendering[1], currently_rendering[2]
    currently_rendering = nil
    love.graphics.pop()

    let window_width, window_height = love.graphics.getDimensions()
    let scale = math_min(window_width / canvas_width, window_height / canvas_height)
    let scaled_width, scaled_height = canvas_width * scale, canvas_height * scale

    let r, g, b, a = love.graphics.getColor()
    love.graphics.setColor(letterbox_color or default_black)
    
    # draw letterbox bars
    love.graphics.rectangle("fill", 0, 0, window_width, 0.5 * (window_height - scaled_height))
    love.graphics.rectangle("fill", 0, window_height, window_width, -0.5 * (window_height - scaled_height))
    love.graphics.rectangle("fill", 0, 0, 0.5 * (window_width - scaled_width), window_height)
    love.graphics.rectangle("fill", window_width, 0, -0.5 * (window_width - scaled_width), window_height)

    # restore original color
    love.graphics.setColor(r, g, b, a)
end

return res
