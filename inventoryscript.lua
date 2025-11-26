local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui        = game:GetService("StarterGui")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")
local TextService       = game:GetService("TextService")
local TweenService      = game:GetService("TweenService")

-- UIScale helpers (локально, без внешних модулей)
local function getEffectiveUIScale(gui: Instance): number
    local k = 1
    local p = gui
    while p and p ~= game do
        for _, ch in ipairs(p:GetChildren()) do
            if ch:IsA("UIScale") then
                k *= (ch.Scale or 1)
            end
        end
        p = p.Parent
    end
    if k == 0 then
        k = 1
    end
    return k
end

local function AbsUnscaled(gui: GuiObject): Vector2
    local k = getEffectiveUIScale(gui)
    local s = gui.AbsoluteSize
    return Vector2.new(s.X / k, s.Y / k)
end

local function ContentUnscaled(layout: UIGridLayout | UIListLayout): Vector2
    local k = getEffectiveUIScale(layout)
    local s = layout.AbsoluteContentSize
    return Vector2.new(s.X / k, s.Y / k)
end

local InventoryApi = ReplicatedStorage:WaitForChild("InventoryApi")
local Inv = {} -- namespace для тяжёлых функций, чтобы не плодить local function

--== Player/data
local player = Players.LocalPlayer
local inventoryFolder = player:WaitForChild("Inventory")

--== GUI
local InventoryMainFrame = script.Parent.Parent
local Scrolling          = script.Parent
local EquippedSection    = Scrolling:WaitForChild("EquippedFrameSlots")
local NotEquippedSection = Scrolling:WaitForChild("NotEquippedFrameSlots")

-- Forward declaration for eqPad.  Declaring here allows it to be captured
-- by functions defined before its assignment.  The actual UIPadding will
-- be assigned later when setting up paddings for the equipped section.
local eqPad

local function findDesc(parent: Instance, name: string)
	for _,d in ipairs(parent:GetDescendants()) do
		if d.Name == name then return d end
	end
end

-- === DELETE MODE UI ===
local RemoveModeBtn = InventoryMainFrame.Parent:WaitForChild("RemoveModeBtn")
local RemoveBtn     = InventoryMainFrame.Parent:WaitForChild("RemoveBtn")

local COLOR_OFF = Color3.fromRGB(200, 60, 60)
local COLOR_ON  = Color3.fromRGB(60, 180, 90)

if RemoveBtn and RemoveBtn:IsA("TextButton") then
	RemoveBtn.Visible = false
	RemoveBtn.Active = false
	RemoveBtn.AutoButtonColor = false
	RemoveBtn.Text = "Remove 0 NFTs"
end

-- Заголовки и счётчики
local EquippedText  = findDesc(Scrolling, "EquippedText")
local EquippedCount = findDesc(Scrolling, "EquippedCount")
local NftsText      = findDesc(Scrolling, "NftsText")
	or findDesc(Scrolling, "NotEquippedText")
	or findDesc(Scrolling, "NftsTitle")
	or findDesc(Scrolling, "Nfts")

-- Tweak section titles for readability on mobile devices.
local IS_TOUCH_ONLY = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

-- хотим РАЗНЫЙ визуальный размер на телефоне и ПК
local TARGET_VIS_TOUCH = 12   -- было 14, стало чуть меньше для телефона
local TARGET_VIS_PC    = 22   -- ПК оставляем как есть

local function getNftsTextSizeFor(gui: GuiObject)
	-- телефон → меньше, ПК → больше
	if IS_TOUCH_ONLY then
		return 1    -- размер заголовка Nfts на телефоне
	else
		return 2    -- на ПК оставляем крупным
	end
end

-- высота строки заголовка; выставим ниже после расчёта шрифта
local NftsHeaderHeight = 18

-- минимальный зазор МЕЖДУ надписью Nfts и первой строкой карточек
local GAP_BELOW_NFTS = IS_TOUCH_ONLY and 2 or 0

do
	if NftsText and NftsText:IsA("TextLabel") then
		-- убираем локальные UIScale, они мешают расчётам
		for _, ch in ipairs(NftsText:GetChildren()) do
			if ch:IsA("UIScale") then
				ch:Destroy()
			end
		end

		NftsText.TextScaled     = false
		NftsText.TextWrapped    = false
		NftsText.TextXAlignment = Enum.TextXAlignment.Center
		NftsText.TextYAlignment = Enum.TextYAlignment.Center

		local sz = getNftsTextSizeFor(NftsText)
		NftsText.TextSize = sz
		NftsHeaderHeight = sz + 4

		NftsText.AnchorPoint = Vector2.new(0.5, 0)
		NftsText.Size        = UDim2.new(1, -12, 0, NftsHeaderHeight)
	end

	if EquippedText and EquippedText:IsA("TextLabel") then
		-- ВАЖНО: переноcим заголовок внутрь EquippedSection,
		-- чтобы его не трогал UIListLayout Scrolling
		EquippedText.Parent = EquippedSection

		EquippedText.TextXAlignment = Enum.TextXAlignment.Center
		EquippedText.TextYAlignment = Enum.TextYAlignment.Center
		EquippedText.AnchorPoint    = Vector2.new(0.5, 0)

		if IS_TOUCH_ONLY then
			EquippedText.Position = UDim2.new(0.5, 0, 0, 4)
			EquippedText.TextSize = 18
		else
			EquippedText.Position = UDim2.new(0.5, 0, 0, 8)
			EquippedText.TextSize = 20
		end
	end

	if EquippedCount and EquippedCount:IsA("TextLabel") then
		-- Тоже внутрь EquippedSection
		EquippedCount.Parent = EquippedSection

		EquippedCount.TextXAlignment = Enum.TextXAlignment.Center
		EquippedCount.TextYAlignment = Enum.TextYAlignment.Center
		EquippedCount.AnchorPoint    = Vector2.new(0.5, 0)

		if IS_TOUCH_ONLY then
			EquippedCount.Position = UDim2.new(0.5, 0, 0, 24)
			EquippedCount.TextSize = 16
		else
			EquippedCount.Position = UDim2.new(0.5, 0, 0, 30)
			EquippedCount.TextSize = 18
		end
	end
end


--== Buttons
local root = InventoryMainFrame.Parent
local EquipBestBtnFrame  = root:FindFirstChild("EquipBestBtnFrame")
local UnequipAllBtnFrame = root:FindFirstChild("UnequipAllBtnFrame")
local EquipBestBtn  = EquipBestBtnFrame and (EquipBestBtnFrame:FindFirstChildWhichIsA("TextButton") or EquipBestBtnFrame:FindFirstChildWhichIsA("ImageButton"))
local UnequipAllBtn = UnequipAllBtnFrame and (UnequipAllBtnFrame:FindFirstChildWhichIsA("TextButton") or UnequipAllBtnFrame:FindFirstChildWhichIsA("ImageButton"))

-- Переключатель размера сетки


--== Templates
local TemplatesFolder       = StarterGui:WaitForChild("Templates")
local NftInvFolder          = TemplatesFolder:WaitForChild("nftInv")
local InventoryNftTemplate  = NftInvFolder:WaitForChild("NftTemplate")
local HoverTemplate         = NftInvFolder:WaitForChild("HoverTemplate")

--== Remotes / optional
local EquipNftEvent         = ReplicatedStorage:WaitForChild("EquipNft")
local UnequipNftEvent       = ReplicatedStorage:WaitForChild("UnequipNft")
local GetPlayerEquipmentLvl = ReplicatedStorage:WaitForChild("GetPlayerEquipmentLvl")
local LimitChangedEvt       = ReplicatedStorage:FindFirstChild("EquipmentLimitChanged")
local UpgradeEvent          = ReplicatedStorage:FindFirstChild("UpgradeEvent")
-- [PERSIST]
local GetEquippedUuidsRF    = ReplicatedStorage:WaitForChild("GetEquippedUuids")
-- [ATOMIC]
local ApplyEquippedLayoutRF = ReplicatedStorage:WaitForChild("ApplyEquippedLayout")
-- [BULK]
local SetEquipSaveSuppressed = ReplicatedStorage:WaitForChild("SetEquipSaveSuppressed")
-- [DELETE]
local RemoveNftsEvent       = ReplicatedStorage:WaitForChild("RemoveNfts")  -- RemoteEvent: FireServer({uuid,...})

--== Demo arts (placeholders)
local Backgrounds = {
	AmberGlow={Image="rbxassetid://89279181330167"}, LightGray={Image="rbxassetid://70836522321637"},
	BeigePastel={Image="rbxassetid://84556689138245"}, BlueMist={Image="rbxassetid://77733131176452"},
	GrassCalm={Image="rbxassetid://109709010633049"}, PinkSoft={Image="rbxassetid://86250097686898"},
	TauWarm={Image="rbxassetid://99507500799188"}, CobaltHaze={Image="rbxassetid://98701422903560"},
	OliveRich={Image="rbxassetid://87527974535302"}, PeachSunset={Image="rbxassetid://88157594856294"},
	CrimsonShockWave={Image="rbxassetid://108282057624310"}, EmeraldCrystal={Image="rbxassetid://138230449200925"},
	GoldBullion={Image="rbxassetid://114110582591564"}, RubyGemstone={Image="rbxassetid://114423487852775"},
	RoyalCrown={Image="rbxassetid://139983433617444"},
}
local Crusts = {
	Default={Image="rbxassetid://101851260116571"}, Silver={Image="rbxassetid://82509111672085"},
	Gold={Image="rbxassetid://119440585844483"}, Rainbow={Image="rbxassetid://119837312413666"},
}
local Nfts = {
	PixelCat={Image="rbxassetid://107930046153111"}, PixelDog={Image="rbxassetid://119726187762456"},
	PixelBunny={Image="rbxassetid://112425592564215"}, PixelPig={Image="rbxassetid://122891807191324"},
	PixelCow={Image="rbxassetid://110566300870228"}, PixelDuck={Image="rbxassetid://132973406871511"},
	PixelChicken={Image="rbxassetid://72307131931361"}, PixelGoat={Image="rbxassetid://123305453868334"},
	PixelHorse={Image="rbxassetid://97863305799901"}, PixelRoseSheep={Image="rbxassetid://139080795020315"},
	PixelFireFly={Image="rbxassetid://136648813959069"}, PixelMagmaSlime={Image="rbxassetid://112768980639196"},
	PixelMagicBat={Image="rbxassetid://70810262682097"}, PixelMagicRaven={Image="rbxassetid://115196132043647"},
	PixelMagicCat={Image="rbxassetid://107955831819008"}, PixelMage={Image="rbxassetid://80694967413584"},
	PixelAlchemy={Image="rbxassetid://112236824047584"}, PixelKnight={Image="rbxassetid://117657482179220"},
	PixelDragon={Image="rbxassetid://70687067814146"},
	PixelFox = { Image = "rbxassetid://133416635464716" },
	PixelBunnySpirit = { Image = "rbxassetid://81591585702610" },
	PixelWolf = { Image = "rbxassetid://140579477285865" },
	PixelChipmunk  = { Image = "rbxassetid://76512183254727" },
	PixelDeerSpirit = { Image = "rbxassetid://80387279889268" },
	PixelFireFlyCreature = { Image = "rbxassetid://81727435061098" },
	PixelOwl = { Image = "rbxassetid://136018380826432" },
	PixelLynx = { Image = "rbxassetid://80658780649767" },
	PixelDeer = { Image = "rbxassetid://115695580822242" },
	PixelSumeruCat = { Image = "rbxassetid://77146495768656" },
	PixelSeagull   = { Image = "rbxassetid://109797653973041" },
	PixelCrab      = { Image = "rbxassetid://104339771003867" },
	PixelParrot    = { Image = "rbxassetid://107462676737880" },
	PixelSeashell  = { Image = "rbxassetid://118698586288757" },
	PixelPearl     = { Image = "rbxassetid://130461354855540" },
	PixelPufferFish= { Image = "rbxassetid://119086693063130" },
	PixelKoi       = { Image = "rbxassetid://107262513783864" },
	PixelCorralSpirit = { Image = "rbxassetid://134625077697021" },
	PixelGoldenDolphin= { Image = "rbxassetid://78252811169723" },
	VoxelBee = { Image = "rbxassetid://96790757788953" },
	VoxelSlime = { Image = "rbxassetid://135604688535262" },
	VoxelMushroom = { Image = "rbxassetid://120692866151507" },
	VoxelStoneGolem = { Image = "rbxassetid://91435373628433" },
	VoxelSamurai = { Image = "rbxassetid://100700860488371" },
	VoxelPhoenix = { Image = "rbxassetid://90013397769892" },
	VoxelDarkReaper = { Image = "rbxassetid://100011151539853" },
	VoxelChinaDragon = { Image = "rbxassetid://136905299367948" },
	VoxelSpirit = { Image = "rbxassetid://132325973663171" },
	VoxelDivineOverlord = { Image = "rbxassetid://129959380244107" },
}

local MAX_NFTS = 400

--== Layout / responsive
local CELL_W, CELL_H = 140, 110
local CELL_PAD       = 12
local SECTION_GAP    = 16
local V_GAP_Y        = CELL_PAD + 12

--========================================================
-- Debug
--========================================================
--========================================================
-- Debug (облегчённый, без локалов)
--========================================================
function _G.INV_LOG(...) end


--========================================================
-- Helpers
--========================================================
local function isSlot(obj: Instance): boolean
	if not obj:IsA("GuiObject") then
		return false
	end

	-- шаблон слота не считаем реальным слотом
	if obj.Name == "SlotTemplate" then
		return false
	end

	-- наши искусственные пустые элементы
	if obj:GetAttribute("IsSpacer") == true then
		return false
	end

	if obj:IsA("UIGridLayout")
		or obj:IsA("UIPadding")
		or obj:IsA("UIListLayout") then
		return false
	end

	return true
end



local function isCard(obj: Instance): boolean
	return obj:IsA("GuiObject") and obj:GetAttribute("IsNftCard") == true
end

-- Приведение секций к одному внутреннему grid-фрейму ----------------
EquippedSection.AutomaticSize    = Enum.AutomaticSize.None
NotEquippedSection.AutomaticSize = Enum.AutomaticSize.None
local function normalizeSectionToSingleGrid(section: Frame, gridName: string): Frame
	for _, ch in ipairs(section:GetChildren()) do
		if ch:IsA("Frame") and ch:FindFirstChildWhichIsA("UIGridLayout") then
			ch.Name = gridName
			ch.BackgroundTransparency = 1
			ch.Size = UDim2.new(1,0,0,0)
			ch.AutomaticSize = Enum.AutomaticSize.Y

			local pad = ch:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
			pad.Parent = ch

			if section == NotEquippedSection then
				-- NFTS (низ) — оставляем как было
				pad.PaddingLeft   = UDim.new(0, 6)
				pad.PaddingRight  = UDim.new(0, 6)
				pad.PaddingTop    = UDim.new(0, 8)
				pad.PaddingBottom = UDim.new(0, 8)
			elseif section == EquippedSection then
				-- ВАЖНО: именно здесь уменьшаем расстояние
				-- между текстом "Equipped 0/10" и слотами
				pad.PaddingTop    = UDim.new(0, 2)          -- было CELL_PAD (12)
				pad.PaddingBottom = UDim.new(0, CELL_PAD)
				pad.PaddingLeft   = UDim.new(0, CELL_PAD)
				pad.PaddingRight  = UDim.new(0, CELL_PAD)
			else
				pad.PaddingTop    = UDim.new(0, CELL_PAD)
				pad.PaddingBottom = UDim.new(0, CELL_PAD)
				pad.PaddingLeft   = UDim.new(0, CELL_PAD)
				pad.PaddingRight  = UDim.new(0, CELL_PAD)
			end

			local gl = ch:FindFirstChildWhichIsA("UIGridLayout")
			if section == EquippedSection then
				gl.CellSize = UDim2.new(0.18, 0, 0.36, 0)
			else
				gl.CellSize = UDim2.fromOffset(CELL_W, CELL_H)
			end
			gl.CellPadding = UDim2.fromOffset(CELL_PAD, V_GAP_Y)
			gl.SortOrder   = Enum.SortOrder.LayoutOrder
			gl.HorizontalAlignment = Enum.HorizontalAlignment.Left
			gl.VerticalAlignment   = Enum.VerticalAlignment.Top
			gl.FillDirectionMaxCells = 0
			return ch
		end
	end

	-- если внутри секции не нашли фрейм с гридом — создаём новый
	local sectionGrid = section:FindFirstChildWhichIsA("UIGridLayout")
	local sectionPad  = section:FindFirstChildOfClass("UIPadding")
	local grid = Instance.new("Frame")
	grid.Name = gridName
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1,0,0,0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.Parent = section

	local p = sectionPad or Instance.new("UIPadding")
	if section == NotEquippedSection then
		p.PaddingLeft   = UDim.new(0, 4)
		p.PaddingRight  = UDim.new(0, 4)
		p.PaddingTop    = UDim.new(0, 8)
		p.PaddingBottom = UDim.new(0, 8)
	elseif section == EquippedSection then
		-- тут тоже делаем маленький верхний паддинг для грид-фрейма
		p.PaddingTop    = UDim.new(0, -10)          -- было CELL_PAD
		p.PaddingBottom = UDim.new(0, CELL_PAD)
		p.PaddingLeft   = UDim.new(0, CELL_PAD)
		p.PaddingRight  = UDim.new(0, CELL_PAD)
	else
		p.PaddingTop    = UDim.new(0, CELL_PAD)
		p.PaddingBottom = UDim.new(0, CELL_PAD)
		p.PaddingLeft   = UDim.new(0, CELL_PAD)
		p.PaddingRight  = UDim.new(0, CELL_PAD)
	end
	p.Parent = grid

	local gl = sectionGrid or Instance.new("UIGridLayout")
	gl.Parent = grid
	if section == EquippedSection then
		gl.CellSize = UDim2.new(0.18, 0, 0.36, 0)
	else
		gl.CellSize = UDim2.fromOffset(CELL_W, CELL_H)
	end
	gl.CellPadding = UDim2.fromOffset(CELL_PAD, V_GAP_Y)
	gl.SortOrder   = Enum.SortOrder.LayoutOrder
	gl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	gl.VerticalAlignment   = Enum.VerticalAlignment.Top
	gl.FillDirectionMaxCells = 0

	for _, ch in ipairs(section:GetChildren()) do
		if ch ~= grid and ch:IsA("GuiObject")
			and not ch:IsA("UIListLayout") and not ch:IsA("UIPadding")
			and not (ch:IsA("TextLabel") or ch:IsA("TextButton")) then
			ch.Parent = grid
		end
	end

	return grid
end

local EquippedNftsFrame = normalizeSectionToSingleGrid(EquippedSection,    "Slots")
local NotEquippedGrid   = normalizeSectionToSingleGrid(NotEquippedSection, "Grid")

-- === Equipped grid responsive -------------------------------------------------
local EquippedGridLayout = EquippedNftsFrame:FindFirstChildWhichIsA("UIGridLayout")
EquippedGridLayout.FillDirection = Enum.FillDirection.Horizontal
EquippedGridLayout.FillDirectionMaxCells = 5
EquippedGridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
EquippedGridLayout.VerticalAlignment   = Enum.VerticalAlignment.Top
EquippedGridLayout.CellSize    = UDim2.fromOffset(100, 100)
EquippedGridLayout.CellPadding = UDim2.fromOffset(CELL_PAD, V_GAP_Y)
local function padX(frame: Frame)
	local p = frame:FindFirstChildOfClass("UIPadding")
	return (p and p.PaddingLeft.Offset or 0) + (p and p.PaddingRight.Offset or 0)
end

-- === [PATCH] Equipped grid responsive (UIScale-safe + avoid last-row single item) ==
-- === [PATCH] Equipped grid responsive (компакт для узких экранов) ==
-- === Equipped grid responsive (компакт для узких экранов) ==
local function applyResponsiveEquipped()
	if not EquippedGridLayout then return end

	-- ширина фрейма с учётом UIScale
	local sizeUnscaled = AbsUnscaled(EquippedNftsFrame)
	local outerW = math.max(0, sizeUnscaled.X)
	if outerW <= 0 then return end
	local innerW = math.max(0, outerW - padX(EquippedNftsFrame))

	-- компактный режим для телефонов
	local compact = false
	do
		local cam = workspace.CurrentCamera
		if cam then
			local vps = cam.ViewportSize
			local shorter = math.min(vps.X, vps.Y)
			compact = (shorter <= 1050)
		end
	end

	local function getMaxEquippedVisualLocal()
		local directLimit = tonumber(player:GetAttribute("EquipmentLimit"))
		if directLimit and directLimit > 0 then return directLimit end
		local lvlAttr = tonumber(player:GetAttribute("EquipmentLvl"))
		if lvlAttr and lvlAttr >= 0 then return 5 + lvlAttr end
		local lvl = tonumber(GetPlayerEquipmentLvl:InvokeServer()) or 0
		return 5 + lvl
	end

	local maxSlots = getMaxEquippedVisualLocal()
	local forceFiveCols = (maxSlots >= 5 and maxSlots <= 10)

	local chosenCols
	local chosenCell

	if compact then
		------------------------------------------------------------
		-- ТЕЛЕФОН
		------------------------------------------------------------
		local MIN_CELL = 60
		local MAX_CELL = 100

		local function solve(cols, gap)
			local totalPad = (cols - 1) * gap
			local cell = math.floor((innerW - totalPad) / cols)
			cell = math.clamp(cell, MIN_CELL, MAX_CELL)
			return cols, cell
		end

		if forceFiveCols then
			chosenCols, chosenCell = solve(math.min(5, maxSlots), 4)
		else
			for _, c in ipairs({6, 5, 4, 3}) do
				local cols, cell = solve(c, 4)
				if cell >= MIN_CELL then
					chosenCols, chosenCell = cols, cell
					break
				end
			end
			if not chosenCols then
				chosenCols, chosenCell = solve(3, 4)
			end
		end
	else
		------------------------------------------------------------
		-- ПК
		------------------------------------------------------------
		local MIN_CELL_SIZE = 60
		local FUDGE = 2

		if forceFiveCols then
			local cols = math.min(5, maxSlots)
			local hPad  = CELL_PAD * (cols - 1)
			local cell  = math.floor((innerW - hPad) / cols) - FUDGE
			if cell < MIN_CELL_SIZE then cell = MIN_CELL_SIZE end
			chosenCols, chosenCell = cols, cell
		else
			local candidates = {5, 4, 3}
			for _, c in ipairs(candidates) do
				local hPad  = CELL_PAD * (c - 1)
				local cell  = math.floor((innerW - hPad) / c) - FUDGE
				if cell >= MIN_CELL_SIZE then
					chosenCols, chosenCell = c, cell
					break
				end
			end

			if not chosenCols then
				local targetCell = 115
				local cols = math.floor((innerW + CELL_PAD) / (targetCell + CELL_PAD))
				cols = math.clamp(cols, 3, 5)

				local hPad = CELL_PAD * (cols - 1)
				local cell = math.floor((innerW - hPad) / cols) - FUDGE
				if cell < MIN_CELL_SIZE then cell = MIN_CELL_SIZE end

				chosenCols, chosenCell = cols, cell
			end
		end
	end

	if not chosenCols or not chosenCell then return end

	-- делаем слегка меньше, чтобы вписать текст и рамки
	chosenCell = math.floor(chosenCell / 1.2)
	if chosenCell < 40 then
		chosenCell = 40
	end

	local padXSlots, padYSlots
	if compact then
		padXSlots = 4
		padYSlots = 4
	else
		padXSlots = CELL_PAD
		padYSlots = V_GAP_Y
	end

	EquippedGridLayout.FillDirectionMaxCells = chosenCols
	EquippedGridLayout.CellSize    = UDim2.fromOffset(chosenCell, chosenCell)
	EquippedGridLayout.CellPadding = UDim2.fromOffset(padXSlots, padYSlots)

	-- ВАЖНО: eqPad теперь больше не трогаем здесь, чтобы не было
	-- случайных прыжков Equipped-текста относительно слотов.
end


--== Scrolling / paddings
local list = Scrolling:FindFirstChildWhichIsA("UIListLayout") or Instance.new("UIListLayout", Scrolling)
list.FillDirection = Enum.FillDirection.Vertical
list.SortOrder = Enum.SortOrder.LayoutOrder
list.HorizontalAlignment = Enum.HorizontalAlignment.Center

-- базовые значения (используем как "многорядные")
local LIST_GAP_TOUCH_MULTI = 6
local LIST_GAP_PC_MULTI    = 14
local LIST_GAP_TOUCH_SINGLE = 2
local LIST_GAP_PC_SINGLE    = 8

-- стартовое значение — как для многорядного варианта
if IS_TOUCH_ONLY then
	list.Padding = UDim.new(0, LIST_GAP_TOUCH_MULTI)
else
	list.Padding = UDim.new(0, LIST_GAP_PC_MULTI)
end

local spad = Scrolling:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding", Scrolling)
spad.PaddingLeft, spad.PaddingRight = UDim.new(0,0), UDim.new(0,0)
spad.PaddingTop,  spad.PaddingBottom= UDim.new(0,8),  UDim.new(0,8)

-- паддинг секции экипировки (отдельно)
eqPad = EquippedSection:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding", EquippedSection)
eqPad.PaddingLeft   = UDim.new(0, 0)
eqPad.PaddingRight  = UDim.new(0, 0)
eqPad.PaddingTop    = UDim.new(0, IS_TOUCH_ONLY and 10 or 10)
eqPad.PaddingBottom = UDim.new(0, IS_TOUCH_ONLY and 10 or 10)

-- === НОВОЕ: паддинги для NotEquippedSection + привязка заголовка ===
local nePad = NotEquippedSection:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding", NotEquippedSection)

-- ВОТ ЭТО — «ОГРОМНЫЙ ОТСТУП СВЕРХУ» ДЛЯ Nfts:
-- на ПК ещё больше, чем на телефоне
local NE_TOP_PAD    = IS_TOUCH_ONLY and -12 or -16
local NE_BOTTOM_PAD = 20

nePad.PaddingTop    = UDim.new(0, NE_TOP_PAD)
nePad.PaddingBottom = UDim.new(0, NE_BOTTOM_PAD)
nePad.PaddingLeft   = UDim.new(0.02, 0)
nePad.PaddingRight  = UDim.new(0.02, 0)

-- переносим NftsText внутрь NotEquippedSection, чтобы он «прилипал» к инвентарю
if NftsText then
	NftsText.Parent = NotEquippedSection
	NftsText.AnchorPoint = Vector2.new(0.5, 0)
	NftsText.Position    = UDim2.new(0.5, 0, 0, NE_TOP_PAD)
	NftsText.ZIndex      = NotEquippedSection.ZIndex + 1
end

local NotEquippedGrid = NotEquippedSection:FindFirstChild("Grid")
if not NotEquippedGrid then
	-- в твоём полном коде grid создаётся выше normalizeSectionToSingleGrid,
	-- здесь просто страховка, если вдруг порядок другой
	for _,ch in ipairs(NotEquippedSection:GetChildren()) do
		if ch:IsA("Frame") and ch:FindFirstChildWhichIsA("UIGridLayout") then
			NotEquippedGrid = ch
			break
		end
	end
end

local neGridPad = NotEquippedGrid and (NotEquippedGrid:FindFirstChildOfClass("UIPadding")
	or Instance.new("UIPadding", NotEquippedGrid))

if neGridPad then
	-- сверху у грида НОЛЬ, весь отступ и заголовок уже учли через NE_TOP_PAD + NftsHeaderHeight
	neGridPad.PaddingTop = UDim.new(0, 0)
end

if NotEquippedGrid then
	-- Грид сидит СРАЗУ под заголовком Nfts
	NotEquippedGrid.AnchorPoint = Vector2.new(0, 0)
	NotEquippedGrid.Position    = UDim2.new(0, 0, 0, NE_TOP_PAD + NftsHeaderHeight + GAP_BELOW_NFTS)
end

-- Scrolling настройки
Scrolling.AutomaticCanvasSize = Enum.AutomaticSize.None
Scrolling.ScrollingEnabled    = true
Scrolling.ScrollingDirection  = Enum.ScrollingDirection.Y
Scrolling.ScrollBarThickness  = 0

-- ===== ДАЛЬШЕ ИДЁТ ВЕСЬ ТВОЙ ОСТАЛЬНЫЙ СКРИПТ БЕЗ ИЗМЕНЕНИЙ =====
-- Hover-окно, карта карточек, виртуализация, EquipBest/UnequipAll, DeleteMode и т.д.
-- (копируй сюда остальную часть БЕЗ правок — всё, что ниже блока с паддингами
--  в твоём последнем варианте).
-- ----- ДАЛЬШЕ СКРИПТ БЕЗ ИЗМЕНЕНИЙ -----
-- (всё, что ниже, оставлено как у тебя: hover, pool, виртуализация, equip best и т.д.)

--========================================================
-- Hover
--========================================================
local function getRootScreenGui()
	local sg = InventoryMainFrame:FindFirstAncestorOfClass("ScreenGui")
	if sg then return sg end
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	return pg:FindFirstChildWhichIsA("ScreenGui") or pg
end

local RootGui = getRootScreenGui()

local HoverClone = HoverTemplate:Clone()
HoverClone.Parent = RootGui
HoverClone.Visible = false
HoverClone.Active = false
HoverClone.Selectable = false
HoverClone.ZIndex = 100000

local uiScale = Instance.new("UIScale")
uiScale.Scale = 0.78
uiScale.Parent = HoverClone

local inner = HoverClone:FindFirstChild("Frame")
local HOVER_PAD    = 6
local HOVER_OFFSET = Vector2.new(10,10)

local HoverFields = {
	Title       = inner and inner:FindFirstChild("Title"),
	Crust       = inner and inner:FindFirstChild("Crust"),
	Background  = inner and inner:FindFirstChild("Background"),
	Power       = inner and inner:FindFirstChild("Power"),
	NoOfLimited = inner and (inner:FindFirstChild("NoOfLimited") or inner:FindFirstChild("NoOflimited")),
}

if inner then
	local pad = inner:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
	pad.Parent = inner
	pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight =
		UDim.new(0,HOVER_PAD), UDim.new(0,HOVER_PAD), UDim.new(0,HOVER_PAD), UDim.new(0,HOVER_PAD)
	if HoverFields.Title and HoverFields.Title:IsA("TextLabel") then HoverFields.Title.TextSize = 20 end
	for _, name in ipairs({ "Crust", "Background", "Power", "NoOfLimited" }) do
		local lbl = HoverFields[name]
		if lbl and lbl:IsA("TextLabel") then lbl.TextSize = 16 end
	end
end
-- состояние "идёт догрузка страницы"
_isPageLoading = false

-- ... [ВСЁ ОСТАЛЬНОЕ БЕЗ ИЗМЕНЕНИЙ, КАК У ТЕБЯ ДО КОНЦА 
local function getMouseGuiPos()
	local m = UserInputService:GetMouseLocation()
	if RootGui.IgnoreGuiInset then return m end
	local inset = GuiService:GetGuiInset()
	return Vector2.new(m.X, m.Y - inset.Y)
end

local function clampToScreen(pos: Vector2, size: Vector2)
	local cam = workspace.CurrentCamera
	local vps = cam and cam.ViewportSize or Vector2.new(1920,1080)
	local maxX = math.max(0, vps.X - size.X)
	local maxY = math.max(0, vps.Y - size.Y - (RootGui.IgnoreGuiInset and 0 or GuiService:GetGuiInset().Y))
	return Vector2.new(math.clamp(pos.X, 0, maxX), math.clamp(pos.Y, 0, maxY))
end

local function positionHoverNearMouse()
	local mouse = getMouseGuiPos()
	local size  = HoverClone.AbsoluteSize
	local pos   = clampToScreen(Vector2.new(mouse.X + HOVER_OFFSET.X, mouse.Y + HOVER_OFFSET.Y), size)
	HoverClone.Position = UDim2.fromOffset(pos.X, pos.Y)
end

local function HoverFill(nftData)
	if HoverFields.Title      then HoverFields.Title.Text      = nftData.Name or "?" end
	if HoverFields.Crust      then HoverFields.Crust.Text      = "Crust: " .. tostring(nftData.Crust) end
	if HoverFields.Background then HoverFields.Background.Text = "Background: " .. tostring(nftData.Background) end
	if HoverFields.Power      then HoverFields.Power.Text      = "Power: " .. tostring(nftData.Power) end
	if HoverFields.NoOfLimited then
		local isLimited = (nftData.IsLimited == true)
		local serial = tonumber(nftData.LimitedNo or nftData.Serial or 0) or 0
		if isLimited and serial > 0 then
			HoverFields.NoOfLimited.Visible = true
			HoverFields.NoOfLimited.Text = "#" .. tostring(serial)
		else
			HoverFields.NoOfLimited.Visible = false
			HoverFields.NoOfLimited.Text = ""
		end
	end
end

-- === НОВОЕ: читаем данные для hover по uuid, а не из старого замыкания ===
local function buildNftDataFromCard(card: GuiObject)
	local uuid = card:GetAttribute("uuid") or card.Name
	local inst = uuid and inventoryFolder:FindFirstChild(uuid)

	local data = {
		uuid       = uuid,
		Name       = "?",
		Crust      = "Default",
		Background = "LightGray",
		Power      = 0,
		IsLimited  = false,
		LimitedNo  = 0,
	}

	if inst then
		data.Name       = inst:GetAttribute("Name")       or data.Name
		data.Crust      = inst:GetAttribute("Crust")      or data.Crust
		data.Background = inst:GetAttribute("Background") or data.Background
		data.Power      = tonumber(inst:GetAttribute("Power")) or data.Power
		data.IsLimited  = (inst:GetAttribute("IsLimited") == true)
		data.LimitedNo  = tonumber(inst:GetAttribute("LimitedNo")) or data.LimitedNo
	end

	return data
end

local HoverCtrl = { followConn = nil }
function HoverCtrl:show(nftData)
	HoverFill(nftData)
	HoverClone.Visible = true
	if not self.followConn then
		self.followConn = RunService.RenderStepped:Connect(function()
			if HoverClone.Visible then positionHoverNearMouse() end
		end)
	end
	positionHoverNearMouse()
end
function HoverCtrl:hide()
	HoverClone.Visible = false
	if self.followConn then self.followConn:Disconnect(); self.followConn = nil end
end

-- === НОВОЕ BindHover: без nftData, всегда тянет актуальные атрибуты по uuid ===
local function BindHover(NftClone: GuiObject)
	NftClone.MouseEnter:Connect(function()
		local nftData = buildNftDataFromCard(NftClone)
		HoverCtrl:show(nftData)
	end)

	NftClone.MouseMoved:Connect(function()
		if HoverClone.Visible then
			positionHoverNearMouse()
		end
	end)

	NftClone.MouseLeave:Connect(function()
		HoverCtrl:hide()
	end)
end

--========================================================
-- Card helpers + POWER label
--========================================================
local function normalizeCard(clone: Instance)
	for _, name in ipairs({ "Background", "Crust", "Nft", "ClickArea", "Selection" }) do
		local g = clone:FindFirstChild(name)
		if g and g:IsA("GuiObject") then
			g.AnchorPoint = Vector2.new(0.5, 0.5)
			g.Position    = UDim2.fromScale(0.5, 0.5)
			g.Size        = UDim2.fromScale(1, 1)
			g.Visible = true
			if g:IsA("ImageLabel") or g:IsA("ImageButton") then g.ImageTransparency = 0 end
		end
	end
	local stroke = clone:FindFirstChildWhichIsA("UIStroke")
	if stroke then stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border end
end
local function setNftOnlySize(card: Instance, scale: number)
	local nftImg = card:FindFirstChild("Nft")
	if nftImg and nftImg:IsA("GuiObject") then
		nftImg.AnchorPoint = Vector2.new(0.5, 0.5)
		nftImg.Position    = UDim2.fromScale(0.5, 0.5)
		nftImg.Size        = UDim2.fromScale(scale, scale)
	end
end

local function formatShort(n: number): string
	n = tonumber(n) or 0
	local a = math.abs(n)
	if a >= 1e9 then
		return (("%.1fB"):format(n/1e9)):gsub("%.0B","B")
	elseif a >= 1e6 then
		return (("%.1fM"):format(n/1e6)):gsub("%.0M","M")
	elseif a >= 1e3 then
		return (("%.1fk"):format(n/1e3)):gsub("%.0k","k")
	else
		return tostring(math.floor(n + 0.5))
	end
end

local _textBoundsCache = {}
local function _getTextBoundsCached(text, size, font)
	local key = font.Name .. "|" .. tostring(size) .. "|" .. text
	local hit = _textBoundsCache[key]
	if hit then return hit end
	local b = TextService:GetTextSize(text, size, font, Vector2.new(1000, size+6))
	_textBoundsCache[key] = b
	return b
end

local _powerCache = setmetatable({}, {__mode="k"})
local _powerSizeSubs = setmetatable({}, {__mode="k"})

local function ensurePowerLabel(card: GuiObject, powerValue: number)
	local cell = math.max(card.AbsoluteSize.X, card.AbsoluteSize.Y)
	local needDeferral = (cell <= 0)

	local lbl = card:FindFirstChild("PowerValue") :: TextLabel
	if not lbl then
		lbl = Instance.new("TextLabel")
		lbl.Name = "PowerValue"
		lbl.Parent = card
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.TextStrokeTransparency = 0
		lbl.TextXAlignment = Enum.TextXAlignment.Right
		lbl.AnchorPoint = Vector2.new(1, 1)
		lbl.ZIndex = (card.ZIndex or 1) + 5
	end

	local shadow = card:FindFirstChild("PowerShadow") :: TextLabel
	if not shadow then
		shadow = Instance.new("TextLabel")
		shadow.Name = "PowerShadow"
		shadow.Parent = card
		shadow.BackgroundTransparency = 1
		shadow.Font = lbl.Font
		shadow.TextColor3 = Color3.new(0, 0, 0)
		shadow.TextTransparency = 0.4
		shadow.TextStrokeTransparency = 1
		shadow.TextXAlignment = Enum.TextXAlignment.Right
		shadow.AnchorPoint = lbl.AnchorPoint
		shadow.ZIndex = lbl.ZIndex - 1
	end

	-- ждём пока Roblox реально создаст объект и даст размеры
	if needDeferral then
		if not _powerSizeSubs[card] then
			_powerSizeSubs[card] = {
				card:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
					if math.max(card.AbsoluteSize.X, card.AbsoluteSize.Y) > 0 then
						ensurePowerLabel(card, powerValue)
					end
				end),
				card.AncestryChanged:Connect(function()
					if not card:IsDescendantOf(game) then
						local subs = _powerSizeSubs[card]
						if subs then
							for _,c in ipairs(subs) do pcall(function() c:Disconnect() end) end
							_powerSizeSubs[card] = nil
						end
					end
				end),
			}
		end
		return
	end

	local text = formatShort(powerValue or 0)

	-- === АДАПТИВНЫЙ РАЗМЕР ТЕКСТА ПО РАЗМЕРУ КАРТОЧКИ ================
	local h = card.AbsoluteSize.Y

	-- доля высоты карточки, которую занимает текст силы
	-- на телефоне меньше, на ПК больше
	local factor = IS_TOUCH_ONLY and 0.22 or 0.29

	-- вычисляем размер текста
	local textSize = math.floor(h * factor)

	-- ограничение, чтобы не вылезало
	textSize = math.clamp(textSize, 14, math.floor(h * 0.9))
	-- =================================================================

	local cache = _powerCache[card]
	if not (cache
		and cache.text == text
		and cache.size == textSize
		and cache.w == card.AbsoluteSize.X
		and cache.h == card.AbsoluteSize.Y) then

		lbl.TextSize = textSize
		lbl.Text = text

		local bounds = _getTextBoundsCached(text, textSize, lbl.Font)
		local maxW = math.floor(card.AbsoluteSize.X * 0.97)
		lbl.Size = UDim2.fromOffset(math.min(bounds.X, maxW), textSize + 6)
		lbl.Position = UDim2.fromScale(1, 1) + UDim2.fromOffset(-6, 6)

		shadow.Text = lbl.Text
		shadow.TextSize = lbl.TextSize
		shadow.Size = lbl.Size
		shadow.Position = lbl.Position + UDim2.fromOffset(2, 3)

		_powerCache[card] = {
			w = card.AbsoluteSize.X,
			h = card.AbsoluteSize.Y,
			text = text,
			size = textSize,
		}
	end

	if not _powerSizeSubs[card] then
		_powerSizeSubs[card] = {
			card:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				ensurePowerLabel(card, powerValue)
			end),
			card.AncestryChanged:Connect(function()
				if not card:IsDescendantOf(game) then
					local subs = _powerSizeSubs[card]
					if subs then
						for _,c in ipairs(subs) do pcall(function() c:Disconnect() end) end
						_powerSizeSubs[card] = nil
					end
				end
			end),
		}
	end
end


local function ensurePowerLabelStrong(card: GuiObject, p: number)
	ensurePowerLabel(card, p)
	RunService.RenderStepped:Wait()
	if card and card.Parent then ensurePowerLabel(card, p) end
end

--========================================================
-- SERIAL LABEL (№ лимитки)
--========================================================
--========================================================
-- SERIAL LABEL (№ лимитки)
--========================================================

local _serialCache    = setmetatable({}, { __mode = "k" })
local _serialSizeSubs = setmetatable({}, { __mode = "k" })

local function ensureSerialLabel(card: GuiObject, isLimited: boolean, serial: number)
	if not card or not card:IsA("GuiObject") then
		return
	end

	serial = tonumber(serial) or 0
	isLimited = (isLimited == true) and serial > 0

	local lbl    = card:FindFirstChild("SerialLabel") :: TextLabel
	local shadow = card:FindFirstChild("SerialShadow") :: TextLabel

	-- если не лимитка → прячем и чистим
	if not isLimited then
		if lbl then
			lbl.Text = ""
			lbl.Visible = false
			lbl.Size = UDim2.fromOffset(0, 0)
		end
		if shadow then
			shadow.Text = ""
			shadow.Visible = false
			shadow.Size = UDim2.fromOffset(0, 0)
		end
		_serialCache[card] = nil
		return
	end

	-- создаём лейбл
	if not lbl then
		lbl = Instance.new("TextLabel")
		lbl.Name = "SerialLabel"
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
		lbl.TextStrokeTransparency = 0
		lbl.TextXAlignment = Enum.TextXAlignment.Center
		lbl.TextYAlignment = Enum.TextYAlignment.Top
		lbl.AnchorPoint = Vector2.new(0.5, 0)
		lbl.Position = UDim2.fromScale(0.5, 0) -- по центру сверху
		lbl.ZIndex = (card.ZIndex or 1) + 5
		lbl.Parent = card
	end

	-- создаём тень
	if not shadow then
		shadow = Instance.new("TextLabel")
		shadow.Name = "SerialShadow"
		shadow.BackgroundTransparency = 1
		shadow.Font = lbl.Font
		shadow.TextColor3 = Color3.new(0, 0, 0)
		shadow.TextTransparency = 0.4
		shadow.TextStrokeTransparency = 1
		shadow.TextXAlignment = Enum.TextXAlignment.Center
		shadow.TextYAlignment = Enum.TextYAlignment.Top
		shadow.AnchorPoint = lbl.AnchorPoint
		shadow.Position = lbl.Position + UDim2.fromOffset(1, 2)
		shadow.ZIndex = lbl.ZIndex - 1
		shadow.Parent = card
	end

	local text = "#" .. tostring(serial)
	local h    = card.AbsoluteSize.Y

	-- размер текста: покрупнее, чем раньше
	local factor   = IS_TOUCH_ONLY and 0.20 or 0.23
	local textSize = math.floor(h * factor)
	textSize = math.clamp(textSize, 14, math.floor(h * 0.45))

	local cache = _serialCache[card]
	if not cache
		or cache.text ~= text
		or cache.size ~= textSize
		or cache.h ~= h
	then
		lbl.Visible = true
		lbl.TextSize = textSize
		lbl.Text = text

		local bounds = _getTextBoundsCached(text, textSize, lbl.Font)
		local maxW   = math.floor(card.AbsoluteSize.X * 0.9)
		lbl.Size     = UDim2.fromOffset(math.min(bounds.X + 4, maxW), textSize + 4)
		lbl.Position = UDim2.fromScale(0.5, 0) + UDim2.fromOffset(0, 2)

		shadow.Visible  = true
		shadow.TextSize = textSize
		shadow.Text     = text
		shadow.Size     = lbl.Size
		shadow.Position = lbl.Position + UDim2.fromOffset(1, 2)

		_serialCache[card] = {
			text     = text,
			size     = textSize,
			h        = h,
			serial   = serial,
			isLimited = true,
		}
	end

	-- подписка на изменение размера карточки
	if not _serialSizeSubs[card] then
		_serialSizeSubs[card] = {
			card:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				local c = _serialCache[card]
				if c and c.isLimited then
					ensureSerialLabel(card, true, c.serial or 0)
				end
			end),

			card.AncestryChanged:Connect(function()
				if not card:IsDescendantOf(game) then
					local subs = _serialSizeSubs[card]
					if subs then
						for _, cn in ipairs(subs) do
							pcall(function() cn:Disconnect() end)
						end
					end
					_serialSizeSubs[card] = nil
					_serialCache[card]    = nil
				end
			end),
		}
	end
end

local function ensureSerialLabelStrong(card: GuiObject, isLimited: boolean, serial: number)
	ensureSerialLabel(card, isLimited, serial)
	RunService.RenderStepped:Wait()
	if card and card.Parent then
		ensureSerialLabel(card, isLimited, serial)
	end
end



--========================================================
-- DELETE MODE (state + visuals)
--========================================================
local removeMode = false
local selectedSet = {}
local selectedOrder = {}

local CONFIRM_SECONDS = 3.0
local _confirmArmed = false
local _confirmExpireAt: number? = nil
local _confirmConn: RBXScriptConnection? = nil

local function disarmConfirm()
	_confirmArmed = false
	_confirmExpireAt = nil
	if _confirmConn then _confirmConn:Disconnect() _confirmConn = nil end
end

local function getOrCreateDeleteOverlay(card: GuiObject)
	local overlay = card:FindFirstChild("DeleteSelectOverlay")
	if not overlay then
		overlay = Instance.new("Frame")
		overlay.Name = "DeleteSelectOverlay"
		overlay.BackgroundColor3 = Color3.fromRGB(220, 35, 35)
		overlay.BackgroundTransparency = 0.35
		overlay.BorderSizePixel = 0
		overlay.AnchorPoint = Vector2.new(0.5, 0.5)
		overlay.Position = UDim2.fromScale(0.5, 0.5)
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.ZIndex = (card.ZIndex or 1) + 4
		overlay.Visible = false
		overlay.Active = false
		overlay.Selectable = false
		overlay.Parent = card

		local stroke = Instance.new("UIStroke")
		stroke.Name = "DeleteSelectStroke"
		stroke.Color = Color3.fromRGB(255, 220, 90)
		stroke.Thickness = 4
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Transparency = 0
		stroke.Enabled = true
		stroke.ZIndex = overlay.ZIndex + 1
		stroke.Parent = overlay

		local existingCorner = card:FindFirstChildOfClass("UICorner")
		if existingCorner then
			local c = existingCorner:Clone()
			c.Parent = overlay
		end
	end
	return overlay
end

local function updateRemoveBtnText()
	if not RemoveBtn or not RemoveBtn:IsA("TextButton") then return end
	local n = #selectedOrder
	if not removeMode then
		RemoveBtn.Text = "Remove 0 NFTs"
		RemoveBtn.Active = false
		RemoveBtn.AutoButtonColor = false
		RemoveBtn.TextTransparency = 0.35
		return
	end
	if _confirmArmed then
		local txt = (n == 1) and "Are you sure you want to delete 1 NFT?" or ("Are you sure you want to delete " .. n .. " NFTs?")
		RemoveBtn.Text = txt
		RemoveBtn.Active = (n > 0)
		RemoveBtn.AutoButtonColor = (n > 0)
		RemoveBtn.TextTransparency = (n > 0) and 0 or 0.35
	else
		RemoveBtn.Text = (n == 1 and "Remove 1 NFT") or ("Remove " .. n .. " NFTs")
		RemoveBtn.Active = (n > 0)
		RemoveBtn.AutoButtonColor = (n > 0)
		RemoveBtn.TextTransparency = (n > 0) and 0 or 0.35
	end
end

local function clearSelectionVisuals()
	for _, uuid in ipairs(selectedOrder) do
		local card = NotEquippedGrid:FindFirstChild(uuid)
		if card and isCard(card) then
			local overlay = card:FindFirstChild("DeleteSelectOverlay")
			if overlay then overlay.Visible = false end
		end
	end
	table.clear(selectedSet)
	table.clear(selectedOrder)
	disarmConfirm()
	updateRemoveBtnText()
end

local function applyRemoveModeUI()
	if RemoveModeBtn then
		RemoveModeBtn.BackgroundColor3 = removeMode and COLOR_ON or COLOR_OFF
	end
	if RemoveBtn and RemoveBtn:IsA("TextButton") then
		RemoveBtn.Visible = removeMode
		RemoveBtn.Active  = removeMode and (#selectedOrder > 0)
		RemoveBtn.AutoButtonColor = (#selectedOrder > 0)
		if not removeMode then
			RemoveBtn.Text = "Remove 0 NFTs"
			RemoveBtn.TextTransparency = 0.35
		end
	end
	if not removeMode then clearSelectionVisuals() end
end

local function setRemoveMode(on: boolean)
	if removeMode == on then return end
	removeMode = on and true or false
	if not removeMode then disarmConfirm() end
	applyRemoveModeUI()
end

-- Можно ли удалять этот NFT по uuid?
local function canDeleteUuid(uuid: string): boolean
	if not uuid or uuid == "" then
		return false
	end

	-- Ищем инстанс в инвентаре
	local inst = inventoryFolder:FindFirstChild(uuid)
	if not inst then
		-- На всякий случай: если нет инстанса, НЕ даём удалить
		return false
	end

	-- 1) Запрещаем удалять лимитки
	if inst:GetAttribute("IsLimited") == true then
		return false
	end

	-- 2) Сюда же можно добавить другие флаги:
	-- if inst:GetAttribute("Locked") == true then
	--     return false
	-- end

	return true
end

local function toggleSelect(uuid: string, card: GuiObject)
	if not uuid or not card then return end

	-- НОВОЕ: если NFT нельзя удалять — просто ничего не делаем
	if not canDeleteUuid(uuid) then
		return
	end
	if card.Parent and card.Parent:IsDescendantOf(EquippedNftsFrame) then
		return
	end
	if selectedSet[uuid] then
		-- снимаем выделение
		selectedSet[uuid] = nil
		for i = #selectedOrder, 1, -1 do
			if selectedOrder[i] == uuid then
				table.remove(selectedOrder, i)
				break
			end
		end
		local overlay = card:FindFirstChild("DeleteSelectOverlay")
		if overlay then overlay.Visible = false end
	else
		-- ставим выделение
		selectedSet[uuid] = true
		table.insert(selectedOrder, uuid)
		local overlay = getOrCreateDeleteOverlay(card)
		overlay.Visible = true
	end

	disarmConfirm()
	updateRemoveBtnText()
end

--========================================================
-- Slots / counters
--========================================================
local function getMaxEquippedVisual()
	local directLimit = tonumber(player:GetAttribute("EquipmentLimit"))
	if directLimit and directLimit > 0 then return directLimit end
	local lvlAttr = tonumber(player:GetAttribute("EquipmentLvl"))
	if lvlAttr and lvlAttr >= 0 then return 5 + lvlAttr end
	local lvl = tonumber(GetPlayerEquipmentLvl:InvokeServer()) or 0
	return 5 + lvl
end
local _counterNextAt = 0

local function updateEquippedCounterDebounced(force: boolean?)
	-- force = true → игнор дебаунса (для EquipBest/UnequipAll)
	local now = tick()
	if not force and now < _counterNextAt then
		return
	end
	_counterNextAt = now + 0.05

	local equipped = 0

	for _, slot in ipairs(EquippedNftsFrame:GetChildren()) do
		if isSlot(slot) then
			local hasCard = false
			for _, ch in ipairs(slot:GetChildren()) do
				if isCard(ch) then
					hasCard = true
					break
				end
			end

			-- Всегда синкаем Occupied из реального состояния,
			-- а не наоборот.
			if slot:GetAttribute("Occupied") ~= hasCard then
				slot:SetAttribute("Occupied", hasCard)
			end

			if hasCard then
				equipped += 1
			end
		end
	end

	local maxEquipped = getMaxEquippedVisual()
	if EquippedText then
		EquippedText.Text = string.format("Equipped %d / %d", equipped, maxEquipped)
	end
	if EquippedCount then
		EquippedCount.Text = string.format("%d/%d", equipped, maxEquipped)
	end
end


local function getOrderedSlots(): {GuiObject}
	local slots = {}
	for _, ch in ipairs(EquippedNftsFrame:GetChildren()) do
		if isSlot(ch) then table.insert(slots, ch) end
	end
	table.sort(slots, function(a, b)
		local la = a.LayoutOrder or 0
		local lb = b.LayoutOrder or 0
		if la ~= lb then return la < lb end
		local na = tonumber((a.Name or ""):match("^Slot_(%d+)$")) or 1e9
		local nb = tonumber((b.Name or ""):match("^Slot_(%d+)$")) or 1e9
		if na ~= nb then return na < nb end
		return tostring(a.Name) < tostring(b.Name)
	end)
	return slots
end

local function renumberSlotsSequential()
	local slots = getOrderedSlots()
	for i, s in ipairs(slots) do
		s.LayoutOrder = i
		if s.Name:match("^Slot_%d+$") then
			s.Name = ("Slot_%d"):format(i)
		end
	end
end

local function GetFirstFreeSlot(): GuiObject?
	for _, slot in ipairs(getOrderedSlots()) do
		if slot.Visible ~= false then
			local occupied = (slot:GetAttribute("Occupied") == true)
			if not occupied then
				local hasCard = false
				for _, ch in ipairs(slot:GetChildren()) do
					if isCard(ch) then hasCard = true break end
				end
				if not hasCard then
					return slot :: GuiObject
				end
			end
		end
	end
	return nil
end

local function applyLastRowCentering()
	if not EquippedGridLayout then return end

	-- нам нужна именно 5-колоночная сетка для паттернов
	local COLS = 5
	EquippedGridLayout.FillDirectionMaxCells = COLS

	-- собираем реальные видимые слоты (без спейсеров и шаблона)
	local slots = {}
	for _, ch in ipairs(EquippedNftsFrame:GetChildren()) do
		if isSlot(ch) and ch.Visible ~= false then
			table.insert(slots, ch)
		end
	end

	table.sort(slots, function(a, b)
		local la, lb = a.LayoutOrder or 0, b.LayoutOrder or 0
		if la ~= lb then return la < lb end

		local na = tonumber((a.Name or ""):match("^Slot_(%d+)$")) or 1e9
		local nb = tonumber((b.Name or ""):match("^Slot_(%d+)$")) or 1e9
		if na ~= nb then return na < nb end

		return tostring(a.Name) < tostring(b.Name)
	end)

	-- паддинги всего фрейма слотов
	local p = EquippedNftsFrame:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding", EquippedNftsFrame)
	if IS_TOUCH_ONLY then
		p.PaddingLeft  = UDim.new(0, 0)
		p.PaddingRight = UDim.new(0, 0)
	else
		p.PaddingLeft  = UDim.new(0, 8)
		p.PaddingRight = UDim.new(0, 8)
	end

	-- удаляем старые спейсеры
	for _, ch in ipairs(EquippedNftsFrame:GetChildren()) do
		if ch:GetAttribute("IsSpacer") == true or ch.Name:match("^Spacer_c%d+") then
			ch:Destroy()
		end
	end

	local total = #slots
	if total == 0 then return end

	-- первый ряд — первые COLS слотов
	for i = 1, math.min(COLS, total) do
		local s = slots[i]
		if s then
			s.LayoutOrder = i
		end
	end

	-- если только один ряд — выходим
	if total <= COLS then return end

	-- нижний ряд: всё, что после первых COLS
	local bottom = {}
	for i = COLS + 1, total do
		table.insert(bottom, slots[i])
	end
	local n = #bottom  -- сколько слотов во второй строке

	-- === паттерн 5 + N ===
	-- startCol = сколько "пустых" колонок слева во втором ряду
	local startCol
	if total <= COLS * 2 then
		local map = {
			[1] = 2, -- 5+1: один слот по центру (3-я колонка)
			[2] = 2, -- 5+2: два слота по центру (3 и 4)  <-- ВОТ ЭТО ТЕБЕ НАДО
			[3] = 1, -- 5+3: 2..4
			[4] = 1, -- 5+4: 2..5
			[5] = 0, -- 5+5: 1..5
		}
		startCol = map[n] or math.ceil((COLS - n) / 2)
	else
		-- на всякий для диких кейсов
		startCol = math.ceil((COLS - n) / 2)
	end

	if startCol < 0 then startCol = 0 end
	if startCol > COLS - n then startCol = COLS - n end

	-- создаём спейсеры во втором ряду слева
	for c = 1, startCol do
		local spacer = Instance.new("Frame")
		spacer.Name = ("Spacer_c%d"):format(c)
		spacer.BackgroundTransparency = 1
		spacer.Size = UDim2.fromScale(1, 1)
		spacer.LayoutOrder = COLS + c
		spacer:SetAttribute("IsSpacer", true)
		spacer.Parent = EquippedNftsFrame
	end

	-- реальные слоты второго ряда
	local firstLayoutOrder = COLS + startCol + 1
	for i, s in ipairs(bottom) do
		s.LayoutOrder = firstLayoutOrder + (i - 1)
	end

	EquippedGridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	EquippedGridLayout.VerticalAlignment   = Enum.VerticalAlignment.Top
end


local function ensureSlotExistence()
	local needed = getMaxEquippedVisual()

	local slots = {}
	for _, ch in ipairs(EquippedNftsFrame:GetChildren()) do
		if isSlot(ch) then table.insert(slots, ch) end
	end
	table.sort(slots, function(a, b)
		local la = a.LayoutOrder or 0
		local lb = b.LayoutOrder or 0
		if la ~= lb then return la < lb end
		local na = tonumber((a.Name or ""):match("^Slot_(%d+)$")) or 1e9
		local nb = tonumber((b.Name or ""):match("^Slot_(%d+)$")) or 1e9
		return na < nb
	end)

	local current = #slots
	local template = EquippedNftsFrame:FindFirstChild("SlotTemplate")
	if not template then
		for _, s in ipairs(slots) do
			if s:IsA("ImageLabel") or s:IsA("Frame") then
				template = s
				break
			end
		end
	end

	if template and current < needed then
		for i = current + 1, needed do
			local newSlot = template:Clone()
			newSlot.Name = ("Slot_%d"):format(i)
			newSlot:SetAttribute("Occupied", false)
			newSlot.Visible = true
			newSlot.LayoutOrder = i
			newSlot.Parent = EquippedNftsFrame
		end
	end

	if current > needed then
		slots = {}
		for _, ch in ipairs(EquippedNftsFrame:GetChildren()) do
			if isSlot(ch) then table.insert(slots, ch) end
		end
		table.sort(slots, function(a, b)
			local la = a.LayoutOrder or 0
			local lb = b.LayoutOrder or 0
			if la ~= lb then return la < lb end
			local na = tonumber((a.Name or ""):match("^Slot_(%d+)$")) or 1e9
			local nb = tonumber((b.Name or ""):match("^Slot_(%d+)$")) or 1e9
			return na < nb
		end)

		for i = #slots, needed + 1, -1 do
			local s = slots[i]
			local occupied = false
			for _, ch in ipairs(s:GetChildren()) do
				if isCard(ch) then occupied = true break end
			end
			if not occupied then s:Destroy() end
		end
	end

	renumberSlotsSequential()
	applyLastRowCentering()
end

local function countTotalNfts(): number
	return #inventoryFolder:GetChildren()
end
local function updateNftsCounter()
	if NftsText then NftsText.Text = string.format("Nfts (%d)", countTotalNfts()) end
end

--========================================================
-- Heights & Canvas (reflow)
--========================================================
local NotEquippedLayout  = NotEquippedGrid:FindFirstChildWhichIsA("UIGridLayout")
local function getHeadersHeight(container: Instance, excludeChild: Instance? )
	local h = 0
	for _, ch in ipairs(container:GetChildren()) do
		if ch:IsA("GuiObject")
			and ch ~= excludeChild
			and not ch:IsA("UIGridLayout")
			and not ch:IsA("UIListLayout")
			and not ch:IsA("UIPadding")
			and not ch:IsA("UICorner")
			and not ch:IsA("UIStroke") then
			h += ch.AbsoluteSize.Y
		end
	end
	return h
end
local EQUIPPED_HEADER_MARGIN = 8
local NOT_EQUIPPED_HEADER_MARGIN = 6
local _reflowNextAt = 0
local _lastCanvasH  = -1
local CANVAS_BOTTOM_FUDGE = 18
local NOTEQ_BOTTOM_FUDGE  = 8

-- === [PATCH] scheduleReflow (UIScale‑safe) =========================
local function scheduleReflow()
	local now = tick()
	if now < _reflowNextAt then return end
	_reflowNextAt = now + 0.05

	local gl        = NotEquippedLayout
	local contentY  = gl and gl.AbsoluteContentSize.Y or 0
	local headersH  = getHeadersHeight(NotEquippedSection, NotEquippedGrid)
	local pad       = NotEquippedSection:FindFirstChildOfClass("UIPadding")
	local padY      = pad and (pad.PaddingTop.Offset + pad.PaddingBottom.Offset) or 0
	local notEqH    = math.ceil(headersH + NOT_EQUIPPED_HEADER_MARGIN + contentY + padY + NOTEQ_BOTTOM_FUDGE)
	NotEquippedSection.Size = UDim2.new(1,0,0, notEqH)

	local sp        = Scrolling:FindFirstChildOfClass("UIPadding")
	local extra     = sp and (sp.PaddingTop.Offset + sp.PaddingBottom.Offset) or 0
	local listH     = list and list.AbsoluteContentSize.Y
		or (EquippedSection.AbsoluteSize.Y + NotEquippedSection.AbsoluteSize.Y)

	local totalH = math.ceil(listH + extra + CANVAS_BOTTOM_FUDGE)
	if totalH ~= _lastCanvasH then
		_lastCanvasH = totalH
		Scrolling.CanvasSize = UDim2.fromOffset(0, totalH)
	end
end

-- ===================================================================

-- === [PATCH] Recompute equipped height (UIScale‑safe) ==============
local function recomputeEquippedHeight()
	-- сначала подгоняем сетку под ширину экрана
	applyResponsiveEquipped()

	local gl = EquippedGridLayout
	if not gl then return end

	local innerPad = EquippedNftsFrame:FindFirstChildOfClass("UIPadding")
	local padY = innerPad and (innerPad.PaddingTop.Offset + innerPad.PaddingBottom.Offset) or 0
	local headersH = getHeadersHeight(EquippedSection, EquippedNftsFrame)

	-- считаем количество колонок и рядов по лимиту экипировки
	local cols  = math.max(1, gl.FillDirectionMaxCells or 5)
	local limit = getMaxEquippedVisual()
	local rows  = math.max(1, math.ceil(limit / cols))

	-- высота грида
	local gridH = gl.AbsoluteContentSize.Y or 0
	if gridH <= 0 then
		local cell  = (gl.CellSize.Y.Offset ~= 0) and gl.CellSize.Y.Offset or 100
		gridH = rows * cell + (rows - 1) * V_GAP_Y
	end

	local FUDGE = 8
	local target = headersH + padY + gridH + EQUIPPED_HEADER_MARGIN + FUDGE
	EquippedSection.Size = UDim2.new(1, 0, 0, math.ceil(target))

	-- === НОВОЕ: динамический зазор между Equipped-секцией и Nfts ===
	local gap
	if rows <= 1 then
		-- когда 1 ряд слотов — секции поджимаем друг к другу
		if IS_TOUCH_ONLY then
			gap = LIST_GAP_TOUCH_SINGLE
		else
			gap = LIST_GAP_PC_SINGLE
		end
	else
		-- при 2+ рядах оставляем более крупный зазор
		if IS_TOUCH_ONLY then
			gap = LIST_GAP_TOUCH_MULTI
		else
			gap = LIST_GAP_PC_MULTI
		end
	end
	list.Padding = UDim.new(0, gap)

	applyLastRowCentering()
end


-- ===================================================================

local function updateCanvasImpl()
	-- пока идёт догрузка страницы, не трогаем CanvasSize
	-- чтобы низ списка не прыгал и новые карточки не "подползали"
	if _isPageLoading then
		return
	end

	scheduleReflow()
end

local function updateSectionHeightsImpl() recomputeEquippedHeight() scheduleReflow() end
_G.__updateCanvas, _G.__updateSectionHeights = updateCanvasImpl, updateSectionHeightsImpl

task.spawn(function()
	for _=1, 4 do
		RunService.RenderStepped:Wait()
		recomputeEquippedHeight()
		scheduleReflow()
	end
end)

--========================================================
-- Not‑equipped grid responsive (adaptive columns)
--========================================================
local LIST_PAD    = 12        -- расстояние между ячейками
local MIN_CELL    = 70        -- минимальный размер слота (px)
local MAX_CELL    = 140       -- максимальный размер слота (px)
local MIN_COLS    = 4         -- lower bound for columns (prefer more on mobile)
local MAX_COLS    = 7         -- upper bound for columns
local FUDGE_LOWER = 2

local function padX_section(frame: Frame)
	local p = frame:FindFirstChildOfClass("UIPadding")
	return (p and p.PaddingLeft.Offset or 0) + (p and p.PaddingRight.Offset or 0)
end
local NotEquippedLayoutRef  = NotEquippedGrid:FindFirstChildWhichIsA("UIGridLayout")

-- === [PATCH] Not‑equipped grid responsive (UIScale‑safe + adaptive) =
-- === [PATCH] Not-equipped grid responsive (UIScale-safe + adaptive + 2 режима) =
-- === Not-equipped grid responsive (UIScale-safe + adaptive + 2 режима) =

-- === Not-equipped grid responsive (UIScale-safe + режим "big/small") ===
local function applyResponsiveNotEquipped()
	if not NotEquippedLayoutRef or not NotEquippedGrid then return end

	-- ширина грида БЕЗ учёта UIScale
	local gridSize    = AbsUnscaled(NotEquippedGrid)
	local sectionPadX = padX_section(NotEquippedSection)
	local gridPadX    = padX_section(NotEquippedGrid)
	local gridWidth   = math.max(0, gridSize.X - sectionPadX - gridPadX)
	if gridWidth <= 0 then return end

	-- режим:
	--  "big"   = стартовый, как было изначально (твой текущий размер)
	--  "small" = уменьшенная, более плотная сетка
	local mode = root:GetAttribute("GridMode") or "big"

	local pad, minCell, maxCell, minCols, maxCols, targetCell

	if mode == "small" then
		-- МЕЛКАЯ/ПЛОТНАЯ сетка
		pad        = 8          -- чуть меньше паддинги
		minCell    = 50         -- меньше минимальный размер
		maxCell    = 100
		minCols    = 5          -- стараемся влезть больше колонок
		maxCols    = 10
		targetCell = 70         -- целевой размер клетки поменьше
	else
		-- BIG: твой ИСХОДНЫЙ вариант (LIST_PAD, MIN_CELL и т.д.)
		pad        = LIST_PAD
		minCell    = MIN_CELL
		maxCell    = MAX_CELL
		minCols    = MIN_COLS
		maxCols    = MAX_COLS
		targetCell = 100
	end

	-- считаем количество колонок
	local cols = math.floor((gridWidth + pad) / (targetCell + pad))
	cols = math.clamp(cols, minCols, maxCols)

	-- реальный размер клетки
	local rawCell = (gridWidth - (cols - 1) * pad) / cols
	local cell    = math.floor(rawCell) - FUDGE_LOWER
	cell = math.clamp(cell, minCell, maxCell)

	NotEquippedLayoutRef.FillDirectionMaxCells = cols
	NotEquippedLayoutRef.HorizontalAlignment   = Enum.HorizontalAlignment.Center
	NotEquippedLayoutRef.VerticalAlignment     = Enum.VerticalAlignment.Top
	NotEquippedLayoutRef.CellPadding           = UDim2.fromOffset(pad, pad)
	NotEquippedLayoutRef.CellSize              = UDim2.fromOffset(cell, cell)

	_G.__updateCanvas()
end


-- ===================================================================

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		applyResponsiveEquipped()
		applyResponsiveNotEquipped()
		recomputeEquippedHeight()
		_G.__updateCanvas()
	end)
end

NotEquippedSection:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	applyResponsiveNotEquipped()
	_G.__updateCanvas()
end)
NotEquippedGrid:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	_G.__updateCanvas()
end)
EquippedNftsFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	recomputeEquippedHeight()
	_G.__updateCanvas()
end)

--========================================================
-- CARD POOL
--========================================================
local CARD_POOL_SIZE   = 64
local CardPoolFree     = {}
local _connMap = setmetatable({}, { __mode = "k" })
local function revealNewCardsBatch()
	if not NotEquippedGrid then return end

	for _, ch in ipairs(NotEquippedGrid:GetChildren()) do
		if isCard(ch) and ch:GetAttribute("IsNewCard") then
			ch.Visible = true
			ch:SetAttribute("IsNewCard", nil)
		end
	end
end

-- === LOADING OVERLAY ДЛЯ ДОГРУЗКИ СТРАНИЦ ==============================

_isPageLoading = false

local function getLoadingOverlay()
	if LoadingOverlay and LoadingOverlay.Parent then
		return LoadingOverlay
	end

	-- используем тот же RootGui, что и для hover
	local gui = RootGui or getRootScreenGui()

	local f = Instance.new("Frame")
	f.Name = "InventoryLoadingOverlay"
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BackgroundTransparency = 0.35
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromOffset(220, 80)
	f.Visible = false
	f.ZIndex = 100002
	f.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = f

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Text"
	lbl.BackgroundTransparency = 1
	lbl.AnchorPoint = Vector2.new(0.5, 0.5)
	lbl.Position = UDim2.fromScale(0.5, 0.5)
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.TextSize = 18
	lbl.Text = "Loading NFTs..."
	lbl.ZIndex = f.ZIndex + 1
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.Parent = f

	LoadingOverlay = f
	return f
end

local function showLoadingOverlay()
	local f = getLoadingOverlay()
	f.Visible = true
end

local function hideLoadingOverlay()
	if LoadingOverlay then
		LoadingOverlay.Visible = false
	end
end

local function __disconnectAll(conns)
	if not conns then return end
	for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	table.clear(conns)
end
local function __wipeCard(card: Instance)
	-- чистим картинки
	if card:FindFirstChild("Background") then
		card.Background.Image = ""
	end
	if card:FindFirstChild("Crust") then
		card.Crust.Image = ""
	end
	if card:FindFirstChild("Nft") then
		card.Nft.Image = ""
	end

	-- сбрасываем базу
	card.Parent = nil
	card.AnchorPoint = Vector2.new(0, 0)
	card.Position    = UDim2.new()
	card.Size        = UDim2.fromScale(1, 1)
	card.LayoutOrder = 0
	card:SetAttribute("uuid", nil)
	card:SetAttribute("IsNftCard", true)

	-- сбрасываем флаг «новая карта» и прячем её
	card:SetAttribute("IsNewCard", nil)
	card.Visible = false

	-- power-лейбл
	local lbl = card:FindFirstChild("PowerValue")
	if lbl and lbl:IsA("TextLabel") then
		lbl.Text = ""
		lbl.Size = UDim2.fromOffset(0, 0)
	end
	local sh = card:FindFirstChild("PowerShadow")
	if sh and sh:IsA("TextLabel") then
		sh.Text = ""
		sh.Size = UDim2.fromOffset(0, 0)
	end

	-- серийник лимитки
	local sl = card:FindFirstChild("SerialLabel")
	if sl and sl:IsA("TextLabel") then
		sl.Text = ""
		sl.Visible = false
		sl.Size = UDim2.fromOffset(0, 0)
	end
	local ss = card:FindFirstChild("SerialShadow")
	if ss and ss:IsA("TextLabel") then
		ss.Text = ""
		ss.Visible = false
		ss.Size = UDim2.fromOffset(0, 0)
	end

	-- overlay delete-режима
	local ov = card:FindFirstChild("DeleteSelectOverlay")
	if ov then
		ov.Visible = false
	end

	-- коннекты
	if _connMap[card] then
		__disconnectAll(_connMap[card])
		_connMap[card] = nil
	end
end

local function AcquireCard(): GuiObject
	local card = table.remove(CardPoolFree)
	if card then return card end

	card = InventoryNftTemplate:Clone()
	card.Name = "PooledCard"
	card:SetAttribute("IsNftCard", true)
	normalizeCard(card)
	setNftOnlySize(card, 0.8)

	_connMap[card] = {}
	-- Hover connections are attached once when the card is created.
	BindHover(card)

	return card
end
local function ReleaseCard(card: GuiObject)
	if not card then return end
	__wipeCard(card)
	table.insert(CardPoolFree, card)
end
task.spawn(function()
	for _=1, CARD_POOL_SIZE do
		local c = AcquireCard()
		ReleaseCard(c)
		task.wait()
	end
end)

--========================================================
-- Queue (budgeted)
--========================================================
local Q_ADD, Q_REMOVE = {}, {}
local workerActive = false
local TARGET_BUDGET_SEC = 0.003 -- slightly wider budget, fewer frames

local function softReflow()
	_G.__updateCanvas()
end

--========================= ADD =========================
local function getPowerForUuid(uuid: string): number
	local inst = inventoryFolder:FindFirstChild(uuid)
	return tonumber(inst and inst:GetAttribute("Power")) or 0
end
local function syncLayoutToServer()
	-- Собираем текущий порядок из слотов
	local slots = {}
	for _, ch in ipairs(EquippedNftsFrame:GetChildren()) do
		if isSlot(ch) then table.insert(slots, ch) end
	end
	table.sort(slots, function(a, b)
		return (a.LayoutOrder or 0) < (b.LayoutOrder or 0)
	end)

	local desired = {}
	for _, s in ipairs(slots) do
		for _, kid in ipairs(s:GetChildren()) do
			if isCard(kid) then
				table.insert(desired, kid.Name)
			end
		end
	end

	local ok, res = pcall(function()
		return ApplyEquippedLayoutRF:InvokeServer(desired)
	end)
	if not ok or not res or res.ok ~= true then
		warn("[INV] ApplyEquippedLayout(sync) failed", ok, res and res.err)
	end
end
local function AddNftCard(inst: Instance)
	local uuid = inst.Name

	-- уже есть в NotEquipped
	if NotEquippedGrid:FindFirstChild(uuid) then
		return
	end

	-- или уже сидит в одном из слотов
	for _, slot in ipairs(EquippedNftsFrame:GetChildren()) do
		if isSlot(slot) then
			for _, ch in ipairs(slot:GetChildren()) do
				if isCard(ch) and ch.Name == uuid then
					return
				end
			end
		end
	end

	-- собираем данные NFT
	local nftData = {
		uuid       = uuid,
		Name       = inst:GetAttribute("Name"),
		Crust      = inst:GetAttribute("Crust"),
		Background = inst:GetAttribute("Background"),
		Power      = tonumber(inst:GetAttribute("Power")) or 0,
		IsLimited  = (inst:GetAttribute("IsLimited") == true),
		LimitedNo  = tonumber(inst:GetAttribute("LimitedNo")) or 0,
	}

	-- берём карточку из пула
	local card = AcquireCard()
	card.Name = uuid
	card:SetAttribute("uuid", uuid)
	card:SetAttribute("IsNftCard", true)

	-- применяем картинки
	local bg = Backgrounds[nftData.Background]
	local cr = Crusts[nftData.Crust]
	local im = Nfts[nftData.Name]

	if card:FindFirstChild("Background") then
		card.Background.Visible = true
		card.Background.ImageTransparency = 0
		card.Background.Image = (bg and bg.Image) or ""
	end
	if card:FindFirstChild("Crust") then
		card.Crust.Visible = true
		card.Crust.ImageTransparency = 0
		card.Crust.Image = (cr and cr.Image) or ""
	end
	if card:FindFirstChild("Nft") then
		card.Nft.Visible = true
		card.Nft.ImageTransparency = 0
		card.Nft.Image = (im and im.Image) or ""
	end

	card.Size = UDim2.fromScale(1, 1)
	card.LayoutOrder = -(nftData.Power or 0)
	card.Parent = NotEquippedGrid

	-- тут: карта считается «новой» и скрытой, пока не коммитнем пачку
	card.Visible = false
	card:SetAttribute("IsNewCard", true)

	-- подписи: сила + серийный номер лимитки
	ensurePowerLabelStrong(card, nftData.Power)
	ensureSerialLabelStrong(card, nftData.IsLimited, nftData.LimitedNo)

	-- клики / коннекты
	local conns = _connMap[card] or {}
	__disconnectAll(conns)
	conns = {}

	local clickable = card:FindFirstChild("ClickArea")

	local function toggleEquip(cardRef: GuiObject)
		local id = cardRef:GetAttribute("uuid") or cardRef.Name
		local inEquipped = cardRef.Parent and cardRef.Parent:IsDescendantOf(EquippedNftsFrame)

		if inEquipped then
			-- UNEQUIP
			local slot = cardRef.Parent
			if slot and isSlot(slot) then
				slot:SetAttribute("Occupied", false)
			end
			cardRef:SetAttribute("EquippedSlotName", nil)
			cardRef.Parent = NotEquippedGrid
			cardRef.AnchorPoint = Vector2.new(0, 0)
			cardRef.Position = UDim2.new()
			cardRef.Size     = UDim2.fromScale(1, 1)
			setNftOnlySize(cardRef, 0.8)

			-- сервер: снимаем
			UnequipNftEvent:FireServer(id)

			-- в гриде карта может быть скрыта до батча → видимость ей выставит revealNewCardsBatch
		else
			-- EQUIP
			local free = GetFirstFreeSlot()
			if not free then return end

			free:SetAttribute("Occupied", true)
			cardRef:SetAttribute("EquippedSlotName", free.Name)
			cardRef.Parent = free
			cardRef.AnchorPoint = Vector2.new(0.5, 0.5)
			cardRef.Position    = UDim2.fromScale(0.5, 0.5)
			cardRef.Size        = UDim2.fromScale(1, 1)
			setNftOnlySize(cardRef, 0.8)

			-- сервер: экипируем
			EquipNftEvent:FireServer(id)

			-- в слоте всегда должно быть видно сразу
			cardRef.Visible = true
		end

		-- локальные счётчики/рефлоу
		updateEquippedCounterDebounced()
		softReflow()

		-- НОВОЕ: после любого изменения раскладки синкаем её на сервер,
		-- чтобы EquipLayoutDS и _equippedLayout[player] всегда совпадали
		syncLayoutToServer()
	end


	local function onPrimaryClick()
		if removeMode then
			toggleSelect(uuid, card)
		else
			toggleEquip(card)
		end
	end

	if clickable and clickable:IsA("GuiButton") then
		table.insert(conns, clickable.MouseButton1Click:Connect(onPrimaryClick))
	else
		table.insert(conns, card.InputBegan:Connect(function(input)
			if input.UserInputType.Name == "MouseButton1" then
				onPrimaryClick()
			end
		end))
	end

	-- реакция на изменение атрибутов инстанса
	table.insert(conns, inst.AttributeChanged:Connect(function(attr)
		if not card.Parent then return end

		if attr == "Power" then
			local p = tonumber(inst:GetAttribute("Power")) or 0
			card.LayoutOrder = -p
			ensurePowerLabelStrong(card, p)

		elseif attr == "Name" or attr == "Crust" or attr == "Background" then
			local bg2 = Backgrounds[tostring(inst:GetAttribute("Background"))]
			local cr2 = Crusts[tostring(inst:GetAttribute("Crust"))]
			local im2 = Nfts[tostring(inst:GetAttribute("Name"))]

			if card:FindFirstChild("Background") then
				card.Background.Image = (bg2 and bg2.Image) or ""
			end
			if card:FindFirstChild("Crust") then
				card.Crust.Image = (cr2 and cr2.Image) or ""
			end
			if card:FindFirstChild("Nft") then
				card.Nft.Image = (im2 and im2.Image) or ""
			end

		elseif attr == "IsLimited" or attr == "LimitedNo" then
			local isLimited = (inst:GetAttribute("IsLimited") == true)
			local serial = tonumber(inst:GetAttribute("LimitedNo")) or 0
			ensureSerialLabelStrong(card, isLimited, serial)
		end
	end))

	_connMap[card] = conns
end

local function RemoveNftCard(inst: Instance)
	local ui = NotEquippedGrid:FindFirstChild(inst.Name)
	if ui and ui:IsA("GuiObject") then
		ReleaseCard(ui)
	end
	softReflow()
end

local function runWorkerBudgeted()
	while (#Q_ADD > 0 or #Q_REMOVE > 0) do
		local frameStart = os.clock()
		if #Q_REMOVE > 0 then
			local inst = table.remove(Q_REMOVE, 1)
			RemoveNftCard(inst)
		elseif #Q_ADD > 0 then
			local inst = table.remove(Q_ADD, 1)
			AddNftCard(inst)
		end
		updateEquippedCounterDebounced()
		if (os.clock() - frameStart) >= TARGET_BUDGET_SEC then
			RunService.Heartbeat:Wait()
		end
	end
end

local function scheduleQueue()
	if workerActive then return end
	workerActive = true
	task.spawn(function()
		while (#Q_ADD > 0 or #Q_REMOVE > 0) do
			runWorkerBudgeted()
			RunService.Heartbeat:Wait()
		end
		workerActive = false

		-- К этому моменту ВСЕ новые карты созданы → открываем их пачкой
		revealNewCardsBatch()
		_G.__updateCanvas()
	end)
end


-- Ждём, пока очередь отрисовки карточек полностью отработает,
-- и только потом скрываем оверлей.
local function waitQueueAndHideOverlay()
	task.spawn(function()
		-- ждём, пока воркер дорисует все карточки из очереди
		while workerActive or #Q_ADD > 0 or #Q_REMOVE > 0 do
			RunService.Heartbeat:Wait()
		end

		hideLoadingOverlay()
		_isPageLoading = false

		-- ВАЖНО: после первой загрузки показываем грид с NFT
		if NotEquippedGrid then
			NotEquippedGrid.Visible = true
		end

		-- теперь можно один раз обновить CanvasSize и увидеть новую партию
		_G.__updateCanvas()
	end)
end

--========================================================
-- VIRTUALIZATION + FAST SORT CORE
--========================================================
local VISIBLE_LIMIT_START = 56
local PAGE_STEP           = 28
local VISIBLE_LIMIT       = VISIBLE_LIMIT_START

-- rec = { uuid, power, name, ref }
local AllSorted = {}
local IndexByUuid = {}
local VisibleSet  = {}

local function powerOf(inst: Instance) return tonumber(inst:GetAttribute("Power")) or 0 end

local function isEquippedUuid(uuid: string)
	for _, slot in ipairs(EquippedNftsFrame:GetChildren()) do
		if isSlot(slot) then
			for _, ch in ipairs(slot:GetChildren()) do
				if isCard(ch) and ch.Name == uuid then return true end
			end
		end
	end
	return false
end

-- === FAST RANK (descending by power, then uuid) ===
local function less(a,b)
	if a.power ~= b.power then return a.power > b.power end
	return tostring(a.uuid) < tostring(b.uuid)
end

local function rebuildAllSorted()
	AllSorted, IndexByUuid = {}, {}
	for _, child in ipairs(inventoryFolder:GetChildren()) do
		if not isEquippedUuid(child.Name) then
			table.insert(AllSorted, { uuid = child.Name, power = powerOf(child), name = child:GetAttribute("Name"), ref = child })
		end
	end
	table.sort(AllSorted, less)
	for i, rec in ipairs(AllSorted) do IndexByUuid[rec.uuid] = i end
end

local function ensureVisibleWindow(limit: number)
	limit = math.min(limit, #AllSorted)
	for i = 1, limit do
		local rec = AllSorted[i]
		if rec and not VisibleSet[rec.uuid] then
			if not NotEquippedGrid:FindFirstChild(rec.uuid) then
				table.insert(Q_ADD, rec.ref)
			end
			VisibleSet[rec.uuid] = true
		end
	end
	for uuid, _ in pairs(VisibleSet) do
		local pos = IndexByUuid[uuid] or math.huge
		if pos > limit then
			local ui = NotEquippedGrid:FindFirstChild(uuid)
			if ui then ReleaseCard(ui) end
			VisibleSet[uuid] = nil
		end
	end
	scheduleQueue()
	_G.__updateCanvas()
end

local function refreshWindowAfterEquipChange()
	-- Quick filter: remove items that became equipped without a full rebuild
	for i = #AllSorted, 1, -1 do
		local rec = AllSorted[i]
		if isEquippedUuid(rec.uuid) then
			table.remove(AllSorted, i)
			IndexByUuid[rec.uuid] = nil
			local ui = NotEquippedGrid:FindFirstChild(rec.uuid)
			if ui then ReleaseCard(ui) end
			VisibleSet[rec.uuid] = nil
		end
	end
	for i, rec in ipairs(AllSorted) do IndexByUuid[rec.uuid] = i end
	ensureVisibleWindow(VISIBLE_LIMIT)
	_G.__updateCanvas()
end

--========================================================
-- BULK‑REPLICATE DETECTOR (главный буст)
--========================================================
local bulk = {
	inProgress = false,
	events = 0,
	lastAt = 0,
	QUIET = 0.12,     -- silence after which we consider things stable
	MAX_WAIT = 0.6,   -- maximum hold time before applying changes
	threshold = 15,   -- >=15 events in a row means a bulk operation
	timerOn = false,
}

local function beginBulk()
	if bulk.inProgress then return end
	bulk.inProgress = true
	bulk.events = 0
	bulk.lastAt = tick()
	-- Hide the grid during a flood of events to avoid layout thrashing
	NotEquippedGrid.Visible = false
end

local function endBulkApply(fullRescan: boolean)
	-- One single rebuild and window update
	if fullRescan then
		rebuildAllSorted()
	else
		rebuildAllSorted()
	end
	ensureVisibleWindow(VISIBLE_LIMIT)
	NotEquippedGrid.Visible = true
	_G.__updateCanvas()
	bulk.inProgress = false
	bulk.timerOn = false
end

local function pokeBulkTimer()
	if bulk.timerOn then return end
	bulk.timerOn = true
	task.spawn(function()
		local started = tick()
		while true do
			local idle = tick() - bulk.lastAt
			if idle >= bulk.QUIET or (tick() - started) >= bulk.MAX_WAIT then
				break
			end
			task.wait(0.03)
		end
		endBulkApply(true)
	end)
end

--========================================================
-- Scroll helpers + paging
--========================================================
local lastCanvasPosY = 0
local SCROLL_LOAD_MARGIN = 2*CELL_H
local function nearBottom()
	local viewportH = Scrolling.AbsoluteSize.Y
	local bottomY   = Scrolling.CanvasPosition.Y + viewportH
	local canvasH   = Scrolling.CanvasSize.Y.Offset
	return bottomY + SCROLL_LOAD_MARGIN >= canvasH
end
local function virtTryLoadMoreByScroll()
	-- всё уже загружено
	if #AllSorted <= VISIBLE_LIMIT then return end
	-- уже загружаем следующую страницу
	if _isPageLoading then return end
	-- реально приблизились к низу
	if nearBottom() then
		VISIBLE_LIMIT = math.min(#AllSorted, VISIBLE_LIMIT + PAGE_STEP)

		_isPageLoading = true
		showLoadingOverlay()

		-- подтягиваем ещё записи в окно видимости
		-- внутри ensureVisibleWindow уже будет вызван _G.__updateCanvas(),
		-- но из-за _isPageLoading updateCanvasImpl сейчас просто ничего не сделает.
		ensureVisibleWindow(VISIBLE_LIMIT)

		-- дожидаемся, пока очередь дорисует все карточки, и только потом обновляем Canvas
		waitQueueAndHideOverlay()
	end
end


Scrolling:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
	local y = Scrolling.CanvasPosition.Y
	if y > lastCanvasPosY + 4 then end
	lastCanvasPosY = y
	virtTryLoadMoreByScroll()
end)

--========================================================
-- Live capacity refresh
--========================================================
local function _refreshCapacity()
	ensureSlotExistence()
	recomputeEquippedHeight()
	updateEquippedCounterDebounced()
	_G.__updateCanvas()
end
player:GetAttributeChangedSignal("EquipmentLimit"):Connect(function() _refreshCapacity() end)
player:GetAttributeChangedSignal("EquipmentLvl"):Connect(function() _refreshCapacity() end)
if LimitChangedEvt and LimitChangedEvt:IsA("RemoteEvent") then
	LimitChangedEvt.OnClientEvent:Connect(function() _refreshCapacity() end)
end
task.defer(function()
	local upg = player:FindFirstChild("PlayerUpgrades")
	if upg then
		local lvl = upg:FindFirstChild("PlayerEquipmentUpgradeLvl")
		if lvl and lvl:IsA("IntValue") then
			lvl:GetPropertyChangedSignal("Value"):Connect(function() _refreshCapacity() end)
		end
	end
end)
if UpgradeEvent and UpgradeEvent:IsA("RemoteEvent") then
	UpgradeEvent.OnClientEvent:Connect(function() _refreshCapacity() end)
end

--========================================================
-- ChildAdded/Removed — through buffer and burst detector
--========================================================
inventoryFolder.ChildAdded:Connect(function(child)
	bulk.events += 1
	bulk.lastAt = tick()
	if not bulk.inProgress and bulk.events >= bulk.threshold then
		beginBulk()
	end

	if bulk.inProgress then
		pokeBulkTimer()
		return
	end

	rebuildAllSorted()
	ensureVisibleWindow(VISIBLE_LIMIT)
	updateNftsCounter()
	_G.__updateCanvas()
end)

inventoryFolder.ChildRemoved:Connect(function(child)
	bulk.events += 1
	bulk.lastAt = tick()
	if not bulk.inProgress and bulk.events >= bulk.threshold then
		beginBulk()
	end

	if bulk.inProgress then
		pokeBulkTimer()
		return
	end

	rebuildAllSorted()
	ensureVisibleWindow(VISIBLE_LIMIT)
	updateNftsCounter()
	_G.__updateCanvas()
end)

--========================================================
-- Init
--========================================================
ensureSlotExistence()
for _, slot in ipairs(EquippedNftsFrame:GetChildren()) do
	if isSlot(slot) then
		slot.ChildAdded:Connect(function()
			updateEquippedCounterDebounced()
			refreshWindowAfterEquipChange()
		end)
		slot.ChildRemoved:Connect(function()
			updateEquippedCounterDebounced()
			refreshWindowAfterEquipChange()
		end)
	end
end

updateEquippedCounterDebounced()
updateNftsCounter()

rebuildAllSorted()
VISIBLE_LIMIT = math.min(VISIBLE_LIMIT_START, #AllSorted)

_isPageLoading = true
showLoadingOverlay()
if NotEquippedGrid then
	NotEquippedGrid.Visible = false
end

ensureVisibleWindow(VISIBLE_LIMIT)
waitQueueAndHideOverlay()

local NotEquippedLayout2  = NotEquippedGrid:FindFirstChildWhichIsA("UIGridLayout")
local EquippedGridLayout2 = EquippedNftsFrame:FindFirstChildWhichIsA("UIGridLayout")
applyResponsiveNotEquipped()
recomputeEquippedHeight()
scheduleReflow()

-- === Переключатель размера сетки (ChangeGridBtn) ===
local ModuleContext = {
        Inv = Inv,
        root = root,
        player = player,
        NotEquippedGrid = NotEquippedGrid,
        EquippedNftsFrame = EquippedNftsFrame,
        applyResponsiveNotEquipped = applyResponsiveNotEquipped,
        scheduleReflow = scheduleReflow,
        isSlot = isSlot,
        isCard = isCard,
        IndexByUuid = IndexByUuid,
        VISIBLE_LIMIT = VISIBLE_LIMIT,
        inventoryFolder = inventoryFolder,
        Q_ADD = Q_ADD,
        scheduleQueue = scheduleQueue,
        setNftOnlySize = setNftOnlySize,
        ensurePowerLabelStrong = ensurePowerLabelStrong,
        getPowerForUuid = getPowerForUuid,
        GetFirstFreeSlot = GetFirstFreeSlot,
        updateEquippedCounterDebounced = updateEquippedCounterDebounced,
        applyLastRowCentering = applyLastRowCentering,
        EquipNftEvent = EquipNftEvent,
        UnequipNftEvent = UnequipNftEvent,
        ApplyEquippedLayoutRF = ApplyEquippedLayoutRF,
        refreshWindowAfterEquipChange = refreshWindowAfterEquipChange,
        SetEquipSaveSuppressed = SetEquipSaveSuppressed,
        GetPlayerEquipmentLvl = GetPlayerEquipmentLvl,
        powerOf = powerOf,
        ensureSlotExistence = ensureSlotExistence,
        AddNftCard = AddNftCard,
        GetEquippedUuidsRF = GetEquippedUuidsRF,
        EquipBestBtn = EquipBestBtn,
        UnequipAllBtn = UnequipAllBtn,
        isRemoveMode = function()
                return removeMode
        end,
}

require(InventoryApi:WaitForChild("GridToggle")).attach(ModuleContext)
require(InventoryApi:WaitForChild("CardLookup")).attach(ModuleContext)
require(InventoryApi:WaitForChild("EquipActions")).attach(ModuleContext)
require(InventoryApi:WaitForChild("Restoration")).attach(ModuleContext)
require(InventoryApi:WaitForChild("EquipButtons")).attach(ModuleContext)


if EquippedGridLayout2 then
	EquippedGridLayout2:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		applyLastRowCentering()
		_G.__updateCanvas()
	end)
end
if NotEquippedLayout2 then
	NotEquippedLayout2:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		_G.__updateCanvas()
	end)
end
list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	_G.__updateCanvas()
end)

-- Автовыключение Delete‑режима при закрытии инвентаря
do
	local sg = InventoryMainFrame:FindFirstAncestorOfClass("ScreenGui")
	if sg then
		sg:GetPropertyChangedSignal("Enabled"):Connect(function()
			if sg.Enabled then
				task.defer(function()
					recomputeEquippedHeight()
					scheduleReflow()
				end)
			end
		end)
	end
	InventoryMainFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if InventoryMainFrame.Visible then
			task.defer(function()
				recomputeEquippedHeight()
				scheduleReflow()
			end)
		end
	end)
end

-- === Delete Mode toggle ===
if RemoveModeBtn and RemoveModeBtn:IsA("GuiButton") then
	RemoveModeBtn.BackgroundColor3 = COLOR_OFF
	RemoveModeBtn.MouseButton1Click:Connect(function()
		setRemoveMode(not removeMode)
	end)
	applyRemoveModeUI()
end

-- === RemoveBtn click → double confirmation + chunking ===
if RemoveBtn and RemoveBtn:IsA("GuiButton") then
	RemoveBtn.MouseButton1Click:Connect(function()
		if not removeMode or #selectedOrder == 0 then return end

		if not _confirmArmed then
			_confirmArmed = true
			_confirmExpireAt = tick() + CONFIRM_SECONDS
			updateRemoveBtnText()

			if _confirmConn then _confirmConn:Disconnect() end
			_confirmConn = RunService.Heartbeat:Connect(function()
				if not _confirmArmed then return end
				if not removeMode or #selectedOrder == 0 then
					disarmConfirm()
					updateRemoveBtnText()
					return
				end
				if _confirmExpireAt and tick() >= _confirmExpireAt then
					disarmConfirm()
					updateRemoveBtnText()
				end
			end)
			return
		end

		_confirmArmed = false
		_confirmExpireAt = nil
		if _confirmConn then _confirmConn:Disconnect() _confirmConn = nil end

		local uuids = table.clone(selectedOrder)
		local total = #uuids
		if total == 0 then return end

		RemoveBtn.Active = false
		RemoveBtn.AutoButtonColor = false
		RemoveBtn.Text = ("Removing 0/%d..."):format(total)

		clearSelectionVisuals()
		updateRemoveBtnText()

		local BATCH = 60
		local sent = 0
		for i = 1, total, BATCH do
			local chunk = {}
			for j = i, math.min(i + BATCH - 1, total) do
				chunk[#chunk+1] = uuids[j]
			end
			pcall(function() RemoveNftsEvent:FireServer(chunk) end)
			sent += #chunk
			RemoveBtn.Text = ("Removing %d/%d..."):format(sent, total)
			RunService.Heartbeat:Wait()
		end

		setRemoveMode(false)
		RemoveBtn.Text = "Remove 0 NFTs"
		RemoveBtn.TextTransparency = 0.35
		RemoveBtn.Active = false
		RemoveBtn.AutoButtonColor = false
        end)
end
