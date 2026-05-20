// =============================================================================
// core/utilities.scd — Shared mathematical and musical helpers
//
// Small, broadly-applicable functions used across the system. Organised into:
//   General vector math    — basic 2D point operations
//   Drawing primitives     — hex geometry helpers (to move to gui.scd)
//   Motion analysis        — interval-contour extraction and similarity
//   Voice realisation      — Stage 2 voicing functions
//   Mode metrics           — modal coverage scoring
// =============================================================================

(

// General vector maths

~zeroVector = Point(0, 0);

~innerProduct = { |a, b|
	if(a.notNil and: { b.notNil }) {
		(a.x * b.x) + (a.y * b.y)
	} { ~zeroVector }
};

~normalize = { |p|
	var mag = (p.x.squared + p.y.squared).sqrt;
	if(mag > 0) { p / mag } { ~zeroVector }
};


// Drawing primitives
// To be relocated to gui.scd when that file is cleaned. Left here for now so
// the GUI continues to find them at load time.

~hexUnit = (0..5).collect { |i|
	var a = i * (pi / 3);
	Point(cos(a), sin(a));
};

~drawHex = { |center, radius|
	var first = center + (~hexUnit[0] * radius);
	Pen.moveTo(first);
	(1..5).do { |i| Pen.lineTo(center + (~hexUnit[i] * radius)) };
	Pen.lineTo(first);
};


// Motion analysis

// Reduce a sequence of motion records to a sign sequence (+1, 0, -1) capturing
// up / static / down melodic contour.
~motionContour = { |motionSequence|
	motionSequence.collect { |m|
		var interval = m[\interval];
		interval.sign
	}
};

// Fraction of contour steps that match between two motion sequences.
// Used by the imitation drive to score how closely an agent's recent motion
// resembles a neighbour's.
~contourSimilarity = { |a, b|
	var length = min(a.size, b.size);
	var sameSteps = 0;
	if(length == 0) { ^0 };
	length.do { |i|
		sameSteps = sameSteps + (a[i] == b[i]).asInteger;
	};
	sameSteps / length
};

// Realise a pitch class as a MIDI note within the agent's range, choosing
// the octave instance that best balances three preferences:
//   1. Melodic smoothness from the agent's previous pitch
//   2. Spacing against other simultaneously-sounding agents
//   3. Mild pull toward the centre of the register
// Weights are read from ~simulation so they can be tuned at runtime.
~realisePitch = { |chosenPC, lastMidi, otherMidis, rangeLo, rangeHi|
	var bestMidi  = nil;
	var bestScore = -inf;
	var wMelodic = ~simulation[\realiseMelodic] ? 0.5;
	var wSpacing = ~simulation[\realiseSpacing] ? 0.35;
	var wCentre  = ~simulation[\realiseCentre]  ? 0.15;

	rangeLo    = rangeLo ? 24;
	rangeHi    = rangeHi ? 84;
	lastMidi   = lastMidi ? (rangeLo + ((rangeHi - rangeLo) / 2).round);
	otherMidis = otherMidis ? [];

	// Score every octave instance of chosenPC that falls inside the range.
	(0..9).do { |oct|
		var midi = chosenPC + (oct * 12);
		if(midi >= rangeLo and: { midi <= rangeHi }) {

			// 1. Melodic smoothness — penalise large intervals from last pitch.
			var melodicDist  = (midi - lastMidi).abs;
			var melodicScore = 1.0 / (1.0 + melodicDist);

			// 2. Ensemble spacing — penalise unison/octave doubling. Score is
			//    0 at unison, 1 at tritone separation.
			var spacingScore = if(otherMidis.isEmpty) { 1.0 } {
				var minDist = otherMidis.collect { |om|
					var d = (midi - om).abs.mod(12);
					d.min(12 - d)
				}.minItem;
				minDist / 6.0
			};

			// 3. Register centre preference — mild pull toward middle of range.
			var centre      = (rangeLo + rangeHi) / 2.0;
			var centreScore = 1.0 - ((midi - centre).abs / ((rangeHi - rangeLo) / 2.0)).clip(0, 1);

			var total = (melodicScore * wMelodic) + (spacingScore * wSpacing) + (centreScore * wCentre);

			if(total > bestScore) {
				bestScore = total;
				bestMidi  = midi;
			}
		}
	};

	// Fallback: no in-range candidate scored. (Note: applies the same range
	// filter as the main loop, so this branch is unreachable when the main
	// loop is unable to score anything — retained for defensive symmetry.)
	if(bestMidi.isNil) {
		var nearest = (0..9).collect { |oct| chosenPC + (oct * 12) }
			.select { |m| m >= rangeLo and: { m <= rangeHi } }
			.minItem { |m| (m - lastMidi).abs };
		bestMidi = nearest;
	};

	// Last resort: range is impossible — clamp lastMidi into valid MIDI.
	if(bestMidi.isNil) {
		bestMidi = lastMidi.clip(0, 127)
	};

	bestMidi
};


// Mode metrics

// F1 score quantifying how well a set of nearby pitch classes "covers" a
// modal collection. Precision: fraction of mode PCs present in the nearby
// set. Recall: fraction of nearby PCs that belong to the mode.
~modeF1 = { |nearbyPCs, modeCollection, tonicPC|
	var transposed = modeCollection.collect { |pc| (pc + tonicPC).mod(12) };
	var covered    = nearbyPCs.count { |pc| transposed.includes(pc) };
	var precision  = covered / transposed.size.max(1);
	var recall     = covered / nearbyPCs.size.max(1);
	if((precision + recall) > 0) {
		2 * precision * recall / (precision + recall)
	} { 0.0 }
};

)
