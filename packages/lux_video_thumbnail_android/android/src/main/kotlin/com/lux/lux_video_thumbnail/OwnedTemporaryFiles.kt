package com.lux.lux_video_thumbnail

import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import java.io.File
import java.io.IOException

/** Files may only become owned by being created here, never by accepting a path. */
internal class OwnedTemporaryFiles(
    cacheDirectory: File,
    private val isSymbolicLink: (File) -> Boolean = ::androidIsSymbolicLink,
) {
    enum class Kind(val directory: String, val prefix: String) {
        INPUT("inputs", "video_"),
        THUMBNAIL("thumbnails", "thumb_"),
    }

    private val root = File(cacheDirectory.canonicalFile, "lux_video_thumbnail")
    private val owned = mutableMapOf<String, Kind>()

    @Synchronized
    fun create(kind: Kind, suffix: String): File {
        if (count(kind) >= if (kind == Kind.INPUT) ThumbnailLimits.MAX_SESSIONS else 64) {
            throw ResourceLimit("Too many owned temporary files")
        }
        val directory = File(root, kind.directory)
        checkDirectory(root)
        checkDirectory(directory)
        val file = File.createTempFile(kind.prefix, suffix, directory)
        // Fail closed if a directory was redirected while creating the file.
        checkLocation(file, kind)
        owned[file.absolutePath] = kind
        return file
    }

    @Synchronized
    fun delete(path: String, kind: Kind) {
        if (owned[path] != kind) {
            throw SecurityException("File is not an owned ${kind.directory} temporary")
        }
        val file = File(path)
        checkLocation(file, kind)
        if (file.exists()) {
            if (!file.isFile) throw SecurityException("Temporary file was replaced by a directory")
            if (!file.delete()) throw IOException("Could not delete owned temporary file")
        }
        owned.remove(path)
    }

    @Synchronized
    fun count(kind: Kind): Int = owned.values.count { it == kind }

    @Synchronized
    fun requireThumbnail(path: String): File {
        if (owned[path] != Kind.THUMBNAIL) throw SecurityException("Not an owned thumbnail")
        return File(path).also { checkLocation(it, Kind.THUMBNAIL) }
    }

    /** Best effort over registered paths only; never scan or recursively delete cacheDir. */
    @Synchronized
    fun deleteAll() {
        owned.toMap().forEach { (path, kind) ->
            try { delete(path, kind) } catch (_: Exception) { /* Fail closed on redirected paths. */ }
        }
    }

    private fun checkDirectory(directory: File) {
        if (isSymbolicLink(directory) || directory.canonicalFile != directory.absoluteFile) {
            throw SecurityException("Temporary directory must not contain symbolic links")
        }
        if (!directory.isDirectory && !directory.mkdirs()) {
            throw IOException("Could not create temporary directory")
        }
        if (isSymbolicLink(directory) || directory.canonicalFile != directory.absoluteFile) {
            throw SecurityException("Temporary directory was redirected")
        }
    }

    private fun checkLocation(file: File, kind: Kind) {
        val directory = File(root, kind.directory)
        if (file.parentFile != directory ||
            isSymbolicLink(root) || isSymbolicLink(directory) || isSymbolicLink(file) ||
            root.canonicalFile != root.absoluteFile ||
            directory.canonicalFile != directory.absoluteFile ||
            file.canonicalFile != file.absoluteFile
        ) {
            throw SecurityException("Temporary path was redirected or is outside its directory")
        }
    }
}

// lstat does not follow the final link and is available from Android API 21.
// java.nio.file.Files is unavailable on the plugin's minimum API level (24).
private fun androidIsSymbolicLink(file: File): Boolean = try {
    OsConstants.S_ISLNK(Os.lstat(file.absolutePath).st_mode)
} catch (error: ErrnoException) {
    if (error.errno == OsConstants.ENOENT) false
    else throw IOException("Could not inspect temporary path", error)
}
