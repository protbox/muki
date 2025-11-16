-- Primary entry-point for muki.
-- DON'T MODIFY SHIT HERE, LEST YOU WANT IT BROKEN
-- USE init.rb INSTEAD!
require "run"

local muki = require("deps.muki") -- change this to wherever muki is

local CACHE_DIR = ""

local function get_files_recursive(dir, files)
    files = files or {}
    dir = dir or ""
    
    local items = love.filesystem.getDirectoryItems(dir)
    
    for _, item in ipairs(items) do
        local path = dir == "" and item or (dir .. "/" .. item)
        local info = love.filesystem.getInfo(path)
        
        if info then
            if info.type == "directory" then
                get_files_recursive(path, files)
            elseif info.type == "file" and path:match("%.rb$") then
                table.insert(files, path)
            end
        end
    end
    
    return files
end

-- check if source file is newer than cached file
local function needs_recompile(src_path, cache_path)
    local src_info = love.filesystem.getInfo(src_path)
    local cache_info = love.filesystem.getInfo(cache_path, "file")
    
    if not cache_info then return true end
    if not src_info then return false end
    
    return src_info.modtime > cache_info.modtime
end

local function ensure_directory(filepath)
    local dir = filepath:match("(.*/)")
    if dir then
        love.filesystem.createDirectory(dir)
    end
end

-- transpile and cache
local function transpile_file(src_path)
    local source = love.filesystem.read(src_path)
    if not source then
        error("Cannot read file: " .. src_path)
    end
    
    local success, lua_code = pcall(muki.transpile, src_path)
    if not success then
        error("Transpilation error in " .. src_path .. ":\n" .. lua_code)
    end
    
    local cache_path = src_path:gsub("%.rb$", ".lua")
    ensure_directory(cache_path)
    
    local write_success = love.filesystem.write(cache_path, lua_code)
    if not write_success then
        error("Failed to write cache file: " .. cache_path)
    end
    
    return cache_path
end

-- transpile all .rb files that need updating
local function init_muki()
    local rb_files = get_files_recursive()
    
    for _, rb_path in ipairs(rb_files) do
        local cache_path = rb_path:gsub("%.rb$", ".lua")
        
        if needs_recompile(rb_path, cache_path) then
            print("Transpiling: " .. rb_path)
            transpile_file(rb_path)
        end
    end
end

function love.load()
    init_muki()
    
    local init_loader = love.filesystem.load("init.lua")
    if init_loader then
        init_loader()
    else
        error("Could not load init.lua - make sure init.rb exists")
    end
end