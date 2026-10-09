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
/// **Some are shut on some days**, so that picking a day changes the plan. For
/// the real places that is when they say they are closed as this is written --
/// the museum on Mondays and Tuesdays, the garden on Mondays; for the invented
/// ones it is invented. A live provider brings real opening hours instead.
///
/// The live version wants a provider -- MapKit's point-of-interest search is the
/// one that needs no key and no contract -- feeding the same `Venue` type, so
/// nothing in `DatePlanner` changes when it arrives.
enum VenueLibrary {

    static let all: [Venue] = [

        // MARK: Outside

        venue("fort-greene-park", "Fort Greene Park", .park, "Fort Greene", 40.6914, -73.9757,
              [.outdoors], [.afternoon]),
        venue("prospect-long-meadow", "Prospect Park, the Long Meadow", .walk, "Prospect Park", 40.6650, -73.9700,
              [.outdoors], [.afternoon]),
        venue("botanic-garden", "Brooklyn Botanic Garden", .park, "Prospect Heights", 40.6694, -73.9624,
              [.outdoors], [.afternoon], closed: [monday]),
        venue("bridge-park-pier-1", "Brooklyn Bridge Park, Pier 1", .walk, "Dumbo", 40.7020, -73.9965,
              [.outdoors, .buildings], [.afternoon, .evening]),
        venue("domino-park", "Domino Park", .walk, "Williamsburg", 40.7145, -73.9682,
              [.outdoors, .buildings], [.afternoon, .evening]),
        venue("mccarren-park", "McCarren Park", .park, "Greenpoint", 40.7203, -73.9516,
              [.outdoors], [.afternoon]),
        venue("green-wood", "Green-Wood Cemetery", .walk, "Sunset Park", 40.6522, -73.9910,
              [.outdoors, .buildings, .words], [.afternoon]),

        // MARK: Looking at things

        venue("brooklyn-museum", "Brooklyn Museum", .museum, "Prospect Heights", 40.6712, -73.9636,
              [.craft, .buildings], [.afternoon], closed: [monday, tuesday]),
        venue("central-library", "Brooklyn Public Library, Central", .library, "Prospect Heights", 40.6725, -73.9682,
              [.words, .buildings], [.afternoon]),
        venue("bam", "BAM", .show, "Fort Greene", 40.6865, -73.9776,
              [.sound, .words], [.evening]),
        venue("pioneer-works", "Pioneer Works", .studio, "Red Hook", 40.6786, -74.0118,
              [.craft, .sound], [.afternoon, .evening]),

        // MARK: Invented -- coffee, shops, studios

        venue("lowlight-coffee", "Lowlight Coffee", .coffee, "Fort Greene", 40.6889, -73.9725,
              [.food, .night], [.afternoon, .evening]),
        venue("half-measure", "Half Measure Café", .coffee, "Prospect Heights", 40.6770, -73.9660,
              [.food, .words], [.afternoon]),
        venue("paper-thread", "Paper & Thread", .shop, "Park Slope", 40.6735, -73.9800,
              [.words, .craft], [.afternoon]),
        venue("silver-bath", "Silver Bath Darkroom", .studio, "Gowanus", 40.6760, -73.9880,
              [.craft], [.afternoon], closed: [monday, tuesday]),
        venue("short-fuse", "Short Fuse Coffee", .coffee, "Williamsburg", 40.7160, -73.9590,
              [.food], [.afternoon, .evening]),
        venue("corner-booth", "Corner Booth", .coffee, "Crown Heights", 40.6705, -73.9480,
              [.food, .words], [.afternoon, .evening]),
        venue("tidewater", "Tidewater", .bar, "Dumbo", 40.7030, -73.9890,
              [.food, .night], [.evening]),
        venue("bright-lines", "Bright Lines Books", .shop, "Greenpoint", 40.7290, -73.9540,
              [.words], [.afternoon]),
        venue("rooftop-records", "Second Pressing Records", .shop, "Williamsburg", 40.7150, -73.9600,
              [.sound], [.afternoon]),

        // MARK: Invented -- to finish

        venue("listening-room", "The Listening Room", .listening, "Clinton Hill", 40.6880, -73.9640,
              [.sound, .night], [.evening], closed: [sunday, monday]),
        venue("felt-hammer", "Felt & Hammer", .bar, "Prospect Heights", 40.6790, -73.9700,
              [.sound, .night], [.evening], closed: [monday]),
        venue("small-hours", "Small Hours", .bar, "Bed-Stuy", 40.6850, -73.9450,
              [.night, .sound], [.evening]),
        venue("night-oven", "Night Oven", .food, "Crown Heights", 40.6700, -73.9500,
              [.food, .night], [.evening], closed: [sunday]),
        venue("corner-table", "Corner Table", .food, "Fort Greene", 40.6880, -73.9760,
              [.food], [.afternoon, .evening]),
        venue("saltbox", "Saltbox", .food, "Prospect Heights", 40.6765, -73.9635,
              [.food], [.afternoon, .evening]),
        venue("wide-bowl", "Wide Bowl Noodles", .food, "Williamsburg", 40.7135, -73.9620,
              [.food], [.afternoon, .evening]),
        venue("tin-roof", "Tin Roof Dumplings", .food, "Sunset Park", 40.6450, -74.0110,
              [.food], [.afternoon, .evening]),
        venue("platform-diner", "Platform Diner", .food, "Bushwick", 40.6990, -73.9230,
              [.food, .buildings, .night], [.afternoon, .evening]),
        venue("slope-wine", "Long Pour", .bar, "Park Slope", 40.6725, -73.9775,
              [.food, .words], [.evening]),

        // MARK: Invented -- so a Swap has somewhere to go
        //
        // Added where a main thing had one place beside it: under "keep it
        // walkable", Domino Park had a single café and a single restaurant in
        // reach, and the stops either side of it could not be swapped at all.

        venue("slack-water", "Slack Water Coffee", .coffee, "Williamsburg", 40.7122, -73.9662,
              [.food], [.afternoon, .evening]),
        venue("little-ladle", "Little Ladle", .food, "Williamsburg", 40.7171, -73.9601,
              [.food], [.afternoon, .evening]),
        venue("ferry-light", "Ferry Light Pizza", .food, "Williamsburg", 40.7103, -73.9638,
              [.food, .night], [.afternoon, .evening]),
        venue("night-kettle", "Night Kettle", .coffee, "Fort Greene", 40.6872, -73.9748,
              [.food, .night], [.evening]),
        venue("gatehouse-kitchen", "Gatehouse Kitchen", .food, "Prospect Heights", 40.6738, -73.9612,
              [.food], [.afternoon, .evening]),
        venue("meadow-edge", "Meadow Edge", .food, "Park Slope", 40.6668, -73.9752,
              [.food], [.afternoon, .evening]),
        venue("quiet-hours", "Quiet Hours Tea", .coffee, "Clinton Hill", 40.6893, -73.9658,
              [.food, .words], [.afternoon, .evening]),

        // MARK: Something to do after dark
        //
        // A plan can hold three activities now, and an evening had five in the
        // whole library, a long way apart: two activities on a walkable
        // evening put a train in the plan more often than not.

        venue("main-street-park", "Main Street Park", .walk, "Dumbo", 40.7040, -73.9900,
              [.outdoors, .buildings], [.afternoon, .evening]),
        venue("little-reel", "Little Reel Cinema", .show, "Williamsburg", 40.7158, -73.9628,
              [.words, .sound], [.evening]),
        venue("back-room-comedy", "Back Room Comedy", .show, "Fort Greene", 40.6893, -73.9762,
              [.words, .night], [.evening]),
        venue("clay-hours", "Clay Hours", .studio, "Prospect Heights", 40.6778, -73.9672,
              [.craft], [.afternoon, .evening]),
    ]

    // `Calendar`'s numbering.
    private static let sunday = 1, monday = 2, tuesday = 3

    private static func venue(
        _ id: String, _ name: String, _ kind: Venue.Kind, _ neighbourhood: String,
        _ latitude: Double, _ longitude: Double,
        _ themes: Set<DateTheme>, _ times: Set<DatePlan.TimeOfDay>,
        closed: Set<Int> = []
    ) -> Venue {
        Venue(id: id, name: name, kind: kind, neighbourhood: neighbourhood,
              coordinate: Coordinate(latitude: latitude, longitude: longitude),
              themes: themes, times: times, closedOn: closed)
    }
}
