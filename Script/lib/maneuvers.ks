// Time to complete a maneuver
FUNCTION BurnTime {
	PARAMETER dv.
	SET ens TO LIST().
	ens:CLEAR.
	SET ens_thrust TO 0.
	SET ens_isp TO 0.
	LIST ENGINES IN myengines.

	FOR en IN myengines {
		IF en:IGNITION = TRUE AND en:FLAMEOUT = FALSE {
			ens:ADD(en).
		}
	}

	FOR en IN ens {
		SET ens_thrust TO ens_thrust + en:AVAILABLETHRUST.
		SET ens_isp TO ens_isp + en:VISP.
	}

	IF ens_thrust = 0 OR ens_isp = 0 {
		RETURN 0.
	}

	ELSE {
		LOCAL f IS ens_thrust * 1000.  // engine thrust (kg * m/s²)
		LOCAL m IS SHIP:MASS * 1000.        // starting mass (kg)
		LOCAL e IS CONSTANT():e.            // base of natural log
		LOCAL p IS ens_isp/ens:LENGTH.               // engine isp (s) support to average different isp values
		LOCAL g IS SHIP:ORBIT:BODY:MU/SHIP:OBT:BODY:RADIUS^2.    // gravitational acceleration constant (m/s²)
		RETURN g * m * p * (1 - e^(-dv/(g*p))) / f.
	}
}

// Velocity at a circular orbit at the given altitude
FUNCTION OrbitalVelocityAt{
	PARAMETER altitude.
	PARAMETER body IS SHIP:OBT:BODY.

	RETURN SQRT(body:MU/(body:RADIUS+altitude)).
}

// Delta v requirements for Hohmann Transfer
FUNCTION SimpleHohmanDv {
	PARAMETER desiredAltitude.

	SET u  TO SHIP:OBT:BODY:MU.
	SET r1 TO SHIP:OBT:SEMIMAJORAXIS.
	SET r2 TO desiredAltitude + SHIP:OBT:BODY:RADIUS.

	// v1
	SET v1 TO SQRT(u / r1) * (SQRT((2 * r2) / (r1 + r2)) - 1).

	// v2
	SET v2 TO SQRT(u / r2) * (1 - SQRT((2 * r1) / (r1 + r2))).

	// Returns list of 2 values, first one is the dv for initial transfer orbit and second is for circularization
	RETURN LIST(v1, v2).
}

// Dv required to change the inclination of an orbit (eccentric orbits allowed)
FUNCTION SimplePlaneChangeDv {
	PARAMETER vel, newInclination, currentInclination.

	// Make sure we use scalar magnitude and not a vector type
	IF vel:ISTYPE("Vector") { SET vel TO vel:MAG. }

	RETURN 2 * vel * SIN(ABS(newInclination - currentInclination) / 2).
}

// Both the initial and final orbits are circular
FUNCTION HohmanAndPlaneChangeDv {
	PARAMETER newAltitude, newInclination.

	LOCAL r1 IS SHIP:OBT:SEMIMAJORAXIS.
	LOCAL r2 IS newAltitude + SHIP:OBT:BODY:RADIUS.
	LOCAL atx IS (r1 + r2) / 2.
	LOCAL Vi1 IS OrbitalVelocityAt(SHIP:OBT:APOAPSIS).
	LOCAL Vf2 IS OrbitalVelocityAt(newAltitude).
	LOCAL Vtx1 IS SQRT(SHIP:OBT:BODY:MU * (2 / r1 - 1 / atx)).
	LOCAL Vtx2 IS SQRT(SHIP:OBT:BODY:MU * (2 / r2 - 1 / atx)).

	LOCAL dv1 IS Vtx1 - Vi1.
	LOCAL dv2 IS SQRT(Vtx2^2 + Vf2^2 - 2 * Vtx2 * Vf2 * COS(ABS(newInclination - SHIP:OBT:INCLINATION))).

	RETURN LIST(dv1, dv2).
}

// Create a maneuver node for a Geostationary Transfer Orbit (GTO)
FUNCTION GeostationaryTransferOrbit {

	// Calculate the diesired Apoapsis. This will be the final altitude of the Geostationary Orbit
	LOCAL desiredAp IS StationaryOrbitAltitude().

	// Calculate time to get to the closest equatorial node where we'll do the maneuver
	LOCAL timeToEq IS TimeToEquatorialNode().

	// Get the spacecrafts position vector at the equatorial node
	LOCAL posAtEq IS POSITIONAT(SHIP, TIME:SECONDS + timeToEq).
	// Get the spacecrafts velocity vector at the equatorial node
	LOCAL velAtEq IS VELOCITYAT(SHIP, TIME:SECONDS + timeToEq):ORBIT.
	// Get the spacecrafts altitude at the equatorial node. This will be the transfer orbits new Periapsis
	LOCAL altAtEq IS BODY:ALTITUDEOF(posAtEq).

	// Calculate the Semi-Major Axis of the new transfer orbit
	LOCAL GTO_SMA IS (desiredAp + altAtEq)/2 + BODY:RADIUS.
	// Calculate the Eccentricity of the new transfer orbit
	LOCAL GTO_ECC IS OrbitalEccentricity(desiredAp, altAtEq).

	// Calculate the spacecrafts speed at the Periapsis of the new transfer orbit
	LOCAL GTO_SpeedAtPe IS OrbitalSpeed(OrbitalRadius(0, GTO_SMA, GTO_ECC), GTO_SMA).
	// Calculate the prograde vector of the spacecraft at the Periapsis of the new transfer orbit
	LOCAL GTO_ProgradeAtPe IS VXCL(posAtEq - BODY:POSITION, velAtEq):NORMALIZED.
	// Multiply the prograde vector by the speed to get the velocity vector at Periapsis of the new transfer orbit
	LOCAL GTO_VelocityAtPe IS GTO_ProgradeAtPe * GTO_SpeedAtPe.

	// Calculate the required change in velocity for the maneuver
	LOCAL GTO_ManeuverDeltaV IS GTO_VelocityAtPe - velAtEq.

	// Create the maneuver node
	LOCAL maneuverNode IS NodeFromVector(GTO_ManeuverDeltaV, TIME:SECONDS + timeToEq).
	// Add the maneuver node to the flight path
	ADD maneuverNode.

	IF HASNODE { RETURN TRUE. }
	RETURN FALSE.
}

// A function that will do a course correction using RCS to get the GTO Apoapsis precisely on target
// Satellite needs to have both forward and backward facing RCS thrusters
FUNCTION GTOApoapsisCorrection {
	PARAMETER RcsForRotation IS FALSE.

	IF ABS(SHIP:APOAPSIS - StationaryOrbitAltitude()) > 500 {

		LOCAL dir IS SHIP:VELOCITY:ORBIT.

		LOCK STEERING TO LOOKDIRUP(dir, SHIP:FACING:TOPVECTOR).

		IF RcsForRotation { RCS ON. }

		WAIT UNTIL VANG(SHIP:FACING:VECTOR, dir) < 0.01 AND (SHIP:ANGULARVEL:MAG < 0.01).
		WAIT 5.

		RCS ON.
		IF SHIP:APOAPSIS < StationaryOrbitAltitude() {
			SET SHIP:CONTROL:FORE TO 1.
			WAIT UNTIL SHIP:APOAPSIS >= StationaryOrbitAltitude()-1000.
			SET SHIP:CONTROL:FORE TO 0.25.
			WAIT UNTIL SHIP:APOAPSIS >= StationaryOrbitAltitude().
			SET SHIP:CONTROL:FORE TO 0.
		} ELSE {
			SET SHIP:CONTROL:FORE TO -1.
			WAIT UNTIL SHIP:APOAPSIS <= StationaryOrbitAltitude()+1000.
			SET SHIP:CONTROL:FORE TO -0.25.
			WAIT UNTIL SHIP:APOAPSIS <= StationaryOrbitAltitude().
			SET SHIP:CONTROL:FORE TO 0.
		}
		RCS OFF.
	}
}

// nodeFromVector - originally created by reddit user ElWanderer_KSP
FUNCTION NodeFromVector {
	PARAMETER vec, n_time IS TIME:SECONDS.

	LOCAL s_pro IS VELOCITYAT(SHIP,n_time):ORBIT.
	LOCAL s_pos IS POSITIONAT(SHIP,n_time) - BODY:POSITION.
	LOCAL s_nrm IS VCRS(s_pro,s_pos).
	LOCAL s_rad IS VCRS(s_nrm,s_pro).

	RETURN NODE(n_time, VDOT(vec,s_rad:NORMALIZED), VDOT(vec,s_nrm:NORMALIZED), VDOT(vec,s_pro:NORMALIZED)).
}

// Execute the next node
FUNCTION ExecNode {
	PARAMETER RCSRequired, autoWarp.
	
	LOCAL n IS NEXTNODE.
	LOCAL v IS n:BURNVECTOR.

	LOCAL startTime IS TIME:SECONDS + n:ETA - BurnTime(v:MAG/2).
	LOCK STEERING TO v.
	IF RCSRequired { RCS ON. }
	WAIT UNTIL VANG(SHIP:FACING:VECTOR, v) < 0.1 AND (SHIP:ANGULARVEL:MAG < 0.01).
	WAIT 5.

	IF autoWarp { WAIT 1. WARPTO(startTime - 60). }

	WAIT UNTIL TIME:SECONDS >= startTime -5.
	SET SHIP:CONTROL:FORE TO 1.
	WAIT UNTIL TIME:SECONDS >= startTime.
	SET SHIP:CONTROL:FORE TO 0.
	LOCK THROTTLE TO MAX(MIN(BurnTime(n:BURNVECTOR:MAG)/2, 1),0.05).
	WAIT UNTIL VDOT(n:BURNVECTOR, v) < 0.
	LOCK THROTTLE TO 0.
	UNLOCK STEERING.
	RCS OFF.
}