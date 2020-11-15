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
	LOCAL timeToAN IS TimeToTrueAnomaly(TA_EquatorialAN()).
	LOCAL timeToDN IS TimeToTrueAnomaly(TA_EquatorialDN()).
	LOCAL timeToEq IS MIN(timeToAN, timeToDN).

	// Make sure that we have enough time to prepare for the maneuver. Otherwise, use next node instead
	IF timeToEq < 60*4 { SET timeToEq TO MAX(timeToAN, timeToDN). }

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

	WAIT 0.
	IF HASNODE { RETURN TRUE. }
	RETURN FALSE.
}

// A function that will do a course correction using RCS to get the GTO Apoapsis precisely on target
// Satellite needs to have both forward and backward facing RCS thrusters
FUNCTION GTOApoapsisCorrection {
	PARAMETER RcsForRotation IS FALSE.

	// Check if correction is needed
	IF ABS(SHIP:APOAPSIS - StationaryOrbitAltitude()) > 500 {

		// Get prograde velocity
		LOCAL dir IS SHIP:VELOCITY:ORBIT.

		// Steer towards prograde
		LOCK STEERING TO LOOKDIRUP(dir, SHIP:FACING:TOPVECTOR).

		// Turn RCS on if required
		IF RcsForRotation { RCS ON. }

		// Wait for the steering to settle on target
		WAIT UNTIL VANG(SHIP:FACING:VECTOR, dir) < 0.01 AND (SHIP:ANGULARVEL:MAG < 0.01).
		WAIT 5.

		RCS ON.
		// Check which way to go and execute the correction maneuver
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

// Match the orbital period perfectly with the desired orbital period
// This should only be executed when the periods are already quite close to each other (after maneuver)
FUNCTION OrbitalPeriodCorrection {
	PARAMETER desiredPeriod.

	// Get all parts and part module information ready
	LOCAL allParts IS SHIP:PARTS.
	LOCAL thrusters IS LIST().

	FOR p IN allPARTS {
		IF p:HASMODULE("ModuleRCSFX") { thrusters:ADD(p:GETMODULE("ModuleRCSFX")). }
	}

	// Get prograde velocity
	LOCAL dir IS SHIP:VELOCITY:ORBIT.

	// Steer towards prograde
	LOCK STEERING TO LOOKDIRUP(dir, SHIP:FACING:TOPVECTOR).

	// Wait for the steering to settle on target
	WAIT UNTIL VANG(SHIP:FACING:VECTOR, dir) < 0.01 AND (SHIP:ANGULARVEL:MAG < 0.01).
	WAIT 5.

	// Sets the thrust limit of all RCS parts for extra fine control
	FUNCTION SetRCSLimitTo {
		PARAMETER limit IS 100.

		FOR t IN thrusters {
			IF t:HASFIELD("thrust limiter") { t:SETFIELD("thrust limiter", limit). }
		}
	}

	RCS ON.
	// Check which way to go and execute the correction maneuver
	IF OBT:PERIOD < desiredPeriod {
		SET SHIP:CONTROL:FORE TO 1.
		WAIT UNTIL OBT:PERIOD >= desiredPeriod-10.
		SET SHIP:CONTROL:FORE TO 0.2.
		WAIT UNTIL OBT:PERIOD >= desiredPeriod-1.
		SET SHIP:CONTROL:FORE TO 0.1.
		WAIT UNTIL OBT:PERIOD >= desiredPeriod-0.1.
		SetRCSLimitTo(5).
		WAIT UNTIL OBT:PERIOD >= desiredPeriod-0.01.
		SetRCSLimitTo(0.5).
		WAIT UNTIL OBT:PERIOD >= desiredPeriod.
		SET SHIP:CONTROL:FORE TO 0.
	} ELSE {
		SET SHIP:CONTROL:FORE TO -1.
		WAIT UNTIL OBT:PERIOD <= desiredPeriod+10.
		SET SHIP:CONTROL:FORE TO -0.2.
		WAIT UNTIL OBT:PERIOD <= desiredPeriod+1.
		SET SHIP:CONTROL:FORE TO -0.1.
		WAIT UNTIL OBT:PERIOD <= desiredPeriod+0.1.
		SetRCSLimitTo(5).
		WAIT UNTIL OBT:PERIOD <= desiredPeriod+0.01.
		SetRCSLimitTo(0.5).
		WAIT UNTIL OBT:PERIOD <= desiredPeriod.
		SET SHIP:CONTROL:FORE TO 0.
	}

	RCS OFF.
	SetRCSLimitTo(100).
}

// Returns the delta v necessary to move to specified longitude as well as number of orbits
// to wait in the lower/higher orbit and the temporary orbital period. Only really meant for GTO sats
FUNCTION MoveToLongitudeDv {
	PARAMETER lngInitial, lngFinal, altFinal, maxDv, passHeight IS "any".

	// Make sure the deltaV budget is > 0
	IF maxDv <= 0 { RETURN LEXICON("deltaV", 0, "orbits", 0, "period", 0). }

	// If no pass height specified the figure out the best one
	IF passHeight = "any" {
		LOCAL diff IS lngFinal-lngInitial.
		IF diff > 0 {
			IF ABS(diff) > 180 {
				SET passHeight TO "under".
			} ELSE {
				SET passHeight TO "over".
			}
		} ELSE IF diff < 0 {
			IF ABS(diff) > 180 {
				SET passHeight TO "over".
			} ELSE {
				SET passHeight TO "under".
			}
		}
	}

	// Track number of orbits for thie calculations below
	LOCAL orbits IS 1.
	// Calculate the orbital period of orbit before maneuvering
	LOCAL period IS PeriodAtSMA(altFinal + BODY:RADIUS).

	IF passHeight = "under" {
		UNTIL FALSE {
			// Calculate a new period, semi-major axis and periapsis
			LOCAL tempPeriod IS period-ABS(diff/orbits)/360*period.
			LOCAL smaRequired IS SMAWithPeriod(tempPeriod).
			LOCAL pgRequired IS smaRequired*2-BODY:RADIUS*2-altFinal.

			// Make sure the new periapsis is above the atmosphere
			IF pgRequired > BODY:ATM:HEIGHT + 25000 {
				// Calculate the orbital speeds
				LOCAL obtEcc IS OrbitalEccentricity(altFinal, pgRequired).
				LOCAL obtSpeedAtAP IS OrbitalSpeed(OrbitalRadius(0, altFinal + BODY:RADIUS, 0), altFinal + BODY:RADIUS).
				LOCAL newObtSpeedAtAP IS OrbitalSpeed(OrbitalRadius(0, smaRequired, obtEcc), smaRequired).
				LOCAL velDiff IS newObtSpeedAtAP - obtSpeedAtAP.
				// If change in velocity is below the max level, return the results
				IF ABS(velDiff) <= maxDv/2 {
					RETURN LEXICON("deltaV", velDiff, "orbits", orbits, "period", tempPeriod).
				}
			}
			// If this calculation did not pass then add another orbit and try again
			SET orbits TO orbits+1.
		}
	} ELSE IF passHeight = "over" {
		UNTIL FALSE {
			// Calculate a new period, semi-major axis and apoapsis
			LOCAL tempPeriod IS period+ABS(diff/orbits)/360*period.
			LOCAL smaRequired IS SMAWithPeriod(tempPeriod).
			LOCAL apRequired IS smaRequired*2-BODY:RADIUS*2-altFinal.

			// Make sure the new apoapsis is within the sphere of influence
			IF apRequired < BODY:SOIRADIUS - BODY:RADIUS - 25000 {
				// Calculate the orbital speeds
				LOCAL obtEcc IS OrbitalEccentricity(altFinal, apRequired).
				LOCAL obtSpeedAtPE IS OrbitalSpeed(OrbitalRadius(0, altFinal + BODY:RADIUS, 0), altFinal + BODY:RADIUS).
				LOCAL newObtSpeedAtPE IS OrbitalSpeed(OrbitalRadius(0, smaRequired, obtEcc), smaRequired).
				LOCAL velDiff IS newObtSpeedAtPE - obtSpeedAtPE.
				// If change in velocity is below the max level, return the results
				IF ABS(velDiff) <= maxDv/2 {
					RETURN LEXICON("deltaV", velDiff, "orbits", orbits, "period", tempPeriod).
				}
			}
			// If this calculation did not pass then add another orbit and try again
			SET orbits TO orbits+1.
		}
	}
	// Incorrect papameters have been passed, return 0s
	RETURN LEXICON("deltaV", 0, "orbits", 0, "period", 0).
}

// Creates a maneuver to circularize the orbit at a specific time (usually time to apoapsis or equatorial nodes)
// If inclination change is also required then the maneuver has to be done at one of the equatorial nodes
FUNCTION CircularizationAt {
	PARAMETER timeToManeuver IS ETA:APOAPSIS, incRequired IS OBT:INCLINATION, overWaypoint IS FALSE.

	// If inclination change is required, make sure that maneuver will take place at equator
	LOCAL nodeType IS "NONE".
	IF incRequired <> OBT:INCLINATION {
		LOCAL timeToAN IS TimeToTrueAnomaly(TA_EquatorialAN()).
		LOCAL timeToDN IS TimeToTrueAnomaly(TA_EquatorialDN()).
		IF timeToManeuver < timeToAN + 30 AND timeToManeuver > timeToAN - 30 {
			SET nodeType TO "AN".
		} ELSE IF timeToManeuver < timeToDN + 30 AND timeToManeuver > timeToDN - 30 {
			SET nodeType TO "DN".
		} ELSE {
			HUDTEXT("kOS: INCLINATION CHANGE MUST BE DONE AT EQUATORIAL NODE.", 30, 2, 20, RED, FALSE).
			RETURN FALSE.
		}
	}

	// Determine the type of overWaypoint parameter provided
	LOCAL long IS -1.
	LOCAL lngMnv IS FALSE.
	IF overWaypoint:ISTYPE("String") {
		SET long TO WAYPOINT(overWaypoint):GEPOSITION:LNG.
	} ELSE IF overWaypoint:ISTYPE("geoCoordinates") {
		SET long TO overWaypoint:LNG.
	} ELSE IF overWaypoint:ISTYPE("Scalar") {
		SET long TO MOD(overWaypoint, 360).
	}
	
	// Save the current time in case it changes during the calculations
	LOCAL t IS TIME:SECONDS.

	// Get position and velocity at the maneuver
	LOCAL mnvPos IS POSITIONAT(SHIP, t+timeToManeuver).
	LOCAL mnvVel IS VELOCITYAT(SHIP, t+timeToManeuver):ORBIT.

	// Find the radius at maneuver position and speed once in circular orbit
	LOCAL radiusAtMnv IS BODY:ALTITUDEOF(mnvPos)+BODY:RADIUS.
	LOCAL desiredSpeed IS OrbitalSpeed(radiusAtMnv, radiusAtMnv).

	// Check whether we need to change the maneuver to arrive at a specific waypoint
	IF long <> -1 {
		LOCAL lngInitial IS MOD(BODY:GEOPOSITIONOF(mnvPos):LNG + 360*(BODY:ROTATIONPERIOD/timeToManeuver),360).
		SET lngMnv TO MoveToLongitudeDv(lngInitial, long, BODY:ALTITUDEOF(mnvPos), 500, "under").
		SET desiredSpeed TO desiredSpeed + lngMnv["deltaV"].
	}

	// Calculate the prograde direction and the velocity of circular orbit
	LOCAL progradeAtMnv IS VXCL(mnvPos - BODY:POSITION, mnvVel):NORMALIZED.
	LOCAL desiredVelocity IS progradeAtMnv * desiredSpeed.

	// If we are also doing inclination change, rotate the final velocity vector to the inclination we want
	IF nodeType <> "NONE" {
		// Find axis of rotation of the velocity vector
		LOCAL radialAtManeuver IS (mnvPos-BODY:POSITION):NORMALIZED.
		// Based on node type, decide if the axis should be pointing towards or away from the planet
		IF nodeType = "DN" { SET radialAtManeuver TO -radialAtManeuver. }

		// Calculate the velocity vector of the final orbit at the maneuver 
		SET desiredVelocity TO Rodrigues(desiredVelocity, radialAtManeuver, ABS(incRequired - OBT:INCLINATION)).
	}

	// Calculate change in velocity needed
	LOCAL velocityDelta IS desiredVelocity - mnvVel.
	// Create a maneuver node with the desired velocity change
	LOCAL maneuverNode IS NodeFromVector(velocityDelta, t+timeToManeuver).
	// Add maneuver to the flight path
	ADD maneuverNode.

	WAIT 0.
	IF HASNODE {
		IF lngMnv <> FALSE AND lngMNV:period <> 0 { RETURN lngMnv. }
		RETURN TRUE.
	}
	RETURN FALSE.
}

// Creates a maneuver to match the orbital plane with your selected target
FUNCTION MatchInclinationWithTarget {
	// Make sure a tarket has been selected
	IF NOT HASTARGET { RETURN 0. }
	// Make sure that the target is either a vessel or a body
	IF NOT TARGET:ISTYPE("Vessel") AND NOT TARGET:ISTYPE("Body") { RETURN 0. }
	// Make sure that your target is orbiting the same body as your ship
	IF NOT TARGET:HASBODY OR TARGET:BODY <> SHIP:BODY { RETURN 0. }

	// Save the current time in case it changes during the calculations
	LOCAL t IS TIME:SECONDS.

	// Get the relative inclination between your orbit and targets orbit
	LOCAL relativeInc IS RelativeInclinationTo(TARGET).
	// If relative inclination is within 0.1 degree, just return as we're already matched
	IF relativeInc < 0.1 { RETURN FALSE. }

	// Calculate time to AN and DN
	LOCAL timeToAN IS TimeToTrueAnomaly(TA_RelativeAN()).
	LOCAL timeToDN IS TimeToTrueAnomaly(TA_RelativeDN()).

	LOCAL timeToNode IS timeToAN.
	LOCAL nodeType IS "AN".

	// Select whether to do the maneuver at AN or DN
	IF timeToAN < 60*4 {
		SET timeToNode TO timeToDN.
		SET nodeType TO "DN".
	} ELSE IF timeToDN < timeToAN AND timeToDN > 60*4  {
		SET timeToNode TO timeToDN.
		SET nodeType TO "DN".
	}

	// Get position and velocity at the maneuver
	LOCAL mnvPos IS POSITIONAT(SHIP, t+timeToNode).
	LOCAL mnvVel IS VELOCITYAT(SHIP, t+timeToNode):ORBIT.

	// Find axis of rotation of the velocity vector
	LOCAL radialAtManeuver IS (mnvPos-BODY:POSITION):NORMALIZED.
	// Based on node type, decide if the axis should be pointing towards or away from the planet
	IF nodeType = "DN" { SET radialAtManeuver TO -radialAtManeuver. }

	// Calculate the velocity vector of the final orbit at the maneuver 
	LOCAL desiredVelocity IS Rodrigues(mnvVel, radialAtManeuver, relativeInc).
	// Calculate change in velocity needed
	LOCAL velocityDelta IS desiredVelocity - mnvVel.
	// Create a maneuver node with the desired velocity change
	LOCAL maneuverNode IS NodeFromVector(velocityDelta, t+timeToNode).
	// Add maneuver to the flight path
	ADD maneuverNode.

	WAIT 0.
	IF HASNODE { RETURN TRUE. }
	RETURN FALSE.
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
	PARAMETER RCSRequired, addKACAlarm IS TRUE.
	
	LOCAL kacAlarmAdvance IS 30.

	LOCAL n IS NEXTNODE.
	LOCAL v IS n:BURNVECTOR.

	LOCAL startTime IS TIME:SECONDS + n:ETA - BurnTime(v:MAG/2).

	IF addKACAlarm AND ADDONS:AVAILABLE("KAC") {
		ADDALARM("Raw", startTime - kacAlarmAdvance, "Maneuver Alarm", SHIP:NAME + " has a scheduled maneuver in " + kacAlarmAdvance + " seconds.").
	}

	LOCK STEERING TO v.
	IF RCSRequired { RCS ON. }
	WAIT UNTIL VANG(SHIP:FACING:VECTOR, v) < 0.1 AND (SHIP:ANGULARVEL:MAG < 0.01).
	WAIT 5.
	HUDTEXT("kOS: Pointing at the Maneuver. Timewarp can be used.", 10, 2, 20, GREEN, FALSE).

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

// Execute the next node but use MechJeb for attitude control.
// kOS will notify the user that he needs to use MechJeb aim at the Maneuver Node
// This should be used for any vehicle that relies on RCS for its on-orbit attitude control.
FUNCTION ExecNodeMJ {
	PARAMETER RCSRequired, addKACAlarm IS TRUE.

	LOCAL kacAlarmAdvance IS 30.

	LOCAL n IS NEXTNODE.
	LOCAL v IS n:BURNVECTOR.

	LOCAL startTime IS TIME:SECONDS + n:ETA - BurnTime(v:MAG/2).

	IF addKACAlarm AND ADDONS:AVAILABLE("KAC") {
		ADDALARM("Raw", startTime - kacAlarmAdvance, "Maneuver Alarm", SHIP:NAME + " has a scheduled maneuver in " + kacAlarmAdvance + " seconds.").
	}
	
	IF RCSRequired { RCS ON. }
	UNTIL VANG(SHIP:FACING:VECTOR, v) < 0.1 AND (SHIP:ANGULARVEL:MAG < 0.01) {
		HUDTEXT("kOS: Use MechJeb to point at the Maneuver Node.", 1, 2, 20, RED, FALSE).
		WAIT 1.
	}
	WAIT 5.
	HUDTEXT("kOS: Pointing at the Maneuver. Timewarp can be used.", 10, 2, 20, GREEN, FALSE).

	WAIT UNTIL TIME:SECONDS >= startTime -5.
	SET SHIP:CONTROL:FORE TO 1.
	WAIT UNTIL TIME:SECONDS >= startTime.
	SET SHIP:CONTROL:FORE TO 0.
	LOCK STEERING TO v.
	LOCK THROTTLE TO MAX(MIN(BurnTime(n:BURNVECTOR:MAG)/2, 1),0.05).
	WAIT UNTIL VDOT(n:BURNVECTOR, v) < 0.
	LOCK THROTTLE TO 0.
	UNLOCK STEERING.
	RCS OFF.
}