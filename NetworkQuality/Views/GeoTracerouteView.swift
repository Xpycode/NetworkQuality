import SwiftUI
import MapKit

// MARK: - Geographic Traceroute View

struct GeoTracerouteView: View {
    @StateObject private var tracerouteService = TracerouteService()
    @StateObject private var geoService = GeoIPService()
    @State private var targetHost = ""
    @State private var selectedHop: GeoTracerouteHop?
    @State private var mapPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.0, longitude: -95.0),
        span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 60)
    ))

    var body: some View {
        HSplitView {
            // Left panel: Controls and hop list
            leftPanel
                .frame(minWidth: 280, maxWidth: 350)

            // Right panel: Map
            mapPanel
        }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "map.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    Text("Route Visualization")
                        .font(.headline)
                }

                // Host input
                HStack {
                    TextField("Host or IP", text: $targetHost)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { startTrace() }

                    Button(action: startTrace) {
                        Image(systemName: tracerouteService.isRunning ? "stop.fill" : "play.fill")
                    }
                    .disabled(targetHost.isEmpty)
                }

                if tracerouteService.isRunning || geoService.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(geoService.isLoading ? "Looking up locations..." : "Tracing route...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()

            Divider()

            // Hop list
            if geoService.geoHops.isEmpty && !tracerouteService.isRunning {
                emptyState
            } else {
                hopList
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "globe.americas")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Enter a host to trace")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("See the geographic path your packets travel")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var hopList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(geoService.geoHops) { hop in
                    HopRow(hop: hop, isSelected: selectedHop?.id == hop.id)
                        .onTapGesture {
                            selectHop(hop)
                        }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Map Panel

    private var mapPanel: some View {
        Map(position: $mapPosition) {
            ForEach(hopsWithCoordinates) { hop in
                Annotation(hop.displayName, coordinate: hop.coordinate!) {
                    HopMarker(hop: hop, isSelected: selectedHop?.id == hop.id)
                        .onTapGesture {
                            selectHop(hop)
                        }
                }
                .annotationTitles(.hidden)
            }
        }
        .overlay(alignment: .topTrailing) {
            mapLegend
                .padding()
        }
    }

    private var mapLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Route Path")
                .font(.caption.bold())

            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Start")
                    .font(.caption2)
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(.blue)
                    .frame(width: 8, height: 8)
                Text("Hop")
                    .font(.caption2)
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("Destination")
                    .font(.caption2)
            }

            if let count = hopsWithCoordinates.count as Int?, count > 0 {
                Divider()
                Text("\(count) located hops")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private var hopsWithCoordinates: [GeoTracerouteHop] {
        geoService.geoHops.filter { $0.coordinate != nil }
    }

    private func startTrace() {
        guard !targetHost.isEmpty else { return }

        if tracerouteService.isRunning {
            tracerouteService.stop()
            return
        }

        selectedHop = nil
        geoService.geoHops = []
        tracerouteService.trace(host: targetHost)

        // Watch for traceroute completion
        Task {
            // Wait for traceroute to finish
            while tracerouteService.isRunning {
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            // Then look up geolocation
            await geoService.lookupHops(tracerouteService.hops)

            // Fit map to show all hops
            fitMapToRoute()
        }
    }

    private func selectHop(_ hop: GeoTracerouteHop) {
        selectedHop = hop

        if let coordinate = hop.coordinate {
            withAnimation {
                mapPosition = .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
                ))
            }
        }
    }

    private func fitMapToRoute() {
        let coords = hopsWithCoordinates.compactMap { $0.coordinate }
        guard !coords.isEmpty else { return }

        let lats = coords.map { $0.latitude }
        let lons = coords.map { $0.longitude }

        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 5),
            longitudeDelta: max((maxLon - minLon) * 1.5, 5)
        )

        withAnimation {
            mapPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}

// MARK: - Hop Row

struct HopRow: View {
    let hop: GeoTracerouteHop
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Hop number
            ZStack {
                Circle()
                    .fill(hopColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text("\(hop.hopNumber)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(hopColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                if hop.timedOut {
                    Text("* * *")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Timed out")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(hop.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if let location = hop.location {
                            Text(location.displayLocation)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else if let ip = hop.ip {
                            Text(ip)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if let rtt = hop.avgRTT {
                            Text(String(format: "%.1f ms", rtt))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Spacer()

            if hop.coordinate != nil {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 14))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }

    private var hopColor: Color {
        if hop.hopNumber == 1 {
            return .green
        } else if hop.isLast {
            return .red
        } else {
            return .blue
        }
    }
}

// MARK: - Hop Marker

struct HopMarker: View {
    let hop: GeoTracerouteHop
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(markerColor)
                    .frame(width: isSelected ? 24 : 18, height: isSelected ? 24 : 18)
                    .shadow(radius: 2)

                Text("\(hop.hopNumber)")
                    .font(.system(size: isSelected ? 11 : 9, weight: .bold))
                    .foregroundStyle(.white)
            }

            if isSelected {
                Text(hop.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private var markerColor: Color {
        if hop.hopNumber == 1 {
            return .green
        } else if hop.isLast {
            return .red
        } else {
            return .blue
        }
    }
}

// MARK: - Preview

#Preview {
    GeoTracerouteView()
        .frame(width: 900, height: 600)
}
