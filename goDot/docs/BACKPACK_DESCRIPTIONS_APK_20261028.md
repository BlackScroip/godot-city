# 背包动态说明与触发机制核对

## 证据范围

- 目标：`1061664.apk`，SHA-256 `ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505`。
- 原生成员：`lib/arm64-v8a/libil2cpp.so`，SHA-256 `86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944`。
- `reports/ability-descriptions-native-20261028.json` 保留 54 个相关方法的 ARM64 指令、调用与可解析的元数据字符串。工具执行时逐字节核对该原生文件与 APK 成员的哈希。
- 以下原版行为结论来自离线静态代码及包内配置；这些证据不表示已运行原版 Android 游戏。

## 实装规则

`scripts/domain/ability_descriptions.gd` 保留原始说明里的颜色、术语与精灵标签，仅按当前状态替换 54 个背包占位字段。没有当前持有物品或不在冒险中时，隐藏整段运行时括号说明，对应 `ATGameManager.ReplaceBuffStr`（文件偏移 `0x2de9b4c`）。

| 字段 | 实际数据 |
| --- | --- |
| `backpack_layer` | 原版计算倍率，或累计记录已达到的层数 |
| `backpack_progress` | 对应物品的真实 StateChange 记录值 / 门槛，当前值截到门槛 |
| `backpack_record_trigger` | 已执行次数 / MaxEffectCount，独立于奖励数量及剩余进度 |
| `backpack_buff_layer:ID` | 优先读取当前战斗的该 buff 层数；预览按实际存档与配置还原 |

`AbilityItem_RogueNormal.CaculateEffectFactor`（`0x2fcc140`）和 `AbilityItem_RogueCombine.CaculateEffectFactor`（`0x2fc9f38`）使用整数来源属性除以配置分母，再乘持有数。普通能力的显示倍率可能高于实际 buff 的层数上限；这两种数值各自遵循原生路径，不混为一个数。

- 背包物品数累计所有可见物品的持有量，包括宝石、精灵。
- 宝石数累计三类宝石的持有量。
- 精灵按不同种类计数，普通品质 3/4/5 对应权重 1/2/3，融合精灵权重 7，不重复乘持有量。
- 星数合计每种保留物品一次，排除金币、魔力、矿石、调查点、卷轴、遗物袋、药水与护甲等获得即消耗的类型。依据 `GetAllLootDataList`（`0x2d98c40`）和 `get_IsCostAfterGet`（`0x2cf9328`）。
- 通用怪物支援遗物按可见对应类型持有量累计，依据 `GetKeepTargetTypeAbilityItemCount`（`0x2d99640`）。
- 计算结果同时用于 `effects.ability_attributes` 与 `systems._gather_ability_buffs`，让显示、数值属性和战斗 buff 绑定采用同一来源。

RecordTrigger 按阈值累计，保留未满阈值的余数；有上限时限制层数或执行次数。一次批量记录可能产生多份奖励，但原生执行次数只增加一次。消息分发命中监听器返回已处理，最外层实际改变状态时发出系统变更通知，并避免同名消息递归重复计数。

普通成长物品 20138、20162、20406、20415、20417、20422 和原有 20 个诅咒物品均使用真实 StateChange 条件完成替换；普通成长没有加入诅咒祭坛专用接口。

背包、仓库、战利品图鉴和迷宫商店详情接入 `SourceRichText`；奖励、营地支援和净化选择由主流程传入同一源说明。背包行内图标会随桌面/手机文字大小重新生成。

预览状态同时核对中文和英文的 54 条实际动态说明。英文原文中的 `(Current)<#backpack_layer> stacks)` 等特殊括号形式按实际状态后缀移除，保留正文、正文括号、颜色与术语标签。

实际 `main.gd` / `world.gd` 桥接在消息、击杀、物件破坏、伙伴技能和自动拾取前同步当前战斗生命与护甲，在属性触发后刷新当前角色。已处理的内部消息不再作为 HUD 提示显示；伙伴技能仅成功按下时记录，松开和冷却拒绝不重复记录。

## 保留的源数据差异

- 猎人行囊 20584 的说明写“30次”，配置 `TriggerPercent` 为 50。
- 小众收藏家 20426 的说明写“+200%、每件 -2%”，实际数值 buff 为 `AtkAddRate +1000` 和每层 `-10`。

这些是同一 APK 内文本与结构参数的差异。当前保留包内原文，执行包内结构参数，未通过改写说明或捏造数值掩盖差异。

## 验证

| 脚本 | 结果 |
| --- | --- |
| `tests/ability_descriptions_test.gd` | headless 431 项通过；图形模式 439 项通过并输出 6 张截图；54 动态说明、19 计算源能力、存档续算、背包/图鉴/商店两种尺寸绑定；商店通过正式 HUD 入口检查遮挡 |
| `tests/ability_description_preview_test.gd` | 441 项通过；中英各 54 条预览正文完整保留、动态状态完整移除、正文括号保护 |
| `tests/backpack_record_runtime_test.gd` | 173 项通过；阈值、消息链、6 普通成长、20 诅咒、迁移与重复房间 |
| `tests/backpack_main_bridge_test.gd` | 169 项通过；真实主场景消息、击杀、破坏、伙伴技能、自动拾取、HUD 描述生产方及生命/护甲同步 |
| `tests/source_rich_text_raw_test.gd` | 16,759 项通过；1,657 个实际原文富文本字段 |
| `tests/inventory_page_test.gd` | 31 项通过 |
| `tests/spirit_attachment_ui_test.gd` | 158 项通过 |
| `tests/room_shop_pricing_test.gd` | 40 项通过 |
| `tests/purification_altar_rules_test.gd` | 113 项通过 |
| `tests/systems_test.gd` | 5,244 项通过 |

除单列图形模式结果外，上述为 headless 验证。`ability_descriptions_test.gd` 已输出背包、图鉴、商店的 1600×900 与 844×390 截图，路径记录在 `reports/ability-descriptions-tests-20261028.json`。

`reports/backpack-main-bridge-20261028.json` 记录 169 项实际主场景检查：50 次猎人消息得到 1 次免费购买；25 次敌人信号、20 次正确陶器配置即时更新成长；伙伴成功按下仅触发一次；自动拾取 125 精粹即时绑定遗物效果；奖励、献祭、NPC 支援和商店说明保留原图标及颜色，并逐项核对实际层数、进度与触发次数。8 个封印条目均进入实际详情控件，20193 的纯文字术语 `keyinshengdian` 正确保留颜色而不强加图标。测试为库存和选项注入确定数据，以真实信号调用击杀与物件破坏处理器，不模拟完整战斗或碰撞，也未运行原版 APK。该测试单独验证所有上述属性链路不会用旧存档数值覆盖未保存的当前生命与护甲。
