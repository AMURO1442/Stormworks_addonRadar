require("yukimaru73.SWLib.PhysicsSensorLib")
require("yukimaru73.SWLib.Vector3")
require("yukimaru73.SWLib.PID")

--I/O定義
--[[Inputs
	------------------------------------PHS
	01: GPS X
	02: GPS Y
	03: GPS Z
	04: Euler X
	05: Euler Y
	06: Euler Z
	07: Local Velocity X
	08: Local Velocity Y
	09: Local Velocity Z
	10: Global angular velocity X
	11: Global angular velocity Y
	12: Global angular velocity Z
	13: Liner Velocity ABS
	14: Angular Velocity ABS
	------------------------------------Target Data
	21: Target GPS X
	22: Target GPS Y
	23: Target GPS Z
	24: Target Velocity X
	25: Target Velocity Y
	26: Target Velocity Z
	27: Target Acceralation X
	28: Target Acceralation Y
	29: Target Acceralation Z
	------------------------------------Numerical Inputs
	30: timelag of target datas
	31: isLaunched(0/1)
]]

--- PN: Proportional Navigation
---@param Pm Vector3 -- missile position
---@param Vm Vector3 -- missile velocity
---@param Pt Vector3 -- target position
---@param Vt Vector3 -- target velocity
---@param Ne number -- normal engagement factor
---@overload fun(Pm: Vector3, Vm: Vector3, Pt: Vector3, Vt: Vector3, Ne: number): Vector3
---@overload fun(Pm: Vector3, Vm: Vector3, Pt: Vector3, Vt: Vector3): Vector3
---@return Vector3 accVec, boolean isBack
function PN(Pm, Vm, Pt, Vt, Ne)
	-- calculate LOS vector(R) and relative velocity(Vr)
	local R, Vr = Pt:sub(Pm), Vm:sub(Vt)

	-- calculate norm of Euclid LOS Norm(R) and Euclid Vel Norm(Vr)
	local R_Norm, VR_Norm = R:getMagnitude(), Vr:getMagnitude()

	-- calculate Navigation Constant(N)
	local N = Ne * VR_Norm / (R:dot(Vm) / R_Norm + 1e-6)

	-- calculate LOS Rate vector(LOSRate)
	local LOSRateVec = Vr:cross(R):mul(1 / (R_Norm * R_Norm))

	return LOSRateVec:cross(Vm):mul(N), R:dot(Vm) < 0
end

--プロパティ
MAX_G = property.getNumber("G")
MAX_G = MAX_G / 60 ^ 2
P = property.getNumber("Kp")
I = property.getNumber("Ki")
D = property.getNumber("Kd")
Im = property.getNumber("Im")
COMM_FILTER_COEF = property.getNumber("CFC")

--インスタンス
PHS = PhysicsSensorLib:new()
PID_YAW = PID:new(P, I, D, Im)
PID_PITCH = PID:new(P, I, D, Im)

--定数
BODY_TIMELAG = 3.5 --tick
TARGET_DATA_TIMELAG = 5 --tick
DIFF_COG = Vector3:new(0, 0, -.51)

--変数
YAW = 0
PITCH = 0
NO_DATA_TIMER = 0
POS_TARGET = Vector3:new()
POS_TARGET_PRE = Vector3:new()
VEL_TARGET = Vector3:new()
VEL_TARGET_DEV = Vector3:new()
ACC = Vector3:new()
MISSILE_COG_P = Vector3:new()

--メインループ
function onTick()
	--PHSの更新
	PHS:update(1)

	--入力
	local targetPosGlobal,
	targetVelGlobal,
	targetAccGlobal,
	timelag,
	missileCoG
	=
	Vector3:new(input.getNumber(21), input.getNumber(22), input.getNumber(23)),
	Vector3:new(input.getNumber(24), input.getNumber(25), input.getNumber(26)),
	Vector3:new(input.getNumber(27), input.getNumber(28), input.getNumber(29)),
	input.getNumber(30),
	PHS:getGPS(BODY_TIMELAG):add(PHS:rotateVector(DIFF_COG, true, BODY_TIMELAG))

	local launched = input.getNumber(31) == 1

	local missileVelGlobal = PHS:rotateVector(PHS.velocity, true)

	--ターゲットデータの処理
	if targetPosGlobal[1] ~= 0 then
		if POS_TARGET_PRE[1] ~= 0 then
			VEL_TARGET_DEV = targetPosGlobal:sub(POS_TARGET_PRE):mul(1 / NO_DATA_TIMER)
		end
		NO_DATA_TIMER = 0
		POS_TARGET_PRE = POS_TARGET
		POS_TARGET = targetPosGlobal
		VEL_TARGET = targetVelGlobal
		--debug.log("$$|| Target Data Received")

	else
		NO_DATA_TIMER = NO_DATA_TIMER + 1
		POS_TARGET = POS_TARGET:add(VEL_TARGET_DEV)
		--POS_TARGET = POS_TARGET:add(VEL_TARGET)
		--debug.log("$$|| No Target Data")
	end

	if launched and VEL_TARGET_DEV[1] ~= 0 then

		--タイムラグ補正
		local targetPosGlobalF = POS_TARGET
			:add(VEL_TARGET:mul(timelag + BODY_TIMELAG))

		--指令加速度の計算
		--local acc, isBack = PN(missileCoG, missileVelGlobal, targetPosGlobalF, VEL_TARGET, 3)
		local acc, isBack = PN(missileCoG, VEL_TARGET_DEV, targetPosGlobalF, VEL_TARGET, 3)
		acc = PHS:rotateVector(acc, false, BODY_TIMELAG)

		--法線加速度の削除
		acc[3] = 0

		--G制限
		local accNorm = acc:getMagnitude()
		acc = accNorm > MAX_G and acc:mul(MAX_G / accNorm) or acc

		--指令加速度の平滑化
		ACC = ACC:mul(COMM_FILTER_COEF):add(acc:mul(1 - COMM_FILTER_COEF))

		local accYaw, accPitch = ACC[1], ACC[2]

		--debug.log("$$|| accG: " .. ACC:getMagnitude() * 60 ^ 2)

		--PID制御
		YAW = PID_YAW:update(accYaw, 0)
		PITCH = PID_PITCH:update(accPitch, 0)
		
	else
		YAW = 0
		PITCH = 0
		ACC = Vector3:new()
		PID_YAW:reset()
		PID_PITCH:reset()
	end

	--出力
	output.setNumber(1, YAW)
	output.setNumber(2, PITCH)

	--値の保存
	POS_TARGET_PRE = targetPosGlobal
	MISSILE_COG_P = missileCoG
end