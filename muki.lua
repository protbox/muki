#!/usr/bin/env luajit

local function rerr(str, ...)
    print(string.format(str, ...))
    os.exit(-1)
end

local function rlog(str, ...)
    print(string.format(str, ...))
end

local function file_exists(file)
    local f = io.open(file, "rb")
    if f then f:close() end
    return f ~= nil
end

local output = ""
local tracker = {} -- i actually set this up inside transpile so it works better with LOVE

local modules = {
    ["Array"] = [[
local _MOCHI_MOD_TABLES = {}

local function $var(t)
    t = t or {}
    local is_array = true
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
            is_array = false
            break
        end
    end
    return setmetatable(t, { 
        __index = _MOCHI_MOD_TABLES,
        __is_array = is_array
    })
end

function _MOCHI_MOD_TABLES:map(fn)
    local res = {}
    for i,v in ipairs(self) do
        res[i] = fn(v)
    end

    return res
end

function _MOCHI_MOD_TABLES:empty()
    return next(self) == nil
end

function _MOCHI_MOD_TABLES:iter(fn)
    if self:_is_array() then
        for i,v in ipairs(self) do
            fn(v, i)
        end
    else
        for k,v in pairs(self) do
            fn(k,v)
        end
    end

    return self
end

function _MOCHI_MOD_TABLES:join(sep, start_idx, end_idx)
    return table.concat(self, sep, start_idx, end_idx)
end

function _MOCHI_MOD_TABLES:filter(fn)
    local res = T{}
    for i,v in ipairs(self) do
        if fn(v) then table.insert(res, v) end
    end

    return res
end

function _MOCHI_MOD_TABLES:find(key, val)
    if self:_is_array() then
        for i,v in ipairs(self) do
            if v == key then return i end

            if type(v) == "table" then
                for k,_v in pairs(v) do
                    if key == k and _v == val then
                        return v, i
                    end
                end
            end
        end
    else
        print("[warning] $var:find() only works for arrays, not hashes")
    end

    return false
end

function _MOCHI_MOD_TABLES:_is_array()
    return getmetatable(self).__is_array
end
]],
    ["String"] = [[
local $var = {}
function $var.starts_w(str, item)
  return string.sub(str, 1, string.len(item)) == item
end

function $var.ends_w(str, item)
  return string.sub(str, -string.len(item)) == item
end

function $var.split(str, sep)
   sep = sep or '%s'
   local t = T and T{} or {}  
   for s in string.gmatch(str, '([^'..sep..']+)') do
      table.insert(t, s)
   end

   return t
end
]]
}

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

local function is_space(c)
    return c == " " or c == "\t"
end

local function emit_word(word)
    output = output .. word
end

local function skip_whitespace(chars, start_pos)
    local pos = start_pos
    while chars[pos] and is_space(chars[pos]) do
        pos = pos + 1
    end
    return pos
end

-- TODO: add a backwards version of collect_until?
-- see compound ops for more insane details on why
local function collect_until(chars, start_pos, stop_char)
    local result = ""
    local pos = start_pos
    while chars[pos] and chars[pos] ~= stop_char do
        result = result .. chars[pos]
        pos = pos + 1
    end
    return result, pos
end

local function get_var_name(chars, i)
    local var = ""
    local n = 1
    
    -- skip any whitespace before the operator
    while chars[i-n] and is_space(chars[i-n]) do
        n = n + 1
    end
    
    -- now collect the variable name
    local var_chars = {}
    while chars[i-n] and chars[i-n]:match("[%w_%.]") do
        table.insert(var_chars, 1, chars[i-n])
        n = n + 1
    end
    
    return table.concat(var_chars)
end

local function extract_braces(str)
    local start_pos = str:find("{")
    if not start_pos then return nil end

    local depth = 0
    for i = start_pos, #str do
        local c = str:sub(i, i)
        if c == "{" then
            depth = depth + 1
        elseif c == "}" then
            depth = depth - 1
            if depth == 0 then
                -- return contents without outer braces
                return str:sub(start_pos + 1, i - 1)
            end
        end
    end
end

-- i realize I'm just duplicating shit
-- maybe I'll clean it up later and re-use this function
local function process_string_interpolation(expr)
    local result = {}
    local i = 1
    while i <= #expr do
        local c = expr:sub(i, i)
        
        if c == '"' then
            -- found a string, process it for interpolation
            local j = i + 1
            local string_parts = {}
            local current_literal = ""
            local string_closed = false
            
            while j <= #expr do
                if expr:sub(j, j) == '"' and (j == 1 or expr:sub(j-1, j-1) ~= "\\") then
                    string_closed = true
                    break
                elseif expr:sub(j, j+1) == "#{" then
                    if current_literal ~= "" then
                        table.insert(string_parts, {type="literal", content=current_literal})
                        current_literal = ""
                    end
                    j = j + 2
                    local interp_expr = ""
                    local brace_depth = 1
                    while j <= #expr and brace_depth > 0 do
                        if expr:sub(j, j) == "{" then
                            brace_depth = brace_depth + 1
                        elseif expr:sub(j, j) == "}" then
                            brace_depth = brace_depth - 1
                            if brace_depth == 0 then break end
                        end
                        interp_expr = interp_expr .. expr:sub(j, j)
                        j = j + 1
                    end
                    table.insert(string_parts, {type="expr", content=interp_expr})
                    j = j + 1
                else
                    current_literal = current_literal .. expr:sub(j, j)
                    j = j + 1
                end
            end
            
            if current_literal ~= "" then
                table.insert(string_parts, {type="literal", content=current_literal})
            end
            
            -- build the interpolated string
            if #string_parts == 0 then
                table.insert(result, '""')
            elseif #string_parts == 1 and string_parts[1].type == "literal" then
                table.insert(result, '"' .. string_parts[1].content .. '"')
            else
                for idx, part in ipairs(string_parts) do
                    if idx > 1 then
                        table.insert(result, " .. ")
                    end
                    if part.type == "literal" then
                        table.insert(result, '"' .. part.content .. '"')
                    else
                        table.insert(result, part.content)
                    end
                end
            end
            
            i = j + 1
        else
            table.insert(result, c)
            i = i + 1
        end
    end
    
    return table.concat(result)
end

local function find_word(word, chars, start_at)
    local word_len = #word
    
    -- first character doesn't match? don't even bother.
    if chars[start_at] ~= word:sub(1, 1) then
        return false
    end

    -- ensure we have enough characters left for the word
    if not chars[start_at + word_len - 1] then
        return false
    end

    -- make sure the rest match up
    for i = 1, word_len do
        local char = chars[start_at + i - 1]
        if char ~= word:sub(i, i) then
            return false
        end
    end

    -- check preceding character
    local before = chars[start_at - 1]
    if before and before:match("[%w_]") then
        return false
    end

    -- check following character
    local after = chars[start_at + word_len]
    if after and after:match("[%w_]") then
        return false
    end

    return true
end

-- "little" helper to strip comments from source before we
-- even begin parsing the file. I couldn't think of a better way to do this
local function strip_comments(source)
    local result = {}
    local in_string = false
    local string_char = nil
    local in_interp = false
    local i = 1
    
    while i <= #source do
        local char = source:sub(i, i)
        local next_char = source:sub(i+1, i+1)
        
        -- track string boundaries
        if char == '"' or char == "'" then
            -- count consecutive backslashes before this quote
            local backslash_count = 0
            local j = i - 1
            while j >= 1 and source:sub(j, j) == "\\" do
                backslash_count = backslash_count + 1
                j = j - 1
            end
            
            -- quote is only escaped if preceded by an odd number of backslashes
            local is_escaped = (backslash_count % 2) == 1
            
            if not is_escaped then
                if not in_string then
                    in_string = true
                    string_char = char
                elseif char == string_char and not in_interp then
                    in_string = false
                    string_char = nil
                end
            end
        end
        
        -- track interpolation inside double quote strings only
        if in_string and string_char == '"' then
            if char == '#' and next_char == '{' then
                in_interp = true
            elseif char == '}' and in_interp then
                in_interp = false
            end
        end
        
        -- remove comments outside of strings and interpolations
        if char == '#' and not in_string and not in_interp then
            -- skip the rest of the line (the comment)
            while i <= #source and source:sub(i, i) ~= '\n' do
                i = i + 1
            end
            -- buuut keep the newline
            if i <= #source then
                table.insert(result, '\n')
            end
        else
            table.insert(result, char)
        end
        
        i = i + 1
    end
    
    return table.concat(result)
end

local function preprocess_shortcuts(chars)
    local i = 1
    local in_string = 0
    local in_interpolation = false
    local result = {}
    
    while i <= #chars do
        local c = chars[i]
        
        -- track string state
        if c == '"' and (i == 1 or chars[i-1] ~= "\\") then
            if in_string == 0 then
                in_string = 1
            elseif in_string == 1 then
                in_string = 0
            end
        elseif c == "'" and (i == 1 or chars[i-1] ~= "\\") then
            if in_string == 0 then
                in_string = 2
            elseif in_string == 2 then
                in_string = 0
            end
        end
        
        -- track interpolation (#{})
        if in_string > 0 and c == "#" and chars[i+1] == "{" then
            in_interpolation = true
        elseif in_interpolation and c == "}" then
            in_interpolation = false
        end
        
        -- only process shortcuts outside strings (or inside interpolation)
        if in_string == 0 or in_interpolation then
            -- Convert @ to self.
            if c == "@" then
                table.insert(result, "s")
                table.insert(result, "e")
                table.insert(result, "l")
                table.insert(result, "f")
                table.insert(result, ".")
                i = i + 1
                goto continue
            end

            if c == "!" and (chars[i+1] and chars[i+1] == "=") then
                table.insert(result, "~")
                i = i + 1
                goto continue
            end

            -- convert \ to self:
            if c == "\\" then
                local prev = chars[i-1]
                local next_c = chars[i+1]
                
                -- it's a shortcut if there's no identifier char before it
                -- and there IS an identifier char after it
                if (not prev or not prev:match("[%w_]")) and 
                   (next_c and next_c:match("[%w_]")) then
                    table.insert(result, "s")
                    table.insert(result, "e")
                    table.insert(result, "l")
                    table.insert(result, "f")
                    table.insert(result, ":")
                    i = i + 1
                    goto continue
                end
            end
        end
        
        -- default: just copy the bitch over
        table.insert(result, c)
        i = i + 1
        
        ::continue::
    end
    
    return result
end

local function transpile(source_path)
    output = ""
    tracker = {
        in_string    = 0,   -- 0 no string, 1 = ", 2 = '
        block_depth  = 0,   -- how many blocks we're in (def, for, while, if, etc)
        table_depth  = 0,   -- how many tables/hashes we're nested in
        in_class     = nil, -- nil when not in class, or the class name when inside
        has_class    = false,
        in_case      = nil, -- are we inside a case
        class_depth  = 0,   -- track class nesting depth
        case_depth   = 0,   -- track case depth
        case_first   = true, -- is it the first "when" in a case to translate to if
        case_subj    = nil,
        in_each_block = false,
        line_start   = true, -- are we at the start of a line (ignoring whitespace)?
        seen_assignment = false, -- have we seen = on this line?
        var_assign_name = "", -- last known variable that was assigned
        modules_to_load = {}, -- which modules get injected at run time
        mod_vars = {},        -- the local var name the module will be stored in
        method = {               -- track method signatures
            args = "",
            name = "",
            class_name = ""
        }
    }
    local chars = {}
    
    -- first pass: read all characters into the table
    for line in io.lines(source_path) do
        local str_len = #line
        line = strip_comments(line)
        for i=1, str_len do
            local c = line:sub(i, i)
            table.insert(chars, c)
        end
        -- add newline between lines
        table.insert(chars, "\n")
    end

    chars = preprocess_shortcuts(chars)
    
    -- second pass: parse the characters
    local i = 1
    local line_no = 1
    
    while i <= #chars do
        local c = chars[i]
        local next_char = chars[i+1]
        local last_char = chars[i-1]

        -- track line numbers
        if c == "\n" then
            line_no = line_no + 1
            tracker.line_start = true
            tracker.seen_assignment = false
            tracker.var_assign_name = ""
            emit_word(c)
            i = i + 1
            goto continue
        end
        
        -- whitespace doesn't break line_start
        if tracker.line_start and is_space(c) then
            emit_word(c)
            i = i + 1
            goto continue
        end
        
        -- track if we see an assignment operator BEFORE checking for statement ternaries
        -- need to peek ahead on the line to see if there's an = before any ?
        if tracker.line_start and not tracker.seen_assignment and tracker.in_string == 0 then
            local peek_pos = i
            while chars[peek_pos] and chars[peek_pos] ~= "\n" and chars[peek_pos] ~= "?" do
                if chars[peek_pos] == "=" then
                    local prev = chars[peek_pos-1]
                    local nxt = chars[peek_pos+1]
                    -- check if it's an assignment = (not ==, >=, <=, ~=, =>)
                    if prev ~= "=" and prev ~= ">" and prev ~= "<" and prev ~= "~" and 
                       nxt ~= "=" and nxt ~= ">" then
                        tracker.seen_assignment = true
                        break
                    end
                end
                peek_pos = peek_pos + 1
            end
        end
        
        -- check for statement ternary at line start
        if tracker.line_start and not tracker.seen_assignment and not is_space(c) and c ~= "\n" and tracker.in_string == 0 then
            -- peek ahead to see if there's a ? at the line level
            local peek_pos = i
            local peek_depth = 0
            local has_statement_ternary = false
            
            while chars[peek_pos] and chars[peek_pos] ~= "\n" do
                if chars[peek_pos] == "(" or chars[peek_pos] == "[" or chars[peek_pos] == "{" then
                    peek_depth = peek_depth + 1
                elseif chars[peek_pos] == ")" or chars[peek_pos] == "]" or chars[peek_pos] == "}" then
                    peek_depth = peek_depth - 1
                elseif chars[peek_pos] == "?" and peek_depth == 0 then
                    has_statement_ternary = true
                    break
                end
                peek_pos = peek_pos + 1
            end
            
            if has_statement_ternary then
                -- collect condition
                local condition = ""
                while chars[i] and chars[i] ~= "?" do
                    condition = condition .. chars[i]
                    i = i + 1
                end
                
                condition = trim(condition)
                
                i = i + 1  -- skip ?
                i = skip_whitespace(chars, i)
                
                -- collect true expression (until : or newline)
                local true_expr = ""
                local depth = 0
                while chars[i] and chars[i] ~= "\n" do
                    if chars[i] == "(" or chars[i] == "[" or chars[i] == "{" then
                        depth = depth + 1
                        true_expr = true_expr .. chars[i]
                        i = i + 1
                    elseif chars[i] == ")" or chars[i] == "]" or chars[i] == "}" then
                        depth = depth - 1
                        true_expr = true_expr .. chars[i]
                        i = i + 1
                    elseif chars[i] == ":" and depth == 0 then
                        break
                    else
                        true_expr = true_expr .. chars[i]
                        i = i + 1
                    end
                end
                
                true_expr = process_string_interpolation(trim(true_expr))
                
                if chars[i] == ":" then
                    -- has else clause
                    i = i + 1  -- skip :
                    i = skip_whitespace(chars, i)
                    
                    -- collect false expression
                    local false_expr = ""
                    while chars[i] and chars[i] ~= "\n" do
                        false_expr = false_expr .. chars[i]
                        i = i + 1
                    end
                    
                    false_expr = process_string_interpolation(trim(false_expr))
                    
                    emit_word("if " .. condition .. " then " .. true_expr .. " else " .. false_expr .. " end")
                else
                    -- no else clause
                    emit_word("if " .. condition .. " then " .. true_expr .. " end")
                end
                
                tracker.line_start = false
                goto continue
            end
        end
        
        -- anything else means we're not at line start anymore
        if tracker.line_start and not is_space(c) then
            tracker.line_start = false
        end

        -- handle string opening/closing and interpolation
        if c == "\"" and tracker.in_string == 0 then
            -- check if this is an escaped quote
            if last_char and last_char == "\\" then
                emit_word(c)
                i = i + 1
            else
                -- start of a string so check for interpolation
                tracker.in_string = 1
                
                -- collect the entire string content first
                local string_parts = {}
                local current_literal = ""
                local j = i + 1
                local string_closed = false
                
                while chars[j] do
                    -- check if string is closing (and not escaped)
                    if chars[j] == "\"" and chars[j-1] ~= "\\" then
                        string_closed = true
                        break
                    end
                    
                    -- check for interpolation start
                    if chars[j] == "#" and chars[j+1] == "{" and chars[j-1] ~= "\\" then
                        -- save current literal if any
                        if current_literal ~= "" then
                            table.insert(string_parts, {type="literal", content=current_literal})
                            current_literal = ""
                        end
                        
                        -- collect the expression
                        j = j + 2  -- skip #{
                        local expr = ""
                        local brace_depth = 1
                        
                        while chars[j] and brace_depth > 0 do
                            if chars[j] == "{" then
                                brace_depth = brace_depth + 1
                                expr = expr .. chars[j]
                                j = j + 1
                            elseif chars[j] == "}" then
                                brace_depth = brace_depth - 1
                                if brace_depth == 0 then
                                    break
                                end
                                expr = expr .. chars[j]
                                j = j + 1
                            else
                                expr = expr .. chars[j]
                                j = j + 1
                            end
                        end
                        
                        if brace_depth ~= 0 then
                            rerr("Unclosed interpolation at line %d", line_no)
                        end
                        
                        table.insert(string_parts, {type="expr", content=expr})
                        j = j + 1  -- skip closing }
                    else
                        current_literal = current_literal .. chars[j]
                        j = j + 1
                    end
                end
                
                if not string_closed then
                    rerr("Unclosed string at line %d", line_no)
                end
                
                -- save final literal if any
                if current_literal ~= "" then
                    table.insert(string_parts, {type="literal", content=current_literal})
                end
                
                -- now emit the proper Lua code
                if #string_parts == 0 then
                    emit_word('""')
                elseif #string_parts == 1 and string_parts[1].type == "literal" then
                    emit_word('"' .. string_parts[1].content .. '"')
                else
                    -- need concatenation
                    for idx, part in ipairs(string_parts) do
                        if idx > 1 then
                            emit_word(" .. ")
                        end
                        
                        if part.type == "literal" then
                            emit_word('"' .. part.content .. '"')
                        else
                            emit_word(part.content)
                        end
                    end
                end
                
                i = j + 1  -- skip past closing quote
                tracker.in_string = 0
            end
            
        -- handle single quotes
        -- no interpolation to be found here
        elseif c == "'" then
            if tracker.in_string == 0 then
                tracker.in_string = 2
                emit_word(c)
                i = i + 1
            elseif tracker.in_string == 2 then
                -- make sure it wasn't escaped
                if last_char and last_char == "\\" then
                    emit_word(c)
                    i = i + 1
                else
                    -- close it off
                    tracker.in_string = 0
                    emit_word(c)
                    i = i + 1
                end
            else
                emit_word(c)
                i = i + 1
            end
            
        -- handle opening braces (tables)
        elseif c == "{" and tracker.in_string == 0 then
            -- check if this is an each block (has | right after {)
            local next_non_space = i + 1
            while chars[next_non_space] and is_space(chars[next_non_space]) do
                next_non_space = next_non_space + 1
            end
            
            -- if it's {|, don't treat as table - it's an each block
            if chars[next_non_space] == "|" then
                emit_word("{")
                i = i + 1
            else
                tracker.table_depth = tracker.table_depth + 1
                emit_word("{")
                i = i + 1
            end
            
        -- handle closing braces
        elseif c == "}" and tracker.in_string == 0 then
            -- check if this closes an each block
            if tracker.in_each_block and tracker.table_depth == 0 then
                tracker.in_each_block = false
                tracker.block_depth = tracker.block_depth - 1
                emit_word("\nend")
                i = i + 1
            else
                tracker.table_depth = tracker.table_depth - 1
                if tracker.table_depth < 0 then
                    rerr("Unexpected } at line %d", line_no)
                end
                emit_word("}")
                i = i + 1
            end
            
        -- handle table key syntax when inside a table
        elseif tracker.table_depth > 0 and c == ":" and tracker.in_string == 0 then
            i = i + 1
            
            -- check if it's raw lua, ie: :[RAW KEY HERE]
            if chars[i] == "[" then
                i = i + 1  -- skip [
                emit_word("[")
                
                -- collect until ]
                local key = ""
                while chars[i] and chars[i] ~= "]" do
                    key = key .. chars[i]
                    i = i + 1
                end
                
                if chars[i] ~= "]" then
                    rerr("Expected ] at line %d", line_no)
                end
                
                emit_word(key .. "]")
                i = i + 1  -- skip ]
            else
                -- regular :key syntax - collect the identifier
                local key = ""
                while chars[i] and chars[i]:match("[%w_]") do
                    key = key .. chars[i]
                    i = i + 1
                end

                if key == "" then
                    rerr("Expected key name after : at line %d", line_no)
                end
                
                emit_word(key)
            end
            
            -- now look for =>
            i = skip_whitespace(chars, i)
            
            if chars[i] == "=" and chars[i+1] == ">" then
                emit_word(" = ")
                i = i + 2
            else
                rerr("Expected => after key at line %d", line_no)
            end
            
        -- handle inline ternary (not at line start or after assignment)
        elseif c == "?" and tracker.in_string == 0 and (not tracker.line_start or tracker.seen_assignment) then
            i = i + 1  -- skip ?
            i = skip_whitespace(chars, i)
            
            -- collect the true expression (until : or end of expression)
            local true_expr = ""
            local depth = 0  -- track parens/brackets/braces
            
            while chars[i] do
                if chars[i] == "(" or chars[i] == "[" or chars[i] == "{" then
                    depth = depth + 1
                    true_expr = true_expr .. chars[i]
                    i = i + 1
                elseif chars[i] == ")" or chars[i] == "]" or chars[i] == "}" then
                    if depth == 0 then
                        -- end of expression
                        break
                    end
                    depth = depth - 1
                    true_expr = true_expr .. chars[i]
                    i = i + 1
                elseif chars[i] == ":" and depth == 0 then
                    -- found the else part
                    break
                elseif (chars[i] == "\n" or chars[i] == ";" or chars[i] == ",") and depth == 0 then
                    -- end of expression
                    break
                else
                    true_expr = true_expr .. chars[i]
                    i = i + 1
                end
            end
            
            true_expr = process_string_interpolation(trim(true_expr))
            
            if chars[i] == ":" then
                -- we has else branch
                i = i + 1  -- skip :
                i = skip_whitespace(chars, i)
                
                -- collect false expression
                local false_expr = ""
                depth = 0
                
                while chars[i] do
                    if chars[i] == "(" or chars[i] == "[" or chars[i] == "{" then
                        depth = depth + 1
                        false_expr = false_expr .. chars[i]
                        i = i + 1
                    elseif chars[i] == ")" or chars[i] == "]" or chars[i] == "}" then
                        if depth == 0 then
                            -- end of expression
                            break
                        end
                        depth = depth - 1
                        false_expr = false_expr .. chars[i]
                        i = i + 1
                    elseif (chars[i] == "\n" or chars[i] == ";" or chars[i] == ",") and depth == 0 then
                        -- end of expression
                        break
                    else
                        false_expr = false_expr .. chars[i]
                        i = i + 1
                    end
                end
                
                false_expr = process_string_interpolation(trim(false_expr))
                
                emit_word(" and " .. true_expr .. " or " .. false_expr)
            else
                -- no else branch, just emit: and true_expr
                emit_word(" and " .. true_expr)
            end
            
        -- stuff we need to check that happens outside of strings
        elseif tracker.in_string == 0 then
            if find_word("class", chars, i) then
                i = i + 5  -- skip "class"
                tracker.block_depth = tracker.block_depth + 1
                
                -- skip whitespace after "class"
                i = skip_whitespace(chars, i)
                
                -- collect class name
                local class_name = ""
                while chars[i] and chars[i]:match("[%w_]") do
                    class_name = class_name .. chars[i]
                    i = i + 1
                end
                
                if class_name == "" then
                    rerr("Expected class name after 'class' at line %d", line_no)
                end
                
                -- track that we're now inside this class
                tracker.in_class = class_name
                tracker.class_depth = tracker.block_depth
                tracker.has_class = true
                
                -- skip whitespace after name
                i = skip_whitespace(chars, i)
                
                -- check for derive (extends) from (<)
                local derive_from = chars[i] == "<"
                if derive_from then
                    i = i + 1
                    i = skip_whitespace(chars, i)
                    local base_name = ""
                    while chars[i] and chars[i]:match("[%w_]") do
                        base_name = base_name .. chars[i]
                        i = i + 1
                    end
                    
                    if base_name == "" then
                        rerr("Expected parent class name after < at line %d", line_no)
                    end
                    
                    emit_word(string.format("local %s = %s:extend_as(\"%s\")", class_name, base_name, class_name))
                else
                    emit_word(string.format("local %s = class:extend_as(\"%s\")", class_name, class_name))
                end
            
            elseif find_word("extend", chars, i) then
                i = i + 7
                i = skip_whitespace(chars, i)
                local mod_name = ""
                mod_name, i = collect_until(chars, i, "\n")
                mod_name = trim(mod_name)

                local save_var = ""
                mod_name, save_var = mod_name:match("([%w_]+)%s*as%s*([%w_]+)")

                if not mod_name or not save_var then
                    rerr("Invalid syntax for 'extend' at line %d", line_no)
                end

                if mod_name == "" or mod_name:match("%s+") then
                    rerr("Invalid module name at line %d", line_no)
                end

                if modules[mod_name] then
                    for _,mod in ipairs(tracker.modules_to_load) do
                        if mod_name == mod then
                            rerr("Attempted to load '%s' twice at line %d", mod_name, line_no)
                        end
                    end

                    table.insert(tracker.modules_to_load, mod_name)
                else
                    rerr("Module '%s' does not exist at line %d", mod_name, line_no)
                end

                tracker.mod_vars[mod_name] = save_var

            elseif find_word("def", chars, i) then
                local inline = false
                i = i + 3  -- skip "def"
                
                -- skip whitespace after "def"
                i = skip_whitespace(chars, i)
                
                -- collect function name
                local func_name = ""
                while chars[i] and chars[i]:match("[%w:._]") do
                    func_name = func_name .. chars[i]
                    i = i + 1
                end
                
                -- no function name so just assume it's anonymous
                if func_name == "" then
                    inline = true
                end
                
                -- skip any whitespace after name
                i = skip_whitespace(chars, i)
                
                -- check for args
                local has_parens = chars[i] == "("
                local args = ""
                
                if has_parens then
                    i = i + 1  -- skip opening (
                    args, i = collect_until(chars, i, ")")
                    i = i + 1  -- skip closing )
                    
                    -- skip whitespace after )
                    i = skip_whitespace(chars, i)
                    args = args:gsub("*args", "...")
                end

                tracker.method.args = args == "" and "self" or "self, " .. args
                tracker.method.name = func_name
                tracker.method.class_name = tracker.in_class
                
                -- check for scope modifier
                local scope = ""
                if chars[i] == ":" then
                    if inline then
                        rerr("Scope modifiers are not available for inline 'def' at line %d", line_no)
                    end

                    i = i + 1  -- skip :
                    i = skip_whitespace(chars, i)
                    
                    -- collect scope keyword
                    while chars[i] and chars[i]:match("[%w_]") do
                        scope = scope .. chars[i]
                        i = i + 1
                    end
                    
                    scope = scope:lower()
                end
                
                -- now emit the proper Lua code
                if scope == "local" then
                    emit_word("local ")
                end
                
                emit_word("function ")

                -- if we're inside a class, prepend ClassName:
                -- also, don'y apply class name to anonymous functions
                if tracker.in_class and not inline then
                    emit_word(tracker.in_class .. ":")
                end
                
                emit_word(func_name .. "(")
                if has_parens then
                    emit_word(args)
                end
                emit_word(") ")
                
                tracker.block_depth = tracker.block_depth + 1
                
            elseif find_word("end", chars, i) then
                tracker.block_depth = tracker.block_depth - 1
                if tracker.block_depth < 0 then
                    rerr("Too many 'end' statements found at line %d", line_no)
                end
                
                local no_emit = false -- when we DON'T want to emit an end
                
                -- check if we're closing a class
                if tracker.in_class and tracker.block_depth < tracker.class_depth then
                    tracker.in_class = nil
                    tracker.class_depth = 0
                    no_emit = true

                -- check if we're closing a case  
                elseif tracker.in_case and tracker.block_depth < tracker.case_depth then
                    tracker.in_case = nil
                    tracker.case_subj = nil
                    tracker.case_depth = 0
                    tracker.case_first = true
                end

                if not no_emit then emit_word("end") end
                
                i = i + 3  -- skip past "end"

            elseif find_word("*args", chars, i) then
                emit_word("...")
                i = i + 5

            elseif find_word("super", chars, i) then
                i = i + 5
                if not tracker.in_class then
                    rerr("Can't call 'super' when not inside class at line %d", line_no)
                end

                emit_word(string.format("%s.parent.%s(%s)",
                    tracker.method.class_name,
                    tracker.method.name,
                    tracker.method.args))

            elseif find_word("each", chars, i) then
                local last_char = chars[i-1] or nil
                if last_char and last_char == "." then
                    local var = ""
                    local n = 2 -- start just before the .
                    
                    -- backtrack to find the variable name
                    while true do
                        last_char = chars[i-n] or nil
                        --if last_char and last_char:match("[%w@%._]") then
                        if last_char and last_char:match("%S") then
                            var = var .. last_char
                        else
                            break
                        end
                        n = n + 1
                    end

                    --if not var:match("[%w@%._]") then
                    if not var:match("%S") then
                        rerr("Invalid expression (check for spaces) before 'each' at line %d", line_no)
                    end

                    var = var:reverse()

                    var = var:gsub("*args", "...")
                    
                    -- remove the variable and dot from output
                    local remove_len = #var + 1  -- +1 for the dot
                    output = output:sub(1, -(remove_len + 1))
                    
                    local body = ""
                    local args = ""
                    local use_braces = false

                    -- check if it's the brace syntax {|args| ... }
                    i = i + 4
                    i = skip_whitespace(chars, i)

                    if chars[i] == "{" then
                        use_braces = true
                        i = i + 1  -- skip {
                        i = skip_whitespace(chars, i)
                        
                        if chars[i] ~= "|" then
                            rerr("Expected | after { in 'each' block at line %d", line_no)
                        end
                        
                        i = i + 1  -- skip |
                        args, i = collect_until(chars, i, "|")
                        i = i + 1  -- skip closing |
                        args = args:match("^%s*(.-)%s*$")
                    else
                        -- do |args| syntax
                        body, i = collect_until(chars, i, "|")
                        body = trim(body)
                        if body ~= "do" then
                            rerr("Invalid 'each' implementation. Missing 'do' perhaps at line %d", line_no)
                        end
                        
                        i = i + 1 -- skip |
                        args, i = collect_until(chars, i, "|")
                        i = i + 1 -- skip other |
                        args = args:match("^%s*(.-)%s*$")
                    end

                    -- ranged each n..n
                    if var:match("[%w@_.]+%.%.[%w@_.]+") then
                        local lo_num, hi_num = var:match("([%w@_.]+)%.%.([%w@_.]+)")
                        if not hi_num then
                            rerr("Bad range in 'each' at line %d", line_no)
                        end

                        local incdec
                        if args:match(",") then
                            args, incdec = args:match("([%w-@_.]+)%s*,%s*([%w-@_.]+)")
                        end

                        if incdec then
                            if not incdec:match("%d+") then
                                rerr("Invalid variation '%s' in each. Must be a number at line %d", incdec, line_no)
                            end

                            emit_word(string.format("for %s=%s,%s,%s do\n", args, lo_num, hi_num, incdec))
                        else
                            emit_word(string.format("for %s=%s,%s do\n", args, lo_num, hi_num))
                        end
                    else
                        -- add _ for index if not supplied
                        if not args:match(",") then
                            args = "_," .. args
                        end
                        emit_word(string.format("for %s in ipairs(%s) do\n", args, var))
                    end
                    -- don't think I need this anymore. not sure why ¯\_(ツ)_/¯
                    --line_no = line_no + 1
                    tracker.block_depth = tracker.block_depth + 1

                    -- if using brace syntax, need to find the closing }
                    if use_braces then
                        tracker.in_each_block = true
                    end
                else
                    rerr("Invalid character preceeding 'each' at line %d", line_no)
                end

            elseif find_word("each_pair", chars, i) then
                local last_char = chars[i-1] or nil
                if last_char and last_char == "." then
                    local var = ""
                    local n = 2 -- start just before the .
                    
                    -- backtrack to find the variable name
                    while true do
                        last_char = chars[i-n] or nil
                        if last_char and last_char:match("[%w@%._]") then
                            var = var .. last_char
                        else
                            break
                        end
                        n = n + 1
                    end

                    if not var:match("[%w@%._]") then
                        rerr("Invalid expression before 'each_pair' at line %d", line_no)
                    end

                    var = var:reverse()
                    
                    -- remove the variable and dot from output
                    local remove_len = #var + 1  -- +1 for the dot
                    output = output:sub(1, -(remove_len + 1))
                    
                    i = skip_whitespace(chars, i)
                    local body = ""
                    local args = ""
                    body, i = collect_until(chars, i, "|")

                    if not body:match("%s*each_pair%s+do%s*") then
                        rerr("Invalid 'each_pair' implementation. Missing 'do' perhaps at line %d", line_no)
                    end

                    i = i + 1 -- skip |
                    args, i = collect_until(chars, i, "|")
                    i = i + 1 -- skip other |
                    args = args:match("^%s*(.-)%s*$")

                    -- add _ for index if not supplied
                    if not args:match(",") then
                        args = "_," .. args
                    end

                    emit_word(string.format("for %s in pairs(%s) do\n", args, var))
                    line_no = line_no + 1
                    tracker.block_depth = tracker.block_depth + 1
                else
                    rerr("Invalid character preceeding 'each_pair' at line %d", line_no)
                end

                i = i + 4 -- why the hell is this 4 and not 9????

            elseif find_word("case", chars, i) then
                if tracker.in_case then
                    rerr("You're already inside a 'case' at line %d", line_no)
                end

                i = i + 4
                i = skip_whitespace(chars, i)
                local subj = ""
                subj, i = collect_until(chars, i, "\n")
                subj = trim(subj)
                if subj == "" then
                    rerr("'case' expects topic at line %d", line_no)
                end

                tracker.in_case = true
                tracker.case_subj = subj
                tracker.block_depth = tracker.block_depth + 1
                tracker.case_depth = tracker.block_depth
            
            elseif find_word("when", chars, i) then
                if not tracker.in_case then
                    rerr("Unable to use 'when' outside 'case' at line %d", line_no)
                end

                if_stmt = tracker.case_first and "if" or "elseif"

                i = i + 4
                i = skip_whitespace(chars, i)
                local expr = ""
                expr, i = collect_until(chars, i, "\n")
                expr = trim(expr)

                if expr == "" then
                    rerr("'when' expects an expression at line %d", line_no)
                end

                expr = process_string_interpolation(expr)

                -- match range n..n
                if expr:match("[%w_]%.%.[%w_]") then
                    local lo_num, hi_num = expr:match("([%w_]+)%.%.([%w_]+)")
                    if not hi_num then
                        rerr("Invalid range check in 'case' at line %d", line_no)
                    end

                    emit_word(string.format("%s %s >= %s and %s <= %s then",
                        if_stmt, tracker.case_subj, lo_num, tracker.case_subj, hi_num))

                elseif expr:match("|") then
                    local cond = ""
                    expr = expr:gsub("[\"']", "") -- remove any quotes
                    for word in expr:gmatch("([^|]+)") do
                        cond = cond .. string.format("%s == \"%s\" or ", tracker.case_subj, trim(word))
                    end

                    -- remove the last or
                    cond = cond:sub(1, -4)

                    emit_word(string.format("%s %s then", if_stmt, cond))

                -- > < >= <= match
                elseif expr:match("^[><=]+%s*[%w_]+$") then
                    local sym, num = expr:match("^([><=]+)%s*([%w_]+)$")

                    emit_word(string.format("%s %s %s %s then",
                        if_stmt, tracker.case_subj, sym, num))

                -- anything else: if subj expr
                else
                    emit_word(string.format("%s %s == %s then",
                        if_stmt, tracker.case_subj, expr))
                end

                tracker.case_first = not tracker.case_first
            
            elseif find_word("else", chars, i) then
                -- handle else - works in both case statements and regular if statements
                emit_word("else")
                i = i + 4
            
            elseif find_word("elsif", chars, i) then              
                i = i + 5  -- skip "elsif"
                i = skip_whitespace(chars, i)
                
                -- collect the condition (everything until newline)
                local condition = ""
                condition, i = collect_until(chars, i, "\n")
                condition = trim(condition)
                
                if condition == "" then
                    rerr("'elsif' expects a condition at line %d", line_no)
                end
                
                emit_word("elseif " .. condition .. " then")
            
            elseif find_word("if", chars, i) then
                -- handle if statements without requiring 'then'
                i = i + 2  -- skip "if"
                i = skip_whitespace(chars, i)
                
                -- collect the condition
                local condition = ""
                condition, i = collect_until(chars, i, "\n")
                condition = trim(condition)
                
                if condition == "" then
                    rerr("'if' expects a condition at line %d", line_no)
                end
                
                emit_word("if " .. condition .. " then")
                tracker.block_depth = tracker.block_depth + 1
            
            elseif find_word("while", chars, i) then
                -- handle while loops without requiring 'do'
                i = i + 5  -- skip "while"
                i = skip_whitespace(chars, i)
                
                -- collect the condition
                local condition = ""
                condition, i = collect_until(chars, i, "\n")
                condition = trim(condition)
                
                if condition == "" then
                    rerr("'while' expects a condition at line %d", line_no)
                end
                
                emit_word("while " .. condition .. " do")
                tracker.block_depth = tracker.block_depth + 1

            elseif find_word("new", chars, i) then
                local last_i = i
                i = i + 3
                i = skip_whitespace(chars, i)

                -- end at new, so they explicitly want to use .new()
                if not chars[i]:match("[%w%._]+") and chars[last_i-1] == '.' then
                    local sv_i = last_i -1

                    i = last_i + 3
                    output = output:sub(1, -2)
                    emit_word(":new")

                    -- look ahead for parens
                    -- if none found, then close off new()
                    i = skip_whitespace(chars, i)
                    if chars[i] ~= "(" and chars[i] ~= "{" and chars[i] ~= "[" then
                        emit_word("()")
                    end                    
                else
                    i = last_i + 3
                    output = output:sub(1, -2)
                    emit_word(".new")
                end

            elseif find_word("let", chars, i) then
                -- finally, an easy one to implement lmao
                emit_word("local ")
                i = i + 3

            elseif find_word("for", chars, i) then
                i = i + 3
                i = skip_whitespace(chars, i)
                local vars = ""
                vars, i = collect_until(chars, i, "\n")

                i = i + 1 -- skip "i"

                local expr = ""
                vars, expr = vars:match("([%w_,%s]+)%s+in%s+(%S+)")

                if not expr or expr == "" then
                    rerr("Invalid 'for' loop at line %d", line_no)
                end

                -- ipairs
                if expr:sub(1, 1) == "@" then
                    expr = "ipairs(" .. expr:sub(2, #expr) .. ")"

                -- pairs
                elseif expr:sub(1, 1) == "%" then
                    expr = "pairs(" .. expr:sub(2, #expr) .. ")"

                elseif not expr:match("[%w_]") then
                    rerr("Expression not recognized in 'for' loop at line %d", line_no)
                end

                emit_word(string.format("for %s in %s do\n", vars, expr))

                tracker.block_depth = tracker.block_depth + 1
                -- for messes with line_no somehow..
                line_no = line_no + 1

                tracker.line_start = true
                tracker.seen_assignment = false
                tracker.var_assign_name = ""

            elseif find_word("do", chars, i) then
                emit_word("do")
                -- TODO:
                -- make sure this doesn't break things, like each
                tracker.block_depth = tracker.block_depth + 1
                i = i + 2
            else
                -- track if we see an assignment operator
                if c == "=" and tracker.in_string == 0 then
                    -- Make sure it's not ==, >=, <=, ~=, =>
                    local prev = chars[i-1]
                    local nxt = chars[i+1]
                    if prev ~= "=" and prev ~= ">" and prev ~= "<" and prev ~= "~" and 
                       nxt ~= "=" and nxt ~= ">" then
                        tracker.seen_assignment = true
                        local var = get_var_name(chars, i)
                        if var then
                            tracker.var_assign_name = trim(var)
                        end
                    end

                -- handle compound assignment operators (+=, -=, *=, /=)
                elseif (c == "+" or c == "-" or c == "*" or c == "/") and 
                       chars[i+1] == "=" and tracker.in_string == 0 then
                    
                    -- we need to backtrack to find the variable being assigned to
                    local var = ""
                    local n = 1
                    
                    -- skip any whitespace before the operator
                    while chars[i-n] and is_space(chars[i-n]) do
                        n = n + 1
                    end
                    
                    -- now collect the variable name
                    local var_chars = {}
                    while chars[i-n] and chars[i-n]:match("[%w_%.]") do
                        table.insert(var_chars, 1, chars[i-n])
                        n = n + 1
                    end
                    
                    var = table.concat(var_chars)
                    
                    if var == "" then
                        rerr("Invalid compound assignment at line %d", line_no)
                    end
                    
                    -- calculate how much to remove from output (variable + whitespace before operator)
                    local remove_len = 0
                    local temp_n = 1
                    while temp_n < n do
                        remove_len = remove_len + 1
                        temp_n = temp_n + 1
                    end
                    
                    -- remove the variable and whitespace from output
                    output = output:sub(1, -(remove_len + 1))

                    -- phew, that was way too much work just to get the variable name
                    -- TODO: perhaps I should add it to a helper function in case I need
                    -- to do this again??
                    
                    -- emit the expanded form: var = var op
                    emit_word(var .. " = " .. var .. " " .. c .. " ")
                    
                    i = i + 2  -- skip the operator and =
                    goto continue
                end
                
                emit_word(c)
                i = i + 1
            end
        else
            emit_word(c)
            i = i + 1
        end
        
        ::continue::
    end
    
    -- final checks / make sure everything is closed off properly
    if tracker.block_depth > 0 then
        rerr("Missing %d 'end' statement(s)", tracker.block_depth)
    end
    
    if tracker.table_depth > 0 then
        rerr("Unclosed table/hash - missing %d }", tracker.table_depth)
    end

    -- inject class if we have one
    if tracker.has_class then
        local class_impl = [[
-- Class implementation"
local class = {}
class.__index = class
function class:initialize() end
function class:extend_as(name)
local cls = {}
cls["__call"] = class.__call
cls.__tostring = class.__tostring
cls.__index = cls
cls.parent = self
cls.__name = name or "Anonymoose"
setmetatable(cls, self)
return cls
end
function class:__tostring()
    if self.__is_instance then
        local mt = getmetatable(self)
        local name = mt and mt.__name or "Unknown"
        return string.format("%s#Instance: %p", name, self)
    else
        return string.format("%s#Class: %p", self.__name or "Unknown", self)
    end
end
function class:new(...)
    local inst = setmetatable({}, self)
    inst.__is_instance = true
    inst:initialize(...)
    return inst
end
function class:is(name)
return self.__name == name
end
function class:__call(...)
local inst = setmetatable({}, self)
inst.__is_instance = true
inst:initialize(...)
return inst
end
]]
        output = class_impl .. output
    end

    -- load any modules
    if #tracker.modules_to_load > 0 then
        -- we need to load Tables first if the user wants it
        -- because some other modules use it if it's available
        local load_tables = false
        for i,mod in ipairs(tracker.modules_to_load) do
            if mod == "Array" then
                load_tables = true
                table.remove(tracker.modules_to_load, i)
                break
            end
        end

        for _,mod in ipairs(tracker.modules_to_load) do
            local str = modules[mod]
            str = str:gsub("$([%w_]+)", tracker.mod_vars[mod])
            output = str .. output
        end

        if load_tables then
            local str = modules["Array"]
            str = str:gsub("$([%w_]+)", tracker.mod_vars["Array"])
            output = str .. output
        end
    end
end

-- for love I could probably get away with removing below and replacing
-- with return { transpile = transpile }
-- update: turns out I also need to return output at the end of transpile!
if #arg < 1 then
    rlog("Usage: muki.lua <source>")
    os.exit(0)
end

local source_path = arg[1]
if not file_exists(source_path) then
    rerr("No such file '%s'", source_path)
end

transpile(source_path)

if arg[2] then
    local s = loadstring(output)
    s()
else
    print(output)
end