package com.togetherly.love

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import dev.fluttercommunity.workmanager.BackgroundWorker

/**
 * fork: FCM как будильник (docs/fork/PLAN.md, S12).
 *
 * В пуше нет ничего, кроме `{type: "sync", event: <id>}`: текст, имена и
 * id пары в Google не уходят. Пуш будит Dart разовой задачей workmanager
 * (тот же диспетчер, что у виджетов, `widgetRefreshDispatcher`), а Dart
 * забирает событие со своего сервера, расшифровывает и рисует уведомление
 * сам (lib/fork/push/fcm_wake.dart).
 *
 * Firebase-проект свой у каждого инстанса: без google-services.json при
 * сборке FirebaseApp не поднимается, [available] отвечает «нет», и
 * приложение остаётся на сокете фонового сервиса.
 */
class ForkFcmService : FirebaseMessagingService() {

    override fun onNewToken(token: String) {
        // Токен на сервер отправляет Dart (у него вход): на следующем запуске
        // getToken отдаст этот же.
        Log.i(TAG, "новый токен FCM")
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (message.data["type"] != "sync") return
        // Приложение открыто — его сокет уже доставил событие.
        if (inForeground()) return
        val event = message.data["event"] ?: return
        try {
            val request = OneTimeWorkRequestBuilder<BackgroundWorker>()
                .setInputData(
                    Data.Builder()
                        .putString(BackgroundWorker.DART_TASK_KEY, TASK)
                        .putString("payload_event", event)
                        .build(),
                )
                .setConstraints(
                    Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build(),
                )
                .build()
            // APPEND: события идут друг за другом, ни одно не теряется.
            WorkManager.getInstance(applicationContext).enqueueUniqueWork(
                "tethered_fcm_wake",
                ExistingWorkPolicy.APPEND_OR_REPLACE,
                request,
            )
        } catch (e: Exception) {
            Log.w(TAG, "не разбудили Dart: ${e.message}")
        }
    }

    private fun inForeground(): Boolean {
        val info = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(info)
        return info.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
    }

    companion object {
        private const val TAG = "ForkFcm"

        /** Задача диспетчера workmanager (ForkFcmWake.task в Dart). */
        const val TASK = "fcmWake"

        /** Есть ли Firebase в сборке и сервисы Google на телефоне. */
        fun available(context: Context): Boolean {
            if (FirebaseApp.getApps(context).isEmpty()) return false
            return try {
                context.packageManager.getPackageInfo("com.google.android.gms", 0)
                true
            } catch (_: PackageManager.NameNotFoundException) {
                false
            }
        }

        /** Токен устройства или null. */
        fun token(context: Context, done: (String?) -> Unit) {
            if (!available(context)) return done(null)
            try {
                FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                    done(if (task.isSuccessful) task.result else null)
                }
            } catch (e: Exception) {
                Log.w(TAG, "токен FCM: ${e.message}")
                done(null)
            }
        }
    }
}
