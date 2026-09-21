package com.vinhamimh.vi_nha_minh

import android.content.Context
import android.os.SystemClock
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/**
 * Khoá ứng dụng (App Lock) — CHỈ bảo vệ thiết bị, KHÔNG phải xác thực Account.
 *
 * Verifier của PIN = HMAC-SHA256(khoá Keystore không xuất được, PBKDF2-HMAC-SHA256(pin, salt, N)).
 *  - Không lưu PIN, không lưu hash thuần: chép file prefs sang máy khác vô dụng vì thiếu
 *    khoá Keystore (không thể trích xuất khỏi thiết bị).
 *  - Bộ đếm sai + thời điểm hết khoá lưu ngay cạnh verifier; tăng bộ đếm TRƯỚC khi so
 *    sánh để force-stop giữa chừng không reset được.
 * Không ghi log bất cứ giá trị nào ở đây.
 */
class AppLockStore(context: Context) {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(): Boolean = prefs.contains(K_VERIFIER)

    fun status(): Map<String, Any> = mapOf(
        "enabled" to isEnabled(),
        "biometric" to prefs.getBoolean(K_BIOMETRIC, false),
        "failedAttempts" to prefs.getInt(K_FAILS, 0),
        "lockoutRemainingMs" to lockoutRemainingMs(),
        "credentialBroken" to (isEnabled() && !keyExists()),
    )

    fun setPin(pin: String, rotateKey: Boolean) {
        require(pin.length == PIN_LENGTH && pin.all { it in '0'..'9' }) { "invalid pin" }
        if (rotateKey || !keyExists()) createKey()
        val salt = ByteArray(SALT_BYTES).also { SecureRandom().nextBytes(it) }
        val verifier = verifierFor(pin, salt, ITERATIONS)
        // 1 lần commit() duy nhất: verifier cũ vẫn hợp lệ cho tới khi cái mới ghi xong.
        val ok = prefs.edit()
            .putString(K_SALT, b64(salt))
            .putString(K_VERIFIER, b64(verifier))
            .putInt(K_ITER, ITERATIONS)
            .putInt(K_FAILS, 0)
            .remove(K_LOCK_ELAPSED).remove(K_LOCK_WALL).remove(K_LOCK_BOOT)
            .commit()
        if (!ok) throw IllegalStateException("persist failed")
    }

    /** Trả về map {result: ok|wrong|locked_out|no_credential|broken, remainingMs, failedAttempts}. */
    fun verify(pin: String): Map<String, Any> {
        val salt = prefs.getString(K_SALT, null)?.let(::unb64)
        val expected = prefs.getString(K_VERIFIER, null)?.let(::unb64)
        if (salt == null || expected == null) return result("no_credential")
        val remaining = lockoutRemainingMs()
        if (remaining > 0) return result("locked_out")
        if (!keyExists()) return result("broken")
        val fails = prefs.getInt(K_FAILS, 0) + 1
        prefs.edit().putInt(K_FAILS, fails).commit()
        val actual = try {
            verifierFor(pin, salt, prefs.getInt(K_ITER, ITERATIONS))
        } catch (e: Exception) {
            return result("broken")
        }
        if (MessageDigest.isEqual(expected, actual)) {
            prefs.edit().putInt(K_FAILS, 0)
                .remove(K_LOCK_ELAPSED).remove(K_LOCK_WALL).remove(K_LOCK_BOOT).commit()
            return result("ok")
        }
        val delay = delayForFailures(fails)
        if (delay > 0) {
            prefs.edit()
                .putLong(K_LOCK_ELAPSED, SystemClock.elapsedRealtime() + delay)
                .putLong(K_LOCK_WALL, System.currentTimeMillis() + delay)
                .putInt(K_LOCK_BOOT, bootCount())
                .commit()
        }
        return result("wrong")
    }

    fun setBiometric(on: Boolean) {
        if (!isEnabled()) return
        prefs.edit().putBoolean(K_BIOMETRIC, on).commit()
    }

    /** Xác minh chủ máy (khoá màn hình hệ thống) xong: gỡ khoá chờ, cho phép đặt PIN mới. */
    fun clearAttempts() {
        prefs.edit().putInt(K_FAILS, 0)
            .remove(K_LOCK_ELAPSED).remove(K_LOCK_WALL).remove(K_LOCK_BOOT).commit()
    }

    fun disable() {
        prefs.edit().clear().commit()
        deleteKey()
    }

    private fun result(r: String): Map<String, Any> = mapOf(
        "result" to r,
        "remainingMs" to lockoutRemainingMs(),
        "failedAttempts" to prefs.getInt(K_FAILS, 0),
    )

    private fun lockoutRemainingMs(): Long {
        if (!prefs.contains(K_LOCK_WALL)) return 0
        val remaining = if (prefs.getInt(K_LOCK_BOOT, -1) == bootCount() && bootCount() != -1) {
            // Cùng lần khởi động: đồng hồ đơn điệu (tính cả lúc máy ngủ), không sửa được bằng đổi giờ.
            prefs.getLong(K_LOCK_ELAPSED, 0) - SystemClock.elapsedRealtime()
        } else {
            // Sau khi khởi động lại: elapsedRealtime về 0 nên dùng giờ tường, kẹp tối đa.
            prefs.getLong(K_LOCK_WALL, 0) - System.currentTimeMillis()
        }
        return remaining.coerceIn(0, MAX_DELAY_MS)
    }

    private fun bootCount(): Int =
        Settings.Global.getInt(appContext.contentResolver, "boot_count", -1)

    private fun delayForFailures(n: Int): Long = when {
        n < 5 -> 0
        n == 5 -> 30_000
        n == 6 -> 60_000
        n == 7 -> 300_000
        n == 8 -> 900_000
        else -> MAX_DELAY_MS
    }

    private fun verifierFor(pin: String, salt: ByteArray, iterations: Int): ByteArray {
        val spec = PBEKeySpec(pin.toCharArray(), salt, iterations, 256)
        val derived = try {
            // Chỉ là thuật toán KDF (PBKDF2). PBKDF2-HMAC-SHA256 có từ API 26; API 24-25 dùng
            // PBKDF2WithHmacSHA1 làm KDF dự phòng — KHÔNG phải băm SHA1 của PIN. Bước sau vẫn
            // là HMAC-SHA256 bằng khoá Keystore ở mọi API, nên verifier luôn cần khoá đó.
            val algo = if (android.os.Build.VERSION.SDK_INT >= 26) "PBKDF2withHmacSHA256"
            else "PBKDF2WithHmacSHA1"
            SecretKeyFactory.getInstance(algo).generateSecret(spec).encoded
        } finally {
            spec.clearPassword()
        }
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(pepperKey() ?: throw IllegalStateException("no key"))
        return mac.doFinal(derived)
    }

    private fun keystore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun keyExists(): Boolean = try {
        keystore().containsAlias(KEY_ALIAS)
    } catch (e: Exception) {
        false
    }

    private fun pepperKey(): SecretKey? = try {
        keystore().getKey(KEY_ALIAS, null) as? SecretKey
    } catch (e: Exception) {
        null
    }

    private fun createKey() {
        deleteKey()
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, "AndroidKeyStore")
        gen.init(KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_SIGN).build())
        gen.generateKey()
    }

    private fun deleteKey() {
        try {
            val ks = keystore()
            if (ks.containsAlias(KEY_ALIAS)) ks.deleteEntry(KEY_ALIAS)
        } catch (e: Exception) {
            // không có gì để xoá
        }
    }

    private fun b64(b: ByteArray) = Base64.encodeToString(b, Base64.NO_WRAP)
    private fun unb64(s: String) = Base64.decode(s, Base64.NO_WRAP)

    companion object {
        const val PREFS = "app_lock_secure"
        private const val KEY_ALIAS = "vnm_app_lock_pepper_v1"
        private const val K_SALT = "salt"
        private const val K_VERIFIER = "verifier"
        private const val K_ITER = "iterations"
        private const val K_BIOMETRIC = "biometric"
        private const val K_FAILS = "fails"
        private const val K_LOCK_ELAPSED = "lock_until_elapsed"
        private const val K_LOCK_WALL = "lock_until_wall"
        private const val K_LOCK_BOOT = "lock_boot"
        private const val PIN_LENGTH = 6
        private const val SALT_BYTES = 16
        private const val ITERATIONS = 210_000
        private const val MAX_DELAY_MS = 1_800_000L
    }
}

class AppLockBridge(private val store: AppLockStore) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "status" -> result.success(store.status())
                "setPin" -> {
                    store.setPin(
                        call.argument<String>("pin") ?: "",
                        call.argument<Boolean>("rotateKey") ?: false,
                    )
                    result.success(null)
                }
                "verifyPin" -> result.success(store.verify(call.argument<String>("pin") ?: ""))
                "setBiometric" -> {
                    store.setBiometric(call.argument<Boolean>("enabled") ?: false)
                    result.success(null)
                }
                "clearAttempts" -> {
                    store.clearAttempts()
                    result.success(null)
                }
                "disable" -> {
                    store.disable()
                    result.success(null)
                }
                "elapsedRealtime" -> result.success(SystemClock.elapsedRealtime())
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            // Không đính kèm thông điệp/chi tiết: tránh rò thông tin nhạy cảm qua log.
            result.error("app_lock_error", "app lock operation failed", null)
        }
    }

    companion object {
        const val CHANNEL = "com.vinhamimh.vi_nha_minh/app_lock"
    }
}
