package com.eta.sideindexx.config

import android.content.Context
import android.net.Uri
import com.eta.sideindexx.Const
import com.eta.sideindexx.util.XLog
import de.robv.android.xposed.XSharedPreferences
import java.io.File

/**
 * Hook 进程侧的配置读取，通道顺序：
 *   0) Settings.Secure（主通道，任何进程免权限，不依赖模块应用存活）
 *   1) XSharedPreferences（经典方式，部分 ROM 可用）
 *   2) 模块的 ContentProvider
 *   3) 直读 SharedPreferences XML
 */
object ConfigReader {

    private val IDLE = ModuleConfig(enabled = false, source = "unavailable")
    private const val FAILURE_WARN_INTERVAL_MS = 60_000L
    private const val PROVIDER_MIN_INTERVAL_MS = 1500L

    @Volatile private var candidates: List<Pair<String, XSharedPreferences>> = emptyList()
    @Volatile private var direct: DirectPrefs? = null
    @Volatile private var cached: ModuleConfig = ModuleConfig()
    @Volatile private var lastReloadAt = 0L
    @Volatile private var lastSource = "none"
    @Volatile private var lastFailureWarnAt = 0L
    @Volatile private var configAvailable = false
    @Volatile private var appContext: Context? = null
    @Volatile private var lastProviderAt = 0L
    private var initialized = false

    fun attach(context: Context?) {
        if (appContext != null) return
        val ctx = context?.applicationContext ?: context ?: return
        appContext = ctx
    }

    fun current(): ModuleConfig {
        ensureInit()
        val interval = cached.reloadIntervalMs.toLong().coerceAtLeast(300L)
        val now = System.currentTimeMillis()
        if (now - lastReloadAt < interval) return if (configAvailable) cached else IDLE
        synchronized(this) {
            if (System.currentTimeMillis() - lastReloadAt < interval) {
                return if (configAvailable) cached else IDLE
            }
            lastReloadAt = System.currentTimeMillis()
            load()?.let {
                cached = it
                XLog.setVerbose(it.logVerbose)
            } ?: run {
                if (!configAvailable && now - lastFailureWarnAt > FAILURE_WARN_INTERVAL_MS) {
                    lastFailureWarnAt = now
                    XLog.w("暂时读不到模块配置，本次不启用索引（打开一次模块设置页即可生成）")
                }
            }
        }
        return if (configAvailable) cached else IDLE
    }

    fun invalidate() { lastReloadAt = 0L }

    fun sourceName(): String { ensureInit(); return lastSource }

    private fun ensureInit() {
        if (initialized) return
        synchronized(this) {
            if (initialized) return
            initialized = true
            candidates = buildCandidates()
            direct = DirectPrefs(PrefFiles.modulePrefsFile())
            load()?.let {
                cached = it
                XLog.setVerbose(it.logVerbose)
            }
            XLog.i("配置初始化：source=$lastSource 可读=$configAvailable")
        }
    }

    private fun load(): ModuleConfig? {
        appContext?.let { ctx ->
            SecureConfigChannel.read(ctx)?.let {
                if (lastSource != "secure") XLog.i("配置来源：Settings.Secure")
                lastSource = "secure"
                configAvailable = true
                return it
            }
        }

        for ((label, prefs) in candidates) {
            try {
                prefs.reload()
                val map = prefs.all
                if (map != null && map.isNotEmpty()) {
                    if (lastSource != label) XLog.i("配置来源：$label（${map.size} 项）")
                    lastSource = label
                    configAvailable = true
                    return ModuleConfig.read(SharedPrefSource(prefs), label)
                }
            } catch (t: Throwable) {
                XLog.d("读取失败 $label：${t.javaClass.simpleName}")
            }
        }

        readViaProvider()?.let { return it }

        val d = direct
        if (d != null && d.exists()) {
            val map = d.read()
            if (map != null) {
                lastSource = "direct-xml"
                configAvailable = true
                return ModuleConfig.read(MapPrefSource(map), lastSource)
            }
        }
        if (!configAvailable) lastSource = "none"
        return null
    }

    private fun readViaProvider(): ModuleConfig? {
        val ctx = appContext ?: return null
        val now = System.currentTimeMillis()
        if (now - lastProviderAt < PROVIDER_MIN_INTERVAL_MS) return null
        lastProviderAt = now
        return try {
            val bundle = ctx.contentResolver.call(
                Uri.parse(Const.PROVIDER_URI), Const.PROVIDER_METHOD_GET, null, null
            )
            val payload = bundle?.getString(Const.PROVIDER_KEY_PAYLOAD)
            ConfigCodec.decode(payload)?.also {
                lastSource = "provider"
                configAvailable = true
                XLog.d("配置来源：provider")
            }
        } catch (t: Throwable) {
            XLog.d("provider 读取失败：${t.javaClass.simpleName}")
            null
        }
    }

    private fun buildCandidates(): List<Pair<String, XSharedPreferences>> {
        val cls = XSharedPreferences::class.java
        val file: File = PrefFiles.modulePrefsFile()
        val attempts = listOf<Pair<String, () -> XSharedPreferences>>(
            "fileName" to { cls.getConstructor(String::class.java).newInstance(Const.PREFS_NAME) },
            "packageName+fileName" to {
                cls.getConstructor(String::class.java, String::class.java)
                    .newInstance(Const.MODULE_PACKAGE, Const.PREFS_NAME)
            },
            "file" to { cls.getConstructor(File::class.java).newInstance(file) }
        )
        val result = ArrayList<Pair<String, XSharedPreferences>>(attempts.size)
        for ((label, factory) in attempts) {
            try { result.add(label to factory()) } catch (t: Throwable) {
                XLog.d("XSharedPreferences 构造失败（$label）：${t.javaClass.simpleName}")
            }
        }
        return result
    }
}
