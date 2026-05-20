// =============================================================================
// ToroidalHexManifold.sc
//
// A toroidal hexagonal grid mapping (column, row) positions onto pitch classes.
// Forms the geometric substrate of the Tonnetz agent system: agents traverse
// this grid, and their position determines the pitch class they sound.
//
// Class file — must be installed in Platform.userExtensionDir and the class
// library recompiled before evaluating main.scd. See README for setup.
// =============================================================================

ToroidalHexManifold {

	/*
	This toroidal hex manifold maps musical pitch classes onto a 2D grid of hexagons.
	"Toroidal" means the grid wraps around at its edges — like a donut — so moving
	off the right edge brings you back to the left, and off the bottom brings you
	to the top. Each hex cell holds a pitch class determined by its position and
	two interval parameters (i1, i2).

	The Tonnetz preset is a classic music-theory layout where moving right by one
	hex goes up a perfect fifth (7 semitones), and moving up-right goes up a
	major third (4 semitones). This principle of Neo-Riemannian theory provides the
	dual-coordinate based substrate over which agents interact.
	*/

	classvar <presets, <>ringCache;
	var <width, <height, <modulus, <>i1, <>i2, <meta;

	// ------------------------------------------------------------
	// Setup
	// ------------------------------------------------------------

	*initClass {
		presets = IdentityDictionary.new;
		ringCache = Dictionary.new;

		// A valid preset must specify a modulus (typically 12 for chromatic
		// pitch space) and two interval parameters i1, i2 — both non-zero and
		// distinct from one another, otherwise the grid would collapse onto
		// a single line or a single pitch class.
		//
		// The Tonnetz uses fifths (7) and major thirds (4): every adjacent
		// triangle of three hexes forms a major or minor triad.
		this.addPreset(\tonnetz, (
			modulus: 12,
			i1: 7,   // interval stepping right across columns (perfect fifth)
			i2: 4    // interval stepping upward across rows (major third)
		));
	}

	*addPreset { |name, dict|
		presets[name] = dict;
	}

	*fromPreset { |name, width=12, height=12|
		var p = presets[name];
		if(p.isNil) { Error("Preset not found").throw };
		^this.new(width, height, p[\modulus], p[\i1], p[\i2], p);
	}

	*new { |width, height, modulus, i1, i2, meta|
		^super.new.init(width, height, modulus, i1, i2, meta)
	}

	init { |w, h, m, a, b, metaDict|
		width   = w;
		height  = h;
		modulus = m;
		i1      = a;
		i2      = b;
		meta    = metaDict;
		^this
	}

	setI1 { |v|
		// Interval 1 must be non-zero and different from interval 2,
		// otherwise the grid collapses (all cells the same pitch, or
		// indistinguishable from the other axis).
		if(v != 0 and: { v != i2 }) {
			i1 = v;
			ringCache = Dictionary.new;
			this.changed(\intervals);
		};
	}

	setI2 { |v|
		if(v != 0 and: { v != i1 }) {
			i2 = v;
			ringCache = Dictionary.new;
			this.changed(\intervals);
		};
	}

	// ------------------------------------------------------------
	// Coordinate handling
	// ------------------------------------------------------------

	/*
	As stated above, this class uses two coordinate systems. These systems can be converted between each other:

	  OFFSET coordinates: simple (col, row) grid positions, like a spreadsheet.
	    Odd columns are shifted down by half a hex to create the staggered "flat" hex layout.
	    This is the system used for storage, pitch calculation, and display.

	  CUBE coordinates: a three-axis system [x, y, z] where x + y + z always = 0.
	    This makes distance and direction calculations clean and symmetrical.
	    Think of it as describing position as a combination of three diagonal axes,
	    each 120 degrees apart. Used internally for geometry.

	    (for a brilliant resource on the subject of mapping hexagonal grids,
	    see: "https://www.redblobgames.com/grids/hexagons/")

	Wrapping: coordinates that go off the edge are folded back using modulo arithmetic,
	so the grid behaves like a torus.
	*/

	// Fold a position back into the grid if it has gone off an edge.
	wrap { |x, y|
		^Point(x.mod(width), y.mod(height))
	}

	wrapPoint { |p|
		if(p.isNil) { "wrapPoint received nil".error };
		^this.wrap(p.x, p.y)
	}

	// Fold a cube coordinate back into the toroidal grid.
	// We do this by converting to offset, wrapping, then converting back.
	wrapCube { |cube|
		var offset = this.cubeToOffset(cube);
		var wrapped = this.wrapPoint(offset);
		^this.offsetToCubeRaw(wrapped)
	}

	// Convert offset (col, row) to cube coordinates [x, y, z].
	// This is the "even-q" hex layout: odd columns are shifted down by half a cell.
	// The offset accounts for this column-stagger before projecting onto cube axes.
	offsetToCubeRaw { |p|
		// Remove the column stagger to get a clean x position on the cube grid.
		var cubeX = p.x - ((p.y - (p.y % 2)) / 2);
		// The z axis maps directly onto the row.
		var cubeZ = p.y;
		// y is determined by x and z (they must always sum to zero).
		var cubeY = cubeX.neg - cubeZ;
		^[cubeX, cubeY, cubeZ]
	}

	// Same as offsetToCubeRaw but wraps the input point first.
	offsetToCube { |p|
		^this.offsetToCubeRaw(this.wrapPoint(p))
	}

	// Convert cube coordinates [x, y, z] back to offset (col, row).
	// This is the inverse of offsetToCubeRaw.
	cubeToOffset { |cube|
		var cubeX = cube[0];
		var cubeZ = cube[2];
		// Restore the column stagger that was removed in offsetToCubeRaw.
		var col = cubeX + ((cubeZ - (cubeZ % 2)) / 2);
		var row = cubeZ;
		^Point(col, row)
	}

	// Round a fractional cube coordinate to the nearest whole hex cell.
	// Naive rounding of all three axes can violate the x+y+z=0 constraint,
	// so we correct whichever axis drifted the most.

	// This needs some work and there is a simpler way to implement
	// (requires slight architectural restructure before submission).
	cubeRound { |cube|
		var rx = cube[0].round;
		var ry = cube[1].round;
		var rz = cube[2].round;

		var xDrift = (rx - cube[0]).abs;
		var yDrift = (ry - cube[1]).abs;
		var zDrift = (rz - cube[2]).abs;

		// Fix the axis that rounded furthest from its true value.
		if(xDrift > yDrift and: { xDrift > zDrift }) {
			rx = ry.neg - rz;   // x was worst: recalculate it from y and z
		}{
			if(yDrift > zDrift) {
				ry = rx.neg - rz; // y was worst: recalculate from x and z
			}{
				rz = rx.neg - ry; // z was worst: recalculate from x and y
			};
		};

		^[rx, ry, rz]
	}

	// Find the shortest displacement in cube space between two points on the torus.
	// On a wrapping grid, there are multiple paths between two points; this finds
	// the one that crosses the fewest hexes (i.e. the shortest route).

	// Note: this works because shortest-path displacement on the toroidal manifold
	// is resolved in the rectangular offset-coordinate projection before being mapped
	cubeDelta { |a, b|
		var wrappedA = this.wrapPoint(a);
		var wrappedB = this.wrapPoint(b);

		// Find the raw offset-space displacement.
		var rawDX = wrappedB.x - wrappedA.x;
		var rawDY = wrappedB.y - wrappedA.y;

		// Remap into the range [-half, +half] so we always take the shorter
		// of the two possible routes around the torus.
		var halfW = width  div: 2;
		var halfH = height div: 2;
		var shortestDX = (rawDX + halfW).mod(width)  - halfW;
		var shortestDY = (rawDY + halfH).mod(height) - halfH;

		// Convert both the starting point and the displaced endpoint to cube space,
		// then subtract to get the displacement vector in cube coordinates.
		var startCube = this.offsetToCubeRaw(wrappedA);
		var endCube   = this.offsetToCubeRaw(Point(wrappedA.x + shortestDX, wrappedA.y + shortestDY));

		^[
			endCube[0] - startCube[0],
			endCube[1] - startCube[1],
			endCube[2] - startCube[2]
		]
	}

	// Alias for cubeDelta — I think "hex delta" is perhaps a more intuitive name.
	hexDelta { |a, b|
		^this.cubeDelta(a, b)
	}

	hexDistance { |a, b|
		var cubeA = this.offsetToCube(a);
		var cubeB = this.offsetToCube(b);

		// Period vectors: how far is "one full wrap" in cube space for this
		// grid's specific width and height. Computed from the actual offset-to-cube
		// mapping rather than assumed — this is what makes it correct for any
		// grid size.
		var pX = this.offsetToCubeRaw(Point(width, 0));
		var pY = this.offsetToCubeRaw(Point(0, height));

		var best = inf;

		// Test every wrap-image of B (one full period in each direction)
		// and keep the minimum cube-space distance.
		[-1, 0, 1].do { |nx|
			[-1, 0, 1].do { |ny|
				var shifted = [
					cubeB[0] + (nx * pX[0]) + (ny * pY[0]),
					cubeB[1] + (nx * pX[1]) + (ny * pY[1]),
					cubeB[2] + (nx * pX[2]) + (ny * pY[2])
				];
				var dist = (
					(shifted[0] - cubeA[0]).abs +
					(shifted[1] - cubeA[1]).abs +
					(shifted[2] - cubeA[2]).abs
				) / 2.0;
				if(dist < best) { best = dist }
			}
		};

		^best
	}

	// Shortest displacement in offset (col, row) space, accounting for torus wrapping.
	offsetDelta { |a, b|
		var rawDX = b.x - a.x;
		var rawDY = b.y - a.y;
		var halfW = width  div: 2;
		var halfH = height div: 2;
		var shortestDX = (rawDX + halfW).mod(width)  - halfW;
		var shortestDY = (rawDY + halfH).mod(height) - halfH;
		^Point(shortestDX, shortestDY)
	}

	// Find the average position of a set of points on the torus.
	// A simple arithmetic mean would fail near the wrap edges (e.g. averaging
	// col 0 and col 11 on a width-12 grid would wrongly give col 5.5 instead of 11.5).
	// Instead, this function projects each axis onto a circle, averaging the angles, then projects back.
	toroidalMean { |points|
		var meanAxis = { |values, axisSize|
			// Map each value to an angle on a circle
			var angles = values.collect { |v| (v / axisSize) * 2pi };
			// Average the sine and cosine components separately (circular mean).
			var avgSin = angles.collect(_.sin).mean;
			var avgCos = angles.collect(_.cos).mean;
			// Recover the mean angle and map back to grid coordinates.
			var meanAngle = atan2(avgSin, avgCos);
			if(meanAngle < 0) { meanAngle = meanAngle + 2pi };
			(meanAngle / 2pi) * axisSize;
		};

		var mx = meanAxis.(points.collect(_.x), width);
		var my = meanAxis.(points.collect(_.y), height);
		^Point(mx.round, my.round)
	}

	// ------------------------------------------------------------
	// Pitch logic
	// ------------------------------------------------------------

	// The pitch class at a grid position is a linear combination of its
	// column and row, scaled by the two interval parameters, then wrapped
	// into the modulus (e.g. 12 for standard chromatic pitch classes).
	// Moving one column right adds i1 semitones; one row up adds i2 semitones.
	pitchClassAt { |x, y|
		var p = this.wrap(x, y);
		^((p.x * i1) + (p.y * i2)).mod(modulus)
	}

	pitchClassAtPoint { |p|
		^this.pitchClassAt(p.x.floor, p.y.floor)
	}

	pitchClassAtCube { |cube|
		^((cube[0] * i1) + (cube[2] * i2)).mod(modulus)
	}

	// Convert a grid position to a MIDI note number.
	// Pitch class gives the note within the octave; the octave parameter shifts it.
	midiAt { |x, y, octave=5|
		^this.pitchClassAt(x, y) + (octave.max(0) * modulus)
	}

	midiAtPoint { |p, octave=5|
		^this.midiAt(p.x.floor, p.y.floor, octave)
	}

	midiAtCube { |cube, octave|
		var offset = this.cubeToOffset(cube);
		^this.midiAt(offset[0], offset[1], octave);
	}

	// ------------------------------------------------------------
	// Neighbourhood
	// ------------------------------------------------------------

	// Return the six immediate neighbours of a hex cell.
	// Works in cube space, where the six neighbour directions are clean
	// unit vectors, then converts back to offset coordinates.
	wrappedNeighbors { |coord|
		var cube = this.offsetToCube(coord);
		// The six cube-space unit directions, one per hex face.
		var hexDirections = [
			[ 1,-1, 0],
			[ 1, 0,-1],
			[ 0, 1,-1],
			[-1, 1, 0],
			[-1, 0, 1],
			[ 0,-1, 1]
		];
		^hexDirections.collect { |dir|
			var neighborCube = [
				cube[0] + dir[0],
				cube[1] + dir[1],
				cube[2] + dir[2]
			];
			this.cubeToOffset(this.wrapCube(neighborCube));
		};
	}

	wrappedNeighborsAtRadius { |coord, r|
		var key, result;

		if(r <= 0) { ^[coord] };
		if(r == 1) { ^this.wrappedNeighbors(coord) };

		// Lazy cache — key on position and radius.
		key = "%;%;%".format(coord.x.asInteger, coord.y.asInteger, r);
		result = ringCache[key];
		if(result.notNil) { ^result };

		// Cache miss — compute and store.
		result = [];
		(0 .. width - 1).do { |x|
			(0 .. height - 1).do { |y|
				var p = Point(x, y);
				if(this.hexDistance(coord, p) == r) {
					result = result.add(p)
				}
			}
		};
		ringCache[key] = result;
		^result
	}

	// All cells within distance r (inclusive), excluding coord itself.
	wrappedNeighborsWithin { |coord, r|
		var result = [];
		(1 .. r).do { |ring|
			result = result ++ this.wrappedNeighborsAtRadius(coord, ring)
		};
		^result
	}

	// Returns the six triangles surrounding pos as an Array of Events.
	// Each event: (vertices: [p1,p2,p3], pcs: [pc1,pc2,pc3], quality: \major/\minor).
	//
	// Each pair indexes into wrappedNeighbors(pos). Together with pos itself
	// as the third vertex, each pair forms one of the six triangular regions
	// associated with this hex. The specific index pattern was chosen to enumerate
	// all six triangles without duplication.
	trianglesAt { |pos|
		var nb     = this.wrappedNeighbors(pos);
		var centre = pos;
		var pairs  = [[0,2],[0,5],[1,3],[1,4],[2,4],[3,5]];
		^pairs.collect { |pair|
			var pts = [centre, nb[pair[0]], nb[pair[1]]];
			var pcs = pts.collect { |p| this.pitchClassAt(p.x, p.y) };
			(vertices: pts, pcs: pcs, quality: this.triadQuality(pcs))
		}
	}

	// Classifies three pitch classes as \major or \minor.
	// Sorts them and checks interval structure.
	triadQuality { |pcs|
		var sorted = pcs.as(Array).sort;
		3.do { |i|
			var a = sorted[i.mod(3)];
			var b = sorted[(i+1).mod(3)];
			var c = sorted[(i+2).mod(3)];
			var lower = (b - a).mod(12);
			var upper = (c - b).mod(12);
			if(lower == 4 and: { upper == 3 }) { ^\major };
			if(lower == 3 and: { upper == 4 }) { ^\minor };
		};
		^\ambiguous
	}

	// Returns the neo-Riemannian transformation type relating two adjacent
	// triangles (Cohn 1997, 2012):
	//   P (parallel)      — two triangles share a perfect fifth/fourth
	//   L (leading-tone)  — two triangles share a major third
	//   R (relative)      — two triangles share a minor third
	// Expects two events as returned by trianglesAt.
	transformationBetween { |triA, triB|
		var aPCs      = triA[\pcs].collect(_.asInteger);
		var bPCs      = triB[\pcs].collect(_.asInteger);
		var sharedPCs = aPCs.select { |pc| bPCs.includes(pc) };
		var interval, shared;
		if(sharedPCs.size != 2) { ^nil };
		interval = (sharedPCs[1] - sharedPCs[0]).abs.mod(12);
		shared   = interval.min(12 - interval);
		if(shared == 5) { ^\P };
		if(shared == 4) { ^\L };
		if(shared == 3) { ^\R };
		^nil
	}

	// ------------------------------------------------------------
	// Scoring
	// ------------------------------------------------------------

	// Provisional placeholder. Returns hex distance from the geometric centre
	// of the grid, used as a default scoring function before the harmonic
	// field's mode-aware scoring takes over. Retained because some debug paths
	// still reach for a per-cell scalar; will be superseded when the harmonic
	// scoring API is consolidated into a dedicated HarmonicField class.
	scoreAt { |x, y|
		var cellPosition = Point(x, y);
		var gridCentre   = Point(width div: 2, height div: 2);
		^this.hexDistance(cellPosition, gridCentre);
	}

	// ------------------------------------------------------------
	// Display
	// ------------------------------------------------------------

	// Convert a hex grid position to pixel coordinates for drawing.
	// Hexagons in this layout are flat-topped, arranged in columns.
	// - Horizontal spacing: columns are 3/4 of the cell width apart
	//   (hexes overlap horizontally by 1/4 to tessellate correctly).
	// - Vertical spacing: rows are (√3 / 2) × cellSize apart.
	// - Odd columns are shifted down by half a row to produce the stagger.
	screenPoint { |x, y, cellSize|
		var horizontalSpacing = cellSize * 0.75;         // 3/4 width per column
		var rowHeight         = cellSize * 0.8660254;    // (√3/2) × cellSize
		var columnStagger     = cellSize * 0.4330127;    // half a row height (√3/4)

		var drawX = x * horizontalSpacing;
		var drawY = (y * rowHeight) + ((x % 2) * columnStagger);
		^Point(drawX, drawY);
	}
}
