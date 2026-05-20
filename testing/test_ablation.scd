// =============================================================================
// test_ablation.scd — Substrate and drive ablation tests
//
// Evaluate AFTER main.scd has loaded the full system.
// Requires ScrambledHexManifold.sc installed in Platform.userExtensionDir
// (recompile class library after adding it).
//
// Tests the central hybrid-architecture claim: that distributing musical
// meaning between substrate-interpretation (Tonnetz geometry encoding
// consonance) and agent-behaviour (drive-model deliberation) produces
// coherent harmonic output that neither component achieves alone.
//
// Three conditions:
//   A. Full system     — Tonnetz + drives (baseline)
//   B. Scrambled       — random pitch classes + drives (substrate ablation)
//   C. Random walk     — Tonnetz + uniform random movement (drive ablation)
//
// Six metrics per condition:
//   1. Functional coherence ratio
//   2. Mean occupied triad count
//   3. Mean implied triad count
//   4. Mean tension level
//   5. PLR transform rate
//   6. Function transition entropy
//
// If the hybrid claim holds:
//   - A should outperform both B and C on coherence metrics
//   - B should show that drives alone (without consonance-encoding geometry)
//     cannot produce coherent harmonic structure
//   - C should show that the Tonnetz alone (without intelligent agent
//     navigation) cannot produce coherent harmonic structure
//
// Birth and death are disabled so that all conditions run with a fixed
// population of agents. This isolates the substrate/drive variable from
// population-size effects.
// =============================================================================

(

// =========================================================================
// 1. INFRASTRUCTURE
// =========================================================================

// --- Sample standard deviation ----------------------------------------------
// Vanilla SuperCollider does NOT define stdDev on Array; it lives in the
// MathLib quark. Define our own so the script works on a stock install.
// Returns 0 for sequences of length < 2.

~sampleStdDev = { |arr|
	var m, n;
	if(arr.isNil or: { arr.size < 2 }) {
		0.0
	} {
		m = arr.mean;
		n = arr.size;
		((arr.collect { |x| (x - m).squared }).sum / (n - 1)).sqrt
	}
};


// --- Transition entropy ------------------------------------------------------
// Shannon entropy of the transition probability matrix for a sequence of
// discrete states. Lower entropy = more predictable transitions.
// Returns 0 for sequences of length < 2.

~transitionEntropy = { |sequence|
	var states, stateIndex, nStates, matrix, entropy, totalWeight;

	if(sequence.size < 2) { 0.0 } {
		states     = sequence.asSet.asArray.sort;
		stateIndex = Dictionary.new;
		nStates    = states.size;

		states.do { |s, i| stateIndex[s] = i };
		matrix = Array.fill(nStates, { Array.fill(nStates, { 0 }) });

		// Build transition count matrix
		(sequence.size - 1).do { |i|
			var from = stateIndex[sequence[i]];
			var to   = stateIndex[sequence[i + 1]];
			matrix[from][to] = matrix[from][to] + 1;
		};

		// Weighted entropy across rows
		entropy     = 0.0;
		totalWeight = 0.0;

		matrix.do { |row|
			var rowSum = row.sum;
			if(rowSum > 0) {
				var h = 0.0;
				row.do { |count|
					if(count > 0) {
						var p = count / rowSum;
						h = h - (p * log2(p));
					}
				};
				entropy     = entropy + (rowSum * h);
				totalWeight = totalWeight + rowSum;
			}
		};

		if(totalWeight > 0) { entropy / totalWeight } { 0.0 }
	}
};


// --- Per-tick metric snapshot -------------------------------------------------

~collectTickMetrics = { |sim|
	var hs = sim[\harmonicState];
	(
		impliedFunction:   hs[\impliedFunction] ? \ambiguous,
		tensionLevel:      hs[\tensionLevel] ? 0.0,
		occupiedTriads:    (hs[\occupiedTriads] ? []).size,
		impliedTriads:     (hs[\impliedTriads] ? []).size,
		// Count transforms logged on this exact step
		plrTransforms:     (hs[\recentTransforms] ? []).count { |e|
			e[\step] == sim[\stepCount]
		}
	)
};


// --- Summary statistics from a single trial ----------------------------------

~summariseTrial = { |tickData|
	var nTicks          = tickData.size.max(1);
	var functionHistory = tickData.collect { |t| t[\impliedFunction] };

	var coherenceRatio = tickData.count { |t|
		t[\impliedFunction] != \ambiguous
	} / nTicks;

	var meanOccupied = tickData.collect { |t| t[\occupiedTriads] }.mean;
	var meanImplied  = tickData.collect { |t| t[\impliedTriads]  }.mean;
	var meanTension  = tickData.collect { |t| t[\tensionLevel]   }.mean;

	// PLR transform rate: total transforms / total ticks
	var totalTransforms = tickData.collect { |t| t[\plrTransforms] }.sum;
	var plrRate         = totalTransforms / nTicks;

	var transEntropy = ~transitionEntropy.(functionHistory);

	(
		coherenceRatio: coherenceRatio,
		meanOccupied:   meanOccupied,
		meanImplied:    meanImplied,
		meanTension:    meanTension,
		plrRate:        plrRate,
		transEntropy:   transEntropy
	)
};


// --- Average across trials ---------------------------------------------------

~averageTrials = { |trialSummaries|
	var keys = [\coherenceRatio, \meanOccupied, \meanImplied,
		\meanTension, \plrRate, \transEntropy];
	var result = ();

	keys.do { |key|
		var values = trialSummaries.collect { |t| t[key] };
		result[key]                     = values.mean;
		result[(key ++ "_sd").asSymbol] = ~sampleStdDev.(values);
	};

	result
};


// =========================================================================
// 2. CONDITION RUNNER
// =========================================================================
// Runs a single condition for nTicks, headlessly. Stubs GUI and MIDI,
// calls sim.step directly in a loop, collects metrics per tick.

~runCondition = { |label, gridFactory, driveOverride, nTicks, nAgents, octave, nTrials|

	var trialSummaries = [];

	// Save globals that step/commit/decide reference
	var savedView           = ~view;
	var savedVoiceView      = ~voiceView;
	var savedRhythmView     = ~rhythmView;
	var savedPlayNote       = ~playNote;
	var savedUpdateMonitors = ~updateMonitors;
	var savedMidiHistory    = ~midiHistory;
	var savedSimulation     = ~simulation;
	var savedDriveModel     = ~driveModel;

	"--- Running condition: % (%  trials × % ticks) ---".format(
		label, nTrials, nTicks).postln;

	nTrials.do { |trial|
		var grid, dm, sim, tickData;
		var seed = 12345 + trial;        // same across conditions, varies per trial

		thisThread.randSeed = seed;      // <-- pair the RNG

		// --- Stub GUI and MIDI ---
		~view            = (refresh: {});
		~voiceView       = nil;
		~rhythmView      = nil;
		~playNote        = { };
		~updateMonitors  = nil;
		~midiHistory     = Dictionary.new;

		// --- Build fresh instances for this trial ---
		grid = gridFactory.();
		dm   = ~driveModelFactory.(nil, grid);
		sim  = ~simulationFactory.(grid, dm);
		dm[\simulation] = sim;

		// Apply drive override if needed (e.g. random walk)
		if(driveOverride.notNil) { driveOverride.(dm) };

		// Patch globals so agent.decide and step's deferred block
		// reference the correct instances
		~driveModel = dm;
		~simulation = sim;

		// --- Spawn agents ---
		sim.spawnAgents(nAgents, octave, 2);

		// Hold population constant — birth/death would change agent count
		// unpredictably across conditions, confounding the comparison.
		sim[\birthEnabled] = false;
		sim[\deathEnabled] = false;

		// Initialise tick state
		sim[\stepCount] = 0;
		sim[\tickTime]  = 0;
		sim[\tickIndex] = 0;

		// --- Run headlessly ---
		tickData = [];

		nTicks.do { |i|
			sim[\tickTime]  = i * sim[\tickSize];
			sim[\tickIndex] = i;

			// step manages stepCount and cyclePos internally
			sim.step;

			tickData = tickData.add(~collectTickMetrics.(sim));
		};

		trialSummaries = trialSummaries.add(~summariseTrial.(tickData));

		"  trial %: coherence=% occupiedTriads=% plrRate=%".format(
			trial + 1,
			trialSummaries.last[\coherenceRatio].round(0.001),
			trialSummaries.last[\meanOccupied].round(0.01),
			trialSummaries.last[\plrRate].round(0.001)
		).postln;
	};

	// --- Restore globals ---
	~view            = savedView;
	~voiceView       = savedVoiceView;
	~rhythmView      = savedRhythmView;
	~playNote        = savedPlayNote;
	~updateMonitors  = savedUpdateMonitors;
	~midiHistory     = savedMidiHistory;
	~simulation      = savedSimulation;
	~driveModel      = savedDriveModel;

	// Return averaged results
	~averageTrials.(trialSummaries)
};


// =========================================================================
// 3. CONDITION DEFINITIONS
// =========================================================================

// --- A. Full system (Tonnetz + drives) ---
~conditionA_grid = { ToroidalHexManifold(24, 12, 12, 7, 4) };

// --- B. Scrambled substrate (random PCs + drives) ---
~conditionB_grid = { ScrambledHexManifold(24, 12, 12) };

// --- C. Random walk (Tonnetz + no drives) ---
~conditionC_grid = { ToroidalHexManifold(24, 12, 12, 7, 4) };

// Override: replace chooseNext with uniform random neighbour selection.
// Returns the same Event shape that resolveCollisions expects.
~randomWalkOverride = { |dm|
	dm[\chooseNext] = { |self, pos, lastDir, otherPos, weights, label,
		recentPos, recentMotion, modeCollection, tensionScore,
		homeTriad, harmonicBias|

		var neighbors = self.grid.wrappedNeighbors(pos.asPoint);
		var chosen    = neighbors.choose;

		// total is used for collision resolution — random priority is fair
		(cell: chosen, total: 1.0.rand, gridDistance: 1)
	};
};


// =========================================================================
// 4. RUN ALL CONDITIONS AND REPORT
// =========================================================================

{
    var labels  = ["Full system", "Scrambled", "Random walk"];
    var metrics = [
        [\coherenceRatio, "Coherence ratio",    "higher = more time in recognisable harmonic function"],
        [\meanOccupied,   "Occupied triads",    "mean fully-occupied triads per tick"],
        [\meanImplied,    "Implied triads",     "mean partially-implied triads per tick"],
        [\meanTension,    "Mean tension",       "average displacement from tonic"],
        [\plrRate,        "PLR transform rate", "valid neo-Riemannian transforms per tick"],
        [\transEntropy,   "Transition entropy", "lower = more predictable harmonic progressions"]
    ];
    var resultFull, resultScrambled, resultRandomWalk, results;
    var pad;

    "".postln;
    "============================================================".postln;
    "  SUBSTRATE & DRIVE ABLATION TEST".postln;
    "============================================================".postln;
    "".postln;

    resultFull = ~runCondition.(
        "A: Full system (Tonnetz + drives)",
        ~conditionA_grid, nil, 1000, 4, 5, 20
    );
    "".postln;

    resultScrambled = ~runCondition.(
        "B: Scrambled substrate (random PCs + drives)",
        ~conditionB_grid, nil, 1000, 4, 5, 20
    );
    "".postln;

    resultRandomWalk = ~runCondition.(
        "C: Random walk (Tonnetz + no drives)",
        ~conditionC_grid, ~randomWalkOverride, 1000, 4, 5, 20
    );

    results = [resultFull, resultScrambled, resultRandomWalk];

    // --- Sanity check: catch a nil result before reporting falls over ---
    if(results.any(_.isNil)) {
        "ERROR: at least one condition returned nil:".postln;
        [resultFull, resultScrambled, resultRandomWalk].do { |r, i|
            "  %: %".format(labels[i], if(r.isNil) { "NIL" } { "ok" }).postln
        };
        "Aborting reporting.".postln;
    } {
        "".postln;
        "============================================================".postln;
        "  RESULTS".postln;
        "============================================================".postln;
        "".postln;

        pad = { |str, n| str.asString.padRight(n, " ") };

        (pad.("Metric", 24) ++ " | "
            ++ pad.(labels[0], 18) ++ " | "
            ++ pad.(labels[1], 18) ++ " | "
            ++ pad.(labels[2], 18)).postln;
        ("-" ! 90).join.postln;

        metrics.do { |row|
            var metricKey   = row[0];
            var metricLabel = row[1];
            var sdKey       = (metricKey ++ "_sd").asSymbol;

            var values = results.collect { |r|
                var mean = r[metricKey];
                var sd   = r[sdKey];
                "% ± %".format(mean.round(0.001), sd.round(0.001))
            };

            (pad.(metricLabel, 24) ++ " | "
                ++ pad.(values[0], 18) ++ " | "
                ++ pad.(values[1], 18) ++ " | "
                ++ pad.(values[2], 18)).postln;
        };

		"".postln;
		"--- Drive surplus over geometric baseline (A − C) ---".postln;
		[
			[\occupiedTriads, "Occupied triads"],
			[\meanImplied,    "Implied triads"],
			[\plrRate,        "PLR transform rate"],
			[\transEntropy,   "Transition entropy"],
			[\meanTension,    "Mean tension"]
		].do { |row|
			var key      = row[0];
			var label    = row[1];
			var aMean    = resultFull[key];
			var cMean    = resultRandomWalk[key];
			var aSD      = resultFull[(key ++ "_sd").asSymbol];
			var cSD      = resultRandomWalk[(key ++ "_sd").asSymbol];
			var diff     = aMean - cMean;
			// Pooled SD assuming independent trials
			var pooledSD = ((aSD.squared + cSD.squared) / 2).sqrt;
			var direction = if(diff > 0) { "↑" } { if(diff < 0) { "↓" } { "—" } };
			"  % %  : % (pooled SD %)".format(
				label.padRight(20, " "),
				direction,
				diff.round(0.001),
				pooledSD.round(0.001)
			).postln;
		};
		"".postln;

        "Interpretation:".postln;
        "  If the hybrid claim holds, condition A should outperform both B and C".postln;
        "  on coherence ratio, occupied triads, and PLR transform rate.".postln;
        "  Transition entropy should be lowest for A (most structured progressions).".postln;
        "".postln;
        "  B (scrambled) tests: do drives alone produce coherence without".postln;
        "  consonance-encoding geometry?".postln;
        "  C (random walk) tests: does the Tonnetz alone produce coherence".postln;
        "  without intelligent navigation?".postln;
        "".postln;

        [1, 2].do { |i|
            var ablationLabel = labels[i];
            var baseCoherence = resultFull[\coherenceRatio];
            var ablCoherence  = results[i][\coherenceRatio];
            var drop          = if(baseCoherence > 0) {
                ((baseCoherence - ablCoherence) / baseCoherence * 100).round(0.1)
            } { 0 };

            "  % → coherence dropped by %%".format(ablationLabel, drop, "%").postln;
        };

        "".postln;
        "============================================================".postln;
        "  TEST COMPLETE".postln;
        "============================================================".postln;
    };

    nil
}.value;

)
