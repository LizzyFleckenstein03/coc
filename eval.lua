local expr = require("expr")
local iota = require("iota")

local function type_match(type, x)
    if not expr.eq(type, x.type) then
        return nil, { err = "type_mismatch", type = type, expr = x }
    end
end

local function expect(loc, val, err)
    if err then
        return nil, { err = "location", location = loc, inner = err }
    end
    return val
end

local reduce
local function reduce_throw(x, env, typeck)
    if x.kind == "bound" then
        return { type = x.type, val = x }
    elseif x.kind == "global" then
        local def = env.global(x.name)
        if def.val and not typeck then
            return expect("definition", reduce(def.val, env, typeck))
        end
        return { type = def.type, val = x }
    elseif x.kind == "elim" then
        local elim = env.global(x.type).elim[x.elim_kind]
        return { type = elim.type, elim_depth = elim.params, val = x }
    elseif x.kind == "app" then
        local left, err = expect("left", reduce(x.left, env, typeck)) if err then return nil, err end
        local right, err = expect("right", reduce(x.right, env, typeck)) if err then return nil, err end

        local left_type, err = expect("left type", reduce(left.type, env, false)) if err then return nil, err end
        local right_type, err = expect("right type", reduce(right.type, env, false)) if err then return nil, err end

        if left_type.val.kind ~= "forall" then
            return expect("left type", nil, { err = "not_function", expr = { val = left.val, type = left_type.val } })
        end

        local param_type, err = expect("param type", reduce(left_type.val.param.type, env, false)) if err then return nil, err end

        local _, err = expect("right type", type_match(param_type.val, { val = right.val, type = right_type.val })) if err then return nil, err end

        -- try beta
        if left.val.kind == "fun" and not typeck then
            local joint = expr.lift(left.val.body, -1, function(n) return n == 0 and right.val end)
            return expect("application", reduce(joint, env, false))
        end

        local joint = { kind = "app", left = left.val, right = right.val }
        local elim_depth = left.elim_depth and (left.elim_depth - 1)

        -- try iota
        if elim_depth == 0 and not typeck then
            local elim, reduced = iota.reduce(joint, env)
            if reduced then
                return expect("eliminated", reduce(elim, env, false))
            end
        end

        local out_type = expr.lift(left_type.val.body, -1, function(n) return n == 0 and right.val end)
        return { type = out_type, elim_depth = elim_depth, val = joint }
    elseif x.kind == "fun" or x.kind == "forall" then
        local param_type, err = expect("param type", reduce(x.param.type, env, typeck)) if err then return nil, err end
        local _, err = expect("param type", type_match({ kind = "type" }, param_type)) if err then return nil, err end
        local param = { name = x.param.name, type = param_type.val }

        local body, err = expect("body", reduce(x.body, env, typeck)) if err then return nil, err end

        if x.kind == "forall" then
            local body_type, err = expect("body type", reduce(body.type, env, false)) if err then return nil, err end
            local _, err = expect("body type", type_match({ kind = "type" }, { type = body_type.val, val = body.val })) if err then return nil, err end
            body.type = body_type.val
        end

        return {
            type = x.kind == "fun" and { kind = "forall", param = param, body = body.type } or { kind = "type" },
            val = { kind = x.kind, param = param, body = body.val }
        }
    elseif x.kind == "type" then
        return { type = x, val = x }
    else
        error(x.kind)
    end
end

reduce = function(x, env, typeck)
    local val, err = reduce_throw(x, env, typeck)
    if err then
        return nil, { err = "reduce", action = typeck and "typeck" or "reduce", expr = x, inner = err }
    end
    return val
end

local function expect_env(env, val, err)
    if err then
        return nil, { err = "env", env = env, inner = err }
    end
    return val
end

local function reduce_check(x, env, want_type, typeck)
    local bound, err = expr.bind(x, env) if err then return nil, err end
    local obj, err = expect_env(env, reduce(bound, env, typeck)) if err then return nil, err end

    if not want_type then
        return obj
    end

    local type, err = expect_env(env, reduce(obj.type, env)) if err then return nil, err end
    local want_type_r, err = reduce_check(want_type, env) if err then return nil, err end
    local _, err = expect_env(env, type_match(want_type_r.val, { val = bound, type = type.val })) if err then return nil, err end

    return { val = obj.val, type = expr.bind(want_type, env) }
end

local function typeck(x, env, want_type)
    local obj, err = reduce_check(x, env, want_type, true) if err then return nil, err end
    return obj.type
end

return {
    reduce = reduce_check,
    typeck = typeck,
}
