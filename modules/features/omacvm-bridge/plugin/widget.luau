--!nonstrict
-- The Mac's Wi-Fi as the glyph, the rest in the tooltip; a click opens the launcher's /mac
-- (plugin.toml), where they are switched.

local format = require("./format.luau")

local function render()
	local wifi = noctalia.state.get("wifi")
	if noctalia.state.get("connected") ~= true or wifi == nil then
		barWidget.setGlyph("wifi-off")
		barWidget.setTooltip("Mac: OmacVM Bridge not reachable")
		return
	end
	barWidget.setGlyph(wifi.connected == true and "wifi" or "wifi-off")
	local rows = { { "Wi-Fi", format.wifi(wifi) } }
	local audio = noctalia.state.get("audio")
	if audio ~= nil then
		table.insert(rows, { "Sound", format.output(audio) })
	end
	local bluetooth = noctalia.state.get("bluetooth")
	if bluetooth ~= nil then
		table.insert(rows, { "Bluetooth", format.bluetooth(bluetooth) })
	end
	local display = noctalia.state.get("display")
	if display ~= nil then
		table.insert(rows, { "Night Shift", format.nightShift(display) })
	end
	barWidget.setTooltip(rows)
end

for _, key in { "connected", "wifi", "audio", "bluetooth", "display" } do
	noctalia.state.watch(key, render)
end
render()
