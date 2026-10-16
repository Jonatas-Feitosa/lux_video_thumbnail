package com.lux.lux_video_thumbnail

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Assume.assumeNoException
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class OwnedTemporaryFilesTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun `only files created by this owner may be deleted`() {
        val cache = temporary.newFolder("cache")
        val owner = owner(cache)
        val original = temporary.newFile("original.mp4").apply { writeText("original") }
        val owned = owner.create(OwnedTemporaryFiles.Kind.INPUT, ".mp4")
        val unregistered = File(owned.parentFile, "unregistered.mp4").apply { writeText("keep") }

        assertThrows(SecurityException::class.java) {
            owner.delete(original.absolutePath, OwnedTemporaryFiles.Kind.INPUT)
        }
        assertThrows(SecurityException::class.java) {
            owner.delete(unregistered.absolutePath, OwnedTemporaryFiles.Kind.INPUT)
        }
        // Merely being in the right directory is insufficient, including after restart.
        assertThrows(SecurityException::class.java) {
            owner(cache).delete(owned.absolutePath, OwnedTemporaryFiles.Kind.INPUT)
        }
        owner.delete(owned.absolutePath, OwnedTemporaryFiles.Kind.INPUT)
        assertFalse(owned.exists())
        assertEquals("original", original.readText())
        assertEquals("keep", unregistered.readText())
    }

    @Test fun `thumbnail deletion cannot delete an owned video input`() {
        val owner = owner(temporary.newFolder("cache"))
        val input = owner.create(OwnedTemporaryFiles.Kind.INPUT, ".mp4")
        val thumbnail = owner.create(OwnedTemporaryFiles.Kind.THUMBNAIL, ".tmp")
        assertThrows(SecurityException::class.java) {
            owner.delete(input.absolutePath, OwnedTemporaryFiles.Kind.THUMBNAIL)
        }
        owner.delete(thumbnail.absolutePath, OwnedTemporaryFiles.Kind.THUMBNAIL)
        assertTrue(input.exists())
        assertFalse(thumbnail.exists())
    }

    @Test fun `traversal aliases are rejected even when they resolve to an owned file`() {
        val owner = owner(temporary.newFolder("cache"))
        val file = owner.create(OwnedTemporaryFiles.Kind.THUMBNAIL, ".tmp")
        val alias = File(file.parentFile, "../thumbnails/${file.name}")
        assertThrows(SecurityException::class.java) {
            owner.delete(alias.absolutePath, OwnedTemporaryFiles.Kind.THUMBNAIL)
        }
        assertTrue(file.exists())
    }

    @Test fun `a cache-evicted temporary can be disposed without touching other files`() {
        val owner = owner(temporary.newFolder("cache"))
        val file = owner.create(OwnedTemporaryFiles.Kind.THUMBNAIL, ".tmp")
        assertTrue(file.delete())
        owner.delete(file.absolutePath, OwnedTemporaryFiles.Kind.THUMBNAIL)
        assertFalse(file.exists())
    }

    @Test fun `a directory substituted for a temporary is never deleted`() {
        val owner = owner(temporary.newFolder("cache"))
        val file = owner.create(OwnedTemporaryFiles.Kind.THUMBNAIL, ".tmp")
        assertTrue(file.delete())
        assertTrue(file.mkdir())
        assertThrows(SecurityException::class.java) {
            owner.delete(file.absolutePath, OwnedTemporaryFiles.Kind.THUMBNAIL)
        }
        assertTrue(file.isDirectory)
    }

    @Test fun `owned file replaced with symbolic link does not delete its target`() {
        val owner = owner(temporary.newFolder("cache"))
        val original = temporary.newFile("original.mp4").apply { writeText("keep") }
        val file = owner.create(OwnedTemporaryFiles.Kind.THUMBNAIL, ".tmp")
        assertTrue(file.delete())
        symbolicLink(file, original)
        assertThrows(SecurityException::class.java) {
            owner.delete(file.absolutePath, OwnedTemporaryFiles.Kind.THUMBNAIL)
        }
        assertEquals("keep", original.readText())
        Files.delete(file.toPath())
    }

    @Test fun `redirected parent directory cannot delete another file with the same name`() {
        val owner = owner(temporary.newFolder("cache"))
        val file = owner.create(OwnedTemporaryFiles.Kind.THUMBNAIL, ".tmp")
        val directory = file.parentFile!!
        val originalDirectory = temporary.newFolder("originals")
        val original = File(originalDirectory, file.name).apply { writeText("keep") }
        assertTrue(file.delete())
        assertTrue(directory.delete())
        symbolicLink(directory, originalDirectory)
        assertThrows(SecurityException::class.java) {
            owner.delete(file.absolutePath, OwnedTemporaryFiles.Kind.THUMBNAIL)
        }
        assertThrows(SecurityException::class.java) {
            owner.create(OwnedTemporaryFiles.Kind.THUMBNAIL, ".tmp")
        }
        assertEquals("keep", original.readText())
        Files.delete(directory.toPath())
    }

    @Test fun `preexisting redirected cache root cannot acquire files`() {
        val cache = temporary.newFolder("cache")
        val originals = temporary.newFolder("originals")
        val link = File(cache, "lux_video_thumbnail")
        symbolicLink(link, originals)
        assertThrows(SecurityException::class.java) {
            owner(cache).create(OwnedTemporaryFiles.Kind.INPUT, ".mp4")
        }
        assertTrue(originals.listFiles()!!.isEmpty())
        Files.delete(link.toPath())
    }

    // Android uses lstat; the host JVM uses NIO to inspect the same real links.
    private fun owner(cache: File) = OwnedTemporaryFiles(cache) {
        Files.isSymbolicLink(it.toPath())
    }

    private fun symbolicLink(link: File, target: File) {
        try {
            Files.createSymbolicLink(link.toPath(), target.toPath())
        } catch (error: UnsupportedOperationException) {
            assumeNoException("Filesystem does not support symbolic links", error)
        } catch (error: java.nio.file.FileSystemException) {
            assumeNoException("Symbolic-link privilege is unavailable", error)
        }
    }
}
