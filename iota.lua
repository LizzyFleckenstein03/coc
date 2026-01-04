local expr = require("expr")

local reduce

local function recursive_call(val, type, elim, cases, base, env, depth)
    local params = {}
    while type.kind == "forall" do
        table.insert(params, type.param)
        type = type.body
    end

    local type_args = {}
    while type.kind == "app" do
        table.insert(type_args, 1, type.right)
        type = type.left
    end

    if type.kind ~= "global" or type.name ~= elim.name then
        return
    end

    local inner_args = {}
    for j = 1, elim.inner_params do
        table.insert(inner_args, type_args[elim.outer_params+j])
    end

    local result = expr.lift(val, #params)
    for _, param in ipairs(params) do
        result = { kind = "app", left = result, right = param.name }
    end

    result = reduce(result, elim, cases, base, inner_args, env, depth + #params)
    result = expr.fun("fun", params, result)
    return result
end

reduce = function(val, elim, cases, base, inner_args, env, depth)
    local args = {}

    local ctor = val
    while ctor.kind == "app" do
        table.insert(args, 1, ctor.right)
        ctor = ctor.left
    end

    local def = ctor.kind == "global" and env(ctor.name).ctor
    if not def then
        local result = expr.lift(base, depth)
        for _, inner in ipairs(inner_args) do
            result = { kind = "app", left = result, right = inner }
        end
        return { kind = "app", left = result, right = val }, false
    end

    local result = expr.lift(cases[def.case], depth)
    local type = def.reduced_type

    local rec_args = {}

    for i, ar in ipairs(args) do
        -- assert(type.kind == "forall")
        local param = type.param
        type = expr.lift(type.body, -1, function(n) if n == 0 then return param.type end end)

        if i > elim.outer_params then
            result = { kind = "app", left = result, right = ar }

            if elim.recursion then
                local rec = recursive_call(ar, param.type, elim, cases, base, env, depth)
                if rec then
                    table.insert(rec_args, rec)
                end
            end
        end
    end

    for _, ar in ipairs(rec_args) do
        result = { kind = "app", left = result, right = ar }
    end

    return result, true
end

local function reduce_expr(x, env)
    local args = {}
    while x.kind == "app" do
        table.insert(args, 1, x.right)
        x = x.left
    end

    local elim = env(x.type).elim[x.elim_kind]

    local val = table.remove(args)
    local inner_args = {}
    for i = 1, elim.inner_params do
        table.insert(inner_args, 1, table.remove(args))
    end

    local base = x
    for _, ar in ipairs(args) do
        base = { kind = "app", left = base, right = ar }
    end

    local cases = {}
    for i = 1, elim.cases do
        table.insert(cases, 1, args[#args-i+1])
    end

    return reduce(val, elim, cases, base, inner_args, env, 0)
end

return {
    reduce = reduce_expr
}
