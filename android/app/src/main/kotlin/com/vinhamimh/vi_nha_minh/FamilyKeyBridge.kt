package com.vinhamimh.vi_nha_minh

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * P10 Family: this installation's X25519 device private key (32-byte seed) at
 * rest, wrapped by a non-exportable Android Keystore AES-256-GCM key with its OWN
 * alias (never the BMK/App Lock/session/DB keys). One slot per Account; AAD binds
 * the ciphertext to uid + installationId. Never logs arguments or key bytes.
 */
class FamilyKeyBridge(context: Context) : MethodChannel.MethodCallHandler {
    private val prefs = context.getSharedPreferences("family_key_secure", Context.MODE_PRIVATE)
    private val alias = "homewallet_family_device_v1"
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
    private fun slot(uid: String): String {
        val d = MessageDigest.getInstance("SHA-256").digest(uid.toByteArray(Charsets.UTF_8))
        return "dk." + d.joinToString("") { "%02x".format(it) }
    }
    private fun aad(uid: String, installationId: String) =
        "family-device|$uid|$installationId".toByteArray(Charsets.UTF_8)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            val uid = requireNotNull(call.argument<String>("uid"))
            when (call.method) {
                "load" -> {
                    val raw = prefs.getString(slot(uid), null)
                    val installationId = prefs.getString(slot(uid) + ".i", null)
                    if (raw == null || installationId == null) {
                        result.success(null)
                    } else {
                        val bytes = Base64.decode(raw, Base64.NO_WRAP)
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
                        cipher.updateAAD(aad(uid, installationId))
                        val seed = cipher.doFinal(bytes.copyOfRange(12, bytes.size))
                        result.success(mapOf("installationId" to installationId,
                            "seed" to Base64.encodeToString(seed, Base64.NO_WRAP)))
                        seed.fill(0)
                    }
                }
                "store" -> {
                    val installationId = requireNotNull(call.argument<String>("installationId"))
                    val seed = Base64.decode(requireNotNull(call.argument<String>("seed")), Base64.NO_WRAP)
                    require(seed.size == 32)
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.ENCRYPT_MODE, key())
                    cipher.updateAAD(aad(uid, installationId))
                    val encrypted = cipher.iv + cipher.doFinal(seed)
                    seed.fill(0)
                    check(prefs.edit().putString(slot(uid) + ".i", installationId)
                        .putString(slot(uid), Base64.encodeToString(encrypted, Base64.NO_WRAP)).commit())
                    result.success(null)
                }
                "clear" -> {
                    check(prefs.edit().remove(slot(uid)).remove(slot(uid) + ".i").commit())
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("family_key_unavailable", "Secure storage unavailable", null)
        }
    }
}
