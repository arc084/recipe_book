package io.github.arc084.recipe_book

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Receives a page shared to Recipe Book and hands the address to Dart.
 *
 * This is done with a plain method channel rather than a plugin: the app only
 * needs ACTION_SEND with text/plain, and every share plugin currently applies
 * the Kotlin Gradle Plugin, which Flutter has begun warning about.
 *
 * Two paths have to work. A share that starts the app cold arrives before Dart
 * is listening, so it is held and collected by `getInitialSharedText`. A share
 * that arrives while the app is already running comes through `onNewIntent`
 * and is pushed straight over.
 */
class MainActivity : FlutterActivity() {

    private var pendingSharedText: String? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialSharedText" -> {
                        // Read once and clear, so a rotation or a later resume
                        // does not re-import the same page.
                        result.success(pendingSharedText)
                        pendingSharedText = null
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // The launch intent is available before Dart asks for it.
        pendingSharedText = extractSharedText(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val shared = extractSharedText(intent) ?: return
        val sink = channel
        if (sink != null) {
            sink.invokeMethod("onSharedText", shared)
        } else {
            // Dart is not attached yet; let it collect this on startup.
            pendingSharedText = shared
        }
    }

    /** The shared text, or null when this intent is not a text share. */
    private fun extractSharedText(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_SEND) return null
        if (intent.type != "text/plain") return null
        return intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()?.ifEmpty { null }
    }

    private companion object {
        const val CHANNEL = "recipe_book/share"
    }
}
