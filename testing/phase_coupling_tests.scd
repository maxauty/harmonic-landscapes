// =============================================================================
// Phase Coupling Tests
// =============================================================================
// Diagnostic suite for the Kuramoto-style phase coupling mechanism.
// Tests run on the live simulation; they perturb agent phases and observe
// convergence behaviour over a number of ticks.
//
// Usage:
//   ~phaseCouplingTests.runAll.(~phaseCouplingTests, duration: 100);
//   ~phaseCouplingTests.convergence.(~phaseCouplingTests);
//   ~phaseCouplingTests.anchor.(~phaseCouplingTests);
//   ~phaseCouplingTests.zeroCoupling.(~phaseCouplingTests);
//   ~phaseCouplingTests.wrapAround.(~phaseCouplingTests);
//   ~phaseCouplingTests.consistency.(~phaseCouplingTests);
//   ~phaseCouplingTests.snapshot.(~phaseCouplingTests);
// =============================================================================

(
~phaseCouplingTests = (

	// -------------------------------------------------------------------------
	// Utility: snapshot of current phase state across all agents.
	// -------------------------------------------------------------------------
	snapshot: { |self|
		var agents = ~simulation[\agents];
		"--- Phase snapshot ---".postln;
		"cyclePos: %  cycleLen: %".format(
			~simulation[\cyclePos] ? 0,
			~simulation[\globalCycleLen] ? 16
		).postln;
		agents.do { |a|
			"  agent % | phase=% | phaseFloat=% | coupling=% | pulses=%".format(
				a[\label],
				a[\rhythm][\phase],
				(a[\rhythm][\phaseFloat] ? a[\rhythm][\phase]).round(0.001),
				(a[\weights][\phaseCoupling] ? 0.0).round(0.001),
				a[\rhythm][\pulses]
			).postln
		};
		"-----------------------".postln;
	},

	// -------------------------------------------------------------------------
	// Compute circular variance of agent phases — close to 0 = synchronised,
	// close to 1 = uniformly distributed around the cycle. Standard order
	// parameter for Kuramoto systems.
	// -------------------------------------------------------------------------
	circularVariance: { |self|
		var agents   = ~simulation[\agents];
		var cycleLen = ~simulation[\globalCycleLen] ? 16;
		var phases, sumSin, sumCos, magnitude;
		var result = 1.0;
		if(agents.size >= 1) {
			phases = agents.collect { |a|
				((a[\rhythm][\phaseFloat] ? a[\rhythm][\phase])
					/ cycleLen) * 2pi
			};
			sumSin = phases.collect(_.sin).sum / agents.size;
			sumCos = phases.collect(_.cos).sum / agents.size;
			magnitude = (sumSin.squared + sumCos.squared).sqrt;
			result = 1.0 - magnitude;
		};
		result
	},

	// -------------------------------------------------------------------------
	// Apply a phase to an agent, updating both integer and float
	// representations and regenerating the pattern.
	// -------------------------------------------------------------------------
	setAgentPhase: { |self, agent, newPhase|
		var cycleLen = ~simulation[\globalCycleLen] ? 16;
		var wrapped  = newPhase.mod(cycleLen);
		agent[\rhythm][\phase]      = wrapped.round.asInteger;
		agent[\rhythm][\phaseFloat] = wrapped;
		~regeneratePattern.(agent[\rhythm]);
	},

	// -------------------------------------------------------------------------
	// Step the simulation N times manually, useful for tests where we don't
	// want to start the routine.
	// -------------------------------------------------------------------------
	stepN: { |self, n = 1|
		n.do { ~simulation.step };
	},

	// -------------------------------------------------------------------------
	// TEST 1 — Mean-field convergence
	// -------------------------------------------------------------------------
	// Spread agents across the cycle, run for N ticks, expect circular
	// variance to monotonically decrease toward 0.
	// -------------------------------------------------------------------------
	convergence: { |self, ticks = 80|
		var agents   = ~simulation[\agents];

		if(agents.size < 2) {
			"convergence: need at least 2 agents".postln;
		} {
			var cycleLen = ~simulation[\globalCycleLen] ? 16;
			var spacing, sample, samples, started;

			"=== TEST 1: Mean-field convergence ===".postln;

			// Set up: spread agents around the cycle but off the symmetric points
			spacing = cycleLen / agents.size;
			agents.do { |a, i|
				self[\setAgentPhase].(self, a, (i * spacing) + (i * 0.7));   // asymmetric perturbation
				a[\weights][\phaseCoupling] = 0.05;
			};

			"Initial spread:".postln;
			self[\snapshot].(self);
			"Initial variance: %".format(self.circularVariance.(self).round(0.001)).postln;

			// Sample variance every 10 ticks
			samples = List.new;
			samples.add(self[\circularVariance].(self));
			(ticks / 10).asInteger.do {
				self[\stepN].(self, 10);
				samples.add(self[\circularVariance].(self));
			};

			"Variance trajectory (every 10 ticks):".postln;
			samples.do { |v, i|
				"  t=%: %".format(i * 10, v.round(0.001)).postln;
			};

			// Expectation: monotonic decrease, ending well below initial value.
			// If start variance > 0.5 and end variance < 0.2, we have convergence.
			if(samples.first > 0.5 and: { samples.last < 0.2 }) {
				"Result: PASS — phases converged toward synchrony".postln;
			} {
				if(samples.last >= samples.first) {
					"Result: FAIL — variance did not decrease (no coupling effect?)".postln;
				} {
					"Result: PARTIAL — some convergence but not strong synchrony".postln;
				}
			};

			"=======================================".postln;
			samples.asArray
		};
	},

	// -------------------------------------------------------------------------
	// TEST 2 — Anchor and followers
	// -------------------------------------------------------------------------
	// Agent 0 has coupling 0 (anchor); others have positive coupling.
	// Followers should converge to anchor's phase.
	// -------------------------------------------------------------------------
	anchor: { |self, ticks = 100|
		var agents   = ~simulation[\agents];

		if(agents.size < 2) {
			"convergence: need at least 2 agents".postln;
		} {
			var cycleLen = ~simulation[\globalCycleLen] ? 16;
			var anchorPhase, finalDeviation;

			"=== TEST 2: Anchor and followers ===".postln;

			// Agent 0 anchor at phase 0, no coupling
			self[\setAgentPhase].(self, agents[0], 0);
			agents[0][\weights][\phaseCoupling] = 0.0;
			anchorPhase = 0;

			// Other agents scattered with coupling 0.1, asymmetric placement
			agents[1..].do { |a, i|
				self[\setAgentPhase].(self, a,
					((i + 1) * 4 - (i * 0.6)).mod(cycleLen));
				a[\weights][\phaseCoupling] = 0.1;
			};

			"Initial state:".postln;
			self[\snapshot].(self);

			self[\stepN].(self, ticks);

			"After % ticks:".format(ticks).postln;
			self[\snapshot].(self);

			// Compute mean deviation of followers from anchor
			finalDeviation = agents[1..].collect { |a|
				var d = ((a[\rhythm][\phaseFloat] ? a[\rhythm][\phase]) - anchorPhase);
				var wrapped = (d + (cycleLen / 2)).mod(cycleLen) - (cycleLen / 2);
				wrapped.abs
			}.mean;

			"Mean follower deviation from anchor: %".format(finalDeviation.round(0.01)).postln;

			// Anchor should not have moved
			if((agents[0][\rhythm][\phaseFloat] ? agents[0][\rhythm][\phase]) != anchorPhase) {
				"  WARN: anchor phase drifted to % (should be %)".format(
					agents[0][\rhythm][\phaseFloat], anchorPhase).postln;
			};

			if(finalDeviation < 1.0) {
				"Result: PASS — followers converged to anchor".postln;
			} {
				if(finalDeviation < 3.0) {
					"Result: PARTIAL — followers approaching anchor".postln;
				} {
					"Result: FAIL — followers not tracking anchor".postln;
				}
			};

			"=====================================".postln;
			finalDeviation
		};
	},

	// -------------------------------------------------------------------------
	// TEST 3 — Zero coupling preserves phase
	// -------------------------------------------------------------------------
	// With all coupling = 0, scattered phases should remain stable across many
	// ticks. Tests that the update doesn't introduce drift through floating
	// point or implementation errors.
	// -------------------------------------------------------------------------
	zeroCoupling: { |self, ticks = 50|
		var agents   = ~simulation[\agents];
		var cycleLen = ~simulation[\globalCycleLen] ? 16;
		var initialPhases, finalPhases, maxDrift;

		"=== TEST 3: Zero-coupling stability ===".postln;

		// Set scattered phases with coupling 0
		agents.do { |a, i|
			self[\setAgentPhase].(self, a, (i * 3).mod(cycleLen));
			a[\weights][\phaseCoupling] = 0.0;
		};

		initialPhases = agents.collect { |a|
			a[\rhythm][\phaseFloat] ? a[\rhythm][\phase]
		};

		"Initial phases: %".format(initialPhases.collect(_.round(0.001))).postln;

		self[\stepN].(self, ticks);

		finalPhases = agents.collect { |a|
			a[\rhythm][\phaseFloat] ? a[\rhythm][\phase]
		};

		"Final phases:   %".format(finalPhases.collect(_.round(0.001))).postln;

		maxDrift = (initialPhases.size).collect { |i|
			(finalPhases[i] - initialPhases[i]).abs
		}.maxItem ? 0;

		"Max drift: %".format(maxDrift.round(0.001)).postln;

		if(maxDrift < 0.01) {
			"Result: PASS — phases stable under zero coupling".postln;
		} {
			"Result: FAIL — phases drifted with coupling 0 (numerical issue)".postln;
		};

		"=======================================".postln;
		maxDrift
	},

	// -------------------------------------------------------------------------
	// TEST 4 — Wrap-around shortest path
	// -------------------------------------------------------------------------
	// Agent at phase 1, agent at phase 15 (in cycle of 16). Shortest path
	// is through 0, not through 8. They should converge to ~0/16, not to 8.
	// -------------------------------------------------------------------------
	wrapAround: { |self, ticks = 60|
		var agents   = ~simulation[\agents];

		if(agents.size < 2) {
			"convergence: need at least 2 agents".postln;
		} {
			var cycleLen = ~simulation[\globalCycleLen] ? 16;
			var midpoint, finalPhases, mean, distFromBoundary, distFromMid;

			"=== TEST 4: Wrap-around shortest path ===".postln;

			// Two agents on either side of the cycle boundary
			self[\setAgentPhase].(self, agents[0], 1);
			self[\setAgentPhase].(self, agents[1], cycleLen - 1);   // 15

			// Mid-point between 1 and 15 the long way is 8
			midpoint = cycleLen / 2;

			// Other agents at coupling 0 to remove their influence
			agents[2..].do { |a|
				a[\weights][\phaseCoupling] = 0.0;
			};
			agents[0][\weights][\phaseCoupling] = 0.1;
			agents[1][\weights][\phaseCoupling] = 0.1;

			"Initial: agent 0 at phase 1, agent 1 at phase 15".postln;

			self[\stepN].(self, ticks);

			finalPhases = [agents[0], agents[1]].collect { |a|
				a[\rhythm][\phaseFloat] ? a[\rhythm][\phase]
			};

			"Final phases: %".format(finalPhases.collect(_.round(0.001))).postln;

			// They should converge near 0 or 16 (same point), not near 8
			// Compute distance from boundary (mod cycleLen, take shortest)
			distFromBoundary = finalPhases.collect { |p|
				(p.mod(cycleLen)).min(cycleLen - p.mod(cycleLen))
			}.mean;

			distFromMid = finalPhases.collect { |p|
				(p - midpoint).abs
			}.mean;

			"Mean distance from boundary (0/cycle): %".format(distFromBoundary.round(0.01)).postln;
			"Mean distance from midpoint (long path): %".format(distFromMid.round(0.01)).postln;

			if(distFromBoundary < distFromMid) {
				"Result: PASS — agents took shortest path (across boundary)".postln;
			} {
				"Result: FAIL — agents took long path through midpoint".postln;
			};

			"==========================================".postln;
			[distFromBoundary, distFromMid]
		};
	},

	// -------------------------------------------------------------------------
	// TEST 5 — Float/integer phase consistency
	// -------------------------------------------------------------------------
	// At all times, agent[\rhythm][\phase] should equal
	// agent[\rhythm][\phaseFloat].round.asInteger.mod(cycleLen).
	// Run for some ticks and verify continuously.
	// -------------------------------------------------------------------------
	consistency: { |self, ticks = 40|
		var agents       = ~simulation[\agents];
		var cycleLen     = ~simulation[\globalCycleLen] ? 16;
		var inconsistent = 0;
		var totalChecks  = 0;

		"=== TEST 5: Float/integer phase consistency ===".postln;

		// Spread phases and enable coupling
		agents.do { |a, i|
			self[\setAgentPhase].(self, a, (i * 2));
			a[\weights][\phaseCoupling] = 0.08;
		};

		ticks.do {
			self[\stepN].(self, 1);
			agents.do { |a|
				var int   = a[\rhythm][\phase];
				var float = a[\rhythm][\phaseFloat] ? int;
				var expected = float.round.asInteger.mod(cycleLen);
				totalChecks = totalChecks + 1;
				if(int != expected) {
					inconsistent = inconsistent + 1;
					if(inconsistent <= 3) {
						"  step %: agent % phase=% phaseFloat=% expected=%".format(
							~simulation[\stepCount],
							a[\label], int, float.round(0.001), expected
						).postln
					}
				}
			}
		};

		"Inconsistencies: % / %".format(inconsistent, totalChecks).postln;

		if(inconsistent == 0) {
			"Result: PASS — int and float phases consistent".postln;
		} {
			"Result: FAIL — phase representations diverged".postln;
		};

		"================================================".postln;
		inconsistent
	},

	// -------------------------------------------------------------------------
	// Run all tests in sequence
	// -------------------------------------------------------------------------
	runAll: { |self, duration = 100|
		Routine({
			"".postln;
			"========== PHASE COUPLING TEST SUITE ==========".postln;
			"Note: simulation is stopped before tests run.".postln;
			"      Restart manually after with sim's start button.".postln;
			"".postln;

			if(~simulation[\timeSource].notNil
				and: { ~simulation[\timeSource][\running] == true })
			{
				~simulation[\stop].(~simulation);
				0.5.wait;
			};

			self[\zeroCoupling].(self, duration / 2);
			0.5.wait;
			self[\consistency].(self, duration / 2);
			0.5.wait;
			self[\convergence].(self, duration);
			0.5.wait;
			self[\anchor].(self, duration);
			0.5.wait;
			self[\wrapAround].(self, duration);
			0.5.wait;

			"".postln;
			"========== TEST SUITE COMPLETE ==========".postln;
		}).play;
		nil
	}
);

"~phaseCouplingTests loaded.".postln;
"  Run all:        ~phaseCouplingTests.runAll.(~phaseCouplingTests);".postln;
"  Snapshot:       ~phaseCouplingTests.snapshot.(~phaseCouplingTests);".postln;
"  Single test:    ~phaseCouplingTests.convergence.(~phaseCouplingTests);".postln;
)
