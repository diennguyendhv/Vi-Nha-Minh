package com.vinhamimh.vi_nha_minh

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity: bắt buộc cho local_auth (BiometricPrompt).
class MainActivity : FlutterFragmentActivity() {
    private lateinit var lockStore: AppLockStore

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        lockStore = AppLockStore(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "homewallet/session")
            .setMethodCallHandler(SessionBridge(this))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "homewallet/backup_key")
            .setMethodCallHandler(BackupKeyBridge(this))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AppLockBridge.CHANNEL)
            .setMethodCallHandler(AppLockBridge(lockStore))
    }

    // Riêng tư ở màn hình đa nhiệm (Recents): CHỈ khi App Lock bật, đặt FLAG_SECURE lúc
    // activity rời foreground rồi gỡ khi quay lại — ảnh thu nhỏ trống, còn chụp màn hình
    // khi đang dùng app vẫn bình thường.
    override fun onPause() {
        if (::lockStore.isInitialized && lockStore.isEnabled()) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
