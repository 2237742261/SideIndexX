package com.eta.sideindexx

import android.app.Application
import com.eta.sideindexx.config.ConfigReader
import com.eta.sideindexx.overlay.SystemUiHost
import com.eta.sideindexx.util.XLog
import de.robv.android.xposed.IXposedHookLoadPackage
import de.robv.android.xposed.IXposedHookZygoteInit
import de.robv.android.xposed.XC_MethodHook
import de.robv.android.xposed.XposedHelpers
import de.robv.android.xposed.callbacks.XC_LoadPackage

/**
 * 模块入口。
 *
 * 只注入「系统界面」：索引浮层由 SystemUI 进程承载，
 * 因此不需要作用域里勾任何目标应用，也不需要前台服务保活。
 */
class ModuleEntry : IXposedHookLoadPackage, IXposedHookZygoteInit {

    override fun initZygote(startupParam: IXposedHookZygoteInit.StartupParam) {
        XLog.i("模块加载完成，modulePath=${startupParam.modulePath}")
    }

    override fun handleLoadPackage(lpparam: XC_LoadPackage.LoadPackageParam) {
        val pkg = lpparam.packageName ?: return

        // 自身设置界面、system_server（LSPosed 里可能报成 android 或 system）都跳过
        if (pkg == Const.MODULE_PACKAGE) return
        if (pkg == "android" || pkg == "system") return
        if (pkg != Const.SYSTEMUI_PACKAGE) return

        XLog.i("注入系统界面进程")
        try {
            XposedHelpers.findAndHookMethod(
                Application::class.java,
                "onCreate",
                object : XC_MethodHook() {
                    override fun afterHookedMethod(param: XC_MethodHook.MethodHookParam) {
                        val app = param.thisObject as? Application ?: return
                        try {
                            ConfigReader.attach(app)
                        } catch (t: Throwable) {
                            XLog.e("配置读取初始化失败", t)
                        }
                        try {
                            SystemUiHost.sync(app)
                        } catch (t: Throwable) {
                            XLog.e("SystemUI 承载启动失败", t)
                        }
                    }
                }
            )
        } catch (t: Throwable) {
            XLog.e("Hook SystemUI 失败", t)
        }
    }
}
