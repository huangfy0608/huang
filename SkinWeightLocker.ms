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
global swl_EnforceLocksSelected
global SWL_UI
global SWL_ShowUI

global swl_StopTimer
global swl_EnsureSkinContext
global swl_IsSafeAutoContext

struct SWL_VertexLockData (
    weightsByBoneID, -- #( #(boneID, weight), ... ) per vertex index (1-based)
    lockedSumByVertex,
    affectedVerts -- bitarray: 仅包含被锁骨骼影响的顶点
)

struct SWL_StateStruct (
    node,
    skinMod,
    listBoneIDs = #(),
    lockedBoneIDs = #(),
    lockData,
    lockDataDirty = false,
    timer,
    enabled = false
)

fn swl_EnsureSkinContext skinMod = (
    if skinMod == undefined then return false
    try(modPanel.setCurrentObject skinMod)catch()
    true
)

fn swl_IsSafeAutoContext skinMod = (
    if skinMod == undefined then return false

    local curObj = undefined
    try(curObj = modPanel.getCurrentObject())catch(curObj = undefined)
    if curObj != skinMod then return false

    local ok = true
    try(skinOps.GetNumberVertices skinMod)catch(ok = false)
    ok
)

fn swl_GetSkinModifier obj = (
    if obj == undefined then return undefined
    for m in obj.modifiers where (classOf m == Skin) do return m
    undefined
)

fn swl_GetBoneIDByNode skinMod boneNode = (
    if not swl_EnsureSkinContext skinMod then return undefined

    local boneCount = skinOps.GetNumberBones skinMod
    for i = 1 to boneCount do (
        local n = skinOps.GetBoneName skinMod i 1
        if n != undefined and n == boneNode do return i
    )
    undefined
)

fn swl_GetCurrentSelectedBoneIDs skinMod = (
    local ids = #()
    if not swl_EnsureSkinContext skinMod then return ids

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

fn swl_GetAllBoneIDs skinMod = (
    local ids = #()
    if not swl_EnsureSkinContext skinMod then return ids

    local boneCount = 0
    try(boneCount = skinOps.GetNumberBones skinMod)catch(boneCount = 0)
    for i = 1 to boneCount do append ids i
    ids
)

fn swl_GetBoneDisplayName skinMod boneID = (
    if not swl_EnsureSkinContext skinMod then return ("Bone_" + boneID as string)

    local n = undefined
    try(n = skinOps.GetBoneName skinMod boneID 1)catch(n = undefined)
    if n == undefined then ("Bone_" + boneID as string) else (n as string)
)

fn swl_GetCheckedBoneIDsFromUI clb skinMod = (
    local ids = #()
    if clb == undefined then return ids

    local count = clb.Items.Count
    for i = 0 to (count - 1) do (
        if clb.GetItemChecked i do append ids (i + 1)
    )
    ids
)

fn swl_CreateLockData skinMod boneIDs = (
    if not swl_EnsureSkinContext skinMod then return SWL_VertexLockData weightsByBoneID:#() lockedSumByVertex:#() affectedVerts:#{}

    local vertCount = skinOps.GetNumberVertices skinMod
    local arr = for v = 1 to vertCount collect #()
    local lockedSums = for v = 1 to vertCount collect 0.0
    local affected = #{}
    affected.count = vertCount

    for v = 1 to vertCount do (
        local wc = skinOps.GetVertexWeightCount skinMod v
        for w = 1 to wc do (
            local bID = skinOps.GetVertexWeightBoneID skinMod v w
            if (findItem boneIDs bID) > 0 do (
                local wt = skinOps.GetVertexWeight skinMod v w
                append arr[v] #(bID, wt)
                lockedSums[v] += wt
                affected[v] = true
            )
        )
    )

    SWL_VertexLockData weightsByBoneID:arr lockedSumByVertex:lockedSums affectedVerts:affected
)

fn swl_EnforceLocks skinMod lockData vertsToProcess:undefined = (
    if lockData == undefined then return false
    if not swl_EnsureSkinContext skinMod then return false

    local vertCount = skinOps.GetNumberVertices skinMod
    local eps = 0.0001
    local vertsMask = undefined

    if vertsToProcess == undefined then (
        vertsMask = lockData.affectedVerts
    ) else (
        vertsMask = vertsToProcess * lockData.affectedVerts
    )

    for v in vertsMask do (
        local lockedPairs = lockData.weightsByBoneID[v]
        if lockedPairs.count == 0 do continue

        local wc = skinOps.GetVertexWeightCount skinMod v
        local curPairs = #() -- #( #(boneID, weight), ... )
        for w = 1 to wc do (
            append curPairs #(skinOps.GetVertexWeightBoneID skinMod v w, skinOps.GetVertexWeight skinMod v w)
        )

        local targetLockedSum = lockData.lockedSumByVertex[v]
        local curLockedSum = 0.0

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

        -- 只有权重明显变化时才回写，比较时按 boneID 匹配，避免顺序差异导致误写
        local needWrite = false
        if outBoneIDs.count != curPairs.count then (
            needWrite = true
        ) else (
            for i = 1 to outBoneIDs.count while (not needWrite) do (
                local curWeight = undefined
                for cp in curPairs where cp[1] == outBoneIDs[i] do (
                    curWeight = cp[2]
                    exit
                )

                if curWeight == undefined then (
                    needWrite = true
                ) else (
                    if (abs (outWeights[i] - curWeight)) > eps do needWrite = true
                )
            )
        )

        if needWrite and outBoneIDs.count > 0 do skinOps.ReplaceVertexWeights skinMod v outBoneIDs outWeights
    )

    true
)

fn swl_EnforceLocksSelected skinMod lockData = (
    local selectedVerts = undefined
    try(selectedVerts = skinOps.GetSelectedVertices skinMod)catch(selectedVerts = undefined)

    if selectedVerts != undefined and selectedVerts.numberSet > 0 then (
        swl_EnforceLocks skinMod lockData vertsToProcess:selectedVerts
    ) else (
        false
    )
)

fn swl_StopTimer = (
    if SWL_State != undefined and SWL_State.timer != undefined do (
        try(SWL_State.timer.Stop())catch()
        SWL_State.timer = undefined
    )
)

rollout SWL_UI "Skin Weight Locker" width:300 height:360
(
    label lb1 "1) 选择带 Skin 的模型"
    label lb2 "2) 进入 Edit Envelopes / Paint Weights"
    label lb3 "3) 在列表中勾选要锁定的骨骼"
    button btSetTarget "设置当前目标模型" width:280
    dotNetControl clbBones "System.Windows.Forms.CheckedListBox" width:280 height:120
    button btRefreshBones "刷新骨骼列表" width:280
    button btUnlock "清除锁定" width:280
    checkbox cbAuto "自动持续约束（推荐）" checked:false
    button btApply "手动执行一次约束" width:280
    label lbStatus "状态：未设置" width:280

    fn applyLocksFromUI = (
        if SWL_State == undefined or SWL_State.skinMod == undefined then return false

        local ids = swl_GetCheckedBoneIDsFromUI clbBones SWL_State.skinMod
        SWL_State.lockedBoneIDs = ids

        if ids.count == 0 then (
            SWL_State.lockData = undefined
            SWL_State.lockDataDirty = false
            SWL_State.enabled = false
        ) else (
            -- 勾选时仅标记脏数据，避免立即全量重算导致界面刷新/打断编辑
            SWL_State.lockDataDirty = true
            SWL_State.enabled = cbAuto.checked
        )

        true
    )

    fn rebuildBoneList restoreChecks:true = (
        if SWL_State == undefined or SWL_State.skinMod == undefined then return false

        local prevChecked = #()
        if restoreChecks do (
            prevChecked = SWL_State.lockedBoneIDs
        )

        clbBones.Items.Clear()

        local boneIDs = swl_GetAllBoneIDs SWL_State.skinMod
        SWL_State.listBoneIDs = boneIDs

        for boneID in boneIDs do (
            local name = swl_GetBoneDisplayName SWL_State.skinMod boneID
            clbBones.Items.Add ("[" + (boneID as string) + "] " + name)
            if (findItem prevChecked boneID) > 0 do clbBones.SetItemChecked (boneID - 1) true
        )

        applyLocksFromUI()
        true
    )

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

        SWL_State = SWL_StateStruct node:obj skinMod:s listBoneIDs:#() lockedBoneIDs:#() lockData:undefined lockDataDirty:false enabled:cbAuto.checked
        swl_EnsureSkinContext s
        rebuildBoneList restoreChecks:false
        refreshStatus()
    )

    on btRefreshBones pressed do (
        if SWL_State == undefined or SWL_State.skinMod == undefined then (
            messageBox "请先点击“设置当前目标模型”。"
            return()
        )

        rebuildBoneList restoreChecks:true
        refreshStatus()
    )

    on btUnlock pressed do (
        if SWL_State != undefined do (
            local itemCount = clbBones.Items.Count
            for i = 0 to (itemCount - 1) do clbBones.SetItemChecked i false

            SWL_State.lockedBoneIDs = #()
            SWL_State.lockData = undefined
            SWL_State.lockDataDirty = false
            SWL_State.enabled = false
        )
        refreshStatus()
    )

    on btApply pressed do (
        if SWL_State == undefined or SWL_State.skinMod == undefined then (
            messageBox "请先点击“设置当前目标模型”。"
            return()
        )

        if SWL_State.lockedBoneIDs.count == 0 then (
            messageBox "请先在骨骼列表中勾选要锁定的骨骼。"
            return()
        )

        if SWL_State.lockDataDirty or SWL_State.lockData == undefined then (
            SWL_State.lockData = swl_CreateLockData SWL_State.skinMod SWL_State.lockedBoneIDs
            SWL_State.lockDataDirty = false
        )

        if SWL_State.lockData == undefined then (
            messageBox "当前无法生成锁定数据，请在 Skin 编辑状态下重试。"
            return()
        )

        swl_EnforceLocks SWL_State.skinMod SWL_State.lockData
        refreshStatus()
    )

    on cbAuto changed state do (
        if SWL_State != undefined do SWL_State.enabled = state
    )

    on clbBones MouseUp arg do (
        if SWL_State == undefined or SWL_State.skinMod == undefined then return()
        applyLocksFromUI()
        refreshStatus()
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
    timer.Interval = 1200
    dotNet.addEventHandler timer "Tick" (fn onTick s e = (
        if SWL_State == undefined then return()
        if SWL_State.enabled != true then return()
        if SWL_State.skinMod == undefined then return()
        if SWL_State.lockedBoneIDs.count == 0 then return()
        if not swl_IsSafeAutoContext SWL_State.skinMod then return()

        try(
            if SWL_State.lockDataDirty or SWL_State.lockData == undefined then (
                SWL_State.lockData = swl_CreateLockData SWL_State.skinMod SWL_State.lockedBoneIDs
                SWL_State.lockDataDirty = false
            )

            if SWL_State.lockData != undefined do swl_EnforceLocksSelected SWL_State.skinMod SWL_State.lockData
        )catch()
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
