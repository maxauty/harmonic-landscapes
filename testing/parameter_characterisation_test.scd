// =============================================================================
// parameter_characterisation_test.scd
//
// Sweep each of a small set of global parameters across its range and
// measure a battery of output metrics at each point. Output is a TSV
// suitable for plotting outside SC.
// =============================================================================

(
~paramSweepConfig = [
    (
        param:      \tempDeliberative,
        values:     [0.4, 0.6, 0.8, 1.0, 1.2, 1.6, 2.0],
        targetPath: { |sim, v| sim[\tempDeliberative] = v }
    ),
    (
        param:      \harmonicBlend,
        values:     [0.2, 0.35, 0.5, 0.65, 0.8],
        targetPath: { |sim, v| sim[\harmonicBlend] = v }
    ),
    (
        param:      \modeStrictness,
        values:     [0.0, 0.25, 0.5, 0.75, 1.0],
        targetPath: { |sim, v| sim[\modeStrictness] = v }
    ),
    (
        param:      \birthContestThreshold,
        values:     [0.5, 0.6, 0.7, 0.8, 0.9],
        targetPath: { |sim, v| sim[\birthContestThreshold] = v }
    ),
    (
        param:      \structuralClockPeriod,
        values:     [4, 8, 12, 16, 24],
        targetPath: { |sim, v| sim[\structuralClockPeriod] = v }
    ),
];

~outcomeMetrics = (
    \functionTransitionEntropy: { |midiHistory, sim, tickData|
        // Shannon entropy of consecutive function transitions
        var fns = tickData.collect(_[\impliedFunction]).select(_.notNil);
        var pairs, counts, total, entropy;
        if(fns.size < 2) { 0 } {
            pairs = (fns.size - 1).collect { |i| [fns[i], fns[i+1]].asString };
            counts = Dictionary.new;
            pairs.do { |p| counts[p] = (counts[p] ? 0) + 1 };
            total = pairs.size;
            entropy = counts.values.collect { |c|
                var p = c / total;
                p.neg * p.log2
            }.sum;
            entropy
        }
    },

    \meanOccupiedTriads: { |midiHistory, sim, tickData|
        tickData.collect { |t| (t[\occupied] ? 0) }.sum / tickData.size.max(1)
    },

    \registerVariance: { |midiHistory, sim, tickData|
        var allMidi = midiHistory.values.flat.select(_.notNil);
        var mean, variance;
        if(allMidi.size < 2) { 0 } {
            mean = allMidi.sum / allMidi.size;
            variance = allMidi.collect { |m| (m - mean).squared }.sum / allMidi.size;
            variance
        }
    },

    \meanInterval: { |midiHistory, sim, tickData|
        var intervals = [];
        midiHistory.values.do { |seq|
            var s = seq.select(_.notNil);
            if(s.size >= 2) {
                (s.size - 1).do { |i|
                    intervals = intervals.add((s[i+1] - s[i]).abs)
                }
            }
        };
        if(intervals.isEmpty) { 0 } { intervals.sum / intervals.size }
    },

    \plrRate: { |midiHistory, sim, tickData|
        // Recent transforms accumulated over the run
        var transforms = sim[\harmonicState][\recentTransforms] ? [];
        transforms.size / tickData.size.max(1)
    },
);


// Run a single sweep: for each value of the parameter, measure all metrics.
~runParamSweep = { |sweep, nTrials = 5, nTicks = 500|
    var results = [];

    sweep[\values].do { |v|
        var trialResults = Dictionary.new;
        ~outcomeMetrics.keysDo { |k| trialResults[k] = [] };

        nTrials.do { |trial|
            var tickData = [];
            thisThread.randSeed = 12345 + trial;
            ~view = (refresh: {});

            ~simulation.spawnAgents(4, 5, 4);
            ~midiHistory = Dictionary.new;
            sweep[\targetPath].(~simulation, v);

            nTicks.do {
                ~simulation.step;
                tickData = tickData.add((
                    impliedFunction: ~simulation[\harmonicState][\impliedFunction],
                    occupied:        (~simulation[\harmonicState][\occupiedTriads] ? []).size
                ));
            };

            ~outcomeMetrics.keysValuesDo { |metricName, metricFn|
                trialResults[metricName] = trialResults[metricName].add(
                    metricFn.(~midiHistory, ~simulation, tickData)
                )
            }
        };

        // Aggregate across trials
        {
            var row = (param: sweep[\param], value: v);
            trialResults.keysValuesDo { |k, vs|
                var m = vs.sum / vs.size;
                row[k]                   = m;
                row[(k ++ "_sd").asSymbol] = {
                    (vs.collect { |x| (x - m).squared }.sum / vs.size).sqrt
                }.value;
            };
            results = results.add(row);
        }.value;
    };
    results
};


// Run all sweeps and write a TSV.
~runAllParamSweeps = { |nTrials = 5, nTicks = 500, outPath = nil|
    var allRows = [];
    var headers = [\param, \value] ++ ~outcomeMetrics.keys.asArray ++
                  ~outcomeMetrics.keys.asArray.collect { |k| (k ++ "_sd").asSymbol };
    var file;

    outPath = outPath ? (thisProcess.nowExecutingPath.dirname ++ "/param_sweep.tsv");

    "".postln;
    "============================================================".postln;
    "  PARAMETER CHARACTERISATION".postln;
    "  % trials × % ticks per (param, value) cell".format(nTrials, nTicks).postln;
    "============================================================".postln;

    ~paramSweepConfig.do { |sweep|
        "".postln;
        "Sweeping %...".format(sweep[\param]).postln;
        allRows = allRows ++ ~runParamSweep.(sweep, nTrials, nTicks);
        "  done (% points)".format(sweep[\values].size).postln;
    };

    // Write TSV
    file = File(outPath, "w");
    file.write(headers.collect(_.asString).join("\t") ++ "\n");
    allRows.do { |row|
        file.write(headers.collect { |h| (row[h] ? "").asString }.join("\t") ++ "\n")
    };
    file.close;
    "".postln;
    "TSV written → %".format(outPath).postln;
    allRows
};
)

// Run with:
   ~paramResults = ~runAllParamSweeps.(5, 500);
   ~paramResults = ~runAllParamSweeps.(5, 10);