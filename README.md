# 侧滑索引（SideIndexX）

ColorOS 上的边缘侧滑字母索引：屏幕边缘竖滑呼出索引条，按字母快速找应用。

## 下载

APK 在 Releases 里：<https://github.com/2237742261/SideIndexX/releases/latest>

当前版本 **1.31.11**（约 117 KB），安装后到 LSPosed 里启用模块，作用域只勾 `com.android.systemui`，然后重启系统界面。

## 功能

- 呼出范围：仅桌面 / 全局（任何应用里都能呼出）
- 呼出侧：右侧（默认）/ 左侧 / 两侧均可
- 字母索引 + ★ 常用栏（按系统使用统计的近 30 天打开次数排序，位置稳定）
- 用小窗（ColorOS 弹性窗口）打开应用；游戏内屏蔽；应用黑名单
- 沉浸模式：背景用壁纸模糊
- 可调：触发宽度 / 触发高度 / 垂直位置 / 灵敏度（滑动距离） / 震动强度 / 每行图标数

## 原理

LSPosed 模块，作用域只挂 `com.android.systemui`：浮层跑在系统界面进程里（划掉后台仍可用），
不需要悬浮窗权限、不依赖模块应用存活。

手势**不是**用悬浮窗拦触摸实现的：感应带窗口永不接收触摸，而是旁听 SystemUI 的手势监视器
（见 `overlay/BackGestureGate.kt`），所以桌面的翻页、系统返回、应用内手势全部照常；
呼出成立时抢指针，避免和桌面「下滑打开控制中心」打架。

## 编译（无 Gradle：aapt + kotlinc + R8 + apksigner）

需要的工具链（默认放 `../toolchain`，也可用 `TOOLCHAIN` 环境变量指定）：

- `sdk33/android-13/android.jar`（API 33 platform）
- `r8.jar`（com.android.tools:r8，内含 R8/D8）
- `xposed-api-82.jar`
- `kotlin-compiler-embeddable-2.1.21.jar` 及 `kotlin-stdlib-2.1.21.jar` 等依赖
- 系统包：`default-jdk aapt apksigner zipalign zip unzip`

```sh
sh tools/build_apk.sh          # 默认 SHRINK=1：dex 走 R8 收缩（规则 tools/keep.pro）；SHRINK=0 退回 D8 全量对照
```

产物 `SideIndexX-<版本>.apk`，约 115KB（dex 73KB + WebP 图标 14KB）。

## 安装

```sh
pm install -r SideIndexX-x.y.z.apk
pm grant com.eta.sideindexx android.permission.WRITE_SECURE_SETTINGS
```

然后在 LSPosed 里启用模块、作用域勾选「系统界面」，最后重启系统界面生效：

```sh
kill -9 $(pidof com.android.systemui)
```

> - 首次构建会用 `release.keystore` 签名，没有就自动生成——**换密钥后必须先卸载再安装**。
> - 本项目与 ColorOS 内部实现（返回手势、控制中心）耦合较深，换 ROM 或大版本升级可能需要适配；
>   相关钩子都做了存在性保护，钩不到时会退化成原生行为，不会崩。

## 配置

配置存在 `Settings.Secure` 的 `eta_sideindex_config`（分号分隔 KV），设置页负责读写，
模块在 SystemUI 侧读取并热更新 —— 改完立即生效，不用重启。
