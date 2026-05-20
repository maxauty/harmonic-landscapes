// =============================================================================
// Chord Detection
//
// (Crude — needs work) v2.5.3
// =============================================================================

(
~simulation[\postChords] = true;

~detectChord = {
	var agents        = ~simulation[\agents];
	var grid          = ~simulation.grid;
	var harmonicState = ~simulation[\harmonicState];
	var noteNames     = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];

	var pcs = agents.collect { |a|
		grid.pitchClassAt(a[\pos].x, a[\pos].y).asInteger
	}.asSet.asArray.sort;

	var templates = [
		[[0,4,7],       "maj"    ], [[0,3,7],       "min"    ],
		[[0,4,8],       "aug"    ], [[0,3,6],       "dim"    ],
		[[0,5,7],       "sus4"   ], [[0,2,7],       "sus2"   ],
		[[0,4,7,11],    "maj7"   ], [[0,4,7,10],    "dom7"   ],
		[[0,3,7,10],    "min7"   ], [[0,3,6,10],    "min7b5" ],
		[[0,3,6,9],     "dim7"   ], [[0,4,8,10],    "aug7"   ],
		[[0,3,7,11],    "minMaj7"], [[0,4,7,10,14], "dom9"   ],
		[[0,4,7,11,14], "maj9"   ], [[0,3,7,10,14], "min9"   ],
		[[0,7],         "5"      ], [[0,4],         "3rd"    ],
		[[0,3],         "min3rd" ],
	];

	var bestScore = -1; var bestRoot = nil; var bestName = nil;

	12.do { |root|
		var intervals = pcs.collect { |pc| (pc - root).mod(12) }
		.asSet.asArray.sort;
		templates.do { |pair|
			var template = pair[0]; var name = pair[1];
			var covered  = template.count { |t| intervals.includes(t) };
			var extras   = intervals.count { |i| template.includes(i).not };
			var score    = (covered / template.size) - (extras * 0.3);
			if(score > bestScore and: { covered == template.size }) {
				bestScore = score; bestRoot = root; bestName = name }
		}
	};

	// return a result event rather than posting directly
	if(bestRoot.notNil) {
		var tonicPC = (harmonicState[\tonicPC] ? 0).round.asInteger;
		(
			found:    true,
			root:     noteNames[bestRoot],
			name:     bestName,
			pcs:      pcs.collect { |pc| noteNames[pc] }.join(" "),
			tonic:    noteNames[tonicPC],
			fn:       harmonicState[\impliedFunction] ? \ambiguous
		)
	} {
		(
			found: false,
			pcs:   pcs.collect { |pc| noteNames[pc] }.join(" ")
		)
	}
};

// posting version — call manually or from postStep
~postChord = {
	var r = ~detectChord.();
	if(r[\found]) {
		"Chord: % % | PCs: [ % ] | tonic: % | fn: %".format(
			r[\root], r[\name], r[\pcs], r[\tonic], r[\fn]).postln
	} {
		"No match | PCs: [ % ]".format(r[\pcs]).postln
	}
};
)