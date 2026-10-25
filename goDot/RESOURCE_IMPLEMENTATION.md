# APK 资源比对与实装记录

日期：2026-10-25。

本轮使用 `reverse-engineer-anything` 比对用户提供的 `../com.teamelo.dungeonchasers.apk`，并在现有 Godot 游戏中接入已确认用途的资源。没有执行原 APK，静态源数据与 Godot 运行验证分别记录。

## 已实装

| 项目 | 当前行为 | 原始依据或适配边界 |
| --- | --- | --- |
| 传送离场 | 使用传送门后角色上升，按原时序隐藏，再进入加载或选路 | 原 `leftroom` 事件长2.5秒；上升位移为本地表现适配，不改物理或存档坐标 |
| 关卡进场 | 加载完成后播放传送降落，落地后恢复操作 | 原 `enterroom` 长1秒，0.167秒显示模型，粒子速度1.5倍；降落位移为本地适配 |
| 复活 | 原复活动画、符文及爆发粒子、两段音效，完整结束后恢复操作 | 原 `revival` 长2.5秒，爆发和第二段音效位于1.2秒 |
| 四类宝箱 | 普通、精致、豪华、诅咒宝箱分别播放原品质开箱特效 | `EnvUnitCfg_[19001]` 的 `TypePrefabList` 与 `TypePrefabOpenFxList` 平行数组 |
| 保护目标 | 交互后显示激活表现，保护战完成后显示销毁表现 | 原Prefab的Active/Destory容器及粒子；完成时选择销毁为本地流程适配 |
| 矿石掉落 | 矿石素材103显示持续星光，拾取或清场后释放 | `MaterialData.item_type=MineralMat`；原EnvUnit10105与 `EnvUnit_PickUpable_MineralMat` 中精确粒子定义 |
| 能力道具生成 | 道具10002生成时播放紫色出现特效，读档不重播 | 原EnvUnit50004的 `GetAbilityItemId=10002` 与 `InitEffectName`；未泛化到所有Rare4道具 |
| BGM | 修正原查找无匹配的问题，营地三曲轮播、五区域选曲 | 使用原音轨；轮播与区域选曲是本地适配 |
| 操作和环境音 | 菜单、拾取、奖励、升级、建造、烹饪、区域氛围及脚步 | 保留原clip层的音量、音高、延迟；语义绑定与脚步距离为本地适配 |
| 环境交互音 | 受击、接触、延迟破坏、破坏和陷阱开始按原字段触发 | `BeAttackSound/TriggerTouchUnitSoundName/BreakDelaySoundName/BreakSoundTrigger/TriggerStartSound` |
| UI资源 | 技能环、模式切换、暂停、充能、拾取与交互框、菜单标题和分隔线等接入现有界面 | 39个逻辑名称对应38个不同内容；相同内容别名不重复计缺失 |

传送及复活支持后台冻结、低画质粒子预算、重复输入拦截和离开场景清理。拾取及交互效果支持存档恢复，瞬时反馈不重复播放。

## 尚未绑定或缺少来源

完整逐项列表见 [资源接入盘点](reports/RESOURCE_USAGE.md)，包含每个未绑定音频文件的全部别名；机器可读证据见 `reports/resource-usage.json`。

- **14个未绑定特效**：旧传送门颜色3种，旧陷阱/屏障4种，能量裂隙阶段4种，旧矿石能量、矿洞掉落和旧诅咒宝箱开箱各1种。对297个相关Prefab根、298个Bundle及112份EnvUnit配置的扫描没有建立这些效果的有效触发关系；部分当前原配置明确使用其他资源，未将近名资源当作别名。
- **114个未绑定物理音频文件**，涉及198个逻辑名称/别名：包含备用语音、录音take和未明事件。名称不能证明用途，未随机分配到游戏事件。
- **19个海岛场景**：模型存在，当前APK配置缺少对应NodeData路线及战斗定义，未编造关卡数据。
- **7个历史引用特效缺定义**：在14613条manifest资源、6131份动作配置、1214个FX包和11850个FX GameObject的限定扫描中没有找到精确名称；完整名单见盘点报告。
- **7个只有禁用命令引用的特效**：与上一组不同，保持原 `enabled=false`。
- **6个独立子特效**已有组合特效的同名粒子层承载候选，未重复叠加播放；层名匹配不等于全部参数一致。

角色、敌人、武器和大部分环境已有动态加载入口；静态引用不代表每个资源都已完成自然流程验收。旧38项ability/622项Buff审阅数字是历史定位清单，不能当作本轮行为失败数。

原进出场配置中的相机、光照、时间缩放及临时武器绑定字段保留在导入数据中，本轮播放器尚未执行这些事件。现有游戏结算相机仍按原有实现运行。原配置只给角色1至6提供特定进场动画条件；没有为缺少源分支的角色编造动画来源。

## 验证

- `node tools/test_resource_integration.mjs`：10组测试全部通过，共7539项检查，覆盖音频、传送、资源反馈、交互、环境效果、死亡/复活、掉落、房间闸门及选路流程。完整输出：`reports/resource-integration-tests.json`。
- Godot图形运行：1600x900与844x390尺寸，传送上升、降落、复活及真实首次进入关卡共74项检查通过，包括非空画面、粒子贴图加载和移动/显隐时序。
- `node tools/audit_resource_usage.mjs`：2702个逻辑条目；无缺失payload。索引包含1051种特效、1414个音频名称/579个物理音频、39个UI名称/38个内容、198个模型。
- 本轮保留并兼容工作区中同步更新的营地、NPC及世界地图流程；测试通过真实可达槽位选择区域，不把区域编号误作槽位ID。

截图位于 `/private/tmp/player-transfer-*.png`，包括桌面/手机比例上升、降落、复活及 `level-arrival`。

## 源证据

- APK SHA-256：`8b6b62e21360f8170fc70d86279e88ab04c7c9c6d0d91f659e76a48bdbdb4ea3`。
- REA inventory：`ev_abcc9134d78621f34fad95c09ca5c13a0e7fa21b69aa75a2edba067acdd81a4e`。
- REA inspect：`ev_6893c551b1ceeacbc6bbd8090f2a216659f956bcf4d2136b5224207e1eb780bf`。
- 完整导出：`reports/RESOURCE_APK_REA_EVIDENCE.json`。
- 玩家事件原JSON、时序及哈希：`reports/player-lifecycle-source.json`；复核命令 `PYTHONPATH=/tmp/city-charge-pydeps:/tmp/city-native-pydeps python3 tools/import_player_lifecycle.py --apk ../com.teamelo.dungeonchasers.apk --check`。
- 环境与拾取原配置、粒子比对：`reports/unbound-environment-effects-apk.json` 及同名Markdown。
- 缺失特效扫描：`reports/unresolved-effects-apk.json`。

REA的ZIP身份和成员证据、Unity序列化对象证据、Godot运行验收是不同层级，均不声称已观察原APK实际运行或达到逐帧等价。
