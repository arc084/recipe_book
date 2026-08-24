package io.github.arc084.recipe_book

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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

        // The update flow's one native need: handing a downloaded APK to the
        // system installer. Same no-plugin reasoning as the share channel.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            INSTALL_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("badArgs", "installApk needs a path", null)
                    } else {
                        try {
                            installApk(path)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("installFailed", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Opens the system installer on the APK at [path].
     *
     * The file travels as a content URI from the manifest's FileProvider —
     * a raw file:// path has not been accepted since Android 7. The system
     * shows its own confirmation, which is correct and not worked around.
     */
    private fun installApk(path: String) {
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            File(path),
        )
        startActivity(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            },
        )
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
        const val INSTALL_CHANNEL = "recipe_book/install"
    }
}
