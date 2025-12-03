import Foundation
import CoreLocation

// MARK: - GeoIP Models

struct GeoIPLocation: Codable, Identifiable {
    var id: String { ip }
    let ip: String
    let status: String
    let country: String?
    let countryCode: String?
    let region: String?
    let regionName: String?
    let city: String?
    let lat: Double?
    let lon: Double?
    let isp: String?
    let org: String?
    let asName: String?

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = lat, let lon = lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var displayLocation: String {
        [city, regionName, country].compactMap { $0 }.joined(separator: ", ")
    }

    var isSuccess: Bool {
        status == "success"
    }

    enum CodingKeys: String, CodingKey {
        case ip = "query"
        case status
        case country
        case countryCode
        case region
        case regionName
        case city
        case lat
        case lon
        case isp
        case org
        case asName = "as"
    }
}

struct GeoTracerouteHop: Identifiable {
    let id = UUID()
    let hopNumber: Int
    let hostname: String?
    let ip: String?
    let rtts: [Double]
    let timedOut: Bool
    let isLast: Bool
    var location: GeoIPLocation?

    init(from hop: TracerouteHop, location: GeoIPLocation? = nil) {
        self.hopNumber = hop.hopNumber
        self.hostname = hop.hostname
        self.ip = hop.ip
        self.rtts = hop.rtts
        self.timedOut = hop.timedOut
        self.isLast = hop.isLast
        self.location = location
    }

    var coordinate: CLLocationCoordinate2D? {
        location?.coordinate
    }

    var displayName: String {
        hostname ?? ip ?? "Hop \(hopNumber)"
    }

    var avgRTT: Double? {
        guard !rtts.isEmpty else { return nil }
        return rtts.reduce(0, +) / Double(rtts.count)
    }
}

// MARK: - GeoIP Service

@MainActor
class GeoIPService: ObservableObject {
    @Published var geoHops: [GeoTracerouteHop] = []
    @Published var isLoading = false
    @Published var error: String?

    private let baseURL = "http://ip-api.com/json/"
    private var cache: [String: GeoIPLocation] = [:]

    /// Look up geolocation for all hops from a traceroute
    func lookupHops(_ hops: [TracerouteHop]) async {
        isLoading = true
        error = nil
        geoHops = hops.map { GeoTracerouteHop(from: $0) }

        // Collect unique IPs to look up
        let ipsToLookup = hops.compactMap { $0.ip }.filter { !isPrivateIP($0) }
        let uniqueIPs = Array(Set(ipsToLookup))

        // Look up each IP (with rate limiting - ip-api.com allows 45 requests/minute)
        for ip in uniqueIPs {
            if let cached = cache[ip] {
                updateHopsWithLocation(ip: ip, location: cached)
                continue
            }

            do {
                let location = try await lookupIP(ip)
                cache[ip] = location
                updateHopsWithLocation(ip: ip, location: location)

                // Rate limit: wait 100ms between requests
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                // Continue with other IPs if one fails
                print("GeoIP lookup failed for \(ip): \(error)")
            }
        }

        isLoading = false
    }

    /// Look up a single IP address
    func lookupIP(_ ip: String) async throws -> GeoIPLocation {
        guard let url = URL(string: "\(baseURL)\(ip)?fields=status,country,countryCode,region,regionName,city,lat,lon,isp,org,as,query") else {
            throw GeoIPError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GeoIPError.requestFailed
        }

        let location = try JSONDecoder().decode(GeoIPLocation.self, from: data)

        if !location.isSuccess {
            throw GeoIPError.lookupFailed(ip)
        }

        return location
    }

    private func updateHopsWithLocation(ip: String, location: GeoIPLocation) {
        for i in geoHops.indices {
            if geoHops[i].ip == ip {
                geoHops[i].location = location
            }
        }
    }

    /// Check if IP is private/local (not routable on internet)
    private func isPrivateIP(_ ip: String) -> Bool {
        // IPv4 private ranges
        if ip.hasPrefix("10.") ||
           ip.hasPrefix("172.16.") || ip.hasPrefix("172.17.") || ip.hasPrefix("172.18.") ||
           ip.hasPrefix("172.19.") || ip.hasPrefix("172.20.") || ip.hasPrefix("172.21.") ||
           ip.hasPrefix("172.22.") || ip.hasPrefix("172.23.") || ip.hasPrefix("172.24.") ||
           ip.hasPrefix("172.25.") || ip.hasPrefix("172.26.") || ip.hasPrefix("172.27.") ||
           ip.hasPrefix("172.28.") || ip.hasPrefix("172.29.") || ip.hasPrefix("172.30.") ||
           ip.hasPrefix("172.31.") ||
           ip.hasPrefix("192.168.") ||
           ip.hasPrefix("127.") ||
           ip.hasPrefix("169.254.") {
            return true
        }

        // IPv6 link-local and private
        if ip.hasPrefix("fe80:") || ip.hasPrefix("fc") || ip.hasPrefix("fd") || ip == "::1" {
            return true
        }

        return false
    }
}

enum GeoIPError: LocalizedError {
    case invalidURL
    case requestFailed
    case lookupFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .requestFailed: return "Request failed"
        case .lookupFailed(let ip): return "Lookup failed for \(ip)"
        }
    }
}
