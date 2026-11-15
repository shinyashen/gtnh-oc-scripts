return {
    -- 核电模式
    scheme = {
        -- 模式名(slyb)
        slyb = {
            -- 所使用到的资源
            resource = {
                {
                    name = "gregtech:gt.360k_Helium_Coolantcell",
                    changeName = -1,
                    dmg = 95,
                    count = 14,
                    slot = { 3, 6, 9, 10, 15, 22, 26, 29, 33, 40, 45, 46, 49, 52 }
                },
                {
                    -- name = "gregtech:gt.reactorUraniumQuad",
                    name = "gregtech:gt.rodUranium4",
                    -- changeName = "IC2:reactorUraniumQuaddepleted",
                    changeName = "gregtech:gt.depletedRodUranium4",  
                    dmg = -1,
                    count = 40,
                    slot = {
                        1, 2, 4, 5, 7, 8, 11, 12, 13, 14, 16, 17, 18, 19, 20, 21, 23, 24, 25, 27, 28, 30, 31, 32, 34, 35, 36, 37,
                        38, 39, 41, 42, 43, 44, 47, 48, 50, 51, 53, 54 }
                }
            }
        },
        mox = {
            resource = {
                {
                    name = "gregtech:gt.360k_Helium_Coolantcell",
                    changeName = -1,
                    dmg = 97,
                    count = 14,
                    slot = { 3, 6, 9, 10, 15, 22, 26, 29, 33, 40, 45, 46, 49, 52 }
                },
                {
                    name = "gregtech:gt.rodMOX4",
                    changeName = "gregtech:gt.depletedRodMOX4",
                    dmg = -1,
                    count = 40,
                    slot = {
                        1, 2, 4, 5, 7, 8, 11, 12, 13, 14, 16, 17, 18, 19, 20, 21, 23, 24, 25, 27, 28, 30, 31, 32, 34, 35, 36, 37,
                        38, 39, 41, 42, 43, 44, 47, 48, 50, 51, 53, 54 }
                }
            }
        },
        yghhw = {
            resource = {
                {
                    name = "gregtech:gt.360k_Helium_Coolantcell",
                    changeName = -1,
                    dmg = 90,
                    count = 9,
                    slot = { 5, 9, 11, 25, 31, 37, 45, 47, 51 }
                },
                {
                    name = "gregtech:gt.Quad_Thoriumcell",
                    changeName = "gregtech:gt.Quad_ThoriumcellDep",
                    dmg = -1,
                    count = 26,
                    slot = { 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50, 52, 54 }
                },
                {
                    name = "gregtech:gt.glowstoneCell",
                    changeName = "gregtech:gt.sunnariumCell",
                    dmg = -1,
                    count = 18,
                    slot = { 1, 3, 7, 13, 15, 17, 19, 21, 23, 27, 29, 33, 35, 39, 41, 43, 49, 53 }
                }
            }
        },
        jfy = {
            -- 所使用到的资源
            resource = {
                {
                    name = "gregtech:gt.1080k_Space_Coolantcell",
                    changeName = -1,
                    dmg = 90,
                    count = 14,
                    slot = { 3, 6, 9, 10, 15, 22, 26, 29, 33, 40, 45, 46, 49, 52 }
                },
                {
                    name = "gregtech:gt.rodExcitedUranium4",
                    changeName = "gregtech:gt.depletedRodExcitedUranium4",  
                    dmg = -1,
                    count = 40,
                    slot = {
                        1, 2, 4, 5, 7, 8, 11, 12, 13, 14, 16, 17, 18, 19, 20, 21, 23, 24, 25, 27, 28, 30, 31, 32, 34, 35, 36, 37,
                        38, 39, 41, 42, 43, 44, 47, 48, 50, 51, 53, 54 }
                }
            }
        }
    },
    -- 是否开启控制台日志清理
    clearLog = true,
    -- 每n秒清理一次控制台日志
    cleatLogInterval = 30,
    --[[
     是否开启电量控制(提供一个红石端口,向该端口开启红石信号后开启核电)
     填入电量控制红石端口的地址,默认不启用（-1)
    --]]
    energyLatchRedstone = "fdb10c8e-eeb2-4070-871c-6899e9b7867d",
    -- 全局红石开关地址(必填)
    globalRedstone = "6bd6e793-e61e-4f9a-9cce-c99a1c9804e5",
    --[[
    核电堆配置,可同时配置多台核电并在启动时自己选择开启哪几台,例如下边有2个核电配置，输入1 2即可开两台,只输入2则只启动第二个配置的核电
    方向取值可开启f3来看当前的朝向:
    底面: 0 对应方向:down下、negy
    顶面: 1 对应方向:up上、posy
    背面: 2 对应方向:north北、negz
    前面: 3 对应方向:south南、posz、forward
    右面: 4 对应方向:west西、negx
    左面: 5 对应方向:east东、posx
    --]]
    reactorChamberList = {
        {
            name = "jf堆1", -- 核电堆命名(用于日志打印显示对应的名称)
            scheme = "jfy", -- 模式
            thresholdHeat = 0, -- 预热堆温
            preheatItem = "gregtech:gt.rodUranium4", -- 预热燃料
            reactorChamberAddr = "d4ab5178-5d8b-486e-a136-d2ebc1ebe8f7", -- 核电仓地址
            reactorChamberSide = 3, -- 核电仓方向
            switchRedstone = "5cd8243c-8a38-422a-9494-d7bc80674ab2", -- 开关核电的红石端口地址
            reactorChamberSideToRS = 3, -- 核电仓相对于红石信号器的方向 旧版本更新的话默认填写nil即可会取{reactorChamberSide}的方向
            transforAddr = "465c2536-087b-4477-972d-e6896ebba930", -- 转运器地址
            inputSide = 0, -- 输入原材料的箱子位置
            outputSide = 0, -- 输出低耐久冷却单元的箱子位置
            changeItemOutputSide = 0, -- 输出枯竭燃料棒
            tempSide = 0, -- 堆加热的东西的箱子位置
            energy = nil -- 是否参与电量控制,默认不填写或者为nil代表参与电量控制,只有在缺电时才会开启,设置为false则无视电量持续监测运行
        },
        {
            name = "jf堆2", -- 核电堆命名(用于日志打印显示对应的名称)
            scheme = "jfy", -- 模式
            thresholdHeat = 0, -- 预热堆温
            preheatItem = "gregtech:gt.rodUranium4", -- 预热燃料
            reactorChamberAddr = "c3718e84-f884-45c6-90c6-a8a63541cde5", -- 核电仓地址
            reactorChamberSide = 5, -- 核电仓方向
            switchRedstone = "5cd8243c-8a38-422a-9494-d7bc80674ab2", -- 开关核电的红石端口地址
            reactorChamberSideToRS = 5, -- 核电仓相对于红石信号器的方向 旧版本更新的话默认填写nil即可会取{reactorChamberSide}的方向
            transforAddr = "465c2536-087b-4477-972d-e6896ebba930", -- 转运器地址
            inputSide = 0, -- 输入原材料的箱子位置
            outputSide = 0, -- 输出低耐久冷却单元的箱子位置
            changeItemOutputSide = 0, -- 输出枯竭燃料棒
            tempSide = 0, -- 堆加热的东西的箱子位置
            energy = nil -- 是否参与电量控制,默认不填写或者为nil代表参与电量控制,只有在缺电时才会开启,设置为false则无视电量持续监测运行
        },
        {
            name = "jf堆3", -- 核电堆命名(用于日志打印显示对应的名称)
            scheme = "jfy", -- 模式
            thresholdHeat = 0, -- 预热堆温
            preheatItem = "gregtech:gt.rodUranium4", -- 预热燃料
            reactorChamberAddr = "3fed73aa-20dc-4163-a447-5de8e1b99af1", -- 核电仓地址
            reactorChamberSide = 2, -- 核电仓方向
            switchRedstone = "5cd8243c-8a38-422a-9494-d7bc80674ab2", -- 开关核电的红石端口地址
            reactorChamberSideToRS = 2, -- 核电仓相对于红石信号器的方向 旧版本更新的话默认填写nil即可会取{reactorChamberSide}的方向
            transforAddr = "465c2536-087b-4477-972d-e6896ebba930", -- 转运器地址
            inputSide = 0, -- 输入原材料的箱子位置
            outputSide = 0, -- 输出低耐久冷却单元的箱子位置
            changeItemOutputSide = 0, -- 输出枯竭燃料棒
            tempSide = 0, -- 堆加热的东西的箱子位置
            energy = nil -- 是否参与电量控制,默认不填写或者为nil代表参与电量控制,只有在缺电时才会开启,设置为false则无视电量持续监测运行
        },
        {
            name = "jf堆4", -- 核电堆命名(用于日志打印显示对应的名称)
            scheme = "jfy", -- 模式
            thresholdHeat = 0, -- 预热堆温
            preheatItem = "gregtech:gt.rodUranium4", -- 预热燃料
            reactorChamberAddr = "8bff9d67-78c0-4f6a-8fed-03e49c9a872f", -- 核电仓地址
            reactorChamberSide = 4, -- 核电仓方向
            switchRedstone = "5cd8243c-8a38-422a-9494-d7bc80674ab2", -- 开关核电的红石端口地址
            reactorChamberSideToRS = 4, -- 核电仓相对于红石信号器的方向 旧版本更新的话默认填写nil即可会取{reactorChamberSide}的方向
            transforAddr = "465c2536-087b-4477-972d-e6896ebba930", -- 转运器地址
            inputSide = 0, -- 输入原材料的箱子位置
            outputSide = 0, -- 输出低耐久冷却单元的箱子位置
            changeItemOutputSide = 0, -- 输出枯竭燃料棒
            tempSide = 0, -- 堆加热的东西的箱子位置
            energy = nil -- 是否参与电量控制,默认不填写或者为nil代表参与电量控制,只有在缺电时才会开启,设置为false则无视电量持续监测运行
        }
    }
}