local expr = require("muprov.expr")
local iota = require("muprov.iota")
local expect = require("muprov.util").expect
local app, fun, forall = expr.app, expr.fun, expr.forall

local reduce

-- reduce until function / weak head normal form
local function reduce_wh(x, env)
    if x.kind == "bound" or x.kind == "fun" or x.kind == "forall" or x.kind == "type" then
        return x
    elseif x.kind == "global" then
        local val = env.global(x.name).val
        if val then
            return reduce_wh(val, env)
        end
        return x
    elseif x.kind == "elim" then
        local elim = env.global(x.type).elim[x.elim_kind]
        return x, elim.params
    elseif x.kind == "app" then
        local left, elim_depth = reduce_wh(x.left, env)

        if left.kind == "fun" then
            local lifted = expr.lift(left.body, -1, function(n) return n == 0 and x.right end)
            return reduce_wh(lifted, env)
        end

        elim_depth = elim_depth and (elim_depth-1)

        if elim_depth == 0 then
            local joint = app(left, reduce(x.right, env, true))
            local elim, reduced = iota.reduce(joint, env)
            if reduced then
                return reduce_wh(elim, env)
            end
            return joint
        end

        return app(left, x.right), elim_depth
    else
        error(x.kind)
    end
end

-- like reduce_weak_head, plus:
-- both sides of app are reduced
-- if not nofuncs, the inside of function bodies is reduced
reduce = function(x, env, nofuncs)
    local function recurse(x)
        if x.kind == "app" then
            return app(recurse(x.left), recurse(reduce_wh(x.right, env)))
        elseif not nofuncs and (x.kind == "fun" or x.kind == "forall") then
            local body = recurse(reduce_wh(x.body, env))
            local ptype = x.kind == "forall" and recurse(reduce_wh(x.param.type, env)) or x.param.type
            return fun(x.param.name, ptype, body, x.kind)
        else
            return x
        end
    end

    return recurse(reduce_wh(x, env))
end

local typeck

local function typematch(expect, type, val, env)
    expect = reduce(expect, env)
    type = reduce(type, env)
    if not expr.eq(expect, type) then
        return nil, { err = "type_mismatch", type = expect, expr = { val = val, type = type } }
    end
end

local function typeck_throw(x, env)
    if x.kind == "bound" then
        return x.type
    elseif x.kind == "global" then
        return env.global(x.name).type
    elseif x.kind == "elim" then
        return env.global(x.type).elim[x.elim_kind].type
    elseif x.kind == "app" then
        local left, err = expect("left", typeck(x.left, env)) if err then return nil, err end
        local right, err = expect("right", typeck(x.right, env)) if err then return nil, err end
        left = reduce_wh(left, env)

        if left.kind ~= "forall" then
            return expect("left", nil, { err = "not_function", expr = { val = x.left, type = left } })
        end

        local _, err = expect("right", typematch(left.param.type, right, x.right, env)) if err then return nil, err end

        return expr.lift(left.body, -1, function(n) return n == 0 and x.right end)
    elseif x.kind == "fun" or x.kind == "forall" then
        local param = expect("param", typeck(x.param.type, env))
        local _, err = typematch(expr.type, param, x.param.type, env) if err then return nil, err end

        local body, err = expect("body", typeck(x.body, env)) if err then return nil, err end
        if x.kind == "forall" then
            local _, err = expect("body", typematch(expr.type, body, x.body, env)) if err then return nil, err end
            return expr.type
        end

        return forall(x.param.name, x.param.type, body)
    elseif x.kind == "type" then
        return x
    else
        error(x.kind)
    end
end

typeck = function(x, env)
    local val, err = typeck_throw(x, env)
    if err then
        return nil, { err = "reduce", action = "typeck", expr = x, inner = err }
    end
    return val
end

local function expect_env(env, val, err)
    if err then
        return nil, { err = "env", env = env, inner = err }
    end
    return val
end

local function bind_check(x, env)
    local bound, err = expr.bind(x, env) if err then return nil, err end
    local type, err = expect_env(env, typeck(bound, env)) if err then return nil, err end

    return type, nil, bound
end

local function safe_typeck(x, env, want_type)
    local type, err, bound = bind_check(x, env) if err then return nil, err end
    if not want_type then
        return type, nil, bound
    end

    local _, err, want = bind_check(want_type, env) if err then return nil, err end
    local _, err = expect_env(env, typematch(want, type, bound, env)) if err then return nil, err end

    return want, nil, bound
end

local function safe_reduce(x, env, want_type, typeck_only)
    local type, err, bound = safe_typeck(x, env, want_type) if err then return nil, err end
    return { val = typeck_only and x or reduce(bound, env), type = type }
end

return {
    typeck = safe_typeck,
    reduce = safe_reduce,
}
