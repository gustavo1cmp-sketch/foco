package com.foco.app

import android.app.AppOpsManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "foco/native")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "installedApps" -> {
                    val pm = packageManager
                    val launch = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                    val list = pm.queryIntentActivities(launch, 0)
                        .filter { it.activityInfo.packageName != packageName }
                        .map {
                            mapOf(
                                "package" to it.activityInfo.packageName,
                                "label" to it.loadLabel(pm).toString(),
                            )
                        }
                        .distinctBy { it["package"] }
                        .sortedBy { it["label"]?.lowercase() }
                    result.success(list)
                }
                "permissions" -> result.success(permissionState())
                "requestPermission" -> {
                    requestPermission(call.argument<String>("name")!!)
                    result.success(null)
                }
                "syncRules" -> {
                    RulesStore.save(
                        this,
                        call.argument<String>("profiles") ?: "[]",
                        call.argument<String>("schedules") ?: "[]",
                        call.argument<String>("activeSessionProfileId"),
                        (call.argument<Number>("sessionEndsAt"))?.toLong(),
                    )
                    result.success(null)
                }
                "grantUnlock" -> {
                    RulesStore.grantUnlock(
                        this,
                        call.argument<String>("target"),
                        call.argument<Number>("until")!!.toLong(),
                    )
                    result.success(null)
                }
                "todayUsage" -> result.success(RulesStore.todayUsage(this))
                "weeklyUsage" -> result.success(RulesStore.weeklyUsage(this))
                "setUninstallProtection" -> result.success(null) // via Device Admin (permissão)
                else -> result.notImplemented()
            }
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(i: Intent?) {
        i?.getStringExtra("blocked_target")?.let {
            if (::channel.isInitialized) channel.invokeMethod("blockedAttempt", it)
        }
    }

    private fun permissionState(): Map<String, Boolean> {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val enabled = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
        val ops = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val usage = ops.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName
        ) == AppOpsManager.MODE_ALLOWED
        return mapOf(
            "accessibility" to enabled.contains("$packageName/${BlockerService::class.java.name}"),
            "usage" to usage,
            "deviceAdmin" to dpm.isAdminActive(ComponentName(this, FocoAdminReceiver::class.java)),
            "overlay" to Settings.canDrawOverlays(this),
        )
    }

    private fun requestPermission(name: String) {
        val intent = when (name) {
            "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            "usage" -> Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            "overlay" -> Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
            "deviceAdmin" -> Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, ComponentName(this@MainActivity, FocoAdminReceiver::class.java))
                putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Evita que o Foco seja desinstalado sem o seu parceiro.")
            }
            else -> return
        }
        startActivity(intent)
    }
}
