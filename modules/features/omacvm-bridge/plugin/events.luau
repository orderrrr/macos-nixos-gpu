--!nonstrict
-- The Bridge's event stream, one per session (omacvm's client proves the Bridge before the
-- token goes out). The latest "wifi", "audio", "bluetooth" and "display" go to the plugin's
-- state for the widget and the launcher; "osd" (the Mac's volume and brightness keys, which
-- the Bridge takes while the VM is in front) shows as Noctalia's own OSD.

local BRIDGE = "@bridge@"
-- As omacvm-bridge-osd: changes from the keys and from this VM, not the Mac's own sliders.
local OSD_SOURCES = { keys = true, api = true }

local function showOsd(osd)
	if not OSD_SOURCES[osd.source] then
		return
	end
	local value = osd.value or 0
	local text = string.format("%d%%", math.round(value))
	local progress = math.clamp(value / 100, 0, 1)
	if osd.kind == "volume" or osd.kind == "mute" then
		local muted = osd.muted == true or value == 0
		noctalia.osd.show(muted and "volume-mute" or "volume-high", text, { progress = progress, inactive = muted })
	elseif osd.kind == "brightness" then
		noctalia.osd.show("brightness-high", text, { progress = progress })
	elseif osd.kind == "keyboard" then
		noctalia.osd.show("keyboard", text, { progress = progress })
	end
end

local event = ""

local function onLine(line)
	if line == "closed" then
		noctalia.state.set("connected", false)
	elseif line:sub(1, 7) == "event: " then
		event = line:sub(8)
	elseif line:sub(1, 6) == "data: " then
		local data = noctalia.json.decode(line:sub(7))
		if type(data) ~= "table" then
			return
		end
		if event == "osd" then
			showOsd(data)
		else
			noctalia.state.set("connected", true)
			noctalia.state.set(event, data)
		end
	end
end

-- The stream ends when the Mac sleeps or the Bridge restarts; it comes back in 3 s, as
-- omacvm's own readers do.
noctalia.runStream("while :; do " .. BRIDGE .. " events; echo closed; sleep 3; done", onLine)
