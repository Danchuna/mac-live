

## Codely Structured Memories

### User

### Feedback
- [2026-09-30 23:47:59] 该项目的验收方式：GUI 效果必须实机跑起来验证（进程/窗口状态/虚拟屏是否存在），不能只靠编译通过；给 App 加 --dump-window 之类诊断开关读真实窗口状态，是这台机器上唯一可行的自动化验证手段（无屏幕录制权限）。

### Project
- [2026-09-30 23:28:16] 本机编译 macOS 工程必须设 DEVELOPER_DIR=/Library/Developer/CommandLineTools：xcode-select 指向损坏的 /Applications/Xcode.app（缺 xcrun），否则 swift/xcrun 直接报错。scripts/build.sh 已内置该覆盖。
- [2026-10-01 00:15:18] 悬浮文字 App（/Users/sai/Desktop/直播悬浮文字）为 SwiftPM 工程（无 xcodeproj）：SwiftUI 设置窗口 + AppKit 透明 NSPanel 悬浮窗；配置 JSON 存 UserDefaults(com.codely.floatingtext)，读取时“合并默认值”兼容旧存档（CGPoint 在 JSON 里是 [x,y] 数组，手写测试存档别写字典）；验证用 --render-preview [--live --composite|--chroma|--transparent] / --dump-window [--toggle-live-after N]，诊断写 /tmp/floatingtext-window.log（终端无屏幕录制权限，截不到窗口）。直播模式：私有 API CGVirtualDisplay 建虚拟屏（SDK 无头文件，走 ObjC runtime KVC+objc_msgSend），窗口整屏铺上去、物理屏保持干净。三种接线：A 画面合成（默认，ScreenCaptureKit 采集物理屏+叠文字后输出整幅画面，需要屏幕录制权限，不挑采集软件）、B 绿幕+色度键、C 窗口采集（透明窗口已实测 sharing=1/onScreen/97%透明，但抖音直播伴侣不保留 alpha → 黑底）。用户直播软件是抖音直播伴侣。
- [2026-10-01 00:49:50] ScreenCaptureKit 是按画面变化投递帧的（Apple 文档：complete=有新画面，idle=内容没变、无新 IOSurface；静止屏几乎收不到帧），所以屏幕共享/合成场景必须自己按固定帧率绘制鼠标指针（已实现 CursorOverlayView + 60Hz Timer，且采集配置里 showsCursor=false 防重影），否则静止时“感觉卡住”。另：ad-hoc 签名每次重建都会让「屏幕录制」TCC 授权失效，更新 App 后需要重新授权。
- [2026-10-01 01:03:32] 自己绘制鼠标指针的坑（/Users/sai/Desktop/直播悬浮文字，CursorGeometry.swift）：NSCursor.hotSpot 是「左上原点」图像坐标，而 NSView/CALayer frame 是左下原点，需要按 imageHeight-hotspot.y 翻转；屏幕坐标(NSEvent.mouseLocation/NSScreen.frame)本身已是左下原点，不要再翻转一次（否则垂直镜像）。另：NSCursor.arrow/.iBeam 的 .image 在部分系统为空，要退回 NSCursor.currentSystem。验证手段：--cursor-check 把指针指到已知屏幕坐标并离屏出图，数值对比 dx/dy 应为 0。
- [2026-10-01 05:58:31] 本机签名方案（/Users/sai/Desktop/直播悬浮文字/scripts/build.sh）：默认用本机「Apple Development: 8618079201273 (9YBYWSC9ZQ)」(Team DYV93262YW) 证书签名，指定要求不含 cdhash，因此重新构建后「屏幕录制」TCC 授权不再失效（ad-hoc 签名每次构建 cdhash 变化会导致授权失效）。注意：自签名 openssl 证书会因未受信任触发联网信任校验，codesign 会挂住（已弃用并删除）。
- [2026-10-01 06:05:00] ScreenCaptureKit 崩溃坑（已修，ScreenCompositeStream.swift）：SCStreamDelegate 的 `stream(_:didStopWithError:)` 在「干净停止」时系统会传 nil error，若按非空 Error 用（如取 localizedDescription）会 EXC_BAD_ACCESS at 0x0；必须声明成可选参数（Swift 会给“可选性不同”警告，属有意为之），且该回调在后台线程，状态改动要回主线程。
- [2026-10-01 06:33:34] App 已改名为 mac-live（2026-10-01）：SwiftPM 包名 mac-live、模块 MacLive、可执行/进程名 mac-live、bundle id com.maclive.app、UserDefaults 键 maclive.overlay.config.v1、日志 /tmp/maclive-*.log、虚拟屏名「mac-live 虚拟屏」。待上传 GitHub 的干净副本在 /Users/sai/Desktop/mac-live（排除 CODELY.md/.codely-cli/.build/dist，已实测可独立构建）。注意：换 bundle id 后「屏幕录制」授权需重新授予一次；UserDefaults 旧域 com.codely.floatingtext 已迁移到新域。测试配置前务必先备份（曾因未备份覆盖过用户配置）。

### Reference

