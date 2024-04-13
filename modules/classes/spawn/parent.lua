local parent = {}

function parent:new(name)
	local o = {}

    o.name = name
    o.age = 50

	self.__index = self
   	return setmetatable(o, self)
end

function parent:getAge()
    return self.age
end

function parent:getName()
    return self.name
end

return parent