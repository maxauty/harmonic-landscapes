// =============================================================================
// core/timesource.scd — Tick scheduling
//
// Abstracts tick scheduling away from the simulation. A time source owns the
// decision of when a tick fires; the simulation supplies `onTick` as a
// callback and responds to it.
//
// All time sources expose the same interface:
//
//   source.start(nTicks)  — begin emitting ticks (nTicks = nil for infinite)
//   source.stop           — halt emission, clear state
//   source.onTick         — settable callback; called with no args at each tick
//   source.tickSize       — beats per tick (read/write)
//   source.tickIndex      — current tick number (read)
//   source.tickTime       — beat position of the current tick (read)
//   source.clock          — the underlying clock driving MIDI scheduling
//
// Two implementations:
//   ~internalTimeSource — drives ticks from SuperCollider's TempoClock.default.
//                         Standalone, no network dependencies.
//   ~linkTimeSource     — drives ticks from a LinkClock. Follows Ableton Link
//                         peers (Ableton Live, other SC sessions, iOS apps)
//                         when they are present on the network.
// =============================================================================

(

// -----------------------------------------------------------------------------
// Internal time source — TempoClock-based
// -----------------------------------------------------------------------------

~internalTimeSource = { |tickSize = 0.25|

	(
		name:       \internal,
		clock:      TempoClock.default,
		tickSize:   tickSize,
		tickIndex:  0,
		tickTime:   0,
		tickZero:   0,
		onTick:     nil,
		routine:    nil,
		running:    false,

		start: { |self, nTicks|
			var clock = self[\clock];
			if(self[\running]) { self[\stop].(self) };

			self[\tickZero]  = clock.nextBar;
			self[\tickIndex] = 0;
			self[\running]   = true;

			self[\routine] = Routine({
				var total = nTicks ? inf;
				total.do { |i|
					var target  = self[\tickZero] + (i * self[\tickSize]);
					var nowBeat = clock.beats;
					var waitFor = (target - nowBeat).max(0);

					// Drift recovery: if we're already past the next tick by
					// more than one tickSize, skip ahead without firing onTick.
					if((nowBeat - target) > self[\tickSize]) {
						self[\tickIndex] = ((nowBeat - self[\tickZero])
							/ self[\tickSize]).floor.asInteger;
						"Time source: drift detected, skipping to tick %"
							.format(self[\tickIndex]).postln;
					} {
						waitFor.wait;
						self[\tickIndex] = i;
						self[\tickTime]  = target;
						if(self[\onTick].notNil) { self[\onTick].value };
					}
				};
				self[\routine] = nil;
				self[\running] = false;
			}).play(clock, quant: nil);

			"Time source: internal started (tickSize = % beats, tempo = % bpm)"
				.format(self[\tickSize], (clock.tempo * 60).round(0.1)).postln;
		},

		stop: { |self|
			if(self[\routine].notNil) {
				self[\routine].stop;
				self[\routine] = nil;
			};
			self[\running] = false;
			"Time source: internal stopped".postln;
		},

		setTempo: { |self, bps|
			self[\clock].tempo = bps;
			"Time source: internal tempo set to % bpm".format(bps * 60).postln;
		},

		numPeers: { |self| 0 },

		describe: { |self|
			"Time source: % | running:% | tick:% | tickSize:% | tempo:% bpm"
				.format(
					self[\name],
					self[\running],
					self[\tickIndex],
					self[\tickSize],
					(self[\clock].tempo * 60).round(0.1)
				).postln;
		}
	)
};


// -----------------------------------------------------------------------------
// Link time source — LinkClock-based, follows Ableton Link peers
// -----------------------------------------------------------------------------
//
// Behavioural notes:
//
//   * LinkClock.tempo is adjusted by the peer network. Local setTempo proposes
//     a tempo to the network; if peers agree it takes hold. If they don't,
//     the network's tempo wins.
//
//   * LinkClock.beats is phase-aligned with peers. tickZero may not be local
//     beat zero; it is whatever beat position the network considers current.
//     Our tick grid aligns to that.
//
//   * If no peers are present, LinkClock behaves like a TempoClock with the
//     configured initial tempo. Joining a peer later adopts its tempo.
//
//   * Latency (default 50ms) is the lookahead needed for network agreement.
//     Lower values are tighter but more fragile; higher values are more
//     robust at the cost of response time.
// -----------------------------------------------------------------------------

~linkTimeSource = { |tickSize = 0.25, initialTempo = 2.0, latency = 0.05|

	var clock;
	try {
		clock = LinkClock.new(initialTempo).latency_(latency);
	} { |err|
		"LinkClock unavailable (%), falling back to TempoClock.default"
			.format(err.errorString).postln;
		clock = TempoClock.default;
	};

	(
		name:       \link,
		clock:      clock,
		tickSize:   tickSize,
		tickIndex:  0,
		tickTime:   0,
		tickZero:   0,
		onTick:     nil,
		routine:    nil,
		running:    false,

		start: { |self, nTicks|
			var clock = self[\clock];
			if(self[\running]) { self[\stop].(self) };

			self[\tickZero]  = clock.nextBar;
			self[\tickIndex] = 0;
			self[\running]   = true;

			self[\routine] = Routine({
				var total = nTicks ? inf;
				total.do { |i|
					var target  = self[\tickZero] + (i * self[\tickSize]);
					var nowBeat = clock.beats;
					var waitFor = (target - nowBeat).max(0);

					// Drift recovery
					if((nowBeat - target) > self[\tickSize]) {
						self[\tickIndex] = ((nowBeat - self[\tickZero])
							/ self[\tickSize]).floor.asInteger;
						"Time source (link): drift detected, skipping to tick %"
							.format(self[\tickIndex]).postln;
					} {
						waitFor.wait;
						self[\tickIndex] = i;
						self[\tickTime]  = target;
						if(self[\onTick].notNil) { self[\onTick].value };
					}
				};
				self[\routine] = nil;
				self[\running] = false;
			}).play(clock, quant: nil);

			"Time source: link started (tickSize = % beats, tempo = % bpm, peers = %)"
				.format(self[\tickSize],
					(clock.tempo * 60).round(0.1),
					self[\numPeers].(self)
				).postln;
		},

		stop: { |self|
			if(self[\routine].notNil) {
				self[\routine].stop;
				self[\routine] = nil;
			};
			self[\running] = false;
			"Time source: link stopped".postln;
		},

		setTempo: { |self, bps|
			self[\clock].tempo = bps;
			"Time source: link tempo proposed at % bpm".format(bps * 60).postln;
		},

		numPeers: { |self|
			if(self[\clock].respondsTo(\numPeers)) {
				self[\clock].numPeers
			} {
				0
			}
		},

		describe: { |self|
			"Time source: % | running:% | tick:% | tickSize:% | tempo:% bpm | peers:%"
				.format(
					self[\name],
					self[\running],
					self[\tickIndex],
					self[\tickSize],
					(self[\clock].tempo * 60).round(0.1),
					self[\numPeers].(self)
				).postln;
		}
	)
};


// -----------------------------------------------------------------------------
// Factory — choose a time source by symbol
// -----------------------------------------------------------------------------

~timeSourceFactory = { |kind = \internal, tickSize = 0.25|
	switch(kind,
		\internal, { ~internalTimeSource.(tickSize) },
		\link,     { ~linkTimeSource.(tickSize) },
		{
			"Unknown time source kind: % — defaulting to internal".format(kind).postln;
			~internalTimeSource.(tickSize)
		}
	)
};

)
