package com.eta.sideindexx

import android.app.Application
import com.eta.sideindexx.config.ConfigReader
import com.eta.sideindexx.overlay.SystemUiHost
import com.eta.sideindexx.util.XLog
import io.github.libxposed.api.XposedModule
import io.github.libxposed.api.XposedModuleInterface

/**
 * 模块入口（libxposed 新版 API，1.32.0 起）。
 *
 * 与旧入口（assets/xposed_init + IXposedHookLoadPackage，1.31.x 及以前）的区别：
 *  - 类由 `META-INF/xposed/java_init.list` 声明，必须继承 [XposedModule]
 *  - 只在 [XposedModuleInterface.PackageReadyParam] 里做「是不是系统界面」的判断，
 *    作用域外的包直接 [detach] 掉，避免后续回调白跑
 *  - 注入时机仍是「包的 classloader 就绪、Application 还没 onCreate」，
 *    所以还是钩 `Application.onCreate` 拿 Context 开工（对齐 1.31.x 的行为）
 *
 * ⚠️ 只注入「系统界面」：索引浮层由 SystemUI 进程承载，划掉模块应用后台也不影响呼出。
 */
class EtaModule : XposedModule() {

    @Volatile private var started = false

    private companion object {
        /** 进程名：模块加载行要等 onPackageReady 才打得出去（那时 LSPosed 的日志通道才通）。 */
        @Volatile var lastProcessName: String = ""
    }

    override fun onModuleLoaded(param: XposedModuleInterface.ModuleLoadedParam) {
        // 这里不能打日志：这一刻 LSPosed 的模块日志通道还没接上，写出去会丢（实测）。
        // 真正"一定看得见"的那一行放到 onPackageReady 里打。
        lastProcessName = param.processName
        LxApi.attach(this)
    }

    override fun onPackageReady(param: XposedModuleInterface.PackageReadyParam) {
        if (param.packageName != Const.SYSTEMUI_PACKAGE) {

            try {
                detach()
            } catch (_: Throwable) {
            }
            return
        }
        // 极少数场景下 onPackageReady 可能晚于 Application.onCreate，那就直接开工
        val existing = currentApplication()
        if (existing != null) {
            start(existing)
            return
        }
        val method = try {
            Application::class.java.getDeclaredMethod("onCreate")
        } catch (_: Throwable) {
            null
        }
        val hooked = LxApi.hookAfter(method) { obj ->
            (obj as? Application)?.let { start(it) }
        }
        if (!hooked) XLog.e("注入系统界面失败：Application.onCreate 钩不上")
    }

    private fun start(app: Application) {
        if (started) return
        started = true
        XLog.a(
            "模块加载完成：api=$apiVersion $frameworkName $frameworkVersion 进程=$lastProcessName"
        )
        try {
            ConfigReader.attach(app)

            // 先读一次配置：log_verbose 要尽早生效，否则启动阶段（装钩子）的日志永远看不到
            ConfigReader.current()
        } catch (t: Throwable) {
            XLog.e("配置读取初始化失败", t)
        }
        XLog.i("注入系统界面进程")


        try {
            SystemUiHost.sync(app)
        } catch (t: Throwable) {
            XLog.e("SystemUI 承载启动失败", t)
        }
    }

    /** `ActivityThread.currentApplication()`：只在 onPackageReady 这一次探一下，之后不再用反射。 */
    private fun currentApplication(): Application? = try {
        val cls = Class.forName("android.app.ActivityThread")
        cls.getDeclaredMethod("currentApplication").invoke(null) as? Application
    } catch (_: Throwable) {
        null
    }
}
