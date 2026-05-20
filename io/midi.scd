// =============================================================================
// MIDI + Audio Output
// =============================================================================

(
// -----------------------------------------------------------------------------
// 1. Native audio fallback — requires nothing external, works on any platform.
//    A simple sine-based synth with fast attack and configurable release.
//    Used automatically when no MIDI device is selected.
// -----------------------------------------------------------------------------

SynthDef(\tonnetzVoice, { |freq=440, amp=0.3, dur=1.0, pan=0.0, out=0|
    var env  = Env.perc(0.01, dur, amp, -4);
    var sig  = SinOsc.ar(freq) * EnvGen.ar(env, doneAction: 2);
    var filt = LPF.ar(sig, freq * 3);
    Out.ar(out, Pan2.ar(filt, pan))
}).add;

SynthDef(\tonnetzPad, { |freq=440, amp=0.2, dur=1.0, pan=0.0, out=0|
    var env  = Env.new([0, 1, 1, 0], [0.05, dur - 0.1, 0.05]);
    var sig  = (SinOsc.ar(freq) + (SinOsc.ar(freq * 2.003) * 0.3)) * 0.5;
    sig = sig * EnvGen.ar(env, doneAction: 2) * amp;
    Out.ar(out, Pan2.ar(sig, pan))
}).add;

// -----------------------------------------------------------------------------
// 2. MIDI initialisation — defensive, cross-platform.
// -----------------------------------------------------------------------------

~midiOut        = nil;
~midiChannel    = 0;
~agentChannels  = [0, 1, 2, 3, 4, 5, 6, 7];
~activeNotes    = List.new;
~useAudioFallback = true;   // default until MIDI confirmed working
~fallbackSynth  = \tonnetzPad;  // or \tonnetzVoice for percussive

// Initialise MIDI client defensively
~initMIDI = {
    var success = false;
    try {
        MIDIClient.init;
        MIDIIn.connectAll;
        success = true;
        "MIDI client initialised.".postln;
        "Available output devices:".postln;
        MIDIClient.destinations.do { |dev, i|
            "  [%] % — %".format(i, dev.device, dev.name).postln;
        };
    } { |err|
        "MIDI init failed: %".format(err).postln;
        "Audio fallback will be used.".postln;
    };
    success
};

// Connect to a specific device by index (from the printed list above).
// Safe to call multiple times — replaces previous connection.
~connectMIDIByIndex = { |index|
    var dev, out;
    if(MIDIClient.destinations.isNil or: {
        MIDIClient.destinations.isEmpty }) {
        "No MIDI destinations available.".postln;
        ~useAudioFallback = true;
    } {
        if(index >= MIDIClient.destinations.size) {
            "Index % out of range (% devices available).".format(
                index, MIDIClient.destinations.size).postln;
        } {
            dev = MIDIClient.destinations[index];
            try {
                out = MIDIOut.newByName(dev.device, dev.name);
                out.latency = 0.0;
                ~midiOut = out;
                ~useAudioFallback = false;
                "Connected to: % — %".format(dev.device, dev.name).postln;
            } { |err|
                "Failed to connect to %: %".format(dev.name, err).postln;
                ~useAudioFallback = true;
            };
        }
    };
};

// Connect by name — useful for scripted setup once you know your device.
~connectMIDIByName = { |deviceName, portName|
    try {
        var out = MIDIOut.newByName(deviceName, portName);
        out.latency = 0.0;
        ~midiOut = out;
        ~useAudioFallback = false;
        "Connected to: % — %".format(deviceName, portName).postln;
    } { |err|
        "Failed to connect to % / %: %".format(
            deviceName, portName, err).postln;
        "Falling back to audio.".postln;
        ~useAudioFallback = true;
    };
};

// Disconnect and revert to audio fallback.
~disconnectMIDI = {
    ~midiOut = nil;
    ~useAudioFallback = true;
    "MIDI disconnected. Using audio fallback.".postln;
};

// -----------------------------------------------------------------------------
// 3. Note cleanup — call before quitting or re-initialising.
// -----------------------------------------------------------------------------

~allNotesOff = {
    if(~midiOut.notNil) {
        ~agentChannels.do { |ch|
            128.do { |note| ~midiOut.noteOff(ch, note, 0) };
        };
    };
    ~activeNotes.clear;
    "All notes off.".postln;
};

// -----------------------------------------------------------------------------
// 4. playNote — unified interface for both MIDI and audio fallback.
//    Replaces the previous version. No non-local returns.
// -----------------------------------------------------------------------------

~playNote = { |midi, vel=100, dur, channel, atBeat|
    var clock = if(~simulation[\timeSource].notNil) {
        ~simulation[\timeSource][\clock]
    } {
        TempoClock.default
    };
    var note, freq, amp, pan;
    var lookAhead = 0.05;
    var startBeat, endBeat, durBeats;

    note    = midi.asInteger.clip(0, 127);
    dur     = dur     ?? { (~simulation[\tickSize] ? 0.25) };
    channel = channel  ? ~midiChannel;
    vel     = vel.clip(0, 127);

    durBeats = (dur - 0.01).max(0.01);

    startBeat = (atBeat ? clock.beats) + (lookAhead * clock.tempo);
    endBeat   = startBeat + durBeats;

    if(startBeat < clock.beats) {
        startBeat = clock.beats + (0.01 * clock.tempo);
        endBeat   = startBeat + durBeats;
    };

    if(~useAudioFallback) {
        // Audio path — MIDI note to frequency, velocity to amplitude
        freq = note.midicps;
        amp  = vel.linlin(0, 127, 0.05, 0.4);
        pan  = channel.linlin(0, 7, -0.6, 0.6);

        // Schedule synth trigger at startBeat rather than firing immediately.
        // Duration passed to Synth is in seconds, so convert beats → seconds
        // using current tempo.
        clock.schedAbs(startBeat, {
            Synth(~fallbackSynth, [
                \freq, freq,
                \amp,  amp,
                \dur,  durBeats / clock.tempo,
                \pan,  pan
            ]);
            nil
        });
    } {
        // MIDI path
        if(~midiOut.notNil) {
            var entry = [note, startBeat, channel];

            // Schedule note-on at startBeat
            clock.schedAbs(startBeat, {
                // Polyphony cap — evict oldest if at limit at emission time
                if(~activeNotes.size >= 64) {
                    var old = ~activeNotes.removeAt(0);
                    try { ~midiOut.noteOff(old[2], old[0], 0) };
                };
                ~activeNotes.add(entry);
                try { ~midiOut.noteOn(channel, note, vel) };
                nil
            });

            // Schedule note-off at endBeat
            clock.schedAbs(endBeat, {
                ~activeNotes.remove(entry);
                if(~midiOut.notNil) {
                    try { ~midiOut.noteOff(channel, note, 0) };
                };
                nil
            });
        };
    };
};

// -----------------------------------------------------------------------------
// 5. Status report — call anytime to check current routing state.
// -----------------------------------------------------------------------------

~midiStatus = {
    "--- Output status ---".postln;
    if(~useAudioFallback) {
        "Mode: AUDIO FALLBACK (SynthDef: %)".format(~fallbackSynth).postln;
        "Server running: %".format(Server.default.serverRunning).postln;
    } {
        "Mode: MIDI".postln;
        "Device: %".format(~midiOut).postln;
        "Active notes: %".format(~activeNotes.size).postln;
    };
    "Agent channels: %".format(~agentChannels).postln;
};

// -----------------------------------------------------------------------------
// 6. Initialise — runs immediately on evaluation.
//    Audio server is booted first so fallback is always available.
// -----------------------------------------------------------------------------

if(Server.default.serverRunning.not) {
    Server.default.waitForBoot {
        "Audio server ready.".postln;
        ~initMIDI.();
        ~midiStatus.();
    };
} {
    ~initMIDI.();
    ~midiStatus.();
};

"
--- MIDI SETUP INSTRUCTIONS ---
Audio fallback is active by default. To use MIDI:

  1. Check the device list printed above.
  2. Connect by index:   ~connectMIDIByIndex.(0)
  3. Or by name:         ~connectMIDIByName.(\"IAC Driver\", \"Bus 1\")   // Mac
                         ~connectMIDIByName.(\"loopMIDI Port\", \"loopMIDI Port\")  // Windows

  To revert to audio:   ~disconnectMIDI.()
  To check status:      ~midiStatus.()
  To silence all notes: ~allNotesOff.()
--------------------------------
".postln;
)