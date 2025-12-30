local expr = require("expr")

local function type_match(type, x)
    if not expr.eq(x.type, type) then
        return nil, { err = "type_mismatch", type = type, expr = x }
    end
end

local function expect(where, val, err)
    if err then
        return nil, { err = "where", where = where, inner = err }
    end
    return val
end

local function wrap_result(reduce)
    return function(x, env, typeck)
        local val, err = reduce(x, env, typeck)
        if err then
            return nil, { err = "what", action = typeck and "typeck" or "reduce", expr = x, inner = err }
        end
        return val
    end
end

local reduce
reduce = wrap_result(function(x, env, typeck)
    if x.kind == "type" then
        return { type = x, val = x }
    elseif x.kind == "var" then
        if not x.type then
            return nil, { err = "var_not_found", var = x.name }
        end
        local val
        if not typeck and x.ref then
            val = env[x.ref].val
            if val then
                local redval, err = expect("definition", reduce(val, env, typeck)) if err then return nil, err end
                val = redval.val
            end
        end
        return { type = x.type, val = val or x }
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
            local out_type = expr.subst(left_type.val.body, left_type.val.param.name, right.val)
            return { type = out_type, val = { kind = "app", left = left.val, right = right.val } }
        end

        local joint = expr.subst(left.val.body, left.val.param.name, right.val)
        return expect("application", reduce(joint, env, false))
    elseif x.kind == "fun" or x.kind == "forall" then
        local param_type, err = expect("param type", reduce(x.param.type, env, kind == "fun" or typeck)) if err then return nil, err end
        local _, err = expect("param type", type_match({ kind = "type" }, param_type)) if err then return nil, err end
        local param = { name = x.param.name, type = param_type.val }

        local body = expr.subst(x.body, x.param.name, { kind = "var", name = param.name, type = param.type })
        local body, err = expect("body", reduce(body, env, typeck)) if err then return nil, err end

        if x.kind == "forall" then
            local body_type, err = expect("body type", reduce(body.type, env, false)) if err then return nil, err end
            local _, err = expect("body type", type_match({ kind = "type" }, { type = body_type.val, val = body.val })) if err then return nil, err end
            body.type = body_type.val
        end

        return {
            type = x.kind == "fun" and { kind = "forall", param = param, body = body.type } or { kind = "type" },
            val = { kind = x.kind, param = param, body = body.val }
        }
    end
end)

local function do_reduce(x, env, typeck)
    return reduce(expr.bind(x, env), env, typeck)
end

local function typeck(x, env)
    local obj, err = do_reduce(x, env, true) if err then return nil, err end
    return obj.type
end

return {
    reduce = do_reduce,
    typeck = typeck,
    type_match = type_match,
}
