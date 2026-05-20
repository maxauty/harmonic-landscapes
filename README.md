# **Harmonic Landscapes**

A generative music system written in SuperCollider. Autonomous agents move across a harmonic lattice, making harmonic decisions in real time. Composers shape the system as it runs, through per-agent drives and global controls.

## **Approach**

Harmonic structure emerges from local interaction: agents weigh competing drives as they move through a space whose adjacencies already encode harmonic relationships.

Output is MIDI. The system can be played as a generative instrument, used as a source of harmonic ideas for further composition, or layered over fixed material.

## **Requirements**

* [SuperCollider](https://supercollider.github.io/) 3.13 or later  
* A MIDI destination (DAW, hardware synth, or virtual MIDI port)

No external quarks required.

## **Getting started**

Clone or download the repository. Open `main.scd` in the SuperCollider IDE and evaluate it. The GUI will open and the system will begin running with the default preset.

Presets are organised under `/presets/`:

* `presets/global/` — full system states; a starting point for exploration  
* `presets/scene/` — population-wide configurations  
* `presets/agent/` — individual agent profiles

## **License**

To be decided — I'm looking to make this as free as possible. 
Until a license is added, default copyright applies and the code may not be reused.
