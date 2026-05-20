// =====================================================================
// stratification_experiment_v2.scd
//
// Extends v1 with two changes:
//
//   1. RANDOMISED SPAWN OCTAVES — after spawnAgents, agent octave
//      assignments and voice ranges are independently shuffled, breaking
//      the correlation between agent index and starting octave that
//      confounded v1's rho metric.
//
//   2. TEMPORAL DYNAMICS — for each run, the post-warmup log is split
//      into three windows (early, mid, late) and metrics are computed
//      per window. This reveals whether stratification emerges over time
//      or is fixed at spawn.
//
// Output: writes summary_v2.csv (per-window) and summary_aggregated.csv
// (whole-run, comparable to v1). The console prints a window-by-window
// comparison.
//
// Load main.scd, then this whole file, then run:
//   ~smokeTestV2.value;
//   ~runExperimentsV2.value;
// =====================================================================


// ---------------------------------------------------------------------
// Configuration (same as v1, plus window count)
// ---------------------------------------------------------------------

(
~cfg = (
    seeds:                  [1001, 1002, 1003, 1004, 1005],
    ticksPerRun:            600,
    warmupTicks:            100,
    nAgents:                4,
    nWindows:               3,
    stepIntervalsRateDiff:  [1, 2, 4, 8],
    stepIntervalsUniform:   [2, 2, 2, 2],
    outputDir:              "C:/Programming/SuperCollider/Agent Rule-space Systems Design/Final_Project/testing/stratification_results"
);
File.mkdir(~cfg[\outputDir]);
"Output directory: %\n".postf(~cfg[\outputDir]);


// ---------------------------------------------------------------------
// API hooks
// ---------------------------------------------------------------------

~apiReset = { |seed|
    var octaves, perms, lo, hi;

    thisThread.randSeed_(seed);

    if(~playNoteSaved.isNil) { ~playNoteSaved = ~playNote };
    ~playNote = { };

    if(~view.isNil)       { ~view       = (refresh: { }) };
    if(~voiceView.isNil)  { ~voiceView  = (refresh: { }) };
    if(~rhythmView.isNil) { ~rhythmView = (refresh: { }) };

    ~simulation[\birthEnabled] = false;
    ~simulation[\deathEnabled] = false;
    ~simulation[\stepCount]      = 0;
    ~simulation[\cyclePos]       = 0;
    ~simulation[\priorityOffset] = 0;
    ~simulation[\harmonicState][\recentTransforms] = [];

    ~simulation.spawnAgents(~cfg[\nAgents], 5, 2);

    // RANDOMISED SPAWN OCTAVES — break the agent-index ↔ octave
    // correlation. Each agent gets one of [3, 4, 5, 6] in randomised
    // order, with voiceRangeLo/Hi recomputed to match.
    octaves = [3, 4, 5, 6].scramble;
    ~simulation[\agents].do { |agent, i|
        var o = octaves[i];
        agent[\octave]       = o;
        agent[\voiceRangeLo] = ((o - 1) * 12).max(24);
        agent[\voiceRangeHi] = ((o + 1) * 12).min(96);
        // Reset realised pitch so the next commit re-realises within the new range.
        agent[\currentMidi]  = nil;
        agent[\lastMidi]     = nil;
    };
};

~apiSetStepIntervals = { |intervals|
    ~simulation[\agents].do { |agent, i|
        agent[\stepInterval] = intervals[i];
        agent[\rhythm]       = ~stepIntervalToRhythm.(intervals[i], 16);
    };
};

~apiSetDriveWeight = { |drive, value|
    ~simulation[\agents].do { |agent|
        agent[\weights][drive] = value;
    };
};

~apiTick = {
    try { ~simulation.step } { |err|
        "WARNING: step raised: %\n".postf(err.errorString);
    };
};

~apiSampleAgent = { |agent|
    var grid = ~simulation[\grid];
    var pc, pitch, sounding, stepInt, resonance, octave;
    pc        = grid.pitchClassAt(agent[\pos].x, agent[\pos].y).asInteger;
    pitch     = agent[\currentMidi];
    sounding  = ~rhythmFiresAt.(agent[\rhythm], ~simulation[\cyclePos])
                and: { (agent[\resonanceScore] ? 0) >= (agent[\soundThreshold] ? 0) };
    stepInt   = agent[\stepInterval];
    resonance = agent[\resonanceScore] ? 0;
    octave    = agent[\octave];
    (agentId: agent[\id], pc: pc, pitch: pitch, sounding: sounding,
     stepInterval: stepInt, resonance: resonance, octave: octave);
};

~apiTonic = {
    (~simulation[\harmonicState][\tonicPC] ? 0).round.asInteger.mod(12);
};

~apiRestore = {
    if(~playNoteSaved.notNil) { ~playNote = ~playNoteSaved };
};


// ---------------------------------------------------------------------
// Conditions
// ---------------------------------------------------------------------

~conditionA = { ~apiSetStepIntervals.(~cfg[\stepIntervalsRateDiff]) };
~conditionB = { ~apiSetStepIntervals.(~cfg[\stepIntervalsUniform])  };
~conditionC = {
    ~apiSetStepIntervals.(~cfg[\stepIntervalsRateDiff]);
    ~apiSetDriveWeight.(\stigmergy, 0.0);
};
~conditionD = {
    ~apiSetStepIntervals.(~cfg[\stepIntervalsRateDiff]);
    ~apiSetDriveWeight.(\sparsity, 0.0);
};

~conditionList = [
    [\A_rateDiffAllDrives,   ~conditionA],
    [\B_uniformRate,         ~conditionB],
    [\C_rateDiffNoStigmergy, ~conditionC],
    [\D_rateDiffNoSparsity,  ~conditionD],
];


// ---------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------

~rankArr = { |arr|
    var sorted = arr.copy.sort;
    arr.collect { |v| sorted.indexOf(v) + 1 };
};

~fmt = { |v|
    if(v.isNil) { "" } {
        if(v.isFloat) { v.round(0.0001).asString } { v.asString }
    };
};


// ---------------------------------------------------------------------
// Metrics — applied to a window of the log
// ---------------------------------------------------------------------

~mMeanPitch = { |log, n|
    n.collect { |i|
        var pitches = log.collect { |sample| sample[i][\pitch] }.reject(_.isNil);
        if(pitches.isEmpty) { nil } { pitches.sum / pitches.size };
    };
};

~mPitchRange = { |log, n|
    n.collect { |i|
        var pitches = log.collect { |sample| sample[i][\pitch] }.reject(_.isNil);
        if(pitches.isEmpty) { nil } { pitches.maxItem - pitches.minItem };
    };
};

~mPCEntropy = { |log, n|
    n.collect { |i|
        var pcs = log.collect { |sample| sample[i][\pc] }.reject(_.isNil);
        var counts, probs;
        if(pcs.isEmpty) { nil } {
            counts = Array.fill(12, 0);
            pcs.do { |pc| counts[pc] = counts[pc] + 1 };
            probs = counts / counts.sum;
            probs.collect { |p| if(p > 0) { p * p.log2.neg } { 0 } }.sum;
        };
    };
};

~mTonicFrac = { |log, n, tonic|
    n.collect { |i|
        var pcs = log.collect { |sample| sample[i][\pc] }.reject(_.isNil);
        if(pcs.isEmpty) { nil } { pcs.count(_ == tonic) / pcs.size };
    };
};

~mRangeOverlap = { |log, n|
    var ranges, overlaps = List.new;
    ranges = n.collect { |i|
        var pitches = log.collect { |sample| sample[i][\pitch] }.reject(_.isNil);
        if(pitches.isEmpty) { nil } { [pitches.minItem, pitches.maxItem] };
    };
    n.do { |i|
        ((i + 1) .. (n - 1)).do { |j|
            var ri = ranges[i], rj = ranges[j];
            var lo, hi, ov, span;
            if(ri.notNil and: { rj.notNil }) {
                lo = max(ri[0], rj[0]);
                hi = min(ri[1], rj[1]);
                ov = max(0, hi - lo);
                span = max(ri[1], rj[1]) - min(ri[0], rj[0]);
                if(span > 0) { overlaps.add(ov / span) };
            };
        };
    };
    if(overlaps.isEmpty) { nil } { overlaps.sum / overlaps.size };
};

~mRankCorr = { |log, n|
    var stepInts, meanPitches, ranksA, ranksB, dSq, result;
    stepInts = n.collect { |i| log[0][i][\stepInterval] };
    meanPitches = ~mMeanPitch.(log, n);
    if(meanPitches.any(_.isNil) or: { stepInts.any(_.isNil) }
        or: { stepInts.asSet.size < 2 }) {
        result = nil
    } {
        ranksA = ~rankArr.(stepInts);
        ranksB = ~rankArr.(meanPitches);
        dSq = (ranksA - ranksB).squared.sum;
        result = 1 - ((6 * dSq) / (n * (n.squared - 1)));
    };
    result
};


// ---------------------------------------------------------------------
// Window slicer
// ---------------------------------------------------------------------

~splitIntoWindows = { |log, nWindows|
    var size = (log.size / nWindows).floor.asInteger;
    nWindows.collect { |w|
        var start = w * size;
        var end = if(w == (nWindows - 1)) { log.size } { (w + 1) * size };
        log.copyRange(start, end - 1)
    };
};


// ---------------------------------------------------------------------
// Single-run executor
// ---------------------------------------------------------------------

~runOne = { |conditionName, conditionFn, seed|
    var log = List.new;
    var n = ~cfg[\nAgents];
    var totalTicks = ~cfg[\warmupTicks] + ~cfg[\ticksPerRun];
    var windows, perWindow, octaveAssignment, agentSpawnOctaves;

    ~apiReset.(seed);
    conditionFn.value;

    // Record the (now randomised) octave assignment for diagnostics.
    agentSpawnOctaves = ~simulation[\agents].collect { |a| a[\octave] };

    totalTicks.do { |t|
        var sample;
        ~apiTick.value;
        if(t >= ~cfg[\warmupTicks]) {
            sample = ~simulation[\agents].collect { |agent|
                ~apiSampleAgent.(agent);
            };
            log.add(sample);
        };
    };

    // Whole-run metrics (comparable to v1 summary).
    perWindow = (
        whole: (
            meanPitch:    ~mMeanPitch.(log, n),
            pitchRange:   ~mPitchRange.(log, n),
            pcEntropy:    ~mPCEntropy.(log, n),
            tonicFraction: ~mTonicFrac.(log, n, ~apiTonic.value),
            rangeOverlap: ~mRangeOverlap.(log, n),
            rankCorr:     ~mRankCorr.(log, n),
        )
    );

    // Per-window metrics.
    windows = ~splitIntoWindows.(log, ~cfg[\nWindows]);
    windows.do { |window, w|
        var key = ("window" ++ w).asSymbol;
        perWindow[key] = (
            meanPitch:    ~mMeanPitch.(window, n),
            pitchRange:   ~mPitchRange.(window, n),
            pcEntropy:    ~mPCEntropy.(window, n),
            tonicFraction: ~mTonicFrac.(window, n, ~apiTonic.value),
            rangeOverlap: ~mRangeOverlap.(window, n),
            rankCorr:     ~mRankCorr.(window, n),
        );
    };

    (
        condition:        conditionName,
        seed:             seed,
        spawnOctaves:     agentSpawnOctaves,
        windows:          perWindow,
    );
};


// ---------------------------------------------------------------------
// CSV writers
// ---------------------------------------------------------------------

~writeWindowed = { |result, file|
    var keys = [\whole] ++ ~cfg[\nWindows].collect { |w| ("window" ++ w).asSymbol };
    keys.do { |windowKey|
        var w = result[\windows][windowKey];
        ~cfg[\nAgents].do { |i|
            file.write(
                [result[\condition], result[\seed], windowKey, i,
                 ~fmt.(result[\spawnOctaves][i]),
                 ~fmt.(w[\meanPitch][i]),
                 ~fmt.(w[\pitchRange][i]),
                 ~fmt.(w[\pcEntropy][i]),
                 ~fmt.(w[\tonicFraction][i]),
                 ~fmt.(w[\rangeOverlap]),
                 ~fmt.(w[\rankCorr])
                ].join(",") ++ "\n"
            );
        };
    };
};


// ---------------------------------------------------------------------
// Aggregator — separate report per window
// ---------------------------------------------------------------------

~report = { |allResults|
    var byCondition = Dictionary.new;
    var windowKeys = [\whole] ++ ~cfg[\nWindows].collect { |w| ("window" ++ w).asSymbol };

    allResults.do { |r|
        var key = r[\condition];
        if(byCondition[key].isNil) { byCondition[key] = List.new };
        byCondition[key].add(r);
    };

    windowKeys.do { |windowKey|
        "\n==============================================================".postln;
        "  WINDOW: %".format(windowKey).postln;
        "==============================================================".postln;
        "  Condition                     mean rho     mean overlap".postln;
        "--------------------------------------------------------------".postln;
        byCondition.keysValuesDo { |cond, runs|
            var rhos = runs.collect { |r| r[\windows][windowKey][\rankCorr] }.reject(_.isNil);
            var overlaps = runs.collect { |r| r[\windows][windowKey][\rangeOverlap] }.reject(_.isNil);
            var rho = if(rhos.isEmpty) { "n/a" } { (rhos.sum / rhos.size).round(0.001).asString };
            var ov  = if(overlaps.isEmpty) { "n/a" } { (overlaps.sum / overlaps.size).round(0.001).asString };
            "  %    %      %".format(
                cond.asString.padRight(28),
                rho.padRight(8),
                ov
            ).postln;
        };
    };
    "==============================================================".postln;
};


// ---------------------------------------------------------------------
// Main runner
// ---------------------------------------------------------------------

~runExperimentsV2 = {
    var allResults = List.new;
    var file;

    file = File(~cfg[\outputDir] ++ "summary_windowed.csv", "w");
    file.write(
        "condition,seed,window,agent_id,spawn_octave,mean_pitch,pitch_range,"
        "pc_entropy,tonic_fraction,range_overlap,rank_corr\n"
    );

    ~conditionList.do { |pair|
        var condName = pair[0];
        var condFn   = pair[1];
        ~cfg[\seeds].do { |seed|
            var result;
            "Running %, seed %\n".postf(condName, seed);
            result = ~runOne.(condName, condFn, seed);
            allResults.add(result);
            ~writeWindowed.(result, file);
        };
    };

    file.close;
    ~apiRestore.value;

    "\nWrote: %\n".postf(~cfg[\outputDir] ++ "summary_windowed.csv");

    ~report.(allResults);
};


// ---------------------------------------------------------------------
// Smoke test
// ---------------------------------------------------------------------

~smokeTestV2 = {
    var ok = true, agents, sample, octaves;
    "\n--- Smoke test V2 ---".postln;

    ~apiReset.(42);

    agents = ~simulation[\agents];
    if(agents.isNil or: { agents.size != ~cfg[\nAgents] }) {
        "FAIL: expected % agents, got %.".format(
            ~cfg[\nAgents],
            if(agents.isNil) { "nil" } { agents.size.asString }
        ).postln;
        ok = false;
    } {
        "OK:   spawned % agents.".format(agents.size).postln;
    };

    octaves = agents.collect { |a| a[\octave] };
    "Octave assignment after reset: % (should be a permutation of [3,4,5,6])".format(octaves).postln;
    if(octaves.asSet.size != 4) {
        "FAIL: octaves are not all distinct.".postln;
        ok = false;
    };

    try {
        ~apiTick.value;
        "OK:   tick advanced.".postln;
    } { |e|
        "FAIL: tick raised: %".format(e.errorString).postln;
        ok = false;
    };

    try {
        sample = ~apiSampleAgent.(~simulation[\agents][0]);
        "OK:   sample = %".format(sample).postln;
    } { |e|
        "FAIL: sampleAgent raised: %".format(e.errorString).postln;
        ok = false;
    };

    ~apiRestore.value;

    if(ok) {
        "Smoke test V2 passed. Run ~runExperimentsV2.value next.\n".postln;
    } {
        "Smoke test V2 FAILED.\n".postln;
    };
};
)


// To run:
   ~smokeTestV2.value;
   ~runExperimentsV2.value;
