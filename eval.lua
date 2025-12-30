local expr = require("expr")

local function type_match(type, x)
    if not expr.eq(x.type, type) then
        return nil, { err = "type_mismatch", type = type, expr = x }
    end
end

local function run(f)
    local function wrap(parent_x)
        return function(f, context)
            return function(x, env, typeck)
                local val, err = f(wrap(x), x, env, typeck)
                if err and parent_x then
                    return nil, { err = "in", inner = err, where = { expr = parent_x, context = context, typeck = typeck } }
                end
                return val, err
            end
        end
    end

    return function(x, env, typeck)
        return wrap(x)(f)(x, env, typeck)
    end
end

-- TODO: re-design error handling: just use wrap, it adds an error
local function reduce(wrap, x, env, typeck)
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
                local redval, err = wrap(reduce, "def")(val, env, typeck) if err then return nil, err end
                val = redval.val
            end
        end
        return { type = x.type, val = val or x }
    elseif x.kind == "app" then
        local left, err = wrap(reduce, "left")(x.left, env, typeck) if err then return nil, err end
        local right, err = wrap(reduce, "right")(x.right, env, typeck) if err then return nil, err end

        local left_type, err = wrap(reduce, "left type")(left.type, env, false) if err then return nil, err end
        local right_type, err = wrap(reduce, "right type")(right.type, env, false) if err then return nil, err end

        if left_type.val.kind ~= "forall" then
            return nil, { err = "not_function", expr = { val = left.val, type = left_type.val } }
        end

        local param_type, err = wrap(reduce, "param type")(left_type.val.param.type, env, false) if err then return nil, err end

        local _, err = type_match(param_type.val, { val = right.val, type = right_type.val }) if err then return nil, err end

        if typeck or left.val.kind ~= "fun" then
            local out_type = expr.subst(left_type.val.body, left_type.val.param.name, right.val)
            return { type = out_type, val = { kind = "app", left = left.val, right = right.val } }
        end

        local joint = expr.subst(left.val.body, left.val.param.name, right.val)
        return wrap(reduce, "joint")(joint, env, false)
    elseif x.kind == "fun" or x.kind == "forall" then
        local param_type, err = wrap(reduce, "param type")(x.param.type, env, kind == "fun" or typeck) if err then return nil, err end
        local _, err = type_match({ kind = "type" }, param_type) if err then return nil, err end
        local param = { name = x.param.name, type = param_type.val }

        local body = expr.subst(x.body, x.param.name, { kind = "var", name = param.name, type = param.type })
        local body, err = wrap(reduce, "body")(body, env, typeck) if err then return nil, err end

        return {
            type = x.kind == "fun" and { kind = "forall", param = param, body = body.type } or { kind = "type" },
            val = { kind = x.kind, param = param, body = body.val }
        }
    end
end

local function eval_reduce(x, env, typeck)
    return run(reduce)(expr.bind(x, env), env, typeck)
end

local function typeck(x, env)
    local obj, err = eval(x, env, true) if err then return nil, err end
    return obj.type
end

return {
    reduce = eval_reduce,
    typeck = typeck,
    type_match = type_match,
}
