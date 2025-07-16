--- Developed using LifeBoatAPI - Stormworks Lua plugin for VSCode - https://code.visualstudio.com/download (search "Stormworks Lua with LifeboatAPI" extension)
--- If you have any issues, please report them here: https://github.com/nameouschangey/STORMWORKS_VSCodeExtension/issues - by Nameous Changey


--[====[ HOTKEYS ]====]
-- Press F6 to simulate this file
-- Press F7 to build the project, copy the output from /_build/out/ into the game to use
-- Remember to set your Author name etc. in the settings: CTRL+COMMA


--[====[ EDITABLE SIMULATOR CONFIG - *automatically removed from the F7 build output ]====]
---@section __LB_SIMULATOR_ONLY__
do
    ---@type Simulator -- Set properties and screen sizes here - will run once when the script is loaded
    simulator = simulator
    simulator:setScreen(1, "3x3")
    simulator:setProperty("ExampleNumberProperty", 123)

    -- Runs every tick just before onTick; allows you to simulate the inputs changing
    ---@param simulator Simulator Use simulator:<function>() to set inputs etc.
    ---@param ticks     number Number of ticks since simulator started
    function onLBSimulatorTick(simulator, ticks)
        -- touchscreen defaults
        local screenConnection = simulator:getTouchScreen(1)
        simulator:setInputBool(1, screenConnection.isTouched)
        simulator:setInputNumber(1, screenConnection.width)
        simulator:setInputNumber(2, screenConnection.height)
        simulator:setInputNumber(3, screenConnection.touchX)
        simulator:setInputNumber(4, screenConnection.touchY)

        -- NEW! button/slider options from the UI
        simulator:setInputBool(31, simulator:getIsClicked(1))     -- if button 1 is clicked, provide an ON pulse for input.getBool(31)
        simulator:setInputNumber(31, simulator:getSlider(1))      -- set input 31 to the value of slider 1

        simulator:setInputBool(32, simulator:getIsToggled(2))     -- make button 2 a toggle, for input.getBool(32)
        simulator:setInputNumber(32, simulator:getSlider(2) * 50) -- set input 32 to the value from slider 2 * 50
    end;
end
---@endsection


--[====[ IN-GAME CODE ]====]

-- try require("Folder.Filename") to include code from another file in this, so you can store code in libraries
-- the "LifeBoatAPI" is included by default in /_build/libs/ - you can use require("LifeBoatAPI") to get this, and use all the LifeBoatAPI.<functions>!
gB, sN = input.getBool, output.setNumber
SHOWDISTANCE = 0 --property.getNumber("ViewDistance") --(m)
FOV = 0          --property.getNumber("FOV")/2
MaxFOV = property.getNumber("MaxFOV (degree)") / 2

bgR, bgG, bgB = property.getNumber("Background R"), property.getNumber("Background G"),property.getNumber("Background B")
flR, flG, flB = property.getNumber("Frame R"), property.getNumber("Frame G"), property.getNumber("Frame B")
tgR, tgG, tgB = property.getNumber("Target R"), property.getNumber("Target G"), property.getNumber("Target B")

Phys = {
    gpsX    = 0,
    alt     = 0,
    gpsY    = 0,
    spdX    = 0,
    spdY    = 0,
    spdZ    = 0,
    AspdX   = 0,
    AspdY   = 0,
    AspdZ   = 0,
    spdABS  = 0,
    AspdABS = 0,
    tiltZ   = 0,
    tiltX   = 0,
    compass = 0
}
RadioData = {}
ShowData = {}
TrackMode = 0 -- 0=None,1=Scan,2=Locked,3=TwsScan,4=TwsLock
TrackVid = nil
Cursor = { X = 0, Y = 0, Azimath = 0, Distance = 0, RdrAzimath = 0 }
w, h = 0, 0
TargetData = {}
Timer = 0
TrackModeold = 0
InfoUpdate = false

function onTick()
    debug.log("$$" .. "onTick------------------------------------------------")
    if gB(29) then
        debug.log("$$" .. "inputPhys_29")
        local N = input.getNumber
        Phys = {
            ------------------------------------
            gpsX    = N(1),
            alt     = N(2),
            gpsY    = N(3),
            spdX    = N(7),
            spdY    = N(8),
            spdZ    = N(9),
            AspdX   = N(10),
            AspdY   = N(11),
            AspdZ   = N(12),
            spdABS  = N(13),
            AspdABS = N(14),
            tiltZ   = N(15),
            tiltX   = N(16),
            compass = N(17)
            ------------------------------------
        }
    elseif gB(28) then
        local gN = input.getNumber
        debug.log("$$" .. "Cursor_input")
        if (InfoUpdate) then
            TrackMode = gN(15)
            InfoUpdate = false
        end
        if (TrackModeold ~= gN(15)) then
            InfoUpdate = true
        else
            InfoUpdate = false
        end
        --scan range
        FOV = gN(5) == 0 and property.getNumber("FOV (degree)") / 2 or gN(5) / 2
        SHOWDISTANCE = gN(6) == 0 and property.getNumber("ViewDistance(m)") or gN(6)

        --mode
        if (not InfoUpdate) then
            tgtLock = gN(10) == 1
            modechange = ((gB(1) and gN(3) <= 12 and gN(4) >= h - 5) or gN(11) == 1)
            if not modechange and tgtLock and TrackMode == 0 then --RWSmode >> ACQmode
                TrackMode = 1                                 --to Scan
            elseif modechange and TrackMode == 0 then         --RWSmode >> TWSmode
                TrackMode = 3                                 --to twsscan
            elseif tgtLock and TrackMode == 2 then            --STTmode >> RWSmode
                TrackMode = 0                                 --to None
            elseif not tgtLock and TrackMode == 1 then        --ACQmode >> RWSmode
                TrackMode = 0                                 --to None
            elseif modechange and TrackMode == 3 then         --TWSmode >> RWSmode
                TrackMode = 0                                 --to None
            elseif TrackMode == 4 and (gB(1) or gN(8) ~= 0 or gN(9) ~= 0) then
                TrackMode = 3                                 --to twsscan
            end
        end
        FOV = TrackMode == 1 and 5 or FOV
        FOV = TrackMode == 2 and MaxFOV or FOV


        --cursor input
        if TrackMode == 0 or TrackMode == 3 or (TrackMode == 4 and (gB(1) or gN(8) ~= 0 or gN(9) ~= 0)) then
            Cursor.X = gB(1) and (2 * gN(3) / w - 1) or clamp(Cursor.X + gN(8) / 10, -1, 1)
            Cursor.Y = gB(1) and (2 * gN(4) / h - 1) or clamp(Cursor.Y - gN(9) / 10, -1, 1)
            Cursor.Azimath = Cursor.X * (MaxFOV / 180)
            Cursor.Distance = (1 - Cursor.Y) * SHOWDISTANCE / 2
            Cursor.RdrAzimath = clamp(Cursor.Azimath, -(1 - FOV / MaxFOV) * (MaxFOV / 180),
                (1 - FOV / MaxFOV) * (MaxFOV / 180))
        elseif TrackMode == 1 then
            Cursor.RdrAzimath = Cursor.Azimath
        end
    else
        local N = input.getNumber
        for i = 1, 4 do
            ---@type number
            local num
            num = gB(30) and i or gB(31) and i + 4 or gB(32) and i + 8 --[1]~[12]
            RadioData[num] = {
                ------------------------------------
                x = N(i * 6 - 5),
                y = N(i * 6 - 4),
                z = N(i * 6 - 3),
                roll = N(i * 6 - 2),
                pitch = N(i * 6 - 1),
                com = N(i * 6),
                vid = N(i + 24),
                mslid = 0
                ------------------------------------
            }
            --debug.log("$$" .. "vid : " .. N(i+24))
        end

        ShowData = {}
        for i, data in ipairs(RadioData) do
            --debug.log("$$" .. "RadioData.vid" .. data.vid)
            local distance = getDistance(Phys, data)
            local bearing = getBearing(Phys, data, Cursor.RdrAzimath / 2)
            if (distance <= SHOWDISTANCE) then                                       --distance conditions
                if (math.abs(bearing) <= FOV) and (math.abs(bearing) <= MaxFOV) then --fov conditions
                    if TrackMode == 0 or TrackMode == 3 or TrackMode == 4 then
                        table.insert(ShowData, data)
                        local bearing = getBearing(Phys, data, Cursor.Azimath / 2)
                        if TrackMode == 3 and (distance >= (-Cursor.Y / 2 + .5) * SHOWDISTANCE - 150) and (distance <= (-Cursor.Y / 2 + .5) * SHOWDISTANCE + 150) and (math.abs(bearing) <= 6) then
                            TrackVid = data.vid
                            TrackMode = 4
                            --debug.log("$$" .. "TWSvid : " .. data.vid)
                        end
                    elseif TrackMode == 1 then
                        table.insert(ShowData, data)
                        TrackVid = data.vid
                        TrackMode = 2
                        goto exit
                    elseif TrackMode == 2 and data.vid == TrackVid then
                        table.insert(ShowData, data)
                        goto exit
                    end
                end
            end
        end
        ::exit::

        TargetData = {}
        --debug.log("$$" .. "TrackMode : " .. TrackMode)
        --syncCursor
        for i, data in ipairs(ShowData) do
            if TrackMode == 4 and TrackVid == data.vid then
                --debug.log("$$" .. "SyncCursor")
                local targetazimath = getBearing(Phys, data, 0)
                local targetdistance = getDistance(Phys, data)
                Cursor.X = (targetazimath / MaxFOV)
                Cursor.Y = (targetdistance / SHOWDISTANCE) * -2 + 1
                Cursor.Azimath = targetazimath / 180 --MaxFOV
                Cursor.Distance = targetdistance
                Cursor.RdrAzimath = clamp(Cursor.Azimath, -(1 - FOV / MaxFOV) * (MaxFOV / 180),
                    (1 - FOV / MaxFOV) * (MaxFOV / 180))
                table.insert(TargetData, data)
                --debug.log("$$" .. "targetazimath : " .. targetazimath)
                break
            end
        end


        --target lost
        if TrackMode == 2 and next(ShowData) == nil then
            TrackMode = 0
            TrackVid = nil
        end
        if TrackMode == 4 and next(TargetData) == nil then
            TrackMode = 3
            TrackVid = nil
        end
    end

    if gB(29) then
        --[[sN(1, Phys.gpsX)
		sN(2, Phys.alt)
		sN(3, Phys.gpsY)
		sN(4, Phys.spdX)
		sN(5, Phys.spdY)
		sN(6, Phys.spdZ)
		sN(7, Phys.AspdX)
		sN(8, Phys.AspdY)
		sN(9, Phys.AspdZ)
		sN(10, Phys.spdABS)
		sN(11, Phys.AspdABS)
		sN(12, Phys.tiltZ)
		sN(13, Phys.tiltX)
		sN(14, Phys.compass)
		output.setBool(29, true)]]
    elseif gB(28) then
        debug.log("$$" .. "Cursor_output")
        output.setBool(28, true)
    else
        for i = 1, 8 do
            --debug.log("$$" .. "ShowData : " .. #ShowData)
            if TrackMode == 2 or TrackMode == 3 or TrackMode == 4 then
                sN(i * 4 - 3, ShowData[i] == nil and 0 or ShowData[i].x)
                sN(i * 4 - 2, ShowData[i] == nil and 0 or ShowData[i].y)
                sN(i * 4 - 1, ShowData[i] == nil and 0 or ShowData[i].z)
                if (TrackMode == 2 or TrackMode == 4) and (ShowData[i] == nil and 0 or ShowData[i].vid) == TrackVid then
                    sN(i * 4, ShowData[i] == nil and 0 or -ShowData[i].vid)
                else
                    local vid = math.abs(ShowData[i] == nil and 0 or ShowData[i].vid)
                    sN(i * 4, vid)
                end
                --debug.log("$$" .. "SendVidlist : " .. target.vid)
            else
                sN(i * 4 - 3, 0)
                sN(i * 4 - 2, 0)
                sN(i * 4 - 1, 0)
                sN(i * 4, 0)
            end
        end
        --debug.log("$$" .. "XYZ : " .. target.x  .. ",".. target.y .. "," .. target.z )
        output.setBool(28, false)
        output.setBool(29, false)
    end
    debug.log("$$" .. "end")
    if TrackMode == 2 or TrackMode == 4 then
        output.setBool(31, true)
    else
        output.setBool(31, false)
    end
    sN(6, TrackMode)
    output = TrackVid == nil and 0 or TrackVid
    sN(7, output)
    TrackModeold = TrackMode
end

function clamp(value, min, Max)
    return math.min(math.max(value, min), Max)
end

function getDistance(PhysData, Target)
    local sx, sy, sz = PhysData.gpsX, PhysData.alt, PhysData.gpsY
    local tx, ty, tz = Target.x, Target.y, Target.z

    return math.sqrt((sx - tx) ^ 2 + (sy - ty) ^ 2 + (sz - tz) ^ 2)
end

function getBearing(physData, target, azimath)
    local sx, sz = physData.gpsX, physData.gpsY
    local tx, tz = target.x, target.z
    return set_deg((math.atan(tx - sx, tz - sz) * (180 / math.pi) + ((physData.compass - azimath) % 1) * 360) % 360)
end

function set_deg(angle)
    if angle > 180 then
        angle = angle - 360
    end

    if angle < -180 then
        angle = angle + 180
    end

    return angle
end

function onDraw()
    w, h = screen.getWidth(), screen.getHeight()
    screen.setColor(bgR, bgG, bgB, 90)
    screen.drawRectF(0, 0, w, h)
    screen.setColor(bgR, bgG, bgB, 95)
    screen.drawRectF(TrackMode == 2 and 0 or w / 2 * (1 - (FOV / MaxFOV) + Cursor.RdrAzimath * (180 / MaxFOV)), 0,
        w * (FOV / MaxFOV), h)
    screen.setColor(flR, flG, flB)
    screen.drawRect(0, 0, w - 1, h - 1)
    screen.drawRect(w * (1 / 7), 0, w * (6 / 7) - w * (1 / 7), h - 1)
    screen.drawRect(w * (2 / 7), 0, w * (5 / 7) - w * (2 / 7), h - 1)
    screen.drawRect(w * (3 / 7), 0, w * (4 / 7) - w * (3 / 7), h - 1)
    screen.drawRect(0, h * (1 / 4), w - 1, h * (3 / 4) - h * (1 / 4))
    screen.drawLine(0, h / 2, w - 1, h / 2)

    --info screen
    screen.setColor(tgR, tgG, tgB)
    --screen.drawText(0, 0, string.format("%0.0f", FOV * 2))
    --screen.drawText(0, 6, string.format("%0.1f", SHOWDISTANCE / 1000))

    --search mode
    if TrackMode == 0 then
        screen.drawText(0, h - 5, "RWS")
        --cursor
        screen.drawLine(Cursor.X * w / 2 - w / 32 + w / 2, Cursor.Y * h / 2 - h / 32 + h / 2, Cursor.X * w / 2 - w / 32 +
            w / 2, Cursor.Y * h / 2 - h / 32 + h / 16 + h / 2)
        screen.drawLine(Cursor.X * w / 2 - w / 32 + w / 16 + w / 2, Cursor.Y * h / 2 - h / 32 + h / 2,
            Cursor.X * w / 2 - w / 32 + w / 16 + w / 2, Cursor.Y * h / 2 - h / 32 + h / 16 + h / 2)
        --screen.drawText(0, 12, string.format("%0.0f", Cursor.X))
        --screen.drawText(0, 18, string.format("%0.0f", Cursor.Y))
    elseif TrackMode == 1 then
        screen.drawText(0, h - 5, "ACQ")
    elseif TrackMode == 2 then
        screen.drawText(0, h - 5, "STT")
    elseif TrackMode == 3 or TrackMode == 4 then
        screen.drawText(0, h - 5, "TWS")
        --cursor
        screen.drawLine(Cursor.X * w / 2 - w / 32 + w / 2, Cursor.Y * h / 2 - h / 32 + h / 2,
            Cursor.X * w / 2 - w / 32 + w / 2, Cursor.Y * h / 2 - h / 32 + h / 16 + h / 2)
        screen.drawLine(Cursor.X * w / 2 - w / 32 + w / 16 + w / 2, Cursor.Y * h / 2 - h / 32 + h / 2,
            Cursor.X * w / 2 - w / 32 + w / 16 + w / 2, Cursor.Y * h / 2 - h / 32 + h / 16 + h / 2)
        --screen.drawText(0, 12, string.format("%0.0f", Cursor.X))
        --screen.drawText(0, 18, string.format("%0.0f", Cursor.Y))
        if TrackMode == 4 then
            screen.drawText(w - 12, h - 5, "Lck")
        end
    else
        screen.drawText(0, h - 5, "ERR")
    end
    for i, data in ipairs(ShowData) do
        local targetazimath = getBearing(Phys, data, 0)
        local targetdistance = getDistance(Phys, data)
        screen.drawRectF(w / 2 - w / 64 + (targetazimath / MaxFOV) * w / 2, h * (1 - (targetdistance / SHOWDISTANCE)),
            w / 32, h / 32)

        if TrackMode == 2 then
            screen.setColor(bgR, bgG, bgB, 95)
            screen.drawLine(w / 2 + (targetazimath / MaxFOV) * w / 2, h * (1 - (targetdistance / SHOWDISTANCE)),
                w / 2 + (targetazimath / MaxFOV) * w / 2, h)
        end
    end
end
