--[[
    RWS/TWS/STT/ACMモードを搭載したレーダーシステム
    物理ボタン、または画面タッチでモード切替が可能どす。
]]

-- ライブラリとプロパティの読み込み
gB, sN = input.getBool, output.setNumber
SHOWDISTANCE = 0
FOV = 0
MaxFOV = property.getNumber("MaxFOV (degree)") / 2

-- 色設定
bgR, bgG, bgB = property.getNumber("Background R"), property.getNumber("Background G"), property.getNumber("Background B")
flR, flG, flB = property.getNumber("Frame R"), property.getNumber("Frame G"), property.getNumber("Frame B")
tgR, tgG, tgB = property.getNumber("Target R"), property.getNumber("Target G"), property.getNumber("Target B")

-- 物理・状態変数の初期化
Phys = {
    gpsX = 0, alt = 0, gpsY = 0,
    spdX = 0, spdY = 0, spdZ = 0,
    AspdX = 0, AspdY = 0, AspdZ = 0,
    spdABS = 0, AspdABS = 0,
    tiltZ = 0, tiltX = 0, compass = 0
}
RadioData = {}
ShowData = {}
TargetData = {}

TrackMode = 0 -- 0=RWS, 1=ACQ, 2=STT, 3=TWS Scan, 4=TWS Lock, 5=ACM
TrackVid = nil
Cursor = { X = 0, Y = 0, Azimath = 0, Distance = 0, RdrAzimath = 0 }
w, h = 0, 0
TrackModeold = 0
InfoUpdate = false

-- ACMモードのダブルクリック検知用
acm_button_timer = 0
acm_button_last_press = false

--------------------------------------------------------------------------------
-- メインループ
--------------------------------------------------------------------------------
function onTick()
    -- 機体の正面方向ベクトルを毎フレーム計算
    local pitch_rad = Phys.tiltX * 2 * math.pi
    local yaw_rad = Phys.compass * 2 * math.pi
    local forward_vec = {
        x = math.cos(pitch_rad) * math.sin(yaw_rad),
        y = math.sin(pitch_rad),
        z = math.cos(pitch_rad) * math.cos(yaw_rad)
    }

    -- 物理データ入力
    if gB(29) then
        local N = input.getNumber
        Phys = {
            gpsX = N(1), alt = N(2), gpsY = N(3),
            spdX = N(7), spdY = N(8), spdZ = N(9),
            AspdX = N(10), AspdY = N(11), AspdZ = N(12),
            spdABS = N(13), AspdABS = N(14),
            tiltZ = N(15), tiltX = N(16), compass = N(17)
        }
    -- カーソル・モード入力
    elseif gB(28) then
        local gN = input.getNumber
        if (InfoUpdate) then
            TrackMode = gN(15)
            InfoUpdate = false
        end
        if (TrackModeold ~= gN(15)) then
            InfoUpdate = true
        else
            InfoUpdate = false
        end
        
        -- スキャン範囲の基本設定
        FOV = gN(5) == 0 and property.getNumber("FOV (degree)") / 2 or gN(5) / 2
        SHOWDISTANCE = gN(6) == 0 and property.getNumber("ViewDistance(m)") or gN(6)

        -- モード変更ロジック
        if (not InfoUpdate) then
            local tgtLock = gN(10) == 1
            
            -- ★ 修正: タッチパネルでのモード変更を復活させました
            local touch_area_pressed = gB(1) and gN(3) <= 12 and gN(4) >= h - 5
            local physical_button_pressed = gN(11) == 1
            local mode_switch_input = touch_area_pressed or physical_button_pressed

            -- モードボタンが押された瞬間の処理
            if mode_switch_input and not acm_button_last_press then
                if TrackMode == 5 then
                    -- ★ ACMモード中に押されたらRWSモードに戻る
                    TrackMode = 0
                    acm_button_timer = 0
                else
                    -- ACMモード以外ならダブルクリック判定を開始
                    if acm_button_timer > 0 then
                        -- ★ ダブルクリック成功: ACMモードへ移行しカーソルをリセット
                        TrackMode = 5
                        Cursor.X = 0
                        Cursor.Y = 0
                        acm_button_timer = 0
                    else
                        acm_button_timer = 5 -- シングルクリックの開始
                    end
                end
            end
            acm_button_last_press = mode_switch_input

            if acm_button_timer > 0 then
                acm_button_timer = acm_button_timer - 1
                if acm_button_timer == 0 then -- 時間切れなら通常のTWS/RWS切替
                    if TrackMode == 0 then TrackMode = 3      -- RWS -> TWS
                    elseif TrackMode == 3 then TrackMode = 0   -- TWS -> RWS
                    end
                end
            end

            -- 通常のモード遷移
            if not modechange and tgtLock and TrackMode == 0 then TrackMode = 1
            elseif tgtLock and TrackMode == 2 then TrackMode = 0
            elseif not tgtLock and TrackMode == 1 then TrackMode = 0
            elseif TrackMode == 4 and (gB(1) or gN(8) ~= 0 or gN(9) ~= 0) then TrackMode = 3
            end
        end
        
        -- 各モード用のパラメータ設定
        if TrackMode == 5 then -- ACM
            FOV = 15
            SHOWDISTANCE = 5000
            Cursor.X = 0
            Cursor.Y = 0
        elseif TrackMode == 1 then -- ACQ
            FOV = 5
        elseif TrackMode == 2 then -- STT
            FOV = MaxFOV
        end

        -- カーソル入力処理
        if TrackMode == 0 or TrackMode == 3 or (TrackMode == 4 and (gB(1) or gN(8) ~= 0 or gN(9) ~= 0)) then
            Cursor.X = gB(1) and (2 * gN(3) / w - 1) or clamp(Cursor.X + gN(8) / 10, -1, 1)
            Cursor.Y = gB(1) and (2 * gN(4) / h - 1) or clamp(Cursor.Y - gN(9) / 10, -1, 1)
        end
        
        Cursor.Azimath = Cursor.X * (MaxFOV / 180)
        Cursor.Distance = (1 - Cursor.Y) * SHOWDISTANCE / 2
        Cursor.RdrAzimath = clamp(Cursor.Azimath, -(1 - FOV / MaxFOV) * (MaxFOV / 180), (1 - FOV / MaxFOV) * (MaxFOV / 180))
        
        if TrackMode == 1 then
            Cursor.RdrAzimath = Cursor.Azimath
        end
    -- レーダーデータ入力と処理
    else
        local N = input.getNumber
        for i = 1, 4 do
            local num = gB(30) and i or gB(31) and i + 4 or gB(32) and i + 8
            RadioData[num] = {
                x = N(i*6-5), y = N(i*6-4), z = N(i*6-3),
                roll = N(i*6-2), pitch = N(i*6-1), com = N(i*6),
                vid = N(i+24), mslid = 0
            }
        end

        ShowData = {}
        TargetData = {}

        for _, data in ipairs(RadioData) do
            if data and data.vid ~= 0 then
                local distance = getDistance(Phys, data)

                if (distance <= SHOWDISTANCE) then
                    -- ACMモードの処理 (3Dベクトル)
                    if TrackMode == 5 then
                        local target_vec = { x = data.x - Phys.gpsX, y = data.y - Phys.alt, z = data.z - Phys.gpsY }
                        local forward_vec_norm = normalize(forward_vec)
                        local target_vec_norm = normalize(target_vec)
                        local angle_cos = dot(forward_vec_norm, target_vec_norm)
                        local threshold_cos = math.sin(10 * math.pi / 180)
                        --debug.log("$$" .. "angle_cos: " .. angle_cos .. "threshold_cos: " .. threshold_cos)
                        
                        if math.abs(angle_cos) < threshold_cos then
                            local data_to_show = {
                                x = data.x, y = data.y, z = data.z, vid = data.vid,
                                distance = distance, bearing = getBearing(Phys, data, 0)
                            }
                            table.insert(ShowData, data_to_show)
                            TrackVid = data.vid
                            TrackMode = 2 -- STTへ移行
                            break
                        end
                    -- RWS/TWS/STTの処理 (水平面方位)
                    else
                        local bearing = getBearing(Phys, data, Cursor.RdrAzimath / 2)
                        
                        if (math.abs(bearing) <= FOV) and (math.abs(bearing) <= MaxFOV) then
                            local data_to_show = {
                                x = data.x, y = data.y, z = data.z, vid = data.vid,
                                distance = distance, bearing = getBearing(Phys, data, 0)
                            }
                            
                            if TrackMode == 0 or TrackMode == 3 or TrackMode == 4 then
                                table.insert(ShowData, data_to_show)
                                local bearing_for_lock = getBearing(Phys, data, Cursor.Azimath / 2)
                                if TrackMode == 3 and (distance >= Cursor.Distance - 150) and (distance <= Cursor.Distance + 150) and (math.abs(bearing_for_lock) <= 6) then
                                    TrackVid = data.vid
                                    TrackMode = 4
                                end
                            elseif TrackMode == 1 then
                                table.insert(ShowData, data_to_show)
                                TrackVid = data.vid
                                TrackMode = 2
                                break
                            elseif TrackMode == 2 and data.vid == TrackVid then
                                table.insert(ShowData, data_to_show)
                                break
                            end
                        end
                    end
                end
            end
        end

        -- ターゲット追跡とロスト処理
        local target_found_in_stt = false
        local target_found_in_tws = false

        for _, data in ipairs(ShowData) do
            if TrackMode == 4 and TrackVid == data.vid then
                Cursor.X = data.bearing / MaxFOV
                Cursor.Y = (data.distance / SHOWDISTANCE) * -2 + 1
                table.insert(TargetData, data)
                target_found_in_tws = true
                break
            end
        end
        if TrackMode == 2 and #ShowData > 0 then
            target_found_in_stt = true
        end
        if TrackMode == 2 and not target_found_in_stt then
            TrackMode = 0
            TrackVid = nil
        end
        if TrackMode == 4 and not target_found_in_tws then
            TrackMode = 3
            TrackVid = nil
        end
    end

    -- 出力処理
    if gB(29) then
        -- (コメントアウト)
    elseif gB(28) then
        output.setBool(28, true)
    else
        for i = 1, 8 do
            local data = ShowData[i]
            if data and (TrackMode == 2 or TrackMode == 3 or TrackMode == 4) then
                sN(i*4-3, data.x)
                sN(i*4-2, data.y)
                sN(i*4-1, data.z)
                if (TrackMode == 2 or TrackMode == 4) and data.vid == TrackVid then
                    sN(i*4, -data.vid)
                else
                    sN(i*4, math.abs(data.vid))
                end
            else
                sN(i*4-3, 0); sN(i*4-2, 0); sN(i*4-1, 0); sN(i*4, 0)
            end
        end
        output.setBool(28, false)
        output.setBool(29, false)
    end
    
    output.setBool(31, TrackMode == 2 or TrackMode == 4)
    sN(6, TrackMode)
    sN(7, TrackVid or 0)
    TrackModeold = TrackMode
end

--------------------------------------------------------------------------------
-- 描画
--------------------------------------------------------------------------------
function onDraw()
    w, h = screen.getWidth(), screen.getHeight()
    
    -- 背景
    screen.setColor(bgR, bgG, bgB, 90)
    screen.drawRectF(0, 0, w, h)
    screen.setColor(bgR, bgG, bgB, 95)
    screen.drawRectF(TrackMode == 2 and 0 or w/2*(1-(FOV/MaxFOV)+Cursor.RdrAzimath*(180/MaxFOV)), 0, w*(FOV/MaxFOV), h)
    
    -- フレーム
    screen.setColor(flR, flG, flB)
    screen.drawRect(0, 0, w - 1, h - 1)
    screen.drawRect(w / 7, 0, w * 5 / 7, h - 1)
    screen.drawRect(w * 2 / 7, 0, w * 3 / 7, h - 1)
    screen.drawRect(w * 3 / 7, 0, w / 7, h - 1)
    screen.drawRect(0, h / 4, w - 1, h / 2)
    screen.drawLine(0, h / 2, w - 1, h / 2)
    
    -- モード表示
    screen.setColor(tgR, tgG, tgB)
    local mode_text = "ERR"
    if TrackMode == 0 then mode_text = "RWS"
    elseif TrackMode == 1 then mode_text = "ACQ"
    elseif TrackMode == 2 then mode_text = "STT"
    elseif TrackMode == 3 or TrackMode == 4 then mode_text = "TWS"
    elseif TrackMode == 5 then mode_text = "ACM"
    end
    screen.drawText(0, h - 5, mode_text)

    -- カーソル
    if TrackMode == 0 or TrackMode == 3 or TrackMode == 4 then
        local cX, cY = Cursor.X * w / 2 + w / 2, Cursor.Y * h / 2 + h / 2
        screen.drawLine(cX - w/32, cY - h/32, cX - w/32, cY + h/32)
        screen.drawLine(cX + w/32, cY - h/32, cX + w/32, cY + h/32)
        if TrackMode == 4 then screen.drawText(w - 12, h - 5, "Lck") end
    end

    -- ACMスキャン範囲
    if TrackMode == 5 then
        local acm_box_w = w / 8
        screen.setColor(flR, flG, flB)
        screen.drawRect(w / 2 - acm_box_w / 2, h / 8, acm_box_w, h * 3 / 4)
    end
    
    -- ターゲット
    screen.setColor(tgR, tgG, tgB)
    for _, data in ipairs(ShowData) do
        local targetX = w / 2 - w / 64 + (data.bearing / MaxFOV) * w / 2
        local targetY = h * (1 - (data.distance / SHOWDISTANCE))
        screen.drawRectF(targetX, targetY, w / 32, h / 32)

        if TrackMode == 2 and data.vid == TrackVid then
            screen.setColor(bgR, bgG, bgB, 95)
            local lineX = w / 2 + (data.bearing / MaxFOV) * w / 2
            screen.drawLine(lineX, targetY, lineX, h)
            screen.setColor(tgR, tgG, tgB)
        end
    end
end

--------------------------------------------------------------------------------
-- ヘルパー関数
--------------------------------------------------------------------------------

-- 値を範囲内に収める
function clamp(value, min, Max)
    return math.min(math.max(value, min), Max)
end

-- 距離計算
function getDistance(PhysData, Target)
    local sx, sy, sz = PhysData.gpsX, PhysData.alt, PhysData.gpsY
    local tx, ty, tz = Target.x, Target.y, Target.z
    return math.sqrt((sx - tx)^2 + (sy - ty)^2 + (sz - tz)^2)
end

-- 水平面の方位角計算
function getBearing(physData, target, azimath)
    local sx, sz = physData.gpsX, physData.gpsY
    local tx, tz = target.x, target.z
    local bearing_rad = math.atan(tx - sx, tz - sz)
    local bearing_deg = bearing_rad * (180 / math.pi)
    local final_bearing = bearing_deg + ((physData.compass - azimath) % 1) * 360
    return set_deg(final_bearing)
end

-- 角度を-180～180に正規化
function set_deg(angle)
    angle = angle % 360
    if angle > 180 then angle = angle - 360
    elseif angle < -180 then angle = angle + 360 end
    return angle
end

-- ベクトルを正規化 (長さを1に)
function normalize(vec)
    local len = math.sqrt(vec.x^2 + vec.y^2 + vec.z^2)
    if len > 0 then
        return { x = vec.x / len, y = vec.y / len, z = vec.z / len }
    end
    return { x = 0, y = 0, z = 1 }
end

-- 2つのベクトルの内積を計算
function dot(v1, v2)
    return v1.x * v2.x + v1.y * v2.y + v1.z * v2.z
end