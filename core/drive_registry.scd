// =================================================================================
// core/drive_registry.scd — Contains all drive functions and metadata.
//
// Each entry declares one drive: its scoring function, its layer (for
// softmax/gating), its GUI grouping, its default weight, its character-draw
// range, and its label/description.
//
// Adding a behavioural drive? Add one entry here. No edits to other files required.
// =================================================================================

// =====================================================================
// DRIVES
// =====================================================================
	// Each drive returns a scalar score for a candidate cell. Drives are
	// grouped below by their layer attribute, which controls how they are
	// combined in selectByMixture.

(

~driveRegistry = [

	// --- MOTION layer ----------------------------------------------------
	// Kinematic substrate. Always contributes.
	// These drives shape the geometry of agent travel without
	// reference to harmonic content.
    (
        name:          \momentum,
        layer:         \motion,
        guiGroup:      \motion,
        label:         "Momentum",
        defaultWeight: 0.2,
        charRange:     [0.1, 0.3],
        description:   "Continuation of recent direction",
        fn: { |self, cell, ctx|
            var currentPC   = self.grid.pitchClassAt(ctx[\pos].x, ctx[\pos].y).asInteger;
            var candidatePC = self.grid.pitchClassAt(cell.x, cell.y).asInteger;
            var step = candidatePC - currentPC;

            if(ctx[\recentMotion].notEmpty) {
                var lastMotion = ctx[\recentMotion].last;
                var lastStep   = lastMotion[\interval] ? 0;
                var lastDist   = lastMotion[\gridDistance] ? 1;

                if(lastStep == 0) {
                    0
                } {
                    var normalisedLast = lastStep / lastDist.max(1);
                    var direction      = normalisedLast.sign;
                    ((step * direction) / step.abs.max(1)).clip(-1, 1)
                }
            } { 0 }
        }
    ),

	(
		name:          \stigmergy,
		layer:         \motion,
		guiGroup:      \motion,
		label:         "Stigmergy",
		defaultWeight: 0.2,
		charRange:     [0.1, 0.3],
		description:   "Attraction to other agents' recent positions",
		fn: { |self, cell, ctx|
			var allTrails         = self.simulation[\agentTrails] ? [];
			var agents            = self.simulation[\agents] ? [];
			var radius            = self.simulation[\trailRadius] ? 1;
			var targetPoint       = cell.asPoint;
			var selfIndex         = agents.indexOf(self);
			var influence         = 0.0;
			var otherPositions    = agents.select { |a| a !== self }.collect(_[\pos]).select(_.notNil);
			var cellIsOccupied    = otherPositions.any { |p|
				p.x == targetPoint.x and: { p.y == targetPoint.y }
			};

			if(cellIsOccupied.not) {
				allTrails.do { |trail, agentIdx|
					// Skip self entirely — fatigue handles self-avoidance.
					if(agentIdx != selfIndex) {
						var length = trail.size;
						if(length > 0) {
							trail.do { |step, i|
								var freshness = (i + 1) / length;
								var distance  = self.grid.hexDistance(targetPoint, step.asPoint);
								var proximity = if(distance == 0) { 1.0 } {
									if(distance <= radius) { 1 - (distance / (radius + 1)) } { 0.0 }
								};
								if(proximity > 0) {
									influence = influence + (freshness * proximity);
								}
							}
						}
					}
				}
			};
			influence
		}
	),

	(
		name:          \sparsity,
		layer:         \motion,
		guiGroup:      \motion,
		label:         "Sparsity",
		defaultWeight: 0.1,
		charRange:     [0.05, 0.15],
		description:   "Pitch class crowding separation",
		fn: { |self, cell, ctx|

			var candidatePC = self.grid.pitchClassAt(cell.x, cell.y).asInteger;

			// Count how many others are already occupying this pitch class
			var density = ctx[\otherPos].count { |other|
				self.grid.pitchClassAt(other.x, other.y).asInteger == candidatePC
			};

			// Crowding pushes us away
			density.neg * 0.5
		}
	),

	(
		name:          \stepCost,
		layer:         \motion,
		guiGroup:      \motion,
		label:         "Jump Cost",
		defaultWeight: 0.3,
		charRange:     nil,
		description:   "Penalty for moving further than one step",
		fn: { |self, cell, ctx|
			var d = ctx[\gridDistance] ? 1;
			-1.0 * (d - 1).max(0)
		}
	),

	// --- CONSTRAINT layer ------------------------------------------------
	// Hard penalties acting as soft filters. The fatigue threshold in
	// filterKinematics turns sufficiently negative scores here into
	// outright candidate rejection.

	(
		name:          \fatigue,
		layer:         \constraint,
		guiGroup:      \motion,
		label:         "Fatigue",
		defaultWeight: 0.2,
		charRange:     [0.1, 0.3],
		description:   "Penalty for occupying a recently occupied cell",
		fn: { |self, cell, ctx|

			var repetitions = ctx[\recentPos].count { |pos|
				(pos.x == cell.x) and: { pos.y == cell.y }
			};

			repetitions.neg * 0.5 // More repetition == stronger push away
		}
	),

	// --- HARMONIC layer --------------------------------------------------
	// Vertical concerns: voice leading, Tonnetz consistency, agent-
	// specific bias. Contribute at a steady baseline regardless of
	// tension — the agent is always a listener.

	(
		name:          \voiceLeading,
		layer:         \harmonic,
		guiGroup:      \harmonic,
		label:         "Voice Leading",
		defaultWeight: 0.5,
		charRange:     [0.3, 0.7],
		description:   "Tendency towards smaller interval steps",
		fn: { |self, cell, ctx|
			var currentPC   = self.grid.pitchClassAt(ctx[\pos].x, ctx[\pos].y).asInteger;
			var candidatePC = self.grid.pitchClassAt(cell.x, cell.y).asInteger;
			var semitones   = (candidatePC - currentPC).abs.mod(12);
			semitones = semitones.min(12 - semitones);
			[1.0, 0.9, 0.7, 0.5, 0.3, 0.1, -0.2].wrapAt(semitones)
		}
	),

	(
		name:          \tonnetzContinuity,
		layer:         \harmonic,
		guiGroup:      \harmonic,
		label:         "Tonnetz Continuity",
		defaultWeight: 0.5,
		charRange:     [0.3, 0.7],
		description:   "Bias towards P-L-R coherence",
		fn: { |self, cell, ctx|
			var currentTriangles = self.grid.trianglesAt(ctx[\pos]);
			var candidateTriangles = self.grid.trianglesAt(cell);
			var shared = candidateTriangles.any { |ct|
				currentTriangles.any { |t|
					ct[\pcs].collect(_.asInteger).sort ==
					t[\pcs].collect(_.asInteger).sort
				}
			};
			if(shared) { 1.0 } { 0.0 }
		}
	),

	(
		name:          \harmonicBias,
		layer:         \harmonic,
		guiGroup:      \harmonic,
		label:         "Harmonic Bias",
		defaultWeight: 0.6,
		charRange:     nil,
		description:   "Reads the per-PC bias array built by updateAgentBias from homeStrength (home-triad weighting) and entrainmentStrength (neighbour implications)",
		fn: { |self, cell, ctx|
			var pc   = self.grid.pitchClassAt(cell.x, cell.y).asInteger;
			var bias = ctx[\harmonicBias] ? Array.fill(12, { 1.0 });
			bias[pc] ? 1.0
		}
	),

	(
		name:          \chordTone,
		layer:         \harmonic,
		guiGroup:      \harmonic,
		label:         "Chord Tone",
		defaultWeight: 0.6,
		charRange:     nil,
		description:   "Chord tone adherence",
		fn: { |self, cell, ctx|
			var pc       = self.grid.pitchClassAt(cell.x, cell.y).asInteger;
			var occupied = self.simulation[\harmonicState][\occupiedTriads] ? [];
			var implied  = self.simulation[\harmonicState][\impliedTriads]  ? [];
			var score    = 0.0;

			// full occupation: strong chord-tone reward
			occupied.do { |t|
				var pcs = t[\pcs].collect(_.asInteger);
				if(pcs.includes(pc)) { score = score.max(1.0) }
			};

			// implied triad (two-thirds covered): moderate reward
			implied.do { |t|
				var pcs = t[\pcs].collect(_.asInteger);
				if(pcs.includes(pc) and: { (t[\coverage] ? 1) == 2 }) {
					score = score.max(0.6)
				}
			};

			score
		}
	),

	// --- GESTURE layer ---------------------------------------------------
	// Conditional layer driven by the gesture gate. Only contributes
	// significantly when imitation is strongly activated — i.e. when
	// another agent's recent motion contour has become predictive.

	(
		name:          \imitation,
		layer:         \gesture,
		guiGroup:      \gesture,
		label:         "Imitation",
		defaultWeight: 0.2,
		charRange:     nil,
		description:   "Tendency to copy distinctive moves of other agents",
		fn: { |self, cell, ctx|

			// Use ctx[\otherAgents] — identity-filtered before decide was
			// called — rather than re-filtering self.simulation[\agents]
			// by position. The position filter breaks whenever two agents
			// share a cell (during spawning, or in theory if collision
			// resolution ever misses). Identity comparison is always correct.
			var others = ctx[\otherAgents] ? [];

			if(others.isEmpty) { 0 } {

				var motions    = others.collect { |a| a[\recentMotion] ? [] };
				var meaningful = motions.select { |m| m.size >= 2 };

				if(meaningful.isEmpty) { 0 } {
					var currentPC    = self.grid.pitchClassAt(ctx[\pos].x, ctx[\pos].y).asInteger;
					var candidatePC  = self.grid.pitchClassAt(cell.x, cell.y).asInteger;
					var proposedStep = candidatePC - currentPC;
					var proposedDirection = proposedStep.sign;
					var myContour = ~motionContour.(ctx[\recentMotion]);

					meaningful.collect { |otherMotion|
						var otherContour = ~motionContour.(otherMotion);
						var overlap = myContour.size.min(otherContour.size);
						var similarity = if(overlap == 0) { 0 } {
							myContour.collect { |step, i|
								if(step == otherContour[i]) { 1 } { 0 }
							}.sum / overlap
						};

						if(similarity > 0.5 and: { otherContour.size > myContour.size }) {
							var expectedNext = otherContour[myContour.size];
							if(proposedDirection == expectedNext) { similarity } { 0 }
						} {
							var lastDirection = otherContour.last ? 0;
							if(proposedDirection == lastDirection) { 0.3 } { 0 }
						}
					}.mean
				}
			}
		}
	),

	// --- DELIBERATIVE layer ----------------------------------------------
	// High-level planning. Includes neo-Riemannian transform continuity,
	// target-triad pull, modal coherence, tonic gravitation, and
	// inter-agent harmonic call-and-response. Gated by tension —
	// engages most strongly when the agent is displaced from home.

	(
		name:          \plrContinuity,
		layer:         \deliberative,
		guiGroup:      \deliberative,
		label:         "PLR Continuity",
		defaultWeight: 0.3,
		charRange:     nil,
		description:   "Reward candidate moves that extend the agent's recent neo-Riemannian transform pattern",
		fn: { |self, cell, ctx|
			var grid               = self.grid;
			var agentLabel         = ctx[\label];
			var currentTriangles   = grid.trianglesAt(ctx[\pos]);
			var candidateTriangles = grid.trianglesAt(cell);
			var agentTransforms;
			var candidateTransform = nil;
			var result;

			if(agentLabel.isNil) {
				result = 0.0
			} {
				agentTransforms = (self.simulation[\harmonicState][\recentTransforms] ? [])
				.select { |e| e[\agent] == agentLabel };

				currentTriangles.do { |ct|
					if(candidateTransform.isNil) {
						candidateTriangles.do { |tt|
							if(candidateTransform.isNil) {
								var t = grid.transformationBetween(ct, tt);
								if(t.notNil) { candidateTransform = t }
							}
						}
					}
				};

				result = self.plrContinuityScore(candidateTransform, agentTransforms)
			};

			result
		}
	),

	(
		name:          \targetTriad,
		layer:         \deliberative,
		guiGroup:      \deliberative,
		label:         "Target Triad",
		defaultWeight: 0.5,
		charRange:     nil,
		description:   "Pull toward the simulation's current target triad, set by structural-time goals",
		fn: { |self, cell, ctx|
			var pc          = self.grid.pitchClassAt(cell.x, cell.y).asInteger;
			var targetTriad = self.simulation[\harmonicState][\targetTriad] ? [];
			if(targetTriad.includes(pc)) { 1.0 } { 0.0 }
		}
	),

	(
		name:          \modeCoherence,
		layer:         \deliberative,
		guiGroup:      \deliberative,
		label:         "Mode Coherence",
		defaultWeight: 0.5,
		charRange:     nil,
		description:   "The inverse of modeDissonance, expressed as a positive deliberative pull",
		fn: { |self, cell, ctx|
			// inverse of modeDissonance, expressed as a positive deliberative pull
			var pc     = self.grid.pitchClassAt(cell.x, cell.y).asInteger;
			var modeColl = ctx[\modeCollection] ? [];
			if(modeColl.isEmpty) { 0.0 } {
				if(modeColl.includes(pc)) { 1.0 } {
					var dist = modeColl.collect { |mc|
						var d = (pc - mc).abs.mod(12);
						d.min(12 - d)
					}.minItem;
					1.0 - (dist / 6.0).clip(0, 1)
				}
			}
		}
	),

	(
		name:          \tonicPull,
		layer:         \deliberative,
		guiGroup:      \deliberative,
		label:         "Tonic Pull",
		defaultWeight: 0.2,
		charRange:     nil,
		description:   "Gravitational pull toward the tonic PC (a single anchor). Distinct from homeStrength/harmonicBias, which biases all three home-triad PCs as a categorical preference; this drive is a continuous distance-to-tonic field, and sharpens when the tonic is locked.",
		fn: { |self, cell, ctx|
			var pc      = self.grid.pitchClassAt(cell.x, cell.y).asInteger;
			var tonicPC = (self.simulation[\harmonicState][\tonicPC] ? 0).round.asInteger.mod(12);
			var dist    = (pc - tonicPC).abs.mod(12);
			var minDist = dist.min(12 - dist);
			var base    = 1.0 - (minDist / 6.0);
			var locked  = self.simulation[\tonicLocked] ? false;

			// locking expresses a categorical commitment to a tonal centre —
			// sharpen the gravitational profile accordingly
			if(locked) { base.squared } { base }
		}
	),

	(
		name:          \harmonicResponse,
		layer:         \deliberative,
		guiGroup:      \deliberative,
		label:         "Call and Response",
		defaultWeight: 0.4,
		charRange:     nil,
		description:   "Call-and-response: extend or echo recent harmonic moves made by other agents",
		fn: { |self, cell, ctx|
			var grid               = self.grid;
			var agentLabel         = ctx[\label];
			var currentTriangles   = grid.trianglesAt(ctx[\pos]);
			var candidateTriangles = grid.trianglesAt(cell);
			var allTransforms      = self.simulation[\harmonicState][\recentTransforms] ? [];
			var stepCount          = self.simulation[\stepCount] ? 0;
			var responseWindow     = self.simulation[\responseWindow] ? 4;
			var candidateTransform = nil;
			var recentByOthers, leaderTransform, oldest;
			var score = 0.0;
			var result = 0.0;

			if(agentLabel.isNil) {
				result = 0.0
			} {
				// What transform would this candidate move represent?
				currentTriangles.do { |ct|
					if(candidateTransform.isNil) {
						candidateTriangles.do { |tt|
							if(candidateTransform.isNil) {
								var t = grid.transformationBetween(ct, tt);
								if(t.notNil) { candidateTransform = t }
							}
						}
					}
				};

				if(candidateTransform.isNil) {
					result = 0.0
				} {
					// Recent transforms by *other* agents within the response window
					recentByOthers = allTransforms.select { |e|
						(e[\agent] != agentLabel)
						and: { (stepCount - (e[\step] ? 0)) <= responseWindow }
					};

					if(recentByOthers.isEmpty) {
						result = 0.0
					} {
						// Option 1: match the most recent leader's transform
						leaderTransform = recentByOthers.last[\transform];
						if(candidateTransform == leaderTransform) {
							score = score.max(0.8);
						};

						// Option 2: complete a pair pattern across two recent leader moves
						// e.g. if recent transforms are [L, R] across two agents, the third
						// agent extending with another L gets rewarded for cycling
						if(recentByOthers.size >= 2) {
							oldest = recentByOthers[recentByOthers.size - 2][\transform];
							if(candidateTransform == oldest
								and: { candidateTransform != leaderTransform })
							{
								score = score.max(0.5)
							}
						};

						result = score
					}
				}
			};

			result
		}
	),

	// --- BIAS PARAMETERS ------------------------------------------------
	// Consumed by updateAgentBias rather than scored per-candidate.
	// fn returns 0 so they don't pollute layer softmaxes; layer/guiGroup
	// determines GUI placement only.

	(
		name:          \entrainmentStrength,
		layer:         \deliberative,
		guiGroup:      \harmonic,
		label:         "Entrainment",
		defaultWeight: 0.4,
		charRange:     [0.2, 0.7],
		description:   "Strength of pull toward neighbouring agents' harmonic implications",
		fn:            { |self, cell, ctx| 0.0 }
	),

	(
		name:          \homeStrength,
		layer:         \deliberative,
		guiGroup:      \harmonic,
		label:         "Home strength",
		defaultWeight: 0.6,
		charRange:     [0.3, 0.8],
		description:   "Strength of pull toward home triad pitch classes",
		fn:            { |self, cell, ctx| 0.0 }
	),

];

// ====================================================================

// Helper: used by presets to look up a drive's default weight by name.
// Falls back to the supplied default if the registry entry is missing
// or has no defaultWeight field. Lets callers depend on the registry
// as source of truth without hardcoding values.
~driveDefault = { |name, fallback|
    var entry = ~driveRegistry.detect { |d| d[\name] == name };
    if(entry.notNil and: { entry[\defaultWeight].notNil }) {
        entry[\defaultWeight]
    } {
        fallback
    }
};

)