local function free(x, name, env)
    if x.kind == "var" then
        return name == x.name or (x.type and free(x.type, name, env))
            or (x.ref and env and env[x.ref].val and free(env[x.ref].val, name, env))
    elseif x.kind == "app" then
        return free(x.left, name, env) or free(x.right, name, env)
    elseif x.kind == "fun" or x.kind == "forall" then
        return free(x.param.type, name, env) or (name ~= x.param.name and free(x.body, name, env))
    elseif x.kind == "type" then
        return false
    else
        error(x.kind)
    end
end

local function subst(x, name, with, env)
    if x.kind == "var" then
        return x.name == name and with or
            { kind = "var", name = x.name, type = x.type and subst(x.type, name, with, env), ref = x.ref }
    elseif x.kind == "app" then
        return { kind = "app", left = subst(x.left, name, with, env), right = subst(x.right, name, with, env) }
    elseif x.kind == "fun" or x.kind == "forall" then
        local param = { name = x.param.name, type = subst(x.param.type, name, with, env) }
        local body = x.body

        if param.name == name then
            return { kind = x.kind, param = param, body = body }
        end

        if free(with, param.name, env) then
            local stem, postfix = param.name:match("^(.+)_(%d+)$")
            if stem then
                postfix = tonumber(postfix)
            else
                stem = param.name
                postfix = 1
            end

            local new_param_name
            repeat new_param_name = ("%s_%d"):format(stem, postfix)
                postfix = postfix + 1
            until not (new_param_name == name or free(with, new_param_name, env) or free(body, new_param_name, env))

            -- TODO: loss of type?
            body = subst(body, param.name, { kind = "var", name = new_param_name }, env)
            param.name = new_param_name
        end

        return { kind = x.kind, param = param, body = subst(body, name, with, env) }
    elseif x.kind == "type" then
        return x
    else
        error(x.kind)
    end
end

local function bind(x, env)
    for i, def in ipairs(env) do
        x = subst(x, def.name, {
            kind = "var",
            name = def.name,
            type = def.type,
            ref = i,
        }, env)
    end
    return x
end

-- assumed to be in same context
local function expr_eq(a, b, alpha)
    if a.kind ~= b.kind then return false end

    alpha = alpha or function(_, x) return x end
    if a.kind == "type" then
        return true
    elseif a.kind == "var" then
        return alpha(true, a.name) == alpha(false, b.name) and a.ref == b.ref
    elseif a.kind == "app" then
        return expr_eq(a.left, b.left, alpha) and expr_eq(a.right, b.right, alpha)
    elseif a.kind == "fun" or a.kind == "forall" then
        return expr_eq(a.param.type, b.param.type, alpha) and
            expr_eq(a.body, b.body, function(side, x)
                if x == (side and a.param.name or b.param.name) then
                    return 0
                end
                local v = alpha(side, x)
                return type(v) == "number" and (v+1) or v
            end)
    else
        error(a.kind)
    end
end

local function expr_str(x)
    if x.kind == "type" then
        return x.kind
    elseif x.kind == "var" then
        return x.name
    elseif x.kind == "app" then
        local right = {}
        local left = x

        while left.kind == "app" do
            table.insert(right, 1, expr_str(left.right))
            left = left.left
        end

        return ("(%s %s)"):format(expr_str(left), table.concat(right, " "))
    elseif x.kind == "fun" or x.kind == "forall" then
        local left = {}
        local right = x

        local type
        local names = {}
        local anon
        local function commit_names()
            if not anon and #names > 0 then
                table.insert(left, ("%s : %s"):format(
                    table.concat(names, " "), expr_str(type)))
                names = {}
            end
        end

        while right.kind == x.kind do
            local want_anon = right.kind == "forall" and not free(right.body, right.param.name)
            if anon ~= nil and anon ~= want_anon then
                break
            end
            anon = want_anon

            if type ~= nil and not expr_eq(type, right.param.type) then
                commit_names()
            end
            type = right.param.type

            table.insert(names, anon and expr_str(right.param.type) or right.param.name)

            if not anon and free(right.param.type, right.param.name) then
                commit_names()
            end

            right = right.body
        end
        commit_names()

        if anon then
            table.insert(names, expr_str(right))
            return ("(%s)"):format(table.concat(names, " -> "))
        else
            if #left > 1 then
                for i, v in ipairs(left) do
                    left[i] = ("(%s)"):format(v)
                end
            end
            return ("(%s %s%s%s)"):format(x.kind, table.concat(left, " "),
                x.kind == "fun" and " => " or ", ", expr_str(right))
        end
    else
        error(x.kind)
    end
end

return {
    free = free,
    subst = subst,
    bind = bind,
    eq = expr_eq,
    str = expr_str,
}
