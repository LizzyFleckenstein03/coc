-- stream

local function stream_new(name, obj)
    local str
    if type(obj) == "string" then
        str = obj
    else
        str = obj:read("*a")
    end

    return { name = name, pos = 1, inner = str }
end

local function stream_get_skip_ws(st, pat)
    local _, pos, match = st.inner:find("^%s*"..pat, st.pos)
    if not pos then
        return
    end
    st.pos = pos+1
    return match or true
end

local function stream_get_skip_comment(st, pat)
    -- remove comments
    while stream_get_skip_ws(st, "(#[^\n]*)") do end
    return stream_get_skip_ws(st, pat)
end

local function stream_end(st)
    return stream_get_skip_comment(st, "$") ~= nil
end

local function stream_get(st, pat)
    return stream_get_skip_comment(st, "("..pat..")")
end

local function stream_pos(st)
    -- TODO: perhaps track charpos
    local lineno = 1
    for _ in st.inner:sub(1, st.pos-1):gmatch("\n") do
        lineno = lineno + 1
    end
    return st.name..":"..lineno
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

local function parse_name(st)
    -- banned chars in names: , ( ) = - > : ; #
    -- makes sense to reserve too: <
    -- want to allow: _
    -- other, perhaps allow: + * ' & | ! ? " $ % . / @ \ ` ~ { } [ ]
    local name = stream_get(st, "[%w_]+")
    if not name then
        return
    end
    return name,
        name == "fun" or
        name == "forall" or
        name == "type" or
        name == "def" or
        name == "eval" or
        name == "check" or
        name == "include"
end

local function parse_ident(st)
    local name, keyword = parse_name(st)
    if not name then
        return
    end
    if keyword then
        return nil, stream_err(st, "expected identifier, got "..name)
    end
    return name
end

local parse_expr

local function parse_param_group(st)
    local has_parens = stream_get(st, "%(")
    local names = {}

    while true do
        local name, err = parse_ident(st) if err then return nil, err end
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
    local name, keyword = parse_name(st)
    if not name then
        return
    end

    if not keyword then
        return { kind = "var", name = name }
    elseif name == "type" then
        return { kind = "type" }
    elseif name == "fun" or name == "forall" then
        local params, err = parse_param_list(st) if err then return nil, err end
        if #params == 0 then
            return nil, stream_err(st, "expected parameter")
        end
        local _, err = expect_tok(st, name == "fun" and "=>" or ",") if err then return nil, err end
        local expr, err = expect(st, "function body", parse_expr(st)) if err then return nil, err end
        for i = #params, 1, -1 do
            expr = {
                kind = name,
                param = params[i],
                body = expr
            }
        end
        return expr
    else
        return nil, stream_err(st, "expected expression, got "..kind)
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
    elseif kind == "include" then
        local path, err = expect(st, "path", stream_get(st, "[%w._-]+")) if err then return nil, err end
        ret = { kind = kind, path = path }
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
}
