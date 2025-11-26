local EquipButtons = {}

function EquipButtons.attach(ctx)
    if ctx.EquipBestBtn then
        ctx.EquipBestBtn.MouseButton1Click:Connect(function()
            ctx.Inv.EquipBestNftsAtomic()
        end)
    end

    if ctx.UnequipAllBtn then
        ctx.UnequipAllBtn.MouseButton1Click:Connect(function()
            ctx.Inv.UnequipAllAtomic()
        end)
    end

    task.defer(function()
        ctx.Inv.restoreEquippedLayoutFromServer()
    end)
end

return EquipButtons
