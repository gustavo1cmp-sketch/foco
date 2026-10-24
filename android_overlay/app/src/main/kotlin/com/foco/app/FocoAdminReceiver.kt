package com.foco.app

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

/**
 * Administrador do dispositivo: impede a desinstalação direta do app.
 * Para remover, o usuário precisa desativar o admin, e essa tela é protegida
 * pelo BlockerService durante sessões rígidas (precisa de liberação do parceiro).
 */
class FocoAdminReceiver : DeviceAdminReceiver() {
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence =
        "Desativar a proteção exige a aprovação do seu parceiro de confiança."
}
