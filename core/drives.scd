// =============================================================================
// core/drives.scd — Drive model
//
// Defines ~driveModelFactory, which constructs the drive-evaluation and
// candidate-selection machinery that powers Stage 1 (pitch-class deliberation)
// of the agent decision pipeline.
//
// The factory returns an Event with three categories of member:
//
//   evaluation      — evalCell, layerSoftmax, plrContinuityScore,
//                     selectByMixture: turn raw drive scores into a
//                     candidate distribution and sample from it.
//
//   filtering       — filterKinematics: hard filter on candidates that
//                     violate kinematic constraints (recently visited,
//                     blocked).
//
//   orchestration   — chooseNext: the entry point called by each agent's
//                     decide method. Generates candidates, runs the drives,
//                     filters, mixes, samples a winner.
//
// Layers are not just labels: selectByMixture combines per-layer softmax
// distributions through state-dependent gates (gMotion, gHarmonic, gGesture,
// gDeliberative), with deliberative weight rising under tension.
// =============================================================================

(
~driveModelFactory = { |simulation, grid|

	(
		simulation:    simulation,
		grid:          grid,

		// =====================================================================
		// DRIVES
		// =====================================================================

		// see: core/drive_registry.scd

		drives: ~driveRegistry,


		// =====================================================================
		// EVALUATION & SELECTION
		// =====================================================================

		// Run every drive over a single candidate cell. Returns an Event keyed
		// by drive name plus the cell's pitch class.
		evalCell: { |self, cell, ctx|
			var ev = (
				cell: cell,
				pc:   self.grid.pitchClassAt(cell.x, cell.y).asInteger
			);
			self.drives.do { |drive|
				ev[drive[\name]] = drive[\fn].(self, cell, ctx);
			};
			ev
		},

		// Compute a softmax probability distribution over candidates, restricted
		// to drives belonging to the named layer. Drive contributions are
		// weighted, normalised to [0,1], divided by temperature, then floored
		// to ensure a minimum probability per candidate.
		layerSoftmax: { |self, scored, layerName, weights, temperature|

			var combined, minVal, maxVal, range, normalised, logits, maxLogit, expScores, sumExp, probabilities, floored, total;
			var floor = 0.01;  // minimum probability per candidate
			// Which drives are relevant to this layer?
			var drives = self.drives.select { |d|
				d[\layer] == layerName
			};

			if(drives.isEmpty) {
				^Array.fill(scored.size, { 1.0 / scored.size });
			};

			// Combine drive contributions into a single score per cell
			combined = scored.collect { |event|
				drives.sum { |d|
					var score  = event[d[\name]] ? 0;
					var weight = weights[d[\name]] ? 1.0;
					score * weight
				}
			};

			// Normalise into a stable 0–1 range
			minVal = combined.minItem;
			maxVal = combined.maxItem;
			range  = (maxVal - minVal).max(0.0001);

			normalised = combined.collect { |v|
				(v - minVal) / range
			};

			// Softmax (temperature-controlled)
			logits = normalised.collect { |v| v / temperature };
			maxLogit = logits.maxItem;  // numerical stability trick

			expScores = logits.collect { |l|
				(l - maxLogit).exp
			};

			sumExp = expScores.sum;

			probabilities = expScores.collect { |e|
				e / sumExp
			};

			// Enforce a minimum probability and renormalise
			floored = probabilities.collect { |p|
				p.max(floor)
			};

			total = floored.sum;

			floored.collect { |p|
				p / total
			}
		},

		// Helper for the plrContinuity drive: scores a candidate transform
		// against an agent's recent transform history.
		//   - anti-reversal: penalise repeating the same transform
		//   - pattern continuation: reward cycling X → Y → X
		//   - connectivity bonus: small reward for any valid transform
		plrContinuityScore: { |self, candidateTransform, agentTransforms|

			var score = 0.0;
			var lastTransform, penultimateTransform;

			if(candidateTransform.isNil) {
				score = 0.0;
			} {
				if(agentTransforms.isEmpty) {
					score = 0.1;
				} {
					lastTransform = agentTransforms.last[\transform];

					// Anti-reversal
					if(candidateTransform == lastTransform) {
						score = score - 0.6;
					};

					// Pattern continuation
					if(agentTransforms.size >= 2) {
						penultimateTransform = agentTransforms[
							agentTransforms.size - 2][\transform];
						if((candidateTransform == penultimateTransform)
							and: { candidateTransform != lastTransform }) {
							score = score + 0.4;
						};
					};

					// Connectivity bonus
					score = score + 0.1;
				}
			};

			score
		},

		// Combine per-layer softmax distributions through state-dependent
		// gates, apply collection-strictness attenuation, and sample a winner.
		// This is where the layer hierarchy described at the top of the file
		// actually takes effect: gates determine how much each layer's
		// distribution contributes to the final mixture.
		selectByMixture: { |self, feasible, weights, tensionScore, ctx|

			// ----------------------------------------------------------------
			// 0. PARAMETERS
			// ----------------------------------------------------------------
			var temperatures = (
				motion:       self.simulation[\tempMotion]       ? 1.0,
				harmonic:     self.simulation[\tempHarmonic]     ? 1.0,
				gesture:      self.simulation[\tempGesture]      ? 1.0,
				deliberative: self.simulation[\tempDeliberative] ? 1.5   // softer, more exploratory
			);

			// effectiveHarmonicBlend is computed in updateTriadState each tick:
			//   harmonicBlend + (tensionLevel * (1 - harmonicBlend))
			// It rises from harmonicBlend toward 1.0 as global tension rises.
			// Falls back to raw harmonicBlend if not yet computed (first tick),
			// then to the factory default if harmonicBlend is also absent.
			var baseBlend        = self.simulation[\effectiveHarmonicBlend]
			? (self.simulation[\harmonicBlend] ? 0.6);
			var resolveBoundary  = self.simulation[\resolveBoundary]  ? 0.5;
			var gestureThresh    = self.simulation[\gestureThreshold] ? 0.5;
			var deliberativeBase = self.simulation[\deliberativeBlend] ? 0.15;

			// ----------------------------------------------------------------
			// 1. PER-LAYER DISTRIBUTIONS
			// ----------------------------------------------------------------
			var pMotion       = self.layerSoftmax(feasible, \motion,       weights, temperatures[\motion]);
			var pHarmonic     = self.layerSoftmax(feasible, \harmonic,     weights, temperatures[\harmonic]);
			var pGesture      = self.layerSoftmax(feasible, \gesture,      weights, temperatures[\gesture]);
			var pDeliberative = self.layerSoftmax(feasible, \deliberative, weights, temperatures[\deliberative]);

			// ----------------------------------------------------------------
			// 2. STATE-DEPENDENT GATES
			// ----------------------------------------------------------------

			var gMotion, combined, r, cumulative, winner, gateSum;

			// Harmonic: tension-modulated baseline. Uses effectiveHarmonicBlend,
			// which interpolates from harmonicBlend toward 1.0 as global tension
			// rises. The agent is always a listener, but listens harder when
			// the ensemble is displaced from home. Uses global tension
			// (harmonicState tensionLevel) rather than per-agent tensionScore —
			// harmonic listening is an ensemble concern.
			var gHarmonic = baseBlend;

			// Gesture: rises only when imitation is strongly activated.
			// Peak concentration of the gesture distribution indicates
			// that another agent's motion contour has become predictive.
			var gestureStrength = pGesture.maxItem;
			var gGesture = if(gestureStrength > gestureThresh) {
				(gestureStrength - gestureThresh) / (1.0 - gestureThresh)
			} { 0.0 };

			// Deliberative: rises with tension. Planning, PLR continuity,
			// tonic pull, and the structural clock's target triad all
			// engage more strongly when the agent is displaced from home.
			// At resolveBoundary and above, deliberative takes over — the
			// agent commits to directed resolution rather than local smoothness.
			var gDeliberative = deliberativeBase + (tensionScore * (1.0 - deliberativeBase));
			if(tensionScore >= resolveBoundary) {
				gDeliberative = gDeliberative.max(0.6);
			};

			// Motion: default/residual. Always present as the substrate of
			// kinematic behaviour.
			gMotion = 1.0;

			// Normalise
			gateSum = gMotion + gHarmonic + gGesture + gDeliberative;
			gMotion       = gMotion       / gateSum;
			gHarmonic     = gHarmonic     / gateSum;
			gGesture      = gGesture      / gateSum;
			gDeliberative = gDeliberative / gateSum;

			// ----------------------------------------------------------------
			// 3. MIXTURE
			// ----------------------------------------------------------------
			combined = feasible.collect { |e, i|
				(gMotion       * pMotion[i])
				+ (gHarmonic     * pHarmonic[i])
				+ (gGesture      * pGesture[i])
				+ (gDeliberative * pDeliberative[i])
			};

			// ----------------------------------------------------------------
			// 3b. COLLECTION STRICTNESS (post-mixture attenuation)
			// ----------------------------------------------------------------
			// Scales out-of-collection candidate probability by (1 - strictness).
			// strictness = 0 → no effect (pure weighted mixture).
			// strictness = 1 → effective hard filter (out-cells zeroed).
			// Between these, borrowed tones remain possible but proportionally rare.
			{
				var strictness = self.simulation[\modeStrictness] ? 0.7;
				var modeColl   = ctx[\modeCollection] ? [];
				var attenuated;
				var sumNew;

				// Lock expresses categorical commitment — clamp strictness to full enforcement.
				// The slider continues to control unlocked behaviour only.
				if(self.simulation[\modeLocked] == true) { strictness = 1.0 };

				if(strictness > 0 and: { modeColl.notEmpty }) {
					attenuated = feasible.collect { |e, i|
						var pc = self.grid.pitchClassAt(e[\cell].x, e[\cell].y).asInteger;
						if(modeColl.includes(pc)) {
							combined[i]
						} {
							combined[i] * (1 - strictness)
						}
					};
					sumNew = attenuated.sum.max(0.0001);
					combined = attenuated.collect { |p| p / sumNew };
				};
			}.value;

			// ----------------------------------------------------------------
			// 4. STORE & SAMPLE
			// ----------------------------------------------------------------

			feasible.do { |e, i|
				e[\pMotion]       = pMotion[i];
				e[\pHarmonic]     = pHarmonic[i];
				e[\pGesture]      = pGesture[i];
				e[\pDeliberative] = pDeliberative[i];
				e[\normTotal]     = combined[i];
				e[\total]         = combined[i];
			};

			// Stash gate values for debug — globally and per-agent label.
			self.simulation[\lastGates] = (
				motion:       gMotion,
				harmonic:     gHarmonic,
				gesture:      gGesture,
				deliberative: gDeliberative
			);
			if(ctx[\label].notNil) {
				if(self.simulation[\gatesByAgent].isNil) {
					self.simulation[\gatesByAgent] = Dictionary.new
				};
				self.simulation[\gatesByAgent][ctx[\label]] = self.simulation[\lastGates]
			};

			r          = 1.0.rand;
			cumulative = 0.0;
			winner     = feasible.last;

			feasible.do { |e, i|
				if(cumulative <= r and: { r < (cumulative + combined[i]) }) {
					winner = e
				};
				cumulative = cumulative + combined[i];
			};

			winner
		},


		// =====================================================================
		// KINEMATIC FILTER
		// =====================================================================
		// Hard filter applied after drive evaluation: removes candidates that
		// violate kinematic constraints. Currently filters on stationary
		// blocks and fatigue (recently visited cells with sufficiently
		// negative fatigue scores). Falls back to the full candidate set if
		// every candidate would be filtered out.

		filterKinematics: { |self, candidates, weights, currentPos|
			var fatigueThreshold = self.simulation[\fatigueThreshold] ? -0.15;
			var blockedCells     = self.simulation[\stationaryPositions] ? [];

			var feasible = candidates.select { |e|
				var cell = e[\cell];
				var isBlocked = blockedCells.any { |bp|
					bp.x == cell.x and: { bp.y == cell.y }
				};
				var fatigueScore = (e[\fatigue] ? 0) * (weights[\fatigue] ? 0);
				var fatigued     = fatigueScore < fatigueThreshold;

				isBlocked.not and: { fatigued.not }
			};

			if(feasible.isEmpty) { feasible = candidates };
			feasible
		},


		// =====================================================================
		// ORCHESTRATOR
		// =====================================================================
		// chooseNext is the entry point called by each agent's `decide` method.
		// Pipeline:
		//   0. Normalise input state (point coercion, nil defaults)
		//   1. Generate candidates within an effective radius (extended by
		//      tension if jumpOnResolve is enabled)
		//   2. Build the per-call evaluation context
		//   3. Run every drive over every candidate via evalCell
		//   4. Drop the stay-cell sentinel (used only for harmonic baseline)
		//   5. Apply hard kinematic filter
		//   6. Sample a winner via state-gated mixture of layer distributions

		chooseNext: { |self, pos, lastDir, otherPos, weights, label,
			recentPos, recentMotion, modeCollection, tensionScore,
			homeTriad, harmonicBias, otherAgents, temporal|

			var evaluated, feasible, winner;
			var neighbors, ctx;

			var baseRadius, jumpResolve, tensionNow, boundary, effectiveRadius, allCandidates;

			// 0. NORMALISE INPUT STATE
			pos            = pos.asPoint;
			lastDir        = lastDir.tryPerform(\asPoint);
			otherPos       = otherPos.collect(_.asPoint);
			recentPos      = recentPos      ? [];
			recentMotion   = recentMotion   ? [];
			modeCollection = modeCollection ? [];

			// 1. CANDIDATE GENERATION
			// Base radius from simulation; tension can extend it to 3 for resolution jumps
			baseRadius   = self.simulation[\jumpRadius]    ? 1;
			jumpResolve  = self.simulation[\jumpOnResolve] ? true;
			tensionNow   = tensionScore ? 0.0;
			boundary     = self.simulation[\resolveBoundary] ? 0.5;

			// drives.scd — chooseNext, candidate generation block

			effectiveRadius = if(jumpResolve and: { baseRadius > 1 } and: { tensionNow >= boundary }) {
				baseRadius.max(3)
			} {
				baseRadius
			};

			// Collect candidates at each radius, tag with grid distance
			allCandidates = [];

			(1 .. effectiveRadius).do { |r|
				var ring = if(r == 1) {
					self.grid.wrappedNeighbors(pos) ? []
				} {
					self.grid.wrappedNeighborsAtRadius(pos, r) ? []
				};
				ring.do { |cell| allCandidates = allCandidates.add((cell: cell, gridDistance: r)) };
			};

			// Always include stay option at distance 0
			allCandidates = allCandidates.add((cell: pos, gridDistance: 0));

			// Context
			otherAgents = otherAgents ? [];
			ctx = (
				pos:            pos,
				lastDir:        lastDir,
				otherPos:       otherPos,
				otherAgents:    otherAgents,
				recentPos:      recentPos,
				recentMotion:   recentMotion,
				label:          label,
				modeCollection: modeCollection,
				homeTriad:      homeTriad,
				harmonicBias:   harmonicBias,
				gridDistance:   1,
				temporal:       temporal ? ()
			);

			// 3. Drive evaluation — gridDistance must be in ctx before evalCell
			//    runs, so stepCost and any other distance-aware drive see it.
			evaluated = allCandidates.collect { |entry|
				var ev;
				ctx[\gridDistance] = entry[\gridDistance];
				ev = self.evalCell(entry[\cell], ctx);
				ev[\gridDistance] = entry[\gridDistance];
				ev
			};

			// 4. Drop `stay` cell (stay was needed only for harmonic stay-cost comparison)
			evaluated = evaluated.copyFromStart(evaluated.size - 1);

			// 5. Hard filters (stationary-blocked, fatigued)
			feasible = self.filterKinematics(evaluated, weights, pos);

			// 6. Mixture selection
			winner = self.selectByMixture(feasible, weights, tensionScore, ctx);

			if(self.simulation[\debugMovement] ? false) {
				~postDebug.(label, feasible, winner, weights,
					feasible.collect(_[\total]), tensionScore, false)
			};

			winner
		},
	)
};
)
