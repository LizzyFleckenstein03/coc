local var = require("muprov.var")

-- constructors

local function free(name)
	return { kind = "free", name = name }
end

local function bound(index, type)
	return { kind = "bound", index = index, type = type }
end

local function global(name)
	return { kind = "global", name = name }
end

local function elim(kind, type)
	return { kind = "elim", elim_kind = kind, type = type,  }
end

local function app(a, b, ...)
    if b then
        return app({ kind = "app", left = a, right = b }, ...)
    else
        return a
    end
end

local function app_t(x, args)
	for _, a in ipairs(args) do
		x = { kind = "app", left = x, right = a }
	end
	return x
end

local function app_range(x, start, n)
    for i = start+n-1, start, -1 do
        x = { kind = "app", left = x, right = bound(i) }
    end
    return x
end

local function param(name, type)
	return { name = name, type = type }
end

local function fun(param_name, param_type, body, kind)
    return {
        kind = kind or "fun",
        param = { name = param_name, type = param_type },
        body = body,
    }
end

local function forall(param_name, param_type, body)
    return fun(param_name, param_type, body, "forall")
end

local function fun_t(params, body, kind)
    local x = body
    for i = #params, 1, -1 do
        x = {
            kind = kind or "fun",
            param = params[i],
            body = x
        }
    end
    return x
end

local function forall_t(params, body)
	return fun_t(params, body, "forall")
end

-- destructors

local function is_bound(x, index)
	return x.kind == "bound" and x.index == index
end

local function is_global(x, name)
	return x.kind == "global" and x.name == name
end

local function peel_app(x, args)
	while x.kind == "app" do
        table.insert(args, 1, x.right)
        x = x.left
	end
	return x
end

local function peel_fun(x, params, kind)
	while x.kind == (kind or "fun") do
		if params then table.insert(params, x.param) end
		x = x.body
	end
	return x
end

local function peel_forall(x, params)
	return peel_fun(x, params, "forall")
end

local function peel_fun_n(x, n, params, kind)
	for i = 1, n do
		assert(x.kind == (kind or "fun"))
		if params then table.insert(params, x.param) end
		x = x.body
	end
	return x
end

local function peel_forall_n(x, n, params)
	return peel_fun_n(x, n, params, "forall")
end

-- logic

local function used(x, var)
    local global = type(var) == "string"
    if x.kind == "bound" then
        return (not global and x.index == var) or (x.type and used(x.type, var))
    elseif x.kind == "global" then
        return global and x.name == var
    elseif x.kind == "elim" then
        return globla and x.type == var
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
                return lift(assert(subst(x.index - depth)), depth)
            end
        end
        return bound(index, x.type and lift(x.type, by, subst, depth))
    elseif x.kind == "global" then
        return x
    elseif x.kind == "elim" then
        return x
    elseif x.kind == "app" then
        return app(lift(x.left, by, subst, depth), lift(x.right, by, subst, depth))
    elseif x.kind == "fun" or x.kind == "forall" then
        return fun(x.param.name, lift(x.param.type, by, subst, depth),
            lift(x.body, by, subst, depth + 1), x.kind)
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
            return bound(index, lift(type, index+1))
        end
        local _, err = var.env_get(env, x.name) if err then return nil, err end
        return global(x.name)
    elseif x.kind == "bound" then
        if not x.type then
            local _, type = params(x.index)
            return bound(x.index, lift(type, x.index+1))
        end
        return x
    elseif x.kind == "global" then
        return x
    elseif x.kind == "elim" then
        local type, err = var.env_get(env, x.type) if err then return nil, err end
        if not type.elim then
            return nil, { err = "not_inductive", type = x.type }
        end
        return x
    elseif x.kind == "app" then
        local left, err = bind(x.left, env, params) if err then return nil, err end
        local right, err = bind(x.right, env, params) if err then return nil, err end
        return app(left, right)
    elseif x.kind == "fun" or x.kind == "forall" then
        local param_type, err = bind(x.param.type, env, params) if err then return nil, err end
        local body, err = bind(x.body, env, var.params_add(params, x.param.name, param_type)) if err then return nil, err end
        return fun(x.param.name, param_type, body, x.kind)
    elseif x.kind == "type" then
        return x
    elseif x.kind == "custom" then
        local x, err = env.parse(x) if err then return nil, err end
        return bind(x, env, params)
    else
        error(x.kind)
    end
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
    elseif a.kind == "elim" then
        return a.elim_kind == b.elim_kind and a.type == b.type
    elseif a.kind == "app" then
        return expr_eq(a.left, b.left, diff, depth) and expr_eq(a.right, b.right, diff, depth)
    elseif a.kind == "fun" or a.kind == "forall" then
        return (a.kind == "fun" or expr_eq(a.param.type, b.param.type, diff, depth))
            and expr_eq(a.body, b.body, diff, depth+1)
    elseif a.kind == "type" then
        return true
    else
        error(a.kind)
    end
end

local function expr_str(x, env, params, indices)
    params = params or function() end

    local disp = env.display(x, env, params, indices)
    if disp then
        return disp
    end

    if x.kind == "bound" then
        return indices and "#"..x.index or assert(params(x.index))
    elseif x.kind == "global" then
        return x.name
    elseif x.kind == "elim" then
        return ("(%s %s)"):format(x.elim_kind, x.type)
    elseif x.kind == "app" then
        local values = {}

        while x.kind == "app" do
            table.insert(values, 1, expr_str(x.right, env, params, indices))
            x = x.left
        end

        if x.kind == "elim" then
            table.insert(values, 1, x.type)
            table.insert(values, 1, x.elim_kind)
        else
            table.insert(values, 1, expr_str(x, env, params, indices))
        end

        return ("(%s)"):format(table.concat(values, " "))
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
            type_str = expr_str(type, env, params, indices)
            param_name, params = var.choose_param_name(right.param, env, params)

            table.insert(names, anon and type_str or param_name)

            right = right.body
        end
        commit_names()

        if anon then
            table.insert(names, expr_str(right, env, params, indices))
            return ("(%s)"):format(table.concat(names, " -> "))
        else
            if #left > 1 then
                for i, v in ipairs(left) do
                    left[i] = ("(%s)"):format(v)
                end
            end
            return ("(%s %s%s%s)"):format(x.kind, table.concat(left, " "),
                x.kind == "fun" and " => " or ", ", expr_str(right, env, params, indices))
        end
    elseif x.kind == "type" then
        return "type"
    else
        error(x.kind)
    end
end

local function axioms(x, t, env)
    if x.kind == "bound" or x.kind == "elim" or x.kind == "type" then
        -- no-op
    elseif x.kind == "global" then
        local def = env.global(x.name)
        if def.val then
            axioms(def.val, t, env)
        elseif not def.elim and not def.ctor then
            table.insert(t, def)
        end
        axioms(def.type, t, env)
    elseif x.kind == "app" then
        axioms(x.left, t, env)
        axioms(x.right, t, env)
    elseif x.kind == "fun" or x.kind == "forall" then
        axioms(x.param.type, t, env)
        axioms(x.body, t, env)
    else
        error(x.kind)
    end
end

return {
    free = free,
    bound = bound,
    global = global,
    elim = elim,
    app = app,
    app_t = app_t,
    app_range = app_range,
    param = param,
    fun = fun,
    forall = forall,
    fun_t = fun_t,
    forall_t = forall_t,
    type = { kind = "type" },

    is_bound = is_bound,
    is_global = is_global,
    peel_app = peel_app,
    peel_fun = peel_fun,
    peel_forall = peel_forall,
    peel_fun_n = peel_fun_n,
    peel_forall_n = peel_forall_n,

    used = used,
    lift = lift,
    bind = bind,
    eq = expr_eq,
    str = expr_str,
    axioms = axioms,
}
