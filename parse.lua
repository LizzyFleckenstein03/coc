-- stream
local expr = require("expr")

local function eat_match(x, pat, accept)
    local _, pos, match = x.buf:find("^"..pat, x.pos)
    if not pos or (accept and not accept(match)) then
        return
    end
    x.pos = pos+1
    return match or true
end

local function read_line(obj)
    if obj.file then
        return obj.file:read()
    elseif obj.read then
        return obj.read()
    else
        return obj.pos <= #obj.buf and eat_match(obj, "([^\n]*)\n?") or nil
    end
end

local function stream_new(name, inner)
    return {
        name = name,
        lineno = 0,
        line = { pos = 1, buf = "" },
        exhausted = false,
        inner =
            type(inner) == "string" and { pos = 1, buf = inner } or
            type(inner) == "function" and { read = inner } or
            { file = inner }
    }
end

local function stream_line_exhausted(st)
    return eat_match(st.line, "%s*$") ~= nil
end

local function stream_next_line(st)
    if st.exhausted then
        return
    end
    local l = read_line(st.inner)
    if not l then
        st.exhausted = true
        return
    end
    st.line = { pos = 1, buf = l }
    st.lineno = st.lineno + 1
    return true
end

local function stream_skip(st)
    st.line = { pos = 1, buf = "" }
end

local function stream_get(st, pat, accept)
    -- skip comments
    while eat_match(st.line, "%s*#.*") do
        stream_next_line(st)
    end

    local x = eat_match(st.line, "%s*("..pat..")", accept)
    if not x and stream_line_exhausted(st) and stream_next_line(st) then
        return stream_get(st, pat, accept)
    end
    return x
end

local function stream_end(st)
    return stream_line_exhausted(st) and not stream_next_line(st)
end

local function stream_pos(st)
    return ("%s:%s:%s"):format(st.name, st.lineno, st.line.pos)
end

local function stream_err(st, msg)
    return { err = "syntax_error", pos = stream_pos(st), msg = msg }
end

-- err helpers

local function expect(st, name, val, err)
    if err then
        return nil, err
    end
    if not val then
        return nil, stream_err(st, "expected "..name)
    end
    return val
end

local function expect_tok(st, tok, name)
    return expect(st, name or tok, stream_get(st, tok))
end

-- parse

local keyword = {
    ["elim"] = true,
    ["rec"] = true,
    ["ind"] = true,
    ["fun"] = true,
    ["forall"] = true,
    ["type"] = true,
    ["def"] = true,
    ["eval"] = true,
    ["check"] = true,
    ["inductive"] = true,
    ["include"] = true,
    ["exit"] = true,
}

local function parse_name(st, accept)
    -- banned chars in names: , ( ) = - > : ; #
    -- makes sense to reserve too: <
    -- want to allow: _
    -- other, perhaps allow: + * ' & | ! ? " $ % . / @ \ ` ~ { } [ ]
    return stream_get(st, "[%w_]+", accept)
end

local function parse_ident(st)
    return parse_name(st, function(x) return not keyword[x] end)
end

local parse_expr

local function parse_param_group(st)
    local has_parens = stream_get(st, "%(")
    local names = {}

    while true do
        local name = parse_ident(st)
        if not name then
            break
        end
        table.insert(names, name)
    end

    if #names == 0 then
        if has_parens then
            return nil, stream_err(st, "expected parameter name")
        end
        return
    end

    local _, err = expect_tok(st, ":") if err then return nil, err end
    local type, err = expect(st, "parameter type", parse_expr(st)) if err then return nil, err end

    if has_parens then
        local _, err = expect_tok(st, "%)", ")") if err then return nil, err end
    end

    return { names = names, type = type }
end

local function parse_param_list(st)
    local params = {}

    while true do
        local g, err = parse_param_group(st) if err then return nil, err end
        if not g then
            break
        end
        for _, n in ipairs(g.names) do
            table.insert(params, { name = n, type = g.type })
        end
    end

    return params
end

local function parse_noapp_expr(st)
    if stream_get(st, "%(") then
        local expr, err = expect(st, "inner expression", parse_expr(st)) if err then return nil, err end
        local _, err = expect_tok(st, "%)", ")") if err then return nil, err end
        return expr
    end
    local name = parse_name(st, function(x)
        return not keyword[x]
            or x == "type"
            or x == "fun"
            or x == "forall"
            or x == "elim"
            or x == "rec"
            or x == "ind"
    end)
    if not name then
        return
    end

    if not keyword[name] then
        return { kind = "free", name = name }
    elseif name == "type" then
        return { kind = "type" }
    elseif name == "elim" or name == "rec" or name == "ind" then
        local type, err = expect(st, name.." type", parse_ident(st)) if err then return nil, err end
        return { kind = "elim", elim_kind = name, type = type }
    elseif name == "fun" or name == "forall" then
        local params, err = parse_param_list(st) if err then return nil, err end
        if #params == 0 then
            return nil, stream_err(st, "expected parameter")
        end
        local _, err = expect_tok(st, name == "fun" and "=>" or ",") if err then return nil, err end
        local body, err = expect(st, "function body", parse_expr(st)) if err then return nil, err end
        return expr.fun(name, params, body)
    end
end

parse_expr = function(st)
    local expr
    while true do
        if expr and stream_get(st, "%->") then
            local right, err = expect(st, "type", parse_expr(st)) if err then return nil, err end
            return {
                kind = "forall",
                param = { name = "_", type = expr },
                body = right
            }
        end

        local right, err = parse_noapp_expr(st) if err then return nil, err end
        if not right then
            break
        end
        expr = expr and { kind = "app", left = expr, right = right  } or right
    end
    return expr
end

local function parse_stmt(st)
    local kind = parse_name(st)
    if not kind then
        return
    end

    local ret
    if kind == "def" or kind == "eval" or kind == "check" then
        local name, type, err, has_body

        has_body = true
        if kind == "def" then
            name, err = expect(st, "identifier", parse_ident(st)) if err then return nil, err end
            if not stream_get(st, ":=") then
                has_body = false
            end
        end

        local expr
        if has_body then
            expr, err = expect(st, "expression", parse_expr(st)) if err then return nil, err end
        end
        if stream_get(st, ":") then
            type, err = expect(st, "type", parse_expr(st)) if err then return nil, err end
        elseif not has_body then
            return nil, stream_err(st, "expected := or :")
        end

        ret = { kind = kind, name = name, expr = expr, type = type }
    elseif kind == "inductive" then
        local name, err = expect(st, "identifier", parse_ident(st)) if err then return nil, err end
        local outer, err = parse_param_list(st) if err then return nil, err end

        local inner, err = {}
        if stream_get(st, ">") then
            inner, err = parse_param_list(st) if err then return nil, err end
        end

        local _, err = expect_tok(st, "|") if err then return nil, err end
        local ctors, err = parse_param_list(st) if err then return nil, err end

        ret = { kind = "inductive", name = name, params = { outer = outer, inner = inner }, ctors = ctors }
    elseif kind == "include" then
        local path, err = expect(st, "path", stream_get(st, "[%w._-]+")) if err then return nil, err end
        ret = { kind = kind, path = path }
    elseif kind == "exit" then
        return { kind = "exit" }
    else
        return nil, stream_err(st, "expected command, got "..kind)
    end

    local _, err = expect_tok(st, ";") if err then return nil, err end
    return ret
end

return {
    stmt = parse_stmt,
    expr = parse_expr,
    err = stream_err,
    done = stream_end,
    stream = stream_new,
    skip = stream_skip,
}
