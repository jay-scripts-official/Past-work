--[[
	DialogModule - NPC Dialog System
	
	PURPOSE:
	This module creates an interactive dialog system for NPCs in Roblox. It handles:
	- Displaying NPC dialog text with a typewriter effect
	- Showing player response options
	- Managing dialog flow and state
	- Visual feedback through GUI animations
	
	ARCHITECTURE:
	The module uses object-oriented programming with metatables. Each NPC gets
	its own DialogModule instance that encapsulates all dialog behavior for that
	specific character.
	
	WORKFLOW:
	1. Create instance with DialogModule.new()
	2. Add dialogs with :addDialog()
	3. Trigger dialog with :triggerDialog()
	4. Listen to self.responded event for player choices
--]]

local DialogModule = {}
DialogModule.__index = DialogModule

---------------------------------------------------------------------
-- SERVICES
-- These provide core Roblox functionality needed throughout the module
---------------------------------------------------------------------
local TweenService = game:GetService("TweenService")      -- Handles smooth animations
local RunService = game:GetService("RunService")          -- Provides frame-by-frame updates
local UserInputService = game:GetService("UserInputService") -- Detects keyboard input
local Players = game:GetService("Players")                -- Access to player objects

---------------------------------------------------------------------
-- PLAYER UI REFERENCES
-- These point to the GUI elements that display dialog responses.
-- The structure expected is: PlayerGui > dialog > dialogResponses
---------------------------------------------------------------------
local player = Players.LocalPlayer
local DialogResponsesUI =
	player:WaitForChild("PlayerGui")
	:WaitForChild("dialog")
	:WaitForChild("dialogResponses")

---------------------------------------------------------------------
-- SOUND EFFECTS
-- Audio feedback for the typewriter effect makes dialog feel more engaging
---------------------------------------------------------------------
local TickSound = script.sounds.tick      -- Plays for each letter typed
local EndTickSound = script.sounds.tick2  -- Could be used when typing completes

---------------------------------------------------------------------
-- CONSTRUCTOR
-- 
-- PURPOSE:
-- Creates a new dialog controller instance for a single NPC. This sets up
-- all the necessary references, state variables, and visual behaviors.
--
-- PARAMETERS:
-- @param npcName   (string)  - Display name of the NPC
-- @param npc       (Model)   - The NPC character model in workspace
-- @param prompt    (ProximityPrompt) - The interaction trigger object
-- @param animationId (string, optional) - Roblox animation asset ID for idle animation
--
-- RETURNS:
-- A new DialogModule instance with all systems initialized
--
-- DESIGN DECISIONS:
-- - Pre-creates response buttons to avoid lag during dialog (see _prepareResponseButtons)
-- - Pre-creates tweens to avoid recreating objects repeatedly (see _createGuiTweens)
-- - Uses BindableEvent for responding because it allows multiple listeners
-- - Separates setup into helper methods for clarity and maintainability
---------------------------------------------------------------------
function DialogModule.new(npcName, npc, prompt, animationId)
	-- Create new instance using metatable for object-oriented behavior
	local self = setmetatable({}, DialogModule)

	---------------------------------------------------------------------
	-- BASIC REFERENCES
	-- Store the essential objects this dialog controller needs to function
	---------------------------------------------------------------------
	self.npcName = npcName  -- Used for debugging and identification
	self.npc = npc          -- The character model to interact with
	self.prompt = prompt    -- ProximityPrompt that triggers dialog

	---------------------------------------------------------------------
	-- STATE CONTROL
	-- These variables track the current state of the dialog system
	---------------------------------------------------------------------
	self.dialogs = {}             -- Array of dialog objects {text, responses}
	self.currentDialogIndex = 1   -- Which dialog to show by default
	self.active = false           -- Is dialog currently accepting input?
	self.talking = false          -- Is typewriter effect currently running?

	---------------------------------------------------------------------
	-- NPC GUI REFERENCE
	-- Points to the BillboardGui on the NPC's head that shows dialog text
	-- Expected hierarchy: NPC > Head > gui (BillboardGui)
	---------------------------------------------------------------------
	self.npcGui = npc:WaitForChild("Head"):WaitForChild("gui")

	---------------------------------------------------------------------
	-- RESPONSE EVENT SYSTEM
	-- 
	-- WHY BINDABLE EVENT:
	-- BindableEvents allow one piece of code to fire events that other
	-- pieces can listen to. This lets external code react when the player
	-- chooses a response without tightly coupling the systems.
	--
	-- HOW IT WORKS:
	-- - self.responded is the public event that external code can :Connect() to
	-- - self._fireResponded is private and used internally to trigger the event
	---------------------------------------------------------------------
	local respondedEvent = Instance.new("BindableEvent")
	self.responded = respondedEvent.Event
	self._fireResponded = respondedEvent

	---------------------------------------------------------------------
	-- INITIALIZATION SEQUENCE
	-- These methods set up various systems needed for smooth dialog flow
	---------------------------------------------------------------------
	
	-- Pre-create all response buttons to avoid frame drops during dialog
	self:_prepareResponseButtons()

	-- Pre-create tween objects to avoid creating new ones every interaction
	self:_createGuiTweens()

	-- If an animation was provided, start playing it on the NPC
	if animationId then
		self:_playNpcAnimation(animationId)
	end

	---------------------------------------------------------------------
	-- VISUAL BEHAVIOR SETUP
	-- These add polish and make the NPC feel alive
	---------------------------------------------------------------------
	
	-- Adds subtle floating motion to the GUI when idle
	self:_startGuiBobbing()
	
	-- Controls when the NPC name is visible based on proximity
	self:_setupPromptVisibility()

	return self
end

---------------------------------------------------------------------
-- DIALOG DATA MANAGEMENT
--
-- PURPOSE:
-- Adds a new dialog entry to this NPC's dialog tree. Each dialog consists
-- of text the NPC says and an array of possible player responses.
--
-- PARAMETERS:
-- @param text      (string)  - What the NPC says
-- @param responses (table)   - Array of strings representing player choices
--
-- EXAMPLE USAGE:
-- npcDialog:addDialog(
--     "Hello traveler! What brings you here?",
--     {"I'm looking for work", "Just passing through", "Where am I?"}
-- )
--
-- DATA STRUCTURE:
-- Each dialog is stored as: {text = "...", responses = {"...", "..."}}
-- This makes it easy to access both the NPC's speech and player options
---------------------------------------------------------------------
function DialogModule:addDialog(text, responses)
	table.insert(self.dialogs, {
		text = text,
		responses = responses
	})
end

---------------------------------------------------------------------
-- UI PREPARATION
--
-- PURPOSE:
-- Pre-creates all response buttons before they're needed. This prevents
-- lag spikes during dialog because creating and parenting GUI objects
-- can cause frame drops.
--
-- HOW IT WORKS:
-- 1. Finds a template button in DialogResponsesUI
-- 2. Clones it 9 times (supports up to 9 response options)
-- 3. Names each clone with a number for easy access later
-- 4. Destroys the template since we don't need it anymore
--
-- DESIGN DECISION:
-- Creating buttons ahead of time trades a small amount of memory for
-- much smoother user experience. The player won't notice a tiny lag
-- when the dialog system initializes, but they WOULD notice lag when
-- trying to interact with an NPC.
---------------------------------------------------------------------
function DialogModule:_prepareResponseButtons()
	local template = DialogResponsesUI:FindFirstChild("template")
	if not template then return end

	-- Create 9 response buttons (1-9 for keyboard shortcuts)
	for i = 1, 9 do
		local clone = template:Clone()
		clone.Name = tostring(i)  -- Name matches keyboard number
		clone.Parent = DialogResponsesUI
	end

	-- Remove template since we've cloned what we need
	template:Destroy()
end

---------------------------------------------------------------------
-- TWEEN CREATION
--
-- PURPOSE:
-- Pre-creates all tween objects used for fading UI elements. Tweens are
-- reusable animation objects that smoothly transition properties.
--
-- WHY PRE-CREATE:
-- Creating new tweens every time we show/hide UI would be wasteful.
-- By creating them once and storing them, we can just call :Play()
-- whenever we need them, which is much more efficient.
--
-- TWEENS CREATED:
-- - fadeNameText: Fades the NPC's name text
-- - fadeNameStroke: Fades the outline around the name
-- - fadeArrowText: Fades the interaction arrow
-- - fadeArrowStroke: Fades the outline around the arrow
--
-- HOW TWEENS WORK:
-- TweenService:Create(object, TweenInfo, propertyTable)
-- - object: What to animate
-- - TweenInfo: Duration and easing settings
-- - propertyTable: End values for properties to animate
---------------------------------------------------------------------
function DialogModule:_createGuiTweens()
	local gui = self.npcGui

	-- Fade the NPC name text to transparent (invisible)
	self.fadeNameText = TweenService:Create(
		gui.name,
		TweenInfo.new(0.3),  -- 0.3 second duration
		{ TextTransparency = 1 }  -- Fully transparent
	)

	-- Fade the stroke (outline) around the name
	self.fadeNameStroke = TweenService:Create(
		gui.name.UIStroke,
		TweenInfo.new(0.3),
		{ Transparency = 1 }
	)

	-- Fade the arrow indicator
	self.fadeArrowText = TweenService:Create(
		gui.arrow,
		TweenInfo.new(0.3),
		{ TextTransparency = 1 }
	)

	-- Fade the arrow's outline
	self.fadeArrowStroke = TweenService:Create(
		gui.arrow.UIStroke,
		TweenInfo.new(0.3),
		{ Transparency = 1 }
	)
end

---------------------------------------------------------------------
-- NPC ANIMATION HELPER
--
-- PURPOSE:
-- Plays an idle animation on the NPC to make them feel more alive.
-- Animations add personality and visual interest.
--
-- PARAMETERS:
-- @param animationId (string) - Roblox asset ID like "rbxassetid://123456"
--
-- HOW ANIMATIONS WORK:
-- 1. Create an Animation instance
-- 2. Set its AnimationId to the asset
-- 3. Load it onto the Humanoid
-- 4. Play the resulting AnimationTrack
--
-- NOTE:
-- The animation loops automatically based on its settings in the
-- animation editor when it was created.
---------------------------------------------------------------------
function DialogModule:_playNpcAnimation(animationId)
	-- Create animation object
	local anim = Instance.new("Animation")
	anim.AnimationId = animationId

	-- Load and play on the NPC's humanoid
	local humanoid = self.npc:WaitForChild("Humanoid")
	local track = humanoid:LoadAnimation(anim)
	track:Play()
end

---------------------------------------------------------------------
-- GUI BOBBING EFFECT
--
-- PURPOSE:
-- Creates a subtle floating motion for the NPC's overhead GUI. This makes
-- the NPC feel alive even when they're not talking.
--
-- HOW IT WORKS:
-- 1. Connects to Heartbeat (runs every frame, ~60 times per second)
-- 2. Uses a sine wave to create smooth up-and-down motion
-- 3. When talking, stops bobbing and locks to a fixed position
--
-- MATH EXPLANATION:
-- math.sin(frame / 25) creates a wave that oscillates between -1 and 1
-- Dividing by 6 reduces the amplitude (height) of the motion
-- Adding 1.55 sets the center point of the bobbing motion
--
-- DESIGN DECISION:
-- Bobbing stops during dialog because the typewriter effect is enough
-- motion. Too much movement would be distracting.
---------------------------------------------------------------------
function DialogModule:_startGuiBobbing()
	local frame = 0  -- Counter for animation timing

	RunService.Heartbeat:Connect(function()
		frame += 1  -- Increment every frame

		-- If currently typing dialog, lock GUI position
		if self.talking then
			self.npcGui.StudsOffset = Vector3.new(0, 1.6, 0)
			return
		end

		-- Calculate smooth bobbing motion using sine wave
		local offsetY = math.sin(frame / 25) / 6 + 1.55
		self.npcGui.StudsOffset = Vector3.new(0, offsetY, 0)
	end)
end

---------------------------------------------------------------------
-- PROMPT VISIBILITY HANDLING
--
-- PURPOSE:
-- Controls when the NPC's name is visible. The name should show when
-- the player is close enough to interact, but hide otherwise.
--
-- HOW IT WORKS:
-- ProximityPrompt has two built-in events:
-- - PromptShown: Fires when player enters range
-- - PromptHidden: Fires when player leaves range
--
-- We connect to these events to control the AlwaysOnTop property,
-- which determines if the GUI renders through walls.
--
-- LOGIC:
-- When prompt shows -> Make GUI always visible
-- When prompt hides -> Hide GUI UNLESS dialog is active
--
-- WHY CHECK self.talking:
-- If the player starts a conversation then backs away, we want to
-- keep the dialog visible until it's actually closed.
---------------------------------------------------------------------
function DialogModule:_setupPromptVisibility()
	-- Player is in range - show the name
	self.prompt.PromptShown:Connect(function()
		self.npcGui.AlwaysOnTop = true
	end)

	-- Player left range - hide name (unless in conversation)
	self.prompt.PromptHidden:Connect(function()
		if self.talking then return end  -- Keep visible during dialog
		self.npcGui.AlwaysOnTop = false
	end)
end

---------------------------------------------------------------------
-- TYPEWRITER TEXT EFFECT
--
-- PURPOSE:
-- Displays text one letter at a time, creating a classic RPG dialog
-- effect. This is more engaging than instant text and gives the player
-- time to read.
--
-- PARAMETERS:
-- @param label (TextLabel) - The GUI element to type into
-- @param text  (string)    - The full text to display
--
-- HOW IT WORKS:
-- 1. Set talking flag to true (stops GUI bobbing, prevents interruption)
-- 2. Clear the label and make it visible
-- 3. Loop through each character in the text
-- 4. Use string.sub to get substring from start to current position
-- 5. Play a tick sound for audio feedback
-- 6. Wait a tiny amount between letters (0.02 seconds)
-- 7. Set talking flag to false when complete
--
-- DESIGN DECISIONS:
-- - 0.02 second delay is fast enough to not feel slow, but slow enough
--   to create the desired effect
-- - Tick sound adds satisfying audio feedback
-- - self.talking flag is critical - it prevents visual glitches and
--   ensures the dialog system state is consistent
---------------------------------------------------------------------
function DialogModule:_typeText(label, text)
	self.talking = true  -- Signal that typing is in progress
	label.Text = ""      -- Start with empty text
	label.Visible = true -- Make sure label is visible

	-- Type each character one at a time
	for i = 1, #text do
		label.Text = text:sub(1, i)  -- Substring from start to current position
		TickSound:Play()              -- Audio feedback
		task.wait(0.02)               -- Small delay between letters
	end

	self.talking = false  -- Typing complete, resume normal behavior
end

---------------------------------------------------------------------
-- DISPLAY SELECTABLE RESPONSES
--
-- PURPOSE:
-- Shows the player's response options and handles input (both mouse
-- and keyboard). This is where the player makes choices that drive
-- the conversation forward.
--
-- PARAMETERS:
-- @param dialogIndex (number) - Which dialog entry we're showing responses for
--
-- HOW IT WORKS:
-- 1. Set active flag to true (allows input processing)
-- 2. Get the dialog entry and its responses
-- 3. For each response, show a button with the text
-- 4. Connect mouse click events to each button
-- 5. Connect keyboard events (1, 2, 3 keys)
-- 6. When a choice is made:
--    - Store which option was selected
--    - Set active to false (prevents duplicate selections)
--    - Fire the responded event with the choice and dialog index
--
-- INPUT HANDLING:
-- - Mouse: Each button has a MouseButton1Down connection
-- - Keyboard: InputBegan event with key mapping (1, 2, 3 keys)
--
-- RESPONSE FORMAT:
-- Text uses rich text with colored numbers: "<font color='...'>1.)</font> Response text"
-- This makes the keyboard shortcuts visually clear
--
-- EVENT FIRING:
-- When player chooses, we fire: self._fireResponded:Fire(choiceIndex, dialogIndex)
-- External code listening to self.responded will receive these parameters
-- and can handle what happens next (show next dialog, give quest, etc.)
---------------------------------------------------------------------
function DialogModule:_showResponses(dialogIndex)
	self.active = true  -- Enable input processing
	local dialog = self.dialogs[dialogIndex]
	if not dialog then return end

	local selected = nil  -- Will store the player's choice
	
	-- Keyboard shortcut mapping: Key -> Response number
	local keyMap = {
		[Enum.KeyCode.One] = 1,
		[Enum.KeyCode.Two] = 2,
		[Enum.KeyCode.Three] = 3,
	}

	-- Show each response as a clickable button
	for i, text in ipairs(dialog.responses) do
		local button = DialogResponsesUI:FindFirstChild(tostring(i))
		if not button then continue end  -- Skip if button doesn't exist

		-- Format the button text with colored number
		button.text.Text =
			"<font color='rgb(255,220,127)'>" .. i .. ".)</font> " .. text
		button.Visible = true

		-- Handle mouse clicks
		button.MouseButton1Down:Connect(function()
			if not self.active then return end  -- Ignore if already processed
			selected = i
			self.active = false  -- Prevent multiple selections
			self._fireResponded:Fire(i, dialogIndex)  -- Notify listeners
		end)
	end

	-- Handle keyboard input (1, 2, 3 keys)
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp or not self.active then return end  -- Ignore if game processed or inactive
		local index = keyMap[input.KeyCode]
		if not index then return end  -- Not a mapped key

		selected = index
		self.active = false
		self._fireResponded:Fire(index, dialogIndex)
	end)

	return selected
end

---------------------------------------------------------------------
-- DISTANCE MONITORING
--
-- PURPOSE:
-- Automatically closes the dialog if the player walks too far away
-- from the NPC. This prevents players from keeping dialog open while
-- running around, which would be weird and immersion-breaking.
--
-- PARAMETERS:
-- @param player (Player) - The player to monitor
--
-- HOW IT WORKS:
-- 1. Get the player's character's primary part (usually HumanoidRootPart)
-- 2. Loop continuously while dialog is active
-- 3. Every 0.2 seconds, check distance between player and NPC
-- 4. If distance exceeds 10 studs (Roblox units), close dialog
--
-- DISTANCE CALCULATION:
-- (playerPos - npcPos).Magnitude gives the distance between two points
-- in 3D space. Magnitude is the length of the vector.
--
-- WHY 10 STUDS:
-- This is a reasonable conversation distance. Close enough that they
-- can talk, but gives some freedom to move around slightly.
--
-- WHY 0.2 SECOND CHECKS:
-- Checking every frame would be overkill. Every 0.2 seconds is
-- frequent enough to feel responsive but doesn't waste performance.
---------------------------------------------------------------------
function DialogModule:_monitorDistance(player)
	-- Get the player's character root part
	local root = player.Character and player.Character.PrimaryPart
	if not root then return end  -- Safety check

	-- Loop while dialog is active
	while self.active do
		-- Calculate 3D distance between player and NPC
		local dist =
			(root.Position - self.npc.Torso.Position).Magnitude

		-- Player is too far - close dialog
		if dist > 10 then
			self:hideGui()     -- Hide the dialog UI
			self.active = false -- Stop accepting input
			return             -- Exit monitoring loop
		end

		task.wait(0.2)  -- Check every 0.2 seconds
	end
end

---------------------------------------------------------------------
-- ENTRY POINT - TRIGGER DIALOG
--
-- PURPOSE:
-- Starts the dialog sequence. This is the main method you call to
-- begin a conversation with the NPC.
--
-- PARAMETERS:
-- @param player (Player) - The player initiating dialog
-- @param index  (number, optional) - Which dialog to show (defaults to currentDialogIndex)
--
-- WORKFLOW:
-- 1. Validate that dialogs exist
-- 2. Determine which dialog to show
-- 3. Show the NPC's GUI
-- 4. Spawn a new thread to handle:
--    a. Typewriter text effect
--    b. Display response options
--    c. Monitor player distance
--
-- WHY task.spawn:
-- We use task.spawn to run the dialog sequence in a separate thread.
-- This prevents blocking the main game loop and allows smooth execution
-- of multiple simultaneous operations (typing, monitoring, etc.)
--
-- THREAD SAFETY:
-- Each operation (typing, showing responses, monitoring) runs
-- cooperatively. The talking flag and active flag ensure they don't
-- interfere with each other.
---------------------------------------------------------------------
function DialogModule:triggerDialog(player, index)
	-- Safety check - make sure we have dialogs configured
	if #self.dialogs == 0 then
		warn("No dialogs for NPC:", self.npcName)
		return
	end

	-- Use provided index or default to current
	local dialogIndex = index or self.currentDialogIndex
	local dialog = self.dialogs[dialogIndex]
	if not dialog then return end  -- Invalid index

	-- Show the GUI elements
	self:showGui()

	-- Start the dialog sequence in a new thread
	task.spawn(function()
		self:_typeText(self.npcGui.dialog, dialog.text)  -- Type NPC's text
		self:_showResponses(dialogIndex)                 -- Show player options
		self:_monitorDistance(player)                    -- Watch for player leaving
	end)
end

---------------------------------------------------------------------
-- GUI VISIBILITY HELPERS
--
-- These methods control the visual state of the NPC's overhead GUI.
-- They handle fading elements in and out smoothly.
---------------------------------------------------------------------

---------------------------------------------------------------------
-- SHOW GUI
--
-- PURPOSE:
-- Makes the dialog GUI visible by fading out the name/arrow and
-- fading in the dialog text.
--
-- DESIGN RATIONALE:
-- When dialog starts, we hide the NPC name and interaction arrow
-- because they're no longer needed - the player is already interacting.
-- The dialog text becomes the focus.
--
-- HOW IT WORKS:
-- Play all fade-out tweens (name and arrow)
-- Set dialog text to fully visible (transparency = 0)
---------------------------------------------------------------------
function DialogModule:showGui()
	-- Fade out name and arrow (player is already interacting)
	self.fadeNameText:Play()
	self.fadeNameStroke:Play()
	self.fadeArrowText:Play()
	self.fadeArrowStroke:Play()

	-- Show dialog text
	self.npcGui.dialog.TextTransparency = 0       -- Fully opaque
	self.npcGui.dialog.UIStroke.Transparency = 0  -- Outline visible
end

---------------------------------------------------------------------
-- HIDE GUI
--
-- PURPOSE:
-- Hides the dialog text and restores the name/arrow display.
-- This happens when the conversation ends.
--
-- DESIGN RATIONALE:
-- After dialog closes, we want to return to the idle state where
-- the NPC's name and interaction arrow are visible, but the dialog
-- text is hidden.
--
-- HOW IT WORKS:
-- Set dialog text to fully transparent (invisible)
-- Make name and arrow visible again
---------------------------------------------------------------------
function DialogModule:hideGui()
	-- Hide dialog text
	self.npcGui.dialog.TextTransparency = 1       -- Fully transparent
	self.npcGui.dialog.UIStroke.Transparency = 1  -- Outline invisible

	-- Restore name and arrow
	self.npcGui.name.Visible = true
	self.npcGui.arrow.Visible = true
end

return DialogModule
