-- implemented according to https://pauillac.inria.fr/~herbelin/publis/univalgcci.pdf

-- a >= b
local function is_ge(c, a, b)
    if c[a] == c[b] then
        return true
    end
    for x in pairs(c[b].gt) do
        if is_ge(c, a, x) then
            return true
        end
    end
    for x in pairs(c[b].ge) do
        if is_ge(c, a, x) then
            return true
        end
    end
    return false
end

-- a > b
local function is_gt(c, a, b)
    if c[a] == c[b] then
        return false
    end
    for x in pairs(c[b].gt) do
        if is_ge(c, a, x) then
            return true
        end
    end
    for x in pairs(c[b].ge) do
        if is_gt(c, a, x) then
            return true
        end
    end
    return false
end

local function merge(c, a, b)
    if c[a] == c[b] then
        return
    end

    for x in pairs(c[b].gt) do
        c[a].gt[x] = true
    end
    for x in pairs(c[b].ge) do
        c[a].ge[x] = true
    end
    for x in pairs(c[b].eq) do
        c[a].eq[x] = true
        c[x] = c[a]
    end
end

-- a >= b
local function merge_interval(c, a, b)
    if c[a] == c[b] then
        return
    end

    for x in pairs(c[b].ge) do
        if is_ge(c, a, x) then
            merge_interval(c, a, x)
        end
    end
    merge(c, a, b)
end

local function constr_new()
    return {}
end

local function constr_var(c)
    local v = #c+1
    table.insert(c, { eq = { [v] = true }, gt = {}, ge = {} })
    return v
end

-- a = b
local function constr_eq(c, a, b)
    if is_gt(c, a, b) or is_gt(c, b, a) then
        return false
    end
    if is_ge(c, a, b) then
        merge_interval(c, a, b)
    elseif is_ge(c, b, a) then
        merge_interval(c, b, a)
    else
        merge(c, a, b)
    end
    return true
end

-- a >= b
local function constr_ge(c, a, b)
    if is_gt(c, b, a) then
        return false
    end

    if is_ge(c, b, a) then
        merge_interval(c, b, a)
    elseif not is_ge(c, a, b) then
        c[b].ge[a] = true
    end
    return true
end

-- a > b
local function constr_gt(c, a, b)
    if is_ge(c, b, a) then
        return false
    end

    if not is_gt(c, a, b) then
        c[b].gt[a] = true
    end
    return true
end

return {
    new = constr_new,
    var = constr_var,
    eq = constr_eq,
    ge = constr_ge,
    gt = constr_gt,
}
