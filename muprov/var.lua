local function env_add(env, name, def)
    if env.global(name) then
        return nil, { err = "already_exists", name = name }
    end
    return { display = env.display, parse = env.parse, global = function(x) return x == name and def or env.global(x) end }
end

local function env_get(env, name)
    local x = env.global(name)
    if not x then
        return nil, { err = "var_not_found", var = name }
    end
    return x
end

local function params_add(params, name, p_type)
    return function(x)
        if type(x) == "number" then
            if x == 0 then
                return name, p_type
            else
                return params(x-1)
            end
        else
            if x == name then
                return 0, p_type
            else
                local idx, ty = params(x)
                if idx then
                    return idx+1, ty
                end
            end
        end
    end
end

local function suggest_name(type, params)
    if type.kind == "bound" then
        return params(type.index):sub(1,1):lower()
    elseif type.kind == "global" then
        return type.name:sub(1,1):lower()
    elseif type.kind == "elim" then
        return "e"
    elseif type.kind == "app" then
        return suggest_name(type.left, params)
    elseif type.kind == "forall" or type.kind == "fun" then
        return "f"
    elseif type.kind == "type" then
        return "t"
    else
        error(type.kind)
    end
end

local function choose_param_name(param, env, params)
    local hint = param.name
    if hint == "_" then
        hint = suggest_name(param.type, params)
    end

    if not (env.global(hint) or params(hint)) then
        return hint, params_add(params, hint, param.type)
    end

    local name
    local postfix = 1
    repeat
        name = ("%s_%d"):format(hint, postfix)
        postfix = postfix + 1
    until not (env.global(name) or params(name))

    return name, params_add(params, name, param.type)
end

return {
    env_add = env_add,
    env_get = env_get,
    params_add = params_add,
    choose_param_name = choose_param_name,
}
