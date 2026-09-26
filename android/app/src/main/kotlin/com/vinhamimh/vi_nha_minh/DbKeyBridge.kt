package com.vinhamimh.vi_nha_minh

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * SQLCipher phase: per-Wallet Database Encryption Key (DEK-DB, 256-bit random)
 * wrapped by a dedicated non-exportable Android Keystore AES-256-GCM key.
 *
 * - One entry per Wallet DB file (`dbFileName`); independent random key each.
 * - AAD = "vinhaminh-db-key|v1|<dbFileName>"; the wrapped plaintext also carries
 *   the walletId, so it is authenticated too (bound after first open).
 * - Never derived from PIN / Google / Backup Password / walletId.
 * - An existing entry is NEVER overwritten or deleted by this bridge: losing it
 *   would make the encrypted DB unreadable.
 * - No logging of arguments, keys or exception details.
 * Not user-auth bound: the DB must open before App Lock UI (App Lock stays UX).
 */
class DbKeyBridge(context: Context) : MethodChannel.MethodCallHandler {
    private val prefs = context.getSharedPreferences("db_key_secure", Context.MODE_PRIVATE)
    private val alias = "homewallet_db_wrap_v1"
    private val version = 1
    private fun key(create: Boolean): SecretKey? {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        if (!create) return null
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    private fun aad(file: String) = "vinhaminh-db-key|v$version|$file".toByteArray(Charsets.UTF_8)
    private fun entryName(file: String): String {
        require(Regex("^[A-Za-z0-9._-]{1,128}$").matches(file))
        return "wallet_db:$file"
    }
    private fun wrap(file: String, raw: ByteArray, walletId: String?): String {
        val body = JSONObject().put("k", Base64.encodeToString(raw, Base64.NO_WRAP))
            .put("w", walletId ?: JSONObject.NULL).toString().toByteArray(Charsets.UTF_8)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(true))
        cipher.updateAAD(aad(file))
        val out = cipher.iv + cipher.doFinal(body)
        body.fill(0)
        return JSONObject().put("v", version)
            .put("c", Base64.encodeToString(out, Base64.NO_WRAP)).toString()
    }
    /** Returns (rawKey, walletId?) or throws if the Keystore key is gone/invalid. */
    private fun unwrap(file: String, stored: String): Pair<ByteArray, String?> {
        val entry = JSONObject(stored)
        require(entry.getInt("v") == version)
        val bytes = Base64.decode(entry.getString("c"), Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, requireNotNull(key(false)),
            GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        cipher.updateAAD(aad(file))
        val body = cipher.doFinal(bytes.copyOfRange(12, bytes.size))
        val json = JSONObject(String(body, Charsets.UTF_8))
        body.fill(0)
        val raw = Base64.decode(json.getString("k"), Base64.NO_WRAP)
        require(raw.size == 32)
        return raw to (if (json.isNull("w")) null else json.getString("w"))
    }
    private fun reply(raw: ByteArray, walletId: String?) = mapOf(
        "key" to Base64.encodeToString(raw, Base64.NO_WRAP),
        "walletId" to walletId, "version" to version)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val file: String
        try {
            file = entryName(requireNotNull(call.argument<String>("file")))
        } catch (_: Exception) {
            result.error("db_key_bad_request", "Invalid request", null); return
        }
        val stored = prefs.getString(file, null)
        try {
            when (call.method) {
                "load" -> {
                    if (stored == null) { result.success(null); return }
                    val (raw, walletId) = unwrap(file.removePrefix("wallet_db:"), stored)
                    result.success(reply(raw, walletId)); raw.fill(0)
                }
                "create" -> {
                    if (stored != null) {
                        result.error("db_key_exists", "Key already exists", null); return
                    }
                    val raw = ByteArray(32).also { SecureRandom().nextBytes(it) }
                    val walletId = call.argument<String>("walletId")
                    check(prefs.edit().putString(file,
                        wrap(file.removePrefix("wallet_db:"), raw, walletId)).commit())
                    result.success(reply(raw, walletId)); raw.fill(0)
                }
                "bindWallet" -> {
                    val walletId = requireNotNull(call.argument<String>("walletId"))
                    val name = file.removePrefix("wallet_db:")
                    val (raw, current) = unwrap(name, requireNotNull(stored))
                    if (current != null && current != walletId) {
                        raw.fill(0); result.error("db_key_wallet_mismatch", "Wallet mismatch", null); return
                    }
                    if (current == null) check(prefs.edit().putString(file, wrap(name, raw, walletId)).commit())
                    raw.fill(0); result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            // Entry exists but cannot be unwrapped (Keystore key lost/invalidated).
            result.error("db_key_unavailable", "Database key unavailable", null)
        }
    }
}
