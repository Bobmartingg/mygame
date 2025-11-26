local CardLookup = {}

function CardLookup.attach(ctx)
    local Inv = ctx.Inv

    function Inv.getCardByUuid(uuid)
        for _, ch in ipairs(ctx.NotEquippedGrid:GetChildren()) do
            if ctx.isCard(ch) and ch.Name == uuid then
                return ch
            end
        end
        return nil
    end

    function Inv.ensureCardSpawned(uuid)
        local found = Inv.getCardByUuid(uuid)
        if found then
            return found
        end

        local recPos = ctx.IndexByUuid[uuid]
        if recPos and recPos <= ctx.VISIBLE_LIMIT then
            local inst = ctx.inventoryFolder:FindFirstChild(uuid)
            if inst then
                table.insert(ctx.Q_ADD, inst)
                ctx.scheduleQueue()
            end
        end

        return Inv.getCardByUuid(uuid)
    end

    function Inv.findEquippedCardByUuid(uuid: string): GuiObject?
        for _, slot in ipairs(ctx.EquippedNftsFrame:GetChildren()) do
            if ctx.isSlot(slot) then
                local ch = slot:FindFirstChild(uuid)
                if ch and ctx.isCard(ch) then
                    return ch
                end
            end
        end
        return nil
    end

    function Inv.ensureCardForUuid(uuid: string): GuiObject?
        local card = ctx.NotEquippedGrid:FindFirstChild(uuid)
        if card and ctx.isCard(card) then
            return card
        end

        card = Inv.findEquippedCardByUuid(uuid)
        if card and ctx.isCard(card) then
            return card
        end

        local inst = ctx.inventoryFolder:FindFirstChild(uuid)
        if not inst then
            inst = ctx.inventoryFolder:WaitForChild(uuid, 5)
        end
        if not inst then
            return nil
        end

        ctx.AddNftCard(inst)
        card = ctx.NotEquippedGrid:FindFirstChild(uuid) or Inv.findEquippedCardByUuid(uuid)
        return (card and ctx.isCard(card)) and card or nil
    end

    function Inv.extractUuid(raw)
        if type(raw) == "string" then
            return raw
        end
        if type(raw) == "table" then
            if type(raw.uuid) == "string" then
                return raw.uuid
            end
            if type(raw.id) == "string" then
                return raw.id
            end
        end
        return nil
    end
end

return CardLookup
