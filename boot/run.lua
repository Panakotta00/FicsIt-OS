
local bootEntries = {}
local bootOrder = {}
local bootFolder = "/boot"

for _, child in pairs(filesystem.childs(bootFolder)) do
	local num = child:match("^(%d+)_.+$")
	if num then
		local entries = bootEntries[num]
		if not entries then
			entries = {}
			bootEntries[num] = entries
			table.insert(bootOrder, num)
		end
		table.insert(entries, child)
	end
end
table.sort(bootOrder)
for _, num in pairs(bootOrder) do
	for _, entry in pairs(bootEntries[num]) do
		filesystem.doFile(filesystem.path(bootFolder, entry))
	end
end
