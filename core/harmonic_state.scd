// =============================================================================
// core/harmonic_state.scd — Harmonic listening and inference
//
// Extends ~simulationFactory with methods that compute the simulation's
// harmonic state: tonic centre, triad inference, function weighting,
// tension, transforms, and the structural clock.
//
// Loaded after simulation.scd. Uses the wrapper-merge pattern: the
// previous ~simulationFactory closure is captured, and the new factory
// invokes it then adds its methods to the returned simulation Event.
// =============================================================================

(
~simulationFactoryBase_harmonic = ~simulationFactory;

~simulationFactory = { |grid, driveModel|
	var sim = ~simulationFactoryBase_harmonic.(grid, driveModel);

	sim[\updateTonicCentre] = { |self|
		var agentPCs, weights, totalWeight, angles, meanAngle;

		// Locked tonic short-circuits everything
		if(self[\tonicLocked] == true) {
			self[\harmonicState][\tonicPC] = self[\lockedTonicPC];
			self[\harmonicCentre]          = self[\lockedTonicPC];
		} {
			if(self[\harmonicState].isNil) {
				self[\harmonicState] = (recentTransforms: [])
			};

			agentPCs = self[\agents].collect { |a|
				self.grid.pitchClassAt(a[\pos].x, a[\pos].y).asInteger };

			weights = self[\agents].collect { |a|
				var localTriangles = self.grid.trianglesAt(a[\pos]);
				var sharedCount = localTriangles.count { |tri|
					var triPCs = tri[\pcs].collect(_.asInteger);
					self[\agents].any { |other|
						other !== a and: {
							var otherPC = self.grid.pitchClassAt(
								other[\pos].x, other[\pos].y).asInteger;
							triPCs.includes(otherPC)
						}
					}
				};
				(sharedCount + 0.1)
			};

			totalWeight = weights.sum.max(0.0001);

			angles    = agentPCs.collect { |p| (p / 12) * 2pi };
			meanAngle = atan2(
				(angles.collect { |a, i| a.sin * weights[i] }).sum / totalWeight,
				(angles.collect { |a, i| a.cos * weights[i] }).sum / totalWeight
			);
			if(meanAngle < 0) { meanAngle = meanAngle + 2pi };

			// Just observe the centroid here. Tonic commitment happens
			// in the structural clock.
			self[\harmonicCentre] = (meanAngle / 2pi) * 12;
		};

		// Trail and motion bookkeeping (independent of tonic)
		self[\agentTrails]  = self[\agents].collect { |a|
			a[\recentPositions].collect(_.asPoint) };
		self[\agentMotions] = self[\agents].collect { |a|
			a[\recentMotion] ? [] };
	};

	sim[\updateTriadState] = { |self|

		var functionWeights, classifyFunction;
		var accumulate, candidates, impliedFunction, totalWeight, weightedDist;
		var accumulateTension, tensionLevel;

		// 2a. Tonal Reference (where is "home"?)

		var tonicPC  = self[\harmonicState][\tonicPC] ? 0;
		var tonicInt = self[\harmonicState][\tonicPC].round.asInteger.mod(12);

		// 2b. Perception (what notes and triads exist?)

		var agentPCs = self[\agents].collect { |a|
			self.grid.pitchClassAt(a[\pos].x, a[\pos].y).asInteger
		};

		var allTriads = self[\agents].collect { |a|
			self.grid.trianglesAt(a[\pos])
		};

		// 2c. Triad Detection (Occupied vs Implied)

		var occupiedTriads = [];
		var impliedTriads  = [];

		classifyFunction = { |triad|

			var root = triad[\pcs].collect(_.asInteger).sort[0];
			var interval = (root - tonicInt).mod(12);

			switch(interval,
				0, { \tonic },
				7, { \dominant },
				5, { \subdominant },
				9, { \predominant },
				2, { \supertonic },
				{ \ambiguous }
			)
		};

		allTriads.do { |triads|
			triads.do { |triad|

				var triadPCs = triad[\pcs].collect(_.asInteger);
				var coverage = triadPCs.count { |pc| agentPCs.includes(pc) };

				if(coverage == 3) {
					if(occupiedTriads.detect { |t| t[\pcs] == triadPCs }.isNil) {
						occupiedTriads = occupiedTriads.add(
							triad.copy.put(\function, classifyFunction.(triad))
						)
					};
				} {
					if(coverage >= 1) {
						if(impliedTriads.detect { |t| t[\pcs] == triadPCs }.isNil) {
							impliedTriads = impliedTriads.add(
								triad.copy
								.put(\coverage, coverage)
								.put(\function, classifyFunction.(triad))
							)
						};
					};
				};
			};
		};

		// 2d. Function Inference (what does the harmony "feel like", roundabout-ly)

		functionWeights = Dictionary.new;

		[\tonic, \dominant, \subdominant,
			\predominant, \supertonic, \ambiguous]
		.do { |fn| functionWeights[fn] = 0.0 };

		accumulate = { |triad, weight|
			var fn = classifyFunction.(triad);
			functionWeights[fn] = functionWeights[fn] + weight;
		};

		// strong evidence: fully occupied
		occupiedTriads.do { |t|
			accumulate.(t, 3.0)
		};

		// weaker evidence: implied
		impliedTriads.do { |t|
			var w = if((t[\coverage] ? 1) == 2) { 1.0 } { 0.2 };
			accumulate.(t, w)
		};

		candidates = functionWeights.keys.asArray.reject(_ == \ambiguous);

		impliedFunction =
		candidates.maxItem { |fn| functionWeights[fn] };

		if(functionWeights[impliedFunction] == 0.0) {
			impliedFunction = \ambiguous
		};

		// 2e. Tension Estimation (how far from "home"?)

		totalWeight  = 0.0;
		weightedDist = 0.0;

		accumulateTension = { |triad, weight|

			var root = triad[\pcs].collect(_.asInteger).sort[0];
			var d    = (root - tonicInt).abs.mod(12);
			var norm = d.min(12 - d) / 6.0;

			weightedDist = weightedDist + (norm * weight);
			totalWeight  = totalWeight  + weight;
		};

		occupiedTriads.do { |t|
			accumulateTension.(t, 3.0)
		};

		impliedTriads.do { |t|
			var w = if((t[\coverage] ? 1) == 2) { 1.0 } { 0.2 };
			accumulateTension.(t, w)
		};

		tensionLevel =
		if(totalWeight > 0) { weightedDist / totalWeight } { 0.0 };

		// 2f. State Update (write back to system)

		self[\harmonicState][\occupiedTriads]  = occupiedTriads;
		self[\harmonicState][\impliedTriads]   = impliedTriads;
		self[\harmonicState][\impliedFunction] = impliedFunction;
		self[\harmonicState][\functionWeights] = functionWeights;
		self[\harmonicState][\tensionLevel]    = tensionLevel;

		// 2g. Global Effect (tension modulates behaviour)
		self[\effectiveHarmonicBlend] =
		self[\harmonicBlend]
		+ (tensionLevel * (1.0 - self[\harmonicBlend]));
	};
	// TODO: Migrate and devise changes

	// functionContest is in [0, 1] where 0 = unambiguous winner, 1 = perfect tie.
	// Computed from the same function-weight distribution that picks
	// impliedFunction; this is what "between functions" actually means.
	sim[\updateFunctionContest] = { |self|
		var weights = self[\harmonicState][\functionWeights] ? ();
		var values  = weights.values.select { |v| v > 0 };
		var sorted, top, second, contest;

		contest = if(values.size < 2) {
			0  // single function or none — no contest
		} {
			sorted = values.sort.reverse;
			top    = sorted[0];
			second = sorted[1];
			if(top > 0) { second / top } { 0 }
		};

		self[\harmonicState][\functionContest] = contest;
	};

	sim[\updateAgentBias] = { |self|
		var interactionRadius   = self[\interactionRadius] ? 4;
		// Defaults sourced from the drive registry. Should never fire in
		// normal operation since every agent receives these weights at
		// spawn, but kept defensive in case agent weight tables are
		// mutated externally.
		var defaultEntrainment  = ~driveDefault.(\entrainmentStrength, 0.4);
		var defaultHomeStrength = ~driveDefault.(\homeStrength,        0.6);

		self[\agents].do { |agent|
			var entrainmentStrength = agent[\weights][\entrainmentStrength] ? defaultEntrainment;
			var homeStrength        = agent[\weights][\homeStrength]        ? defaultHomeStrength;
			var bias = Array.fill(12, { 1.0 });
			var bMax, bMin, bRange;

			agent[\homeTriad].do { |pc|
				bias[pc] = bias[pc] + homeStrength
			};

			self[\agents].do { |other|
				if(other !== agent) {
					var dist = self.grid.hexDistance(agent[\pos], other[\pos]);
					if(dist <= interactionRadius) {
						var strength = (1 - (dist / interactionRadius))
						* entrainmentStrength;
						var otherPC  = self.grid.pitchClassAt(
							other[\pos].x, other[\pos].y).asInteger;
						[0, 3, 4, 7].do { |interval|
							var targetPC = (otherPC + interval).mod(12);
							bias[targetPC] = bias[targetPC] + strength;
						}
					}
				}
			};

			bMax   = bias.maxItem;
			bMin   = bias.minItem;
			bRange = (bMax - bMin).max(0.0001);
			agent[\harmonicBias] = bias.collect { |b|
				0.5 + ((b - bMin) / bRange) };
		};
	};

	sim[\updateAgentTension] = { |self|
		var tonicPC       = self[\harmonicState][\tonicPC] ? 0;
		var collectiveTonic = tonicPC.round.asInteger;

		self[\agents].do { |agent|

			// Agent pitch class
			var agentPC = self.grid.pitchClassAt(
				agent[\pos].x, agent[\pos].y
			).asInteger;
			var otherPCs = self[\agents]
			.reject(_ === agent)
			.collect { |a|
				self.grid.pitchClassAt(a[\pos].x, a[\pos].y).asInteger
			};

			var fd = (agentPC - collectiveTonic).abs.mod(12);
			var functionalDist  = fd.min(12 - fd) / 6.0;

			var collectiveDist = if(otherPCs.notEmpty) {
				otherPCs.collect { |opc|
					var d = (agentPC - opc).abs.mod(12); d.min(12 - d)
			}.mean / 6.0 } { 0.0 };

			var modeDisplacement = if(
				agent[\modeCollection].notNil and: { agent[\modeCollection].notEmpty }
			) {
				if(agent[\modeCollection].includes(agentPC)) { 0.0 } {
					var dist = agent[\modeCollection].collect { |mc|
						var d = (agentPC - mc).abs.mod(12); d.min(12 - d)
					}.minItem ? 6;
					(dist / 6.0).clip(0, 1) }
			} { 0.0 };

			var modeKey, intervals;

			// resonanceScore: how well the agent's current PC fits the collective harmonic state.
			// High resonance = agent is expressing something meaningful = worth sounding.
			// Complement of tension in some respects, but not simply 1 - tension:
			// an agent can be both tense (displaced from tonic) and resonant
			// (strongly implying a coherent triad with neighbours).

			var triadCoverage = self[\agents].reject(_ === agent).select { |other|

				var tri = self.grid.trianglesAt(agent[\pos]);
				tri.any { |t|
					var otherPC = self.grid.pitchClassAt(
						other[\pos].x, other[\pos].y).asInteger;
					t[\pcs].collect(_.asInteger).includes(otherPC)
				}
			}.size;

			var maxNeighbours = self[\agents].size - 1;
			var coverageScore = if(maxNeighbours > 0) {
				triadCoverage / maxNeighbours
			} {
				1.0   // N=1: the agent is its own context
			};

			// Harmonic bias at current position: how strongly the field pulls here
			var harmonicBiasArray = agent[\harmonicBias];
			var currentPC = self.grid.pitchClassAt(agent[\pos].x, agent[\pos].y).asInteger;
			var rawBias = if(harmonicBiasArray.notNil) {
				harmonicBiasArray[currentPC] ? 1.0
			} { 1.0 };
			var biasScore = rawBias.linlin(0.5, 1.5, 0.0, 1.0);

			// Stasis pressure — normalised over a ~16 step window
			// An agent stationary for 8 steps contributes 0.5, for 16+ contributes 1.0
			var stasisTension = ((agent[\stepsSinceMove] ? 0) / 16.0).clip(0, 1);

			// Silence pressure — normalised over a ~8 step window
			var silenceTension = ((agent[\stepsSinceSound] ? 0) / 8.0).clip(0, 1);

			var nearbyPCs, bestMode, bestFit;
			var hysteresis, currentMode, currentColl, currentTransp, currentFit;
			var tonicInt;

			agent[\resonanceScore] = (coverageScore * 0.6) + (biasScore * 0.4);

			agent[\tensionScore] =
			(functionalDist  * 0.3)
			+ (collectiveDist  * 0.3)
			+ (modeDisplacement * 0.15)
			+ (stasisTension   * 0.15)
			+ (silenceTension  * 0.1);


			// Derive mode collection from local pitch-class neighbourhood
			nearbyPCs = ([agent] ++ self[\agents].select { |other|
				other !== agent and: {
					self.grid.hexDistance(agent[\pos], other[\pos]) <= (self[\interactionRadius] ? 4)
				}
			}).collect { |a|
				self.grid.pitchClassAt(a[\pos].x, a[\pos].y).asInteger
			}.asSet.asArray;

			// Score each mode collection against the neighbourhood
			tonicInt = self[\harmonicState][\tonicPC].round.asInteger.mod(12);

			if(self[\modeLocked] == true) {
				modeKey = self[\lockedModeKey];
			} {
				bestMode = \major;
				bestFit  = -inf;

				// Score all modes except chromatic: chromatic is last resort only
				self[\modeCollections].keysValuesDo { |key, collection|
					if(key != \chromatic) {
						var fit = ~modeF1.(nearbyPCs, collection, tonicInt);
						if(fit > bestFit) { bestFit = fit; bestMode = key }
					}
				};

				// Use chromatic only if no mode clears a minimum threshold
				if(bestFit < 0.1) { bestMode = \chromatic };

				hysteresis  = self[\modeHysteresis] ? 0.2;
				currentMode = agent[\modeKey] ? \major;
				currentFit  = ~modeF1.(nearbyPCs, self[\modeCollections][currentMode], tonicInt);

				modeKey = if(bestFit > (currentFit + hysteresis)) {
					bestMode
				} {
					currentMode
				};
			};

			intervals = ~modeHomeTriad[modeKey] ? [0, 4, 7];
			agent[\modeKey]        = modeKey;
			agent[\homeTriad]      = intervals.collect { |i| (collectiveTonic + i).mod(12) };
			agent[\modeCollection] = (self[\modeCollections][modeKey] ? self[\modeCollections][\major])
			.collect { |pc| (pc + collectiveTonic).mod(12) };

		};
	};

	sim[\decideTonicShift] = { |self|
		var hs           = self[\harmonicState];
		var current      = hs[\tonicPC] ? 0;
		var observed     = self[\harmonicCentre] ? current;
		var tension      = hs[\tensionLevel] ? 0.0;
		var modRate      = self[\tonicUpdateRate] ? 0.5;

		// Shortest signed angular distance on the pitch-class circle
		var d            = (observed - current).mod(12);
		var shortest     = if(d > 6) { d - 12 } { d };
		var displacement = shortest.abs;

		// Threshold: the centroid must be at least this far from the
		// current tonic to count as a meaningful displacement.
		var threshold    = self[\tonicShiftThreshold] ? 1.5;

		// Modulation gate: combine displacement and tension. A large
		// displacement alone can trigger a shift; under high tension,
		// smaller displacements suffice.
		var pressure     = displacement + (tension * 3.0);
		var willShift    = pressure >= threshold;

		var noteNames    = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];

		if(willShift and: { self[\tonicLocked] != true }) {
			// Commit a graded step toward the centroid. modRate scales
			// how decisive the shift is; bounded so modulation never
			// overshoots.
			var stepSize = (displacement * modRate).clip(0, displacement);
			var newTonic = (current + (shortest.sign * stepSize)).mod(12);

			hs[\tonicPC] = newTonic;

			if(self[\debugStructuralClock] ? false) {
				"=== Tonic shift | step:% | from:%(%) → to:%(%) | displacement:% | tension:% ===".format(
					self[\stepCount],
					current.round(0.01),
					noteNames[current.round.asInteger.mod(12)],
					newTonic.round(0.01),
					noteNames[newTonic.round.asInteger.mod(12)],
					displacement.round(0.01),
					tension.round(0.01)
				).postln;
			};
		};
	};

	sim[\updateStructuralClock] = { |self|
		var period    = self[\structuralClockPeriod] ? 8;
		var stepCount = self[\stepCount] ? 0;
		var noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];

		if(stepCount % period == 0) {

			self.decideTonicShift;

			{
				var hs       = self[\harmonicState];
				var tension  = hs[\tensionLevel]     ? 0.0;
				var history  = hs[\recentTransforms] ? [];
				var tonicInt = (hs[\tonicPC] ? 0).round.asInteger.mod(12);
				var boundary = self[\resolveBoundary] ? 0.5;
				var targetTriad = nil;

				if(tension >= boundary) {

					// High tension: target the home triad (force resolution)
					// Use the dominant mode across living agents to determine triad quality
					var modes      = self[\agents].collect { |a| a[\modeKey] ? \major };
					var modeCounts = Dictionary.new;
					var dominantMode, intervals;
					modes.do { |m| modeCounts[m] = (modeCounts[m] ? 0) + 1 };
					dominantMode = modes.maxItem { |m| modeCounts[m] };
					intervals    = ~modeHomeTriad[dominantMode] ? [0, 4, 7];
					targetTriad = intervals.collect { |i| (tonicInt + i).mod(12) };

				} {

					// Low tension: continue the dominant PLR trajectory
					var recentHistory = history.keep(-6);
					var dominantTransform = nil;
					var baseTriad = nil;
					var occupied, implied;

					// Find the most frequent transform in recent history
					if(recentHistory.notEmpty) {
						var counts = Dictionary.new;
						recentHistory.do { |e|
							var t = e[\transform];
							if(t.notNil) {
								counts[t] = (counts[t] ? 0) + 1
							}
						};
						if(counts.notEmpty) {
							dominantTransform = counts.keys.asArray
							.maxItem { |k| counts[k] }
						}
					};

					// Most recently occupied triad as starting point for projection
					occupied = hs[\occupiedTriads] ? [];
					implied  = hs[\impliedTriads]  ? [];

					if(occupied.notEmpty) {
						baseTriad = occupied.last[\pcs].collect(_.asInteger)
					} {
						if(implied.notEmpty) {
							baseTriad = implied.last[\pcs].collect(_.asInteger)
						}
					};

					// Project one step along the dominant transform
					if(baseTriad.notNil and: { dominantTransform.notNil }) {
						targetTriad = self.applyPLRTransform(baseTriad, dominantTransform)
					};
				};

				// Fallback: home triad in major if nothing resolved
				if(targetTriad.isNil) {
					targetTriad = [0, 4, 7].collect { |i| (tonicInt + i).mod(12) }
				};

				hs[\targetTriad] = targetTriad;

				if(self[\debugStructuralClock] ? false) {
					"=== Structural clock | step:% | tension:% | target:[%] ===".format(
						stepCount,
						tension.round(0.01),
						targetTriad.collect { |pc| noteNames[pc] }.join(", ")
					).postln
				};
			}.value;
		};
	};

	sim[\applyPLRTransform] = { |self, triadPCs, transform|
		// Detect major {r, r+4, r+7} or minor {r, r+3, r+7} by sorted interval structure
		var sorted  = triadPCs.sort;
		var i1      = (sorted[1] - sorted[0]).mod(12);
		var i2      = (sorted[2] - sorted[1]).mod(12);
		var isMajor = (i1 == 4) and: { i2 == 3 };
		var isMinor = (i1 == 3) and: { i2 == 4 };
		var r       = sorted[0];
		var result;

		if(isMajor.not and: { isMinor.not }) {

			// Not a standard triad — return unchanged
			result = triadPCs;
		} {
			result = if(transform == \P) {

				// Parallel: same root and fifth, move third by one semitone
				if(isMajor) { [r, (r+3).mod(12), (r+7).mod(12)] }
				{ [r, (r+4).mod(12), (r+7).mod(12)] }
			} {
				if(transform == \L) {

					// Leading-tone exchange:
					if(isMajor) { [(r-1).mod(12), (r+4).mod(12), (r+7).mod(12)] }
					{ [r,             (r+3).mod(12), (r+8).mod(12)] }
				} {
					if(transform == \R) {

						// Relative:
						if(isMajor) { [r,              (r+4).mod(12), (r+9).mod(12)] }
						{ [(r-2).mod(12),  (r+3).mod(12), (r+7).mod(12)] }
					} {
						triadPCs  // unknown transform..
					}
				}
			};
		};

		result.collect(_.mod(12)).sort
	};

	sim[\logTransforms] = { |self, activeAgents, previousPositions|
		var maxHistory = 16;
		var newEvents  = [];
		var existing, transform, fromTriad, toTriad;

		activeAgents.do { |agent, i|
			var oldPos       = previousPositions[i];
			var newPos       = agent[\pos];
			var oldTriangles, newTriangles;

			if((oldPos.x != newPos.x) or: { oldPos.y != newPos.y }) {
				var found = false;
				oldTriangles = self.grid.trianglesAt(oldPos);
				newTriangles = self.grid.trianglesAt(newPos);

				transform = nil;
				fromTriad = nil;
				toTriad   = nil;

				oldTriangles.do { |oldTri|
					if(found.not) {
						newTriangles.do { |newTri|
							if(found.not) {
								var t = self.grid.transformationBetween(oldTri, newTri);
								if(t.notNil) {
									transform = t;
									fromTriad = oldTri;
									toTriad   = newTri;
									found     = true;
								}
							}
						}
					}
				};

				if(transform.notNil) {
					newEvents = newEvents.add((
						agent:        agent[\label],
						transform:    transform,
						fromTriad:    fromTriad,
						toTriad:      toTriad,
						step:         self[\stepCount],
						gridDistance: self.grid.hexDistance(oldPos, newPos)
					))
				}
			};
		};

		existing = self[\harmonicState] !? _[\recentTransforms] ? [];
		self[\harmonicState][\recentTransforms] =
		(existing ++ newEvents).keep(maxHistory.neg);
	};

	sim
};
)