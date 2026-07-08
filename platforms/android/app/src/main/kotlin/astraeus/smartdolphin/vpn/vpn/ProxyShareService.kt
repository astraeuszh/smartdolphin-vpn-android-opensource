package astraeus.smartdolphin.vpn.vpn

import android.util.Log
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean

/** 简易 HTTP CONNECT / SOCKS5 代理，供「代理共享」在 VPN 连接后向局域网设备提供出口。 */
object ProxyShareService {
    private const val TAG = "ProxyShareService"
    private const val HTTP_PORT = 8080
    private const val SOCKS_PORT = 1080

    private var worker: Thread? = null
    private val running = AtomicBoolean(false)

    @Synchronized
    fun start(mode: String) {
        stop()
        running.set(true)
        val port = if (mode == "socks5") SOCKS_PORT else HTTP_PORT
        worker = Thread {
            try {
                ServerSocket(port).use { server ->
                    server.reuseAddress = true
                    Log.i(TAG, "proxy share listening on 0.0.0.0:$port mode=$mode")
                    while (running.get()) {
                        try {
                            val client = server.accept()
                            Thread { handleClient(client, mode) }.start()
                        } catch (e: Exception) {
                            if (running.get()) Log.w(TAG, "accept failed", e)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "proxy share failed", e)
            }
        }.also { it.isDaemon = true; it.start() }
    }

    @Synchronized
    fun stop() {
        running.set(false)
        worker?.interrupt()
        worker = null
    }

    private fun handleClient(client: Socket, mode: String) {
        client.soTimeout = 30000
        try {
            client.use { c ->
                if (mode == "socks5") {
                    handleSocks5(c)
                } else {
                    handleHttp(c)
                }
            }
        } catch (e: Exception) {
            Log.d(TAG, "client closed: ${e.message}")
        }
    }

    private fun handleHttp(client: Socket) {
        val input = client.getInputStream().bufferedReader()
        val requestLine = input.readLine() ?: return
        val parts = requestLine.split(' ')
        if (parts.size < 3) return
        val method = parts[0]
        val target = parts[1]
        while (true) {
            val line = input.readLine() ?: break
            if (line.isEmpty()) break
        }
        if (method.equals("CONNECT", ignoreCase = true)) {
            val hostPort = target.split(':')
            val host = hostPort[0]
            val port = hostPort.getOrNull(1)?.toIntOrNull() ?: 443
            relayConnect(client, host, port)
        } else {
            client.getOutputStream().write("HTTP/1.1 501 Not Implemented\r\n\r\n".toByteArray())
        }
    }

    private fun handleSocks5(client: Socket) {
        val input = client.getInputStream()
        val output = client.getOutputStream()
        val header = ByteArray(2)
        if (input.read(header) != 2) return
        val nMethods = header[1].toInt() and 0xFF
        input.skip(nMethods.toLong())
        output.write(byteArrayOf(0x05, 0x00))
        output.flush()
        val req = ByteArray(4)
        if (input.read(req) != 4) return
        val addrType = req[3].toInt() and 0xFF
        val host = when (addrType) {
            0x01 -> {
                val buf = ByteArray(4)
                input.read(buf)
                buf.joinToString(".") { (it.toInt() and 0xFF).toString() }
            }
            0x03 -> {
                val len = input.read()
                val buf = ByteArray(len)
                input.read(buf)
                String(buf)
            }
            else -> return
        }
        val portBuf = ByteArray(2)
        input.read(portBuf)
        val port = ((portBuf[0].toInt() and 0xFF) shl 8) or (portBuf[1].toInt() and 0xFF)
        relayConnect(client, host, port)
    }

    private fun relayConnect(client: Socket, host: String, port: Int) {
        Socket().use { remote ->
            remote.connect(InetSocketAddress(host, port), 15000)
            client.getOutputStream().write("HTTP/1.1 200 Connection Established\r\n\r\n".toByteArray())
            pipe(client.getInputStream(), remote.getOutputStream())
            pipe(remote.getInputStream(), client.getOutputStream())
        }
    }

    private fun pipe(input: InputStream, output: OutputStream) {
        val buf = ByteArray(8192)
        while (true) {
            val read = input.read(buf)
            if (read <= 0) break
            output.write(buf, 0, read)
            output.flush()
        }
    }
}
