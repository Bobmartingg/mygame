local Restoration = {}

local function fetchEquippedListWithRetry(ctx, maxAttempts: number, delaySec: number)
    for attempt = 1, maxAttempts do
        local ok, res = pcall(function()
            return ctx.GetEquippedUuidsRF:InvokeServer()
        end)

        if not ok then
            warn("[INV] GetEquippedUuidsRF failed:", res)
            return nil
        end

        if type(res) == "table" and #res > 0 then
            return res
        end

        task.wait(delaySec)
    end
    return nil
end

function Restoration.attach(ctx)
    local Inv = ctx.Inv

    function Inv.restoreEquippedLayoutFromServer()
        local equippedList = fetchEquippedListWithRetry(ctx, 10, 0.2)
        if not equippedList or #equippedList == 0 then
            return
        end

        ctx.ensureSlotExistence()

        for _, raw in ipairs(equippedList) do
            local uuid = Inv.extractUuid(raw)
            if uuid and #uuid > 0 then
                uuid = tostring(uuid)

                local card = Inv.ensureCardForUuid(uuid)
                if card then
                    local parentSlot = card.Parent
                    if parentSlot and parentSlot:IsDescendantOf(ctx.EquippedNftsFrame) then
                        parentSlot:SetAttribute("Occupied", true)
                        card.Visible = true
                    else
                        local free = ctx.GetFirstFreeSlot()
                        if free then
                            free:SetAttribute("Occupied", true)
                            card:SetAttribute("EquippedSlotName", free.Name)
                            card.Parent = free
                            card.AnchorPoint = Vector2.new(0.5, 0.5)
                            card.Position = UDim2.fromScale(0.5, 0.5)
                            card.Size = UDim2.fromScale(1, 1)
                            ctx.setNftOnlySize(card, 0.8)
                            ctx.ensurePowerLabelStrong(card, ctx.getPowerForUuid(card.Name))
                            card.Visible = true
                        else
                            warn("[INV] no free slot for equipped uuid", uuid)
                        end
                    end
                else
                    warn("[INV] cannot restore equipped uuid, not found:", uuid)
                end
            end
        end

        ctx.applyLastRowCentering()
        ctx.updateEquippedCounterDebounced(true)
        _G.__updateCanvas()
    end
end

return Restoration
