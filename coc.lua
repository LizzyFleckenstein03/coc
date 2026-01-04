#!/usr/bin/env lua

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
local induct = require("induct")

local function error_str(err, env, params)
    params = params or function() end
    if err.err == "reduce" then
        local new_params = params
        local inner, loc = err.inner, ""
        if err.inner.err == "location" then
            if (err.expr.kind == "fun" or err.expr.kind == "forall") and
                (inner.location == "body" or inner.location == "body type") then
                local _
                _, new_params = expr.choose_param_name(err.expr.param, env, params)
            end

            loc = " in " .. inner.location
            inner = inner.inner
        end

        return ("error%s during %s %s:\n%s"):format(
            loc,
            err.action,
            expr.str(err.expr, env, params),
            error_str(inner, env, new_params))
    elseif err.err == "location" then
        return ("error in %s:\n%s"):format(
            err.location,
            error_str(err.inner, env, params))
    elseif err.err == "env" then
        return error_str(err.inner, err.env, params)
    elseif err.err == "var_not_found" then
        return ("variable not found: %s"):format(err.var)
    elseif err.err == "not_function" then
        return ("not a function:\ngot %s : %s"):format(
            expr.str(err.expr.val, env, params),
            expr.str(err.expr.type, env, params))
    elseif err.err == "not_inductive" then
        return ("not an inductive type: %s"):format(err.type)
    elseif err.err == "type_mismatch" then
        return ("expected type: %s\ngot %s : %s"):format(
            expr.str(err.type, env, params),
            expr.str(err.expr.val, env, params),
            expr.str(err.expr.type, env, params))
    elseif err.err == "constructor_type_mismatch" then
        return ("constructor return type mismatch")
    elseif err.err == "outer_param_mismatch" then
        return ("outer parameter mismatch")
    elseif err.err == "already_exists" then
        return ("already exists: %s"):format(err.name)
    elseif err.err == "syntax_error" then
        return ("syntax error in %s: %s"):format(err.pos, err.msg)
    else
        error(err.err)
    end
end

local function report_error(err)
    print(error_str(err))
    return false
end

local function new_state()
    local env_table = {}
    return {
        included = {},
        env = function(x) return env_table[x] end,
        env_table = env_table
    }
end

local run_file

local function run_command(state, com)
    if com.kind == "def" or com.kind == "check" or com.kind == "eval" then
        local res, type
        local val = com.expr and expr.bind(com.expr, state.env)

        if com.expr then
            local obj, err = eval.reduce(com.expr, state.env, com.type, com.kind ~= "eval") if err then return report_error(err) end
            res, type = obj.val, obj.type
        else
            local _, err = eval.typeck(com.type, state.env, { kind = "type" }) if err then return report_error(err) end
            type = expr.bind(com.type, state.env)
        end

        local def = com.kind == "def" and { name = com.name, type = type, val = val }
        if def then
            local _, err = expr.env_add(state.env, def.name, def) if err then return report_error(err) end
        end

        if com.kind == "eval" then
            print(("%s\n\t= %s\n\t: %s"):format(
                expr.str(val, state.env),
                expr.str(res, state.env),
                expr.str(type, state.env)))
        elseif com.kind == "def" then
            print(("%s : %s"):format(
                com.name,
                expr.str(type, state.env)))
        elseif com.kind == "check" then
            print(("%s : %s"):format(
                expr.str(val, state.env),
                expr.str(type, state.env)))
        end

        if def then
            state.env_table[def.name] = def
        end

        return true
    elseif com.kind == "inductive" then
        local def, err = induct.define_type(com, state.env) if err then return report_error(err) end

        print(("%s : %s"):format(def.type.name, expr.str(def.type.type, state.env)))
        state.env_table[def.type.name] = def.type
        for _, ctor in ipairs(def.ctors) do
            print(("%s : %s"):format(ctor.name, expr.str(ctor.type, state.env)))
            state.env_table[ctor.name] = ctor
        end

        return true
    elseif com.kind == "include" then
        return run_file(state, com.path)
    elseif com.kind == "exit" then
        return true, true
    else
        error(com.kind)
    end
end

local function parse_and_run_command(state, stream)
    local com, err = parse.stmt(stream)
    if err then
        return report_error(err)
    end
    if not com then
        if not parse.done(stream) then
            return report_error(parse.err(stream, "expected command"))
        end
        return true, true
    end
    return run_command(state, com)
end

local function run_stream(state, stream, keep_going, pre)
    while true do
        if pre then
            pre(stream, env)
        end
        local success, done = parse_and_run_command(state, stream)
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

run_file = function(state, path)
    if state.included[path] then
        return true
    end

    local f = io.open(path, "r")
    if not f then
        print("error: failed to open file " .. path)
        return false
    end

    local success = run_stream(state, parse.stream(path, f))
    if success then
        state.included[path] = true
    end
    return success
end

local function run_repl(state)
    local has_readline, readline = pcall(require, "readline")
    local read

    if has_readline then
        read = readline.readline
    else
        read = function(prompt)
            io.write(prompt)
            return io.read()
        end
    end

    local multiline = false
    return run_stream(state,
        parse.stream("stdin", function()
            local line = read(multiline and ">> " or "> ")
            multiline = multiline or (line and line:match("[^%s\n]"))
            return line
        end), true, function() multiline = false end)

end

local function main()
    local repl
    local file

    if arg[1] then
        if arg[1] == "-i" then
            repl = true
            file = arg[2]
        else
            file = arg[1]
        end
    else
        repl = true
    end

    local state = new_state()
    if file and not run_file(state, file) then
        return false
    end
    if repl and not run_repl(state) then
        return false
    end
    return true
end

if not main() then
    os.exit(1)
end
