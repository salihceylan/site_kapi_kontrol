package com.example.site_kapi_kontrol

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class DoorWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.door_widget).apply {
                val doorName = widgetData.getString("door_name", "Kapı Seçilmedi") ?: "Kapı Seçilmedi"
                val siteName = widgetData.getString("site_name", "") ?: ""
                val statusText = widgetData.getString("door_status", "Hazır") ?: "Hazır"
                val isOnline = widgetData.getBoolean("is_online", false)
                val doorCount = widgetData.getInt("door_count", 1)
                val doorIndex = widgetData.getInt("current_door_index", 0)

                setTextViewText(R.id.widget_door_name, doorName)
                setTextViewText(R.id.widget_site_name, siteName)
                setTextViewText(R.id.widget_status_text, statusText)

                // Counter text: e.g. 1/3
                if (doorCount > 1) {
                    setTextViewText(R.id.widget_door_counter, "${doorIndex + 1}/$doorCount")
                } else {
                    setTextViewText(R.id.widget_door_counter, "")
                }

                // Prev & Next door buttons logic
                val hasPrev = doorCount > 1 && doorIndex > 0
                val hasNext = doorCount > 1 && doorIndex < doorCount - 1

                if (hasPrev) {
                    setInt(R.id.widget_btn_prev, "setBackgroundResource", R.drawable.widget_nav_button)
                    setTextColor(R.id.widget_btn_prev, Color.WHITE)
                    val prevIntent = HomeWidgetBackgroundIntent.getBroadcast(
                        context,
                        Uri.parse("sitekapi://prev_door")
                    )
                    setOnClickPendingIntent(R.id.widget_btn_prev, prevIntent)
                } else {
                    setInt(R.id.widget_btn_prev, "setBackgroundResource", R.drawable.widget_nav_button_disabled)
                    setTextColor(R.id.widget_btn_prev, Color.parseColor("#475569"))
                    setOnClickPendingIntent(R.id.widget_btn_prev, null)
                }

                if (hasNext) {
                    setInt(R.id.widget_btn_next, "setBackgroundResource", R.drawable.widget_nav_button)
                    setTextColor(R.id.widget_btn_next, Color.WHITE)
                    val nextIntent = HomeWidgetBackgroundIntent.getBroadcast(
                        context,
                        Uri.parse("sitekapi://next_door")
                    )
                    setOnClickPendingIntent(R.id.widget_btn_next, nextIntent)
                } else {
                    setInt(R.id.widget_btn_next, "setBackgroundResource", R.drawable.widget_nav_button_disabled)
                    setTextColor(R.id.widget_btn_next, Color.parseColor("#475569"))
                    setOnClickPendingIntent(R.id.widget_btn_next, null)
                }

                // Online vs Offline styling & behavior
                if (isOnline) {
                    setTextViewText(R.id.widget_status_dot, "●")
                    setTextColor(R.id.widget_status_dot, Color.parseColor("#34D399"))
                    setTextColor(R.id.widget_status_text, Color.parseColor("#34D399"))

                    setCharSequence(R.id.widget_open_button, "setText", "KAPIYI AÇ")
                    setInt(R.id.widget_open_button, "setBackgroundResource", R.drawable.widget_button_background)
                    setTextColor(R.id.widget_open_button, Color.WHITE)

                    val openIntent = HomeWidgetBackgroundIntent.getBroadcast(
                        context,
                        Uri.parse("sitekapi://open_door_action")
                    )
                    setOnClickPendingIntent(R.id.widget_open_button, openIntent)
                } else {
                    setTextViewText(R.id.widget_status_dot, "●")
                    setTextColor(R.id.widget_status_dot, Color.parseColor("#EF4444"))
                    setTextColor(R.id.widget_status_text, Color.parseColor("#EF4444"))

                    setCharSequence(R.id.widget_open_button, "setText", "KAPI ÇEVRİMDIŞI")
                    setInt(R.id.widget_open_button, "setBackgroundResource", R.drawable.widget_button_disabled)
                    setTextColor(R.id.widget_open_button, Color.parseColor("#94A3B8"))

                    val offlineIntent = HomeWidgetBackgroundIntent.getBroadcast(
                        context,
                        Uri.parse("sitekapi://door_offline_action")
                    )
                    setOnClickPendingIntent(R.id.widget_open_button, offlineIntent)
                }

                // App launch intent when tapping the widget container/title
                val launchIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("sitekapi://door_control")
                )
                setOnClickPendingIntent(R.id.widget_container, launchIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
