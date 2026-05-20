// =============================================================================
// core/presets.scd — Preset system
//
// Three preset scopes:
//   \global — sim-wide configurable fields on ~simulation
//   \agent  — per-agent weights, character, and rhythm
//   \scene  — global + all agents bundled together
//
// This file also serves as the single source of truth for which keys
// belong to each scope and what their defaults and ranges are. Other
// files (gui.scd layerSpecs, weightsFromChar, simulationFactory defaults)
// should eventually be refactored to read from ~presetSchema rather than
// redeclaring these values.
//
// Preset files are plain .scd files containing a single Event literal.
// They are human-readable, hand-editable, and round-trip via .asCompileString
// and path.load. Stored under presets/global/, presets/agent/, presets/scene/.
// =============================================================================

(

// --- Schema version ---------------------------------------------------------
// Increment whenever a key is added, removed, or renamed.
// Loaded presets carry their version; mismatches warn but load gracefully
// (missing keys fall back to schema defaults, unknown keys are ignored).

~presetSchemaVersion = 1;

// --- Base path --------------------------------------------------------------
// Captured at load time while thisProcess.nowExecutingPath is valid.
// Assumes this file lives at project/core/presets.scd, so two dirnames
// up gives the project root.

~presetBaseDir = thisProcess.nowExecutingPath.dirname.dirname ++ "/presets/";

// --- Schema -----------------------------------------------------------------
// Each numeric field:  (default: v, range: [lo, hi])
// Each boolean field:  (default: v)
// Each symbolic field: (default: v)
// Weight fields carry a layer tag for GUI population (future migration).

~presetSchema = (

    global: (

        // Harmonic system
        harmonicBlend:         ( default: 0.6,   range: [0.0, 1.0]  ),
        modeStrictness:        ( default: 0.85,  range: [0.0, 1.0]  ),
        modeHysteresis:        ( default: 0.1,   range: [0.0, 0.5]  ),
        tonicUpdateRate:       ( default: 0.15,  range: [0.0, 1.0]  ),
        tonicShiftThreshold:   ( default: 2.5,   range: [0.0, 6.0]  ),
        interactionRadius:     ( default: 3,     range: [1,   12]   ),
        responseWindow:        ( default: 4,     range: [1,   16]   ),

        // Decision mixture
        resolveBoundary:       ( default: 0.55,  range: [0.0, 1.0]  ),
        gestureThreshold:      ( default: 0.45,  range: [0.0, 1.0]  ),
        deliberativeBlend:     ( default: 0.2,   range: [0.0, 1.0]  ),

        // Layer temperatures
        tempMotion:            ( default: 0.8,   range: [0.1, 3.0]  ),
        tempHarmonic:          ( default: 0.7,   range: [0.1, 3.0]  ),
        tempGesture:           ( default: 1.0,   range: [0.1, 3.0]  ),
        tempDeliberative:      ( default: 1.0,   range: [0.1, 3.0]  ),

        // Voicing
        realiseMelodic:        ( default: 0.55,  range: [0.0, 1.0]  ),
        realiseSpacing:        ( default: 0.3,   range: [0.0, 1.0]  ),
        realiseCentre:         ( default: 0.15,  range: [0.0, 1.0]  ),
        registerCenter:        ( default: 5,     range: [1,   8]    ),

        // Structural
        structuralClockPeriod: ( default: 8,     range: [2,   32]   ),
        jumpRadius:            ( default: 1,     range: [1,   3]    ),
        globalCycleLen:        ( default: 16,    range: [4,   64]   ),

        // Timing
        tickSize:              ( default: 1.0,   range: [0.05, 4.0] ),
        linkLatency:           ( default: 0.1,   range: [0.001, 0.2]),
        initialTempo:          ( default: 2.0,   range: [0.5,  8.0] ),

        // Lifecycle (birth)
        birthEnabled:          ( default: true                      ),
        birthContestThreshold: ( default: 0.75,  range: [0.5, 0.95] ),
        birthDwellSteps:       ( default: 3,     range: [1,   10]   ),
        maxAgents:             ( default: 8,     range: [2,   16]   ),

        // Lifecycle (death)
        deathEnabled:          ( default: true                      ),
        samePCDeathSteps:      ( default: 16,    range: [4,   64]   ),
        blockedDeathSteps:     ( default: 16,    range: [4,   64]   ),
        minAgents:             ( default: 1,     range: [1,   4]    ),

        // Booleans
        jumpOnResolve:         ( default: true                      ),
        postChords:            ( default: true                      ),
        debugMovement:         ( default: false                     ),

        // Tonal lock state
        tonicLocked:           ( default: false                     ),
        modeLocked:            ( default: false                     ),
        lockedTonicPC:         ( default: 0,     range: [0,   11]   ),
        lockedModeKey:         ( default: \major                    ),
    ),

    agentChar: (
        activation:            ( default: 0.5,  range: [0.0, 1.0]  ),
        soundThreshold:        ( default: 0.3,  range: [0.0, 1.0]  ),
        voiceRangeLo:          ( default: 48,   range: [0,   127]  ),
        voiceRangeHi:          ( default: 72,   range: [0,   127]  ),
        stepInterval:          ( default: 4,    range: [1,   16]   ),
        modeKey:               ( default: \major                   ),
        channel:               ( default: 0,    range: [0,   15]   ),
    ),

    agentWeights: (
        // Motion
        momentum:              ( default: 0.25, range: [0.0, 1.0], layer: \motion      ),
        stigmergy:             ( default: 0.2,  range: [0.0, 1.0], layer: \motion      ),
        sparsity:              ( default: 0.08, range: [0.0, 1.0], layer: \motion      ),
        stepCost:              ( default: 0.3,  range: [0.0, 1.0], layer: \motion      ),

        // Constraint
        fatigue:               ( default: 0.15, range: [0.0, 1.0], layer: \constraint  ),

        // Gesture
        imitation:             ( default: 0.2,  range: [0.0, 1.0], layer: \gesture     ),

        // Harmonic
        voiceLeading:          ( default: 0.5,  range: [0.0, 1.0], layer: \harmonic    ),
        tonnetzContinuity:     ( default: 0.5,  range: [0.0, 1.0], layer: \harmonic    ),
        chordTone:             ( default: 0.5,  range: [0.0, 1.0], layer: \harmonic    ),
        harmonicBias:          ( default: 0.6,  range: [0.0, 1.0], layer: \harmonic    ),
        homeStrength:          ( default: 0.55, range: [0.0, 1.0], layer: \harmonic    ),
        entrainmentStrength:   ( default: 0.4,  range: [0.0, 1.0], layer: \harmonic    ),

        // Deliberative
        plrContinuity:         ( default: 0.3,  range: [0.0, 1.0], layer: \deliberative),
        targetTriad:           ( default: 0.45, range: [0.0, 1.0], layer: \deliberative),
        tonicPull:             ( default: 0.2,  range: [0.0, 1.0], layer: \deliberative),
        modeCoherence:         ( default: 0.5,  range: [0.0, 1.0], layer: \deliberative),
        harmonicResponse:      ( default: 0.4,  range: [0.0, 1.0], layer: \deliberative),

        // Rhythmic
        phaseCoupling:         ( default: 0.05, range: [0.0, 0.3], layer: \rhythmic    ),
    ),

    agentRhythm: (
        pulses:                ( default: 4,    range: [1, 16] ),
        cycleLen:              ( default: 16,   range: [4, 32] ),
        phase:                 ( default: 0,    range: [0, 31] ),
    ),
);


// =============================================================================
// CAPTURE
// =============================================================================
// Read only schema-declared keys off the live target. Any key not yet
// initialised in the target falls back to the schema default, so captures
// are always complete and valid.

~captureGlobalPreset = {
    var snap = ( schemaVersion: ~presetSchemaVersion, scope: \global );
    ~presetSchema[\global].keysValuesDo { |key, spec|
        snap[key] = ~simulation[key] ? spec[\default];
    };
    snap
};

~captureAgentPreset = { |agent|
    var snap = ( schemaVersion: ~presetSchemaVersion, scope: \agent );

    ~presetSchema[\agentChar].keysValuesDo { |key, spec|
        snap[key] = agent[key] ? spec[\default];
    };

    snap[\weights] = ();
    ~presetSchema[\agentWeights].keysValuesDo { |key, spec|
        snap[\weights][key] = (agent[\weights] !? { |w| w[key] }) ? spec[\default];
    };

    snap[\rhythm] = ();
    ~presetSchema[\agentRhythm].keysValuesDo { |key, spec|
        snap[\rhythm][key] = (agent[\rhythm] !? { |r| r[key] }) ? spec[\default];
    };

    snap
};

~captureScenePreset = {
    var snap = ( schemaVersion: ~presetSchemaVersion, scope: \scene );
    snap[\global] = ~captureGlobalPreset.();
    snap[\agents] = ~simulation[\agents].collect { |a| ~captureAgentPreset.(a) };
    snap
};


// =============================================================================
// APPLY
// =============================================================================
// Write schema-declared keys from a snapshot into the live target.
// Unknown keys in the snapshot are silently ignored (forward compatibility).
// Missing keys fall back to schema defaults (backward compatibility).
// Calls recompute hooks so cached downstream state stays in sync.

~applyGlobalPreset = { |snap|
    if(snap[\schemaVersion] != ~presetSchemaVersion) {
        "Preset schema version mismatch (file: %, current: %). Applying with defaults for missing keys."
            .format(snap[\schemaVersion], ~presetSchemaVersion).warn;
    };

    ~presetSchema[\global].keysValuesDo { |key, spec|
        ~simulation[key] = snap[key] ? spec[\default];
    };

    // Sync tickSize into the running time source if there is one
    if(~simulation[\timeSource].notNil) {
        ~simulation[\timeSource][\tickSize] = ~simulation[\tickSize];
    };

    // Recompute harmonic state so agents reflect the new configuration
    // before the next tick fires
    if(~simulation[\agents].notNil and: { ~simulation[\agents].size > 0 }) {
        ~simulation.updateTonicCentre;
        ~simulation.updateTriadState;
        ~simulation.updateAgentBias;
        ~simulation.updateAgentTension;
    };

    // Refresh GUI if loaded
    { ~refreshWeightSliders !? _.() }.defer;
};

~applyAgentPreset = { |agent, snap|
    if(snap[\schemaVersion] != ~presetSchemaVersion) {
        "Agent preset schema version mismatch. Applying with defaults for missing keys.".warn;
    };

    // Character fields
    ~presetSchema[\agentChar].keysValuesDo { |key, spec|
        agent[key] = snap[key] ? spec[\default];
    };

    // Drive weights
    if(snap[\weights].notNil) {
        if(agent[\weights].isNil) { agent[\weights] = () };
        ~presetSchema[\agentWeights].keysValuesDo { |key, spec|
            agent[\weights][key] = snap[\weights][key] ? spec[\default];
        };
    };

    // Rhythm — update fields, then regenerate Bjorklund pattern
    if(snap[\rhythm].notNil) {
        if(agent[\rhythm].isNil) { agent[\rhythm] = () };
        ~presetSchema[\agentRhythm].keysValuesDo { |key, spec|
            agent[\rhythm][key] = snap[\rhythm][key] ? spec[\default];
        };
        ~regeneratePattern !? { |fn| fn.(agent[\rhythm]) };
    };

    // Re-derive modal context from the (possibly changed) modeKey.
    // Uses current collective tonic rather than whatever was in the snapshot.
    {
        var tonicInt  = (~simulation[\harmonicState][\tonicPC] ? 0).round.asInteger;
        var key       = agent[\modeKey] ? \major;
        var intervals = ~modeHomeTriad[key] ? [0, 4, 7];
        agent[\homeTriad]      = intervals.collect { |i| (tonicInt + i).mod(12) };
        agent[\modeCollection] = (~modeCollections[key] ? ~modeCollections[\major])
            .collect { |pc| (pc + tonicInt).mod(12) };
    }.value;

    agent
};

~applyScenePreset = { |snap|
    snap[\global] !? { |g| ~applyGlobalPreset.(g) };

    snap[\agents] !? { |agentSnaps|
        agentSnaps.do { |agentSnap, i|
            var agent = ~simulation[\agents][i];
            // Agent count mismatch: apply as many as exist, skip the rest
            agent !? { ~applyAgentPreset.(agent, agentSnap) };
        };
    };

    { ~refreshWeightSliders !? _.() }.defer;
    { ~rhythmView  !? _.refresh }.defer;
    { ~updateMonitors !? _.() }.defer;
};


// =============================================================================
// PERSISTENCE
// =============================================================================

// Ensure all three scope subdirectories exist under ~presetBaseDir.
// Safe to call multiple times — just checks and creates if absent.
~ensurePresetDirs = {
    if(File.exists(~presetBaseDir).not) { File.mkdir(~presetBaseDir) };
    [\global, \agent, \scene].do { |scope|
        var dir = ~presetBaseDir ++ scope.asString ++ "/";
        if(File.exists(dir).not) { File.mkdir(dir) };
    };
};

~presetPath = { |scope, name|
    ~presetBaseDir ++ scope.asString ++ "/" ++ name ++ ".scd"
};

// Save a captured snapshot to disk.
// name: a plain string, no extension, e.g. "settled" or "my-anchor-agent"
~savePreset = { |snap, name|
    var scope = snap[\scope] ? \global;
    var path  = ~presetPath.(scope, name);
    var file;

    ~ensurePresetDirs.();

    file = File(path, "w");
    file.write(snap.asCompileString);
    file.close;
    "Preset saved → %".format(path).postln;
    path
};

// Load a preset from disk. Returns the Event, or nil on failure.
~loadPreset = { |scope, name|
    var path = ~presetPath.(scope, name);
    var snap = nil;
    if(File.exists(path)) {
        snap = path.load;
        "Preset loaded ← %".format(path).postln;
    } {
        "Preset not found: %".format(path).warn;
    };
    snap
};

// List available preset names for a given scope.
// Returns an Array of strings (no extension).
~listPresets = { |scope|
    var dir = ~presetBaseDir ++ scope.asString ++ "/";
    if(File.exists(dir)) {
        PathName(dir).files
            .select  { |f| f.extension == "scd" }
            .collect { |f| f.fileNameWithoutExtension }
    } {
        []
    }
};

// Convenience: list all three scopes at once and post to console.
~listAllPresets = {
    [\global, \agent, \scene].do { |scope|
        var names = ~listPresets.(scope);
        "Presets [%]: %".format(scope, if(names.isEmpty) { "(none)" } { names.join(", ") }).postln;
    };
};


// =============================================================================
// MORPH (numeric fields only — booleans and symbols snap at t = 0.5)
// =============================================================================
// Returns a new snapshot interpolated between a and b at position t (0.0–1.0).
// Scope must match. Does not apply — call the relevant ~apply* function with
// the result.

~morphPresets = { |snapA, snapB, t|
    var morphEvent;

    if(snapA[\scope] != snapB[\scope]) {
        "morphPresets: scope mismatch (% vs %). Returning snapA unchanged."
            .format(snapA[\scope], snapB[\scope]).warn;
        snapA
    } {
        morphEvent = { |a, b, schema|
            var result = ();
            schema.keysValuesDo { |key, spec|
                var va = a[key] ? spec[\default];
                var vb = b[key] ? spec[\default];
                result[key] = if(spec[\range].notNil) {
                    // Numeric: linear interpolation
                    va + ((vb - va) * t)
                } {
                    // Symbol / boolean: snap at midpoint
                    if(t < 0.5) { va } { vb }
                };
            };
            result
        };

        switch(snapA[\scope],
            \global, {
                var snap = morphEvent.(snapA, snapB, ~presetSchema[\global]);
                snap[\scope]         = \global;
                snap[\schemaVersion] = ~presetSchemaVersion;
                snap
            },
            \agent, {
                var snap      = morphEvent.(snapA, snapB, ~presetSchema[\agentChar]);
                snap[\scope]  = \agent;
                snap[\schemaVersion] = ~presetSchemaVersion;
                snap[\weights] = morphEvent.(snapA[\weights] ? (), snapB[\weights] ? (), ~presetSchema[\agentWeights]);
                // Rhythm: snap (non-interpolable Bjorklund integers)
                snap[\rhythm]  = if(t < 0.5) { snapA[\rhythm] } { snapB[\rhythm] };
                snap
            },
            \scene, {
                var snap = ();
                snap[\scope]         = \scene;
                snap[\schemaVersion] = ~presetSchemaVersion;
                snap[\global]        = ~morphPresets.(snapA[\global], snapB[\global], t);
                snap[\agents]        = snapA[\agents].collect { |agA, i|
                    var agB = snapB[\agents][i] ? agA;
                    ~morphPresets.(agA, agB, t)
                };
                snap
            }
        )
    }
};


// --- Initialise directories on load ----------------------------------------
~ensurePresetDirs.();
"Preset system ready. Base dir: %".format(~presetBaseDir).postln;

// =============================================================================
// Initialisation
// =============================================================================

~driveModel              = ~driveModelFactory.(nil, ~grid, ~harmonicField);
~simulation              = ~simulationFactory.(~grid, ~driveModel);
~driveModel[\simulation] = ~simulation;

)