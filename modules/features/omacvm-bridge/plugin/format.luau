--!nonstrict
-- The Bridge's payloads as text, for the widget's tooltip and the launcher.

local M = {}

local function percent(fraction)
	return string.format("%d%%", math.round(fraction * 100))
end

function M.wifi(wifi)
	if wifi.power ~= true then
		return "off"
	end
	if wifi.connected ~= true then
		return "not connected"
	end
	if wifi.ssid == nil then
		return "connected (the Bridge has no Location Services, so no name)"
	end
	if wifi.quality == nil then
		return wifi.ssid
	end
	return wifi.ssid .. " (" .. wifi.quality .. "%)"
end

function M.output(audio)
	local output = audio.output
	if output == nil then
		return "none"
	end
	if output.muted == true then
		return output.name .. ", muted"
	end
	if output.volume == nil then
		return output.name
	end
	return output.name .. ", " .. percent(output.volume)
end

function M.device(device)
	local battery = device.battery
	if device.connected ~= true or battery == nil then
		return device.name
	end
	local levels = {}
	for _, part in { "main", "left", "right", "case" } do
		if battery[part] ~= nil then
			table.insert(levels, battery[part] .. "%")
		end
	end
	return device.name .. " (" .. table.concat(levels, " ") .. ")"
end

function M.bluetooth(bluetooth)
	if bluetooth.power ~= true then
		return "off"
	end
	local names = {}
	for _, device in bluetooth.devices or {} do
		if device.connected == true then
			table.insert(names, M.device(device))
		end
	end
	if #names == 0 then
		return "on"
	end
	return table.concat(names, ", ")
end

function M.nightShift(display)
	local nightShift = display.night_shift
	if nightShift == nil or nightShift.available ~= true then
		return "not available"
	end
	return nightShift.enabled == true and "on" or "off"
end

return M
