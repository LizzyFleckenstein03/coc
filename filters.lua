local eval = require("eval")
local expr = require("expr")

local function parse_uint(f, x)
    local v = { kind = "global", name = f.zero }
    for i = 1, x.val do
        v = { kind = "app", left = { kind = "global", name = f.succ }, right = v }
    end
    return v
end

local function display_uint(f, x)
    local val = 0
    while x.kind == "app" and x.left.kind == "global" and x.left.name == f.succ do
        val = val + 1
        x = x.right
    end

    if x.kind == "global" and x.name == f.zero then
        return tostring(val)
    end
end

local handlers = {
    parse = { uint = parse_uint },
    display = { uint = display_uint }
}

local function filter_error(msg, ...)
    return { err = "filter_error", msg = msg:format(...) }
end

local function display(filters, ...)
    for name, f in pairs(filters.display) do
        local disp = handlers.display[name](f, ...)
        if disp then
            return disp
        end
    end
end

local function parse(filters, x, ...)
    local filt = filters.parse[x.custom_kind]
    if not filt then
        return nil, filter_error("no parse filter active for %s", x.custom_kind)
    end
    return handlers.parse[x.custom_kind](filt, x, ...)
end

local function register(filters, desc, env)
    local filt = filters[desc.filter_kind]
    if not filt then
        return nil, filter_error("not a valid filter kind: %s", desc.filter_kind)
    end
    if not handlers[desc.filter_kind][desc.filter_name] then
        return nil, filter_error("not a valid %s filter: %s", desc.filter_kind, desc.filter_name)
    end

    if #desc.args == 0 then
        filt[desc.filter_name] = nil
        return
    end

    for _, ar in ipairs(desc.args) do
        local _, err = expr.env_get(env, ar) if err then return nil, err end
    end

    if desc.filter_name == "uint" then
        filt.uint = {
            zero = desc.args[1],
            succ = desc.args[2],
        }
    else
        error(desc.filter_name)
    end
end

local function filters_new()
    return { parse = {}, display = {} }
end

return {
    display = display,
    parse = parse,
    register = register,
    new = filters_new,
}
