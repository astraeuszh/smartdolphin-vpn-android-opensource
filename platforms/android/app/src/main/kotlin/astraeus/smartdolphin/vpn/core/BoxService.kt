package com.smartdolphin.vpn.core

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import com.smartdolphin.libbox.CommandClient
import com.smartdolphin.libbox.CommandClientOptions
import com.smartdolphin.libbox.CommandClientHandler
import com.smartdolphin.libbox.CommandServer
import com.smartdolphin.libbox.CommandServerHandler
import com.smartdolphin.libbox.Connections
import com.smartdolphin.libbox.Connection
import com.smartdolphin.libbox.Libbox
import com.smartdolphin.libbox.LogEntry
import com.smartdolphin.libbox.LogIterator
import com.smartdolphin.libbox.NetworkInterface as LibboxInterface
import com.smartdolphin.libbox.NetworkInterfaceIterator
import com.smartdolphin.libbox.Notification as LibboxNotification
import com.smartdolphin.libbox.OutboundGroupIterator
import com.smartdolphin.libbox.OverrideOptions
import com.smartdolphin.libbox.PlatformInterface
import com.smartdolphin.libbox.SetupOptions
import com.smartdolphin.libbox.StatusMessage
import com.smartdolphin.libbox.StringIterator
import com.smartdolphin.libbox.SystemProxyStatus
import com.smartdolphin.libbox.TunOptions
import com.smartdolphin.libbox.WIFIState
import org.json.JSONObject

/// The entire VPN backend is Go (Dolphin-Core / libbox). This Kotlin class is
/// the unavoidable Android glue: a VpnService that builds the tun and hands its
/// fd to Go (openTun), protects the engine's sockets, and starts/stops the box.
class BoxService : VpnService(), PlatformInterface, CommandServerHandler {

    companion object {
        private const val TAG = "BoxService"
        const val ACTION_START = "com.smartdolphin.vpn.START"
        const val ACTION_STOP = "com.smartdolphin.vpn.STOP"
        const val ACTION_NETWORK_CHANGED = "com.smartdolphin.vpn.NETWORK_CHANGED"
        const val EXTRA_CONFIG = "config"
        private const val NOTIF_CHANNEL = "dolphin_vpn"
        private const val NOTIF_ID = 7301
        private const val ACCOUNT_NOTIF_CHANNEL = "account_messages"
        private const val ACCOUNT_NOTIF_BASE_ID = 20000

        @Volatile
        var instance: BoxService? = null

        private val REFRESH_DELAYS_MS = longArrayOf(300, 1000, 3000)
    }

    private var commandServer: CommandServer? = null
    private var commandClient: CommandClient? = null
    private var tunPfd: ParcelFileDescriptor? = null
    private var connectivity: ConnectivityManager? = null
    private val capturedConnectionIds = LinkedHashSet<String>()
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private val boxLock = Any()
    // libbox start/reload/stop can wait on native socket and TUN teardown.
    // Never run those operations on Android's service main thread: a delayed
    // STOP arriving during a new START otherwise freezes MainActivity and
    // triggers an input-dispatch ANR.
    private val coreExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var defaultInterfaceListener: com.smartdolphin.libbox.InterfaceUpdateListener? = null
    @Volatile private var defaultInterfaceReady = false
    @Volatile private var notificationPollRunning = false
    private val notificationPoll = object : Runnable {
        override fun run() {
            pollAccountNotification()
            val prefs = getSharedPreferences("smartdolphin_vpn", Context.MODE_PRIVATE)
            val interval = if (prefs.getBoolean("account_risk_fast_poll", false)) 60_000L else 300_000L
            mainHandler.postDelayed(this, interval)
        }
    }

    fun isTunnelRunning(): Boolean = commandServer != null && tunPfd != null

    fun isTunnelValidated(): Boolean {
        val cm = connectivity ?: return false
        return runCatching {
            cm.allNetworks.any { network ->
                val capabilities = cm.getNetworkCapabilities(network) ?: return@any false
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                    capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
            }
        }.getOrDefault(false)
    }

    private fun persistedConfigFile(): File = File(filesDir, "dolphin_core/active-config.json")

    /**
     * A sticky VPN service may be recreated after Android kills the app process.
     * CoreBridge is process memory, so it cannot be the only copy of a running
     * tunnel's configuration. This app-private file is replaced atomically and
     * removed only for an explicit service stop.
     */
    private fun persistConfig(config: String) {
        val target = persistedConfigFile()
        target.parentFile?.mkdirs()
        val temporary = File(target.parentFile, "${target.name}.tmp")
        temporary.writeText(config, Charsets.UTF_8)
        if (!temporary.renameTo(target)) {
            target.writeText(config, Charsets.UTF_8)
            temporary.delete()
        }
    }

    private fun restorePersistedConfig(): String? = runCatching {
        persistedConfigFile().takeIf { it.isFile }?.readText(Charsets.UTF_8)
            ?.takeIf { it.isNotBlank() }
    }.getOrNull()

    private fun clearPersistedConfig() {
        runCatching { persistedConfigFile().delete() }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        CoreLogFile.init(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                clearPersistedConfig()
                coreExecutor.execute { synchronized(boxLock) { stopBox() } }
                return START_NOT_STICKY
            }
            ACTION_NETWORK_CHANGED -> {
                val config = restorePersistedConfig()
                if (commandServer != null) {
                    // Do not reload the core for a harmless Wi-Fi/cellular
                    // transition. The existing interface monitor will publish
                    // the new NIC; reloading here caused visible flashes and
                    // dropped otherwise healthy background tunnels.
                    scheduleDefaultInterfaceRefresh()
                    return START_STICKY
                }
                if (config.isNullOrBlank()) return START_NOT_STICKY
                startForeground(NOTIF_ID, buildNotification())
                mainHandler.removeCallbacks(notificationPoll)
                mainHandler.post(notificationPoll)
                coreExecutor.execute { synchronized(boxLock) { startBox(config) } }
                return START_STICKY
            }
            else -> {
                val config = intent?.getStringExtra(EXTRA_CONFIG)
                    ?: CoreBridge.pendingConfig
                    ?: restorePersistedConfig()
                if (config.isNullOrBlank()) {
                    // This is a sticky restart with no surviving session, not
                    // an error. Avoid bringing an Activity to the foreground.
                    return START_NOT_STICKY
                }
                persistConfig(config)
                startForeground(NOTIF_ID, buildNotification())
                mainHandler.removeCallbacks(notificationPoll)
                mainHandler.post(notificationPoll)
                coreExecutor.execute {
                    synchronized(boxLock) {
                        // A second START without STOP (reconnect / stale service) must not
                        // stack two libbox instances 鈥?that leaves a zombie tun that looks
                        // "connected" but carries no traffic after hours in background.
                        teardownBox(emitDisconnected = false)
                        startBox(config)
                    }
                }
                return START_STICKY
            }
        }
    }

    private fun startBox(config: String) {
        try {
            CoreBridge.emitStage("connecting")
            CoreLogFile.append("startBox begin")
            val base = filesDir.absolutePath
            val work = filesDir.resolve("dolphin_core").apply { mkdirs() }.absolutePath
            val tmp = cacheDir.resolve("dolphin_core").apply { mkdirs() }.absolutePath
            val setup = SetupOptions()
            setup.basePath = base
            setup.workingPath = work
            setup.tempPath = tmp
            Libbox.setup(setup)
            Libbox.setMemoryLimit(true)

            val server = Libbox.newCommandServer(this, this)
            server.start()
            commandServer = server
            // options MUST be non-null: the Go side dereferences it directly
            // (command_server.go StartOrReloadService) 鈫?nil would SIGSEGV the core.
            // The monitor can become ready synchronously while libbox starts.
            // Resetting this flag afterwards used to erase that signal and made
            // every otherwise healthy connection wait the full ten seconds.
            defaultInterfaceReady = false
            server.startOrReloadService(config, OverrideOptions())

            startStatusClient()
            scheduleDefaultInterfaceRefresh()
            if (!waitForDefaultInterfaceReady(1_200)) {
                throw IllegalStateException("default physical interface unavailable")
            }
            CoreBridge.markCoreReady()
            CoreBridge.emitStage("connected")
            CoreLogFile.append("Dolphin-Core service started")
            Log.i(TAG, "Dolphin-Core service started")
        } catch (e: Exception) {
            Log.e(TAG, "startBox failed", e)
            CoreLogFile.append("startBox failed: ${e.message}")
            CoreBridge.emitStage("error")
            stopBox()
        }
    }

    /** Tear down libbox + tun without necessarily killing the VpnService process. */
    private fun teardownBox(emitDisconnected: Boolean) {
        mainHandler.removeCallbacks(notificationPoll)
        mainHandler.removeCallbacksAndMessages(null)
        clearDefaultInterface()
        try { commandClient?.disconnect() } catch (_: Exception) {}
        commandClient = null
        try { commandServer?.closeService() } catch (_: Exception) {}
        try { commandServer?.close() } catch (_: Exception) {}
        commandServer = null
        try { tunPfd?.close() } catch (_: Exception) {}
        tunPfd = null
        networkCallback?.let { cb -> runCatching { connectivity?.unregisterNetworkCallback(cb) } }
        networkCallback = null
        if (emitDisconnected) {
            CoreBridge.emitStage("disconnected")
        }
    }

    private fun stopBox() {
        teardownBox(emitDisconnected = true)
        CoreLogFile.append("stopBox")
        stopForegroundCompat()
        stopSelf()
    }

    override fun onDestroy() {
        instance = null
        coreExecutor.execute {
            synchronized(boxLock) { teardownBox(emitDisconnected = true) }
        }
        coreExecutor.shutdown()
        super.onDestroy()
    }

    override fun onRevoke() {
        // System or another VPN revoked our permission.
        coreExecutor.execute { synchronized(boxLock) { stopBox() } }
        super.onRevoke()
    }

    // --- status (CommandClient) ---------------------------------------------

    private fun startStatusClient() {
        try {
            val opts = CommandClientOptions()
            opts.addCommand(Libbox.CommandStatus)
            val auditMode = auditCaptureMode()
            if (auditMode != "basic") {
                opts.addCommand(Libbox.CommandConnections)
                if (auditMode == "enhanced") opts.addCommand(Libbox.CommandLog)
            }
            // Enhanced diagnostics samples often enough to observe short-lived
            // connections. Normal operation keeps the lower-frequency status path.
            opts.statusInterval = if (auditMode == "enhanced") 2_000L else 5_000L
            val client = Libbox.newCommandClient(StatusHandler(), opts)
            client.connect()
            commandClient = client
        } catch (e: Exception) {
            Log.w(TAG, "status client failed: ${e.message}")
        }
    }

    private fun auditCaptureMode(): String =
        getSharedPreferences("smartdolphin_vpn", Context.MODE_PRIVATE)
            .getString("audit_capture_mode", "basic") ?: "basic"

    fun refreshAuditCapture() {
        coreExecutor.execute {
            synchronized(boxLock) {
                runCatching { commandClient?.disconnect() }
                commandClient = null
                capturedConnectionIds.clear()
                if (commandServer != null) startStatusClient()
            }
        }
    }

    private inner class StatusHandler : CommandClientHandler {
        override fun connected() {}
        override fun disconnected(message: String?) {}
        override fun clearLogs() {}
        override fun initializeClashMode(modeList: StringIterator?, currentMode: String?) {}
        override fun setDefaultLogLevel(level: Int) {}
        override fun updateClashMode(newMode: String?) {}
        override fun writeConnections(message: Connections?) {
            if (message == null) return
            val mode = auditCaptureMode()
            if (mode == "basic") return
            val iterator = message.iterator()
            while (iterator.hasNext()) {
                val connection: Connection = iterator.next() ?: continue
                val id = connection.id?.trim().orEmpty()
                if (id.isEmpty() || !capturedConnectionIds.add(id)) continue
                while (capturedConnectionIds.size > 4096) {
                    val oldest = capturedConnectionIds.iterator()
                    if (!oldest.hasNext()) break
                    oldest.next()
                    oldest.remove()
                }
                val destination = connection.destination?.trim().orEmpty()
                val domain = connection.domain?.trim().orEmpty()
                val detail = buildString {
                    append("connection destination=")
                    append(if (destination.isEmpty()) "unknown" else destination)
                    append(" protocol=")
                    append(connection.protocol?.trim().orEmpty())
                    if (mode == "enhanced" && domain.isNotEmpty()) {
                        append(" sni=")
                        append(domain)
                    }
                }
                CoreLogFile.append(detail)
            }
        }
        override fun writeGroups(message: OutboundGroupIterator?) {}
        override fun writeLogs(messageList: LogIterator?) {
            if (messageList == null) return
            while (messageList.hasNext()) {
                val entry: LogEntry = messageList.next() ?: continue
                val message = entry.message
                // Runtime access logs can arrive many times per second. Writing every
                // line to Logcat and storage keeps the CPU and flash awake in background.
                // Preserve warnings/errors while lifecycle events are logged separately.
                val important = message.contains("error", ignoreCase = true) ||
                    message.contains("warning", ignoreCase = true) ||
                    message.contains("fatal", ignoreCase = true) ||
                    message.contains("panic", ignoreCase = true)
                if (important) {
                    Log.w("DolphinCore", message)
                    CoreLogFile.append(message)
                }
            }
        }
        override fun writeStatus(message: StatusMessage?) {
            if (message == null) return
            val json = JSONObject()
            json.put("up", message.uplink)
            json.put("down", message.downlink)
            json.put("upTotal", message.uplinkTotal)
            json.put("downTotal", message.downlinkTotal)
            json.put("trafficAvailable", message.trafficAvailable)
            CoreBridge.emitStatus(json.toString())
        }
    }

    // --- CommandServerHandler -----------------------------------------------

    override fun serviceReload() {
        val cfg = CoreBridge.pendingConfig ?: return
        coreExecutor.execute {
            synchronized(boxLock) {
                runCatching { commandServer?.startOrReloadService(cfg, OverrideOptions()) }
            }
        }
    }

    override fun serviceStop() {
        coreExecutor.execute { synchronized(boxLock) { stopBox() } }
    }

    override fun getSystemProxyStatus(): SystemProxyStatus = SystemProxyStatus()

    override fun setSystemProxyEnabled(isEnabled: Boolean) {}

    override fun writeDebugMessage(message: String?) {
        if (message != null) Log.d(TAG, message)
    }

    // --- PlatformInterface --------------------------------------------------

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        // Protect the engine's outbound sockets so they bypass the tun.
        protect(fd)
    }

    override fun openTun(options: TunOptions): Int {
        val builder = Builder()
        builder.setSession("Dolphin-Core")
        builder.setMtu(options.mtu)

        val inet4 = options.inet4Address
        while (inet4.hasNext()) {
            val p = inet4.next()
            builder.addAddress(p.address(), p.prefix())
        }
        val inet6 = options.inet6Address
        while (inet6.hasNext()) {
            val p = inet6.next()
            builder.addAddress(p.address(), p.prefix())
        }

        if (options.autoRoute) {
            val r4 = options.inet4RouteAddress
            if (r4.hasNext()) {
                while (r4.hasNext()) {
                    val p = r4.next()
                    builder.addRoute(p.address(), p.prefix())
                }
            } else {
                builder.addRoute("0.0.0.0", 0)
            }
            val r6 = options.inet6RouteAddress
            if (r6.hasNext()) {
                while (r6.hasNext()) {
                    val p = r6.next()
                    builder.addRoute(p.address(), p.prefix())
                }
            }
        }

        runCatching {
            val dns = options.dnsServerAddress?.value
            if (!dns.isNullOrBlank()) builder.addDnsServer(dns)
        }

        val include = options.includePackage
        var hasInclude = false
        while (include.hasNext()) {
            runCatching { builder.addAllowedApplication(include.next()); hasInclude = true }
        }
        if (!hasInclude) {
            val exclude = options.excludePackage
            while (exclude.hasNext()) {
                runCatching { builder.addDisallowedApplication(exclude.next()) }
            }
        }

        builder.setBlocking(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

        val pfd = builder.establish() ?: throw IllegalStateException("VpnService.establish() returned null")
        tunPfd = pfd
        CoreBridge.markTunEstablished()
        return pfd.fd
    }

    override fun useProcFS(): Boolean = false

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String?,
        sourcePort: Int,
        destinationAddress: String?,
        destinationPort: Int,
    ): Int = -1

    override fun packageNameByUid(uid: Int): String {
        return runCatching { packageManager.getPackagesForUid(uid)?.firstOrNull() }.getOrNull() ?: ""
    }

    override fun uidByPackageName(packageName: String?): Int {
        if (packageName == null) return -1
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageUid(packageName, android.content.pm.PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageUid(packageName, 0)
            }
        }.getOrDefault(-1)
    }

    override fun startDefaultInterfaceMonitor(listener: com.smartdolphin.libbox.InterfaceUpdateListener?) {
        val cm = connectivity ?: return
        defaultInterfaceListener = listener
        pushDefaultInterface(listener)
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = pushDefaultInterface(listener)
            override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) = pushDefaultInterface(listener)
            override fun onLost(network: Network) = pushDefaultInterface(listener)
        }
        networkCallback = cb
        // Track the UNDERLYING physical network (Wi-Fi / cellular), never our own
        // VPN. Using the default callback returned tun0 once connected, leaving
        // sing-box with "no available network interface" for every dial.
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        runCatching { cm.registerNetworkCallback(request, cb) }
    }

    override fun closeDefaultInterfaceMonitor(listener: com.smartdolphin.libbox.InterfaceUpdateListener?) {
        networkCallback?.let { cb -> runCatching { connectivity?.unregisterNetworkCallback(cb) } }
        networkCallback = null
        clearDefaultInterface()
        defaultInterfaceListener = null
    }

    private fun clearDefaultInterface() {
        defaultInterfaceReady = false
        runCatching {
            defaultInterfaceListener?.updateDefaultInterface("", -1, false, false)
        }
    }

    /** Re-publish default NIC after service (re)start 鈥?libbox reload can miss the first update. */
    private fun scheduleDefaultInterfaceRefresh() {
        for (delay in REFRESH_DELAYS_MS) {
            mainHandler.postDelayed({ pushDefaultInterface(defaultInterfaceListener) }, delay)
        }
    }

    /**
     * libbox cannot dial until the underlying Wi-Fi/cellular NIC is bound.
     * Windows waits for `waitForStarted`; Android must not emit "connected" before this.
     */
    private fun waitForDefaultInterfaceReady(timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            val listener = defaultInterfaceListener
            if (listener != null) {
                pushDefaultInterface(listener)
                if (defaultInterfaceReady) return true
            }
            Thread.sleep(40)
        }
        return defaultInterfaceReady
    }

    private fun pushDefaultInterface(listener: com.smartdolphin.libbox.InterfaceUpdateListener?) {
        if (listener == null) return
        val cm = connectivity ?: return
        runCatching {
            // Choose the underlying physical network (Wi-Fi / cellular), NOT our
            // own VPN. cm.activeNetwork returns the VPN (tun0) once connected,
            // which made sing-box report "no available network interface".
            var chosenLp: LinkProperties? = null
            var chosenValidated = false
            for (network in cm.allNetworks) {
                val caps = cm.getNetworkCapabilities(network) ?: continue
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
                if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) continue
                val lp = cm.getLinkProperties(network) ?: continue
                if (lp.interfaceName.isNullOrBlank()) continue
                val validated = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                if (chosenLp == null || (validated && !chosenValidated)) {
                    chosenLp = lp
                    chosenValidated = validated
                }
                if (validated) break
            }
            val name = chosenLp?.interfaceName ?: ""
            if (name.isEmpty()) {
                Log.w(TAG, "pushDefaultInterface -> no physical NIC, clearing default")
                defaultInterfaceReady = false
                listener.updateDefaultInterface("", -1, false, false)
                return
            }
            // Index MUST match an entry from getInterfaces() or libbox filters the
            // interface list to empty 鈫?"no available network interface" on every dial.
            val index = findInterfaceIndexForName(name)
            if (index <= 0) {
                Log.w(TAG, "pushDefaultInterface -> index unresolved for '$name', clearing default")
                defaultInterfaceReady = false
                listener.updateDefaultInterface("", -1, false, false)
                return
            }
            Log.i(TAG, "pushDefaultInterface -> name='$name' index=$index validated=$chosenValidated")
            defaultInterfaceReady = true
            listener.updateDefaultInterface(name, index, false, false)
        }.onFailure { Log.w(TAG, "pushDefaultInterface failed: ${it.message}") }
    }

    /** Resolve NIC index from the same enumeration libbox reads via getInterfaces(). */
    private fun findInterfaceIndexForName(name: String): Int {
        runCatching {
            for (ni in java.net.NetworkInterface.getNetworkInterfaces()) {
                if (ni.name == name && ni.isUp && ni.index > 0) return ni.index
            }
        }
        return -1
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val result = ArrayList<LibboxInterface>()
        runCatching {
            for (ni in java.net.NetworkInterface.getNetworkInterfaces()) {
                if (!ni.isUp) continue
                val item = LibboxInterface()
                item.name = ni.name
                item.index = ni.index
                item.mtu = runCatching { ni.mtu }.getOrDefault(1500)
                // Raw Linux interface flags. THE GO CORE (route/network.go
                // UpdateInterfaces) KEEPS ONLY interfaces with IFF_UP set; if flags
                // stays 0 the whole interface list is filtered to empty and every
                // dial fails with "no available network interface".
                // IFF_UP=0x1 BROADCAST=0x2 LOOPBACK=0x8 POINTOPOINT=0x10 RUNNING=0x40 MULTICAST=0x1000
                var flags = 0x1 or 0x40 // up + running (already skipped !isUp above)
                runCatching { if (ni.isLoopback) flags = flags or 0x8 }
                runCatching { if (ni.isPointToPoint) flags = flags or 0x10 }
                runCatching { if (ni.supportsMulticast()) flags = flags or 0x1000 }
                runCatching { if (!ni.isLoopback && !ni.isPointToPoint) flags = flags or 0x2 }
                item.flags = flags
                val addrs = ArrayList<String>()
                for (ia in ni.interfaceAddresses) {
                    var host = ia.address.hostAddress ?: continue
                    // Strip IPv6 zone/scope id (e.g. "fe80::1%rmnet_data0"): sing-box's
                    // netip.ParsePrefix panics on a zone in a prefix 鈫?crashes the whole core.
                    val zone = host.indexOf('%')
                    if (zone >= 0) host = host.substring(0, zone)
                    val pfx = ia.networkPrefixLength.toInt()
                    addrs.add("$host/$pfx")
                }
                item.addresses = StrIter(addrs)
                result.add(item)
            }
        }
        Log.i(TAG, "getInterfaces -> " + result.joinToString { "${it.name}(idx=${it.index},fl=0x${Integer.toHexString(it.flags)})" })
        return IfaceIter(result)
    }

    override fun underNetworkExtension(): Boolean = false

    override fun includeAllNetworks(): Boolean = false

    override fun readWIFIState(): WIFIState? = null

    override fun systemCertificates(): StringIterator = StrIter(emptyList())

    override fun localDNSTransport(): com.smartdolphin.libbox.LocalDNSTransport? = null

    override fun clearDNSCache() {}

    override fun sendNotification(notification: LibboxNotification?) {}

    private fun pollAccountNotification() {
        if (notificationPollRunning || !CoreBridge.connected) return
        val prefs = getSharedPreferences("smartdolphin_vpn", Context.MODE_PRIVATE)
        val token = prefs.getString("account_session_token", "")?.trim().orEmpty()
        if (token.isEmpty()) return
        notificationPollRunning = true
        Thread {
            try {
                val connection = (URL("https://smartdolphinvpn.com/api/auth/account-status").openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = 8_000
                    readTimeout = 8_000
                    setRequestProperty("Authorization", "Bearer $token")
                    setRequestProperty("X-SmartDolphin-Client", "android")
                    val packageInfo = packageManager.getPackageInfo(packageName, 0)
                    val versionName = packageInfo.versionName ?: "0"
                    val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        packageInfo.longVersionCode
                    } else {
                        @Suppress("DEPRECATION") packageInfo.versionCode.toLong()
                    }
                    setRequestProperty("X-SmartDolphin-Version", versionName)
                    setRequestProperty("X-SmartDolphin-Build", versionCode.toString())
                }
                val code = connection.responseCode
                if (code == 200) {
                    val body = connection.inputStream.bufferedReader().use { it.readText() }
                    val account = JSONObject(body)
                    val fastPoll = account.optInt("violation_count", 0) > 0 ||
                        account.optBoolean("locked", false) ||
                        account.optBoolean("banned", false)
                    prefs.edit().putBoolean("account_risk_fast_poll", fastPoll).apply()
                    val notification = account.optJSONObject("notification")
                    if (notification != null) {
                        val id = notification.optInt("id", 0)
                        val last = prefs.getInt("account_notification_last", 0)
                        val title = notification.optString("title").trim()
                        val text = notification.optString("body").trim()
                        if (id > last && title.isNotEmpty() && text.isNotEmpty()) {
                            showAccountNotification(id, title, text)
                            prefs.edit().putInt("account_notification_last", id).apply()
                        }
                    }
                } else if (code == 401 || code == 403) {
                    prefs.edit().remove("account_session_token").apply()
                }
                connection.disconnect()
            } catch (error: Throwable) {
                Log.d(TAG, "Account notification poll deferred: ${error.message}")
            } finally {
                notificationPollRunning = false
            }
        }.start()
    }

    private fun showAccountNotification(id: Int, title: String, text: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    ACCOUNT_NOTIF_CHANNEL,
                    "Account messages",
                    NotificationManager.IMPORTANCE_HIGH,
                )
            )
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pending = PendingIntent.getActivity(
            this,
            id,
            launch ?: Intent(),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, ACCOUNT_NOTIF_CHANNEL)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        manager.notify(
            ACCOUNT_NOTIF_BASE_ID + id.mod(10_000),
            builder.setSmallIcon(applicationInfo.icon)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setAutoCancel(true)
                .setContentIntent(pending)
                .build(),
        )
    }

    // --- helpers ------------------------------------------------------------

    private class StrIter(private val items: List<String>) : StringIterator {
        private var i = 0
        override fun hasNext(): Boolean = i < items.size
        override fun next(): String = items[i++]
        override fun len(): Int = items.size
    }

    private class IfaceIter(private val items: List<LibboxInterface>) : NetworkInterfaceIterator {
        private var i = 0
        override fun hasNext(): Boolean = i < items.size
        override fun next(): LibboxInterface = items[i++]
    }

    private fun buildNotification(): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(NOTIF_CHANNEL, "VPN", NotificationManager.IMPORTANCE_LOW)
            nm.createNotificationChannel(ch)
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(
            this, 0, launch ?: Intent(),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIF_CHANNEL)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        return b.setContentTitle("SmartDolphin VPN")
            .setContentText("Connected via Dolphin-Core")
            .setSmallIcon(applicationInfo.icon)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION") stopForeground(true)
        }
    }
}
