#!/usr/bin/env lua

local muprov = require("muprov")

local help_text = [[
usage: %s [-i] [-v] [-h] [<file>]
    -v: verbose mode, report all definitions from files
    -i: interactive mode, start REPL after executing <file>
    -h: show help
    <file>: muprov file to run. if no file is given, a REPL is started.
]]

local function main()
    local state = muprov.new_state()
    local repl, file

    local idx = 1
    while arg[idx] and arg[idx]:sub(1,1) == "-" do
        local ar = arg[idx]
        idx = idx + 1

        if ar == "-i" then
            repl = true
        elseif ar == "-v" then
            state.verbose = true
        elseif ar == "--" then
            break
        else
            io.write(help_text:format(arg[0]))
            return ar == "-h"
        end
    end

    file = arg[idx]
    repl = repl or not file

    if file and not muprov.run_file(state, file) then
        return false
    end
    if repl and not muprov.run_repl(state) then
        return false
    end
    return true
end

if not main() then
    os.exit(1)
end
