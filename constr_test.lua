local constr = require("constr")

-- basic
do
    local co = constr.new()
    local a, b, c, d = constr.var(co), constr.var(co), constr.var(co), constr.var(co)

    --a >= b >= c >= d, d < a
    assert(constr.ge(co, a, b))
    assert(constr.ge(co, b, c))
    assert(constr.ge(co, c, d))
    assert(not constr.gt(co, d, a))
end

-- paths
do
    local co = constr.new()

    local levels = {}

    for i = 1, 7 do
        local next = {}
        for j = 1, 3 do
            table.insert(next, constr.var(co))
        end
        if i > 1 then
            for _, g in ipairs(levels[i-1]) do
            for _, l in ipairs(next) do
                assert(constr.ge(co, g, l))
            end
            end
        end
        table.insert(levels, next)
    end

    for i = 1, #levels do
    for j = i+1, #levels do
        for _, g in ipairs(levels[i]) do
        for _, l in ipairs(levels[j]) do
            assert(not constr.gt(co, l, g))
        end
        end
    end
    end
end

-- single forcing constraint
do
    local co = constr.new()
    local gs = {constr.var(co)}
    local ls = {constr.var(co)}
    assert(constr.gt(co, gs[1], ls[1]))

    for i = 1, 100 do
        local g = gs[math.random(#gs)]
        local l = ls[math.random(#ls)]
        table.insert(gs, constr.var(co))
        table.insert(ls, constr.var(co))
        assert(constr.ge(co, gs[#gs], g))
        assert(constr.ge(co, l, ls[#ls]))
    end

    for i = 1, 100 do
        local g = gs[math.random(#gs)]
        local l = ls[math.random(#ls)]
        assert(not constr.ge(co, l, g))
    end
end
