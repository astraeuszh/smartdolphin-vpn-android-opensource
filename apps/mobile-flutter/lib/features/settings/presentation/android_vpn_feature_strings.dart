import 'package:flutter/widgets.dart';

String androidVpnText(BuildContext context, String key) {
  final language = Localizations.localeOf(context).languageCode;
  final values = _strings[key] ?? _strings['demoNotice']!;
  return values[language] ?? values['en']!;
}

const Map<String, Map<String, String>> _strings = {
  'title': {
    'zh': 'Android VPN 功能',
    'en': 'Android VPN features',
    'ja': 'Android VPN 機能',
    'ko': 'Android VPN 기능',
    'es': 'Funciones VPN de Android'
  },
  'demoNotice': {
    'zh': '当前功能正在开发中，目前只是演示模式',
    'en': 'This feature is under development and is currently a demo.',
    'ja': 'この機能は開発中で、現在はデモモードです。',
    'ko': '이 기능은 개발 중이며 현재 데모 모드입니다.',
    'es': 'Esta funcion esta en desarrollo y actualmente es una demostracion.'
  },
  'status': {
    'zh': '已接入的设置立即生效；标记为演示的功能会保存界面选择，但暂不修改 VPN 核心。',
    'en':
        'Supported settings take effect immediately. Demo settings are saved but do not change the VPN core yet.',
    'ja': '対応済みの設定はすぐに反映されます。デモ設定は保存されますが、VPN コアはまだ変更しません。',
    'ko': '지원되는 설정은 즉시 적용됩니다. 데모 설정은 저장되지만 아직 VPN 코어를 변경하지 않습니다.',
    'es':
        'Los ajustes compatibles se aplican al instante. Los ajustes de demostracion se guardan, pero aun no modifican el nucleo VPN.'
  },
  'connection': {
    'zh': '连接与节点',
    'en': 'Connection and nodes',
    'ja': '接続とノード',
    'ko': '연결 및 노드',
    'es': 'Conexion y nodos'
  },
  'routingRules': {
    'zh': '分流与规则',
    'en': 'Routing and rules',
    'ja': 'ルーティングとルール',
    'ko': '라우팅 및 규칙',
    'es': 'Enrutamiento y reglas'
  },
  'securityDns': {
    'zh': '安全与 DNS',
    'en': 'Security and DNS',
    'ja': 'セキュリティと DNS',
    'ko': '보안 및 DNS',
    'es': 'Seguridad y DNS'
  },
  'trafficProxy': {
    'zh': '流量与本地代理',
    'en': 'Traffic and local proxies',
    'ja': '通信量とローカルプロキシ',
    'ko': '트래픽 및 로컬 프록시',
    'es': 'Trafico y proxies locales'
  },
  'tunnelAdvanced': {
    'zh': '隧道与高级',
    'en': 'Tunnel and advanced',
    'ja': 'トンネルと詳細設定',
    'ko': '터널 및 고급 설정',
    'es': 'Tunel y opciones avanzadas'
  },
  'connect': {
    'zh': '一键连接 / 断开',
    'en': 'Connect / disconnect',
    'ja': '接続 / 切断',
    'ko': '연결 / 연결 해제',
    'es': 'Conectar / desconectar'
  },
  'connected': {
    'zh': '已连接',
    'en': 'Connected',
    'ja': '接続済み',
    'ko': '연결됨',
    'es': 'Conectado'
  },
  'connectHint': {
    'zh': '请在首页选择节点后连接',
    'en': 'Select a node on Home, then connect',
    'ja': 'ホームでノードを選択して接続してください',
    'ko': '홈에서 노드를 선택한 후 연결하세요',
    'es': 'Selecciona un nodo en Inicio y conectate'
  },
  'boot': {
    'zh': '开机自动连接',
    'en': 'Connect on startup',
    'ja': '起動時に自動接続',
    'ko': '시작 시 자동 연결',
    'es': 'Conectar al iniciar'
  },
  'reconnect': {
    'zh': '自动重连',
    'en': 'Auto reconnect',
    'ja': '自動再接続',
    'ko': '자동 재연결',
    'es': 'Reconexion automatica'
  },
  'node': {
    'zh': '节点选择',
    'en': 'Node selection',
    'ja': 'ノード選択',
    'ko': '노드 선택',
    'es': 'Seleccion de nodo'
  },
  'listChoice': {
    'zh': '列表选择',
    'en': 'Choose from list',
    'ja': 'リストから選択',
    'ko': '목록에서 선택',
    'es': 'Elegir de la lista'
  },
  'latency': {
    'zh': '节点延迟测速',
    'en': 'Node latency test',
    'ja': 'ノード遅延テスト',
    'ko': '노드 지연 테스트',
    'es': 'Prueba de latencia'
  },
  'tapTest': {
    'zh': '点击开始测试',
    'en': 'Tap to start',
    'ja': 'タップして開始',
    'ko': '탭하여 시작',
    'es': 'Toca para iniciar'
  },
  'protocol': {
    'zh': '协议选择',
    'en': 'Protocol',
    'ja': 'プロトコル',
    'ko': '프로토콜',
    'es': 'Protocolo'
  },
  'proxyMode': {
    'zh': '代理模式',
    'en': 'Proxy mode',
    'ja': 'プロキシモード',
    'ko': '프록시 모드',
    'es': 'Modo proxy'
  },
  'global': {
    'zh': '全局',
    'en': 'Global',
    'ja': 'グローバル',
    'ko': '글로벌',
    'es': 'Global'
  },
  'rules': {'zh': '分流', 'en': 'Rules', 'ja': 'ルール', 'ko': '규칙', 'es': 'Reglas'},
  'direct': {
    'zh': '直连',
    'en': 'Direct',
    'ja': '直接接続',
    'ko': '직접 연결',
    'es': 'Directo'
  },
  'appRouting': {
    'zh': '按应用分流',
    'en': 'Per-app routing',
    'ja': 'アプリ別ルーティング',
    'ko': '앱별 라우팅',
    'es': 'Enrutamiento por aplicacion'
  },
  'multiApp': {
    'zh': '应用列表多选',
    'en': 'Select multiple apps',
    'ja': '複数アプリを選択',
    'ko': '여러 앱 선택',
    'es': 'Seleccionar varias aplicaciones'
  },
  'domainRouting': {
    'zh': '按域名分流',
    'en': 'Domain routing',
    'ja': 'ドメイン別ルーティング',
    'ko': '도메인 라우팅',
    'es': 'Enrutamiento por dominio'
  },
  'ipRouting': {
    'zh': '按 IP 段分流',
    'en': 'IP range routing',
    'ja': 'IP 範囲ルーティング',
    'ko': 'IP 대역 라우팅',
    'es': 'Enrutamiento por rango IP'
  },
  'ruleSubscription': {
    'zh': '规则订阅',
    'en': 'Rule subscription',
    'ja': 'ルール購読',
    'ko': '규칙 구독',
    'es': 'Suscripcion de reglas'
  },
  'autoUpdate': {
    'zh': '自动更新',
    'en': 'Auto update',
    'ja': '自動更新',
    'ko': '자동 업데이트',
    'es': 'Actualizacion automatica'
  },
  'updateInterval': {
    'zh': '自动更新间隔',
    'en': 'Update interval',
    'ja': '更新間隔',
    'ko': '업데이트 간격',
    'es': 'Intervalo de actualizacion'
  },
  'ipv6': {
    'zh': 'IPv6 泄漏防护',
    'en': 'IPv6 leak protection',
    'ja': 'IPv6 リーク保護',
    'ko': 'IPv6 유출 방지',
    'es': 'Proteccion contra fugas IPv6'
  },
  'customDns': {
    'zh': '自定义 DNS',
    'en': 'Custom DNS',
    'ja': 'カスタム DNS',
    'ko': '사용자 지정 DNS',
    'es': 'DNS personalizado'
  },
  'dnsLeak': {
    'zh': 'DNS 泄漏防护',
    'en': 'DNS leak protection',
    'ja': 'DNS リーク保護',
    'ko': 'DNS 유출 방지',
    'es': 'Proteccion contra fugas DNS'
  },
  'obfuscation': {
    'zh': '流量混淆',
    'en': 'Traffic obfuscation',
    'ja': '通信難読化',
    'ko': '트래픽 난독화',
    'es': 'Ofuscacion de trafico'
  },
  'type': {'zh': '类型', 'en': 'Type', 'ja': '種類', 'ko': '유형', 'es': 'Tipo'},
  'realtime': {
    'zh': '实时流量速度显示',
    'en': 'Live traffic speed',
    'ja': 'リアルタイム通信速度',
    'ko': '실시간 트래픽 속도',
    'es': 'Velocidad de trafico en vivo'
  },
  'trafficStats': {
    'zh': '流量用量统计',
    'en': 'Traffic usage statistics',
    'ja': '通信量統計',
    'ko': '트래픽 사용량 통계',
    'es': 'Estadisticas de uso'
  },
  'localLogs': {
    'zh': '连接日志本地保存',
    'en': 'Save connection logs locally',
    'ja': '接続ログをローカル保存',
    'ko': '연결 로그 로컬 저장',
    'es': 'Guardar registros localmente'
  },
  'socks': {
    'zh': '本地 SOCKS5 代理',
    'en': 'Local SOCKS5 proxy',
    'ja': 'ローカル SOCKS5 プロキシ',
    'ko': '로컬 SOCKS5 프록시',
    'es': 'Proxy SOCKS5 local'
  },
  'http': {
    'zh': '本地 HTTP 代理',
    'en': 'Local HTTP proxy',
    'ja': 'ローカル HTTP プロキシ',
    'ko': '로컬 HTTP 프록시',
    'es': 'Proxy HTTP local'
  },
  'tun': {
    'zh': 'TUN 模式',
    'en': 'TUN mode',
    'ja': 'TUN モード',
    'ko': 'TUN 모드',
    'es': 'Modo TUN'
  },
  'fakeIp': {
    'zh': 'Fake-IP 模式',
    'en': 'Fake-IP mode',
    'ja': 'Fake-IP モード',
    'ko': 'Fake-IP 모드',
    'es': 'Modo Fake-IP'
  },
  'mtu': {
    'zh': 'MTU 设置',
    'en': 'MTU',
    'ja': 'MTU 設定',
    'ko': 'MTU 설정',
    'es': 'MTU'
  },
  'config': {
    'zh': '配置文件导入导出',
    'en': 'Import or export configuration',
    'ja': '設定のインポート / エクスポート',
    'ko': '구성 가져오기 / 내보내기',
    'es': 'Importar o exportar configuracion'
  },
  'subscription': {
    'zh': '订阅链接导入',
    'en': 'Import subscription URL',
    'ja': '購読 URL をインポート',
    'ko': '구독 URL 가져오기',
    'es': 'Importar URL de suscripcion'
  },
  'controller': {
    'zh': '外部控制器',
    'en': 'External controller',
    'ja': '外部コントローラー',
    'ko': '외부 컨트롤러',
    'es': 'Controlador externo'
  },
  'adDns': {
    'zh': '广告过滤 DNS',
    'en': 'Ad-blocking DNS',
    'ja': '広告ブロック DNS',
    'ko': '광고 차단 DNS',
    'es': 'DNS con bloqueo de anuncios'
  },
  'ipLeak': {
    'zh': 'IP 泄漏检测',
    'en': 'IP leak test',
    'ja': 'IP リークテスト',
    'ko': 'IP 유출 테스트',
    'es': 'Prueba de fuga IP'
  },
  'run': {
    'zh': '点击执行',
    'en': 'Tap to run',
    'ja': 'タップして実行',
    'ko': '탭하여 실행',
    'es': 'Toca para ejecutar'
  },
  'devices': {
    'zh': '多设备管理',
    'en': 'Multi-device management',
    'ja': '複数デバイス管理',
    'ko': '다중 기기 관리',
    'es': 'Gestion multidispositivo'
  },
  'deviceList': {
    'zh': '设备列表',
    'en': 'Device list',
    'ja': 'デバイス一覧',
    'ko': '기기 목록',
    'es': 'Lista de dispositivos'
  },
  'notification': {
    'zh': '通知栏快捷控制',
    'en': 'Notification quick controls',
    'ja': '通知クイック操作',
    'ko': '알림 빠른 제어',
    'es': 'Controles rapidos de notificacion'
  },
  'demo': {
    'zh': '演示模式',
    'en': 'Demo mode',
    'ja': 'デモモード',
    'ko': '데모 모드',
    'es': 'Modo de demostracion'
  },
  'port': {'zh': '端口', 'en': 'Port', 'ja': 'ポート', 'ko': '포트', 'es': 'Puerto'},
  'chooseFile': {
    'zh': '选择文件',
    'en': 'Choose file',
    'ja': 'ファイルを選択',
    'ko': '파일 선택',
    'es': 'Elegir archivo'
  },
  'invalidFile': {
    'zh': '文件格式不符合要求',
    'en': 'Unsupported file format',
    'ja': '未対応のファイル形式です',
    'ko': '지원되지 않는 파일 형식입니다',
    'es': 'Formato de archivo no compatible'
  },
  'invalidUrl': {
    'zh': '请输入有效 HTTP/HTTPS URL',
    'en': 'Enter a valid HTTP/HTTPS URL',
    'ja': '有効な HTTP/HTTPS URL を入力してください',
    'ko': '유효한 HTTP/HTTPS URL을 입력하세요',
    'es': 'Introduce una URL HTTP/HTTPS valida'
  },
  'invalidHttps': {
    'zh': '请输入有效 HTTPS URL',
    'en': 'Enter a valid HTTPS URL',
    'ja': '有効な HTTPS URL を入力してください',
    'ko': '유효한 HTTPS URL을 입력하세요',
    'es': 'Introduce una URL HTTPS valida'
  },
  'invalidIp': {
    'zh': '请输入有效 IP 地址',
    'en': 'Enter a valid IP address',
    'ja': '有効な IP アドレスを入力してください',
    'ko': '유효한 IP 주소를 입력하세요',
    'es': 'Introduce una direccion IP valida'
  },
  'range': {
    'zh': '请输入',
    'en': 'Enter',
    'ja': '入力範囲:',
    'ko': '입력 범위:',
    'es': 'Introduce'
  },
  'cancel': {
    'zh': '取消',
    'en': 'Cancel',
    'ja': 'キャンセル',
    'ko': '취소',
    'es': 'Cancelar'
  },
  'save': {'zh': '保存', 'en': 'Save', 'ja': '保存', 'ko': '저장', 'es': 'Guardar'},
};
