// A landing library - Using Trajectories
@LAZYGLOBAL OFF.

// A function that does a simple landing on a non atmospheric body.
FUNCTION Land_Anywhere {
	IF ADDONS:TR:AVAILABLE {
		// Complete a de-orbit burn first that makes the lander impact in less that 10 minutes from now
		LOCK STEERING TO LOOKDIRUP(-SHIP:VELOCITY:ORBIT, SHIP:FACING:TOPVECTOR).
		WAIT UNTIL VANG(-SHIP:VELOCITY:ORBIT, SHIP:FACING:FOREVECTOR) < 0.1.
		LOCK THROTTLE TO 1.
		WAIT UNTIL ADDONS:TR:HASIMPACT AND ADDONS:TR:TIMETILIMPACT < 600.
		LOCK THROTTLE TO 0.

		// 
	} ELSE {
		RETURN FALSE.
	}
}

FUNCTION Land_CalculateLandingBurn {
	PARAMETER engs, dryMass, timeStep IS 1, endAlt IS 100, endSpeed IS 50.

	LOCAL impactTime IS TIME:SECONDS + ADDONS:TR:TIMETILIMPACT.
	LOCAL startMass IS SHIP:MASS * 1000.

	LOCAL engThrust IS 0.
	LOCAL massFlow IS 0.

	FOR eng IN engs {
		SET engThrust TO engThrust + eng:POSSIBLETHRUSTAT(0) * 1000.
		SET massFlow TO massFlow + eng:POSSIBLETRHUSTAT(0) * 1000 / (eng:VISP * CONSTANT:g0).
	}

	LOCAL done IS FALSE.

	LOCAL startTime IS (impactTime - TIME:SECONDS)/2 + TIME:SECONDS.

	LOCAL newVel IS VELOCITYAT(SHIP, startTime).
	LOCAL newPos IS POSITIONAT(SHIP, startTime).
	LOCAL newAlt IS BODY:ALTITUDEOF(newPos).
	LOCAL newAcc IS v(0,0,0).
	LOCAL newGra IS (newPos - BODY:POSITION):NORMALIZED * Gravity(newAltitude).

	LOCAL oldVel IS newVel.
	LOCAL oldPos IS newPos.

	UNTIL done {
		
	}
}