-- for debugging purposes
function dump(x, idt)
    local p = {}
    local idt = idt or 0
    for k, v in pairs(x) do
        local s
        if type(v) == "table" then
            s = dump(v, idt+1)
        elseif type(v) == "string" then
            s = ("\"%s\""):format(v)
        else
            s = ("%s"):format(v)
        end
        table.insert(p, ("%s%s = %s"):format((" "):rep(4*(idt+1)), k, s))
    end
    return ("{\n%s\n%s}"):format(table.concat(p, ", \n"), (" "):rep(4*idt))
end

local expr = require("expr")
local parse = require("parse")
local eval = require("eval")

local function error_str(err)
    if err.err == "what" then
        local inner, where = err.inner, ""
        if err.inner.err == "where" then
            where = " in " .. inner.where
            inner = inner.inner
        end
        return ("error%s during %s %s:\n%s")
            :format(where, err.action, expr.str(err.expr), error_str(inner))
    elseif err.err == "where" then
        return ("error in %s:\n%s")
            :format(err.where, error_str(err.inner))
    elseif err.err == "var_not_found" then
        return ("variable not found: %s")
            :format(err.var)
    elseif err.err == "not_function" then
        return ("not a function:\ngot %s : %s")
            :format(expr.str(err.expr.val), expr.str(err.expr.type))
    elseif err.err == "type_mismatch" then
        return ("expected type: %s\ngot %s : %s")
            :format(expr.str(err.type), expr.str(err.expr.val), expr.str(err.expr.type))
    elseif err.err == "syntax_error" then
        return ("syntax error in %s: %s")
            :format(err.pos, err.msg)
    end
end

local function report_error(err)
    print(error_str(err))
    return false
end

local run_file

local function eval_typed(x, env, typeck, want_type)
    local obj, err = eval.reduce(x, env, typeck) if err then return nil, err end

    if not want_type then
        return obj
    end

    local type, err = eval.reduce(obj.type, env) if err then return nil, err end
    local want_type_r, err = eval.reduce(want_type, env) if err then return nil, err end
    local _, err = eval.type_match(want_type_r.val, { val = x, type = type.val }) if err then return nil, err end

    return { val = obj.val, type = want_type }
end

local function run_command(com, env)
    if com.kind == "def" or com.kind == "check" or com.kind == "eval" then
        local val, type

        if com.expr then
            local obj, err = eval_typed(com.expr, env, com.kind ~= "eval", com.type) if err then return report_error(err) end
            val, type = obj.val, obj.type
        else
            local _, err = eval_typed(com.type, env, true, { kind = "type" }) if err then return report_error(err) end
            type = com.type
        end

        if com.kind == "eval" then
            print(("%s\n\t= %s\n\t: %s"):format(expr.str(com.expr), expr.str(val), expr.str(type)))
        elseif com.kind == "def" then
            print(("%s : %s"):format(com.name, expr.str(type)))
        elseif com.kind == "check" then
            print(("%s : %s"):format(expr.str(com.expr), expr.str(type)))
        end

        if com.kind == "def" then
            table.insert(env, {
                name = com.name,
                type = expr.bind(type, env),
                val = val and expr.bind(val, env)
            })
        end

        return true
    elseif com.kind == "include" then
        return run_file(com.path, env)
    elseif com.kind == "exit" then
        return true, true
    else
        error()
    end
end

local function parse_and_run_command(stream, env)
    local com, err = parse.stmt(stream)
    if err then
        return report_error(err, stream)
    end
    if not com then
        if not parse.done(stream) then
            return report_error(parse.err(stream, "expected command"))
        end
        return true, true
    end
    return run_command(com, env)
end

local function run_stream(stream, env, keep_going, pre)
    while true do
        if pre then
            pre(stream, env)
        end
        local success, done = parse_and_run_command(stream, env)
        if done then
            break
        end
        if not success then
            if keep_going then
                parse.skip(stream)
            else
                return false
            end
        end
    end

    return true
end

run_file = function(path, env)
    local f = io.open(path, "r")
    if not f then
        print("error: failed to open file " .. path)
        return false
    end

    return run_stream(parse.stream(path, f), env)
end

local function main()
    if arg[1] then
        return run_file(arg[1], {})
    else
        local has_readline, readline = pcall(require, "readline")

        if has_readline then
            return run_stream(parse.stream("stdin", setmetatable({}, {__index = {
                read = function()
                    return readline.readline("> ")
                end,
            }})), {}, true)
        else
            return run_stream(parse.stream("stdin", io.stdin), {}, true, function()
                io.write("> ")
            end)
        end
    end
end

if not main() then
    os.exit(1)
end
