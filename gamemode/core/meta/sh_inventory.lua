local _R = debug.getregistry()

local META = _R.Inventory or setmetatable({}, {})
META.__index = META
META.slots = META.slots or {}
META.w = META.w or 4
META.h = META.h or 4

function META:setSize(w, h)
	self.w = w
	self.h = h
end

function META:getSize()
	return self.w, self.h
end

function META:setOwner(owner)
	if (type(owner) == "Player" and owner:getNetVar("charID")) then
		owner = owner:getNetVar("charID")
	elseif (type(owner) != "number") then
		return
	end

	self.owner = owner
end

function META:canItemFit(x, y, w, h, item2)
	local canFit = true

	for x2 = 0, w - 1 do
		for y2 = 0, h - 1 do
			local item = (self.slots[x + x2] or {})[y + y2]

			if ((x + x2) > self.w or item) then
				if (item2) then
					if (item and item.id == item2.id) then
						continue
					end
				end

				canFit = false
				break
			end
		end

		if (!canFit) then
			break
		end
	end

	return canFit
end

function META:findEmptySlot(w, h)
	w = w or 1
	h = h or 1

	if (w > self.w or h > self.h) then
		return
	end

	local canFit = false

	for y = 1, self.h - (h - 1) do
		for x = 1, self.w - (w - 1) do
			if (self:canItemFit(x, y, w, h)) then
				return x, y
			end
		end
	end
end

function META:getItemAt(x, y)
	if (self.slots and self.slots[x]) then
		return self.slots[x][y]
	end
end

function META:remove(id, noReplication, noDelete)
	local x2, y2

	for x = 1, self.w do
		if (self.slots[x]) then
			for y = 1, self.h do
				local item = self.slots[x][y]

				if (item and item.id == id) then
					self.slots[x][y] = nil

					x2 = x2 or x
					y2 = y2 or y
				end
			end
		end
	end

	if (SERVER and !noReplication) then
		local receiver = self:getReceiver()

		if (IsValid(receiver) and receiver:getChar() and self.owner == receiver:getChar():getID()) then
			netstream.Start(receiver, "invRmv", id)
		else
			netstream.Start(receiver, "invRmv", id, self.owner)
		end

		if (!noDelete) then
			nut.db.query("DELETE FROM nut_items WHERE _itemID = "..id)
			nut.item.instances[id] = nil
		end
	end

	return x2, y2
end

function META:getReceiver()
	for k, v in ipairs(player.GetAll()) do
		if (v:getNetVar("charID") == self.owner) then
			return v
		end
	end
end

function META:getItemByID(id)
	for k, v in pairs(self.slots) do
		for k2, v2 in pairs(v) do
			if (v2.id == id) then
				return k, k2
			end
		end
	end
end

if (SERVER) then
	function META:sendSlot(x, y, item)
		local receiver = self:getReceiver()

		if (IsValid(receiver) and receiver:getChar() and self.owner == receiver:getChar():getID()) then
			netstream.Start(receiver, "invSet", item and item.uniqueID or nil, item and item.id or nil, x, y)
		else
			netstream.Start(receiver, "invSet", item and item.uniqueID or nil, item and item.id or nil, x, y, self.owner)
		end
	end

	function META:add(uniqueID, quantity, data, x, y, noReplication)
		quantity = quantity or 1

		if (self.owner and quantity > 0) then
			if (type(uniqueID) != "number" and quantity > 1) then
				for i = 1, quantity do
					self:add(uniqueID, 1, data)
				end

				return
			end

			if (type(uniqueID) == "number") then
				local item = nut.item.instances[uniqueID]

				if (item) then
					if (!x and !y) then
						x, y = self:findEmptySlot(item.width, item.height)
					end
					
					if (x and y) then
						self.slots[x] = self.slots[x] or {}
						self.slots[x][y] = true

						item.gridX = x
						item.gridY = y

						for x2 = 0, item.width - 1 do
							for y2 = 0, item.height - 1 do
								self.slots[x + x2] = self.slots[x + x2] or {}
								self.slots[x + x2][y + y2] = item
							end
						end

						if (!noReplication) then
							self:sendSlot(x, y, item)
						end

						nut.db.query("UPDATE nut_items SET _charID = "..self.owner..", _x = "..x..", _y = "..y.." WHERE _itemID = "..item.id)

						return x, y
					else
						return false, "no space"
					end
				else
					return false, "invalid index"
				end
			else
				local itemTable = nut.item.list[uniqueID]

				if (!itemTable) then
					return false, "invalid item"
				end

				if (!x and !y) then
					x, y = self:findEmptySlot(itemTable.width, itemTable.height)
				end
				
				if (x and y) then
					self.slots[x] = self.slots[x] or {}
					self.slots[x][y] = true

					nut.item.instance(self.owner, uniqueID, data, x, y, function(item)
						item.gridX = x
						item.gridY = y

						for x2 = 0, item.width - 1 do
							for y2 = 0, item.height - 1 do
								self.slots[x + x2] = self.slots[x + x2] or {}
								self.slots[x + x2][y + y2] = item
							end
						end

						if (!noReplication) then
							self:sendSlot(x, y, item)
						end
					end)

					return x, y
				else
					return false, "no space"
				end
			end
		end
	end

	function META:sync(receiver)
		local slots = {}

		for x, items in pairs(self.slots) do
			for y, item in pairs(items) do
				if (item.gridX == x and item.gridY == y) then
					slots[#slots + 1] = {x, y, item.uniqueID, item.id, item.data}
				end
			end
		end

		netstream.Start(receiver, "inv", slots, self.w, self.h, receiver == nil and self.owner or nil)
	end
end

_R.Inventory = META