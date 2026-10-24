package tw.toast.image_compressor

import android.app.Activity
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.ext.SdkExtensions
import android.provider.MediaStore
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Android file access for the Flutter side (channel "imgc/files").
 *
 * The Rust core works on plain paths, so picked / shared images are copied into
 * cacheDir/imgc/import, outputs are written to cacheDir/imgc/export by Rust and then
 * copied into the user's folder through the Storage Access Framework.
 */
class FilesChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "imgc/files")
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val resolver: ContentResolver get() = activity.contentResolver
    private val root = File(activity.cacheDir, "imgc")
    private var importSeq = 0
    private var pending: MethodChannel.Result? = null
    private var pendingShared: List<Map<String, Any?>>? = null

    init {
        channel.setMethodCallHandler(this)
        // Leftovers from the previous session
        root.deleteRecursively()
        root.mkdirs()
    }

    companion object {
        private const val REQ_IMAGES = 0x4D01
        private const val REQ_TREE = 0x4D02
        val IMAGE_EXTS = setOf(
            "jpg", "jpeg", "png", "webp", "bmp", "tif", "tiff", "gif", "heic", "heif", "hif"
        )

        fun isImageName(name: String): Boolean =
            IMAGE_EXTS.contains(name.substringAfterLast('.', "").lowercase())
    }

    // ---------- plumbing ----------

    private fun <T> background(result: MethodChannel.Result, work: () -> T) {
        io.execute {
            try {
                val v = work()
                main.post { result.success(v) }
            } catch (e: Exception) {
                main.post { result.error("io", e.message ?: e.toString(), null) }
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "cacheDir" -> result.success(root.absolutePath)
            "pickImages" -> startPick(
                result,
                REQ_IMAGES,
                if (call.argument<Boolean>("gallery") == true) galleryIntent() else Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "image/*"
                    putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                }
            )
            "pickFolder" -> startPick(result, REQ_TREE, Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                )
            })
            "importTree" -> {
                val tree = Uri.parse(call.argument<String>("tree")!!)
                val recursive = call.argument<Boolean>("recursive") ?: false
                background(result) { importTree(tree, recursive) }
            }
            "treeName" -> {
                val tree = Uri.parse(call.argument<String>("tree")!!)
                background(result) { if (hasPermission(tree)) treeName(tree) else null }
            }
            "moveToOld" -> {
                val tree = Uri.parse(call.argument<String>("tree")!!)
                val dir = call.argument<String>("dir") ?: ""
                val regex = Regex(call.argument<String>("regex")!!)
                background(result) { moveToOld(tree, dir, regex) }
            }
            "writeFile" -> {
                val tree = Uri.parse(call.argument<String>("tree")!!)
                val rel = call.argument<String>("relPath")!!
                val src = File(call.argument<String>("src")!!)
                val backup = call.argument<Boolean>("backup") ?: false
                background(result) { writeFile(tree, rel, src, backup) }
            }
            "openTree" -> {
                val tree = Uri.parse(call.argument<String>("tree")!!)
                val dir = call.argument<String>("dir") ?: ""
                io.execute {
                    val uri = try {
                        val id = dirId(tree, dir, false) ?: DocumentsContract.getTreeDocumentId(tree)
                        docUri(tree, id)
                    } catch (_: Exception) {
                        null
                    }
                    main.post { result.success(uri != null && openDir(uri)) }
                }
            }
            "galleryAvailable" -> result.success(Build.VERSION.SDK_INT >= 29)
            "saveToGallery" -> {
                val src = File(call.argument<String>("src")!!)
                val album = call.argument<String>("album") ?: "Image Compressor"
                background(result) { saveToGallery(src, album) }
            }
            "openGallery" -> result.success(openGallery())
            "takeShared" -> {
                result.success(pendingShared)
                pendingShared = null
            }
            else -> result.notImplemented()
        }
    }

    /** System photo picker (Android 13+, or 11+ with the SDK extension); otherwise a gallery app. */
    private fun galleryIntent(): Intent {
        val hasPicker = Build.VERSION.SDK_INT >= 33 ||
            (Build.VERSION.SDK_INT >= 30 && SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) >= 2)
        if (hasPicker) {
            return Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                type = "image/*"
                putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, MediaStore.getPickImagesMaxLimit())
            }
        }
        return Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "image/*"
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
    }

    private fun startPick(result: MethodChannel.Result, code: Int, intent: Intent) {
        pending?.error("cancelled", "superseded", null)
        pending = result
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, code)
        } catch (e: Exception) {
            pending = null
            result.error("no_picker", e.message, null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_IMAGES && requestCode != REQ_TREE) return false
        val result = pending ?: return true
        pending = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(null)
            return true
        }
        when (requestCode) {
            REQ_IMAGES -> {
                val uris = mutableListOf<Uri>()
                data.clipData?.let { c -> for (i in 0 until c.itemCount) uris.add(c.getItemAt(i).uri) }
                if (uris.isEmpty()) data.data?.let { uris.add(it) }
                background(result) { importUris(uris) }
            }
            REQ_TREE -> {
                val tree = data.data
                if (tree == null) {
                    result.success(null)
                } else {
                    try {
                        resolver.takePersistableUriPermission(
                            tree,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                        )
                    } catch (_: SecurityException) {
                    }
                    background(result) { mapOf("uri" to tree.toString(), "name" to treeName(tree)) }
                }
            }
        }
        return true
    }

    // ---------- share intents ----------

    fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val uris: List<Uri> = when (intent.action) {
            Intent.ACTION_SEND -> listOfNotNull(streamExtra(intent))
            Intent.ACTION_SEND_MULTIPLE -> streamListExtra(intent)
            else -> return
        }
        if (uris.isEmpty()) return
        // Consume so a configuration change doesn't import twice
        intent.action = Intent.ACTION_MAIN
        io.execute {
            val files = try {
                importUris(uris)
            } catch (_: Exception) {
                emptyList()
            }
            main.post {
                if (files.isEmpty()) return@post
                // Dart polls takeShared on start; if it is already running, push the files.
                pendingShared = (pendingShared ?: emptyList()) + files
                channel.invokeMethod("shared", null)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(i: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else i.getParcelableExtra(Intent.EXTRA_STREAM)

    @Suppress("DEPRECATION")
    private fun streamListExtra(i: Intent): List<Uri> =
        (if (Build.VERSION.SDK_INT >= 33) i.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else i.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)) ?: emptyList()

    // ---------- import ----------

    private fun newImportDir(): File {
        val d = File(root, "import/${System.currentTimeMillis()}_${importSeq++}")
        d.mkdirs()
        return d
    }

    private fun displayName(uri: Uri): String {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst() && !c.isNull(0)) return c.getString(0)
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "image"
    }

    private fun safeName(name: String): String =
        name.replace(Regex("[\\\\/:*?\"<>|\\u0000]"), "_").ifBlank { "image" }

    private fun copyIn(uri: Uri, dst: File) {
        dst.parentFile?.mkdirs()
        resolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "cannot open $uri" }
            dst.outputStream().use { input.copyTo(it, 1 shl 16) }
        }
    }

    /** Single files (picker / share): copied to a fresh folder, keeping their names. */
    private fun importUris(uris: List<Uri>): List<Map<String, Any?>> {
        val dir = newImportDir()
        val used = mutableSetOf<String>()
        val out = mutableListOf<Map<String, Any?>>()
        for (u in uris) {
            var name = safeName(displayName(u))
            if (!name.contains('.')) {
                val ext = when (resolver.getType(u)) {
                    "image/jpeg" -> "jpg"; "image/png" -> "png"; "image/webp" -> "webp"
                    "image/heic", "image/heif" -> "heic"; "image/gif" -> "gif"; else -> null
                }
                if (ext != null) name = "$name.$ext"
            }
            if (!isImageName(name)) continue
            // Same name twice (e.g. two IMG_0001.HEIC): add a counter
            var unique = name
            var n = 1
            while (!used.add(unique.lowercase())) {
                unique = "${name.substringBeforeLast('.')} ($n).${name.substringAfterLast('.')}"
                n++
            }
            val f = File(dir, unique)
            try {
                copyIn(u, f)
                out.add(mapOf("path" to f.absolutePath, "name" to unique))
            } catch (_: Exception) {
            }
        }
        return out
    }

    private data class Child(val id: String, val name: String, val mime: String?)

    private fun children(tree: Uri, docId: String): List<Child> {
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, docId)
        val cols = arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE)
        val out = mutableListOf<Child>()
        resolver.query(uri, cols, null, null, null)?.use { c ->
            while (c.moveToNext()) out.add(Child(c.getString(0), c.getString(1) ?: "", c.getString(2)))
        }
        return out
    }

    private fun isDir(c: Child) = c.mime == Document.MIME_TYPE_DIR

    private fun hasPermission(tree: Uri): Boolean =
        resolver.persistedUriPermissions.any { it.uri == tree && it.isReadPermission }

    private fun treeName(tree: Uri): String {
        val doc = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        return try {
            displayName(doc)
        } catch (_: Exception) {
            DocumentsContract.getTreeDocumentId(tree).substringAfterLast(':').substringAfterLast('/')
        }
    }

    /**
     * Copies the images of a picked folder into the cache, mirroring sub folders.
     * Returns base (local mirror root), name and files [{path, name, relDir}].
     */
    private fun importTree(tree: Uri, recursive: Boolean): Map<String, Any?> {
        val base = newImportDir()
        val files = mutableListOf<Map<String, Any?>>()
        fun walk(docId: String, rel: String) {
            val kids = children(tree, docId).sortedBy { it.name.lowercase() }
            for (k in kids) {
                if (isDir(k)) {
                    if (recursive && k.name != "_old") walk(k.id, if (rel.isEmpty()) k.name else "$rel/${k.name}")
                } else if (isImageName(k.name)) {
                    val dst = File(base, if (rel.isEmpty()) k.name else "$rel/${k.name}")
                    try {
                        copyIn(DocumentsContract.buildDocumentUriUsingTree(tree, k.id), dst)
                        files.add(mapOf("path" to dst.absolutePath, "name" to k.name, "relDir" to rel))
                    } catch (_: Exception) {
                    }
                }
            }
        }
        walk(DocumentsContract.getTreeDocumentId(tree), "")
        return mapOf("base" to base.absolutePath, "name" to treeName(tree), "files" to files)
    }

    // ---------- export ----------

    /** Finds (and optionally creates) the folder at relDir ("a/b") under the tree root. */
    private fun dirId(tree: Uri, relDir: String, create: Boolean): String? {
        var id = DocumentsContract.getTreeDocumentId(tree)
        for (seg in relDir.split('/').filter { it.isNotEmpty() }) {
            val found = children(tree, id).firstOrNull { isDir(it) && it.name == seg }
            id = when {
                found != null -> found.id
                create -> {
                    val parent = DocumentsContract.buildDocumentUriUsingTree(tree, id)
                    val made = DocumentsContract.createDocument(resolver, parent, Document.MIME_TYPE_DIR, seg)
                        ?: throw IllegalStateException("cannot create folder $seg")
                    DocumentsContract.getDocumentId(made)
                }
                else -> return null
            }
        }
        return id
    }

    private fun docUri(tree: Uri, id: String) = DocumentsContract.buildDocumentUriUsingTree(tree, id)

    /** Moves one document into <dir>/_old (copy + delete when the provider can't move). */
    private fun moveOne(tree: Uri, dirIdValue: String, child: Child) {
        val oldId = children(tree, dirIdValue).firstOrNull { isDir(it) && it.name == "_old" }?.id
            ?: DocumentsContract.getDocumentId(
                DocumentsContract.createDocument(resolver, docUri(tree, dirIdValue), Document.MIME_TYPE_DIR, "_old")
                    ?: throw IllegalStateException("cannot create _old")
            )
        val src = docUri(tree, child.id)
        val taken = children(tree, oldId).map { it.name.lowercase() }.toSet()
        var target = child.name
        var n = 1
        while (taken.contains(target.lowercase())) {
            target = "${child.name.substringBeforeLast('.')} ($n).${child.name.substringAfterLast('.')}"
            n++
        }
        if (target == child.name && Build.VERSION.SDK_INT >= 24) {
            try {
                if (DocumentsContract.moveDocument(resolver, src, docUri(tree, dirIdValue), docUri(tree, oldId)) != null) return
            } catch (_: Exception) {
            }
        }
        val dst = DocumentsContract.createDocument(resolver, docUri(tree, oldId), child.mime ?: "image/jpeg", target)
            ?: throw IllegalStateException("cannot create $target")
        resolver.openInputStream(src).use { i ->
            resolver.openOutputStream(dst, "w").use { o -> requireNotNull(i).copyTo(requireNotNull(o)) }
        }
        DocumentsContract.deleteDocument(resolver, src)
    }

    /** Moves files in relDir whose names match [regex] into relDir/_old. Returns the count. */
    private fun moveToOld(tree: Uri, relDir: String, regex: Regex): Int {
        val id = dirId(tree, relDir, false) ?: return 0
        val victims = children(tree, id).filter { !isDir(it) && regex.matches(it.name) }
        for (v in victims) moveOne(tree, id, v)
        return victims.size
    }

    private fun mimeOf(name: String) = when (name.substringAfterLast('.').lowercase()) {
        "jpg", "jpeg" -> "image/jpeg"
        "png" -> "image/png"
        "webp" -> "image/webp"
        else -> "application/octet-stream"
    }

    /** Writes [src] to relPath under the tree. backup = move an existing file to _old first. */
    private fun writeFile(tree: Uri, relPath: String, src: File, backup: Boolean): String {
        val relDir = relPath.substringBeforeLast('/', "")
        val name = relPath.substringAfterLast('/')
        val dir = dirId(tree, relDir, true)!!
        val existing = children(tree, dir).firstOrNull { !isDir(it) && it.name == name }
        val target: Uri = if (existing != null && !backup) {
            docUri(tree, existing.id)
        } else {
            if (existing != null) moveOne(tree, dir, existing)
            DocumentsContract.createDocument(resolver, docUri(tree, dir), mimeOf(name), name)
                ?: throw IllegalStateException("cannot create $name")
        }
        // "wt" truncates; some providers only accept "w"
        val out = try {
            resolver.openOutputStream(target, "wt")
        } catch (_: Exception) {
            resolver.openOutputStream(target, "w")
        }
        out.use { o -> src.inputStream().use { it.copyTo(requireNotNull(o), 1 shl 16) } }
        return target.toString()
    }

    // ---------- gallery ----------

    /** Inserts [src] into MediaStore under Pictures/<album> (Android 10+, no permission needed). */
    private fun saveToGallery(src: File, album: String): String {
        if (Build.VERSION.SDK_INT < 29) throw IllegalStateException("requires Android 10")
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, src.name)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeOf(src.name))
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/$album")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore insert failed")
        try {
            resolver.openOutputStream(uri, "w").use { o ->
                src.inputStream().use { it.copyTo(requireNotNull(o), 1 shl 16) }
            }
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        return uri.toString()
    }

    private fun openGallery(): Boolean = try {
        activity.startActivity(Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_GALLERY))
        true
    } catch (_: Exception) {
        false
    }

    private fun openDir(uri: Uri): Boolean {
        for (type in listOf(Document.MIME_TYPE_DIR, "resource/folder")) {
            val i = Intent(Intent.ACTION_VIEW).setDataAndType(uri, type)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            try {
                activity.startActivity(i)
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }
}
