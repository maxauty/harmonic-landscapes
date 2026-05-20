// =============================================================================
// core/simulation.scd — Simulation factory and orchestration
//
// Defines ~simulationFactory and its core control methods: spawning,
// start/stop, the main step loop, and the methods that step calls
// directly to advance one tick of simulation time.
//
// Harmonic state methods (tonic tracking, triad inference, function
// weighting, tension, structural clock) live in harmonic_state.scd.
// Agent population dynamics (birth, death, phase coupling) live in
// lifecycle.scd. Both files extend ~simulationFactory at load time.
// =============================================================================

(
~simulationFactory = { |grid, driveModel|
    var sd = ~presetSchema[\global]; // schema defaults — valid at call time

    (
        // =====================================================================
        // INJECTED DEPENDENCIES
        // =====================================================================
        grid:                 grid,
        driveModel:           driveModel,
        modeCollections:      ~modeCollections,

        // =====================================================================
        // CONFIGURATION — from schema (single source of truth: ~presetSchema)
        // =====================================================================
        // Movement & timing
        tickSize:             sd[\tickSize][\default],
        globalCycleLen:       sd[\globalCycleLen][\default],
        gestureThreshold:     sd[\gestureThreshold][\default],
        jumpRadius:           sd[\jumpRadius][\default],
        jumpOnResolve:        sd[\jumpOnResolve][\default],
        initialTempo:         sd[\initialTempo][\default],

        // Layer blending
        harmonicBlend:        sd[\harmonicBlend][\default],
        deliberativeBlend:    sd[\deliberativeBlend][\default],
        tempMotion:           sd[\tempMotion][\default],
        tempHarmonic:         sd[\tempHarmonic][\default],
        tempGesture:          sd[\tempGesture][\default],
        tempDeliberative:     sd[\tempDeliberative][\default],

        // Harmonic state
        tonicLocked:          sd[\tonicLocked][\default],
        lockedTonicPC:        sd[\lockedTonicPC][\default],
        modeLocked:           sd[\modeLocked][\default],
        lockedModeKey:        sd[\lockedModeKey][\default],
        modeStrictness:       sd[\modeStrictness][\default],
        modeHysteresis:       sd[\modeHysteresis][\default],
        tonicShiftThreshold:  sd[\tonicShiftThreshold][\default],
        tonicUpdateRate:      sd[\tonicUpdateRate][\default],
        resolveBoundary:      sd[\resolveBoundary][\default],

        // Structural clock
        structuralClockPeriod: sd[\structuralClockPeriod][\default],

        // Lifecycle (birth)
        birthEnabled:          sd[\birthEnabled][\default],
        birthContestThreshold: sd[\birthContestThreshold][\default],
        birthDwellSteps:       sd[\birthDwellSteps][\default],
        maxAgents:             sd[\maxAgents][\default],

        // Lifecycle (death)
        deathEnabled:          sd[\deathEnabled][\default],
        samePCDeathSteps:      sd[\samePCDeathSteps][\default],
        blockedDeathSteps:     sd[\blockedDeathSteps][\default],
        minAgents:             sd[\minAgents][\default],

        // Voice realisation
        realiseMelodic:       sd[\realiseMelodic][\default],
        realiseSpacing:       sd[\realiseSpacing][\default],
        realiseCentre:        sd[\realiseCentre][\default],
        registerCenter:       sd[\registerCenter][\default],

        // Spatial & social
        interactionRadius:    sd[\interactionRadius][\default],
        responseWindow:       sd[\responseWindow][\default],

        // Debug
        debugMovement:        sd[\debugMovement][\default],
        postChords:           sd[\postChords][\default],
        debugStructuralClock: false,    // dev flag, intentionally hardcoded

        // =====================================================================
        // RUNTIME STATE — mutated by the simulation as it runs
        // =====================================================================
        // Agent population
        agents:               Array.new,
        nextAgentID:          0,
        priorityOffset:       0,
        agentRoutine:         nil,

        // Time
        timeSource:           nil,
        timeSourceKind:       \internal,
        tickIndex:            0,
        tickTime:             0,
        cyclePos:             0,

        // Tension-modulated runtime copy of harmonicBlend
        effectiveHarmonicBlend: sd[\harmonicBlend][\default],

        // Harmonic state (this whole nested Event is mutated each step)
        harmonicState: (
            tonicPC:           0,
            occupiedTriads:    [],
            impliedTriads:     [],
            impliedFunction:   \ambiguous,
            tensionLevel:      0.0,
            recentTransforms:  [],
            functionWeights:   (),
            functionContest:   0,
            contestHistory:    [],
        ),

        // =====================================================================
        // METHODS (defined below and in harmonic_state.scd, lifecycle.scd)
        // =====================================================================

		spawnAgents: { |self, nAgents, octave, stepInterval=2|

			var center, neighbors;
			var defaultModes = [\major, \dorian, \mixolydian, \minor,
				\phrygian, \hexatonic, \octatonic, \chromatic];

			// initial placement diversity — staggers starting modeCollections
			// around the circle of fifths; not a persistent per-agent property
			var tonicOffsets = [0, 7, 2, 9, 4, 11, 5, 10];
			var thresholds   = [0.2, 0.3, 0.25, 0.35, 0.2, 0.3, 0.25, 0.35];
			var entrainments = [0.6, 0.3, 0.5,  0.2,  0.6, 0.3, 0.5,  0.2 ];
			var homeStrengths= [0.4, 0.7, 0.5,  0.8,  0.4, 0.7, 0.5,  0.8 ];
			var octaveSpread = [-2, -1, -1, 0, 0, 0, 1, 1];

			var rawDeltas    = Array.fill(nAgents, { |i| i - ((nAgents - 1) / 2) });
			var maxSpread    = 2;  // outer agents this many octaves from centre
			var scale        = if(nAgents > 1) { maxSpread / rawDeltas.last } { 0 };
			var octaveDeltas = rawDeltas.collect { |d| (d * scale).round.asInteger };

			self[\registerCentre] = octave;  // Record the request, separate from per-agent assignments
			self[\nextAgentID] = 0;

			center    = Point(rrand(0, self.grid.width - 1),
				rrand(0, self.grid.height - 1));
			neighbors = self.grid.wrappedNeighbors(center);

			self[\agents] = Array.fill(nAgents, { |i|
				var pos     = if(i == 0) { center } { neighbors.scramble.wrapAt(i - 1) };
				var modeKey = defaultModes.wrapAt(i);
				var tonicPC = tonicOffsets.wrapAt(i);
				var char    = ~randomAgentChar.();
				/*var octaveDeltas = [-2, -1, -1, 0, 0, 0, 1, 1];*/
				var agentOctave = (octave + octaveDeltas.wrapAt(i)).clip(2, 8);

				var agentID = self[\nextAgentID];
				self[\nextAgentID] = self[\nextAgentID] + 1;
				~makeAgent.(
					pos, agentOctave, Color.rand,
					~weightsFromChar.(char),
					agentID.asSymbol, stepInterval,
					~agentChannels.wrapAt(agentID),
					self.grid, modeKey, tonicPC,
					char[\activation],
					agentID,
					char[\soundThreshold] ? 0.3
				)
			});
			"Agent(s) spawned".postln;

			{ ~view.refresh }.defer;
		},

		start: { |self, nTicks=nil|
			if(self[\timeSource].isNil
				or: { self[\timeSource][\name] != self[\timeSourceKind] }
			) {
				if(self[\timeSource].notNil) {
					self[\timeSource][\stop].(self[\timeSource])
				};
				self[\timeSource] = ~timeSourceFactory.(
					self[\timeSourceKind], self[\tickSize]
				);
				self[\timeSource][\setTempo].(
					self[\timeSource], self[\initialTempo]
				);
			};

			// Reset tick-related state so every start begins cleanly aligned
			self[\stepCount] = 0;

			self[\timeSource][\tickSize] = self[\tickSize];
			self[\timeSource][\onTick]   = {
				self[\tickIndex] = self[\timeSource][\tickIndex];
				self[\tickTime]  = self[\timeSource][\tickTime];
				self.step;
			};

			self[\timeSource][\start].(self[\timeSource], nTicks);
			"Simulation started".postln;
		},

		stop: { |self|
			if(self[\timeSource].notNil) {
				self[\timeSource][\stop].(self[\timeSource])
			};
			self[\agents].do { |a|
				a[\recentMotion]    = [];
				a[\recentPositions] = [];
			};
			if(~activeNotes.notNil) {
				~activeNotes.copy.do { |entry|
					try { ~midiOut.noteOff(entry[2], entry[0], 0) };
				};
				~activeNotes.clear;
			};
			"Simulation stopped".postln;
		},

		step: { |self|
			var result, activeAgents, decisions, nextPositions;
			self[\stepCount] = (self[\stepCount] ? 0) + 1;
			self[\cyclePos]  = (self[\stepCount] - 1).mod(self[\globalCycleLen]);
			self.updateEnvironment; // moved to harmonic_state.scd v2.5.2

			if(self[\debugMovement]) { ~postStepHeader.(self) };

			result       = self.collectDecisions;
			activeAgents = result[0];
			decisions    = result[1];

			nextPositions = if(activeAgents.notEmpty) {
				self.resolveCollisions(activeAgents, decisions)
			} { [] };

			if(activeAgents.notEmpty) {
				var previousPositions = activeAgents.collect { |a| a[\pos].copy };
				activeAgents.do { |agent, i| agent[\commit].(agent, nextPositions[i]) };
				self.logTransforms(activeAgents, previousPositions);
				if(self[\debugMovement]) {
					~postStepFooter.(self, activeAgents, previousPositions) };
			};

			self[\agents].do { |agent|
				if(~rhythmFiresAt.(agent[\rhythm], self[\cyclePos])) {
					if(activeAgents.includes(agent).not) {
						agent[\commit].(agent, agent[\pos])
					}
				}
			};

			self.checkDeath; // moved to lifecycle.scd
			self.checkBirth; // moved to lifecycle.scd

			self.postStep(activeAgents);
			self[\priorityOffset] = (self[\priorityOffset] + 1) % self[\agents].size.max(1);

			{
				if(~midiHistory.notNil) {
					~simulation[\agents].do { |agent|
						var midi = agent[\currentMidi];
						if(midi.notNil) {
							var h = ~midiHistory[agent[\id]] ? [];
							~midiHistory[agent[\id]] = (h ++ [midi]).keep(-32)
						}
					}
				};
				~view.refresh;
				if(~voiceView.notNil) { ~voiceView.refresh };
				if(~rhythmView.notNil) { ~rhythmView.refresh };
				if(~updateMonitors.notNil) { ~updateMonitors.() };
			}.defer;
		},

		// Coordinator — called from step, sequences the sub-methods
		updateEnvironment: { |self|
			self.updateTonicCentre;
			self.updateTriadState;
			self.updateFunctionContest;
			self.updateAgentBias;
			self.updateAgentTension;
			self.updateStructuralClock;
			self.updatePhaseCoupling;
			self.debugHarmonicState;
		},

		collectDecisions: { |self|
			var activeAgents = List.new;
			var decisions    = List.new;
			var grid         = self.grid;
			var hs           = self[\harmonicState];

			// Stationary this tick = agents whose stepInterval doesn't fire.
			// Their current positions are hard-blocked for other agents.
			// Agents whose stepInterval does fire may vacate — not blocked.
			var stationaryPositions = self[\agents]
			.select { |a|
				~rhythmFiresAt.(a[\rhythm], self[\cyclePos]).not
			}
			.collect { |a| a[\pos] }
			.select(_.notNil);

			self[\stationaryPositions] = stationaryPositions;

			self[\agents].do { |agent|
				var pos = self[\cyclePos];
				if(~rhythmFiresAt.(agent[\rhythm], pos)) {
					var others        = self[\agents].reject(_ === agent);
					var activation    = agent[\activation] ? (self[\activation] ? 0.5);
					var tensionScore  = agent[\tensionScore] ? 0.0;

					// Tension raises effective activation probability
					var effective     = activation + (tensionScore * (1.0 - activation));
					var willAct       = 1.0.rand <= effective;

					if(self[\debugMovement] ? false) {
						var agentPC = grid.pitchClassAt(
							agent[\pos].x, agent[\pos].y).asInteger;
						"Step: % | Agent: % | pc:% activation:% tension:% → p_act:% | %".format(
							self[\stepCount],
							agent[\label],
							agentPC,
							activation.round(0.01),
							tensionScore.round(0.01),
							effective.round(0.01),
							if(willAct) { "ACT" } { "—" }
						).postln;
					};

					if(willAct) {
						var decision = agent[\decide].(agent, others, tensionScore);
						if(decision.notNil) {
							activeAgents.add(agent);
							decisions.add(decision);
						}
					}
				}
			};

			[activeAgents, decisions]
		},

		resolveCollisions: { |self, activeAgents, decisions|
			var nextPositions = decisions.collect(_[\cell]);
			var losers        = Array.fill(activeAgents.size, false);
			var order         = (0 .. activeAgents.size - 1).rotate(self[\priorityOffset]);

			// Occupied positions: agents NOT in activeAgents this tick
			var occupiedByStationary = self[\agents]
			.reject { |a| activeAgents.includes(a) }
			.collect { |a| a[\pos] }
			.select(_.notNil);

			// Block moves into stationary-occupied cells
			activeAgents.do { |agent, i|
				if(losers[i].not) {
					var target = nextPositions[i];
					var blocked = occupiedByStationary.any { |p|
						p.x == target.x and: { p.y == target.y }
					};
					if(blocked) { losers[i] = true }
				}
			};

			// Existing pairwise collision resolution
			order.do { |i|
				order.do { |j|
					if(i < j and: { losers[i].not } and: { losers[j].not }) {
						if(nextPositions[i].x == nextPositions[j].x and: {
							nextPositions[i].y == nextPositions[j].y } and: {
							(nextPositions[i].x != activeAgents[i][\pos].x) or: {
								nextPositions[i].y != activeAgents[i][\pos].y
							}
						}) {
							if(decisions[i][\total] > decisions[j][\total]) {
								losers[j] = true
							} {
								losers[i] = true
							}
						}
					}
				}
			};

			activeAgents.do { |agent, i|
				if(losers[i]) {
					nextPositions[i] = agent[\pos];
					agent[\stepsBlocked] = (agent[\stepsBlocked] ? 0) + 1;
				} {
					agent[\stepsBlocked] = 0;
				}
			};

			nextPositions
		},

		postStep: { |self, activeAgents|
			if((self[\stepCount] % 4) == 0 and: self[\postChords] ? false) { ~detectChord.() };
		}
	)
};

)
