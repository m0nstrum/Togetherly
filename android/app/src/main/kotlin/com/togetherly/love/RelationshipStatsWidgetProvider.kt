package com.togetherly.love

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Виджет «Relationship Stats» — 2×2 сетка:
 * Days Together, Memories, Drawings, Miss Yous.
 */
class RelationshipStatsWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId -> render(context, appWidgetManager, widgetId, widgetData) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        val data = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        render(context, appWidgetManager, appWidgetId, data)
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
    }

    private fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetId: Int,
        widgetData: SharedPreferences,
    ) {
        val g = WidgetGroupHelper.getOrBind(context, "stats", widgetId)
        // В тесной ячейке — компактная сетка (B7): полной нужно ≈237dp при
        // гарантированных 180dp, и подписи нижних плиток срезались.
        val options = appWidgetManager.getAppWidgetOptions(widgetId)
        val layout = WidgetSizing.fit(
            context, options,
            R.layout.relationship_stats_widget, R.layout.relationship_stats_widget_compact, 238,
        )
        val views = RemoteViews(context.packageName, layout).apply {

            val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("loveapp://home")
            )
            setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            // ── Data ──
            val days = if (g.isEmpty()) "0" else widgetData.getString("stats_${g}_days", "0") ?: "0"
            val memories = if (g.isEmpty()) "0" else widgetData.getString("stats_${g}_memories", "0") ?: "0"
            val drawings = if (g.isEmpty()) "0" else widgetData.getString("stats_${g}_drawings", "0") ?: "0"
            val missYou = if (g.isEmpty()) "0" else widgetData.getString("stats_${g}_miss_you", "0") ?: "0"

            // ── Labels ──
            val daysLabel = if (g.isEmpty()) "Days Together" else widgetData.getString("stats_${g}_days_label", "Days Together") ?: "Days Together"
            val memoriesLabel = if (g.isEmpty()) "Memories" else widgetData.getString("stats_${g}_memories_label", "Memories") ?: "Memories"
            val drawingsLabel = if (g.isEmpty()) "Drawings" else widgetData.getString("stats_${g}_drawings_label", "Drawings") ?: "Drawings"
            val missYouLabel = if (g.isEmpty()) "Miss Yous" else widgetData.getString("stats_${g}_miss_you_label", "Miss Yous") ?: "Miss Yous"

            // ── Populate Views ──
            setTextViewText(R.id.stat_days_value, days)
            setTextViewText(R.id.stat_days_label, daysLabel)

            setTextViewText(R.id.stat_memories_value, memories)
            setTextViewText(R.id.stat_memories_label, memoriesLabel)

            setTextViewText(R.id.stat_drawings_value, drawings)
            setTextViewText(R.id.stat_drawings_label, drawingsLabel)

            setTextViewText(R.id.stat_miss_you_value, missYou)
            setTextViewText(R.id.stat_miss_you_label, missYouLabel)
        }

        appWidgetManager.updateAppWidget(widgetId, views)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        WidgetGroupHelper.clearBindings(context, "stats", appWidgetIds)
    }
}
