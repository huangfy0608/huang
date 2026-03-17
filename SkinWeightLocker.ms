/*
    Skin Weight Locker for 3ds Max
    功能：在 Skin 编辑模式下锁定选中骨骼的权重，防止其它骨骼修改锁定骨骼的权重。
*/

global SWL_State

global SWL_VertexLockData
global SWL_StateStruct
global swl_GetSkinModifier
global swl_GetBoneIDByNode
global swl_GetCurrentSelectedBoneIDs
global swl_CreateLockData
global swl_EnforceLocks
global SWL_UI
global SWL_ShowUI

global swl_StopTimer

struct SWL_VertexLockData (
    weightsByBoneID -- #( #(boneID, weight), ... ) per vertex index (1-based)
)

struct SWL_StateStruct (
    node,
    skinMod,
    lockedBoneIDs = #(),
    lockData,
    timer,
    enabled = false
)

fn swl_GetSkinModifier obj = (
    if obj == undefined then return undefined
    for m in obj.modifiers where (classOf m == Skin) do return m
    undefined
)

fn swl_GetBoneIDByNode skinMod boneNode = (
    local boneCount = skinOps.GetNumberBones skinMod
    for i = 1 to boneCount do (
        local n = skinOps.GetBoneName skinMod i 1
        if n != undefined and n == boneNode do return i
    )
    undefined
)

fn swl_GetCurrentSelectedBoneIDs skinMod = (
    local ids = #()

    -- 支持通过场景选择骨骼进行批量锁定
    for n in selection do (
        local id = swl_GetBoneIDByNode skinMod n
        if id != undefined do appendIfUnique ids id
    )

    -- 支持 Skin 面板中单个当前选中骨骼
    local currentID = skinOps.GetSelectedBone skinMod
    if currentID != undefined and currentID > 0 do appendIfUnique ids currentID

    ids
)

fn swl_CreateLockData skinMod boneIDs = (
    local vertCount = skinOps.GetNumberVertices skinMod
    local arr = for v = 1 to vertCount collect #()

    for v = 1 to vertCount do (
        local wc = skinOps.GetVertexWeightCount skinMod v
        for w = 1 to wc do (
            local bID = skinOps.GetVertexWeightBoneID skinMod v w
            if (findItem boneIDs bID) > 0 do (
                local wt = skinOps.GetVertexWeight skinMod v w
                append arr[v] #(bID, wt)
            )
        )
    )

    SWL_VertexLockData weightsByBoneID:arr
)

fn swl_EnforceLocks skinMod lockData = (
    if lockData == undefined then return false

    local vertCount = skinOps.GetNumberVertices skinMod

    for v = 1 to vertCount do (
        local lockedPairs = lockData.weightsByBoneID[v]
        if lockedPairs.count == 0 do continue

        local wc = skinOps.GetVertexWeightCount skinMod v
        local curPairs = #() -- #( #(boneID, weight), ... )
        for w = 1 to wc do (
            append curPairs #(skinOps.GetVertexWeightBoneID skinMod v w, skinOps.GetVertexWeight skinMod v w)
        )

        local targetLockedSum = 0.0
        local curLockedSum = 0.0

        for lp in lockedPairs do targetLockedSum += lp[2]
        for cp in curPairs do (
            for lp in lockedPairs where cp[1] == lp[1] do curLockedSum += cp[2]
        )

        local unlockedCurSum = 1.0 - curLockedSum
        local unlockedTargetSum = 1.0 - targetLockedSum
        local scale = 1.0
        if unlockedCurSum > 1e-6 then scale = unlockedTargetSum / unlockedCurSum else scale = 0.0

        local outBoneIDs = #()
        local outWeights = #()

        -- 先写锁定骨骼权重（使用快照值）
        for lp in lockedPairs do (
            append outBoneIDs lp[1]
            append outWeights lp[2]
        )

        -- 其它骨骼按比例缩放，保留其相对分布
        for cp in curPairs do (
            local isLocked = false
            for lp in lockedPairs where cp[1] == lp[1] do isLocked = true

            if not isLocked do (
                append outBoneIDs cp[1]
                append outWeights (cp[2] * scale)
            )
        )

        if outBoneIDs.count > 0 do skinOps.ReplaceVertexWeights skinMod v outBoneIDs outWeights
    )

    true
)

fn swl_StopTimer = (
    if SWL_State != undefined and SWL_State.timer != undefined do (
        try(SWL_State.timer.Stop())catch()
        SWL_State.timer = undefined
    )
)

rollout SWL_UI "Skin Weight Locker" width:300 height:230
(
    label lb1 "1) 选择带 Skin 的模型"
    label lb2 "2) 进入 Edit Envelopes / Paint Weights"
    label lb3 "3) 选择要锁定的骨骼（场景中或 Skin 面板）"
    button btSetTarget "设置当前目标模型" width:280
    button btLock "锁定当前选中骨骼权重" width:280
    button btUnlock "清除锁定" width:280
    checkbox cbAuto "自动持续约束（推荐）" checked:true
    button btApply "手动执行一次约束" width:280
    label lbStatus "状态：未设置" width:280

    fn refreshStatus = (
        if SWL_State == undefined or SWL_State.skinMod == undefined then (
            lbStatus.text = "状态：未设置"
        ) else (
            lbStatus.text = ("状态：已锁定骨骼数 " + (SWL_State.lockedBoneIDs.count as string))
        )
    )

    on btSetTarget pressed do (
        if selection.count != 1 then (
            messageBox "请先选择一个带 Skin 的物体。"
            return()
        )

        local obj = selection[1]
        local s = swl_GetSkinModifier obj
        if s == undefined then (
            messageBox "该物体没有 Skin 修改器。"
            return()
        )

        SWL_State = SWL_StateStruct node:obj skinMod:s lockedBoneIDs:#() lockData:undefined enabled:cbAuto.checked
        refreshStatus()
    )

    on btLock pressed do (
        if SWL_State == undefined or SWL_State.skinMod == undefined then (
            messageBox "请先点击“设置当前目标模型”。"
            return()
        )

        local ids = swl_GetCurrentSelectedBoneIDs SWL_State.skinMod
        if ids.count == 0 then (
            messageBox "未检测到已选骨骼，请在场景中选择骨骼或在 Skin 面板选中骨骼。"
            return()
        )

        SWL_State.lockedBoneIDs = ids
        SWL_State.lockData = swl_CreateLockData SWL_State.skinMod ids
        SWL_State.enabled = cbAuto.checked
        refreshStatus()
    )

    on btUnlock pressed do (
        if SWL_State != undefined do (
            SWL_State.lockedBoneIDs = #()
            SWL_State.lockData = undefined
            SWL_State.enabled = false
        )
        refreshStatus()
    )

    on btApply pressed do (
        if SWL_State == undefined or SWL_State.skinMod == undefined or SWL_State.lockData == undefined then (
            messageBox "没有可执行的锁定数据。"
            return()
        )

        swl_EnforceLocks SWL_State.skinMod SWL_State.lockData
        refreshStatus()
    )

    on cbAuto changed state do (
        if SWL_State != undefined do SWL_State.enabled = state
    )

    on SWL_UI close do (
        swl_StopTimer()
    )
)

fn SWL_ShowUI = (
    try(destroyDialog SWL_UI)catch()
    createDialog SWL_UI style:#(#style_titlebar, #style_sysmenu, #style_minimizebox)

    swl_StopTimer()
    local timer = dotNetObject "System.Windows.Forms.Timer"
    timer.Interval = 250
    dotNet.addEventHandler timer "Tick" (fn onTick s e = (
        if SWL_State == undefined then return()
        if SWL_State.enabled != true then return()
        if SWL_State.skinMod == undefined or SWL_State.lockData == undefined then return()
        swl_EnforceLocks SWL_State.skinMod SWL_State.lockData
    ))
    timer.Start()

    if SWL_State == undefined then SWL_State = SWL_StateStruct()
    SWL_State.timer = timer
)

macroScript SkinWeightLocker
category:"RiggingTools"
toolTip:"Skin Weight Locker"
buttonText:"SkinWeightLocker"
(
    SWL_ShowUI()
)

-- 直接 Run Script 时也会弹出 UI，避免只定义 macro 不显示界面
SWL_ShowUI()
