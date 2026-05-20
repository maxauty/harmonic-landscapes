// =============================================================================
// core/agents.scd — Agent factories
//
// Defines:
//   ~randomAgentChar — produces a randomised drive-weight profile, used to
//                      diversify agent populations at spawn time
//   ~makeAgent       — the main factory: constructs an agent Event with
//                      identity, spatial state, modal context, memory,
//                      lifecycle counters, and the decide/commit methods
//                      that drive its behaviour each tick
//
// The three-stage decision pipeline is implemented within `commit`:
//   Stage 1 — Position: record motion, update memory, commit new grid pos
//   Stage 2 — Voicing:  realise the chosen pitch class as an octave-placed MIDI note
//   Stage 3 — Sound:    emit if resonance exceeds threshold, update stasis counters
// =============================================================================

(

// --- Agent lookup helpers ---------------------------------------------------

~agentByID = { |id|
    ~simulation[\agents].detect { |a| a[\id] == id }
};

~nextFreeAgentID = {
    var usedIDs = ~simulation[\agents].collect { |a| a[\id] }.asSet;
    var id = 0;
    { usedIDs.includes(id) }.while { id = id + 1 };
    id
};

// --- Per-agent randomisation ------------------------------------------------
// Returns an Event of randomly-drawn drive weights and thresholds, used to
// give each agent in a population a slightly different temperament. Ranges
// are hand-tuned to keep agents in a viable behavioural region.

~randomAgentChar = {
    var event = ();

    // Drive-level randomisation: walk the registry, draw any drive that
    // declares a charRange.
    ~driveRegistry.do { |d|
        if(d[\charRange].notNil) {
            event[d[\name]] = rrand(d[\charRange][0], d[\charRange][1])
        }
    };

    // Agent-level randomisation (not per-drive):
    event[\activation]     = rrand(0.4, 0.8);
    event[\soundThreshold] = rrand(0.0, 0.1);

    event
};

// Canonical default weights — single source of truth.
// Reads from ~presetSchema so defaults never diverge from the schema registry.
~defaultAgentWeights = {
    var w = ();
    ~presetSchema[\agentWeights].keysValuesDo { |key, spec|
        w[key] = spec[\default];
    };
    w
};

// Build a weights Event from a per-agent character draw.
// Character-randomised fields come from char; everything else falls through
// to the schema default via ~defaultAgentWeights.
~weightsFromChar = { |char|
    var weights = ();
    ~driveRegistry.do { |d|
        var fromChar = char[d[\name]];
        weights[d[\name]] = fromChar ? d[\defaultWeight];
    };
    weights
};


// --- Agent factory ----------------------------------------------------------

~makeAgent = { |pos, octave=5, color, weights, label, stepInterval=4.0,
                channel=0, grid, modeKey=\major, tonicPC=0,
                activation=0.5, id=0, soundThreshold=0.3|

	// tonicPC enters only via the derived modal context (collection and
	// home triad). It is not stored on the agent — the simulation's collective
	// tonic governs runtime modal behaviour.
	var collection = (~modeCollections[modeKey] ? ~modeCollections[\major])
		.collect { |pc| (pc + tonicPC).mod(12) };
	var triadIntervals = ~modeHomeTriad[modeKey] ? [0, 4, 7];
	var homeTriad      = triadIntervals.collect { |i| (tonicPC + i).mod(12) };

	color   = color ? Color.white;
	weights = weights ? ~defaultAgentWeights.();

	(
		// --- identity ---
		id:               id,
		label:            label,

		// --- spatial state ---
		pos:              pos.asPoint,
		lastDir:          nil,
		grid:             grid,

		// --- voicing state ---
		octave:           octave,
		currentMidi:      nil,
		lastMidi:         nil,
		// Register constraint — preferred MIDI range. Candidates outside this
		// range are penalised in scoreHarmonics independently of the harmonic
		// constraint system.
		voiceRangeLo:     ((octave - 1) * 12).clip(12, 120),
		voiceRangeHi:     ((octave + 1) * 12).clip(12, 120),

		// --- modal context ---
		modeKey:          modeKey,
		modeCollection:   collection,
		homeTriad:        homeTriad,
		harmonicBias:     Array.fill(12, { 1.0 }),

		// --- behavioural parameters ---
		color:            color,
		weights:          weights,
		stepInterval:     stepInterval,
		channel:          channel,
		activation:       activation,
		soundThreshold:   soundThreshold,   // was: 0.0
		tensionScore:     0.0,

		// --- memory ---
		trail:            [],
		recentPositions:  [],
		recentMotion:     [],

		// --- timing / stasis counters ---
		stepsSinceMove:   0,
		stepsSinceSound:  0,

		// --- lifecycle scaffolding ---
		// Fields reserved for planned features: agent destruction on prolonged
		// high tension, agent splitting on harmonic ambiguity, and stagnation
		// detection. Currently inert — written but not yet read by the
		// simulation loop.
		stepsHighTension: 0,
		stepsSamePC:      0,
		stepsBlocked:     0,
		dead:             false,

		// --- rhythmic state ---
		rhythm: ~stepIntervalToRhythm.(stepInterval, 16),


		// --- decide -----------------------------------------------------------
		// Delegate harmonic deliberation in pitch-class space to the shared
		// drive model. Returns the next position chosen for this tick.
		decide: { |self, others, tensionScore|
			~driveModel.chooseNext(
				self[\pos],
				self[\lastDir],
				others.collect(_[\pos]),
				self[\weights],
				self[\label],
				self[\recentPositions],
				self[\recentMotion],
				self[\modeCollection],
				tensionScore ? 0.5,
				self[\homeTriad],
				self[\harmonicBias],
				others,
				(
					stepInterval: self[\stepInterval],
					rhythm:       self[\rhythm],
					cyclePos:     ~simulation[\cyclePos]
				)
			)
		},


		// --- commit -----------------------------------------------------------
		// Apply the decision: update position and memory, realise voicing,
		// emit sound if appropriate, and update stasis counters.
		commit: { |self, newPos|
			var chosenPC, otherMidis, newMidi, soundThreshold, resonance;
			var currentPos = self[\pos];
			var moved      = (newPos != currentPos);

			// =================================================================
			// STAGE 1 — Position: Tonnetz navigation already chosen by `decide`
			// =================================================================

			// Memory: append current position before overwriting.
			self[\recentPositions] = (self[\recentPositions] ++ [currentPos]).keep(-8);
			self[\trail]           = (self[\trail] ++ [currentPos]).keep(-5);

			// Motion record: only logged when an actual step took place.
			if(moved) {
				var movedPC = self[\grid].pitchClassAt(newPos.x, newPos.y).asInteger;
				var lastPC  = self[\grid].pitchClassAt(currentPos.x, currentPos.y).asInteger;
				self[\lastDir]      = self[\grid].hexDelta(currentPos, newPos);
				self[\recentMotion] = (self[\recentMotion] ++ [(
					dir:          self[\lastDir],
					interval:     (movedPC - lastPC),                          // raw signed interval
					gridDistance: self[\grid].hexDistance(currentPos, newPos)  // step size on the torus
				)]).keep(-6);
			};

			self[\pos] = newPos;


			// =================================================================
			// STAGE 2 — Voicing: realise chosen PC as an octave-placed MIDI note
			// =================================================================

			chosenPC   = self[\grid].pitchClassAt(newPos.x, newPos.y).asInteger;
			otherMidis = self[\grid].notNil.if({
				// Sounded MIDI pitches of all other agents — used by the voice
				// leading cost function to avoid octave doublings and crossings.
				~simulation[\agents]
				.reject { |a| a === self }
				.collect { |a| a[\currentMidi] }
				.select(_.notNil)
			}, { [] });

			newMidi = ~realisePitch.(
				chosenPC,
				self[\currentMidi],
				otherMidis,
				self[\voiceRangeLo],
				self[\voiceRangeHi]
			);

			self[\lastMidi]    = self[\currentMidi];
			self[\currentMidi] = newMidi;


			// =================================================================
			// STAGE 3 — Sound emission
			// =================================================================

			soundThreshold = self[\soundThreshold] ? 0.3;
			resonance      = self[\resonanceScore] ? 0.0;

			if(resonance >= soundThreshold) {
				var tickBeat = ~simulation[\tickTime];

				// Derive duration from the actual gap to the next onset in
				// this agent's Bjorklund pattern, not from stepInterval.
				// When stepIntervalToRhythm rounds pulses up or down, the
				// inter-onset gaps are uneven; (stepInterval * tickSize) - 0.01
				// can overshoot the shorter gaps, so a noteOn arrives
				// before the previous noteOff on the same channel.
				// ~nextOnsetGap searches forward from the current cyclePos
				// and returns the actual tick distance to the next firing.
				var gap      = ~nextOnsetGap.(self[\rhythm], ~simulation[\cyclePos]);
				var durBeats = ((gap * ~simulation[\tickSize]) - 0.01).max(0.01);

				~playNote.(
					newMidi,
					70,
					durBeats,
					self[\channel],
					tickBeat
				)
			};

			// Update stasis / silence counters.
			self[\stepsSinceMove]  = if(moved)                       { 0 } { (self[\stepsSinceMove]  ? 0) + 1 };
			self[\stepsSinceSound] = if(resonance >= soundThreshold) { 0 } { (self[\stepsSinceSound] ? 0) + 1 };
		},
	)
};

)
