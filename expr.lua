local function used(x, var)
    local global = type(var) == "string"
    if x.kind == "bound" then
        return (not global and x.index == var) or used(x.type, var)
    elseif x.kind == "global" then
        return global and x.name == var
    elseif x.kind == "app" then
        return used(x.right, var) or used(x.left, var)
    elseif x.kind == "fun" or x.kind == "forall" then
        return used(x.param.type, var) or used(x.body, global and var or (var + 1))
    elseif x.kind == "type" then
        return false
    else
        error(x.kind)
    end
end

local function lift(x, by, subst, depth)
    if by == 0 then return x end
    depth = depth or 0
    if x.kind == "bound" then
        local index = x.index
        if index >= depth then
            index = index + by
            if index < depth then
                local subst_arg = x.index - depth
                return lift(
                    assert(subst(subst_arg)),
                    index + 1,
                    function(n) return subst(n+subst_arg+1) end)
            end
        end
        return { kind = "bound", index = index, type = lift(x.type, by, subst, depth) }
    elseif x.kind == "global" then
        return x
    elseif x.kind == "app" then
        return { kind = "app", left = lift(x.left, by, subst, depth), right = lift(x.right, by, subst, depth) }
    elseif x.kind == "fun" or x.kind == "forall" then
        return {
            kind = x.kind,
            param = { name = x.param.name, type = lift(x.param.type, by, subst, depth) },
            body = lift(x.body, by, subst, depth + 1)
        }
    elseif x.kind == "type" then
        return x
    else
        error(x.kind)
    end
end

local function bind(x, env, params)
    params = params or function() end
    if x.kind == "free" then
        local index, type = params(x.name)
        if index then
            return { kind = "bound", index = index, type = lift(type, index+1) }
        elseif env(x.name) then
            return { kind = "global", name = x.name }
        else
            return nil, { err = "var_not_found", var = x.name }
        end
    -- convenience: allow re-binding
    elseif x.kind == "bound" or x.kind == "global" then
        return x
    elseif x.kind == "app" then
        local left, err = bind(x.left, env, params) if err then return nil, err end
        local right, err = bind(x.right, env, params) if err then return nil, err end
        return { kind = "app", left = left, right = right }
    elseif x.kind == "fun" or x.kind == "forall" then
        local param_type, err = bind(x.param.type, env, params) if err then return nil, err end
        local body, err = bind(x.body, env, function(name)
            if name == x.param.name then
                return 0, param_type
            end
            local index, type = params(name)
            if index then
                return index+1, type
            end
        end) if err then return nil, err end

        return {
            kind = x.kind,
            param = { name = x.param.name, type = param_type },
            body = body,
        }
    elseif x.kind == "type" then
        return x
    else
        error(x.kind)
    end
end

local function params_add(params, name)
    return function(x)
        if type(x) == "number" then
            return x == 0 and name or params(x-1)
        else
            if x == name then
                return 0
            end
            local p = params(x)
            return p and (p+1)
        end
    end
end

local function choose_param_name(hint, env, params)
    if not (env(hint) or params(hint)) then
        return hint, params_add(params, hint)
    end

    local name
    local postfix = 1
    repeat
        name = ("%s_%d"):format(hint, postfix)
        postfix = postfix + 1
    until not (env(name) or params(name))

    return name, params_add(params, name)
end

-- diff: how much deeper is b compared to a
-- visually: [any x shared] [diff x only_b] [depth x shared]
local function expr_eq(a, b, diff, depth)
    if a.kind ~= b.kind then return false end
    diff = diff or 0
    depth = depth or 0

    if a.kind == "bound" then
        if b.index + depth < diff then
            return false
        end
        return a.index == b.index - diff
    elseif a.kind == "global" then
        return a.name == b.name
    elseif a.kind == "app" then
        return expr_eq(a.left, b.left, diff, depth) and expr_eq(a.right, b.right, diff, depth)
    elseif a.kind == "fun" or a.kind == "forall" then
        return expr_eq(a.param.type, b.param.type, diff, depth) and expr_eq(a.body, b.body, diff, depth+1)
    elseif a.kind == "type" then
        return true
    else
        error(a.kind)
    end
end

local function expr_str(x, env, params)
    params = params or function() end
    if x.kind == "bound" then
        return assert(params(x.index))
    elseif x.kind == "global" then
        return x.name
    elseif x.kind == "app" then
        local right = {}
        local left = x

        while left.kind == "app" do
            table.insert(right, 1, expr_str(left.right, env, params))
            left = left.left
        end

        return ("(%s %s)"):format(expr_str(left, env, params), table.concat(right, " "))
    elseif x.kind == "fun" or x.kind == "forall" then
        local left = {}
        local right = x

        local type, type_str
        local names = {}
        local anon
        local function commit_names()
            if not anon and #names > 0 then
                table.insert(left, ("%s : %s"):format(
                    table.concat(names, " "), type_str))
                names = {}
            end
        end

        while right.kind == x.kind do
            local want_anon = right.kind == "forall" and not used(right.body, 0)
            if anon ~= nil and anon ~= want_anon then
                break
            end
            anon = want_anon

            if type ~= nil and not expr_eq(type, right.param.type, 1) then
                commit_names()
            end

            local param_name
            type = right.param.type
            type_str = expr_str(type, env, params)
            param_name, params = choose_param_name(right.param.name, env, params)

            table.insert(names, anon and type_str or param_name)

            right = right.body
        end
        commit_names()

        if anon then
            table.insert(names, expr_str(right, env, params))
            return ("(%s)"):format(table.concat(names, " -> "))
        else
            if #left > 1 then
                for i, v in ipairs(left) do
                    left[i] = ("(%s)"):format(v)
                end
            end
            return ("(%s %s%s%s)"):format(x.kind, table.concat(left, " "),
                x.kind == "fun" and " => " or ", ", expr_str(right, env, params))
        end
    elseif x.kind == "type" then
        return "type"
    else
        error(x.kind)
    end
end

local function fun(kind, params, body)
    local x = body
    for i = #params, 1, -1 do
        x = {
            kind = kind,
            param = params[i],
            body = x
        }
    end
    return x
end

local function env_add(env, name, def)
    if env(name) then
        return nil, { err = "already_exists", name = name }
    end
    return function(x) return x == name and def or env(x) end
end

return {
    used = used,
    lift = lift,
    bind = bind,
    choose_param_name = choose_param_name,
    eq = expr_eq,
    str = expr_str,
    fun = fun,
    env_add = env_add,
}
