// ==========================================================================================================
// Harmonic Landscapes — a multi-agent system for real-time harmonic composition
// main.scd — System boot
//
// Loads the agent-based music system in dependency order:
//   core/ — geometric, temporal, and behavioural foundations
//   io/   — MIDI output, console diagnostics, additional utilities such as chord detection
//   gui/  — inspection and control interface
// ---------------------------------------------------------------------------------------------------------
//
// FIRST-TIME START/HELP:
//   ToroidalHexManifold.sc file MUST be moved to the SuperCollider extension folder on your machine:
//   1. Find 'classes/ToroidalHexManifold.sc' in the project folder.
//   2. Locate the local class library using 'Platform.userExtensionDir'
//        (alternatively, open 'ToroidalHexManifold.sc' and go to 'File - Save As Extension')
//   3. Drop, duplicate, or save the file into a custom folder.
//   4. Be sure to save the file as a '.sc' file.
//
// Usage:
//   1. Make sure 'ToroidalHexManifold.sc' has been moved to SuperCollider's extensions folder (see above).
//   2. Evaluate the block below to load all modules.
//   3. If using MIDI, call ~connectMIDIByIndex.(n) with your chosen output device index.
//   4. (Optional) Open scratch.scd for diagnostic and testing example invocations.
//
// ---------------------------------------------------------------------------------------------------------
// SuperCollider IDE + Evaluation:
//   'ctrl + d' opens the help browser
//
//   Code blocks can be evaluated with 'ctrl + enter'
//   Single lines can be evaluated with 'shift + enter'
//
//   Press 'ctrl + enter' anywhere in the text below to load the program
//
// ==========================================================================================================

(

Server.killAll;

s = Server.default;

Routine({
	"--- [SERVER BOOT] ---".postln;

	s.waitForBoot {
		var coreModules = [
			"grid.scd", "utilities.scd", "timesource.scd",
			"drive_registry.scd", "drives.scd", "agents.scd", "rhythm.scd",
			"simulation.scd", "harmonic_state.scd", "lifecycle.scd",
			"presets.scd"
		];
		var ioModules   = [
			"midi.scd", "debug.scd", "chord.scd"
		];
		var uiModules   = [
			"gui.scd"
		];
		var base = thisProcess.nowExecutingPath.dirname ++ "/";

        "--- [LOADING TOPOLOGICAL CORE] ---".postln;
        coreModules.do { |file|
            (base ++ "core/" ++ file).load;
            0.1.wait;
            postf("  Core module: % [OK]\n", file.padRight(15, "."));
        };
        s.sync;
        0.5.wait;

        "--- [LOADING I/O SUBSYSTEMS] ---".postln;
        ioModules.do { |file|
            (base ++ "io/" ++ file).load;
            0.2.wait;
            postf("  I/O module: % [OK]\n", file.padRight(15, "."));
        };

        uiModules.do { |file| (base ++ "gui/" ++ file).load };

        0.5.wait;
        s.sync;

        " ".postln;
        "----------------------------------------------".postln;
        "SYSTEM STATUS: ACTIVE".postln;

        if(~midiInstructions.notNil) { ~midiInstructions.value };
    };

}).play(AppClock);

)

//-----------------------------------------------------------------------------
// Connect to the relevant MIDI port by evaluating the lines below
//
// On Windows, download and install LoopMIDI
// On Mac, enable the IAC Driver in Audio MIDI Setup (Window/Show_Midi_Studio)
// Linux compatibility in progress...

MIDIClient.init         // list of available MIDI devices
~connectMIDIByIndex.(1) // choose the relevant MIDI port by changing the number

//   The index corresponds to the MIDI Destinations list:
//     first MIDI destination in list = ~connectMIDIByIndex.(0)
//     second MIDI destination in list = ~connectMIDIByIndex.(1)
//     etc...

//-----------------------------------------------------------------------------
