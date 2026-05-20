// =============================================================================
// PLR Transform Debug — temporary, remove after verification
// =============================================================================

(
~debugPLR = {
    var grid     = ~simulation.grid;
    var agents   = ~simulation[\agents];
    var noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];
	var recent;

    "".postln;
    "=== PLR Transform Debug ===".postln;
    "Grid intervals: i1=%, i2=%".format(grid.i1, grid.i2).postln;
    "".postln;

    agents.do { |agent|
        var pos       = agent[\pos];
        var triangles = grid.trianglesAt(pos);
        var neighbors = grid.wrappedNeighbors(pos);
        var agentPC   = grid.pitchClassAt(pos.x, pos.y).asInteger;

        "--- Agent % at (%, %) PC: % ---".format(
            agent[\label], pos.x, pos.y,
            noteNames[agentPC]
        ).postln;

        if(triangles.isNil or: { triangles.isEmpty }) {
            "  WARNING: no triangles at this position".postln;
        } {
            "  Triangles at current pos: %".format(
                triangles.collect { |t|
                    t[\pcs].collect { |pc| noteNames[pc.asInteger] }
                }
            ).postln;
        };

        // for each neighbor, check what transform would be detected
        neighbors.do { |n|
            var nPC        = grid.pitchClassAt(n.x, n.y).asInteger;
            var nTriangles = grid.trianglesAt(n);
            var transform  = nil;

            // mirror the detection logic from scoreHarmonics
            triangles.do { |ct|
                if(transform.isNil) {
                    nTriangles.do { |tt|
                        if(transform.isNil) {
                            var t = grid.transformationBetween(ct, tt);
                            if(t.notNil) { transform = t }
                        }
                    }
                }
            };

            "  → neighbor (%, %) PC:% | transform: %".format(
                n.x, n.y,
                noteNames[nPC],
                transform ?? { "nil (not in graph)" }
            ).postln;
        };

        "".postln;
    };

    // also dump recent transform history if any steps have run
    recent = ~simulation[\harmonicState][\recentTransforms] ? [];
    if(recent.notEmpty) {
        "=== Recent transform log (last %) ===".format(recent.size).postln;
        recent.do { |e|
            "  step:% agent:% | %→% transform:%".format(
                e[\step],
                e[\agent],
                e[\fromTriad].notNil.if {
                    e[\fromTriad][\pcs].collect { |pc| noteNames[pc.asInteger] }
                } { "?" },
                e[\toTriad].notNil.if {
                    e[\toTriad][\pcs].collect { |pc| noteNames[pc.asInteger] }
                } { "?" },
                e[\transform]
            ).postln;
        };
    } {
        "No transforms logged yet — run a few steps first.".postln;
    };
};

// Fire immediately for static position check:
~debugPLR.();
)

(
~diagnosticLocality = {
    var grid      = ~simulation.grid;
    var agents    = ~simulation[\agents];
    var noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];
    var stepCount = ~simulation[\stepCount] ? 0;
	var target;

    "".postln;
    "=== LOCALITY DIAGNOSTIC | step:% | nAgents:% ===".format(
        stepCount, agents.size).postln;
    "".postln;

    agents.do { |agent|
        var pos      = agent[\pos];
        var pc       = grid.pitchClassAt(pos.x, pos.y).asInteger;
        var midi     = agent[\currentMidi];
        var lastMidi = agent[\lastMidi];
        var history  = agent[\recentPositions] ? [];
        var motions  = agent[\recentMotion]    ? [];

        "--- Agent % | pos:(%, %) | PC:% | MIDI:% ---".format(
            agent[\label],
            pos.x, pos.y,
            noteNames[pc],
            midi ?? { "nil" }
        ).postln;

        // MIDI interval since last step
        if(midi.notNil and: { lastMidi.notNil }) {
            var midiInterval = (midi - lastMidi).abs;
            "  MIDI move: % → % | interval: % semitones %".format(
                lastMidi, midi, midiInterval,
                if(midiInterval > 12) { "*** LARGE LEAP ***" } { "" }
            ).postln;
        };

        // recent position history with grid distances
        if(history.size >= 2) {
            "  Position history (last %):".format(history.size).postln;
            history.doAdjacentPairs { |a, b|
                var dist    = grid.hexDistance(a.asPoint, b.asPoint);
                var pcA     = grid.pitchClassAt(a.x, a.y).asInteger;
                var pcB     = grid.pitchClassAt(b.x, b.y).asInteger;
                var pcDist  = (pcB - pcA).abs.mod(12);
                pcDist      = pcDist.min(12 - pcDist);
                "    (%, %) % → (%, %) % | hexDist:% pcInterval:% %".format(
                    a.x, a.y, noteNames[pcA],
                    b.x, b.y, noteNames[pcB],
                    dist, pcDist,
                    if(dist > 1) { "<<< JUMP dist:%" .format(dist) } { "" }
                ).postln;
            };
        };

        // motion record
        if(motions.notEmpty) {
            "  Motion record:".format.postln;
            motions.do { |m|
                "    interval:% gridDist:% %".format(
                    m[\interval]     ? "?",
                    m[\gridDistance] ? "?",
                    if((m[\gridDistance] ? 1) > 1) { "<<< JUMP" } { "" }
                ).postln;
            };
        };

        // voice range check
        "  Voice range: % – % | current MIDI: % | %".format(
            agent[\voiceRangeLo],
            agent[\voiceRangeHi],
            midi ?? { "nil" },
            if(midi.notNil and: {
                (midi < (agent[\voiceRangeLo] ? 24)) or: {
                    midi > (agent[\voiceRangeHi] ? 84) }
            }) { "*** OUT OF RANGE ***" } { "in range" }
        ).postln;

        // jump radius in effect at last decision
        "  jumpRadius:% jumpPenalty:% jumpOnResolve:%".format(
            ~simulation[\jumpRadius]    ? 1,
            ~simulation[\jumpPenalty]   ? 0.3,
            ~simulation[\jumpOnResolve] ? true
        ).postln;

        "".postln;
    };

    // cross-agent summary: are any two agents impossibly far apart?
    if(agents.size >= 2) {
        "  Inter-agent distances:".postln;
        agents.do { |a|
            agents.do { |b|
                if(a[\id] < b[\id]) {
                    var d = grid.hexDistance(a[\pos], b[\pos]);
                    "    Agent % ↔ Agent % | hexDist:%  %".format(
                        a[\label], b[\label], d,
                        if(d > 8) { "(far)" } { "" }
                    ).postln;
                }
            }
        };
    };

    // structural clock state
    target = ~simulation[\harmonicState][\targetTriad] ? [];
    "  Structural target: [%] | clockPeriod:% | step mod period:%".format(
        target.collect { |pc| noteNames[pc] }.join(", "),
        ~simulation[\structuralClockPeriod] ? 8,
        (~simulation[\stepCount] ? 0) % (~simulation[\structuralClockPeriod] ? 8)
    ).postln;
};

// bind to a key or call manually:
~diagnosticLocality.();
)

// Grid

(
var grid      = ~grid;
var noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];
var errors    = List.new;
var passed    = 0;
var check     = { |label, cond|
    if(cond) {
        passed = passed + 1;
    } {
        errors.add(label);
        "FAIL: %".format(label).postln;
    }
};

var pos0, n1, r1, r2, r3, w2, w3;
var edge, edgeN, allInBounds, da, db, pcOrigin, tris, transforms;

"=== GRID LAYER TESTS ===".postln;
"Grid: %x% i1=% i2=%".format(
    grid.width, grid.height, grid.i1, grid.i2).postln;
"".postln;

// --- 1. Neighbor counts ---
"-- Neighbor counts --".postln;
pos0 = Point(5, 5);
n1   = grid.wrappedNeighbors(pos0);
r1   = grid.wrappedNeighborsAtRadius(pos0, 1);
r2   = grid.wrappedNeighborsAtRadius(pos0, 2);
r3   = grid.wrappedNeighborsAtRadius(pos0, 3);
w2   = grid.wrappedNeighborsWithin(pos0, 2);
w3   = grid.wrappedNeighborsWithin(pos0, 3);


"wrappedNeighbors(5,5):           %  (expect 6)".format(n1.size).postln;
"wrappedNeighborsAtRadius(5,5,1): %  (expect 6)".format(r1.size).postln;
"wrappedNeighborsAtRadius(5,5,2): %  (expect 12)".format(r2.size).postln;
"wrappedNeighborsAtRadius(5,5,3): %  (expect 18)".format(r3.size).postln;
"wrappedNeighborsWithin(5,5,2):   %  (expect 18)".format(w2.size).postln;
"wrappedNeighborsWithin(5,5,3):   %  (expect 36)".format(w3.size).postln;

check.("radius-1 count == 6",  n1.size == 6);
check.("ring-1 == neighbors",  r1.size == 6);
check.("ring-2 count == 12",   r2.size == 12);
check.("ring-3 count == 18",   r3.size == 18);
check.("within-2 count == 18", w2.size == 18);
check.("within-3 count == 36", w3.size == 36);

// --- 2. Toroidal wrapping ---
"".postln;
"-- Toroidal wrapping --".postln;
edge   = Point(0, 0);
edgeN  = grid.wrappedNeighbors(edge);
"Neighbors of (0,0): %".format(edgeN).postln;
check.("corner (0,0) has 6 neighbors", edgeN.size == 6);
allInBounds = edgeN.every { |p|
    p.x >= 0 and: { p.x < grid.width } and: {
        p.y >= 0 } and: { p.y < grid.height }
};
check.("all wrapped neighbors in bounds", allInBounds);

// --- 3. hexDistance ---
"".postln;
"-- hexDistance --".postln;
da = grid.hexDistance(Point(5,5), Point(5,5));
db = grid.hexDistance(Point(5,5), Point(6,5));
"hexDistance self:     % (expect 0)".format(da).postln;
"hexDistance neighbor: % (expect 1)".format(db).postln;
check.("hexDistance self == 0",     da == 0);
check.("hexDistance neighbor == 1", db == 1);

r2.do { |p|
    var d = grid.hexDistance(pos0, p);
    if(d != 2) {
        errors.add("ring-2 cell at wrong distance: % d=%".format(p, d));
        "FAIL: ring-2 cell % has hexDistance % (expect 2)".format(p, d).postln;
    } { passed = passed + 1 };
};

// --- 4. pitchClassAt ---
"".postln;
"-- pitchClassAt --".postln;
pcOrigin = grid.pitchClassAt(0, 0).asInteger;
"pitchClassAt(0,0): % (%)".format(pcOrigin, noteNames[pcOrigin]).postln;

grid.wrappedNeighbors(Point(0,0)).do { |p|
    var pc = grid.pitchClassAt(p.x, p.y).asInteger;
    "  neighbor (%, %): % (%)".format(p.x, p.y, pc, noteNames[pc]).postln;
};
check.("pitchClassAt returns 0-11",
    (0..5).every { |i|
        var p  = grid.wrappedNeighbors(Point(0,0))[i];
        var pc = grid.pitchClassAt(p.x, p.y).asInteger;
        pc >= 0 and: { pc <= 11 }
    }
);

// --- 5. trianglesAt ---
"".postln;
"-- trianglesAt --".postln;
tris = grid.trianglesAt(Point(5,5));
"trianglesAt(5,5): % triangles".format(tris.size).postln;
tris.do { |t|
    var pcs = t[\pcs].collect(_.asInteger);
    "  [%]".format(pcs.collect { |pc| noteNames[pc] }.join(", ")).postln;
};
check.("trianglesAt returns at least 2", tris.size >= 2);
check.("all triangle PCs in 0-11",
    tris.every { |t| t[\pcs].collect(_.asInteger).every { |pc| pc >= 0 and: { pc <= 11 } } }
);

// --- 6. transformationBetween ---
"".postln;
"-- transformationBetween (PLR coverage) --".postln;
transforms = Dictionary.new;
transforms[\P] = 0; transforms[\L] = 0;
transforms[\R] = 0; transforms[\nil] = 0;

grid.wrappedNeighbors(Point(5,5)).do { |n|
    var fromTris = grid.trianglesAt(Point(5,5));
    var toTris   = grid.trianglesAt(n);
    var found    = nil;
	var key, npc;
    fromTris.do { |ft|
        if(found.isNil) {
            toTris.do { |tt|
                if(found.isNil) {
                    var t = grid.transformationBetween(ft, tt);
                    if(t.notNil) { found = t }
                }
            }
        }
    };
    key = found ?? { \nil };
	npc;
    transforms[key] = transforms[key] + 1;
    npc = grid.pitchClassAt(n.x, n.y).asInteger;
    "  neighbor (%, %) %: transform=%".format(
        n.x, n.y, noteNames[npc], found ?? { "nil" }).postln;
};

"Transform distribution from (5,5): P=% L=% R=% nil=%".format(
    transforms[\P], transforms[\L],
    transforms[\R], transforms[\nil]).postln;

check.("at least one L transform reachable", transforms[\L] > 0);
check.("at least one R transform reachable", transforms[\R] > 0);
check.("at least one P transform reachable", transforms[\P] > 0);
check.("no more than 2 nil neighbors",       transforms[\nil] <= 2);

// --- Summary ---
"".postln;
"=== GRID TEST SUMMARY ===".postln;
"Passed: % | Failed: %".format(passed, errors.size).postln;
if(errors.notEmpty) {
    "Failures:".postln;
    errors.do { |e| "  - %".format(e).postln };
};
)

(
var grid      = ~grid;
var noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];
var counts    = Dictionary.new;
var examples;
[\P, \L, \R, \nil].do { |k| counts[k] = 0 };
examples  = Dictionary.new;

// Sample 20 random positions
20.do {
    var pos      = Point(grid.width.rand, grid.height.rand);
    var fromTris = grid.trianglesAt(pos);
    grid.wrappedNeighbors(pos).do { |n|
        var toTris = grid.trianglesAt(n);
        var found  = nil;
		var key;
        fromTris.do { |ft|
            if(found.isNil) {
                toTris.do { |tt|
                    if(found.isNil) {
                        var t = grid.transformationBetween(ft, tt);
                        if(t.notNil) { found = t }
                    }
                }
            }
        };
        key = found ?? { \nil };
        counts[key] = counts[key] + 1;
        if(found.notNil and: { examples[found].isNil }) {
            examples[found] = (
                from: pos,
                to:   n,
                fromPC: noteNames[grid.pitchClassAt(pos.x, pos.y).asInteger],
                toPC:   noteNames[grid.pitchClassAt(n.x, n.y).asInteger]
            );
        };
    };
};

"Transform counts across 20 random positions:".postln;
"  P=% L=% R=% nil=%".format(
    counts[\P], counts[\L], counts[\R], counts[\nil]).postln;
"Examples found:".postln;
examples.keysValuesDo { |k, v|
    "  %: (%, %) % → (%, %) %".format(
        k,
        v[\from].x, v[\from].y, v[\fromPC],
        v[\to].x,   v[\to].y,   v[\toPC]
    ).postln;
};
)

(
// Inspect exactly what trianglesAt returns for two P-adjacent cells
var grid      = ~grid;
var noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];
var posA      = Point(5, 5);   // G
var posB      = Point(4, 5);   // C — should be P-related

var trisA = grid.trianglesAt(posA);
var trisB = grid.trianglesAt(posB);

"Triangles at (5,5) G:".postln;
trisA.do { |t|
    "  [%]".format(t[\pcs].collect { |pc|
        noteNames[pc.asInteger] }.join(", ")).postln };

"".postln;
"Triangles at (4,5) C:".postln;
trisB.do { |t|
    "  [%]".format(t[\pcs].collect { |pc|
        noteNames[pc.asInteger] }.join(", ")).postln };

"".postln;
"Shared PCs between each pair:".postln;
trisA.do { |ta|
    trisB.do { |tb|
        var shared = ta[\pcs].select { |pc| tb[\pcs].includes(pc) };
        if(shared.size >= 1) {
            "  [%] ∩ [%] = [%]".format(
                ta[\pcs].collect { |pc| noteNames[pc.asInteger] }.join(","),
                tb[\pcs].collect { |pc| noteNames[pc.asInteger] }.join(","),
                shared.collect { |pc| noteNames[pc.asInteger] }.join(",")
            ).postln
        }
    }
};
)

// Timing

(
var grid  = ~grid;
var pos   = Point(5, 5);
var t0, t1, t2;

t0 = Process.elapsedTime;
1000.do { grid.wrappedNeighborsAtRadius(pos, 2) };
t1 = Process.elapsedTime;
1000.do { grid.wrappedNeighborsAtRadius(pos, 3) };
t2 = Process.elapsedTime;

"wrappedNeighborsAtRadius(r=2) × 1000: % ms".format(
    ((t1 - t0) * 1000).round(0.1)).postln;
"wrappedNeighborsAtRadius(r=3) × 1000: % ms".format(
    ((t2 - t1) * 1000).round(0.1)).postln;
"Per-call r=2: % µs".format(((t1 - t0) * 1000000 / 1000).round(0.1)).postln;
"Per-call r=3: % µs".format(((t2 - t1) * 1000000 / 1000).round(0.1)).postln;
)

(
var grid = ~grid;
var pos  = Point(5, 5);
var t0, t1, t2, t3, t4;

// cold
t0 = Process.elapsedTime;
grid.wrappedNeighborsAtRadius(pos, 2);
t1 = Process.elapsedTime;
grid.wrappedNeighborsAtRadius(pos, 3);
t2 = Process.elapsedTime;

// warm
grid.wrappedNeighborsAtRadius(pos, 2);
t3 = Process.elapsedTime;
grid.wrappedNeighborsAtRadius(pos, 2);
t4 = Process.elapsedTime;

"Cold r=2: % ms".format(((t1 - t0) * 1000).round(0.01)).postln;
"Cold r=3: % ms".format(((t2 - t1) * 1000).round(0.01)).postln;
"Warm r=2: % µs".format(((t4 - t3) * 1000000).round(0.1)).postln;
)

/////////////////////////////////////////////

(
var grid      = ~grid;
var sim       = ~simulation;
var dm        = ~driveModel;
var noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];
var errors    = List.new;
var passed    = 0;
var check     = { |label, cond|
    if(cond) { passed = passed + 1 } {
        errors.add(label);
        "FAIL: %".format(label).postln;
    }
};

// ================================================================
// HELPERS — build minimal agent contexts for isolated testing
// ================================================================

var makeCtx = { |pos, recentPos, recentMotion, otherPos|
    (
        pos:          pos.asPoint,
        lastDir:      nil,
        otherPos:     (otherPos ? []).collect(_.asPoint),
        recentPos:    recentPos  ? [],
        recentMotion: recentMotion ? []
    )
};

var makeCandidate = { |cell|
    var pc = grid.pitchClassAt(cell.x, cell.y).asInteger;
    (cell: cell, pc: pc, gridDistance: 1)
};

// A fixed position to anchor all tests
var anchorPos  = Point(6, 6);
var anchorPC   = grid.pitchClassAt(anchorPos.x, anchorPos.y).asInteger;
var neighbors  = grid.wrappedNeighbors(anchorPos);
var candidates = neighbors.collect { |n| makeCandidate.(n) };

var ctx0, ev0, evMom, lastStep, motionForward, motionBackward, evForward, evBackward, manyVisits,
evFatigued, evFresh, crowdedOtherPos, evCrowded, evEmpty, s0, s1, histL, sReversal, histLR, sContinue,
sNew, scoredCands, tonicPC, homeTriad, modeColl, scored, allNormalised, hsValues, hsRange, homeScores,
nonHomeScores, cand1, cand2, cand3, scored123, weights, evalledCands, feasible, heavilyFatigued, fallback,
winner, winnerHighTension, agent0, otherPCs, decision, noNils, allInBounds;

"=== DRIVE MODEL TESTS ===".postln;
"Anchor: (%, %) PC:%".format(
    anchorPos.x, anchorPos.y, noteNames[anchorPC]).postln;
"".postln;

// ================================================================
// 1. INDIVIDUAL DRIVE FUNCTIONS
// ================================================================

"-- 1. Drive function outputs --".postln;

// evalCell should return an event with all drive scores
ctx0 = makeCtx.(anchorPos, [], [], []);
ev0  = dm.evalCell(neighbors[0], ctx0);

check.("evalCell returns event",        ev0.isKindOf(Event));
check.("evalCell has momentum key",     ev0[\momentum].notNil);
check.("evalCell has fatigue key",      ev0[\fatigue].notNil);
check.("evalCell has stigmergy key",    ev0[\stigmergy].notNil);
check.("evalCell has sparsity key",     ev0[\sparsity].notNil);
check.("evalCell has imitation key",    ev0[\imitation].notNil);
check.("evalCell has cell key",         ev0[\cell].notNil);

// Momentum — no history should return 0
evMom = dm.evalCell(neighbors[0], makeCtx.(anchorPos, [], [], []));
check.("momentum with no history == 0", evMom[\momentum] == 0);

// Momentum — with history, continuation should score > reversal
lastStep = (
    grid.pitchClassAt(neighbors[0].x, neighbors[0].y).asInteger -
    anchorPC
);
motionForward  = [(interval: lastStep, dir: nil, gridDistance: 1)];
motionBackward = [(interval: lastStep.neg, dir: nil, gridDistance: 1)];

evForward  = dm.evalCell(
    neighbors[0],
    makeCtx.(anchorPos, [], motionForward, []));
evBackward = dm.evalCell(
    neighbors[0],
    makeCtx.(anchorPos, [], motionBackward, []));

"  momentum forward: %  backward: %".format(
    evForward[\momentum].round(0.01),
    evBackward[\momentum].round(0.01)).postln;
check.("momentum rewards continuation over reversal",
    evForward[\momentum] >= evBackward[\momentum]);

// Fatigue — repeated visits should produce more negative scores
manyVisits = Array.fill(6, { anchorPos });
evFatigued = dm.evalCell(
    anchorPos,
    makeCtx.(anchorPos, manyVisits, [], []));
evFresh = dm.evalCell(
    neighbors[0],
    makeCtx.(anchorPos, [], [], []));

"  fatigue at current pos (6 visits): %".format(
    evFatigued[\fatigue].round(0.01)).postln;
"  fatigue at fresh cell: %".format(
    evFresh[\fatigue].round(0.01)).postln;
check.("fatigue more negative at repeatedly visited cell",
    evFatigued[\fatigue] <= evFresh[\fatigue]);

// Sparsity — crowded cell should score lower
crowdedOtherPos = Array.fill(3, { neighbors[0] });
evCrowded = dm.evalCell(
    neighbors[0],
    makeCtx.(anchorPos, [], [], crowdedOtherPos));
evEmpty = dm.evalCell(
    neighbors[0],
    makeCtx.(anchorPos, [], [], []));

"  sparsity crowded: %  empty: %".format(
    evCrowded[\sparsity].round(0.01),
    evEmpty[\sparsity].round(0.01)).postln;
check.("sparsity lower when cell is crowded",
    evCrowded[\sparsity] <= evEmpty[\sparsity]);

// ================================================================
// 2. plrContinuityScore
// ================================================================

"".postln;
"-- 2. plrContinuityScore --".postln;

// nil transform should return 0
s0 = dm.plrContinuityScore(nil, []);
check.("nil transform → 0.0", s0 == 0.0);

// empty history → small connectivity bonus only
s1 = dm.plrContinuityScore(\L, []);
"  L with no history: %  (expect ~0.1)".format(s1.round(0.01)).postln;
check.("empty history → 0.1", s1 == 0.1);

// immediate reversal — same transform as last → penalty
histL  = [(transform: \L, step: 1, agent: \test)];
sReversal = dm.plrContinuityScore(\L, histL);
"  L after L (reversal): %  (expect negative)".format(
    sReversal.round(0.01)).postln;
check.("immediate reversal scores negative", sReversal < 0);

// pattern continuation — L after R after L → reward
histLR = [
    (transform: \L, step: 1, agent: \test),
    (transform: \R, step: 2, agent: \test)
];
sContinue = dm.plrContinuityScore(\L, histLR);
"  L after R-L (continuation): %  (expect positive)".format(
    sContinue.round(0.01)).postln;
check.("alternating pattern continuation scores positive",
    sContinue > 0);

// different transform from last, no pattern → connectivity bonus only
sNew = dm.plrContinuityScore(\R, histL);
"  R after L (new direction): %  (expect ~0.1)".format(
    sNew.round(0.01)).postln;
check.("new direction after single history → ~0.1",
    sNew > 0 and: { sNew < 0.5 });

// ================================================================
// 3. scoreHarmonics
// ================================================================

"".postln;
"-- 3. scoreHarmonics --".postln;

// Build candidates from all neighbors + tag gridDistance
scoredCands = neighbors.collect { |n|
    (cell: n, pc: grid.pitchClassAt(n.x, n.y).asInteger, gridDistance: 1)
};

tonicPC   = sim[\harmonicState][\tonicPC].round.asInteger.mod(12);
homeTriad = [0, 4, 7].collect { |i| (tonicPC + i).mod(12) };
modeColl  = (~modeCollections[\major] ? [0,2,4,5,7,9,11])
    .collect { |pc| (pc + tonicPC).mod(12) };

scored = dm.scoreHarmonics(
    scoredCands,
    anchorPos,
    [],
    homeTriad,
    Array.fill(12, { 1.0 }),
    0.5, 0.5,
    modeColl,
    nil
);

// All candidates should have harmonicScore in [0,1]
allNormalised = scored.every { |e|
    (e[\harmonicScore] ? -1) >= 0 and: {
        (e[\harmonicScore] ? 2) <= 1.0001 }
};
check.("all harmonicScores normalised to [0,1]", allNormalised);

// Scores should not all be identical (normalisation should spread them)
hsValues = scored.collect { |e| e[\harmonicScore] ? 0 };
hsRange  = hsValues.maxItem - hsValues.minItem;
"  harmonicScore range: %".format(hsRange.round(0.001)).postln;
check.("harmonicScores are not all identical", hsRange > 0);

// vlScore should exist on all candidates
check.("all candidates have vlScore",
    scored.every { |e| e[\vlScore].notNil });

// hcScore should be non-negative
check.("all hcScores non-negative",
    scored.every { |e| (e[\hcScore] ? 0) >= 0 });

// modeDissonance should be in [0,1]
check.("all modeDissonance in [0,1]",
    scored.every { |e|
        (e[\modeDissonance] ? 0) >= 0 and: {
            (e[\modeDissonance] ? 0) <= 1.001 }
    });

// Home triad candidates should score higher than non-home on average
homeScores = scored.select { |e|
    homeTriad.includes(
        grid.pitchClassAt(e[\cell].x, e[\cell].y).asInteger)
}.collect { |e| e[\harmonicScore] ? 0 };

nonHomeScores = scored.reject { |e|
    homeTriad.includes(
        grid.pitchClassAt(e[\cell].x, e[\cell].y).asInteger)
}.collect { |e| e[\harmonicScore] ? 0 };

if(homeScores.notEmpty and: { nonHomeScores.notEmpty }) {
    "  avg home triad score: %  avg non-home: %".format(
        homeScores.mean.round(0.01),
        nonHomeScores.mean.round(0.01)).postln;
    check.("home triad candidates score higher on average",
        homeScores.mean >= nonHomeScores.mean);
} {
    "  (no home triad candidates in neighbor set — skipping bias check)".postln;
};

// distancePenalty should scale with gridDistance
cand1 = (cell: neighbors[0], pc: 0, gridDistance: 1);
cand2 = (cell: neighbors[0], pc: 0, gridDistance: 2);
cand3 = (cell: neighbors[0], pc: 0, gridDistance: 3);
scored123 = dm.scoreHarmonics(
    [cand1, cand2, cand3], anchorPos, [],
    homeTriad, Array.fill(12, { 1.0 }),
    0.5, 0.5, modeColl, nil);
"  distancePenalty d1:% d2:% d3:%".format(
    (scored123[0][\distancePenalty] ? 0).round(0.01),
    (scored123[1][\distancePenalty] ? 0).round(0.01),
    (scored123[2][\distancePenalty] ? 0).round(0.01)).postln;
check.("distancePenalty increases with gridDistance",
    (scored123[0][\distancePenalty] ? 0)
    < (scored123[1][\distancePenalty] ? 0)
    and: {
        (scored123[1][\distancePenalty] ? 0)
        < (scored123[2][\distancePenalty] ? 0)
    });

// ================================================================
// 4. filterKinematics
// ================================================================

"".postln;
"-- 4. filterKinematics --".postln;

weights = (
    momentum: 0.3, fatigue: 0.15,
    stigmergy: 0.2, sparsity: 0.08, imitation: 0.2
);

// Evaluate candidates with fatigue scores
evalledCands = scored.collect { |e|
    var ev = dm.evalCell(e[\cell], makeCtx.(anchorPos, [], [], []));
    ev[\gridDistance]   = e[\gridDistance] ? 1;
    ev[\harmonicScore]  = e[\harmonicScore] ? 0;
    ev[\distancePenalty] = e[\distancePenalty] ? 0;
    ev
};

feasible = dm.filterKinematics(evalledCands, weights, anchorPos);

check.("filterKinematics returns non-empty array",
    feasible.notEmpty);
check.("filterKinematics returns subset of candidates",
    feasible.size <= evalledCands.size);
check.("filtered candidates all have cell key",
    feasible.every { |e| e[\cell].notNil });

// Fallback: if all candidates fatigued, should still return something
heavilyFatigued = evalledCands.collect { |e|
    var copy = e.copy;
    copy[\fatigue] = -10.0;
    copy
};
fallback = dm.filterKinematics(heavilyFatigued, weights, anchorPos);
check.("filterKinematics fallback returns all candidates when all fatigued",
    fallback.size == heavilyFatigued.size);

// ================================================================
// 5. selectKinematic
// ================================================================

"".postln;
"-- 5. selectKinematic --".postln;

winner = dm.selectKinematic(feasible, weights, 0.3);

check.("selectKinematic returns non-nil", winner.notNil);
check.("winner has cell key",             winner[\cell].notNil);
check.("winner has total key",            winner[\total].notNil);
check.("winner total in [0,1]",
    (winner[\total] ? 0) >= 0 and: { (winner[\total] ? 0) <= 1.001 });
check.("winner is from feasible set",
    feasible.any { |e| e[\cell] == winner[\cell] });

// High tension should not crash selectKinematic
winnerHighTension = dm.selectKinematic(feasible, weights, 0.95);
check.("selectKinematic handles high tension",
    winnerHighTension.notNil);

// ================================================================
// 6. chooseNext end-to-end
// ================================================================

"".postln;
"-- 6. chooseNext end-to-end --".postln;

agent0     = sim[\agents][0];
otherPCs   = sim[\agents].reject(_ === agent0).collect { |a| a[\pos] };
decision   = dm.chooseNext(
    agent0[\pos],
    agent0[\lastDir],
    otherPCs,
    agent0[\weights],
    agent0[\label],
    agent0[\recentPositions],
    agent0[\recentMotion],
    agent0[\modeCollection],
    agent0[\tensionScore] ? 0.5,
    agent0[\homeTriad],
    agent0[\harmonicBias],
    agent0[\vlWeight],
    agent0[\hcWeight]
);

check.("chooseNext returns non-nil",         decision.notNil);
check.("chooseNext result has cell",         decision[\cell].notNil);
check.("chooseNext result has harmonicScore",decision[\harmonicScore].notNil);
check.("chooseNext result has total",        decision[\total].notNil);
check.("chooseNext cell in grid bounds",
    decision[\cell].x >= 0
    and: { decision[\cell].x < grid.width }
    and: { decision[\cell].y >= 0 }
    and: { decision[\cell].y < grid.height });
check.("chooseNext cell PC in 0-11",
    grid.pitchClassAt(
        decision[\cell].x,
        decision[\cell].y).asInteger.inRange(0, 11));

// Check gridDistance is tagged on decision
"  decision gridDistance: %".format(
    decision[\gridDistance] ? "MISSING").postln;
check.("chooseNext result has gridDistance",
    decision[\gridDistance].notNil);

// Run chooseNext 20 times — should never return nil or crash
noNils = true;
allInBounds = true;
20.do {
    var d = dm.chooseNext(
        agent0[\pos],
        agent0[\lastDir],
        otherPCs,
        agent0[\weights],
        agent0[\label],
        agent0[\recentPositions],
        agent0[\recentMotion],
        agent0[\modeCollection],
        1.0.rand,
        agent0[\homeTriad],
        agent0[\harmonicBias],
        agent0[\vlWeight],
        agent0[\hcWeight]
    );
    if(d.isNil) { noNils = false };
    if(d.notNil) {
        if(d[\cell].x < 0
            or: { d[\cell].x >= grid.width }
            or: { d[\cell].y < 0 }
            or: { d[\cell].y >= grid.height }
        ) { allInBounds = false }
    };
};
check.("chooseNext never returns nil over 20 calls",      noNils);
check.("chooseNext always returns in-bounds cell",         allInBounds);

// ================================================================
// SUMMARY
// ================================================================

"".postln;
"=== DRIVE MODEL TEST SUMMARY ===".postln;
"Passed: % | Failed: %".format(passed, errors.size).postln;
if(errors.notEmpty) {
    "Failures:".postln;
    errors.do { |e| "  - %".format(e).postln };
} {
    "Drive model layer: ALL PASS — ready for environment update tests.".postln;
};
)