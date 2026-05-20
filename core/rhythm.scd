// =============================================================================
// core/rhythm.scd — Rhythm substrate
//
// Per-agent rhythmic identity:
//
//   pulses:    integer count of onsets per cycle (N)
//   cycleLen:  total grid positions per cycle (K)
//   phase:     offset within cycle, 0..K-1
//   pattern:   derived array of K integers (1=onset, 0=rest)
//
// The pattern is the Bjorklund-distributed pulse count over cycleLen,
// rotated by phase. Operations that change pulses, cycleLen, or phase
// must call ~regeneratePattern to refresh the pattern array.
//
// Phase coupling — Kuramoto-style agent synchronisation that operates on
// these rhythms — is a separate concern handled outside this file. This
// module provides only the per-agent rhythmic substrate that coupling
// reads and modulates.
// =============================================================================

(

// -----------------------------------------------------------------------------
// Bjorklund's algorithm — distribute N pulses as evenly as possible over K positions.
//
// Implementation follows Toussaint (2005). For Euclidean rhythms, the result is
// the maximally even distribution: tresillo (3,8) = [1,0,0,1,0,0,1,0],
// cinquillo (5,8) = [1,0,1,1,0,1,1,0], etc.
// -----------------------------------------------------------------------------

~bjorklund = { |pulses, cycleLen|
	var result;

	if(pulses <= 0 or: { cycleLen <= 0 }) {
		result = Array.fill(cycleLen.max(1), 0)
	} {
		if(pulses >= cycleLen) {
			result = Array.fill(cycleLen, 1)
		} {

			var sequences = Array.fill(pulses, { [1] })
				++ Array.fill(cycleLen - pulses, { [0] });
			var done    = false;
			var maxIter = pulses.min(cycleLen - pulses) + 2;

			maxIter.do { |iter|
				var first, last, nFirst, nLast, nPair, paired, leftoverFirst, leftoverLast;

				if(done.not) {
					first  = sequences[0];
					last   = sequences[sequences.size - 1];
					nFirst = sequences.count { |s| s == first };
					nLast  = sequences.count { |s| s == last };

					if(first == last or: { nLast <= 1 }) {
						done = true
					} {
						nPair  = nFirst.min(nLast);
						paired = Array.fill(nPair, { |i|
							sequences[i] ++ sequences[sequences.size - 1 - i]
						});
						leftoverFirst = if(nFirst > nPair) {
							sequences.copyRange(nPair, nFirst - 1)
						} { [] };
						leftoverLast = if(nLast > nPair) {
							sequences.copyRange(nFirst, sequences.size - nPair - 1)
						} { [] };

						sequences = paired ++ leftoverFirst ++ leftoverLast;

						// If the operation produced a pattern that won't
						// reduce further, exit.
						if(sequences.size == 1 or: { nPair < 1 }) { done = true }
					}
				}
			};

			result = sequences.flat;
		}
	};

	result
};


// -----------------------------------------------------------------------------
// Build a rhythm event for an agent.
// -----------------------------------------------------------------------------

~makeRhythm = { |pulses = 4, cycleLen = 16, phase = 0|
	var pattern = ~bjorklund.(pulses, cycleLen);
	if(phase != 0) {
		pattern = pattern.rotate(phase.neg)   // rotate so phase=N starts at index N
	};

	(
		pulses:   pulses,
		cycleLen: cycleLen,
		phase:    phase,
		pattern:  pattern
	)
};


// -----------------------------------------------------------------------------
// Regenerate the pattern after pulses/cycleLen/phase changes.
// Call this whenever rhythm parameters mutate.
// -----------------------------------------------------------------------------

~regeneratePattern = { |rhythm|
	var pattern = ~bjorklund.(rhythm[\pulses], rhythm[\cycleLen]);
	if(rhythm[\phase] != 0) {
		pattern = pattern.rotate(rhythm[\phase].neg)
	};
	rhythm[\pattern] = pattern;
	rhythm
};


// -----------------------------------------------------------------------------
// Query: does this rhythm fire at cycle position `pos`?
// -----------------------------------------------------------------------------

~rhythmFiresAt = { |rhythm, pos|
	var idx = pos.mod(rhythm[\cycleLen]);
	(rhythm[\pattern][idx] ? 0) == 1
};

// -----------------------------------------------------------------------------
// Query: how many ticks until the next onset after `currentPos`?
//
// Searches forward through the pattern wrapping at cycleLen.
// Returns cycleLen if there is only one onset — the note should then
// last a full cycle. Returns 1 if every position is an onset.
//
// This is what Stage 3 of agent commit uses to set note duration, so
// that the noteOff is scheduled to arrive just before the next noteOn
// rather than at some nominal stepInterval that may not match the
// actual Bjorklund distribution.
// -----------------------------------------------------------------------------

~nextOnsetGap = { |rhythm, currentPos|
    var pattern  = rhythm[\pattern];
    var cycleLen = rhythm[\cycleLen];
    var gap      = cycleLen;   // fallback: full cycle (single or zero onsets)
    var found    = false;

    (cycleLen - 1).do { |i|
        if(found.not) {
            var nextIdx = (currentPos + 1 + i).mod(cycleLen);
            if((pattern[nextIdx] ? 0) == 1) {
                gap   = i + 1;
                found = true;
            }
        }
    };

    gap
};

// -----------------------------------------------------------------------------
// Construct a rhythm from a step interval — derives a Euclidean rhythm whose
// density matches the requested step rate. With stepInterval 4 and cycleLen
// 16, returns a 4-pulse rhythm firing at positions 0, 4, 8, 12. Used by the
// agent factory to give each agent a rhythm matching its configured step rate.
// -----------------------------------------------------------------------------

~stepIntervalToRhythm = { |stepInterval, cycleLen = 16|
	var pulses = (cycleLen / stepInterval.max(1)).round.asInteger.max(1).min(cycleLen);
	~makeRhythm.(pulses, cycleLen, 0)
};

)
