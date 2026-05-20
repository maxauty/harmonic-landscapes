// =============================================================================
// core/lifecycle.scd — Agent population dynamics
//
// Extends ~simulationFactory with birth, death, and phase coupling.
// =============================================================================

(
~simulationFactoryBase_lifecycle = ~simulationFactory;

~simulationFactory = { |grid, driveModel|
	var sim = ~simulationFactoryBase_lifecycle.(grid, driveModel);

	sim[\checkDeath] = { |self|
		if(self[\deathEnabled] == true) {
			var m       = self[\samePCDeathSteps] ? 8;
			var minA    = self[\minAgents] ? 1;
			var living  = self[\agents].reject { |a| a[\dead] == true };
			var blockedThreshold;

			if(living.size > minA) {
				blockedThreshold = self[\blockedDeathSteps] ? 10;

				living.do { |a|
					if(a[\dead] != true
						and: { (a[\stepsBlocked] ? 0) >= blockedThreshold }
						and: { (a[\resonanceScore] ? 0) < 0.3 }
						and: { living.reject(_[\dead] == true).size > minA }
					) {
						a[\dead] = true;
						"Agent % died: outcompeted after % blocked steps".format(
							a[\label], a[\stepsBlocked]).postln;
					}
				};

				// Condition 2: same pitch class for M consecutive steps
				living.do { |a|
					if(a[\dead] != true) {
						var aPC = self.grid.pitchClassAt(
							a[\pos].x, a[\pos].y).asInteger;
						var sharing = living.any { |b|
							b !== a
							and: { b[\dead] != true }
							and: {
								self.grid.pitchClassAt(
									b[\pos].x, b[\pos].y).asInteger == aPC
							}
						};
						a[\stepsSamePC] = if(sharing) {
							(a[\stepsSamePC] ? 0) + 1
						} { 0 };

						if(a[\stepsSamePC] >= m
							and: { living.reject(_[\dead] == true).size > minA }
						) {
							// again, lower resonanceScore loses
							var rivals = living.select { |b|
								b !== a
								and: { b[\dead] != true }
								and: {
									self.grid.pitchClassAt(
										b[\pos].x, b[\pos].y).asInteger == aPC
								}
							};
							var loser = ([a] ++ rivals).minItem { |x|
								x[\resonanceScore] ? 0 };
							loser[\dead] = true;
							"Agent % died: % steps on PC %".format(
								loser[\label], m, aPC).postln;
						}
					}
				}
			}
		};

		// Clean up
		self[\agents].do { |a|
			if(a[\dead] == true) {
				~midiHistory.removeAt(a[\id]);
			}
		};

		self[\agents] = self[\agents].reject { |a| a[\dead] == true };
	};

	sim[\checkBirth] = { |self|
			if(self[\birthEnabled] == true) {
				var maxA           = self[\maxAgents] ? 8;
				var contestThresh  = self[\birthContestThreshold] ? 0.75;
				var dwellSteps     = self[\birthDwellSteps] ? 3;
				var contestHistory = self[\harmonicState][\contestHistory] ? [];
				var currentContest = self[\harmonicState][\functionContest] ? 0;
				var toSpawn        = [];

				// Maintain a short rolling history of contest values, gated on the
				// structural metric rather than per-agent tension. Birth becomes
				// a property of the harmonic moment, not of any individual agent.
				contestHistory = (contestHistory ++ [currentContest]).keep(-1 * dwellSteps);
				self[\harmonicState][\contestHistory] = contestHistory;

				// Sustained contest: every entry in the window is above threshold.
				if(contestHistory.size >= dwellSteps
					and: { contestHistory.every { |c| c >= contestThresh } }
				) {
					// Now find the right agent to split. The agent best positioned
					// to "articulate the unresolved options" is the one whose local
					// triangles overlap with the *contesting* functions, not just
					// any implied triad.
					var topFunctions = self.topContestingFunctions(2);  // helper below

					self[\agents].do { |agent|
						if((self[\agents].size + toSpawn.size) < maxA) {
							var localPCs = self.grid.trianglesAt(agent[\pos]).collect { |t|
								t[\pcs].collect(_.asInteger).sort
							};

							var triadA = topFunctions[0][\triad];  // PCs of dominant-implied triad
							var triadB = topFunctions[1][\triad];  // PCs of second-implied triad

							if(localPCs.any { |pcs| pcs == triadA.sort }
								and: { localPCs.any { |pcs| pcs == triadB.sort }
							}) {
								toSpawn = toSpawn.add((
									parent: agent,
									triadA: triadA,
									triadB: triadB
								));

								"Birth triggered: agent % straddles % and %".format(
									agent[\label],
									topFunctions[0][\function],
									topFunctions[1][\function]
								).postln;
							}
						}
					};

					// Once any agent splits, clear the contest history so we don't
					// keep firing on the same sustained ambiguity.
					if(toSpawn.size > 0) {
						self[\harmonicState][\contestHistory] = [];
					}
				};

				// Second pass: perform splits
				toSpawn.do { |spec|
					var parent    = spec[\parent];
					var triadA    = spec[\triadA];
					var triadB    = spec[\triadB];
					var neighbors = self.grid.wrappedNeighbors(parent[\pos]);
					var occupied  = self[\agents].collect { |a| a[\pos] }.select(_.notNil);

					var freeNeighbors = neighbors.select { |n|
						occupied.any { |p| p.x == n.x and: { p.y == n.y } }.not
					};

					var neighA = freeNeighbors.select { |n|
						triadA.includes(self.grid.pitchClassAt(n.x, n.y).asInteger)
					};
					var neighB = freeNeighbors.select { |n|
						triadB.includes(self.grid.pitchClassAt(n.x, n.y).asInteger)
					};

					var posA = if(neighA.notEmpty) { neighA.choose } {
						if(freeNeighbors.notEmpty) { freeNeighbors.choose } { nil }
					};

					var posB = if(neighB.notEmpty) {
						var candidates = neighB.reject { |n|
							posA.notNil and: { n.x == posA.x and: { n.y == posA.y } }
						};
						if(candidates.notEmpty) { candidates.choose } {
							var remaining = freeNeighbors.reject { |n|
								posA.notNil and: { n.x == posA.x and: { n.y == posA.y } }
							};
							if(remaining.notEmpty) { remaining.choose } { nil }
						}
					} {
						var remaining = freeNeighbors.reject { |n|
							posA.notNil and: { n.x == posA.x and: { n.y == posA.y } }
						};
						if(remaining.notEmpty) { remaining.choose } { nil }
					};

					if(posA.notNil and: { posB.notNil }) {
						var mutationStrength = 0.1;  // jitter scale for inherited weights
						var inheritedWeights = parent[\weights].copy;

						// Apply small per-drive mutation so the two children diverge over time
						// rather than behaving identically. Mutation is symmetric around the
						// parent's value, so the *expected* child weights = parent weights.
						var mutate = { |weights|
							var out = weights.copy;
							out.keysValuesDo { |k, v|
								out[k] = (v + (mutationStrength.rand2)).clip(0.0, 1.0)
							};
							out
						};

						// --- Child A: inherits parent's identity ---
						// Reuses parent's ID, label, channel, midiHistory. Position and weights
						// are new but anchored in the parent. The agent's "career" continues
						// through child A in the GUI, rhythm strip, and any external state
						// keyed by ID.
						var childA = ~makeAgent.(
							posA,
							parent[\octave],
							parent[\color],
							mutate.(inheritedWeights),
							parent[\label],
							parent[\stepInterval],
							parent[\channel] ? ~agentChannels.wrapAt(parent[\id]),
							self.grid,
							parent[\modeKey],
							parent[\tonicPC] ? self[\harmonicState][\tonicPC].round.asInteger,
							parent[\activation] ? 0.5,
							parent[\id],
							parent[\soundThreshold] ? 0.3
						);

						// Inherit derived state that makeAgent would otherwise reset
						childA[\recentMotion] = (parent[\recentMotion] ? []).copy;
						childA[\recentPos]    = (parent[\recentPos] ? []).copy;
						childA[\harmonicBias] = (parent[\harmonicBias] ? Array.fill(12, { 1.0 })).copy;

						self[\agents] = self[\agents].add(childA);
						// midiHistory is keyed by id, so already preserved — no reset needed

						"Agent % continued through split (lineage preserved)".format(parent[\label]).postln;

						// Child B: new sibling
						// Fresh ID and label, inherits parent's modeKey, stepInterval, octave,
						// and *mutated* weights. The colour shifts perceptibly so listeners can
						// distinguish parent-line from sibling.
						{
							var siblingID    = ~nextFreeAgentID.();
							var siblingColor = parent[\color].vary(0.3);
							var childB = ~makeAgent.(
								posB,
								parent[\octave],
								siblingColor,
								mutate.(inheritedWeights),
								siblingID.asSymbol,
								parent[\stepInterval],
								~agentChannels.wrapAt(siblingID),
								self.grid,
								parent[\modeKey],
								parent[\tonicPC] ? self[\harmonicState][\tonicPC].round.asInteger,
								parent[\activation] ? 0.5,
								siblingID,
								parent[\soundThreshold] ? 0.3
							);
							childB[\recentMotion] = [];  // sibling starts fresh on motion
							childB[\recentPos]    = [];
							childB[\harmonicBias] = (parent[\harmonicBias] ? Array.fill(12, { 1.0 })).copy;

							self[\agents] = self[\agents].add(childB);
							~midiHistory[siblingID] = [];

							"Agent % born from split of % at %".format(
								siblingID, parent[\label], posB).postln;
						}.value;

						// Remove parent: moved to child A
						self[\agents] = self[\agents].reject { |a| a === parent };

					} {
						"Agent %: split aborted, no free positions".format(
							parent[\label]).postln;
					}
				};
			}
		};

	// Helper on simulation: return the top N functions by weight, each with
	// its associated implied triad. Reads from harmonicState directly.
	sim[\topContestingFunctions]  = { |self, n=2|
		var weights  = self[\harmonicState][\functionWeights] ? ();
		var triads   = self[\harmonicState][\impliedTriads] ? [];
		var occupied = self[\harmonicState][\occupiedTriads] ? [];
		var pairs    = [];
		var sorted;

		weights.keysValuesDo { |fn, w|
			if(fn != \ambiguous) {
				pairs = pairs.add([fn, w])
			}
		};

		sorted = pairs.sort { |a, b| a[1] > b[1] };

		sorted[0..(n-1)].collect { |pair|
			var fn = pair[0];
			// Search occupied first (stronger evidence), then implied
			var triad = occupied.detect { |t| t[\function] == fn }
			?? { triads.detect { |t| t[\function] == fn } };
			(function: fn, weight: pair[1], triad: if(triad.notNil) { triad[\pcs] } { [] })
		}
	};

	// Phase coupling — Kuramoto-style mean-field. Agents adjust their
	// rhythmic phase toward the mean of their neighbours' phases.
	// Step size per tick is per-agent (phaseCoupling weight).
	sim[\updatePhaseCoupling] = { |self|
		var agents   = self[\agents];
		var cycleLen = self[\globalCycleLen] ? 16;
		var twoPi    = 2pi;

		if(agents.size >= 2) {
			agents.do { |agent|
				var ownPhase = agent[\rhythm][\phaseFloat]
				?? { agent[\rhythm][\phase] ? 0 };
				var coupling = agent[\weights][\phaseCoupling] ? 0.05;
				var contributions, meanForce, newPhaseFloat, newPhaseInt;

				if(coupling > 0) {
					contributions = agents.select { |a| a !== agent }.collect { |other|
						var otherPhase = other[\rhythm][\phaseFloat]
						?? { other[\rhythm][\phase] ? 0 };
						var deltaCycle = (otherPhase - ownPhase);
						var deltaWrapped = (deltaCycle + (cycleLen / 2))
						.mod(cycleLen) - (cycleLen / 2);
						var deltaRadians = (deltaWrapped / cycleLen) * twoPi;
						deltaRadians.sin
					};

					meanForce = if(contributions.size > 0) {
						contributions.sum / contributions.size
					} { 0 };

					newPhaseFloat = ownPhase + (coupling * meanForce * cycleLen / twoPi);
					newPhaseInt   = newPhaseFloat.round.asInteger.mod(cycleLen);

					if(newPhaseInt != (agent[\rhythm][\phase] ? 0)) {
						agent[\rhythm][\phase] = newPhaseInt;
						~regeneratePattern.(agent[\rhythm]);
					};

					agent[\rhythm][\phaseFloat] = newPhaseFloat.mod(cycleLen);
				};
			};
		};
	};

    sim
};
)