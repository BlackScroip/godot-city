# 营地主城页面与系统实装

日期：2026-10-28。本次接续 [2026-10-27 营地实装](../reports/CAMP_COMPLETION_20261027.md)，覆盖营地入口、未完成页面、交易与存档，以及左侧返回和手机横屏排版。用户提供的四张页面图片用于信物、角色、公会和武器布局核对；附件内容仅作为参考数据。

## 实装范围

营地菜单的 21 项系统入口及开始/继续冒险均有实际路由。资源详情、派遣详情、增幅确认、悬赏确认等子页也接入真实操作。以下“完成”指本地 Godot 工程的页面、规则、交互和存档闭环，不代表已接入原版在线服务。

| 系统 | 当前可用行为与本次补齐 |
| --- | --- |
| 营地建设 | 七种建筑、21 阶段；条件和费用校验、升级、场景刷新及设施定位；统一左侧返回 |
| 主城装饰 | 分类、购买、装备、恢复场景；交易通知在状态全部写入后发出 |
| 资源与仓库 | 实装资源总览和单项详情、拥有/获得/消耗统计、来源入口；空搜索不保留上一项动作 |
| 角色与时装 | 招募、升级、选择、天赋、时装及属性详情；操作后保留正在查看的角色 |
| 武器 | 打造、升级、装备及角色过滤；为非当前角色操作装备时写入该角色独立配置 |
| 训练场 | 进入范围判断、开始、实时统计、重置及结束；连接实际训练目标 |
| 公会支援 | 天赋节点与父子条件、费用、升级和选中状态；专用页面与实际宿主回归 |
| 伙伴与派遣 | 伙伴养成；派遣开工、领取、升级、停止确认、离线进度和日限；计时刷新保留筛选与选择 |
| 猫饭料理 | 研究、点餐、购买、重做、容量与增益；新增行后按身份保留当前菜品 |
| 居民与支援 | NPC 入口、关系剧情、赠礼和支援；取消/完成分别处理，不提前扣除赠礼材料 |
| 觉醒 | 独立实装页面，8 角色、110 个公开节点；解锁、激活、停用、等级和潜能预算；保存选择及滚动位置 |
| 信物 | 原图网格、未解锁剪影、等级、当前装备栏、详情、强化及装备；操作后保留所选信物 |
| 增幅 | 三个镶嵌位、开槽、装备/拆卸、五合一、批量预览、重选、15 个预设；直接点第 2/3 槽的镶嵌使用对应槽位 |
| 普通委托与成就 | 原任务和成就条件、进度、领取、分类及滚动；重复领取受事务保护 |
| 悬赏委托 | 独立接取、放弃、进度、完成领取与广告回调；准备页入口完整可见 |
| 图鉴与冒险档案 | 发现状态、分类、详情；真实历史记录及只读结算详情 |
| 本地商城 | 本地材料兑换、宝箱、已接入的广告接口；宝藏入口别名打开实际商城分类 |
| 冒险准备 | 角色/武器/信物跳转、难度、掉落加成、混沌、悬赏、进入冒险及帮助；补小屏布局与按钮检查 |
| 设置 | 保留设置和本地保存；统一返回入口，在线功能仍明确其依赖状态 |

## 返回与页面状态

- 使用同一张原包箭头、透明按钮背景和统一安全边距。缩放后点击区域至少 44 像素。
- 建设页和角色属性详情的左上关闭符号统一为返回箭头；时装、角色、武器、背包、商城等使用相同返回组件。
- 顶级页面关闭后回营地；派遣详情返回派遣列表；从角色进入觉醒后返回原角色；从准备页进入信物/增幅后返回准备页。
- 返回时保留正确的来源上下文。解锁、强化、装备和激活后的刷新不再把选择覆盖为最初入口的 ID。
- 觉醒列表及详情分别保存滚动位置；切节点重置详情，切角色重置两处。派遣计时刷新和筛选操作保留当前项目身份。

## 按钮与排版修正

冒险准备页的开始按钮原先误用“主城建造离开按钮”作为可用状态，手机横屏高度只有 38 像素。现在按原包 `ATBtn_Select` 使用“几何ui-异形白色按钮”和浅金色可用状态，底部按钮区独立于难度列表，并保留至少 44 像素点击高度。按钮获得焦点后仍使用清晰的深色文字；禁用的开始按钮与首通奖励按钮使用浅色文字，保持可读性。锁定原因、混沌层数与奖励不会挤压开始按钮；空原因不占行。左侧装备标题、图标和等级均检查容器边界，满 7 个信物槽时可横向滚动。难度锁图标随实际解锁状态刷新。

准备页原按钮为 `640.4277×91.0434`、缩放 `1.2298`；左侧装备框的静态位置被入场动画覆盖，实际结束 X 为 78。原始锚点、尺寸、动画终值及资源哈希见 [准备页布局证据](../reports/adventure-prepare-layout-evidence-20261028.json)。响应式布局保留原素材和区域关系，同时为窄屏操作留出实际空间。

公会解锁按钮原先误用“商店按钮_底”，被压成扁长形。新 APK 的 `ATPanel_TalentTree/PopPanel/PopPanel_TalentDetail/Container/ATBtn_LevelUp` 实际使用“几何ui-椭圆白色按钮”，原控件 `300×94`。已换成当前包导出的 `sprite_39ebe9c97d61.png`，按图像比例决定高度，保留原可用/禁用色和真实解锁、升级操作。原 prefab 的 bundle SHA-256 为 `41c1baee91085e8ccc7d068b9d51decf49d169f485bbca3e1ddb86af1f28f5f5`，按钮 GameObject pathID 为 `-7886139063027504804`。

武器 202 的详情与选择预览中，原透明特效曾被当作不透明 PBR 材质显示成白色矩形。已从同一 APK 恢复四张纹理、材质绑定及遮罩、扭曲、渐隐参数，并复用工程已有的恢复材质。原 GLSL 的渐隐公式包含顶点透明度；仅此预览材质启用该分支，共享 Shader 的默认行为保持不变。实际渲染验证了特效随时间变化，两个预览在桌面和手机横屏均完整位于视口内。

## 事务与存档

营地经济操作统一在状态完整提交后发出资源事件、玩法事件和变更通知。同步订阅者重入时拒绝第二次交易和原始扣款，防止重复扣费、重复发奖或保存“已付款但尚未发货”的中间状态。覆盖建筑、角色、武器、天赋、伙伴、派遣、料理、觉醒、信物、装饰、时装、任务、商城、悬赏与结算。

广告奖励在一次领取中只取一次时钟，避免每日重置边界造成奖励和回执落入不同账本；回执、次数和免广告次数先提交，再发布通知。取消、失败及已使用回执继续拒绝发奖。

新增存档检查覆盖广告账本、对话状态、角色/武器/难度/料理 ID 以及营地装备结构；拒绝小数、溢出和不完整的新结构。保留旧存档迁移、数字 ID 归一化以及损坏主档的备份恢复。

## 原包证据与资源

基准 APK：`/Users/hanyu/U3D/City/1061664.apk`。

- APK SHA-256：`ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505`
- 匹配 ARM64 库 SHA-256：`86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944`
- 本次 REA 导出：[营地包体检查证据](../../reports/camp-systems-apk-rea-evidence-20261028.json)。目标已关闭；没有运行原 APK。
- 规则依据复用同版本 [营地经济审计](../reports/NEW_APK_CAMP_ECONOMY_AUDIT.md)、[信物原生证据](../reports/relationship-tokens-native-evidence-20261027.json) 和 [社交原生证据](../reports/camp-social-native-evidence-20261027.json)。
- 从 APK 补提 35 张觉醒图标和佩特拉信物图标，共 36 张；110 个公开觉醒节点均解析到对应原图，不再以角色头像替代。
- [提取脚本](../tools/recover_camp_progression_icons.py)、[图标来源和哈希](../assets/ui/camp/awakening/provenance.json)、[资源映射](../assets/ui/camp/awakening/resource_map.json) 保留了可复核记录。
- 武器预览保留 [材质和四张纹理来源](../assets/ui/role_weapon/source_materials.json)、[可复现导出脚本](../tools/export_weapon_preview_materials.py) 和 [原 Shader 公式证据](../reports/weapon-preview-shader-evidence-20261028.json)。

## 验证

以下为本次实际执行的通过结果，分别列出，不把不同运行累计为一个总数。

| 测试 | 通过项数或结果 |
| --- | ---: |
| `camp_transaction_test` | 68 |
| `camp_reward_transaction_test` | 21 |
| `camp_persistence_test` | 180 |
| `save_recovery_test` | 24 |
| `camp_progression_icons_test` | 413 |
| `awakening_page_test` | 285（无界面；含新增滚动回归） |
| `camp_token_reference_test` | 117（实际渲染） |
| `camp_selection_refresh_test` | 26 |
| `camp_services_presentation_test` | 243 |
| `camp_service_state_test` | 52 |
| `camp_page_integration_test` | 24 |
| `camp_navigation_test` | 518（实际渲染；含角色属性详情）；最终代码无界面 498 |
| `page_back_flow_test` | 142 |
| `camp_completion_ui_test` | 220（实际渲染）；最终集成无界面 187 |
| `character_page_test` | 105（最终代码无界面；招募、升级、属性与时装） |
| `role_pages_integration_test` | 245（实际渲染；含招募确认、跨角色装备、公会按钮比例与解锁） |
| `weapon_page_test` | 200（实际渲染；含原特效动画像素与模型边缘检查） |
| `adventure_prepare_layout_test` | 1663（实际渲染）；1648（无界面）；五尺寸、三种状态与满信物槽 |
| `adventure_prepare_flow_test` | 41（实际进入、退出冒险流程） |
| `camp_flow_test` | 70 |
| `game_flow_test` | 111 |
| `systems_test` | 5244 |
| `camp_economy_test` | 114 |
| `relationship_tokens_test` | 124 |
| `partner_status_test` | 192 |
| `meal_economy_test` | 113 |
| `camp_unlock_contract_test` | 35 |
| `camp_decoration_test`、`character_fashion_test` | 各 30 |
| `extra_challenges_test` | 65 |
| `ads_test` | 通过 |
| `mall_test` | 301 |
| `camp_dialogue_flow_test` | 130 |
| `camp_social_host_test` | 15 |
| `settlement_rules_test` | 36 |

截图均来自实际 Godot 页面。常规覆盖 1600×900、844×390、2460×1080；准备页另检查 740×360 和 667×375，觉醒另检查 390×844。左侧返回专项覆盖 27 个页面，检查箭头来源、边距、点击区域、标题对齐及返回目标。

- [信物手机横屏](../reports/camp-token-reference-844x390.png)
- [信物桌面](../reports/camp-token-reference-1600x900.png)
- [觉醒手机横屏](../reports/awakening-page-844x390.png)
- [冒险准备手机横屏](../reports/camp-navigation-difficulty-844x390.png)
- [准备页窄屏锁定状态](../reports/adventure-prepare-locked-740x360.png)
- [准备页窄屏混沌状态](../reports/adventure-prepare-chaos-667x375.png)
- [公会按钮手机横屏](../reports/role-camp-talents-844x390.png)
- [跨角色武器预览手机横屏](../reports/role-camp-other-weapons-844x390.png)
- 其余返回截图：`reports/camp-navigation-{page}-{width}x{height}.png`。

## 验收边界

原版 APK 的运行画面与交互、实体 Android/iOS 设备、广告平台真实投放、账号、云存档、兑换码及真实支付仍需要相应运行环境或服务。不以本地界面、测试回调或禁用状态代替在线服务实装。原版 Shader、动画和 RNG 序列的逐帧或逐位等价也未在本次证明。

本次保留工作区内其他角色、战斗、环境与设置修改，没有回退并发工作，也没有提交 Git 或发布构建。
