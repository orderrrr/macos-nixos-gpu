--!nonstrict
-- /mac in the launcher: the Mac's Night Shift, True Tone, sound output and Bluetooth, each
-- result one omacvm-bridge command. Wi-Fi is shown only: the Bridge cannot switch it.

local BRIDGE = "@bridge@"
local format = require("./format.luau")

-- A result's id is its omacvm-bridge arguments (a device's uid may hold spaces).
local function command(args)
	return noctalia.json.encode(args)
end

local function onOff(enabled)
	return enabled == true and "on" or "off"
end

local function displayResults(results, display)
	local nightShift = display.night_shift
	if nightShift ~= nil and nightShift.available == true then
		table.insert(results, {
			id = command({ "night-shift", "toggle" }),
			title = "Night Shift",
			subtitle = onOff(nightShift.enabled),
			glyph = nightShift.enabled == true and "nightlight-on" or "nightlight-off",
		})
	end
	local trueTone = display.true_tone
	if trueTone ~= nil and trueTone.available == true then
		table.insert(results, {
			id = command({ "true-tone", "toggle" }),
			title = "True Tone",
			subtitle = onOff(trueTone.enabled),
			glyph = "sun",
		})
	end
end

local function audioResults(results, audio)
	for _, device in audio.devices or {} do
		if device.has_output == true then
			table.insert(results, {
				id = command({ "output", device.uid }),
				title = device.name,
				subtitle = device.default_output == true and "Sound output (current)" or "Sound output",
				glyph = "device-speaker",
			})
		end
	end
end

local function bluetoothResults(results, bluetooth)
	table.insert(results, {
		id = command({ "bluetooth", "power", "toggle" }),
		title = "Bluetooth",
		subtitle = onOff(bluetooth.power),
		glyph = bluetooth.power == true and "bluetooth" or "bluetooth-off",
	})
	if bluetooth.power == true then
		for _, device in bluetooth.devices or {} do
			if device.paired == true then
				local connected = device.connected == true
				table.insert(results, {
					id = command({ "bluetooth", connected and "disconnect" or "connect", device.address }),
					title = format.device(device),
					subtitle = connected and "Connected: disconnect" or "Connect",
					glyph = connected and "bluetooth-connected" or "bluetooth",
				})
			end
		end
	end
	-- Pairing needs macOS's own dialog.
	table.insert(results, {
		id = command({ "bluetooth", "settings" }),
		title = "Pair a new device…",
		subtitle = "Opens the Mac's Bluetooth settings",
		glyph = "bluetooth",
	})
end

local function allResults()
	local results = {}
	local wifi = noctalia.state.get("wifi")
	if noctalia.state.get("connected") ~= true or wifi == nil then
		table.insert(results, { id = "", title = "OmacVM Bridge not reachable", glyph = "wifi-off" })
		return results
	end
	table.insert(results, { id = "", title = "Wi-Fi: " .. format.wifi(wifi), glyph = "wifi" })
	local display = noctalia.state.get("display")
	if display ~= nil then
		displayResults(results, display)
	end
	local audio = noctalia.state.get("audio")
	if audio ~= nil then
		audioResults(results, audio)
	end
	local bluetooth = noctalia.state.get("bluetooth")
	if bluetooth ~= nil then
		bluetoothResults(results, bluetooth)
	end
	return results
end

function onQuery(text)
	local results = allResults()
	if text ~= "" then
		local matches = {}
		for _, result in results do
			result.score = noctalia.fuzzyScore(text, result.title .. " " .. (result.subtitle or ""))
			if result.score ~= nil then
				table.insert(matches, result)
			end
		end
		results = matches
	end
	launcher.setResults(text, results)
end

-- The next event shows the command's effect.
function onActivate(id)
	if id == "" then
		return
	end
	local argv = { BRIDGE }
	for _, arg in noctalia.json.decode(id) do
		table.insert(argv, arg)
	end
	noctalia.runAsync(argv, function(result)
		if result.exitCode ~= 0 then
			local why = result.stderr ~= "" and result.stderr or result.stdout
			noctalia.notifyError("Mac", noctalia.string.trim(why))
		end
	end)
end
