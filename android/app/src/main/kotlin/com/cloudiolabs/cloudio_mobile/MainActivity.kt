package com.cloudiolabs.cloudio_mobile

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

class MainActivity: AudioServiceActivity() {
    private val decoder = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.cloudiolabs.cloudio/tiktok_audio_cache")
            .setMethodCallHandler { call, result ->
                decoder.execute {
                    try {
                        val value = handleTikTokCache(call)
                        runOnUiThread { if (!isDestroyed) result.success(value) }
                    } catch (_: Exception) {
                        runOnUiThread { if (!isDestroyed) result.error("audio_cache_failed", "Audio TikTok belum dapat disiapkan", null) }
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.cloudiolabs.cloudio/audio_sample")
            .setMethodCallHandler { call, result ->
                if (call.method != "decode") { result.notImplemented(); return@setMethodCallHandler }
                val media = call.argument<ByteArray>("bytes")
                if (media == null || media.size > 12 * 1024 * 1024) {
                    result.error("invalid_audio", "Audio tidak valid", null)
                    return@setMethodCallHandler
                }
                decoder.execute {
                    try {
                        val sample = decodeSample(media)
                        runOnUiThread { if (!isDestroyed) result.success(sample) }
                    } catch (_: Exception) {
                        runOnUiThread { if (!isDestroyed) result.error("decode_failed", "Audio tidak dapat dibaca", null) }
                    }
                }
            }
    }

    private fun handleTikTokCache(call: MethodCall): Any? {
        val directory = File(cacheDir, "cloudio-tiktok-audio-v1").apply { mkdirs() }
        directory.listFiles()?.filter {
            (it.name.startsWith("download-") || it.name.startsWith("export-")) &&
                it.lastModified() < System.currentTimeMillis() - 600_000L
        }?.forEach { it.delete() }
        if (call.method == "directory") return directory.absolutePath
        val id = call.argument<String>("id") ?: error("Missing cache id")
        require(id.matches(Regex("^[0-9]+$")))
        val cached = listOf("m4a", "mp3").map { File(directory, "sound-$id.$it") }
            .firstOrNull { it.isFile && it.length() > 0 }
        if (call.method == "lookup") {
            cached?.setLastModified(System.currentTimeMillis())
            return cached?.absolutePath
        }
        if (call.method == "remove") {
            listOf("m4a", "mp3").forEach { File(directory, "sound-$id.$it").delete() }
            return null
        }
        if (call.method == "info") {
            if (cached == null) return null
            val reader = MediaExtractor()
            try {
                reader.setDataSource(cached.absolutePath)
                var audio = 0; var video = 0; var duration = 0L
                for (index in 0 until reader.trackCount) {
                    val format = reader.getTrackFormat(index)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                    if (mime.startsWith("audio/")) audio++
                    if (mime.startsWith("video/")) video++
                    if (format.containsKey(MediaFormat.KEY_DURATION)) duration = maxOf(duration, format.getLong(MediaFormat.KEY_DURATION) / 1000)
                }
                return mapOf("path" to cached.absolutePath, "bytes" to cached.length(),
                    "audioTracks" to audio, "videoTracks" to video, "durationMs" to duration)
            } finally { reader.release() }
        }
        require(call.method == "extract")
        if (cached != null) return cached.absolutePath
        val input = File(call.argument<String>("inputPath") ?: error("Missing media"))
        require(input.canonicalFile.parentFile == directory.canonicalFile &&
            input.name.startsWith("download-") && input.length() in 1..(64L * 1024 * 1024))
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        var started = false
        var partial: File? = null
        try {
            extractor.setDataSource(input.absolutePath)
            require(input.length() <= 32L * 1024 * 1024 || (0 until extractor.trackCount).none {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
            })
            val audio = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: error("No audio")
            val format = extractor.getTrackFormat(audio)
            val mime = format.getString(MediaFormat.KEY_MIME)
            if (mime == "audio/mpeg") {
                require((0 until extractor.trackCount).none {
                    extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
                })
                val output = File(directory, "sound-$id.mp3")
                partial = File.createTempFile("export-$id-", ".mp3", directory)
                input.copyTo(partial, overwrite = true)
                check(partial.renameTo(output))
                trimTikTokCache(directory, output)
                return output.absolutePath
            }
            require(mime == "audio/mp4a-latm")
            extractor.selectTrack(audio)
            partial = File.createTempFile("export-$id-", ".m4a", directory)
            val writer = MediaMuxer(partial.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = writer
            val outputTrack = writer.addTrack(format)
            writer.start(); started = true
            val capacity = if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE))
                format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE).coerceAtLeast(256 * 1024) else 256 * 1024
            require(capacity <= 2 * 1024 * 1024)
            val buffer = ByteBuffer.allocate(capacity)
            val info = MediaCodec.BufferInfo()
            val deadline = System.nanoTime() + 15_000_000_000L
            var samples = 0
            var firstTime = -1L
            while (extractor.sampleTime >= 0) {
                check(System.nanoTime() < deadline && !Thread.currentThread().isInterrupted)
                buffer.clear()
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                require(size <= capacity && extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_ENCRYPTED == 0)
                if (firstTime < 0) firstTime = extractor.sampleTime
                val flags = if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                info.set(0, size, extractor.sampleTime - firstTime, flags)
                writer.writeSampleData(outputTrack, buffer, info)
                samples++
                extractor.advance()
            }
            check(samples > 0)
            writer.stop(); started = false
            writer.release(); muxer = null
            val output = File(directory, "sound-$id.m4a")
            check(partial.renameTo(output))
            trimTikTokCache(directory, output)
            return output.absolutePath
        } finally {
            if (started) try { muxer?.stop() } catch (_: Exception) { }
            muxer?.release()
            extractor.release()
            partial?.delete()
        }
    }

    private fun trimTikTokCache(directory: File, keeping: File) {
        val files = (directory.listFiles() ?: emptyArray()).filter {
            it.name.startsWith("sound-") && it != keeping
        }.sortedBy { it.lastModified() }
        var total = keeping.length() + files.sumOf { it.length() }
        var count = files.size + 1
        for (file in files) {
            if (count <= 32 && total <= 128L * 1024 * 1024) break
            val size = file.length()
            if (file.delete()) { total -= size; count-- }
        }
    }

    private fun decodeSample(media: ByteArray): Map<String, Any> {
        val file = File.createTempFile("cloudio-sample-", ".media", cacheDir)
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            file.writeBytes(media)
            extractor.setDataSource(file.absolutePath)
            val index = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: error("No audio track")
            extractor.selectTrack(index)
            val format = extractor.getTrackFormat(index)
            var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            format.setInteger("pcm-encoding", AudioFormat.ENCODING_PCM_16BIT)
            val activeCodec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec = activeCodec
            activeCodec.configure(format, null, null, 0)
            activeCodec.start()
            val output = ByteArrayOutputStream()
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var done = false
            var encoding = AudioFormat.ENCODING_PCM_16BIT
            val started = System.nanoTime()
            while (!done && !Thread.currentThread().isInterrupted && System.nanoTime() - started < 15_000_000_000L) {
                if (!inputDone) {
                    val slot = activeCodec.dequeueInputBuffer(10000)
                    if (slot >= 0) {
                        val buffer = activeCodec.getInputBuffer(slot)!!
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0 || extractor.sampleTime > 13_000_000) {
                            activeCodec.queueInputBuffer(slot, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            activeCodec.queueInputBuffer(slot, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val slot = activeCodec.dequeueOutputBuffer(info, 10000)
                if (slot == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val actual = activeCodec.outputFormat
                    rate = actual.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = actual.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    if (actual.containsKey("pcm-encoding")) encoding = actual.getInteger("pcm-encoding")
                    require(rate in 8000..192000 && channels in 1..8)
                } else if (slot >= 0) {
                    val buffer = activeCodec.getOutputBuffer(slot)!!
                    buffer.position(info.offset)
                    buffer.limit(info.offset + info.size)
                    val chunk = ByteArray(info.size)
                    buffer.get(chunk)
                    val pcm = if (encoding == AudioFormat.ENCODING_PCM_FLOAT) {
                        val floats = ByteBuffer.wrap(chunk).order(ByteOrder.LITTLE_ENDIAN)
                        val shorts = ByteBuffer.allocate(chunk.size / 2).order(ByteOrder.LITTLE_ENDIAN)
                        while (floats.remaining() >= 4) shorts.putShort((floats.float.coerceIn(-1f, 1f) * 32767).toInt().toShort())
                        shorts.array()
                    } else {
                        require(encoding == AudioFormat.ENCODING_PCM_16BIT)
                        chunk
                    }
                    val limit = minOf(rate * channels * 2 * 12, 8 * 1024 * 1024)
                    val size = minOf(pcm.size, limit - output.size())
                    if (size > 0) output.write(pcm, 0, size)
                    done = output.size() >= limit || info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    activeCodec.releaseOutputBuffer(slot, false)
                }
            }
            val pcm = output.toByteArray()
            require(pcm.isNotEmpty())
            return mapOf("pcm" to pcm, "sampleRate" to rate, "channels" to channels)
        } finally {
            try { codec?.stop() } catch (_: Exception) { }
            codec?.release()
            extractor.release()
            file.delete()
        }
    }

    override fun onDestroy() {
        decoder.shutdownNow()
        super.onDestroy()
    }
}
