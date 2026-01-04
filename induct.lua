local expr = require("expr")
local eval = require("eval")

local function expect(loc, val, err)
    if err then
        return nil, { err = "location", location = loc, inner = err }
    end
    return val
end

local function apply_args(x, start, n)
    for i = start+n-1, start, -1 do
        x = { kind = "app", left = x, right = { kind = "bound", index = i } }
    end
    return x
end

local function process_type_args(args, desc, outer_args, x)
    for i = 1, #desc.params.outer do
        local outer_arg = outer_args + #desc.params.outer-i
        if args[i].kind ~= "bound" or args[i].index ~= outer_arg then
            return nil, { err = "outer_param_mismatch" }
        end
    end

    for i = 1, #desc.params.inner do
        x = { kind = "app", left = x, right = args[#desc.params.outer+i] }
    end

    return x
end

local function underscore(prefix, x)
    if x == "_" then
        return prefix
    else
        return prefix.."_"..x
    end
end

local function ctor_param(type, desc, ret_type, outer_args, rec_param)
    if not expr.used(type, desc.name) then
        return
    end

    type = expr.lift(type, rec_param+1)

    local params = {}
    while type.kind == "forall" do
        if expr.used(type.param.type, desc.name) then
            return nil, { err = "not_positive", name = desc.name }
        end
        table.insert(params, type.param)
        type = type.body
    end

    ret_type = ret_type + #params
    outer_args = outer_args + #params

    local args = {}
    while type.kind == "app" do
        if expr.used(type.right, desc.name) then
            return nil, { err = "not_positive", name = desc.name }
        end
        table.insert(args, 1, type.right)
        type = type.left
    end

    -- this can't happen currently, just double check
    if type.kind ~= "global" or type.name ~= desc.name then
        return
    end

    -- assert(#args == #desc.params.outer + #desc.params.inner)

    for i = 1, #desc.params.outer do
        local outer_arg = outer_args + #desc.params.outer-i
        if args[i].kind ~= "bound" or args[i].index ~= outer_arg then
            return nil, { err = "outer_param_mismatch" }
        end
    end

    local ret_rec = { kind = "bound", index = ret_type }
    local ret_ind, err = process_type_args(args, desc, outer_args, ret_rec) if err then return nil, err end
    ret_ind = { kind = "app", left = ret_ind,
        right = apply_args({ kind = "bound", index = rec_param }, 0, #params) }

    return {
        rec = expr.fun("forall", params, ret_rec),
        ind = expr.fun("forall", params, ret_ind)
    }
end

local function define_ctor(ctor, num, desc, elim_params, env)
    local wrapped_type = expr.fun("forall", desc.params.outer, ctor.type)
    local reduced_type, err = expect("constructor signature", eval.reduce(wrapped_type, env, { kind = "type" })) if err then return nil, err end

    local ret_type = (num-1)
    local outer_args = ret_type+1

    local unwrapped_type = reduced_type.val
    for i = 1, #desc.params.outer do
        -- assert(unwrapped_type.kind == "forall")
        unwrapped_type = unwrapped_type.body
    end
    unwrapped_type = expr.lift(unwrapped_type, outer_args)

    local type = unwrapped_type
    local params = {}
    while type.kind == "forall" do
        table.insert(params, type.param)
        type = type.body
    end

    local params_rec = {}
    local params_ind = {}
    for i, param in ipairs(params) do
        local offset = #params+#params_rec
        local rec, ind, err = ctor_param(
            param.type,
            desc,
            ret_type+offset,
            outer_args+offset,
            offset-i
        )
        if rec then
            table.insert(params_rec, { name = underscore("rec", param.name), type = rec.rec })
            table.insert(params_ind, { name = underscore("IH", param.name), type = rec.ind })
        end
    end

    table.insert(elim_params.elim, { name = "case_"..ctor.name, type =
        expr.fun("forall", params, { kind = "bound", index = ret_type + #params })
    })
    table.insert(elim_params.rec, { name = "case_"..ctor.name, type =
        expr.fun("forall", params, expr.fun("forall", params_rec,
            { kind = "bound", index = ret_type + #params+#params_rec }))
    })

    type = expr.lift(type, #params_ind)
    local args = {}
    while type.kind == "app" do
        table.insert(args, 1, type.right)
        type = type.left
    end

    if type.kind ~= "global" or type.name ~= desc.name then
        return nil, { err = "constructor_type_mismatch" }
    end

    outer_args = outer_args + #params + #params_ind
    ret_type = ret_type + #params + #params_ind

    local ctor_call = apply_args(
        apply_args({ kind = "global", name = ctor.name }, outer_args, #desc.params.outer),
        #params_ind, #params)

    local ind_hypot, err = process_type_args(args, desc, outer_args, { kind = "bound", index = ret_type }) if err then return nil, err end

    local ind_ret = { kind = "app", left = ind_hypot, right = ctor_call }

    table.insert(elim_params.ind, { name = "case_"..ctor.name, type =
        expr.fun("forall", params, expr.fun("forall", params_ind, ind_ret))
    })

    return {
        name = ctor.name,
        type = expr.bind(wrapped_type, env),
        ctor = {
            case = num,
            reduced_type = reduced_type.val,
        },
    }
end

local function define_type_throw(desc, env)
    local params = {}
    for _, outer in ipairs(desc.params.outer) do
        table.insert(params, outer)
    end
    for _, inner in ipairs(desc.params.inner) do
        table.insert(params, inner)
    end

    local type_type = expr.fun("forall", params, { kind = "type" })
    local _, err = expect("type signature", eval.typeck(type_type, env, { kind = "type" })) if err then return nil, err end
    local type_def = {
        name = desc.name,
        type = expr.bind(type_type, env),
    }
    local env, err = expr.env_add(env, type_def.name, type_def) if err then return nil, err end
    local ind_type = { kind = "global", name = desc.name }

    local elim_params = {elim = {}, rec = {}, ind = {}}

    for elim_kind, elim_p in pairs(elim_params) do
        for _, outer in ipairs(desc.params.outer) do
            table.insert(elim_p, outer)
        end
        table.insert(elim_p, {
            name = "R",
            type = elim_kind == "ind"
                and expr.fun("forall", desc.params.inner, {
                    kind = "forall",
                    param = {
                        name = "_",
                        type = apply_args(ind_type, 0, #params),
                    },
                    body = { kind = "type" }
                })
                or { kind = "type" }
        })
    end

    local ctors = {}
    local ctor_env = env
    for num, ctor in ipairs(desc.ctors) do
        local def, err = expect("constructor "..ctor.name,
            define_ctor(ctor, num, desc, elim_params, ctor_env)) if err then return nil, err end
        env, err = expr.env_add(env, def.name, def) if err then return nil, err end
        table.insert(ctors, def)
    end

    local elim = {}
    for elim_kind, elim_p in pairs(elim_params) do
        for _, inner in ipairs(desc.params.inner) do
            table.insert(elim_p, inner)
        end
        table.insert(elim_p, { name = "_", type = apply_args(
            apply_args(ind_type, #desc.params.inner+#desc.ctors+1, #desc.params.outer),
            0, #desc.params.inner
        )})

        local ret_type = { kind = "bound", index = 1+#desc.params.inner+#desc.ctors }
        if elim_kind == "ind" then
            ret_type = apply_args(ret_type, 0, 1+#desc.params.inner)
        end

        local elim_type = expr.fun("forall", elim_p, ret_type)
        local _, err = expect(elim_kind.." type", eval.typeck(elim_type, env, { kind = "type" })) if err then return nil, err end

        elim[elim_kind] = {
            name = desc.name,
            cases = #desc.ctors,
            inner_params = #desc.params.inner,
            outer_params = #desc.params.outer,
            params = #elim_p,
            recursion = elim_kind ~= "elim",
            type = expr.bind(elim_type, env),
        }
    end
    type_def.elim = elim

    return {
        type = type_def,
        ctors = ctors,
    }
end

local function define_type(desc, env)
    return expect("inductive " .. desc.name, define_type_throw(desc, env))
end

return {
    define_type = define_type,
}
