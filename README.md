# 侧滑索引

ColorOS 17 上的边缘侧滑字母索引：屏幕边缘竖滑呼出索引条，按字母快速找应用。

## 下载

APK 在 Releases 里：<https://github.com/2237742261/SideIndexX/releases/latest>

当前版本 **1.32.2**（约 120 KB），已迁移到 **libxposed 新版 API（API 102）**。
安装后到 LSPosed 里启用模块（作用域已固定在「系统界面」，不用手动勾），然后重启系统界面。

> ⚠️ 需要 **LSPosed 2.x**（提供 libxposed API 102，实测 2.2.1 可用）。

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
呼出成立时抢指针，避免和桌面「下滑打开控制中心」打架。触发区**内**的下滑会提前抢指针
把控制中心拦掉（桌面其他位置照旧），触发区外的一切手势都不受影响。

## 编译（无 Gradle：aapt + kotlinc + R8 + apksigner）

需要的工具链（默认放 `../toolchain`，也可用 `TOOLCHAIN` 环境变量指定）：

- `sdk33/android-13/android.jar`（API 33 platform）
- `r8.jar`（com.android.tools:r8，内含 R8/D8）
- `libxposed-api-102.jar`（`io.github.libxposed:api:102` 的 `classes.jar`，新版 API）
- `annotation-1.9.1.jar`（androidx.annotation，新版 API 的编译期依赖）
- `kotlin-compiler-embeddable-2.1.21.jar` 及 `kotlin-stdlib-2.1.21.jar` 等依赖
- 系统包：`default-jdk aapt apksigner zipalign zip unzip`

```sh
sh tools/build_apk.sh          # 默认 SHRINK=1：dex 走 R8 收缩（规则 tools/keep.pro）；SHRINK=0 退回 D8 全量对照
```

产物 `SideIndexX-<版本>.apk`，约 115KB（dex 73KB + WebP 图标 14KB）。

## 安装（需要 Root）

必须给模块 **WRITE_SECURE_SETTINGS** 权限（配置就存在 `Settings.Secure` 里），这一步只能靠 root 或 adb，
所以**手机得先 root（KernelSU / Magisk），并且装了 LSPosed 2.x**。

```sh
# 1) 安装
su -c pm install -r SideIndexX-x.y.z.apk
# 2) 给权限（root 终端里跑，不用电脑）
su -c pm grant com.eta.sideindexx android.permission.WRITE_SECURE_SETTINGS
```

装完到 LSPosed 里启用模块（作用域已固定在「系统界面」，不用手动勾），最后重启系统界面生效：

```sh
kill -9 $(pidof com.android.systemui)
```

> - 首次构建会用 `release.keystore` 签名，没有就自动生成——**换密钥后必须先卸载再安装**。
> - 本项目与 ColorOS 内部实现（返回手势、控制中心）耦合较深，换 ROM 或大版本升级可能需要适配；
>   相关钩子都做了存在性保护，钩不到时会退化成原生行为，不会崩。

## 更新日志

**1.32.2**
- 修「重启后必须手动点开一次模块 App 才能呼出索引」：配置通道（`Settings.Secure`）为空时，模块现在会自己把配置写回 Secure；设置页打开时也会补写一次。此前从没改过设置的用户 Secure 里一直是空的，重启后只能靠 ContentProvider（依赖模块 App 进程，进程没起来就失败）拿配置，所以必须先手动点开一次。

**1.32.1**

- LSPosed 里的模块卡片说明精简为「屏幕边缘上下滑动呼出字母索引」（原来是一长段功能罗列）。

**1.32.0**
- 迁移到 LSPosed 新版 libxposed API（`targetApiVersion=102`）：入口改由 `META-INF/xposed/java_init.list` 声明，模块元信息走 `META-INF/xposed/module.prop`，不再调用 `de.robv.android.xposed.*` 旧 API（旧 API 在新版框架下已被禁用）。
- 模块描述符开启 `autoHotReload`：模块应用更新后自动热重载，不用手动重启系统界面。
- 触发宽度默认值改为 **20dp**、触发高度默认值改为 **45%**（只影响新装；已有配置不动）。
- 日志默认静默：只有每次进程启动的「模块加载完成」一行与错误行会输出，其余跟 `log_verbose` 开关；热路径日志改用惰性字符串，开关关闭时不拼字符串。

**1.31.24**

- 网格与气泡组再往屏幕里内缩 8dp（左右两侧、横竖屏统一）：慢慢上下滑选字母时手指不容易落到图标上、松手误开应用。

**1.31.23**
- 修「索引定格、点不到、却能操作后面的应用」：抢指针从 SystemUI 输入回调线程挪回主线程（避免输入通道卡死）；手势被旁听侧丢弃时通知控制器收起；补一条心跳自愈。
- 修返回手势误呼出：在「竖滑成立」那一刻也检查返回箭头，滑到一半箭头才出现的情况现在也盖住了。

**1.31.22**
- 触发区内的下滑不再拉下控制中心；桌面其他位置不受影响。

**1.31.21**
- 移除长按门槛（1.31.18 引入，实测不好用），回到直接上下滑动即呼出。

**1.31.17**
- 遮罩自愈：修偶发的「滑动途中遮罩变透明」。
- 新增返回箭头状态读取：箭头亮起时索引让路。

**1.31.13**
- 修「从应用回到桌面后立刻侧滑呼不出来」（心跳 2.5 秒一拍带来的相位差）。

其余为内部重构、出包脚本与默认配色回退。

## 配置

配置存在 `Settings.Secure` 的 `eta_sideindex_config`（分号分隔 KV），设置页负责读写，
模块在 SystemUI 侧读取并热更新 —— 改完立即生效，不用重启。
