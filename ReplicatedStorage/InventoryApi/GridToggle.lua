local GridToggle = {}

function GridToggle.attach(ctx)
    local Inv = ctx.Inv

    function Inv.updateGridIcon(btn)
        local mode = ctx.root:GetAttribute("GridMode") or "big"
        if mode == "big" then
            btn.Image = "rbxassetid://122085968144036" -- иконка мелкой сетки
        else
            btn.Image = "rbxassetid://106305965634447" -- иконка крупной сетки
        end
    end

    function Inv.setupChangeGridBtn()
        local btn = ctx.root:FindFirstChild("ChangeGridBtn")
        if not (btn and btn:IsA("ImageButton")) then
            return
        end

        if ctx.root:GetAttribute("GridMode") == nil then
            ctx.root:SetAttribute("GridMode", "big")
        end

        Inv.updateGridIcon(btn)

        btn.MouseButton1Click:Connect(function()
            local mode = ctx.root:GetAttribute("GridMode") or "big"
            if mode == "big" then
                mode = "small"
            else
                mode = "big"
            end

            ctx.root:SetAttribute("GridMode", mode)
            Inv.updateGridIcon(btn)

            ctx.applyResponsiveNotEquipped()
            ctx.scheduleReflow()
        end)
    end

    Inv.setupChangeGridBtn()
end

return GridToggle
