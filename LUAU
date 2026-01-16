local DialogModule = {}
DialogModule.__index = DialogModule

--// Services
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

--// Player UI references
local player = Players.LocalPlayer
local DialogResponsesUI =
	player:WaitForChild("PlayerGui")
	:WaitForChild("dialog")
	:WaitForChild("dialogResponses")

--// Sounds
local TickSound = script.sounds.tick
local EndTickSound = script.sounds.tick2

---------------------------------------------------------------------
-- Constructor
-- Creates a dialog controller for a single NPC
---------------------------------------------------------------------
function DialogModule.new(npcName, npc, prompt, animationId)
	local self = setmetatable({}, DialogModule)

	-- Basic references
	self.npcName = npcName
	self.npc = npc
	self.prompt = prompt

	-- State control
	self.dialogs = {}
	self.currentDialogIndex = 1
	self.active = false
	self.talking = false

	-- NPC GUI
	self.npcGui = npc:WaitForChild("Head"):WaitForChild("gui")

	-- Event used to notify when player chooses a response
	local respondedEvent = Instance.new("BindableEvent")
	self.responded = respondedEvent.Event
	self._fireResponded = respondedEvent

	-- Pre-create response buttons to avoid lag later
	self:_prepareResponseButtons()

	-- Prepare tweens once to avoid recreating them every interaction
	self:_createGuiTweens()

	-- Optional idle animation
	if animationId then
		self:_playNpcAnimation(animationId)
	end

	-- Visual behavior
	self:_startGuiBobbing()
	self:_setupPromptVisibility()

	return self
end

---------------------------------------------------------------------
-- Dialog data management
---------------------------------------------------------------------
function DialogModule:addDialog(text, responses)
	table.insert(self.dialogs, {
		text = text,
		responses = responses
	})
end

---------------------------------------------------------------------
-- UI preparation
-- Buttons are cloned early so dialog feels instant
---------------------------------------------------------------------
function DialogModule:_prepareResponseButtons()
	local template = DialogResponsesUI:FindFirstChild("template")
	if not template then return end

	for i = 1, 9 do
		local clone = template:Clone()
		clone.Name = tostring(i)
		clone.Parent = DialogResponsesUI
	end

	template:Destroy()
end

---------------------------------------------------------------------
-- Tween creation
-- Tweens are stored so we don’t recreate objects repeatedly
---------------------------------------------------------------------
function DialogModule:_createGuiTweens()
	local gui = self.npcGui

	self.fadeNameText = TweenService:Create(
		gui.name,
		TweenInfo.new(0.3),
		{ TextTransparency = 1 }
	)

	self.fadeNameStroke = TweenService:Create(
		gui.name.UIStroke,
		TweenInfo.new(0.3),
		{ Transparency = 1 }
	)

	self.fadeArrowText = TweenService:Create(
		gui.arrow,
		TweenInfo.new(0.3),
		{ TextTransparency = 1 }
	)

	self.fadeArrowStroke = TweenService:Create(
		gui.arrow.UIStroke,
		TweenInfo.new(0.3),
		{ Transparency = 1 }
	)
end

---------------------------------------------------------------------
-- NPC animation helper
---------------------------------------------------------------------
function DialogModule:_playNpcAnimation(animationId)
	local anim = Instance.new("Animation")
	anim.AnimationId = animationId

	local humanoid = self.npc:WaitForChild("Humanoid")
	local track = humanoid:LoadAnimation(anim)
	track:Play()
end

---------------------------------------------------------------------
-- GUI bobbing
-- Idle motion makes NPC feel alive when not talking
---------------------------------------------------------------------
function DialogModule:_startGuiBobbing()
	local frame = 0

	RunService.Heartbeat:Connect(function()
		frame += 1

		if self.talking then
			self.npcGui.StudsOffset = Vector3.new(0, 1.6, 0)
			return
		end

		local offsetY = math.sin(frame / 25) / 6 + 1.55
		self.npcGui.StudsOffset = Vector3.new(0, offsetY, 0)
	end)
end

---------------------------------------------------------------------
-- Prompt visibility handling
-- Keeps name visible only when appropriate
---------------------------------------------------------------------
function DialogModule:_setupPromptVisibility()
	self.prompt.PromptShown:Connect(function()
		self.npcGui.AlwaysOnTop = true
	end)

	self.prompt.PromptHidden:Connect(function()
		if self.talking then return end
		self.npcGui.AlwaysOnTop = false
	end)
end

---------------------------------------------------------------------
-- Typewriter text
-- Letters appear gradually for readability and atmosphere
---------------------------------------------------------------------
function DialogModule:_typeText(label, text)
	self.talking = true
	label.Text = ""
	label.Visible = true

	for i = 1, #text do
		label.Text = text:sub(1, i)
		TickSound:Play()
		task.wait(0.02)
	end

	self.talking = false
end

---------------------------------------------------------------------
-- Displays selectable responses
-- Handles mouse + keyboard input
---------------------------------------------------------------------
function DialogModule:_showResponses(dialogIndex)
	self.active = true
	local dialog = self.dialogs[dialogIndex]
	if not dialog then return end

	local selected = nil
	local keyMap = {
		[Enum.KeyCode.One] = 1,
		[Enum.KeyCode.Two] = 2,
		[Enum.KeyCode.Three] = 3,
	}

	for i, text in ipairs(dialog.responses) do
		local button = DialogResponsesUI:FindFirstChild(tostring(i))
		if not button then continue end

		button.text.Text =
			"<font color='rgb(255,220,127)'>" .. i .. ".)</font> " .. text
		button.Visible = true

		button.MouseButton1Down:Connect(function()
			if not self.active then return end
			selected = i
			self.active = false
			self._fireResponded:Fire(i, dialogIndex)
		end)
	end

	-- Keyboard support
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp or not self.active then return end
		local index = keyMap[input.KeyCode]
		if not index then return end

		selected = index
		self.active = false
		self._fireResponded:Fire(index, dialogIndex)
	end)

	return selected
end

---------------------------------------------------------------------
-- Distance monitoring
-- Closes dialog if player walks away
---------------------------------------------------------------------
function DialogModule:_monitorDistance(player)
	local root = player.Character and player.Character.PrimaryPart
	if not root then return end

	while self.active do
		local dist =
			(root.Position - self.npc.Torso.Position).Magnitude

		if dist > 10 then
			self:hideGui()
			self.active = false
			return
		end

		task.wait(0.2)
	end
end

---------------------------------------------------------------------
-- Entry point
-- Starts dialog flow
---------------------------------------------------------------------
function DialogModule:triggerDialog(player, index)
	if #self.dialogs == 0 then
		warn("No dialogs for NPC:", self.npcName)
		return
	end

	local dialogIndex = index or self.currentDialogIndex
	local dialog = self.dialogs[dialogIndex]
	if not dialog then return end

	self:showGui()

	task.spawn(function()
		self:_typeText(self.npcGui.dialog, dialog.text)
		self:_showResponses(dialogIndex)
		self:_monitorDistance(player)
	end)
end

---------------------------------------------------------------------
-- GUI visibility helpers
---------------------------------------------------------------------
function DialogModule:showGui()
	self.fadeNameText:Play()
	self.fadeNameStroke:Play()
	self.fadeArrowText:Play()
	self.fadeArrowStroke:Play()

	self.npcGui.dialog.TextTransparency = 0
	self.npcGui.dialog.UIStroke.Transparency = 0
end

function DialogModule:hideGui()
	self.npcGui.dialog.TextTransparency = 1
	self.npcGui.dialog.UIStroke.Transparency = 1

	self.npcGui.name.Visible = true
	self.npcGui.arrow.Visible = true
end

return DialogModule
