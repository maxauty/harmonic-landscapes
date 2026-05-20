// =============================================================================
// Debug
// =============================================================================

(
~simulation[\debugMovement] = false;

~noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];

~pcName = { |pc| ~noteNames.at(pc.asInteger.mod(12)) };

// Map drive layers to compact prefixes for the debug row. Drives in
// the bias layer (entrainmentStrength, homeStrength) score 0 per
// candidate, so they're skipped here regardless of their layer tag.
~debugLayerPrefix = (
    motion:       "mot",
    constraint:   "cst",
    harmonic:     "harm",
    gesture:      "gest",
    deliberative: "delib"
);

// Drives whose fn returns 0 by design (consumed by updateAgentBias
// rather than scored per-candidate). Skipped in the per-row dump to
// keep output uncluttered.
~debugSkipDrives = Set[\entrainmentStrength, \homeStrength];

~postDebug = { |label, scored, winner, weights, probs, motivatorScore, inactive|
    var wpc, wdist;
    label   = label   ? "?";
    weights = weights ? Event.new;
    probs   = probs   ? [];

    "  Agent % | tension:% | %".format(
        label,
        motivatorScore.round(0.001),
        if(inactive == true) { "INACTIVE" } { "ACTIVE" }
    ).postln;

    if(inactive != true) {
        scored.do { |e, i|
            var cell     = e[\cell];
            var pc       = ~simulation.grid.pitchClassAt(cell.x, cell.y).asInteger;
            var dist     = e[\gridDistance] ? 1;
            var isWinner = (e[\cell] == winner[\cell]);
            var isJump   = dist > 1;

            // Group drive contributions by layer for readability.
            var driveStrs = Dictionary.new;
            ~driveRegistry.do { |d|
                var name      = d[\name];
                var layer     = d[\layer];
                var prefix    = ~debugLayerPrefix[layer] ? layer.asString;
                var rawScore  = e[name] ? 0;
                var weighted  = rawScore * (weights[name] ? 0);
                var entry;

                // Skip bias-only drives that always score 0
                if(~debugSkipDrives.includes(name).not) {
                    entry = "%:%".format(name, weighted.round(0.01));
                    driveStrs[prefix] = (driveStrs[prefix] ? []).add(entry);
                }
            };

            (
                "    [d%] (%, %) % | % | p:%"
                ++ if(isWinner) { " ◄" } { "" }
                ++ if(isJump)   { " <<JUMP>>" } { "" }
            ).format(
                dist,
                cell.x, cell.y,
                ~pcName.(pc),
                // Layer-grouped drives joined with " | " between layers,
                // " " between drives within a layer
                [\motion, \constraint, \harmonic, \gesture, \deliberative]
                    .collect { |layer|
                        var prefix = ~debugLayerPrefix[layer];
                        var items  = driveStrs[prefix];
                        if(items.notNil and: { items.notEmpty }) {
                            "%[%]".format(prefix, items.join(" "))
                        } { nil }
                    }
                    .reject(_.isNil)
                    .join(" | "),
                (probs[i] ? 0).round(0.01)
            ).postln;
        };

        wpc   = ~simulation.grid.pitchClassAt(
            winner[\cell].x, winner[\cell].y).asInteger;
        wdist = winner[\gridDistance] ? 1;

        // Winner summary: show the four drives most informative for
        // a one-line "why did this candidate win" — same as before,
        // but pulled from the registry by name rather than hardcoded.
        "    → [d%] (%, %) % | vl:% tnz:% ct:% | plr:% tgt:% | p:% %".format(
            wdist,
            winner[\cell].x, winner[\cell].y,
            ~pcName.(wpc),
            (winner[\voiceLeading]      ? 0).round(0.01),
            (winner[\tonnetzContinuity] ? 0).round(0.01),
            (winner[\chordTone]         ? 0).round(0.01),
            (winner[\plrContinuity]     ? 0).round(0.01),
            (winner[\targetTriad]       ? 0).round(0.01),
            (winner[\total]             ? 0).round(0.01),
            if(wdist > 1) { "<<< JUMP dist:%".format(wdist) } { "" }
        ).postln;
    };
};

~postStepHeader = { |sim|
    var hs        = sim[\harmonicState];
    var tonic     = hs[\tonicPC] ? 0;
    var target    = hs[\targetTriad] ? [];
    var tonicName = ~pcName.(tonic.round.asInteger);

    "".postln;
    "=== Step % | tonic:% (%) | tension:% | fn:% | hBlend:% | target:[%] ===".format(
        sim[\stepCount],
        tonic.round(0.01),
        tonicName,
        (hs[\tensionLevel] ? 0).round(0.001),
        hs[\impliedFunction],
        (sim[\effectiveHarmonicBlend] ? sim[\harmonicBlend] ? 0.5).round(0.01),
        target.collect { |pc| ~pcName.(pc) }.join(", ")
    ).postln;

    sim[\agents].do { |a|
        var pc     = sim.grid.pitchClassAt(a[\pos].x, a[\pos].y).asInteger;
        var active = (a[\tensionScore] ? 0) >= (a[\activationThreshold] ? 0.3);
        "  [%] (%, %) % | mode:% | home:[%] | tension:% | %".format(
            a[\label],
            a[\pos].x, a[\pos].y,
            ~pcName.(pc),
            a[\modeKey],
            (a[\homeTriad] ? []).collect { |p| ~pcName.(p) }.join(","),
            (a[\tensionScore] ? 0).round(0.001),
            if(active) { "→ deciding" } { "· resting" }
        ).postln;
    };
};

~postStepFooter = { |sim, activeAgents, previousPositions|
    var transforms = sim[\harmonicState][\recentTransforms] ? [];
    var latest     = transforms.select { |e| e[\step] == sim[\stepCount] };

    if(latest.notEmpty) {
        "  Transforms this step:".postln;
        latest.do { |e|
            var fromPCs = if(e[\fromTriad].notNil) {
                e[\fromTriad][\pcs] ? []
            } { [] };
            var toPCs = if(e[\toTriad].notNil) {
                e[\toTriad][\pcs] ? []
            } { [] };
            var dist = e[\gridDistance] ? 1;

            "    Agent % : [%] → [%] via % %".format(
                e[\agent],
                fromPCs.collect { |pc| ~pcName.(pc) }.join(","),
                toPCs.collect   { |pc| ~pcName.(pc) }.join(","),
                e[\transform],
                if(dist > 1) { "<<< JUMP d:%".format(dist) } { "" }
            ).postln;
        };
    };

    activeAgents.do { |a, i|
        var prev = previousPositions[i];
        if(prev.notNil) {
            var dist = sim.grid.hexDistance(prev, a[\pos]);
            if(dist > 1) {
                "  ! Agent % jumped % steps: (%, %) → (%, %)".format(
                    a[\label], dist,
                    prev.x, prev.y,
                    a[\pos].x, a[\pos].y
                ).postln;
            }
        }
    };

    activeAgents.do { |a|
        if((a[\tensionScore] ? 0) >= (sim[\resolveBoundary] ? 0.8)) {
            "  ! Agent % forced resolution (tension:%)".format(
                a[\label],
                (a[\tensionScore] ? 0).round(0.001)
            ).postln;
        }
    };
};
)
