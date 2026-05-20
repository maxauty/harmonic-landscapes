// =============================================================================
// GUI
// =============================================================================

(
// ----------------------------------------------------------------
// Layout
// ----------------------------------------------------------------
var cellSize    = 30;
var voiceHeight = 80;
var panelHeight = 400;
var rhythmViewWidth = 401;
var col1 = 12, col2 = 248, col3 = 508, col4 = 808;
var panelW1 = 220, panelW2 = 240, panelW3 = 280, panelW4 = 220;
var winWidth, winHeight;

var window, panel;
var selectedAgentID = -1;

// helpers
var sep, sectionLabel, monitor, makeSlider, makeButton, makeCheckbox;
var buildAgentSlider, buildWeightSlider, buildSimSlider;

// layout state
var colPY = Dictionary.new;

// refresh tracking
var weightSliders     = Dictionary.new;  // popup drive weights
var agentCharSliders  = Dictionary.new;  // main-panel per-agent sliders
var drivePopups       = Dictionary.new;

// top-level UI refs
var nAgentsLbl, nAgentsSl, octaveLbl, octaveSl, stepIntLbl, stepIntSl;
var modeLbl, modeMenu, modeLock;
var homeTriadLbl, midiMonitor, chordMonitor, tonicMonitor;
var noteNames, tonicMenu, tonicLock;
var gateMonitor;

// layer specifications
var layerMeta;
var layerSpecs;

~midiHistory = Dictionary.new;
~voiceView = nil;

// ----------------------------------------------------------------
// Primitive helpers
// ----------------------------------------------------------------
sep = { |parent, x, y, w|
	var line = UserView(parent, Rect(x, y, w, 1));
	line.drawFunc = { Pen.color = Color.grey(0.3); Pen.fillRect(Rect(0, 0, w, 1)) };
};

sectionLabel = { |parent, x, y, w, str|
	var lbl = StaticText(parent, Rect(x, y, w, 16));
	lbl.string      = str.toUpper;
	lbl.font        = Font.monospace(9, true);
	lbl.stringColor = Color.grey(0.5);
};

monitor = { |parent, x, y, w, str|
	var lbl = StaticText(parent, Rect(x, y, w, 16));
	lbl.string      = str;
	lbl.font        = Font.monospace(10);
	lbl.stringColor = Color.grey(0.85);
	lbl
};

makeSlider = { |parent, x, y, w, labelStr, initVal, lo, hi, action, integer|
	var lbl, sl;
	w       = w       ? 176;
	initVal = initVal ? 0.0;
	lo      = lo      ? 0.0;
	hi      = hi      ? 1.0;
	integer = integer ? false;
	lbl = StaticText(parent, Rect(x, y, w, 14));
	sl  = Slider(parent, Rect(x, y + 14, w, 14));
	lbl.string      = "% : %".format(labelStr, initVal.round(if(integer) { 1 } { 0.01 }));
	lbl.font        = Font.monospace(9);
	lbl.stringColor = Color.grey(0.75);
	sl.value        = ((initVal - lo) / (hi - lo)).clip(0, 1);
	sl.background   = Color.grey(0.15);
	sl.action = { |s|
		var val = (lo + (s.value * (hi - lo))).round(if(integer) { 1 } { 0.001 });
		if(integer) { sl.value = (val - lo) / (hi - lo) };
		lbl.string = "% : %".format(labelStr, val.round(if(integer) { 1 } { 0.01 }));
		action.(val);
	};
	[lbl, sl]
};

makeButton = { |parent, x, y, w, h, str, action|
	var btn = Button(parent, Rect(x, y, w, h));
	btn.states = [[str, Color.grey(0.9), Color.grey(0.2)]];
	btn.font   = Font.monospace(10, true);
	btn.action = action;
	btn
};

makeCheckbox = { |parent, x, y, str, initVal, action|
	var cb;
	initVal = initVal ? false;
	cb = CheckBox(parent, Rect(x, y, 160, 18), str);
	cb.font   = Font.monospace(9);
	cb.value  = initVal;
	cb.action = { |c| action.(c.value) };
	cb
};

// target-aware slider builders
buildAgentSlider = { |parent, x, y, w, key, label, lo, hi, integer|
	var sourceAgent = if(~simulation[\agents].size > 0) {
		if(selectedAgentID == -1) {
			~simulation[\agents].first
		} {
			~agentByID.(selectedAgentID) ?? { ~simulation[\agents].first }
		}
	} { nil };
	var initVal = if(sourceAgent.notNil) {
		sourceAgent[key] ? ((lo + hi) / 2)
	} { (lo + hi) / 2 };
	makeSlider.(parent, x, y, w, label, initVal, lo, hi, { |v|
		if(selectedAgentID == -1) {
			~simulation[\agents].do { |a| a[key] = v }
		} {
			var a = ~agentByID.(selectedAgentID);
			if(a.notNil) { a[key] = v }
		}
	}, integer)
};

buildWeightSlider = { |parent, x, y, w, key, label, lo, hi, integer|
    var schemaDefault = ~presetSchema[\agentWeights][key] !? { |s| s[\default] } ? 0.3;
    var sourceAgent = if(~simulation[\agents].size > 0) {
        if(selectedAgentID == -1) {
            ~simulation[\agents].first
        } {
            ~agentByID.(selectedAgentID) ?? { ~simulation[\agents].first }
        }
    } { nil };
    var initVal = if(sourceAgent.notNil) {
        sourceAgent[\weights][key] ? schemaDefault
    } { schemaDefault };
    makeSlider.(parent, x, y, w, label, initVal, lo, hi, { |v|
        if(selectedAgentID == -1) {
            ~simulation[\agents].do { |a| a[\weights][key] = v }
        } {
            var a = ~agentByID.(selectedAgentID);
            if(a.notNil) { a[\weights][key] = v }
        }
    }, integer)
};

buildSimSlider = { |parent, x, y, w, key, label, lo, hi, integer|
	var initVal = ~simulation[key] ? ((lo + hi) / 2);
	makeSlider.(parent, x, y, w, label, initVal, lo, hi, { |v|
		~simulation[key] = v
	}, integer)
};

// ----------------------------------------------------------------
// Layer specifications — GUI metadata only.
// Drive ordering and display grouping live here; labels come from
// ~driveRegistry; ranges come from ~presetSchema[\agentWeights].
// ----------------------------------------------------------------
{
    var layerMeta = [
        (
            key:           \motion,
            label:         "Motion",
            color:         Color(0.45, 0.7, 1.0),
            baselineKey:   nil,
            baselineLabel: nil,
            temperatureKey:\tempMotion,
            driveKeys: [\momentum, \stigmergy, \sparsity, \stepCost, \fatigue],
        ),
        (
            key:           \harmonic,
            label:         "Harmonic",
            color:         Color(0.4, 0.95, 0.5),
            baselineKey:   \harmonicBlend,
            baselineLabel: "Baseline",
            temperatureKey:\tempHarmonic,
            driveKeys: [\voiceLeading, \tonnetzContinuity, \chordTone,
                        \harmonicBias, \homeStrength, \entrainmentStrength],
        ),
        (
            key:           \gesture,
            label:         "Gesture",
            color:         Color(1.0, 0.55, 0.5),
            baselineKey:   \gestureThreshold,
            baselineLabel: "Threshold",
            temperatureKey:\tempGesture,
            driveKeys: [\imitation],
        ),
        (
            key:           \deliberative,
            label:         "Deliberative",
            color:         Color(1.0, 0.88, 0.4),
            baselineKey:   \deliberativeBlend,
            baselineLabel: "Baseline",
            temperatureKey:\tempDeliberative,
            driveKeys: [\plrContinuity, \harmonicResponse, \targetTriad,
                        \tonicPull, \modeCoherence],
        ),
    ];

    layerSpecs = layerMeta.collect { |meta|
        var spec = meta.copy;
        spec[\drives] = meta[\driveKeys].collect { |key|
            var entry  = ~driveRegistry.detect { |d| d[\name] == key };
            var schema = ~presetSchema[\agentWeights][key];
            var label, range;

            // Fail loudly if the registry or schema is missing a key the
            // GUI expects — better than rendering a silently-broken slider.
            if(entry.isNil) {
                Error("layerSpecs: no registry entry for drive %".format(key)).throw
            };
            if(schema.isNil) {
                Error("layerSpecs: no presetSchema entry for drive %".format(key)).throw
            };

            label = entry[\label] ? key.asString;
            range = schema[\range];
            [key, label, range[0], range[1]]
        };
        spec.removeKey(\driveKeys);
        spec
    };
}.value;

// ----------------------------------------------------------------
// Window + grid view — top left
// ----------------------------------------------------------------
winWidth  = (~simulation.grid.width * (cellSize / 1.312)) + 100;
winHeight = (~simulation.grid.height * cellSize * 0.866) + (cellSize * 0.433);

// Total window width: Tonnetz + rhythm panel, or the panel's minimum, whichever is wider
window = Window("Harmonic Landscapes",
	Rect(100, 50,
		(winWidth + rhythmViewWidth).max(1050),
		winHeight + voiceHeight + panelHeight)
).front;

~view = UserView(window, Rect(0, 0, winWidth, winHeight));
~view.background = Color.grey(0.12);
~view.animate    = false;
~view.drawFunc   = {
	var grid     = ~simulation.grid;
	var agents   = ~simulation[\agents];
	var occupied = agents.collect(_[\pos]).select(_.notNil);

	grid.width.do { |x|
		grid.height.do { |y|
			var pc         = grid.midiAt(x, y, 4) % 12;
			var isOccupied = occupied.any { |p| p.x == x and: { p.y == y } };
			var brightness = if(isOccupied) { 0.4 } { 0.6 };
			var center = grid.screenPoint(x, y, cellSize)
				+ Point(cellSize * 0.5, cellSize * 0.433);
			Pen.fillColor = Color.hsv(pc / 12, 0.6, brightness);
			~drawHex.(center, cellSize / 2);
			Pen.fill;
		};
	};

	agents.do { |agent|
		agent[\trail].do { |pos, i|
			if(pos.notNil) {
				var center    = grid.screenPoint(pos.x, pos.y, cellSize)
					+ Point(cellSize * 0.5, cellSize * 0.5);
				var trailSize = cellSize * 0.15;
				var alpha     = ((i + 1) / agent[\trail].size) * 0.6;
				Pen.fillColor = agent[\color].copy.alpha_(alpha);
				Pen.fillOval(Rect(
					center.x - (trailSize * 0.5),
					center.y - (trailSize * 0.5),
					trailSize, trailSize));
			};
		};
	};

	agents.do { |agent|
		if(agent[\pos].notNil) {
			var center = grid.screenPoint(agent[\pos].x, agent[\pos].y, cellSize)
				+ Point(cellSize * 0.5, cellSize * 0.5);
			Pen.fillColor = agent[\color];
			Pen.fillOval(Rect(
				center.x - (cellSize * 0.25),
				center.y - (cellSize * 0.25),
				cellSize * 0.5, cellSize * 0.5));
		};
	};

	agents.do { |agent|
		if(agent[\pos].notNil) {
			var center     = grid.screenPoint(agent[\pos].x, agent[\pos].y, cellSize)
				+ Point(cellSize * 0.5, cellSize * 0.5);
			var tension    = (agent[\tensionScore] ? 0.0);
			var activation = agent[\activation] ? 0.5;
			var effective  = activation + (tension * (1.0 - activation));
			Pen.font  = Font.monospace(9, true);
			// Brightness encodes action probability — matches the gate in collectDecisions
			Pen.color = Color.white.alpha_(0.3 + (effective * 0.5));
			Pen.stringAtPoint(effective.round(0.01).asString,
				Point(center.x - (cellSize * 0.25), center.y - (cellSize * 0.55)));
			Pen.font  = Font.monospace(11);
			Pen.color = Color.white.alpha_(0.7);
			Pen.stringAtPoint(agent[\label].asString,
				Point(center.x - 2.9, center.y - 4.5));
		};
	};
};

~intervalController = SimpleController(~grid).put(\intervals, {
    if(~view.notNil) { ~view.refresh };
});

// ----------------------------------------------------------------
// Voice view — central
// ----------------------------------------------------------------
~voiceView = UserView(window, Rect(0, winHeight, winWidth.max(1050), voiceHeight));
~voiceView.background = Color.grey(0.12);
~voiceView.drawFunc = {
	var agents   = ~simulation[\agents];
	var nAgents  = agents.size.max(1);
	var stripH   = voiceHeight / nAgents;

	agents.do { |agent, i|
		var history = ~midiHistory[agent[\id]] ? [];
		var lo      = agent[\voiceRangeLo] ? 48;
		var hi      = agent[\voiceRangeHi] ? 72;
		var range   = (hi - lo).max(1);
		var stripY  = i * stripH;
		var nPts    = history.size;
		var col     = agent[\color] ? Color.white;

		Pen.fillColor = Color.grey(0.12);
		Pen.fillRect(Rect(0, stripY, ~voiceView.bounds.width, stripH));

		Pen.strokeColor = Color.grey(0.2);
		Pen.line(
			Point(0,                       stripY + (stripH * 0.5)),
			Point(~voiceView.bounds.width, stripY + (stripH * 0.5))
		);
		Pen.stroke;

		Pen.font  = Font.monospace(8);
		Pen.color = col.copy.alpha_(0.4);
		Pen.stringAtPoint(agent[\label].asString, Point(3, stripY + 2));

		if(nPts >= 2) {
			var stepW = ~voiceView.bounds.width / 32.0;

			(nPts - 1).do { |j|
				var m0       = history[j];
				var m1       = history[j + 1];
				var interval = (m1 - m0).abs;
				var x0 = (j - (nPts - 32).max(0)) * stepW;
				var x1 = x0 + stepW;
				var y0 = stripY + stripH - ((m0 - lo / range) * stripH).clip(0, stripH);
				var y1 = stripY + stripH - ((m1 - lo / range) * stripH).clip(0, stripH);
				var smoothness = 1.0 - (interval / 12.0).clip(0, 1);
				var lineCol    = Color.hsv(
					col.asHSV[0],
					smoothness * col.asHSV[1],
					0.4 + (smoothness * 0.5)
				);

				Pen.strokeColor = lineCol;
				Pen.width       = 1.5;
				Pen.line(Point(x0, y0), Point(x1, y1));
				Pen.stroke;

				Pen.fillColor = lineCol;
				Pen.fillOval(Rect(x1 - 2, y1 - 2, 4, 4));
			}
		}
	}
};

// ----------------------------------------------------------------
// Rhythm view — upper right
// ----------------------------------------------------------------
~rhythmView = UserView(window,
	Rect(winWidth, 0, rhythmViewWidth, winHeight)
);
~rhythmView.background = Color.grey(0.12);
~rhythmView.drawFunc = {
	var agents      = ~simulation[\agents];
	var nAgents     = agents.size.max(1);
	var cycleLen    = ~simulation[\globalCycleLen] ? 16;
	var cyclePos    = ~simulation[\cyclePos] ? 0;

	var marginX     = 12;
	var marginTop   = 12;
	var labelHeight = 14;
	var rowGap      = 8;
	var rulerHeight = 18;

	var availW      = ~rhythmView.bounds.width - (marginX * 2);
	var cellW       = availW / cycleLen;
	var availH      = ~rhythmView.bounds.height - marginTop - rulerHeight - 16;
	var rowHeight   = ((availH / nAgents) - rowGap - labelHeight).max(8);

	var y;

	// Header label
	Pen.font  = Font.monospace(10, true);
	Pen.color = Color.grey(0.5);
	Pen.stringAtPoint("RHYTHM", Point(marginX, marginTop));

	// Cycle ruler
	y = marginTop + 16;
	cycleLen.do { |i|
		var cellRect = Rect(marginX + (i * cellW), y, cellW - 1, rulerHeight);
		var isCurrent = (i == cyclePos);
		var isDownbeat = (i == 0);
		Pen.fillColor = if(isCurrent) {
			Color.white.alpha_(0.8)
		} {
			if(isDownbeat) { Color.grey(0.45) } { Color.grey(0.22) }
		};
		Pen.fillRect(cellRect);

		// position number every 4 cells
		if(i % 4 == 0) {
			Pen.font  = Font.monospace(8);
			Pen.color = Color.grey(0.6);
			Pen.stringAtPoint(i.asString,
				Point(marginX + (i * cellW) + 2, y + rulerHeight + 2));
		};
	};
	y = y + rulerHeight + 14;

	// Per-agent rows
	agents.do { |agent, agentIdx|
		var pattern   = agent[\rhythm][\pattern] ? Array.fill(cycleLen, 0);
		var col       = agent[\color] ? Color.white;
		var isSelected = (selectedAgentID == agent[\id]);
		var rowY      = y + (agentIdx * (rowHeight + rowGap + labelHeight));

		// Agent label
		Pen.font  = Font.monospace(9);
		Pen.color = if(isSelected) { Color.white } { col.copy.alpha_(0.7) };
		Pen.stringAtPoint(
			"% [%/%]".format(
				agent[\label],
				agent[\rhythm][\pulses] ? "?",
				agent[\rhythm][\cycleLen] ? "?"
			),
			Point(marginX, rowY)
		);

		// Pattern cells
		cycleLen.do { |i|
			var cellY = rowY + labelHeight;
			var cellRect = Rect(marginX + (i * cellW), cellY, cellW - 1, rowHeight);
			var fires = (pattern.wrapAt(i) == 1);
			var isCurrent = (i == cyclePos);

			if(fires) {
				var alpha = if(isCurrent) { 1.0 } { 0.7 };
				Pen.fillColor = col.copy.alpha_(alpha);
			} {
				Pen.fillColor = Color.grey(0.15);
			};
			Pen.fillRect(cellRect);
		};

		if(agent[\rhythm][\phaseFloat].notNil) {
			var phaseFloat = agent[\rhythm][\phaseFloat];
			var phaseX = marginX + (phaseFloat * cellW);
			var rowYTop = rowY + labelHeight;
			var rowYBot = rowYTop + rowHeight;
			Pen.strokeColor = col.copy.alpha_(0.5);
			Pen.width = 2;
			Pen.line(Point(phaseX, rowYTop), Point(phaseX, rowYBot));
			Pen.stroke;
		};

		// Selection highlight — outline the row
		if(isSelected) {
			Pen.strokeColor = Color.white.alpha_(0.4);
			Pen.width = 1;
			Pen.strokeRect(Rect(
				marginX - 2,
				rowY + labelHeight - 1,
				availW + 2,
				rowHeight + 2
			));
		};
	};

	// Vertical playhead through all rows
	if(cyclePos < cycleLen) {
		var playX = marginX + (cyclePos * cellW) + (cellW / 2);
		Pen.strokeColor = Color.white.alpha_(0.4);
		Pen.width = 1;
		Pen.line(
			Point(playX, marginTop + 16),
			Point(playX, ~rhythmView.bounds.height - 8)
		);
		Pen.stroke;
	};
};

// ----------------------------------------------------------------
// Panel
// ----------------------------------------------------------------
panel = UserView(window, Rect(0, winHeight + voiceHeight, winWidth.max(1050), panelHeight));
panel.background = Color.grey(0.12);
panel.drawFunc = {
	[col2 - 8, col3 - 8, col4 - 8].do { |x|
		Pen.color = Color.grey(0.25);
		Pen.fillRect(Rect(x, 8, 1, panelHeight - 16));
	};
};

colPY[col1] = 8; colPY[col2] = 8; colPY[col3] = 8; colPY[col4] = 8;

// ================================================================
// Drive popup builder
// ================================================================
~makeDrivePopup = { |spec|
	var key = spec[\key];
	var existing = drivePopups[key];
	var w, y, winH;

	if(existing.notNil and: { existing.isClosed.not }) {
		existing.front;
	} {
		winH = 120 + (spec[\drives].size * 34);
		if(spec[\baselineKey].notNil) { winH = winH + 34 };

		w = Window("% drives".format(spec[\label]),
			Rect(500, 200, 280, winH)
		);
		w.background = Color.grey(0.14);

		y = 12;

		sectionLabel.(w, 12, y, 256, "Layer controls");
		y = y + 16;

		makeSlider.(w, 12, y, 256, "Temperature",
			~simulation[spec[\temperatureKey]] ? 1.0,
			0.1, 3.0,
			{ |v| ~simulation[spec[\temperatureKey]] = v },
			false
		);
		y = y + 34;

		if(spec[\baselineKey].notNil) {
			makeSlider.(w, 12, y, 256, spec[\baselineLabel],
				~simulation[spec[\baselineKey]] ? 0.4,
				0.0, 1.0,
				{ |v| ~simulation[spec[\baselineKey]] = v },
				false
			);
			y = y + 34;
		};

		sep.(w, 12, y, 256);
		y = y + 10;

		sectionLabel.(w, 12, y, 256,
			if(selectedAgentID == -1) { "Drive weights (all agents)" }
			{ "Drive weights (agent %)".format(selectedAgentID) }
		);
		y = y + 16;

		spec[\drives].do { |d|
			var dkey = d[0], dlabel = d[1], dlo = d[2], dhi = d[3];
			var pair = buildWeightSlider.(w, 12, y, 256, dkey, dlabel, dlo, dhi, false);
			weightSliders[dkey] = pair;
			y = y + 32;
		};

		w.onClose = {
			drivePopups[key] = nil;
			spec[\drives].do { |d| weightSliders[d[0]] = nil }
		};
		w.front;
		drivePopups[key] = w;
	}
};

~makeSettingsPopup = {
	var existing = ~settingsPopup;
	var w, y = 12;

	if(existing.notNil and: { existing.isClosed.not }) {
		existing.front;
	} {
		w = Window("System Settings", Rect(200, 200, 320, 320));
		w.background = Color.grey(0.14);

		// Output section
		sectionLabel.(w, 12, y, 296, "Output");
		y = y + 18;

		makeCheckbox.(w, 12, y, "Use internal audio synth",
			~useAudioFallback ? false,
			{ |v| ~useAudioFallback = v });
		y = y + 28;

		sep.(w, 12, y, 296);
		y = y + 8;

		// Clock section
		sectionLabel.(w, 12, y, 296, "Clock");
		y = y + 18;

		makeButton.(w, 12, y, 296, 22,
			switch(~simulation[\timeSourceKind],
				\internal, { "Internal → Link" },
				\link,     { "Link → Internal" }
			),
			{ |btn|
				var wasRunning = (~simulation[\timeSource].notNil
					and: { ~simulation[\timeSource][\running] == true });

				if(wasRunning) {
					~simulation[\stop].(~simulation);
				};

				~simulation[\timeSourceKind] = switch(~simulation[\timeSourceKind],
					\internal, \link,
					\link,     \internal,
					\internal
				);

				~simulation[\timeSource] = nil;

				btn.states = [[
					switch(~simulation[\timeSourceKind],
						\internal, { "Internal → Link" },
						\link,     { "Link → Internal" }
					),
					Color.grey(0.9), Color.grey(0.2)
				]];
				btn.refresh;

				if(wasRunning) {
					~simulation[\start].(~simulation);
				};
			}
		);
		y = y + 30;

		makeSlider.(w, 12, y, 296, "Link latency (s)",
			0.1, 0.001, 0.2,
			{ |v|
				if(~simulation[\timeSource].notNil
					and: { ~simulation[\timeSourceKind] == \link })
				{
					~simulation[\timeSource][\clock].latency = v;
				};
				~simulation[\linkLatency] = v;
			}, false);
		y = y + 34;

		sep.(w, 12, y, 296);
		y = y + 8;

		// Timing section
		sectionLabel.(w, 12, y, 296, "Timing");
		y = y + 18;

		makeSlider.(w, 12, y, 296, "Beats/tick",
			~simulation[\tickSize] ? 0.25, 0.05, 4.0,
			{ |v|
				~simulation[\tickSize] = v;
				if(~simulation[\timeSource].notNil) {
					~simulation[\timeSource][\tickSize] = v;
				};
			}, false);
		y = y + 34;

		w.front;
		~settingsPopup = w;
	}
};

~makeSimSettingsPopup = { |title, settings|
	var existing, w, y;

	if(~simSettingsPopups.isNil) { ~simSettingsPopups = Dictionary.new };

	existing = ~simSettingsPopups[title];

	if(existing.notNil and: { existing.isClosed.not }) {
		existing.front;
	} {
		w = Window(title, Rect(500, 200, 280, 60 + (settings.size * 34)));
		w.background = Color.grey(0.14);

		y = 12;
		sectionLabel.(w, 12, y, 256, title);
		y = y + 18;

		settings.do { |spec|
			var key = spec[0], label = spec[1], lo = spec[2], hi = spec[3], isInt = spec[4];
			buildSimSlider.(w, 12, y, 256, key, label, lo, hi, isInt);
			y = y + 32;
		};

		w.onClose = { ~simSettingsPopups[title] = nil };
		w.front;
		~simSettingsPopups[title] = w;
	}
};

~makeRhythmPopup = {
	var existing = ~rhythmPopup;
	var w, y;
	var pulsesSlider, cycleSlider, phaseSlider, couplingSlider;
	var globalCycleSlider;
	var update;

	if(existing.notNil and: { existing.isClosed.not }) {
		existing.front;
	} {
		w = Window("Rhythm controls", Rect(450, 200, 320, 420));
		w.background = Color.grey(0.14);

		y = 12;

		// ----------------------------------------------------------------
		// Per-agent / All section
		// ----------------------------------------------------------------
		sectionLabel.(w, 12, y, 296,
			if(selectedAgentID == -1) { "All agents (broadcast)" }
			{ "Agent %".format(selectedAgentID) });
		y = y + 18;

		pulsesSlider = makeSlider.(w, 12, y, 296, "Pulses", 4, 1, 16,
			{ |v|
				var act = { |a|
					a[\rhythm][\pulses] = v.asInteger;
					~regeneratePattern.(a[\rhythm]);
				};
				if(selectedAgentID == -1) {
					~simulation[\agents].do(act);
				} {
					var a = ~agentByID.(selectedAgentID);
					if(a.notNil) { act.(a) };
				};
				if(~rhythmView.notNil) { ~rhythmView.refresh };
			}, true);
		y = y + 32;

		cycleSlider = makeSlider.(w, 12, y, 296, "Cycle length (per-agent)", 16, 4, 32,
			{ |v|
				var act = { |a|
					a[\rhythm][\cycleLen] = v.asInteger;
					~regeneratePattern.(a[\rhythm]);
				};
				if(selectedAgentID == -1) {
					~simulation[\agents].do(act);
				} {
					var a = ~agentByID.(selectedAgentID);
					if(a.notNil) { act.(a) };
				};
				if(~rhythmView.notNil) { ~rhythmView.refresh };
			}, true);
		y = y + 32;

		phaseSlider = makeSlider.(w, 12, y, 296, "Phase", 0, 0, 31,
			{ |v|
				var act = { |a|
					var cycleLen = a[\rhythm][\cycleLen] ? 16;
					var wrapped  = v.asInteger.mod(cycleLen);
					a[\rhythm][\phase]      = wrapped;
					a[\rhythm][\phaseFloat] = wrapped;
					~regeneratePattern.(a[\rhythm]);
				};
				if(selectedAgentID == -1) {
					~simulation[\agents].do(act);
				} {
					var a = ~agentByID.(selectedAgentID);
					if(a.notNil) { act.(a) };
				};
				if(~rhythmView.notNil) { ~rhythmView.refresh };
			}, true);
		y = y + 32;

		couplingSlider = makeSlider.(w, 12, y, 296, "Phase coupling", 0.05, 0.0, 0.3,
			{ |v|
				if(selectedAgentID == -1) {
					~simulation[\agents].do { |a| a[\weights][\phaseCoupling] = v }
				} {
					var a = ~agentByID.(selectedAgentID);
					if(a.notNil) { a[\weights][\phaseCoupling] = v };
				};
			}, false);
		y = y + 36;

		sep.(w, 12, y, 296);
		y = y + 8;

		// ----------------------------------------------------------------
		// Sim-level section
		// ----------------------------------------------------------------
		sectionLabel.(w, 12, y, 296, "Simulation rhythm");
		y = y + 18;

		globalCycleSlider = makeSlider.(w, 12, y, 296, "Global cycle length",
			~simulation[\globalCycleLen] ? 16, 4, 64,
			{ |v|
				~simulation[\globalCycleLen] = v.asInteger;
				if(~rhythmView.notNil) { ~rhythmView.refresh };
			}, true);
		y = y + 36;

		sep.(w, 12, y, 296);
		y = y + 8;

		// ----------------------------------------------------------------
		// Quick actions
		// ----------------------------------------------------------------
		sectionLabel.(w, 12, y, 296, "Quick actions");
		y = y + 18;

		makeButton.(w, 12, y, 140, 22, "Spread phases",
			{
				var agents = ~simulation[\agents];
				var cycleLen = ~simulation[\globalCycleLen] ? 16;
				var spacing = cycleLen / agents.size.max(1);
				agents.do { |a, i|
					var p = (i * spacing).round.asInteger.mod(cycleLen);
					a[\rhythm][\phase]      = p;
					a[\rhythm][\phaseFloat] = p;
					~regeneratePattern.(a[\rhythm]);
				};
				if(~rhythmView.notNil) { ~rhythmView.refresh };
			}
		);
		makeButton.(w, 156, y, 140, 22, "Align to 0",
			{
				~simulation[\agents].do { |a|
					a[\rhythm][\phase]      = 0;
					a[\rhythm][\phaseFloat] = 0;
					~regeneratePattern.(a[\rhythm]);
				};
				if(~rhythmView.notNil) { ~rhythmView.refresh };
			}
		);
		y = y + 28;

		makeButton.(w, 12, y, 140, 22, "Anchor selected",
			{
				if(selectedAgentID != -1) {
					var a = ~agentByID.(selectedAgentID);
					if(a.notNil) {
						a[\weights][\phaseCoupling] = 0.0;
						"Agent % anchored (coupling 0).".format(selectedAgentID).postln;
						if(~makeRhythmPopupRefresh.notNil) { ~makeRhythmPopupRefresh.() };
					}
				} {
					"Anchor: select a single agent first.".postln;
				}
			}
		);
		makeButton.(w, 156, y, 140, 22, "Reset coupling",
			{
				~simulation[\agents].do { |a|
					a[\weights][\phaseCoupling] = 0.05;
				};
				if(~makeRhythmPopupRefresh.notNil) { ~makeRhythmPopupRefresh.() };
			}
		);
		y = y + 32;

		// ----------------------------------------------------------------
		// Refresh logic — update slider values from the current selected agent
		// ----------------------------------------------------------------
		update = {
			var sourceAgent = if(~simulation[\agents].size > 0) {
				if(selectedAgentID == -1) {
					~simulation[\agents].first
				} {
					~agentByID.(selectedAgentID) ?? { ~simulation[\agents].first }
				}
			} { nil };

			if(sourceAgent.notNil) {
				var rhythm = sourceAgent[\rhythm] ? (pulses: 4, cycleLen: 16, phase: 0);

				// Update pulses slider
				pulsesSlider[1].value  = ((rhythm[\pulses] - 1) / 15).clip(0, 1);
				pulsesSlider[0].string = "Pulses : %".format(rhythm[\pulses]);

				// Update cycle length slider
				cycleSlider[1].value  = ((rhythm[\cycleLen] - 4) / 28).clip(0, 1);
				cycleSlider[0].string = "Cycle length (per-agent) : %".format(rhythm[\cycleLen]);

				// Update phase slider
				phaseSlider[1].value  = (rhythm[\phase] / 31).clip(0, 1);
				phaseSlider[0].string = "Phase : %".format(rhythm[\phase]);

				// Update coupling slider
				{
					var coupling = sourceAgent[\weights][\phaseCoupling] ? 0.05;
					couplingSlider[1].value  = (coupling / 0.3).clip(0, 1);
					couplingSlider[0].string = "Phase coupling : %".format(coupling.round(0.001));
				}.value;

				// Update global cycle length slider (sim-level, not agent-dependent)
				globalCycleSlider[1].value  =
					(((~simulation[\globalCycleLen] ? 16) - 4) / 60).clip(0, 1);
				globalCycleSlider[0].string =
					"Global cycle length : %".format(~simulation[\globalCycleLen] ? 16);
			};
		};

		// Run once
		update.();

		// Expose externally so agent-button switches refresh
		~makeRhythmPopupRefresh = update;

		w.onClose = {
			~rhythmPopup = nil;
			~makeRhythmPopupRefresh = nil;
		};
		w.front;
		~rhythmPopup = w;
	}
};

~makePresetPopup = {
    var existing = ~presetPopup;
    var w, y;
    var scopeButtons, currentScope;
    var nameField, listView, availablePresets;
    var refreshList;

    if(existing.notNil and: { existing.isClosed.not }) {
        existing.front;
    } {
        currentScope = \global;
        w = Window("Presets", Rect(300, 150, 320, 370));
        w.background = Color.grey(0.14);
        y = 12;

        // --- Scope selector ---
        sectionLabel.(w, 12, y, 296, "Scope");
        y = y + 18;

        scopeButtons = [\global, \agent, \scene].collect { |scope, i|
            var btn = Button(w, Rect(12 + (i * 100), y, 92, 22));
			var label = scope.asString;
			label = label[0].toUpper.asString ++ label[1..]; // "Global", "Agent", "Scene"
            btn.states = [
                [label, Color.grey(0.65), Color.grey(0.2) ],
                [label, Color.white,      Color.grey(0.38)]
            ];
            btn.font  = Font.monospace(9, true);
            btn.value = if(i == 0) { 1 } { 0 };
            btn.action = { |b|
                currentScope = scope;
                scopeButtons.do { |ob, j| ob.value = if(j == i) { 1 } { 0 } };
                refreshList.();
            };
            btn
        };
        y = y + 30;

        sep.(w, 12, y, 296);
        y = y + 10;

        // --- Save name and button ---
        sectionLabel.(w, 12, y, 296, "Save");
        y = y + 18;

        nameField = TextField(w, Rect(12, y, 200, 22));
        nameField.font        = Font.monospace(10);
        nameField.string      = "untitled";
        nameField.background  = Color.grey(0.2);
        nameField.stringColor = Color.grey(0.9);

        makeButton.(w, 218, y, 90, 22, "SAVE", {
            var name = nameField.string.stripWhiteSpace;
            if(name.size > 0) {
                var snap = switch(currentScope,
                    \global, { ~captureGlobalPreset.() },
                    \agent, {
                        var agent = if(selectedAgentID == -1) {
                            ~simulation[\agents].first
                        } { ~agentByID.(selectedAgentID) };
                        agent !? { ~captureAgentPreset.(agent) }
                    },
                    \scene, { ~captureScenePreset.() }
                );
                if(snap.notNil) {
                    ~savePreset.(snap, name);
                    refreshList.();
                } { "No agent to capture — spawn first.".warn };
            } { "Enter a name before saving.".warn };
        });
        y = y + 30;

        sep.(w, 12, y, 296);
        y = y + 10;

        // Available presets list
        sectionLabel.(w, 12, y, 296, "Available");
        y = y + 18;

        listView = ListView(w, Rect(12, y, 296, 120));
        listView.font        = Font.monospace(10);
        listView.background  = Color.grey(0.18);
        listView.stringColor = Color.grey(0.85);
        y = y + 128;

        // Load / Delete
        makeButton.(w, 12, y, 144, 22, "LOAD SELECTED", {
            var idx = listView.value;
            if(idx.notNil
                and: { availablePresets.notNil }
                and: { idx < availablePresets.size }
            ) {
                var name = availablePresets[idx];
                var snap = ~loadPreset.(currentScope, name);
                if(snap.notNil) {
                    switch(currentScope,
                        \global, { ~applyGlobalPreset.(snap) },
                        \agent, {
                            var agent = if(selectedAgentID == -1) {
                                ~simulation[\agents].first
                            } { ~agentByID.(selectedAgentID) };
                            if(agent.notNil) {
                                ~applyAgentPreset.(agent, snap);
                                { ~refreshWeightSliders.() }.defer;
                            }
                        },
                        \scene, { ~applyScenePreset.(snap) }
                    )
                }
            } { "Select a preset from the list first.".warn }
        });

        makeButton.(w, 164, y, 144, 22, "DELETE SELECTED", {
            var idx = listView.value;
            if(idx.notNil
                and: { availablePresets.notNil }
                and: { idx < availablePresets.size }
            ) {
                var name = availablePresets[idx];
                var path = ~presetPath.(currentScope, name);
                File.delete(path);
                "Deleted: %".format(path).postln;
                refreshList.();
            } { "Select a preset from the list first.".warn }
        });
        y = y + 28;

        // Refresh helper
        refreshList = {
            availablePresets = ~listPresets.(currentScope);
            { listView.items = availablePresets }.defer;
        };

        refreshList.();

        w.onClose = { ~presetPopup = nil };
        w.front;
        ~presetPopup = w;
    }
};

// ================================================================
// COLUMN 1 — Setup + Transport + Options
// ================================================================
makeButton.(panel, col1, colPY[col1], panelW1, 22, "⚙ Settings",
	{ ~makeSettingsPopup.() });
colPY[col1] = colPY[col1] + 28;

sectionLabel.(panel, col1, colPY[col1], panelW1, "Setup");
colPY[col1] = colPY[col1] + 18;

#nAgentsLbl, nAgentsSl = makeSlider.(panel, col1, colPY[col1], panelW1,
	"Agents", 4, 1, 8, { |v| nAgentsLbl.string = "Agents : " ++ v.asInteger }, true);
colPY[col1] = colPY[col1] + 32;

#octaveLbl, octaveSl = makeSlider.(panel, col1, colPY[col1], panelW1,
	"Register centre", 5, 1, 8, { |v|
		var centre = v.asInteger * 12;
		var half   = 12;
		if(selectedAgentID == -1) {
			~simulation[\agents].do { |a|
				a[\voiceRangeLo] = centre - half;
				a[\voiceRangeHi] = centre + half;
			}
		} {
			var a = ~agentByID.(selectedAgentID);
			if(a.notNil) {
				a[\voiceRangeLo] = centre - half;
				a[\voiceRangeHi] = centre + half;
			}
		}
	}, true);
colPY[col1] = colPY[col1] + 32;

#stepIntLbl, stepIntSl = makeSlider.(panel, col1, colPY[col1], panelW1,
	"Step interval", 4, 1, 16, { |v|
		if(selectedAgentID == -1) {
			~simulation[\agents].do { |a| a[\stepInterval] = v.asInteger }
		} {
			var a = ~agentByID.(selectedAgentID);
			if(a.notNil) { a[\stepInterval] = v.asInteger }
		}
	}, true);
colPY[col1] = colPY[col1] + 36;

makeButton.(panel, col1, colPY[col1], panelW1, 24, "SPAWN", {
    var n = (nAgentsSl.value * 7 + 1).round.asInteger.clip(1, 8);
    var o = (octaveSl.value  * 7 + 1).round.asInteger.clip(1, 8);
    var s = (stepIntSl.value * 15 + 1).round.asInteger.clip(1, 16);

    ~simulation.spawnAgents(n, o, s);
    selectedAgentID = -1;
    ~midiHistory = Dictionary.new;
    ~refreshAllViews.();
});
colPY[col1] = colPY[col1] + 34;

sectionLabel.(panel, col1, colPY[col1], panelW1, "Transport");
colPY[col1] = colPY[col1] + 18;

makeButton.(panel, col1,       colPY[col1], 66, 22, "START", { ~simulation.start });
makeButton.(panel, col1 + 72,  colPY[col1], 66, 22, "STOP",  { ~simulation[\stop].(~simulation) });
makeButton.(panel, col1 + 144, colPY[col1], 66, 22, "STEP",  { ~simulation.step });
colPY[col1] = colPY[col1] + 28;

~tempoMonitor = monitor.(panel, col1, colPY[col1], panelW1, "Tempo: — bpm");
colPY[col1] = colPY[col1] + 18;

makeSlider.(panel, col1, colPY[col1], panelW1, "Tempo (bpm)",
	(TempoClock.default.tempo * 60), 40, 200,
	{ |v|
		TempoClock.default.tempo = v / 60;
		if(~simulation[\timeSource].notNil) {
			~simulation[\timeSource][\setTempo].(~simulation[\timeSource], v / 60);
		}
}, true);
colPY[col1] = colPY[col1] + 36;

sectionLabel.(panel, col1, colPY[col1], panelW1, "Options");
colPY[col1] = colPY[col1] + 18;

// lighter grey pannel behind checkboxes
StaticText(panel, Rect(col1, colPY[col1], 130, 72))
    .background_(Color.grey(0.9, 0.5)) // Very light grey with 50% transparency
    .alpha_(0.5);

makeCheckbox.(panel, col1 + 2, colPY[col1], "Debug movement",
	~simulation[\debugMovement] ? false,
	{ |v| ~simulation[\debugMovement] = v });
colPY[col1] = colPY[col1] + 18;

makeCheckbox.(panel, col1 + 2, colPY[col1], "Birth enabled",
	~simulation[\birthEnabled] ? true,
	{ |v| ~simulation[\birthEnabled] = v });
colPY[col1] = colPY[col1] + 18;

makeCheckbox.(panel, col1 + 2, colPY[col1], "Death enabled",
	~simulation[\deathEnabled] ? true,
	{ |v| ~simulation[\deathEnabled] = v });
colPY[col1] = colPY[col1] + 18;

makeCheckbox.(panel, col1 + 2, colPY[col1], "Jump on resolve",
	~simulation[\jumpOnResolve] ? true,
	{ |v| ~simulation[\jumpOnResolve] = v });

// ================================================================
// COLUMN 2 — Agent select + Character + Monitors
// ================================================================
sectionLabel.(panel, col2, colPY[col2], panelW2, "Agent select");
colPY[col2] = colPY[col2] + 18;

~agentButtonContainer = CompositeView(panel,
	Rect(col2, colPY[col2], panelW2, 24));
~agentButtonContainer.background = Color.grey(0.12);
~agentButtons = [];
colPY[col2] = colPY[col2] + 30;

~allModeHint = StaticText(panel, Rect(col2, colPY[col2], panelW2, 14));
~allModeHint.font        = Font.monospace(8);
~allModeHint.stringColor = Color.grey(0.5);
~allModeHint.string      = "all mode: edits broadcast to every agent";
colPY[col2] = colPY[col2] + 16;

sectionLabel.(panel, col2, colPY[col2], panelW2, "Character");
colPY[col2] = colPY[col2] + 16;

agentCharSliders[\activation] =
	buildAgentSlider.(panel, col2, colPY[col2], panelW2,
		\activation, "Activation", 0.0, 1.0, false);
colPY[col2] = colPY[col2] + 30;

agentCharSliders[\soundThreshold] =
	buildAgentSlider.(panel, col2, colPY[col2], panelW2,
		\soundThreshold, "Sound threshold", 0.0, 1.0, false);
colPY[col2] = colPY[col2] + 30;

sectionLabel.(panel, col2, colPY[col2], panelW2, "Register");
colPY[col2] = colPY[col2] + 16;

agentCharSliders[\voiceRangeLo] =
	buildAgentSlider.(panel, col2, colPY[col2], panelW2,
		\voiceRangeLo, "Range lo (MIDI)", 0, 127, true);
colPY[col2] = colPY[col2] + 30;

agentCharSliders[\voiceRangeHi] =
	buildAgentSlider.(panel, col2, colPY[col2], panelW2,
		\voiceRangeHi, "Range hi (MIDI)", 0, 127, true);
colPY[col2] = colPY[col2] + 34;

sectionLabel.(panel, col2, colPY[col2], panelW2, "Tonal centre");
colPY[col2] = colPY[col2] + 16;

noteNames  = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];
tonicMenu  = PopUpMenu(panel, Rect(col2, colPY[col2], panelW2 - 50, 20));
tonicLock  = Button(panel, Rect(col2 + panelW2 - 46, colPY[col2], 46, 20));
tonicMenu.font  = Font.monospace(9);
tonicMenu.items = noteNames;
tonicMenu.value = ~simulation[\lockedTonicPC] ? 0;
tonicMenu.action = { |m|
	~simulation[\lockedTonicPC] = m.value;
	if(~simulation[\tonicLocked] == true) {
		~simulation[\harmonicState][\tonicPC] = m.value;
	}
};
tonicLock.states = [
	["free",   Color.grey(0.9), Color.grey(0.25)],
	["locked", Color.white,     Color.grey(0.45)]
];
tonicLock.font   = Font.monospace(8, true);
tonicLock.value  = 0;
tonicLock.action = { |b|
	~simulation[\tonicLocked] = (b.value == 1);
	if(b.value == 1) {
		var tonicInt = ~simulation[\lockedTonicPC];
		~simulation[\harmonicState][\tonicPC] = tonicInt;
		~simulation[\harmonicCentre] = tonicInt;
		// re-anchor each agent's collection and home triad to the locked tonic
		~simulation[\agents].do { |a|
			var intervals = ~modeHomeTriad[a[\modeKey]] ? [0, 4, 7];
			a[\homeTriad] = intervals.collect { |i| (tonicInt + i).mod(12) };
			a[\modeCollection] = (~modeCollections[a[\modeKey]] ? ~modeCollections[\major])
				.collect { |pc| (pc + tonicInt).mod(12) };
		}
	}
};
colPY[col2] = colPY[col2] + 24;

makeButton.(panel, col4, colPY[col4], panelW4, 22, "Presets...",
    { ~makePresetPopup.() });
colPY[col4] = colPY[col4] + 28;

modeMenu = PopUpMenu(panel, Rect(col2, colPY[col2], panelW2 - 50, 20));
modeLock = Button(panel, Rect(col2 + panelW2 - 46, colPY[col2], 46, 20));
modeMenu.font  = Font.monospace(9);
modeMenu.items = ~modeNames.collect(_.asString);
modeMenu.value  = ~modeNames.indexOf((~simulation[\lockedModeKey] ? \major).asString) ? 0;
modeMenu.action = { |m|
	var key      = ~modeNames[m.value].asSymbol;
	var tonicInt = (~simulation[\harmonicState][\tonicPC] ? 0).round.asInteger;
	var intervals = ~modeHomeTriad[key] ? [0, 4, 7];

	var applyTo = { |a|
		a[\modeKey]        = key;
		a[\homeTriad]      = intervals.collect { |i| (tonicInt + i).mod(12) };
		a[\modeCollection] = (~modeCollections[key] ? ~modeCollections[\major])
			.collect { |pc| (pc + tonicInt).mod(12) };
	};

	if(~simulation[\modeLocked] == true) {
		~simulation[\lockedModeKey] = key;
		~simulation[\agents].do(applyTo);
	} {
		if(selectedAgentID == -1) {
			~simulation[\agents].do(applyTo);
		} {
			var a = ~agentByID.(selectedAgentID);
			if(a.notNil) { applyTo.(a) };
		}
	}
};
modeLock.states = [
	["free",   Color.grey(0.9), Color.grey(0.25)],
	["locked", Color.white,     Color.grey(0.45)]
];
modeLock.font  = Font.monospace(8, true);
modeLock.value = 0;
modeLock.action = { |b|
	~simulation[\modeLocked] = (b.value == 1);
	if(b.value == 1) {
		var key       = ~modeNames[modeMenu.value].asSymbol;
		var tonicInt  = (~simulation[\harmonicState][\tonicPC] ? 0).round.asInteger;
		var intervals = ~modeHomeTriad[key] ? [0, 4, 7];
		~simulation[\lockedModeKey] = key;
		~simulation[\agents].do { |a|
			a[\modeKey]        = key;
			a[\homeTriad]      = intervals.collect { |i| (tonicInt + i).mod(12) };
			a[\modeCollection] = (~modeCollections[key] ? ~modeCollections[\major])
				.collect { |pc| (pc + tonicInt).mod(12) };
		}
	}
};
colPY[col2] = colPY[col2] + 30;

buildSimSlider.(panel, col2, colPY[col2], panelW2,
	\modeStrictness, "Mode strictness", 0.0, 1.0, false);
colPY[col2] = colPY[col2] + 30;

homeTriadLbl = monitor.(panel, col2, colPY[col2], panelW2, "Home: [ ]");
colPY[col2] = colPY[col2] + 18;

midiMonitor  = monitor.(panel, col2, colPY[col2], panelW2, "MIDI: —");
colPY[col2]  = colPY[col2] + 18;

chordMonitor = monitor.(panel, col2, colPY[col2], panelW2, "Chord: —");
colPY[col2]  = colPY[col2] + 18;

tonicMonitor = monitor.(panel, col2, colPY[col2], panelW2, "Tonic: —");
colPY[col2]  = colPY[col2] + 18;

modeLbl = monitor.(panel, col2, colPY[col2], panelW2, "Mode: major");
colPY[col2] = colPY[col2] + 16;

// ================================================================
// COLUMN 3 — Gate monitor + Layer controls
// ================================================================
sectionLabel.(panel, col3, colPY[col3], panelW3, "Gate monitor");
colPY[col3] = colPY[col3] + 16;

gateMonitor = UserView(panel, Rect(col3, colPY[col3], panelW3, 80));
gateMonitor.drawFunc = {
	var gates = nil;
	if(selectedAgentID == -1) {
		gates = ~simulation[\lastGates]
	} {
		var a = ~agentByID.(selectedAgentID);
		if(a.notNil) {
			gates = (~simulation[\gatesByAgent] ? Dictionary.new)[a[\label]]
		}
	};
	gates = gates ? (motion: 0, harmonic: 0, gesture: 0, deliberative: 0);

	Pen.fillColor = Color.grey(0.1);
	Pen.fillRect(Rect(0, 0, panelW3, 80));

	layerSpecs.do { |spec, i|
		var val      = (gates[spec[\key]] ? 0).clip(0, 1);
		var barH     = 14;
		var y0       = 6 + (i * 18);
		var labelStr = spec[\label][0..0];

		Pen.font  = Font.monospace(11, true);
		Pen.color = Color.grey(0.85);
		Pen.stringAtPoint(labelStr, Point(6, y0));

		Pen.fillColor = Color.grey(0.2);
		Pen.fillRect(Rect(22, y0 + 2, panelW3 - 72, barH - 4));

		Pen.fillColor = spec[\color].copy.alpha_(0.85);
		Pen.fillRect(Rect(22, y0 + 2, (panelW3 - 72) * val, barH - 4));

		Pen.color = Color.white.alpha_(0.85);
		Pen.font  = Font.monospace(9);
		Pen.stringAtPoint(val.round(0.01).asString, Point(panelW3 - 42, y0));
	};
};
colPY[col3] = colPY[col3] + 88;

sectionLabel.(panel, col3, colPY[col3], panelW3, "Layers");
colPY[col3] = colPY[col3] + 16;

// Per-layer row
layerSpecs.do { |spec|
	var rowLbl = StaticText(panel, Rect(col3, colPY[col3], 130, 16));
	rowLbl.string      = spec[\label];
	rowLbl.font        = Font.monospace(10, true);
	rowLbl.stringColor = spec[\color];

	makeButton.(panel, col3 + 156, colPY[col3] - 1, 124, 20,
		"drives...",
		{ ~makeDrivePopup.(spec) }
	);
	colPY[col3] = colPY[col3] + 18;

	if(spec[\baselineKey].notNil) {
		buildSimSlider.(panel, col3, colPY[col3], panelW3,
			spec[\baselineKey], spec[\baselineLabel], 0.0, 1.0, false);
		colPY[col3] = colPY[col3] + 30;
	} {
		var note = StaticText(panel, Rect(col3, colPY[col3], panelW3, 14));
		note.string      = "(residual, always present)";
		note.font        = Font.monospace(9);
		note.stringColor = Color.grey(0.5);
		colPY[col3] = colPY[col3] + 16;
	};

	sep.(panel, col3, colPY[col3] + 2, panelW3);
	colPY[col3] = colPY[col3] + 8;
};

colPY[col3] = colPY[col3] + 4;

buildSimSlider.(panel, col3, colPY[col3], panelW3,
	\resolveBoundary, "Resolve boundary", 0.0, 1.0, false);
colPY[col3] = colPY[col3] + 32;

// ======================================================================
// COLUMN 4 — Rhythm system Harmonic system + Voicing + Structural + Grid
// ======================================================================

makeButton.(panel, col4, colPY[col4], panelW4, 22, "Rhythm controls...",
	{ ~makeRhythmPopup.() });
colPY[col4] = colPY[col4] + 28;

makeButton.(panel, col4, colPY[col4], panelW4, 22, "Harmonic system...",
	{ ~makeSimSettingsPopup.("Harmonic system", [
		[\modeHysteresis,    "Mode hysteresis",    0.0, 0.5,  false],
		[\tonicUpdateRate,   "Tonic shift size",   0.0, 1.0,  false],
		[\tonicShiftThreshold, "Tonic shift threshold", 0.0, 6.0, false],
		[\interactionRadius, "Interaction radius", 1,   12,   true]
	])
});
colPY[col4] = colPY[col4] + 28;

makeButton.(panel, col4, colPY[col4], panelW4, 22, "Voicing...",
	{ ~makeSimSettingsPopup.("Voicing", [
		[\realiseMelodic, "Melodic weight", 0.0, 1.0, false],
		[\realiseSpacing, "Spacing weight", 0.0, 1.0, false],
		[\realiseCentre,  "Centre weight",  0.0, 1.0, false]
	])
});
colPY[col4] = colPY[col4] + 28;

sectionLabel.(panel, col4, colPY[col4], panelW4, "Structural");
colPY[col4] = colPY[col4] + 16;

buildSimSlider.(panel, col4, colPY[col4], panelW4,
	\structuralClockPeriod, "Clock period (ticks)", 2, 32, true);
colPY[col4] = colPY[col4] + 30;

buildSimSlider.(panel, col4, colPY[col4], panelW4,
	\jumpRadius, "Jump radius", 1, 3, true);
colPY[col4] = colPY[col4] + 34;

sectionLabel.(panel, col4, colPY[col4], panelW4, "Grid");
colPY[col4] = colPY[col4] + 16;

makeSlider.(panel, col4, colPY[col4], panelW4, "i1 (col interval)",
    ~grid.i1, 1, 11, { |v|
        ~grid.setI1(v.asInteger);
        ~recomputeOnGridChange.();
    }, true);
colPY[col4] = colPY[col4] + 30;

makeSlider.(panel, col4, colPY[col4], panelW4, "i2 (row interval)",
    ~grid.i2, 1, 11, { |v|
        ~grid.setI2(v.asInteger);
        ~recomputeOnGridChange.();
    }, true);
colPY[col4] = colPY[col4] + 32;

~gridInfoMonitor = monitor.(panel, col4, colPY[col4], panelW4,
    "Grid: %x%  +x=%st  +y=%st".format(
        ~simulation.grid.width, ~simulation.grid.height,
        ~simulation.grid.i1, ~simulation.grid.i2));

// ================================================================
// Refresh helpers
// ================================================================

// Called whenever the grid's i1 or i2 interval changes.
// Forces an immediate recompute of all geometry-dependent agent state
// (homeTriad, modeCollection, tonicPC, occupiedTriads, harmonicBias)
// so that agents reflect the new pitch-class assignment before the
// next tick fires. Also redraws the Tonnetz and updates the grid
// info monitor.
//
// Defined here rather than in simulation.scd because it references
// GUI views (~view, ~gridInfoMonitor) that don't exist when
// simulation.scd loads.
~recomputeOnGridChange = {
    if(~simulation[\agents].size > 0) {
        ~simulation.updateTonicCentre;
        ~simulation.updateTriadState;
        ~simulation.updateAgentBias;
        ~simulation.updateAgentTension;
    };
    {
        ~view.refresh;
        if(~gridInfoMonitor.notNil) {
            ~gridInfoMonitor.string = "Grid: %x%  +x=%st  +y=%st".format(
                ~simulation.grid.width, ~simulation.grid.height,
                ~simulation.grid.i1, ~simulation.grid.i2
            );
        };
    }.defer;
};

~refreshWeightSliders = {
	if(~simulation[\agents].size > 0) {
		var agent = if(selectedAgentID == -1) {
			~simulation[\agents].first
		} {
			~agentByID.(selectedAgentID) ?? { ~simulation[\agents].first }
		};
		if(agent.notNil) {

			// setup sliders
			{
				var centre, lo, hi;

				if(selectedAgentID == -1) {
					// "All" view: show the requested centre (what user asked for at spawn)
					// and the envelope of all agents' voice ranges
					centre = ~simulation[\registerCentre] ? 5;
					lo     = ~simulation[\agents].collect(_[\voiceRangeLo]).minItem ? 48;
					hi     = ~simulation[\agents].collect(_[\voiceRangeHi]).maxItem ? 72;
				} {
					// Individual agent view: show that agent's actual values
					centre = ((agent[\voiceRangeLo] ? 48) + (agent[\voiceRangeHi] ? 72)) / 2 / 12;
					lo     = agent[\voiceRangeLo] ? 48;
					hi     = agent[\voiceRangeHi] ? 72;
				};

				octaveSl.value   = (centre - 1) / 7;
				octaveLbl.string = "Register centre : " ++ centre.round.asInteger;
				stepIntSl.value   = (agent[\stepInterval] - 1) / 15;
				stepIntLbl.string = "Step interval : " ++ agent[\stepInterval];

				// Update voiceRangeLo/Hi sliders too
			}.value;

			// per-agent character sliders
			agentCharSliders.keysValuesDo { |key, pair|
				var val, hi, lo;

				// For voice range sliders, use the envelope when "All" is selected
				val = if(selectedAgentID == -1 and: { [\voiceRangeLo, \voiceRangeHi].includes(key) }) {
					if(key == \voiceRangeLo) {
						~simulation[\agents].collect(_[\voiceRangeLo]).minItem
					} {
						~simulation[\agents].collect(_[\voiceRangeHi]).maxItem
					}
				} {
					agent[key]
				};

				if(val.notNil and: { pair.notNil } and: { pair[1].notNil }) {
					pair[0].string = "% : %".format(
						pair[0].string.split($:)[0].stripWhiteSpace,
						val.round(if([\voiceRangeLo, \voiceRangeHi].includes(key)) { 1 } { 0.01 })
					);
					pair[1].value = if([\voiceRangeLo, \voiceRangeHi].includes(key)) {
						(val / 127).clip(0, 1)
					} {
						val.clip(0, 1)
					};
				};
			};

			// drive weight sliders in open popups
			weightSliders.keysValuesDo { |key, pair|
				if(pair.notNil and: { pair[1].notNil }) {
					var val = agent[\weights][key] ? 0.0;
					pair[1].value  = val.clip(0, 1);
					pair[0].string = "% : %".format(
						pair[0].string.split($:)[0].stripWhiteSpace, val.round(0.01));
				};
			};
		}
	};
};

~updateMonitors = {
	if(~simulation[\agents].size > 0) {
		var r, modeKey, ht, tonicPC, midiStr, chordStr, homeStr, modeStr, modeIdx;
		var agent = if(selectedAgentID == -1) {
			~simulation[\agents].first
		} {
			~agentByID.(selectedAgentID) ?? { ~simulation[\agents].first }
		};
		if(agent.notNil) {
			r       = ~detectChord.();
			modeKey = agent[\modeKey] ? \major;
			ht      = agent[\homeTriad] ? [];
			tonicPC = (~simulation[\harmonicState][\tonicPC] ? 0).round.asInteger;

			midiStr  = "MIDI: "  ++ (agent[\currentMidi] ? "—");
			chordStr = "Chord: " ++ if(r[\found]) { "% %".format(r[\root], r[\name]) } { "—" };
			homeStr  = "Home: % (tonic %)".format(ht, tonicPC);
			modeStr  = "Mode: " ++ modeKey;
			modeIdx  = ~modeNames.indexOf(modeKey.asString) ? 0;

			{
				var tonicPCInt = (~simulation[\harmonicState][\tonicPC] ? 0).round.asInteger.mod(12);
				var tonicName  = noteNames[tonicPCInt];
				tonicMonitor.string = "Tonic: % (%)".format(tonicName, tonicPCInt);
				midiMonitor.string  = midiStr;
				chordMonitor.string = chordStr;
				homeTriadLbl.string = homeStr;
				modeLbl.string      = "Inferred: " ++ modeKey;
				if(~tempoMonitor.notNil) {
					var ts      = ~simulation[\timeSource];
					var srcKind = ~simulation[\timeSourceKind] ? \internal;
					var peers   = if(ts.notNil and: { srcKind == \link }) {
						ts[\numPeers].(ts)
					} { nil };
					~tempoMonitor.string = if(peers.notNil) {
						"Tempo: % bpm | % b/tick | peers: %".format(
							(TempoClock.default.tempo * 60).round(0.1),
							(~simulation[\tickSize] ? 0.25).round(0.01),
							peers
						)
					} {
						"Tempo: % bpm | % b/tick".format(
							(TempoClock.default.tempo * 60).round(0.1),
							(~simulation[\tickSize] ? 0.25).round(0.01)
						)
					};
				};
				gateMonitor.refresh;
			}.defer;
		}
	}
};

~rebuildAgentButtons = {
	var agents  = ~simulation[\agents];
	var nTotal, btnW, btnH, allBtn;

	// close open drives popups — they reflect stale agent values
	drivePopups.keysValuesDo { |k, w|
		if(w.notNil and: { w.isClosed.not }) { w.close };
	};
	drivePopups = Dictionary.new;
	weightSliders = Dictionary.new;

	nTotal  = agents.size + 1;
	btnW    = (panelW2 / nTotal).floor;
	btnH    = 24;

	~agentButtons.do { |b| b.remove };
	~agentButtons = [];

	allBtn = Button(~agentButtonContainer, Rect(0, 0, btnW, btnH));
	allBtn.states = [
		["A", Color.grey(0.9), Color.grey(0.25)],
		["A", Color.grey(0.9), Color.grey(0.45)]
	];
	allBtn.font   = Font.monospace(8, true);
	allBtn.value  = if(selectedAgentID == -1) { 1 } { 0 };
	allBtn.action = {
		selectedAgentID = -1;
		~refreshAllViews.();
	};

	if(~allModeHint.notNil) {
		~allModeHint.string = if(selectedAgentID == -1) {
			"all mode: edits broadcast to every agent"
		} {
			"editing agent % only".format(selectedAgentID)
		};
	};

	~agentButtons = ~agentButtons.add(allBtn);

	agents.do { |agent, i|
		var x   = btnW * (i + 1);
		var col = agent[\color] ? Color.white;
		var btn = Button(~agentButtonContainer, Rect(x, 0, btnW, btnH));
		btn.states = [
			[agent[\id].asString, Color.grey(0.1), col.copy.alpha_(0.45)],
			[agent[\id].asString, Color.white,     col.copy.alpha_(0.9)]
		];
		btn.font  = Font.monospace(8, true);
		btn.value = if(selectedAgentID == agent[\id]) { 1 } { 0 };
		btn.action = {
			selectedAgentID = agent[\id];
			~refreshAllViews.();
		};
		~agentButtons = ~agentButtons.add(btn);
	};
};

// Single source of truth for "agent state has changed — redraw everything."
// Called from Spawn, from any agent button, from birth/death GUI hooks, etc. Messy, but it works.
~refreshAllViews = {
    ~refreshWeightSliders.();
    ~rebuildAgentButtons.();
    if(~updateMonitors.notNil)            { ~updateMonitors.() };
    if(~makeRhythmPopupRefresh.notNil)    { ~makeRhythmPopupRefresh.() };
    {
        if(~view.notNil)            { ~view.refresh };
        if(~rhythmView.notNil)      { ~rhythmView.refresh };
        if(~voiceView.notNil)       { ~voiceView.refresh };
        if(~gridInfoMonitor.notNil) { ~gridInfoMonitor.refresh };
    }.defer;
};

~rebuildAgentButtons.();

window.onClose = {
	if(~simSettingsPopups.notNil) {
		~simSettingsPopups.do { |w|
			if(w.notNil and: { w.isClosed.not }) { w.close }
		}
	};
	if(~rhythmPopup.notNil  and: { ~rhythmPopup.isClosed.not  }) { ~rhythmPopup.close  };
	if(~presetPopup.notNil  and: { ~presetPopup.isClosed.not  }) { ~presetPopup.close  };
	~simulation.stop;
	~intervalController.remove;
};
)
