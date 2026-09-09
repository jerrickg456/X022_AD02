package com.sonicmesh.app.acoustic

import java.util.zip.CRC32

object Crc32 {
    fun compute(data: ByteArray, offset: Int = 0, length: Int = data.size): Long {
        val crc = CRC32()
        crc.update(data, offset, length)
        return crc.value
    }

    fun verify(data: ByteArray, expectedCrc: Long, offset: Int = 0, length: Int = data.size): Boolean {
        return compute(data, offset, length) == expectedCrc
    }
}
