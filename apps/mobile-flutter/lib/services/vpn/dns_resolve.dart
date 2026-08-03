import 'dns_resolve_stub.dart' if (dart.library.io) 'dns_resolve_io.dart'
    as impl;

Future<Set<String>> resolveDomainToIpv4(String domain) =>
    impl.resolveDomainToIpv4(domain);
