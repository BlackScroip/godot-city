# Dungeon Chasers 广告接入记录

日期：2026-10-23。项目：`goDot`。包名：`com.teamelo.dungeonchasers.godot`。

## 后台配置

已在 TopOn 和 AdMob 分别建立 Android、iOS 应用和激励视频广告位。
两个 TopOn 聚合页面均显示 1 个启用中的 AdMob Partner Bidding 广告源。
原链接中其他游戏的 AdMob 应用没有被复用。

| 配置 | Android | iOS |
| --- | --- | --- |
| TopOn App ID | `h6adb09c6cffb4` | `h6adb0660a7723` |
| TopOn 激励视频位 | `n6adb0bfb1235a` | `n6adb07f3aa701` |
| AdMob App ID | `ca-app-pub-8202400143123367~2924302885` | `ca-app-pub-8202400143123367~2836672976` |
| AdMob 激励视频单元 | `ca-app-pub-8202400143123367/1700307390` | `ca-app-pub-8202400143123367/9948876238` |

完整客户端配置在 `goDot/assets/ads.json`。App Key 是客户端 SDK 配置，不是后台管理凭据。
后台截图：`ads-android-topon.jpg`、`ads-ios-topon.jpg`、`ads-ios-admob.jpg`。

## 游戏接入

- 商城广告商品：复用原商品奖励与每日/每局限购，不再静默转为金币兑换。
- 猫饭：已研究等级可看广告免费点餐，不解锁研究、不额外增加料理效果；每日上限按原配置 100 次。
- 怪物派遣：广告成功后所选派遣缩短 30 分钟，最早完成时间为当前时间；每日上限按原配置 10 次。
- 三个入口共用每日 3 次免广告权益；SDK 不可用时仍可使用免费权益。
- 每日次数沿用现有项目的 UTC 日期边界；原 APK 的时区规则尚未恢复。
- 仅原生 SDK 的奖励回调发奖。失败、关闭、取消和普通播放结束均不发奖；重复和失效请求不会重复领取。
- 准备广告超时可重试；返回键和关闭按钮取消待播请求，广告播放期间保持游戏弹窗状态。
- Android/iOS 均通过 UMP 获取隐私状态，再初始化、加载、展示广告；设置页提供隐私选项入口。

APK 使用的是穿山甲激励广告，迁移项目改接 TopOn/AdMob。静态证据、地址、推断与未知项见 `ads-apk-reference.md`。
工作加速由 APK 构造常量和计时循环证实为默认 30 分钟；现有 Godot 采用 UTC 派遣订单，所以这里映射为所选订单的 1800 秒，不宣称完全复制原版共享累计工作模型。

## 验证与构建

- 广告奖励测试通过：重复回调、失效请求、取消、超时重试、失败、每日重置、免费次数、猫饭等级、工作加速与上限。
- 广告 UI 测试通过：无 SDK 时免费入口存在、返回键/关闭按钮取消准备、播放中不会关闭游戏暂停页面。
- 运行流程测试：2112 项断言，0 失败。
- 玩法系统测试：4926 项断言，0 失败。
- Android 原生插件：Debug/Release AAR 完整 Gradle 构建成功，且已使用官方匹配 Godot AAR 再次编译。
- iOS：包含 TopOn、AdMob、UMP 和 `DungeonAds` 的 arm64 未签名应用构建成功，成品 PCK 与导出 PCK 哈希一致。详见 `goDot/reports/ios-unsigned.json`。
- Android 最终 APK 已导出成功：`goDot/builds/android/DungeonChasers-debug.apk`，约 478 MiB。成品清单中的包名、AdMob App ID 和插件注册均正确；DEX 已核验存在 DungeonAds、TopOn 激励视频、AdMob 和 UMP 类。构建日志见 `goDot/reports/export-android-console.log`。

Android APK SHA-256：`55de8e382cbc586adaf25a7879ab74305e77612ecab832350a25dc697d3b8449`。
APK Signature Scheme v2 校验通过，原生库仅包含 arm64-v8a。

Android 官方 Gradle 模板 SHA-256：`a15416b528efb0a19a7d187e4d9f4e5336d0689144b111329fb4bd12c4447ad3`。
本机旧模板夹带其他游戏的原生广告代码，已隔离至 `/private/tmp/city-ads-quarantined-template-20261023`，当前项目使用重新下载校验的官方模板。

## 尚未完成的验收

1. 真机广告请求、展示、完整观看及奖励回调尚未验收；后台启用和编译通过不等于已验证广告填充。测试前应注册测试设备。
2. iOS 尚未签名、安装、提交 App Store；需要实际团队和描述文件。
3. AdMob 隐私消息发布、实际隐私政策地址及商店数据声明尚未验收；没有代填未知信息。
4. APK 的额外委托领取、广告完成、双倍奖励三个入口，对应玩法尚未在 Godot 中实现，本次没有伪造入口。
5. 未添加复活、定时插屏、横幅或开屏广告，因为本次 APK 调用证据未确认这些时机。

复现构建与测试说明：`goDot/native/README.md`。
