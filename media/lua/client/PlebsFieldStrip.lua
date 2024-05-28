require("ISUI/ISInventoryPaneContextMenu")

local function ifNotBroken(item)
	return not item:isBroken()
end

local function normalizeStack(items)
	print("normalizing stack")
	local out, queue, seen = {}, {items}, {}

	while #queue > 0 do
		local nxt = table.remove(queue, 1)
		print("next item", nxt)
		if nxt.items then
			print("item.items")
			for i = 1, #nxt.items do
				local item = nxt.items[i]
				table.insert(queue, item)
				print(item)
			end
		elseif type(nxt) == "table" then
			print("item table")
			for _, item in ipairs(nxt) do
				table.insert(queue, item)
				print(item)
			end
		elseif instanceof(nxt, "HandWeapon") then
			print("item")
			if not seen[nxt] then
				table.insert(out, nxt)
				seen[nxt] = true
			end
		end
	end

	return out
end

local function hasAvailableAction(weapon, inv)
	if not weapon:getMagazineType() and weapon:getCurrentAmmoCount() > 0 then
		-- If we don't have a magazine (integral), and ammo to remove from it.
		return true
	end

	if weapon:isContainsClip() then
		-- We have a magazine to remove.
		return true
	end

	if weapon:isJammed() or ISReloadWeaponAction.canRack(weapon) then
		-- We can rack the gun, or clear a jam.
		return true
	end

	local hasScrewdriver = inv:containsTagEvalRecurse("Screwdriver", ifNotBroken)
	local availablePart = false
	for _, part in ipairs({"Scope", "Sling", "Stock", "Canon", "Recoilpad"}) do
		part = weapon["get" .. part](weapon)
		if part then
			availablePart = true
			break
		end
	end

	if availablePart then
		if not hasScrewdriver then
			return false, "ContextMenu_NET_PartsAvailableNoScrewdriver"
		end

		return true
	end

	return false
end

local function onClearGun(weapon, ply)
	local idx = ply:getPlayerNum()
	if not weapon:getMagazineType() then
		-- If we don't have a clip (integral), we clear that.
		ISInventoryPaneContextMenu.equipWeapon(weapon, true, false, idx)
		ISTimedActionQueue.add(ISUnloadBulletsFromFirearm:new(ply, weapon))
	end

	if weapon:isContainsClip() then
		-- Eject Clip
		ISInventoryPaneContextMenu.equipWeapon(weapon, true, false, idx)
		ISTimedActionQueue.add(ISEjectMagazine:new(ply, weapon))
	end

	if weapon:isJammed() or ISReloadWeaponAction.canRack(weapon) then
		-- Clear the Weapon
		ISInventoryPaneContextMenu.equipWeapon(weapon, true, false, idx)
		ISTimedActionQueue.add(ISRackFirearm:new(ply, weapon))
	end

	local inv = ply:getInventory()
	local hasScrewdriver = inv:containsTagEvalRecurse("Screwdriver", ifNotBroken)
	if hasScrewdriver then
		local screwdriver = inv:getFirstTagEvalRecurse("Screwdriver", ifNotBroken)
		for _, part in ipairs({"Scope", "Sling", "Stock", "Canon", "Recoilpad"}) do
			part = weapon["get" .. part](weapon)
			if part then
				ISInventoryPaneContextMenu.equipWeapon(screwdriver, true, false, idx)
				ISInventoryPaneContextMenu.transferIfNeeded(ply, weapon)
				ISTimedActionQueue.add(ISRemoveWeaponUpgrade:new(ply, weapon, part, 50))
			end
		end
	end
end

local function onClearGuns(weapons, ply)
	for _, weapon in ipairs(weapons) do
		onClearGun(weapon, ply)
	end
end

local function OnFillInventoryObjectContextMenu(idx, context, items)
	local ply = getSpecificPlayer(idx)
	if not ply then
		return
	end

	items = normalizeStack(items)
	local allowed, blocked, inv = {}, {}, ply:getInventory()
	for _, item in ipairs(items) do
		local allow, reason = hasAvailableAction(item, inv)
		if allow then
			table.insert(allowed, item)
		elseif reason then
			table.insert(blocked, reason)
		end
	end

	local allowedCount = #allowed
	if allowedCount == 0 and #blocked == 0 then
		return
	end

	local hdr = allowedCount > 1 and getText("ContextMenu_NET_ClearFirearms", allowedCount) or getText("ContextMenu_NET_ClearFirearm")
	if allowedCount ~= 0 then
		context:addOption(hdr, allowed, onClearGuns, ply)
	elseif #blocked ~= 0 then
		local tooltip = ISInventoryPaneContextMenu.addToolTip()
		tooltip.description = getText(blocked[1])

		local option = context:addOption(hdr)
		option.notAvailable = true
		option.toolTip = tooltip
	end
end

Events.OnFillInventoryObjectContextMenu.Add(OnFillInventoryObjectContextMenu)
