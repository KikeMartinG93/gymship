import Foundation
import MapKit
import CoreLocation

/// Geocodes typed addresses and calculates driving ETAs between points.
/// Forward geocoding a typed address doesn't require any location
/// permission, so this needs no entitlement beyond network access.
enum ETACalculator {
    /// Resolves a free-text address to a coordinate.
    static func geocode(address: String) async throws -> CLLocationCoordinate2D {
        guard let request = MKGeocodingRequest(addressString: address) else {
            throw ETAError.addressNotFound
        }
        let items = try await request.mapItems
        guard let coordinate = items.first?.location.coordinate else {
            throw ETAError.addressNotFound
        }
        return coordinate
    }

    /// Expected driving travel time between two points.
    static func travelTime(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> TimeInterval {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: origin.latitude, longitude: origin.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
        request.transportType = .automobile
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else {
            throw ETAError.noRouteFound
        }
        return route.expectedTravelTime
    }

    enum ETAError: LocalizedError {
        case addressNotFound
        case noRouteFound

        var errorDescription: String? {
            switch self {
            case .addressNotFound: return String(localized: "Couldn't find that address.")
            case .noRouteFound: return String(localized: "Couldn't calculate a driving route.")
            }
        }
    }
}
