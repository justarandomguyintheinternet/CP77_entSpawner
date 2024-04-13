local parent = require("modules/classes/spawn/parent")
local child = setmetatable({}, { __index = parent })

function child:new(name)
	local o = parent.new(self, name)

    o.inSchool = false

    setmetatable(o, { __index = self })
   	return o
end

function child:getAge()
    return -self.age
end

function child:isInSchool()
    print(self.inSchool)
end

function child:getOriginalAge()
    return parent.getAge(self)
end

return child