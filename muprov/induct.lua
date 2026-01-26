local expr = require("muprov.expr")
local eval = require("muprov.eval")
local util = require("muprov.util")
local var = require("muprov.var")

local function process_type_args(args, desc, outer_args, x)
    for i = 1, #desc.params.outer do
    	local outer_arg = outer_args + #desc.params.outer-i
        if not expr.is_bound(args[i], outer_arg) then
            return nil, { err = "outer_param_mismatch" }
        end
    end

    for i = 1, #desc.params.inner do
        x = expr.app(x, args[#desc.params.outer+i])
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

local function check_positive(vals, name, is_param)
	for _, v in ipairs(vals) do
        if expr.used(is_param and v.type or v, name) then
            return nil, { err = "not_positive", name = name }
        end
	end
end

local function ctor_param(type, desc, ret_type, outer_args, rec_param)
    if not expr.used(type, desc.name) then
        return
    end

    local params = {}
	local args = {}
	local peeled_type = expr.peel_app(expr.peel_forall(expr.lift(type, rec_param+1), params), args)

	local _, err = check_positive(params, desc.name, true) if err then return nil, err end
	local _, err = check_positive(args, desc.name) if err then return nil, err end

    -- this can't happen currently, just double check
    if not expr.is_global(peeled_type, desc.name) then
        return
    end

    ret_type = ret_type + #params
    outer_args = outer_args + #params

    -- assert(#args == #desc.params.outer + #desc.params.inner)

    local ret_rec = expr.bound(ret_type)
    local ret_ind, err = process_type_args(args, desc, outer_args, ret_rec) if err then return nil, err end
    ret_ind = expr.app(ret_ind, expr.app_range(expr.bound(rec_param), 0, #params))

    return {
        rec = expr.forall_t(params, ret_rec),
        ind = expr.forall_t(params, ret_ind)
    }
end

local function define_ctor(ctor, num, desc, elim_params, env)
    local wrapped_type = expr.forall_t(desc.params.outer, ctor.type)
    local reduced_type, err = util.expect("constructor signature", eval.reduce(wrapped_type, env, expr.type)) if err then return nil, err end

    local ret_type = (num-1)
    local outer_args = ret_type+1

	local params = {}
	local peeled_type = expr.peel_forall(
		expr.lift(expr.peel_forall_n(reduced_type.val, #desc.params.outer), outer_args),
		params
	)

    local params_rec = {}
    local params_ind = {}
    for i, param in ipairs(params) do
        local offset = #params+#params_rec
        local rec, err = ctor_param(
            param.type,
            desc,
            ret_type+offset,
            outer_args+offset,
            offset-i
        ) if err then return nil, err end
        if rec then
            table.insert(params_rec, expr.param(underscore("rec", param.name), rec.rec))
            table.insert(params_ind, expr.param(underscore("IH", param.name), rec.ind))
        end
    end

    table.insert(elim_params.elim, expr.param("case_"..ctor.name,
    	expr.forall_t(params, expr.bound(ret_type + #params))
    ))
    table.insert(elim_params.rec, expr.param("case_"..ctor.name,
    	expr.forall_t(params, expr.forall_t(params_rec,
    		expr.bound(ret_type + #params+#params_rec)))
    ))

    local args = {}
    peeled_type = expr.peel_app(expr.lift(peeled_type, #params_ind), args)

    if not expr.is_global(peeled_type, desc.name) then
        return nil, { err = "constructor_type_mismatch" }
    end

    outer_args = outer_args + #params + #params_ind
    ret_type = ret_type + #params + #params_ind

    local ctor_call = expr.app_range(
        expr.app_range(expr.global(ctor.name), outer_args, #desc.params.outer),
        #params_ind, #params)

    local ind_hypot, err = process_type_args(args, desc, outer_args, expr.bound(ret_type)) if err then return nil, err end
    local ind_ret = expr.app(ind_hypot, ctor_call)

    table.insert(elim_params.ind, expr.param("case_"..ctor.name,
        expr.forall_t(params, expr.forall_t(params_ind, ind_ret))
    ))

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
    local type_type = expr.forall_t(desc.params.outer, expr.forall_t(desc.params.inner, expr.type))
    local _, err = util.expect("type signature", eval.typeck(type_type, env, expr.type)) if err then return nil, err end
    local type_def = {
        name = desc.name,
        type = expr.bind(type_type, env),
    }
    local env, err = var.env_add(env, type_def.name, type_def) if err then return nil, err end
    local ind_type = expr.global(desc.name)

    local elim_params = {elim = {}, rec = {}, ind = {}}

    for elim_kind, elim_p in pairs(elim_params) do
        for _, outer in ipairs(desc.params.outer) do
            table.insert(elim_p, outer)
        end
        table.insert(elim_p, {
            name = "R",
            type = elim_kind == "ind"
                and expr.forall_t(desc.params.inner, expr.forall("_",
                    expr.app_range(ind_type, 0, #desc.params.inner+#desc.params.outer),
                    expr.type
                ))
                or expr.type
        })
    end

    local ctors = {}
    local ctor_env = env
    for num, ctor in ipairs(desc.ctors) do
        local def, err = util.expect("constructor "..ctor.name,
            define_ctor(ctor, num, desc, elim_params, ctor_env)) if err then return nil, err end
        env, err = var.env_add(env, def.name, def) if err then return nil, err end
        table.insert(ctors, def)
    end

    local elim = {}
    for elim_kind, elim_p in pairs(elim_params) do
        for _, inner in ipairs(desc.params.inner) do
            table.insert(elim_p, inner)
        end
        table.insert(elim_p, expr.param("_", expr.app_range(
            expr.app_range(ind_type, #desc.params.inner+#desc.ctors+1, #desc.params.outer),
            0, #desc.params.inner
        )))

        local ret_type = expr.bound(1+#desc.params.inner+#desc.ctors)
        if elim_kind == "ind" then
            ret_type = expr.app_range(ret_type, 0, 1+#desc.params.inner)
        end

        local elim_type = expr.forall_t(elim_p, ret_type)
        local _, err = util.expect(elim_kind.." type", eval.typeck(elim_type, env, expr.type)) if err then return nil, err end

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
        name = desc.name,
        type = type_def,
        ctors = ctors,
    }
end

local function define_type(desc, env)
    return util.expect("inductive " .. desc.name, define_type_throw(desc, env))
end

return {
    define_type = define_type,
}
