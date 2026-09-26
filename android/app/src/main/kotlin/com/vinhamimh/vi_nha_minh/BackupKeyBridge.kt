package com.vinhamimh.vi_nha_minh

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * P8: Wallet Backup Master Key (BMK) at rest, wrapped by a non-exportable
 * Android Keystore AES-256-GCM key (separate alias from App Lock and P7 session).
 * AAD binds the ciphertext to uid + walletId. Never logs arguments or key bytes.
 * No user-auth requirement on the key: incremental backup must run unattended;
 * App Lock remains the interactive device gate.
 */
class BackupKeyBridge(context: Context) : MethodChannel.MethodCallHandler {
    private val prefs = context.getSharedPreferences("backup_key_secure", Context.MODE_PRIVATE)
    private val alias = "homewallet_backup_bmk_v1"
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    private fun aad(uid: String, walletId: String) = "$uid|$walletId".toByteArray(Charsets.UTF_8)
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "load" -> {
                    val uid = requireNotNull(call.argument<String>("uid"))
                    val raw = prefs.getString("bmk", null)
                    val walletId = prefs.getString("wallet", null)
                    if (raw == null || walletId == null || prefs.getString("account", null) != uid) {
                        result.success(null)
                    } else {
                        val bytes = Base64.decode(raw, Base64.NO_WRAP)
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
                        cipher.updateAAD(aad(uid, walletId))
                        val bmk = cipher.doFinal(bytes.copyOfRange(12, bytes.size))
                        result.success(mapOf("walletId" to walletId,
                            "bmk" to Base64.encodeToString(bmk, Base64.NO_WRAP)))
                        bmk.fill(0)
                    }
                }
                "store" -> {
                    val uid = requireNotNull(call.argument<String>("uid"))
                    val walletId = requireNotNull(call.argument<String>("walletId"))
                    val bmk = Base64.decode(requireNotNull(call.argument<String>("bmk")), Base64.NO_WRAP)
                    require(bmk.size == 32)
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.ENCRYPT_MODE, key())
                    cipher.updateAAD(aad(uid, walletId))
                    val encrypted = cipher.iv + cipher.doFinal(bmk)
                    bmk.fill(0)
                    check(prefs.edit().putString("account", uid).putString("wallet", walletId)
                        .putString("bmk", Base64.encodeToString(encrypted, Base64.NO_WRAP)).commit())
                    result.success(null)
                }
                "clear" -> {
                    check(prefs.edit().clear().commit())
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("backup_key_unavailable", "Secure storage unavailable", null)
        }
    }
}
