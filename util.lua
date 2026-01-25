local function expect(loc, val, err)
    if err then
        return nil, { err = "location", location = loc, inner = err }
    end
    return val
end

return {
    expect = expect,
}
