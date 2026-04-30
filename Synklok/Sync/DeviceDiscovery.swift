import Foundation
import Network

@MainActor
@Observable
final class DeviceDiscovery {
    var discoveredHosts: [String] = []
    var isBrowsing: Bool = false

    private var browser: NWBrowser?

    /// Browse for `_http._tcp` services and surface ones that look like RME gear.
    func start() {
        guard browser == nil else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = false

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_http._tcp", domain: nil)
        let b = NWBrowser(for: descriptor, using: parameters)

        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                self.discoveredHosts = results.compactMap { result in
                    if case .service(let name, _, _, _) = result.endpoint {
                        let lower = name.lowercased()
                        if lower.contains("rme") ||
                           lower.contains("m-1620") ||
                           lower.contains("m1620") ||
                           lower.contains("madi") {
                            // Resolve to <name>.local (mDNS) — usable as a host string.
                            return "\(name).local"
                        }
                    }
                    return nil
                }
            }
        }

        b.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:  self.isBrowsing = true
                case .failed, .cancelled: self.isBrowsing = false
                default: break
                }
            }
        }

        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
    }
}
