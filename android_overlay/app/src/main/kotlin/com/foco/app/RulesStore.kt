package com.foco.app

import android.annotation.SuppressLint
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * Guarda as regras enviadas pelo Flutter e decide se um pacote deve ser bloqueado agora.
 * Roda dentro do AccessibilityService, então não depende do Flutter estar aberto.
 */
object RulesStore {
    private const val PREFS = "foco_rules"

    fun save(ctx: Context, profiles: String, schedules: String, activeProfile: String?, endsAt: Long?) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("profiles", profiles)
            .putString("schedules", schedules)
            .putString("activeProfile", activeProfile)
            .putLong("endsAt", endsAt ?: 0L)
            .apply()
    }

    /** Liberação temporária concedida pelo parceiro. target == null libera tudo. */
    fun grantUnlock(ctx: Context, target: String?, untilMillis: Long) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putLong("unlock_${target ?: "*"}", untilMillis).apply()
    }

    private fun isUnlocked(ctx: Context, pkg: String): Boolean {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        return p.getLong("unlock_$pkg", 0L) > now || p.getLong("unlock_*", 0L) > now
    }

    private fun profiles(ctx: Context): List<JSONObject> {
        val s = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("profiles", "[]")!!
        val a = JSONArray(s)
        return (0 until a.length()).map { a.getJSONObject(it) }
    }

    private fun profileIdsActiveNow(ctx: Context): Set<String> {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val ids = mutableSetOf<String>()

        // 1) Sessão manual em andamento
        val ends = p.getLong("endsAt", 0L)
        val active = p.getString("activeProfile", null)
        if (active != null && ends > System.currentTimeMillis()) ids += active

        // 2) Agendamentos recorrentes
        val cal = Calendar.getInstance()
        val weekday = ((cal.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1 // 1=segunda..7=domingo
        val minutes = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
        val arr = JSONArray(p.getString("schedules", "[]"))
        for (i in 0 until arr.length()) {
            val sc = arr.getJSONObject(i)
            if (!sc.optBoolean("enabled", true)) continue
            val days = sc.getJSONArray("weekdays")
            val onDay = (0 until days.length()).any { days.getInt(it) == weekday }
            if (!onDay) continue
            val start = sc.getInt("startMinutes")
            val end = sc.getInt("endMinutes")
            val inside = if (start <= end) minutes in start until end else (minutes >= start || minutes < end)
            if (inside) ids += sc.getString("profileId")
        }
        return ids
    }

    /** True se este pacote deve ser bloqueado neste instante. */
    fun shouldBlock(ctx: Context, pkg: String): Boolean {
        if (pkg == ctx.packageName || isUnlocked(ctx, pkg)) return false
        val activeIds = profileIdsActiveNow(ctx)

        for (prof in profiles(ctx)) {
            val apps = prof.getJSONArray("blockedApps")
            val listed = (0 until apps.length()).any { apps.getString(it) == pkg }
            if (!listed) continue

            // Bloqueio por horário/sessão
            if (prof.getString("id") in activeIds) return true

            // Bloqueio por localização
            if (insideGeofence(ctx, prof)) return true

            // Limite diário por app
            // Limite diário: ausente = sem limite; 0 = bloqueado o dia todo
            val lims = prof.optJSONObject("dailyLimitMinutes")
            if (lims != null && lims.has(pkg)) {
                val limit = lims.optInt(pkg, 0)
                if (limit <= 0 || usageTodayMinutes(ctx, pkg) >= limit) return true
            }
        }
        return false
    }

    /** Sessão rígida ativa? (usado para proteger telas de desinstalação/acessibilidade). */
    fun strictSessionActive(ctx: Context): Boolean {
        val ids = profileIdsActiveNow(ctx)
        return profiles(ctx).any { it.getString("id") in ids && it.optBoolean("strictMode", true) }
    }

    @SuppressLint("MissingPermission")
    private fun insideGeofence(ctx: Context, prof: JSONObject): Boolean {
        val radius = prof.optDouble("radiusMeters", 0.0)
        if (radius <= 0 || prof.isNull("lat") || prof.isNull("lng")) return false
        if (ctx.checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION)
            != PackageManager.PERMISSION_GRANTED) return false
        val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val loc = lm.getProviders(true).mapNotNull { lm.getLastKnownLocation(it) }
            .maxByOrNull { it.time } ?: return false
        val out = FloatArray(1)
        Location.distanceBetween(loc.latitude, loc.longitude, prof.getDouble("lat"), prof.getDouble("lng"), out)
        return out[0] <= radius
    }

    fun usageTodayMinutes(ctx: Context, pkg: String): Int = todayUsage(ctx)[pkg] ?: 0

    fun todayUsage(ctx: Context): Map<String, Int> {
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val stats = usm.queryAndAggregateUsageStats(cal.timeInMillis, System.currentTimeMillis())
        return stats.mapValues { (it.value.totalTimeInForeground / 60000).toInt() }
            .filterValues { it > 0 }
    }

    /** Minutos totais de uso por dia nos últimos 7 dias (mais antigo primeiro). */
    fun weeklyUsage(ctx: Context): List<Int> {
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        return (6 downTo 0).map { back ->
            val start = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, -back)
                set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }
            val end = (start.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, 1) }
            usm.queryAndAggregateUsageStats(start.timeInMillis, end.timeInMillis)
                .values.sumOf { it.totalTimeInForeground / 60000 }.toInt()
        }
    }
}
