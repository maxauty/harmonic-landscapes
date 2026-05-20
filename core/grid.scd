// =============================================================================
// core/grid.scd — Geometric and harmonic substrate
//
// Constructs the toroidal hex grid that agents traverse, and defines the
// musical material the grid is interpreted through:
//   ~grid             — a ToroidalHexManifold instance (Tonnetz-tuned)
//   ~modeCollections  — pitch-class sets for each supported mode
//   ~modeNames        — ordered mode list (used by GUI selectors)
//   ~modeHomeTriad    — tonic triad of each mode, as intervals from tonic
//
// The class ToroidalHexManifold lives in a separate .sc file installed into
// Platform.userExtensionDir and compiled with the class library.
// =============================================================================

(

// --- Grid -------------------------------------------------------------------

~grid = ToroidalHexManifold(24, 12, 12, 7, 4);


// --- Mode collections -------------------------------------------------------
// Pitch-class sets for each mode, expressed relative to a tonic of 0.
// Actual pitch classes at runtime are computed as (mode + tonicPC).mod(12).

~modeCollections = (
    major:         [0, 2, 4, 5, 7, 9, 11],
    minor:         [0, 2, 3, 5, 7, 8, 10],
    dorian:        [0, 2, 3, 5, 7, 9, 10],
    phrygian:      [0, 1, 3, 5, 7, 8, 10],
    lydian:        [0, 2, 4, 6, 7, 9, 11],
    mixolydian:    [0, 2, 4, 5, 7, 9, 10],
    locrian:       [0, 1, 3, 5, 6, 8, 10],
    harmonicMinor: [0, 2, 3, 5, 7, 8, 11],
    melodicMinor:  [0, 2, 3, 5, 7, 9, 11],
    hexatonic:     [0, 3, 4, 7, 8, 11],
    octatonic:     [0, 1, 3, 4, 6, 7, 9, 10],
    chromatic:     [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
);

~modeNames = [
    "major", "minor", "dorian", "phrygian", "lydian", "mixolydian", "locrian",
    "harmonicMinor", "melodicMinor", "hexatonic", "octatonic", "chromatic"
];


// --- Mode home triads -------------------------------------------------------
// Tonic triad for each mode, derived from the triad on scale degree I.
// Major-quality modes use [0, 4, 7]; minor-quality modes use [0, 3, 7];
// locrian uses the diminished triad [0, 3, 6].
// Expressed as intervals from tonic — actual PCs computed at spawn from tonicPC.

~modeHomeTriad = (
    major:         [0, 4, 7],
    minor:         [0, 3, 7],
    dorian:        [0, 3, 7],
    phrygian:      [0, 3, 7],
    lydian:        [0, 4, 7],
    mixolydian:    [0, 4, 7],
    locrian:       [0, 3, 6],
    harmonicMinor: [0, 3, 7],
    melodicMinor:  [0, 3, 7],
    hexatonic:     [0, 4, 7],
    octatonic:     [0, 3, 7],
    chromatic:     [0, 4, 7]
);

)
