import Foundation

/// Somewhere to go, for the date planner's design build.
///
/// **Parks, museums and libraries are real places; every café, bar, studio and
/// restaurant is invented.** A public park's location is a fact anybody can
/// check, so putting it in is harmless. A business's hours, prices and continued
/// existence are not, and a planner that sent two people to a real café that
/// closed in the spring would be the app being wrong about the one thing it
/// promised to get right. The invented ones sit in real neighbourhoods so the
/// distances are honest, and none of them shares a name with anywhere real that
/// I know of.
///
/// The live version wants a provider -- MapKit's point-of-interest search is the
/// one that needs no key and no contract -- feeding the same `Venue` type, so
/// nothing in `DatePlanner` changes when it arrives.
enum VenueLibrary {

    static let all: [Venue] = [

        // MARK: Outside

        venue("fort-greene-park", "Fort Greene Park", .park, "Fort Greene", 40.6914, -73.9757,
              [.outdoors], [.afternoon], [.opener, .main]),
        venue("prospect-long-meadow", "Prospect Park, the Long Meadow", .walk, "Prospect Park", 40.6650, -73.9700,
              [.outdoors], [.afternoon], [.opener, .main]),
        venue("botanic-garden", "Brooklyn Botanic Garden", .park, "Prospect Heights", 40.6694, -73.9624,
              [.outdoors], [.afternoon], [.main]),
        venue("bridge-park-pier-1", "Brooklyn Bridge Park, Pier 1", .walk, "Dumbo", 40.7020, -73.9965,
              [.outdoors, .buildings], [.afternoon, .evening], [.opener, .main]),
        venue("domino-park", "Domino Park", .walk, "Williamsburg", 40.7145, -73.9682,
              [.outdoors, .buildings], [.afternoon, .evening], [.opener, .main]),
        venue("mccarren-park", "McCarren Park", .park, "Greenpoint", 40.7203, -73.9516,
              [.outdoors], [.afternoon], [.opener]),
        venue("green-wood", "Green-Wood Cemetery", .walk, "Sunset Park", 40.6522, -73.9910,
              [.outdoors, .buildings, .words], [.afternoon], [.main]),

        // MARK: Looking at things

        venue("brooklyn-museum", "Brooklyn Museum", .museum, "Prospect Heights", 40.6712, -73.9636,
              [.craft, .buildings], [.afternoon], [.main]),
        venue("central-library", "Brooklyn Public Library, Central", .library, "Prospect Heights", 40.6725, -73.9682,
              [.words, .buildings], [.afternoon], [.opener, .main]),
        venue("bam", "BAM", .listening, "Fort Greene", 40.6865, -73.9776,
              [.sound, .words], [.evening], [.main]),
        venue("pioneer-works", "Pioneer Works", .studio, "Red Hook", 40.6786, -74.0118,
              [.craft, .sound], [.afternoon, .evening], [.main]),

        // MARK: Invented -- coffee, shops, studios

        venue("lowlight-coffee", "Lowlight Coffee", .coffee, "Fort Greene", 40.6889, -73.9725,
              [.food, .night], [.afternoon, .evening], [.opener]),
        venue("half-measure", "Half Measure Café", .coffee, "Prospect Heights", 40.6770, -73.9660,
              [.food, .words], [.afternoon], [.opener]),
        venue("paper-thread", "Paper & Thread", .shop, "Park Slope", 40.6735, -73.9800,
              [.words, .craft], [.afternoon], [.opener]),
        venue("silver-bath", "Silver Bath Darkroom", .studio, "Gowanus", 40.6760, -73.9880,
              [.craft], [.afternoon], [.main]),
        venue("short-fuse", "Short Fuse Coffee", .coffee, "Williamsburg", 40.7160, -73.9590,
              [.food], [.afternoon, .evening], [.opener]),
        venue("corner-booth", "Corner Booth", .coffee, "Crown Heights", 40.6705, -73.9480,
              [.food, .words], [.afternoon, .evening], [.opener]),
        venue("tidewater", "Tidewater", .bar, "Dumbo", 40.7030, -73.9890,
              [.food, .night], [.evening], [.opener, .closer]),
        venue("bright-lines", "Bright Lines Books", .shop, "Greenpoint", 40.7290, -73.9540,
              [.words], [.afternoon], [.opener]),
        venue("rooftop-records", "Second Pressing Records", .shop, "Williamsburg", 40.7150, -73.9600,
              [.sound], [.afternoon], [.opener, .main]),

        // MARK: Invented -- to finish

        venue("listening-room", "The Listening Room", .listening, "Clinton Hill", 40.6880, -73.9640,
              [.sound, .night], [.evening], [.main, .closer]),
        venue("felt-hammer", "Felt & Hammer", .bar, "Prospect Heights", 40.6790, -73.9700,
              [.sound, .night], [.evening], [.closer]),
        venue("small-hours", "Small Hours", .bar, "Bed-Stuy", 40.6850, -73.9450,
              [.night, .sound], [.evening], [.closer]),
        venue("night-oven", "Night Oven", .food, "Crown Heights", 40.6700, -73.9500,
              [.food, .night], [.evening], [.closer]),
        venue("corner-table", "Corner Table", .food, "Fort Greene", 40.6880, -73.9760,
              [.food], [.afternoon, .evening], [.closer]),
        venue("saltbox", "Saltbox", .food, "Prospect Heights", 40.6765, -73.9635,
              [.food], [.afternoon, .evening], [.closer]),
        venue("wide-bowl", "Wide Bowl Noodles", .food, "Williamsburg", 40.7135, -73.9620,
              [.food], [.afternoon, .evening], [.closer]),
        venue("tin-roof", "Tin Roof Dumplings", .food, "Sunset Park", 40.6450, -74.0110,
              [.food], [.afternoon, .evening], [.closer]),
        venue("platform-diner", "Platform Diner", .food, "Bushwick", 40.6990, -73.9230,
              [.food, .buildings, .night], [.afternoon, .evening], [.closer]),
        venue("slope-wine", "Long Pour", .bar, "Park Slope", 40.6725, -73.9775,
              [.food, .words], [.evening], [.closer]),
    ]

    private static func venue(
        _ id: String, _ name: String, _ kind: Venue.Kind, _ neighbourhood: String,
        _ latitude: Double, _ longitude: Double,
        _ themes: Set<DateTheme>, _ times: Set<DatePlan.TimeOfDay>, _ roles: Set<DatePlan.Role>
    ) -> Venue {
        Venue(id: id, name: name, kind: kind, neighbourhood: neighbourhood,
              coordinate: Coordinate(latitude: latitude, longitude: longitude),
              themes: themes, times: times, roles: roles)
    }
}
