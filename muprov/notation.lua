local expr = require("muprov.expr")
local var = require("muprov.var")

local function parse_uint(notat, x)
    local v = expr.global(notat.zero)
    for i = 1, x.val do
        v = expr.app(expr.global(notat.succ), v)
    end
    return v
end

local function display_uint(notat, x)
    local val = 0
    while x.kind == "app" and expr.is_global(x.left, notat.succ) do
        val = val + 1
        x = x.right
    end

    if expr.is_global(x, notat.zero) then
        return tostring(val)
    end
end

local function parse_array(notat, x)
    local v = expr.app(expr.global(notat.empty), x.type)
    for i = #x.elems, 1, -1 do
        v = expr.app(expr.global(notat.cons), x.type, x.elems[i], v)
    end
    return v
end

local function display_array(notat, x, ...)
    local elems = {}

    while true do
        local args = {}
        if not expr.is_global(expr.peel_app(x, args), notat.cons) or #args ~= 3 then
            break
        end

        table.insert(elems, expr.str(args[2], ...))
        x = args[3]
    end

    if x.kind == "app" and expr.is_global(x.left, notat.empty) then
        return ("[%s%s %s]"):format(table.concat(elems, ", "), #elems > 0 and " :" or ":", expr.str(x.right, ...))
    end
end

local handlers = {
    parse = { uint = parse_uint, array = parse_array },
    display = { uint = display_uint, array = display_array }
}

local function notation_error(msg, ...)
    return { err = "notation_error", msg = msg:format(...) }
end

local function display(notations, ...)
    for name, notat in pairs(notations.display) do
        local disp = handlers.display[name](notat, ...)
        if disp then
            return disp
        end
    end
end

local function parse(notations, x, ...)
    local notat = notations.parse[x.custom_kind]
    if not notat then
        return nil, notation_error("no parse notation active for %s", x.custom_kind)
    end
    return handlers.parse[x.custom_kind](notat, x, ...)
end

local function register(notations, desc, env)
    local notat = notations[desc.notation_kind]
    if not notat then
        return nil, notation_error("not a valid notation kind: %s", desc.notation_name)
    end
    if not handlers[desc.notation_kind][desc.notation_name] then
        return nil, notation_error("not a valid %s notation: %s", desc.notation_kind, desc.notation_name)
    end

    if #desc.args == 0 then
        notat[desc.notation_name] = nil
        return
    end

    for _, ar in ipairs(desc.args) do
        local _, err = var.env_get(env, ar) if err then return nil, err end
    end

    if desc.notation_name == "uint" then
        notat.uint = {
            zero = desc.args[1],
            succ = desc.args[2],
        }
    elseif desc.notation_name == "array" then
        notat.array = {
            empty = desc.args[1],
            cons = desc.args[2],
        }
    else
        error(desc.notation_name)
    end
end

local function notation_new()
    return { parse = {}, display = {} }
end

return {
    display = display,
    parse = parse,
    register = register,
    new = notation_new,
}
