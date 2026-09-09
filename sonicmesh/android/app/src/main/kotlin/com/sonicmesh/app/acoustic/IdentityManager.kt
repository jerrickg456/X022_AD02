package com.sonicmesh.app.acoustic

import android.content.Context
import java.security.MessageDigest
import kotlin.random.Random

data class SonicIdentity(
    val deviceId: Int,
    val deviceIdHex: String,
    val deviceName: String,
    val publicKeyFingerprint: String,
    val fingerprintInt: Int
)

class IdentityManager(private val context: Context? = null) {

    val identity: SonicIdentity by lazy {
        loadOrCreateIdentity()
    }

    private fun loadOrCreateIdentity(): SonicIdentity {
        val prefs = context?.getSharedPreferences("sonicmesh_identity", Context.MODE_PRIVATE)

        val id = if (prefs != null && prefs.contains("device_id")) {
            prefs.getInt("device_id", 0)
        } else {
            val newId = (Random.nextInt() and 0x7FFFFFFF) or 0x10000000
            prefs?.edit()?.putInt("device_id", newId)?.apply()
            newId
        }

        val hex = String.format("%08X", id)
        val shortHex = hex.substring(0, 4) + "-" + hex.substring(4)

        val defaultName = "Sonic-" + hex.substring(0, 4)
        val name = prefs?.getString("device_name", defaultName) ?: defaultName
        if (prefs != null && !prefs.contains("device_name")) {
            prefs.edit().putString("device_name", defaultName).apply()
        }

        // Generate synthetic ECDSA public key fingerprint derived from deviceId
        val md = MessageDigest.getInstance("SHA-256")
        val hash = md.digest(hex.toByteArray(Charsets.UTF_8))
        val fingerprint = String.format("%02X%02X-%02X%02X", hash[0], hash[1], hash[2], hash[3])
        val fpInt = ((hash[0].toInt() and 0xFF) shl 24) or
                    ((hash[1].toInt() and 0xFF) shl 16) or
                    ((hash[2].toInt() and 0xFF) shl 8) or
                    (hash[3].toInt() and 0xFF)

        return SonicIdentity(
            deviceId = id,
            deviceIdHex = shortHex,
            deviceName = name,
            publicKeyFingerprint = fingerprint,
            fingerprintInt = fpInt
        )
    }

    fun toMap(): Map<String, Any> {
        return mapOf(
            "deviceId" to identity.deviceId,
            "deviceIdHex" to identity.deviceIdHex,
            "deviceName" to identity.deviceName,
            "fingerprint" to identity.publicKeyFingerprint
        )
    }
}
