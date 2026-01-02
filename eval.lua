local expr = require("expr")

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
        local def = env(x.name)
        local val
        if def.val and not typeck then
            local reduced_val, err = expect("definition", reduce(def.val, env, typeck)) if err then return nil, err end
            val = reduced_val.val
        end
        return { type = def.type, val = val or x }
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

        if typeck or left.val.kind ~= "fun" then
            local out_type = expr.lift(left_type.val.body, -1, function(n) return n == 0 and right.val end)
            return { type = out_type, val = { kind = "app", left = left.val, right = right.val } }
        end

        local joint = expr.lift(left.val.body, -1, function(n) return n == 0 and right.val end)
        return expect("application", reduce(joint, env, false))
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

local function reduce_check(x, env, want_type, typeck)
    local bound, err = expr.bind(x, env) if err then return nil, err end
    local obj, err = reduce(bound, env, typeck) if err then return nil, err end

    if not want_type then
        return obj
    end

    local type, err = reduce_check(obj.type, env) if err then return nil, err end
    local want_type_r, err = reduce_check(want_type, env) if err then return nil, err end
    local _, err = type_match(want_type_r.val, { val = bound, type = type.val }) if err then return nil, err end

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
