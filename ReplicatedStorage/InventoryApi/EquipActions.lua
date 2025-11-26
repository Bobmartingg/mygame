local EquipActions = {}

local function getMaxEquipped(ctx)
    local directLimit = tonumber(ctx.player:GetAttribute("EquipmentLimit"))
    if directLimit and directLimit > 0 then
        return directLimit
    end
    local lvlAttr = tonumber(ctx.player:GetAttribute("EquipmentLvl"))
    if lvlAttr and lvlAttr >= 0 then
        return 5 + lvlAttr
    end
    local lvl = tonumber(ctx.GetPlayerEquipmentLvl:InvokeServer()) or 0
    return 5 + lvl
end

local function collectSlots(frame, isSlot)
    local slots = {}
    for _, ch in ipairs(frame:GetChildren()) do
        if isSlot(ch) then
            table.insert(slots, ch)
        end
    end
    table.sort(slots, function(a, b)
        return (a.LayoutOrder or 0) < (b.LayoutOrder or 0)
    end)
    return slots
end

function EquipActions.attach(ctx)
    local Inv = ctx.Inv

    local function moveCardToGrid(card)
        card.Parent = ctx.NotEquippedGrid
        card.AnchorPoint = Vector2.new(0, 0)
        card.Position = UDim2.new()
        card.Size = UDim2.fromScale(1, 1)
        ctx.setNftOnlySize(card, 0.8)
    end

    local function relocateCardToSlot(card, slot)
        slot:SetAttribute("Occupied", true)
        card:SetAttribute("EquippedSlotName", slot.Name)
        card.Parent = slot
        card.AnchorPoint = Vector2.new(0.5, 0.5)
        card.Position = UDim2.fromScale(0.5, 0.5)
        card.Size = UDim2.fromScale(1, 1)
        ctx.setNftOnlySize(card, 0.8)
        ctx.ensurePowerLabelStrong(card, ctx.getPowerForUuid(card.Name))
        card.Visible = true
    end

    local function pushDesiredOrderToServer()
        local desired = {}
        local slots = collectSlots(ctx.EquippedNftsFrame, ctx.isSlot)
        for _, s in ipairs(slots) do
            for _, kid in ipairs(s:GetChildren()) do
                if ctx.isCard(kid) then
                    table.insert(desired, kid.Name)
                end
            end
        end

        local ok, res = pcall(function()
            return ctx.ApplyEquippedLayoutRF:InvokeServer(desired)
        end)
        if not ok or not res or res.ok ~= true then
            warn("[INV] ApplyEquippedLayout failed", ok, res and res.err)
        end
    end

    function Inv.EquipBestNftsAtomic()
        if ctx.isRemoveMode() then
            return
        end
        ctx.SetEquipSaveSuppressed:FireServer(true)

        local oldEquipped = {}
        for _, slot in ipairs(ctx.EquippedNftsFrame:GetChildren()) do
            if ctx.isSlot(slot) then
                for _, ch in ipairs(slot:GetChildren()) do
                    if ctx.isCard(ch) then
                        table.insert(oldEquipped, ch.Name)
                    end
                end
            end
        end

        for _, slot in ipairs(ctx.EquippedNftsFrame:GetChildren()) do
            if ctx.isSlot(slot) then
                for _, ch in ipairs(slot:GetChildren()) do
                    if ctx.isCard(ch) then
                        slot:SetAttribute("Occupied", false)
                        ch:SetAttribute("EquippedSlotName", nil)
                        moveCardToGrid(ch)
                    end
                end
            end
        end

        local maxEquipped = getMaxEquipped(ctx)
        local candidates = {}
        for _, inst in ipairs(ctx.inventoryFolder:GetChildren()) do
            table.insert(candidates, { uuid = inst.Name, power = ctx.powerOf(inst) })
        end
        table.sort(candidates, function(a, b)
            if a.power ~= b.power then
                return a.power > b.power
            end
            return tostring(a.uuid) < tostring(b.uuid)
        end)

        local newEquippedSet = {}
        for i = 1, math.min(maxEquipped, #candidates) do
            local u = candidates[i].uuid
            local card = Inv.ensureCardSpawned(u)
            if card then
                local free = ctx.GetFirstFreeSlot()
                if not free then
                    break
                end
                relocateCardToSlot(card, free)
                newEquippedSet[u] = true
            end
        end

        ctx.updateEquippedCounterDebounced(true)
        ctx.applyLastRowCentering()

        local oldSet = {}
        for _, uuid in ipairs(oldEquipped) do
            oldSet[uuid] = true
        end

        for _, uuid in ipairs(oldEquipped) do
            if not newEquippedSet[uuid] then
                ctx.UnequipNftEvent:FireServer(uuid)
            end
        end

        for uuid in pairs(newEquippedSet) do
            if not oldSet[uuid] then
                ctx.EquipNftEvent:FireServer(uuid)
            end
        end

        pushDesiredOrderToServer()
        ctx.SetEquipSaveSuppressed:FireServer(false)
        ctx.refreshWindowAfterEquipChange()
    end

    function Inv.UnequipAllAtomic()
        if ctx.isRemoveMode() then
            return
        end
        ctx.SetEquipSaveSuppressed:FireServer(true)

        local oldEquipped = {}
        for _, slot in ipairs(ctx.EquippedNftsFrame:GetChildren()) do
            if ctx.isSlot(slot) then
                for _, ch in ipairs(slot:GetChildren()) do
                    if ctx.isCard(ch) then
                        table.insert(oldEquipped, ch.Name)
                    end
                end
            end
        end

        for _, slot in ipairs(ctx.EquippedNftsFrame:GetChildren()) do
            if ctx.isSlot(slot) then
                for _, ch in ipairs(slot:GetChildren()) do
                    if ctx.isCard(ch) then
                        slot:SetAttribute("Occupied", false)
                        ch:SetAttribute("EquippedSlotName", nil)
                        moveCardToGrid(ch)
                        ctx.ensurePowerLabelStrong(ch, ctx.getPowerForUuid(ch.Name))
                    end
                end
            end
        end

        ctx.updateEquippedCounterDebounced(true)
        ctx.applyLastRowCentering()
        _G.__updateCanvas()

        for _, uuid in ipairs(oldEquipped) do
            ctx.UnequipNftEvent:FireServer(uuid)
        end

        local ok, res = pcall(function()
            return ctx.ApplyEquippedLayoutRF:InvokeServer({})
        end)
        if not ok or not res or res.ok ~= true then
            warn("[INV] ApplyEquippedLayout(empty) failed", ok, res and res.err)
        end

        ctx.SetEquipSaveSuppressed:FireServer(false)
        ctx.refreshWindowAfterEquipChange()
    end
end

return EquipActions
