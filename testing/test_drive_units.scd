// =============================================================================
// test_drive_units.scd
//
// Behavioural unit tests for individual drives. Each test isolates one drive
// by setting its weight to low / medium / high values while holding all
// others at the schema default, then measures the drive's predicted effect
// on output. Passes if the observed slope of metric-vs-weight matches the
// predicted direction with statistical significance.
//
// NOTE: This is a preliminary unit-testing harness. Some drives produce clean
// passing results (voiceLeading at t=-2.25). Larger trial counts (n>=32)
// would be the natural next iteration.
//
// Run order: load main.scd first, then evaluate this file.
// =============================================================================

(
~driveUnitTests = [
    (
        drive:        \tonicPull,
        prediction:   \positive,
        predicate:    "fraction of agent-PCs within tonic triad",
        weights:      [0.0, 0.3, 0.6, 0.9],
        metric: { |midiHistory, sim|
            // Count agent notes whose PC falls within the current tonic triad
            var tonicPC  = (sim[\harmonicState][\tonicPC] ? 0).round.asInteger.mod(12);
            var triadPCs = [0, 4, 7].collect { |i| (tonicPC + i).mod(12) };
            var allMidi  = midiHistory.values.flat;
            if(allMidi.isEmpty) { 0 } {
                allMidi.count { |m| triadPCs.includes(m.asInteger.mod(12)) }
                / allMidi.size
            }
        }
    ),

    (
        drive:        \voiceLeading,
        prediction:   \negative,
        predicate:    "mean absolute semitone interval between consecutive notes",
        weights:      [0.0, 0.3, 0.6, 0.9],
        metric: { |midiHistory, sim|
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
        }
    ),

    (
        drive:        \modeCoherence,
        prediction:   \negative,
        predicate:    "fraction of agent-PCs outside the mode collection",
        weights:      [0.0, 0.3, 0.6, 0.9],
        metric: { |midiHistory, sim|
            var outOfMode = 0;
            var total     = 0;
            sim[\agents].do { |a|
                var modeColl = a[\modeCollection] ? [];
                var history  = midiHistory[a[\id]] ? [];
                history.do { |m|
                    if(m.notNil) {
                        total = total + 1;
                        if(modeColl.includes(m.asInteger.mod(12)).not) {
                            outOfMode = outOfMode + 1
                        }
                    }
                }
            };
            if(total == 0) { 0 } { outOfMode / total }
        }
    ),

    (
        drive:        \chordTone,
        prediction:   \positive,
        predicate:    "fraction of agent-PCs that occupy any implied/occupied triad",
        weights:      [0.0, 0.3, 0.6, 0.9],
        metric: { |midiHistory, sim|
            // At end of run: how often did agent PCs belong to a triad the
            // population was implying. Approximated by checking against the
            // final occupied + implied triad PC-sets.
            var triads  = ((sim[\harmonicState][\occupiedTriads] ? [])
                          ++ (sim[\harmonicState][\impliedTriads] ? []))
                         .collect { |t| t[\pcs].collect(_.asInteger) }.flat;
            var allPCs  = midiHistory.values.flat.collect { |m| m.asInteger.mod(12) };
            if(allPCs.isEmpty) { 0 } {
                allPCs.count { |pc| triads.includes(pc) } / allPCs.size
            }
        }
    ),

    (
        drive:        \momentum,
        prediction:   \positive,
        predicate:    "mean directional consistency of consecutive intervals",
        weights:      [0.0, 0.3, 0.6, 0.9],
        metric: { |midiHistory, sim|
            // Fraction of consecutive-interval pairs that share sign
            var same = 0;
            var total = 0;
            midiHistory.values.do { |seq|
                var s = seq.select(_.notNil);
                if(s.size >= 3) {
                    (s.size - 2).do { |i|
                        var d1 = s[i+1] - s[i];
                        var d2 = s[i+2] - s[i+1];
                        if(d1 != 0 and: { d2 != 0 }) {
                            total = total + 1;
                            if(d1.sign == d2.sign) { same = same + 1 }
                        }
                    }
                }
            };
            if(total == 0) { 0 } { same / total }
        }
    ),

    (
        drive:        \stigmergy,
        prediction:   \positive,
        predicate:    "fraction of moves toward a recently-visited peer cell",
        weights:      [0.0, 0.3, 0.6, 0.9],
        metric: { |midiHistory, sim|
            // Surrogate: variance of pairwise PC-distances across agents.
            // High stigmergy should compress distances. Lower variance = pass.
            // (We invert sign by negating: a positive slope on -variance
            // = compression of agent PC spread under higher stigmergy.)
            var pcs = sim[\agents].collect { |a|
                (a[\currentMidi] ? 60).asInteger.mod(12)
            };
            if(pcs.size < 2) { 0 } {
                var mean = pcs.sum / pcs.size;
                var variance  = pcs.collect { |p| (p - mean).squared }.sum / pcs.size;
                variance.neg   // negate so positive prediction = compression
            }
        }
    ),
];


// -----------------------------------------------------------------------------
// Run a single unit test: sweep the drive across its weight values, measure
// the metric at each, regress metric on weight, return slope and direction.
// -----------------------------------------------------------------------------

~runDriveUnitTest = { |test, nTrials = 8, nTicks = 300|
    var weightValues = test[\weights];
    var driveName    = test[\drive];
    var results      = [];

    // Save real GUI/state references
    var savedView                  = ~view;
    var savedVoiceView             = ~voiceView;
    var savedRhythmView            = ~rhythmView;
    var savedUpdateMonitors        = ~updateMonitors;
    var savedMidiHistory           = ~midiHistory;
    var savedMidiHistorySampled    = ~midiHistorySampled;
    var savedPlayNote              = ~playNote;

    // ACTUALLY stub everything (the bug was that this block was identical
    // to the restore block, so nothing got stubbed and ~playNote kept
    // queueing notes on TempoClock).
    ~view              = (refresh: {});
    ~voiceView         = (refresh: {});
    ~rhythmView        = (refresh: {});
    ~updateMonitors    = { };
    ~playNote          = { |midi, vel=100, dur, channel, atBeat| };

    weightValues.do { |w|
        var trialMetrics = [];

        nTrials.do { |trial|
            var seed = 12345 + trial;
            var metricValue;

            thisThread.randSeed = seed;

            ~simulation.spawnAgents(4, 5, 4);
            ~midiHistory        = Dictionary.new;
            ~midiHistorySampled = Dictionary.new;   // <-- this was the crash

            // ---------------------------------------------------------------
            // Deterministic weights: every drive set to schema default,
            // except the target drive which gets the swept value. This
            // removes per-agent character noise from the test entirely.
            // ---------------------------------------------------------------
            ~simulation[\agents].do { |agent|
                ~driveRegistry.do { |d|
                    var defaultW = (~presetSchema[\agentWeights][d[\name]]
                                    !? { |s| s[\default] }) ? 0.3;
                    agent[\weights][d[\name]] = if(d[\name] == driveName) {
                        w
                    } {
                        defaultW
                    }
                }
            };

			// ---------------------------------------------------------------
			// Run nTicks. step's deferred block will fire but does nothing
			// visible (all GUI hooks stubbed). midiHistory is written here,
			// synchronously, so the metric below sees a populated history.
			// ---------------------------------------------------------------
			nTicks.do {
				~simulation.step;

				~simulation[\agents].do { |agent|
					var midi   = agent[\currentMidi];
					var agentID = agent[\id];
					if(midi.notNil and: { agentID.notNil }) {
						var sampled  = ~midiHistorySampled[agentID];
						var distinct = ~midiHistory[agentID];

						// Defensive init — never index a nil
						if(sampled.isNil)  { sampled  = [] };
						if(distinct.isNil) { distinct = [] };

						// Per-tick sample (for fraction-of-time metrics)
						~midiHistorySampled[agentID] = (sampled ++ [midi]).keep(-256);

						// Distinct-note sequence (for consecutive-interval metrics)
						if(distinct.isEmpty or: { distinct.last != midi }) {
							~midiHistory[agentID] = (distinct ++ [midi]).keep(-32);
						};
					};
				};
			};

			"  midiHistory size after run: %, total notes: %".format(
				~midiHistory.size,
				~midiHistory.values.flat.size
			).postln;

            metricValue = test[\metric].(~midiHistory, ~simulation);
            trialMetrics = trialMetrics.add(metricValue);
        };

        results = results.add((
            weight: w,
            mean:   trialMetrics.sum / trialMetrics.size,
            sd:     {
                var m = trialMetrics.sum / trialMetrics.size;
                (trialMetrics.collect { |v| (v - m).squared }.sum / trialMetrics.size).sqrt
            }.value
        ));
    };

    // -------------------------------------------------------------------------
    // Linear regression of metric vs weight
    // -------------------------------------------------------------------------
    {
        var xs    = results.collect(_[\weight]);
        var ys    = results.collect(_[\mean]);
        var n     = xs.size;
        var meanX = xs.sum / n;
        var meanY = ys.sum / n;
        var num   = (xs collect: { |x, i| (x - meanX) * (ys[i] - meanY) }).sum;
        var den   = xs.collect { |x| (x - meanX).squared }.sum;
        var slope = if(den > 0) { num / den } { 0 };

        var predictedYs = xs.collect { |x| meanY + (slope * (x - meanX)) };
        var residuals   = (ys collect: { |y, i| y - predictedYs[i] });
        var residSD     = (residuals.collect(_.squared).sum / (n - 2).max(1)).sqrt;
        var slopeSE     = if(den > 0) { residSD / den.sqrt } { 1 };
        var tStat       = if(slopeSE > 0) { slope / slopeSE } { 0 };
        var resultEvent;

        resultEvent = (
            drive:      driveName,
            prediction: test[\prediction],
            predicate:  test[\predicate],
            points:     results,
            slope:      slope,
            slopeSE:    slopeSE,
            tStat:      tStat,
            passed: switch(test[\prediction],
                \positive, { slope > 0 and: { tStat.abs > 2 } },
                \negative, { slope < 0 and: { tStat.abs > 2 } }
            )
        );

        // ---------------------------------------------------------------------
        // Restore the real GUI/state references before returning
        // ---------------------------------------------------------------------

        ~view              = savedView;
        ~voiceView         = savedVoiceView;
        ~rhythmView        = savedRhythmView;
        ~updateMonitors    = savedUpdateMonitors;
        ~midiHistory       = savedMidiHistory;
        ~midiHistorySampled = savedMidiHistorySampled;
        ~playNote          = savedPlayNote;

        resultEvent
    }.value
};


// -----------------------------------------------------------------------------
// Run all unit tests, format a table.
// -----------------------------------------------------------------------------

~runAllDriveUnitTests = { |nTrials = 8, nTicks = 300|
    var allResults  = [];
    var savedSim    = ~simulation;
    var savedMidi   = ~midiHistory;
    var savedView   = ~view;
    var pad;

    "".postln;
    "============================================================".postln;
    "  DRIVE UNIT TESTS".postln;
    "  % trials × % ticks per (drive, weight) cell".format(nTrials, nTicks).postln;
    "============================================================".postln;
    "".postln;

    ~driveUnitTests.do { |test|
        var result;
        "Testing %...".format(test[\drive]).postln;
        result = ~runDriveUnitTest.(test, nTrials, nTicks);
        allResults = allResults.add(result);

        "  predicate: %".format(test[\predicate]).postln;
        "  sweep:".postln;
        result[\points].do { |p|
            "    weight=% → metric=% (±%)".format(
                p[\weight].round(0.01),
                p[\mean].round(0.001),
                p[\sd].round(0.001)
            ).postln;
        };
        "  slope=% (SE=%), t=%, prediction=%, result=%".format(
            result[\slope].round(0.001),
            result[\slopeSE].round(0.001),
            result[\tStat].round(0.01),
            test[\prediction],
            if(result[\passed]) { "PASS" } { "FAIL/INCONCLUSIVE" }
        ).postln;
        "".postln;
    };

    "============================================================".postln;
    "  SUMMARY".postln;
    "============================================================".postln;
    "".postln;

    pad = { |s, n| s.asString.padRight(n, " ") };

    (pad.("Drive", 22) ++ " | " ++ pad.("Predicted", 10)
        ++ " | " ++ pad.("Slope", 10) ++ " | " ++ pad.("t", 8)
        ++ " | Result").postln;
    ("-" ! 90).join.postln;

    allResults.do { |r|
        (pad.(r[\drive], 22) ++ " | "
            ++ pad.(r[\prediction], 10) ++ " | "
            ++ pad.(r[\slope].round(0.001), 10) ++ " | "
            ++ pad.(r[\tStat].round(0.01), 8) ++ " | "
            ++ if(r[\passed]) { "PASS" } { "INCONCLUSIVE" }).postln;
    };

    "".postln;
    "Pass rate: % / %".format(
        allResults.count(_[\passed]), allResults.size
    ).postln;

    // Restore
    ~simulation   = savedSim;
    ~midiHistory  = savedMidi;
    ~view         = savedView;

    allResults
};
)

// Run with:
   ~unitResults = ~runAllDriveUnitTests.(8, 300);
//
// Or quick test:
   ~unitResults = ~runAllDriveUnitTests.(2, 50);
