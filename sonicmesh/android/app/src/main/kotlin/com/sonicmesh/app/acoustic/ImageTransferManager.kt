package com.sonicmesh.app.acoustic

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.roundToInt
import kotlin.random.Random

class ImageTransferManager(
    private val context: Context,
    private val onEvent: (Map<String, Any?>) -> Unit
) {
    data class PreparedImage(
        val imageId: Int,
        val width: Int,
        val height: Int,
        val fileSize: Int,
        val webpBytes: ByteArray,
        val chunks: List<ByteArray>,
        val totalChunks: Int,
        val estimatedDurationSec: Int,
        val imageCrc32: Int
    )

    // Active session for incoming images
    class ImageSession(
        val imageId: Int,
        val width: Int,
        val height: Int,
        val fileSize: Int,
        val format: Byte,
        val totalChunks: Int,
        val chunkSize: Int,
        val receivedChunks: ConcurrentHashMap<Int, ByteArray> = ConcurrentHashMap(),
        var expectedCrc32: Int? = null,
        var lastUpdatedMs: Long = System.currentTimeMillis()
    )

    private val activeSessions = ConcurrentHashMap<Int, ImageSession>()
    private var lastPreparedImage: PreparedImage? = null

    fun prepareImageFromBytes(
        rawBytes: ByteArray,
        targetWidth: Int = 64,
        targetHeight: Int = 64,
        quality: Int = 45,
        chunkSize: Int = 48
    ): PreparedImage? {
        try {
            val originalBitmap = BitmapFactory.decodeByteArray(rawBytes, 0, rawBytes.size) ?: return null
            return processBitmap(originalBitmap, targetWidth, targetHeight, quality, chunkSize)
        } catch (e: Exception) {
            return null
        }
    }

    fun prepareImageFromUri(
        uri: Uri,
        isThumbnail: Boolean = true,
        chunkSize: Int = 48
    ): PreparedImage? {
        try {
            val inputStream = context.contentResolver.openInputStream(uri) ?: return null
            val originalBitmap = BitmapFactory.decodeStream(inputStream) ?: return null
            inputStream.close()

            val targetSize = if (isThumbnail) 64 else 128
            val quality = if (isThumbnail) 40 else 50
            return processBitmap(originalBitmap, targetSize, targetSize, quality, chunkSize)
        } catch (e: Exception) {
            return null
        }
    }

    private fun processBitmap(
        original: Bitmap,
        targetWidth: Int,
        targetHeight: Int,
        quality: Int,
        chunkSize: Int
    ): PreparedImage {
        // Calculate aspect ratio preserving scaled dimensions
        val originalWidth = original.width
        val originalHeight = original.height
        val ratio = originalWidth.toFloat() / originalHeight.toFloat()

        val finalWidth: Int
        val finalHeight: Int
        if (ratio > 1) {
            finalWidth = targetWidth
            finalHeight = (targetWidth / ratio).roundToInt().coerceAtLeast(16)
        } else {
            finalHeight = targetHeight
            finalWidth = (targetHeight * ratio).roundToInt().coerceAtLeast(16)
        }

        val scaledBitmap = Bitmap.createScaledBitmap(original, finalWidth, finalHeight, true)

        val stream = ByteArrayOutputStream()
        @Suppress("DEPRECATION")
        scaledBitmap.compress(Bitmap.CompressFormat.WEBP, quality, stream)
        val webpBytes = stream.toByteArray()

        val imageId = Random.nextInt(10000, 99999)
        val crc = Crc32.compute(webpBytes).toInt()

        // Fragment into chunks
        val chunks = mutableListOf<ByteArray>()
        var offset = 0
        while (offset < webpBytes.size) {
            val end = (offset + chunkSize).coerceAtMost(webpBytes.size)
            chunks.add(webpBytes.copyOfRange(offset, end))
            offset = end
        }

        val totalChunks = chunks.size
        // 25 baud FSK: ~40ms per bit -> ~320ms per byte. Frame overhead: ~15 bytes -> ~5s per chunk
        // With inter-frame spacing (~300ms): ~3.5s per chunk average
        val estimatedSec = (totalChunks * 3.5 + 4).roundToInt()

        val prepared = PreparedImage(
            imageId = imageId,
            width = finalWidth,
            height = finalHeight,
            fileSize = webpBytes.size,
            webpBytes = webpBytes,
            chunks = chunks,
            totalChunks = totalChunks,
            estimatedDurationSec = estimatedSec,
            imageCrc32 = crc
        )
        lastPreparedImage = prepared
        return prepared
    }

    fun getLastPreparedImage(): PreparedImage? = lastPreparedImage

    fun handleImageStart(data: AcousticPacket.ImageStartData) {
        val session = ImageSession(
            imageId = data.imageId,
            width = data.width.toInt(),
            height = data.height.toInt(),
            fileSize = data.fileSize,
            format = data.format,
            totalChunks = data.totalChunks.toInt(),
            chunkSize = data.chunkSize.toInt()
        )
        activeSessions[data.imageId] = session
        onEvent(mapOf(
            "type" to "IMAGE_RX_START",
            "imageId" to data.imageId,
            "width" to data.width.toInt(),
            "height" to data.height.toInt(),
            "fileSize" to data.fileSize,
            "totalChunks" to data.totalChunks.toInt()
        ))
    }

    fun handleImageChunk(data: AcousticPacket.ImageChunkData) {
        var session = activeSessions[data.imageId]
        if (session == null) {
            // Unannounced chunk, create fallback session
            session = ImageSession(
                imageId = data.imageId,
                width = 64,
                height = 64,
                fileSize = 0,
                format = AcousticPacket.FORMAT_WEBP,
                totalChunks = data.totalChunks.toInt(),
                chunkSize = data.chunkData.size
            )
            activeSessions[data.imageId] = session
        }

        session.receivedChunks[data.chunkIndex.toInt()] = data.chunkData
        session.lastUpdatedMs = System.currentTimeMillis()

        val receivedCount = session.receivedChunks.size
        val progress = receivedCount.toFloat() / session.totalChunks.toFloat()

        onEvent(mapOf(
            "type" to "IMAGE_RX_PROGRESS",
            "imageId" to data.imageId,
            "chunkIndex" to data.chunkIndex.toInt(),
            "receivedChunks" to receivedCount,
            "totalChunks" to session.totalChunks,
            "progress" to progress
        ))

        checkAndReassembleIfComplete(session)
    }

    fun handleImageEnd(data: AcousticPacket.ImageEndData) {
        val session = activeSessions[data.imageId] ?: return
        session.expectedCrc32 = data.imageCrc32
        checkAndReassembleIfComplete(session)
    }

    private fun checkAndReassembleIfComplete(session: ImageSession) {
        if (session.receivedChunks.size >= session.totalChunks) {
            // Reassemble in sequence
            val totalBytes = session.receivedChunks.values.sumOf { it.size }
            val reassembled = ByteArray(totalBytes)
            var destPos = 0
            for (i in 1..session.totalChunks) {
                val chunk = session.receivedChunks[i] ?: ByteArray(0)
                System.arraycopy(chunk, 0, reassembled, destPos, chunk.size)
                destPos += chunk.size
            }

            // Verify CRC32 if provided
            val computedCrc = Crc32.compute(reassembled).toInt()
            val expected = session.expectedCrc32
            val crcMatches = (expected == null || expected == computedCrc)

            // Save to internal storage
            val imagesDir = File(context.filesDir, "sonic_images").apply { mkdirs() }
            val file = File(imagesDir, "img_${session.imageId}.webp")
            try {
                FileOutputStream(file).use { it.write(reassembled) }
            } catch (_: Exception) {}

            onEvent(mapOf(
                "type" to "IMAGE_RECEIVED",
                "imageId" to session.imageId,
                "filePath" to file.absolutePath,
                "fileSize" to reassembled.size,
                "width" to session.width,
                "height" to session.height,
                "crcValid" to crcMatches,
                "totalChunks" to session.totalChunks,
                "rawBytes" to reassembled
            ))

            activeSessions.remove(session.imageId)
        }
    }

    fun getMissingChunks(imageId: Int): List<Int> {
        val session = activeSessions[imageId] ?: return emptyList()
        return (1..session.totalChunks).filter { !session.receivedChunks.containsKey(it) }
    }
}
