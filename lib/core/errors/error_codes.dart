/// Error codes aligned with SmartDolphinVPN Windows (0X00MMNN00).
/// MM = module, NN = sequence. English messages are brief and professional.

// Basic/General (0X0001XX00)
const int ecStartupInitFailed = 0x00010100;
const int ecComponentMissing = 0x00010200;
const int ecLogDirCreateFailed = 0x00010400;
const int ecLogWriteFailed = 0x00010500;
const int ecInsufficientPermission = 0x00010600;
const int ecConfigCorrupted = 0x00010800;
const int ecMemoryInsufficient = 0x00010900;

// Network/Node (0X0003XX00)
const int ecNodeConfigFailed = 0x00030100;
const int ecNodeConnTimeout = 0x00030200;
const int ecNodeConnRefused = 0x00030300;
const int ecLocalNetDisconnected = 0x00030400;
const int ecDnsResolveFailed = 0x00030500;
const int ecNetworkUnstable = 0x00030700;
const int ecNodeDisconnected = 0x00030C00;
const int ecVpnPermissionDenied = 0x00030D00;
const int ecTrafficLimited = 0x00030B00;
const int ecTrafficQuota90 = 0x00030E00;
const int ecSessionTimerCap = 0x00030F00;

// Core/VPN (0X0005XX00)
const int ecCoreStartFailed = 0x00050100;
const int ecCoreConfigFailed = 0x00050300;

// Profile/Config (0X000EXX00)
const int ecProfileLoadFailed = 0x000E0400;
const int ecProfileCorrupted = 0x000E0200;

// System (0X000FXX00)
const int ecServiceUnavailable = 0x000F0400;

/// Returns brief English message for error code.
String getErrorMessage(int code) {
  switch (code) {
    case ecStartupInitFailed:
      return 'Startup initialization failed';
    case ecComponentMissing:
      return 'Critical component missing';
    case ecLogDirCreateFailed:
      return 'Log directory creation failed';
    case ecLogWriteFailed:
      return 'Log write failed';
    case ecInsufficientPermission:
      return 'Insufficient permission';
    case ecConfigCorrupted:
      return 'Configuration corrupted';
    case ecMemoryInsufficient:
      return 'Memory insufficient';
    case ecNodeConfigFailed:
      return 'Node config failed';
    case ecNodeConnTimeout:
      return 'Connection timeout';
    case ecNodeConnRefused:
      return 'Connection refused';
    case ecLocalNetDisconnected:
      return 'Network error';
    case ecDnsResolveFailed:
      return 'DNS resolve failed';
    case ecNetworkUnstable:
      return 'Network unstable';
    case ecNodeDisconnected:
      return 'Connection disconnected';
    case ecTrafficLimited:
      return 'Traffic limit reached';
    case ecTrafficQuota90:
      return 'Traffic quota warning';
    case ecSessionTimerCap:
      return 'Session timer limit';
    case ecVpnPermissionDenied:
      return 'VPN permission denied';
    case ecCoreStartFailed:
      return 'VPN core start failed';
    case ecCoreConfigFailed:
      return 'VPN config failed';
    case ecProfileLoadFailed:
      return 'Config load failed';
    case ecProfileCorrupted:
      return 'Config corrupted';
    case ecServiceUnavailable:
      return 'Service unavailable';
    default:
      return 'Unknown error';
  }
}

/// Format error code as 0X00000000 string.
String formatErrorCode(int code) {
  return '0X${code.toRadixString(16).toUpperCase().padLeft(8, '0')}';
}
