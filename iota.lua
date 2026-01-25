local expr = require("expr")

local reduce

local function recursive_call(val, type, elim, cases, base, env, depth)
    local params = {}
    local type_args = {}
    local peeled_type = expr.peel_app(expr.peel_forall(type, params), type_args)

    if not expr.is_global(peeled_type, elim.name) then
        return
    end

    local inner_args = {}
    for j = 1, elim.inner_params do
        table.insert(inner_args, type_args[elim.outer_params+j])
    end

    local result = expr.lift(val, #params)
    result = expr.app_range(result, 0, #params)
    result = reduce(result, elim, cases, base, inner_args, env, depth + #params)
    result = expr.fun_t(params, result)
    return result
end

reduce = function(val, elim, cases, base, inner_args, env, depth)
    local args = {}
    local ctor = expr.peel_app(val, args)

    local def = ctor.kind == "global" and env.global(ctor.name).ctor
    if not def then
        return expr.app(expr.app_t(expr.lift(base, depth), inner_args), val), false
    end

    local result = expr.lift(cases[def.case], depth)
    local type = def.reduced_type

    local rec_args = {}

    for i, ar in ipairs(args) do
        -- assert(type.kind == "forall")
        local param = type.param
        type = expr.lift(type.body, -1, function(n) if n == 0 then return ar end end)

        if i > elim.outer_params then
            result = expr.app(result, ar)

            if elim.recursion then
                local rec = recursive_call(ar, param.type, elim, cases, base, env, depth)
                if rec then
                    table.insert(rec_args, rec)
                end
            end
        end
    end

    return expr.app_t(result, rec_args), true
end

local function reduce_expr(x, env)
    local args = {}
    local base = expr.peel_app(x, args)
    local elim = env.global(base.type).elim[base.elim_kind]

    local val = table.remove(args)
    local inner_args = {}
    for i = 1, elim.inner_params do
        table.insert(inner_args, 1, table.remove(args))
    end
    local cases = {}
    for i = 1, elim.cases do
        table.insert(cases, 1, args[#args-i+1])
    end

    return reduce(val, elim, cases, expr.app_t(base, args), inner_args, env, 0)
end

return {
    reduce = reduce_expr
}
