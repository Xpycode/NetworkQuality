import Foundation
import CoreLocation

// MARK: - GeoIP Models

struct GeoIPLocation: Codable, Identifiable, Sendable {
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

struct GeoTracerouteHop: Identifiable, Sendable {
    let id: UUID
    let hopNumber: Int
    let hostname: String?
    let ip: String?
    let rtts: [Double]
    let timedOut: Bool
    let isLast: Bool
    var location: GeoIPLocation?

    init(from hop: TracerouteHop, location: GeoIPLocation? = nil) {
        self.id = UUID()
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

// MARK: - GeoIP Rate Limiter

/// Actor-based rate limiter for GeoIP API requests
/// ip-api.com allows 45 requests per minute for free tier
actor GeoIPRateLimiter {
    private let maxRequestsPerMinute: Int
    private let minimumInterval: TimeInterval
    private var requestTimestamps: [Date] = []
    private var lastRequestTime: Date?

    init(maxRequestsPerMinute: Int = 45) {
        self.maxRequestsPerMinute = maxRequestsPerMinute
        self.minimumInterval = 60.0 / Double(maxRequestsPerMinute) // ~1.33 seconds between requests
    }

    /// Wait if necessary to respect rate limits, returns true if request can proceed
    func waitForSlot() async -> Bool {
        // Clean up old timestamps (older than 1 minute)
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        requestTimestamps.removeAll { $0 < oneMinuteAgo }

        // Check if we're at the limit
        if requestTimestamps.count >= maxRequestsPerMinute {
            // Calculate wait time until oldest request expires
            if let oldest = requestTimestamps.first {
                let waitTime = oldest.timeIntervalSince(oneMinuteAgo)
                if waitTime > 0 {
                    NetworkQualityLogger.geoIP.debug("Rate limit reached, waiting \(waitTime) seconds")
                    try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                }
            }
        }

        // Ensure minimum interval between requests
        if let lastTime = lastRequestTime {
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed < minimumInterval {
                let waitTime = minimumInterval - elapsed
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }

        // Record this request
        requestTimestamps.append(Date())
        lastRequestTime = Date()

        return true
    }

    func reset() {
        requestTimestamps.removeAll()
        lastRequestTime = nil
    }
}

// MARK: - GeoIP Service

@MainActor
class GeoIPService: ObservableObject {
    @Published var geoHops: [GeoTracerouteHop] = []
    @Published var isLoading = false
    @Published var error: String?

    // Using ip-api.com with HTTPS (Pro endpoint)
    // Note: Free tier only supports HTTP. For production, consider:
    // - ip-api.com Pro (HTTPS): Requires API key
    // - ipinfo.io (HTTPS): Free tier available
    // - ipgeolocation.io (HTTPS): Free tier available
    //
    // For this implementation, we use ipinfo.io as it provides HTTPS for free
    private let baseURL = "https://ipinfo.io"
    private var cache: [String: GeoIPLocation] = [:]
    private let rateLimiter = GeoIPRateLimiter(maxRequestsPerMinute: 45)

    /// Look up geolocation for all hops from a traceroute
    func lookupHops(_ hops: [TracerouteHop]) async {
        isLoading = true
        error = nil
        geoHops = hops.map { GeoTracerouteHop(from: $0) }

        // Collect unique IPs to look up
        let ipsToLookup = hops.compactMap { $0.ip }.filter { !isPrivateIP($0) }
        let uniqueIPs = Array(Set(ipsToLookup))

        NetworkQualityLogger.geoIP.info("Looking up \(uniqueIPs.count) unique IPs")

        // Look up each IP with rate limiting
        for ip in uniqueIPs {
            if Task.isCancelled {
                NetworkQualityLogger.geoIP.debug("GeoIP lookup cancelled")
                break
            }

            if let cached = cache[ip] {
                updateHopsWithLocation(ip: ip, location: cached)
                continue
            }

            do {
                // Wait for rate limiter
                _ = await rateLimiter.waitForSlot()

                let location = try await lookupIP(ip)
                cache[ip] = location
                updateHopsWithLocation(ip: ip, location: location)
            } catch {
                // Continue with other IPs if one fails
                NetworkQualityLogger.geoIP.warning("GeoIP lookup failed for \(ip): \(error.localizedDescription)")
            }
        }

        isLoading = false
    }

    /// Look up a single IP address using ipinfo.io (HTTPS)
    func lookupIP(_ ip: String) async throws -> GeoIPLocation {
        // Validate IP format before making request
        guard isValidIP(ip) else {
            throw GeoIPError.invalidIP(ip)
        }

        guard let url = URL(string: "\(baseURL)/\(ip)/json") else {
            throw GeoIPError.invalidURL
        }

        NetworkQualityLogger.geoIP.debug("Looking up IP: \(ip)")

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeoIPError.requestFailed
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 429:
            throw GeoIPError.rateLimited
        case 400...499:
            throw GeoIPError.lookupFailed(ip)
        default:
            throw GeoIPError.requestFailed
        }

        // Parse ipinfo.io response format
        let ipinfoResponse = try JSONDecoder().decode(IPInfoResponse.self, from: data)

        // Convert to our GeoIPLocation format
        return ipinfoResponse.toGeoIPLocation()
    }

    /// Clear the cache
    func clearCache() {
        cache.removeAll()
        Task {
            await rateLimiter.reset()
        }
    }

    private func updateHopsWithLocation(ip: String, location: GeoIPLocation) {
        for i in geoHops.indices {
            if geoHops[i].ip == ip {
                geoHops[i].location = location
            }
        }
    }

    /// Check if IP is valid format
    private func isValidIP(_ ip: String) -> Bool {
        // IPv4 validation
        let ipv4Pattern = "^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
        if ip.range(of: ipv4Pattern, options: .regularExpression) != nil {
            return true
        }

        // Basic IPv6 validation (simplified)
        if ip.contains(":") && !ip.contains(" ") {
            return true
        }

        return false
    }

    /// Check if IP is private/local (not routable on internet)
    private func isPrivateIP(_ ip: String) -> Bool {
        // IPv4 private ranges
        if ip.hasPrefix("10.") { return true }

        // 172.16.0.0 - 172.31.255.255
        if ip.hasPrefix("172.") {
            let parts = ip.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), second >= 16 && second <= 31 {
                return true
            }
        }

        if ip.hasPrefix("192.168.") { return true }
        if ip.hasPrefix("127.") { return true }
        if ip.hasPrefix("169.254.") { return true }

        // CGNAT range (used by some carriers and Tailscale)
        if ip.hasPrefix("100.64.") || ip.hasPrefix("100.65.") ||
           ip.hasPrefix("100.66.") || ip.hasPrefix("100.67.") ||
           ip.hasPrefix("100.68.") || ip.hasPrefix("100.69.") ||
           ip.hasPrefix("100.7") { // 100.70-100.79, etc through 100.127
            let parts = ip.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), second >= 64 && second <= 127 {
                return true
            }
        }

        // IPv6 private/local ranges
        let ipLower = ip.lowercased()
        if ipLower.hasPrefix("fe80:") { return true }  // Link-local
        if ipLower.hasPrefix("fc") || ipLower.hasPrefix("fd") { return true }  // Unique local
        if ipLower == "::1" { return true }  // Loopback
        if ipLower.hasPrefix("::ffff:") { return true }  // IPv4-mapped

        return false
    }
}

// MARK: - IPInfo.io Response Model

private struct IPInfoResponse: Codable {
    let ip: String
    let hostname: String?
    let city: String?
    let region: String?
    let country: String?
    let loc: String?  // Format: "lat,lon"
    let org: String?
    let postal: String?
    let timezone: String?

    func toGeoIPLocation() -> GeoIPLocation {
        var lat: Double?
        var lon: Double?

        if let loc = loc {
            let coords = loc.split(separator: ",")
            if coords.count == 2 {
                lat = Double(coords[0])
                lon = Double(coords[1])
            }
        }

        // Extract ASN from org (format: "AS12345 Organization Name")
        var asName: String?
        var isp: String?
        if let org = org {
            if org.hasPrefix("AS") {
                asName = org
                // ISP is the part after the AS number
                if let spaceIndex = org.firstIndex(of: " ") {
                    isp = String(org[org.index(after: spaceIndex)...])
                }
            } else {
                isp = org
            }
        }

        return GeoIPLocation(
            ip: ip,
            status: "success",
            country: country,
            countryCode: country,  // ipinfo.io uses 2-letter codes
            region: nil,
            regionName: region,
            city: city,
            lat: lat,
            lon: lon,
            isp: isp,
            org: org,
            asName: asName
        )
    }
}

// MARK: - GeoIP Error

enum GeoIPError: LocalizedError {
    case invalidURL
    case invalidIP(String)
    case requestFailed
    case lookupFailed(String)
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidIP(let ip):
            return "Invalid IP address: \(ip)"
        case .requestFailed:
            return "Request failed"
        case .lookupFailed(let ip):
            return "Lookup failed for \(ip)"
        case .rateLimited:
            return "Rate limit exceeded. Please wait before making more requests."
        }
    }
}
