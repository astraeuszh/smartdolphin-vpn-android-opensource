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
import com.smartdolphin.libbox.CommandClient
import com.smartdolphin.libbox.CommandClientOptions
import com.smartdolphin.libbox.CommandClientHandler
import com.smartdolphin.libbox.CommandServer
import com.smartdolphin.libbox.CommandServerHandler
import com.smartdolphin.libbox.Connections
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
        const val EXTRA_CONFIG = "config"
        private const val NOTIF_CHANNEL = "dolphin_vpn"
        private const val NOTIF_ID = 7301

        @Volatile
        var instance: BoxService? = null

        private val REFRESH_DELAYS_MS = longArrayOf(300, 1000, 3000)
    }

    private var commandServer: CommandServer? = null
    private var commandClient: CommandClient? = null
    private var tunPfd: ParcelFileDescriptor? = null
    private var connectivity: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private val boxLock = Any()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var defaultInterfaceListener: com.smartdolphin.libbox.InterfaceUpdateListener? = null
    @Volatile private var defaultInterfaceReady = false

    override fun onCreate() {
        super.onCreate()
        instance = this
        connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        CoreLogFile.init(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                synchronized(boxLock) { stopBox() }
                return START_NOT_STICKY
            }
            else -> {
                val config = intent?.getStringExtra(EXTRA_CONFIG) ?: CoreBridge.pendingConfig
                if (config.isNullOrBlank()) {
                    synchronized(boxLock) { stopBox() }
                    return START_NOT_STICKY
                }
                startForeground(NOTIF_ID, buildNotification())
                Thread {
                    synchronized(boxLock) {
                        // A second START without STOP (reconnect / stale service) must not
                        // stack two libbox instances 鈥?that leaves a zombie tun that looks
                        // "connected" but carries no traffic after hours in background.
                        teardownBox(emitDisconnected = false)
                        startBox(config)
                    }
                }.start()
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
            server.startOrReloadService(config, OverrideOptions())

            startStatusClient()
            defaultInterfaceReady = false
            scheduleDefaultInterfaceRefresh()
            if (!waitForDefaultInterfaceReady(10_000)) {
                Log.w(TAG, "Default physical NIC not ready at connect time 鈥?continuing with scheduled refresh")
                CoreLogFile.append("startBox warning: default interface not ready yet")
            }
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
        try { tunPfd?.close() } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onRevoke() {
        // System or another VPN revoked our permission.
        stopBox()
        super.onRevoke()
    }

    // --- status (CommandClient) ---------------------------------------------

    private fun startStatusClient() {
        try {
            val opts = CommandClientOptions()
            opts.addCommand(Libbox.CommandStatus)
            // Traffic counters are presentation data, not a tunnel heartbeat.
            // A one-second cross-language callback keeps the app process and radio
            // active in background. Ten seconds is enough for quota/UI updates.
            opts.statusInterval = 10_000L
            val client = Libbox.newCommandClient(StatusHandler(), opts)
            client.connect()
            commandClient = client
        } catch (e: Exception) {
            Log.w(TAG, "status client failed: ${e.message}")
        }
    }

    private inner class StatusHandler : CommandClientHandler {
        override fun connected() {}
        override fun disconnected(message: String?) {}
        override fun clearLogs() {}
        override fun initializeClashMode(modeList: StringIterator?, currentMode: String?) {}
        override fun setDefaultLogLevel(level: Int) {}
        override fun updateClashMode(newMode: String?) {}
        override fun writeConnections(message: Connections?) {}
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
        runCatching { commandServer?.startOrReloadService(cfg, OverrideOptions()) }
    }

    override fun serviceStop() {
        stopBox()
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
            Thread.sleep(250)
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
