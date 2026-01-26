local expr = require("muprov.expr")
local induct = require("muprov.induct")
local eval = require("muprov.eval")
local util = require("muprov.util")
local var = require("muprov.var")

local function check_duplicate(fields)
    local field_names = {}
    for _, f in ipairs(fields) do
        if field_names[f.name] then
            return nil, { err = "already_defined", name = f.name }
        end
        field_names[f.name] = true
    end
end


local function define_inductive(desc, env)
    local ind, err = induct.define_type({
        name = desc.name,
        params = {
            outer = desc.params,
            inner = {},
        },
        ctors = {{
            name = desc.ctor,
            type = expr.forall_t(desc.fields,
                expr.app_range(expr.free(desc.name), #desc.fields, #desc.params))
        }}
    }, env) if err then return nil, err end

    local ctor = ind.ctors[1]
    local type = ind.type

    env, err = var.env_add(env, type.name, type) assert(not err)
    env, err = var.env_add(env, ctor.name, ctor) assert(not err)

    return { ctor = ctor, type = type, env = env }
end

local function define_dtor(desc, name, inner_type, idx, record, record_params, field_params, env)
    if expr.used(inner_type, record) then
        return nil, { err = "recursive_record" }
    end

    local record_type = expr.app_range(expr.global(record), 0, #desc.params)
    local field_type = expr.lift(expr.lift(inner_type, 1, nil, idx), -idx, function(n)
        return expr.app_range(expr.global(field_params[idx-n].name), 0, #desc.params+1)
    end)

    local val = expr.fun_t(record_params, expr.app(
        expr.app_range(expr.elim("ind", record), 0, #desc.params),
        expr.fun("_", record_type, field_type),
        expr.fun_t(field_params, expr.bound(#desc.fields-idx-1))
    ))

    local type = expr.forall_t(record_params, expr.forall("_", record_type, field_type))
    local type, err = eval.typeck(val, env, type) if err then return nil, err end
    local dtor = {
        name = name,
        val = expr.bind(val, env),
        type = type
    }

    env, err = var.env_add(env, dtor.name, dtor) if err then return nil, err end

    return {
        env = env,
        dtor = dtor,
    }
end

local function define_dtors(desc, type, ctor, env)
    local type_params = {}
    local field_params = {}
    expr.peel_forall_n(
        expr.peel_forall_n(ctor, #desc.params, type_params),
        #desc.fields, field_params)

    local dtors = {}
    for i, f in ipairs(field_params) do
        local def, err = util.expect("field " .. f.name, define_dtor(
            desc,
            f.name,
            f.type,
            i-1,
            type,
            type_params,
            field_params,
            env
        )) if err then return nil, err end
        env = def.env
        table.insert(dtors, def.dtor)
    end
    return dtors
end

local function define_type_throw(desc, env)
    local _, err = check_duplicate(desc.fields) if err then return nil, err end
    local ind, err = define_inductive(desc, env) if err then return nil, err end
    local dtors, err = define_dtors(desc, ind.type.name, ind.ctor.type, ind.env) if err then return nil, err end

    return {
        type = ind.type,
        ctor = ind.ctor,
        dtors = dtors,
    }
end

local function define_type(desc, env)
    return util.expect("record " .. desc.name, define_type_throw(desc, env))
end

return {
    define_type = define_type,
}
