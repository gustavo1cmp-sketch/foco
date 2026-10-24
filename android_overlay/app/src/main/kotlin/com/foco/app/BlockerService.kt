package com.foco.app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent

/**
 * Detecta qual app está em primeiro plano e abre a tela de bloqueio quando necessário.
 * Também protege as telas do sistema que permitiriam burlar o app durante uma sessão rígida
 * (desinstalar, desativar acessibilidade, remover administrador do dispositivo).
 */
class BlockerService : AccessibilityService() {

    private var lastBlocked = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return

        if (isSensitiveSystemScreen(pkg, event)) {
            if (RulesStore.strictSessionActive(this) && !hasPartnerUnlock()) {
                performGlobalAction(GLOBAL_ACTION_HOME)
                showBlock("Proteção do Foco")
                return
            }
        }

        if (RulesStore.shouldBlock(this, pkg)) {
            val now = System.currentTimeMillis()
            if (now - lastBlocked < 800) return // evita loop de abertura
            lastBlocked = now
            performGlobalAction(GLOBAL_ACTION_HOME)
            showBlock(pkg)
        }
    }

    private fun hasPartnerUnlock(): Boolean {
        val p = getSharedPreferences("foco_rules", MODE_PRIVATE)
        val now = System.currentTimeMillis()
        return p.getLong("unlock_*", 0L) > now || p.getLong("unlock_uninstall", 0L) > now
    }

    private fun isSensitiveSystemScreen(pkg: String, e: AccessibilityEvent): Boolean {
        val systemPkgs = setOf(
            "com.android.settings", "com.google.android.packageinstaller",
            "com.android.packageinstaller", "com.samsung.android.packageinstaller",
        )
        if (pkg !in systemPkgs) return false
        val text = (e.text.joinToString(" ") + " " + (e.className ?: "")).lowercase()
        return text.contains("foco") || text.contains("device admin") ||
            text.contains("administrador do dispositivo") || text.contains("acessibilidade")
    }

    private fun showBlock(target: String) {
        startActivity(Intent(this, BlockActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("target", target)
        })
    }

    override fun onInterrupt() {}
}
