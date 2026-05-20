// =============================================================================
// Tonnetz Agent System — Modal & Tonal Quantitative Tests
// =============================================================================
// Usage:
//   Load after the main system is up. Then:
//     ~modalTests.debugModeLock.();        // immediate diagnostic
//     ~modalTests.runAll.(duration: 200);  // full test suite over N ticks
//     ~modalTests.collectionPurity.(duration: 200);  // individual tests
//
// Tests assume the simulation is running — start it manually before calling.
// Results are posted to the interpreter and optionally written to CSV.
// =============================================================================

(
~modalTests = (

	// -----------------------------------------------------------------
	// Utility: resolve the current collection from the simulation state.
	// Uses lockedModeKey/tonicPC if locked, else dominant agent mode.
	// -----------------------------------------------------------------
	currentCollection: { |self|
		var sim        = ~simulation;
		var tonicPC    = (sim[\harmonicState][\tonicPC] ? 0).round.asInteger.mod(12);
		var modeKey;

		if(sim[\modeLocked] == true) {
			modeKey = sim[\lockedModeKey] ? \major;
		} {
			var modes = sim[\agents].collect { |a| a[\modeKey] ? \major };
			var counts = Dictionary.new;
			modes.do { |m| counts[m] = (counts[m] ? 0) + 1 };
			modeKey = counts.keys.asArray.maxItem { |k| counts[k] };
		};

		(~modeCollections[modeKey] ? ~modeCollections[\major])
			.collect { |pc| (pc + tonicPC).mod(12) }
	},

	noteNames: ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"],

	// -----------------------------------------------------------------
	// DEBUG — Mode lock verification
	// -----------------------------------------------------------------
	// Checks that when mode and tonic are locked, every agent's
	// modeCollection matches the locked collection, and no agent is
	// currently sitting on an out-of-collection PC.
	// -----------------------------------------------------------------
	debugModeLock: { |self|
		var sim     = ~simulation;
		var locked  = sim[\modeLocked] ? false;
		var tonicLock = sim[\tonicLocked] ? false;
		var lockedKey = sim[\lockedModeKey] ? \major;
		var lockedTonic = sim[\lockedTonicPC] ? 0;
		var expectedColl, agentsOnIllegal, agentsMismatchedColl;

		"================== MODE LOCK DEBUG ==================".postln;
		"Mode locked:   %".format(locked).postln;
		"Tonic locked:  %".format(tonicLock).postln;
		"Locked key:    %".format(lockedKey).postln;
		"Locked tonic:  % (%)".format(lockedTonic, self.noteNames[lockedTonic]).postln;
		"Current tonic (harmonicState): %".format(
			(sim[\harmonicState][\tonicPC] ? 0).round(0.01)
		).postln;
		"".postln;

		if(locked.not) {
			"Mode is NOT locked — further checks skipped. Lock it first.".postln;
			"===================================================".postln;
			^nil;
		};

		expectedColl = (~modeCollections[lockedKey] ? ~modeCollections[\major])
			.collect { |pc| (pc + lockedTonic).mod(12) }.sort;

		"Expected collection: [%]".format(
			expectedColl.collect { |pc| self.noteNames[pc] }.join(", ")
		).postln;
		"".postln;

		// Per-agent verification
		"Per-agent state:".postln;
		sim[\agents].do { |a|
			var aColl = (a[\modeCollection] ? []).asSortedList.asArray;
			var aPC   = sim.grid.pitchClassAt(a[\pos].x, a[\pos].y).asInteger;
			var collMatch = (aColl == expectedColl);
			var onLegal   = expectedColl.includes(aPC);

			"  agent % | modeKey=% | coll=[%] | pos PC=% (%) | coll✓=% | pos✓=%".format(
				a[\label],
				a[\modeKey],
				aColl.collect { |pc| self.noteNames[pc] }.join(","),
				aPC,
				self.noteNames[aPC],
				collMatch,
				onLegal
			).postln;
		};

		// Aggregate health checks
		agentsMismatchedColl = sim[\agents].count { |a|
			((a[\modeCollection] ? []).asSortedList.asArray != expectedColl)
		};
		agentsOnIllegal = sim[\agents].count { |a|
			var pc = sim.grid.pitchClassAt(a[\pos].x, a[\pos].y).asInteger;
			expectedColl.includes(pc).not
		};

		"".postln;
		"Summary:".postln;
		"  Agents with mismatched modeCollection: % / %".format(
			agentsMismatchedColl, sim[\agents].size
		).postln;
		"  Agents currently on out-of-collection PC: % / %".format(
			agentsOnIllegal, sim[\agents].size
		).postln;

		if(agentsMismatchedColl > 0) {
			"  ⚠  Some agents do not have the locked collection — lock not propagating.".postln
		};
		if(agentsOnIllegal > 0 and: { (sim[\modeStrictness] ? 0.7) >= 1.0 }) {
			"  ⚠  Agents sitting on non-collection PCs despite full strictness.".postln
		};
		"===================================================".postln;
	},

	// -----------------------------------------------------------------
	// TEST 1 — Collection purity
	// -----------------------------------------------------------------
	// Fraction of sounded MIDI note events whose PC falls in the
	// target collection. For locked C major, target = 1.0.
	// -----------------------------------------------------------------
	collectionPurity: { |self, duration = 200|
		var sim        = ~simulation;
		var collection = self.currentCollection.(self);
		var sounded    = List.new;
		var inColl, outColl, purity;
		var startTick  = sim[\stepCount] ? 0;

		"Running collectionPurity test for % ticks...".format(duration).postln;

		// Sample every tick for `duration` ticks
		duration.do {
			sim[\agents].do { |a|
				var m = a[\currentMidi];
				if(m.notNil) { sounded.add(m.mod(12)) }
			};
			(sim[\tickSize] ? 1.0).wait;
		};

		if(sounded.isEmpty) {
			"No notes sounded during test window.".postln;
			^(purity: 0, sounded: 0);
		};

		inColl  = sounded.count { |pc| collection.includes(pc) };
		outColl = sounded.size - inColl;
		purity  = inColl / sounded.size;

		"--- Collection Purity ---".postln;
		"Collection: [%]".format(
			collection.sort.collect { |pc| self.noteNames[pc] }.join(",")
		).postln;
		"Total notes sampled: %".format(sounded.size).postln;
		"In collection:       % (%%)".format(inColl,  (purity * 100).round(0.1)).postln;
		"Out of collection:   % (%%)".format(outColl, ((1 - purity) * 100).round(0.1)).postln;
		"Purity score:        %".format(purity.round(0.001)).postln;
		"-------------------------".postln;

		(purity: purity, sounded: sounded.size, inCollection: inColl)
	},

	// -----------------------------------------------------------------
	// TEST 2 — Chord-type distribution
	// -----------------------------------------------------------------
	// Every `sampleEvery` ticks, snapshot all current PCs and classify:
	//   diatonicTriad | diatonicSeventh | nonDiatonic | cluster | incomplete
	// -----------------------------------------------------------------
	chordDistribution: { |self, duration = 200, sampleEvery = 4|
		var sim        = ~simulation;
		var collection = self.currentCollection.(self);
		var counts     = (
			diatonicTriad:   0,
			diatonicSeventh: 0,
			diatonicNonTriad: 0,
			outOfCollection: 0,
			incomplete:      0
		);
		var total = 0;

		// Diatonic triads in the collection
		var diatonicTriads = collection.collect { |root|
			// Build third and fifth by scale steps
			var sortedColl = collection.asSortedList.asArray;
			var rootIdx    = sortedColl.indexOf(root);
			if(rootIdx.isNil) { [root] } {
				[
					root,
					sortedColl.wrapAt(rootIdx + 2),
					sortedColl.wrapAt(rootIdx + 4)
				].sort
			}
		};
		var diatonicSevenths = collection.collect { |root|
			var sortedColl = collection.asSortedList.asArray;
			var rootIdx    = sortedColl.indexOf(root);
			if(rootIdx.isNil) { [root] } {
				[
					root,
					sortedColl.wrapAt(rootIdx + 2),
					sortedColl.wrapAt(rootIdx + 4),
					sortedColl.wrapAt(rootIdx + 6)
				].sort
			}
		};

		"Running chordDistribution test for % ticks...".format(duration).postln;

		(duration / sampleEvery).asInteger.do {
			var pcs = sim[\agents]
				.collect { |a| a[\currentMidi] }
				.select(_.notNil)
				.collect(_.mod(12))
				.asSet.asArray.sort;

			var classification;
			var inCollection = pcs.every { |pc| collection.includes(pc) };

			if(pcs.size < 3) {
				classification = \incomplete;
			} {
				if(inCollection.not) {
					classification = \outOfCollection;
				} {
					if(pcs.size == 3 and: { diatonicTriads.any { |t| t.sort == pcs } }) {
						classification = \diatonicTriad;
					} {
						if(pcs.size == 4 and: { diatonicSevenths.any { |t| t.sort == pcs } }) {
							classification = \diatonicSeventh;
						} {
							classification = \diatonicNonTriad;
						}
					}
				}
			};

			counts[classification] = counts[classification] + 1;
			total = total + 1;

			(sim[\tickSize] ? 1.0 * sampleEvery).wait;
		};

		"--- Chord Distribution ---".postln;
		"Samples: %".format(total).postln;
		counts.keysValuesDo { |k, v|
			"  %: % (%%)".format(
				k, v, ((v / total.max(1)) * 100).round(0.1)
			).postln
		};
		"--------------------------".postln;

		counts
	},

	// -----------------------------------------------------------------
	// TEST 3 — Root progression statistics
	// -----------------------------------------------------------------
	// Detects chord root every `sampleEvery` ticks, records transitions,
	// and reports the transition matrix. Also flags the most frequent
	// progressions.
	// -----------------------------------------------------------------
	rootProgression: { |self, duration = 200, sampleEvery = 4|
		var sim        = ~simulation;
		var collection = self.currentCollection.(self);
		var roots      = List.new;
		var lastRoot   = nil;
		var transitions = Dictionary.new;
		var total = 0;

		// build diatonic triad templates for root detection
		var diatonicTriads = collection.collect { |root|
			var sorted = collection.asSortedList.asArray;
			var rootIdx = sorted.indexOf(root);
			if(rootIdx.isNil) { [root] } {
				[root, sorted.wrapAt(rootIdx + 2), sorted.wrapAt(rootIdx + 4)].sort
			}
		};

		"Running rootProgression test for % ticks...".format(duration).postln;

		(duration / sampleEvery).asInteger.do {
			var pcs = sim[\agents]
				.collect { |a| a[\currentMidi] }
				.select(_.notNil)
				.collect(_.mod(12))
				.asSet.asArray.sort;
			var matchedRoot = nil;

			// match against diatonic triad templates
			if(pcs.size >= 3) {
				diatonicTriads.do { |triad|
					if(matchedRoot.isNil and: { triad.every { |pc| pcs.includes(pc) } }) {
						matchedRoot = triad[0];
					}
				}
			};

			if(matchedRoot.notNil) {
				roots.add(matchedRoot);
				if(lastRoot.notNil and: { lastRoot != matchedRoot }) {
					var key = (lastRoot - matchedRoot).mod(12);
					transitions[key] = (transitions[key] ? 0) + 1;
					total = total + 1;
				};
				lastRoot = matchedRoot;
			};

			(sim[\tickSize] ? 1.0 * sampleEvery).wait;
		};

		"--- Root Progression ---".postln;
		"Chord samples:   %".format(roots.size).postln;
		"Transitions:     %".format(total).postln;
		"".postln;
		"Transition intervals (semitones down, wrapped 0-11):".postln;
		(0..11).do { |i|
			var count = transitions[i] ? 0;
			var pct   = if(total > 0) { (count / total) * 100 } { 0 };
			var label = switch(i,
				5,  "(↑P4, V→I equiv)",
				7,  "(↓P4, I→V equiv)",
				2,  "(↑m7/↓M2)",
				10, "(↑M2/↓m7)",
				""
			);
			"  +%: % occurrences (%%) %".format(
				i.asString.padLeft(2), count,
				pct.round(0.1), label
			).postln
		};
		"------------------------".postln;

		(transitions: transitions, total: total, roots: roots.asArray)
	},

	// -----------------------------------------------------------------
	// TEST 4 — Tonic gravitational return
	// -----------------------------------------------------------------
	// Tracks harmonicCentre over time. A "return" is when the centroid
	// passes within ±0.5 of the locked/current tonic. Reports return
	// frequency and inter-return interval distribution.
	// -----------------------------------------------------------------
	tonicReturn: { |self, duration = 200|
		var sim = ~simulation;
		var tonicPC  = (sim[\harmonicState][\tonicPC] ? 0).round.asInteger.mod(12);
		var history  = List.new;
		var returns  = List.new;
		var wasNear  = false;
		var intervals, meanInterval, medianInterval;

		if(sim[\tonicLocked] == true) {
			"Tonic return test skipped — tonic is locked (centroid is static by definition).".postln;
			^(skipped: true, reason: \tonicLocked);
		};

		"Running tonicReturn test for % ticks...".format(duration).postln;

		duration.do { |tick|
			var centre = sim[\harmonicCentre] ? tonicPC;
			var dist   = (centre - tonicPC).abs.mod(12);
			var minDist = dist.min(12 - dist);
			var isNear = (minDist <= 0.5);

			history.add(centre);

			// Rising-edge return detection
			if(isNear and: { wasNear.not }) {
				returns.add(tick);
			};
			wasNear = isNear;

			(sim[\tickSize] ? 1.0).wait;
		};

		"--- Tonic Gravitational Return ---".postln;
		"Target tonic:    % (%)".format(tonicPC, self.noteNames[tonicPC]).postln;
		"Duration:        % ticks".format(duration).postln;
		"Return events:   %".format(returns.size).postln;

		if(returns.size >= 2) {
			intervals = (1..returns.size-1).collect { |i| returns[i] - returns[i-1] };
			meanInterval = intervals.sum / intervals.size;
			medianInterval = intervals.asSortedList.asArray.at(intervals.size div: 2);

			"Mean interval:   % ticks".format(meanInterval.round(0.1)).postln;
			"Median interval: % ticks".format(medianInterval).postln;
			"Min interval:    % ticks".format(intervals.minItem).postln;
			"Max interval:    % ticks".format(intervals.maxItem).postln;
		} {
			"(Too few returns to compute interval statistics.)".postln;
		};

		"Centroid range:  % — %".format(
			history.minItem.round(0.01),
			history.maxItem.round(0.01)
		).postln;
		"----------------------------------".postln;

		(returns: returns.asArray, history: history.asArray)
	},

	// -----------------------------------------------------------------
	// Run everything as a coherent suite
	// -----------------------------------------------------------------
	runAll: { |self, duration = 200|
		var results = Dictionary.new;

		Routine({
			"".postln;
			"========== MODAL TEST SUITE ==========".postln;
			"Duration per test: % ticks".format(duration).postln;
			"Current collection:".postln;
			"  [%]".format(
				self.currentCollection.(self).sort
					.collect { |pc| self.noteNames[pc] }.join(",")
			).postln;
			"======================================".postln;
			"".postln;

			self.debugModeLock.(self);
			"".postln;

			results[\purity] = self.collectionPurity.(self, duration);
			"".postln;

			results[\chords] = self.chordDistribution.(self, duration);
			"".postln;

			results[\progression] = self.rootProgression.(self, duration);
			"".postln;

			results[\tonic] = self.tonicReturn.(self, duration);
			"".postln;

			"========== TEST SUITE COMPLETE ==========".postln;
			~modalTests[\lastResults] = results;
			"(Results stored in ~modalTests[\\lastResults])".postln;
		}).play;

		nil
	},

	// -----------------------------------------------------------------
	// Optional CSV export of the last run
	// -----------------------------------------------------------------
	exportCSV: { |self, path|
		var r = ~modalTests[\lastResults];
		var f;
		path = path ? ("~/tonnetz_test_results.csv".standardizePath);

		if(r.isNil) {
			"No results to export. Run runAll first.".postln;
			^nil;
		};

		f = File(path, "w");
		f.write("metric,value\n");
		f.write("collection_purity,%\n".format(r[\purity][\purity]));
		f.write("notes_sampled,%\n".format(r[\purity][\sounded]));
		r[\chords].keysValuesDo { |k, v|
			f.write("chord_%,%\n".format(k, v))
		};
		f.write("root_transitions_total,%\n".format(r[\progression][\total]));
		f.write("tonic_returns,%\n".format(r[\tonic][\returns].size));
		f.close;
		"Exported to: %".format(path).postln;
	},
);

"~modalTests loaded. Available methods:".postln;
"  ~modalTests.debugModeLock.(~modalTests);".postln;
"  ~modalTests.runAll.(~modalTests, duration: 200);".postln;
"  ~modalTests.collectionPurity.(~modalTests, duration: 200);".postln;
"  ~modalTests.chordDistribution.(~modalTests, duration: 200);".postln;
"  ~modalTests.rootProgression.(~modalTests, duration: 200);".postln;
"  ~modalTests.tonicReturn.(~modalTests, duration: 200);".postln;
"  ~modalTests.exportCSV.(~modalTests);".postln;
)
