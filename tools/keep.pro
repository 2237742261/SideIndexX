# R8 收缩配置（侧滑索引模块）—— 命令行构建用，读法同 ProGuard
#
# 为什么需要：dex 里大头是**没被裁剪的 kotlin 标准库 + 未使用的自家代码**。
# 用 D8（只做 dex 转换、不裁剪）打的包：classes.dex 未压缩 2.2MB / APK 内压缩后 694KB；
# 换 R8 收缩后 143KB / 压缩后 73KB —— 同一份源码，APK 从 817KB 掉到 101KB。
#
# 必须保留的入口：
#   1. LSPosed 按类名加载的入口（见 assets/xposed_init）
#   2. AndroidManifest 里声明、由系统按类名实例化的组件
#   3. **重写框架回调**的继承关系（View 的 onDraw/onTouchEvent、ContentObserver.onChange、
#      BroadcastReceiver.onReceive、ComponentCallbacks…）——这些方法是由框架调用的，
#      R8 从自家代码出发看不到调用点。整类保留的代价只有几 KB，别为了省这点去赌。
#
# 故意 -dontobfuscate：混淆只能再省 ~9KB（压缩后 ~3.5KB），
# 但会让 SystemUI 崩溃日志里全是 a.b.c，排障变难，不划算。

-dontwarn **
-dontobfuscate

# 注解/泛型签名等属性：Kotlin 与 Xposed 都可能用到
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# ---- LSPosed 入口（libxposed 新版 API，1.32.0 起）----
# 入口类只被 META-INF/xposed/java_init.list 按类名引用、由框架实例化，
# R8 从自家代码出发看不到调用点，不加 keep 会被整类删掉
# （表现：模块完全不加载、没有任何日志）。
-keep class * extends io.github.libxposed.api.XposedModule { *; }
-keep class com.eta.sideindexx.EtaModule { *; }

# ---- 清单里的组件 ----
-keep class com.eta.sideindexx.settings.SettingsActivity { *; }
-keep class com.eta.sideindexx.settings.AppPickerActivity { *; }
-keep class com.eta.sideindexx.settings.ConfigProvider { *; }

# ---- 框架回调型基类：整类保留 ----
-keep class * extends android.view.View { *; }
-keep class * extends android.content.ContentObserver { *; }
-keep class * extends android.content.BroadcastReceiver { *; }
-keep class * implements android.content.ComponentCallbacks { *; }


# ---- 模块内被 Xposed Hook 回调间接触达的单例（1.31.17）----
# R8 从自家代码出发看不到调用点：BackGestureUi 只被 SystemUiHost 调一次 install()，
# 之后 isShowing() 是被"框架回调里才读"的，收缩时会被判成不可达而删掉。
# 表现：箭头判定静默失效（不报错、只是永远返回 false）。
-keep class com.eta.sideindexx.overlay.BackGestureUi { *; }
-keep class com.eta.sideindexx.overlay.BackGestureGate { *; }
-keep class com.eta.sideindexx.overlay.ForegroundApp { *; }
-keep class com.eta.sideindexx.overlay.SystemUiHost { *; }

# 系统遮挡状态（1.32.4）：只在钩 apply() 的回调里写 volatile 字段，触摸回调里读；
# 别让 R8 把它当不可达删掉（删了表现是「通知栏/锁屏上照样弹索引」）。
-keep class com.eta.sideindexx.overlay.SystemCover { *; }
