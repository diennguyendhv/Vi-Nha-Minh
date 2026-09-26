package com.vinhamimh.vi_nha_minh

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** P7 storage is independent of wallet files and device lock settings. */
class SessionBridge(context: Context) : MethodChannel.MethodCallHandler {
    private val prefs = context.getSharedPreferences("cloud_session_secure", Context.MODE_PRIVATE)
    private val alias = "homewallet_cloud_session_v1"
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
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "installationId" -> {
                    var id = prefs.getString("installation", null)
                    if (id == null) {
                        id = UUID.randomUUID().toString()
                        check(prefs.edit().putString("installation", id).commit())
                    }
                    result.success(id)
                }
                "read" -> {
                    val uid = requireNotNull(call.argument<String>("uid"))
                    val raw = prefs.getString("credential", null)
                    if (raw == null || prefs.getString("account", null) != uid) {
                        result.success(null)
                    } else {
                        val bytes = Base64.decode(raw, Base64.NO_WRAP)
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
                        cipher.updateAAD(uid.toByteArray(Charsets.UTF_8))
                        result.success(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
                    }
                }
                "write" -> {
                    val uid = requireNotNull(call.argument<String>("uid"))
                    val value = requireNotNull(call.argument<String>("value"))
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.ENCRYPT_MODE, key())
                    cipher.updateAAD(uid.toByteArray(Charsets.UTF_8))
                    val encrypted = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
                    check(prefs.edit().putString("account", uid).putString("credential",
                        Base64.encodeToString(encrypted, Base64.NO_WRAP)).commit())
                    result.success(null)
                }
                "clear" -> {
                    check(prefs.edit().remove("credential").remove("account").commit())
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            // Never include underlying exception, arguments, UID or credential.
            result.error("session_storage_unavailable", "Secure storage unavailable", null)
        }
    }
}
