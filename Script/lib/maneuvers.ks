@LAZYGLOBAL OFF.

// Time to complete a maneuver
FUNCTION BurnTime {
	PARAMETER dv.
	LOCAL ens IS LIST().
	ens:CLEAR.
	LOCAL ens_thrust IS 0.
	LOCAL ens_isp IS 0.
	LOCAL myengines IS LIST().
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
	PARAMETER altitudeIn.
	PARAMETER obtBody IS OBT:BODY.

	RETURN SQRT(obtBody:MU/(obtBody:RADIUS+altitudeIn)).
}

// Delta v requirements for Hohmann Transfer
FUNCTION SimpleHohmanDv {
	PARAMETER desiredAltitude.

	LOCAL u  IS SHIP:OBT:BODY:MU.
	LOCAL r1 IS SHIP:OBT:SEMIMAJORAXIS.
	LOCAL r2 IS desiredAltitude + SHIP:OBT:BODY:RADIUS.

	// v1
	LOCAL v1 IS SQRT(u / r1) * (SQRT((2 * r2) / (r1 + r2)) - 1).

	// v2
	LOCAL v2 IS SQRT(u / r2) * (1 - SQRT((2 * r1) / (r1 + r2))).

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

// Create a maneuver node for changing apoapsis
FUNCTION ApoapsisChange {
	PARAMETER desiredAp, mnvEta.

	// Get the spacecrafts position vector at maneuver
	LOCAL posAtMnv IS POSITIONAT(SHIP, TIME:SECONDS + mnvEta).
	// Get the spacecrafts velocity vector at maneuver
	LOCAL velAtMnv IS VELOCITYAT(SHIP, TIME:SECONDS + mnvEta):ORBIT.
	// Get the spacecrafts altitude at maneuver. This will be the new orbits Periapsis
	LOCAL altAtMnv IS BODY:ALTITUDEOF(posAtMnv).

	// Calculate the Semi-Major Axis of the new orbit
	LOCAL MNV_SMA IS (desiredAp + altAtMnv)/2 + BODY:RADIUS.
	// Calculate the Eccentricity of the new orbit
	LOCAL MNV_ECC IS OrbitalEccentricity(desiredAp, altAtMnv).

	// Calculate the spacecrafts speed at the Periapsis of the new orbit
	LOCAL MNV_SpeedAtPe IS OrbitalSpeed(OrbitalRadius(0, MNV_SMA, MNV_ECC), MNV_SMA).
	// Calculate the prograde vector of the spacecraft at the Periapsis of the new orbit
	LOCAL MNV_ProgradeAtPe IS VXCL(posAtMnv - BODY:POSITION, velAtMnv):NORMALIZED.
	// Multiply the prograde vector by the speed to get the velocity vector at Periapsis of the new orbit
	LOCAL MNV_VelocityAtPe IS MNV_ProgradeAtPe * MNV_SpeedAtPe.

	// Calculate the required change in velocity for the maneuver
	LOCAL MNV_ManeuverDeltaV IS MNV_VelocityAtPe - velAtMnv.

	// Create the maneuver node
	LOCAL maneuverNode IS NodeFromVector(MNV_ManeuverDeltaV, TIME:SECONDS + mnvEta).
	// Add the maneuver node to the flight path
	ADD maneuverNode.

	WAIT 0.
	IF HASNODE { RETURN TRUE. }
	RETURN FALSE.
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
	IF timeToEq < 60*5 { SET timeToEq TO MAX(timeToAN, timeToDN). }

	RETURN ApoapsisChange(desiredAp, timeToEq).
}

// Create a maneuver node for a Molniya Orbit
FUNCTION MolniyaOrbit {
	PARAMETER ArgOfPe IS 270.

	// Time to maneuver
	LOCAL MNV_TA IS MOD(ArgOfPe - OBT:ARGUMENTOFPERIAPSIS + 360, 360).
	LOCAL timeToMnv IS TimeToTrueAnomaly(MNV_TA).
	IF timeToMnv < 60*5 { SET timeToMnv TO timeToMnv + OBT:PERIOD. }

	// Calculate the desired orbital period. For Molniya orbit this should be half of the siderial day
	LOCAL desiredPeriod IS BODY:ROTATIONPERIOD/2.

	// Get the spacecrafts position vector at maneuver
	LOCAL posAtMnv IS POSITIONAT(SHIP, TIME:SECONDS + timeToMnv).
	// Get the spacecrafts altitude at maneuver. This will be the new orbits Periapsis
	LOCAL altAtMnv IS BODY:ALTITUDEOF(posAtMnv).
	// Get the new orbits Semi-Major Axis
	LOCAL MNV_SMA IS SMAWithPeriod(desiredPeriod).
	// Calculate the diesired Apoapsis.
	LOCAL desiredAp IS MNV_SMA * 2 - altAtMnv - BODY:RADIUS * 2.

	RETURN ApoapsisChange(desiredAp, timeToMnv).
}

// Create a maneuver node for a Tundra Orbit
FUNCTION TundraOrbit {
	PARAMETER ArgOfPe IS 270.

	// Time to maneuver
	LOCAL MNV_TA IS MOD(ArgOfPe - OBT:ARGUMENTOFPERIAPSIS + 360, 360).
	LOCAL timeToMnv IS TimeToTrueAnomaly(MNV_TA).
	IF timeToMnv < 60*5 { SET timeToMnv TO timeToMnv + OBT:PERIOD. }

	// Calculate the desired orbital period. For Tundra orbit this should be half of the siderial day
	LOCAL desiredPeriod IS BODY:ROTATIONPERIOD.

	// Get the spacecrafts position vector at maneuver
	LOCAL posAtMnv IS POSITIONAT(SHIP, TIME:SECONDS + timeToMnv).
	// Get the spacecrafts altitude at maneuver. This will be the new orbits Periapsis
	LOCAL altAtMnv IS BODY:ALTITUDEOF(posAtMnv).
	// Get the new orbits Semi-Major Axis
	LOCAL MNV_SMA IS SMAWithPeriod(desiredPeriod).
	// Calculate the diesired Apoapsis.
	LOCAL desiredAp IS MNV_SMA * 2 - altAtMnv - BODY:RADIUS * 2.

	RETURN ApoapsisChange(desiredAp, timeToMnv).
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
		UNLOCK STEERING.
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
	WAIT UNTIL VANG(SHIP:FACING:VECTOR, dir) < 0.1 AND (SHIP:ANGULARVEL:MAG < 0.01).
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
	UNLOCK STEERING.
	RCS OFF.
	SetRCSLimitTo(100).
}

// Returns the delta v necessary to move to specified longitude as well as number of orbits
// to wait in the lower/higher orbit and the temporary orbital period. Only really meant for GTO sats
FUNCTION MoveToLongitudeDv {
	PARAMETER lngInitial, lngFinal, altFinal, maxDv, tempOrbit IS "any".

	// Make sure the deltaV budget is > 0
	IF maxDv <= 0 { RETURN LEXICON("deltaV", 0, "orbits", 0, "period", 0). }

	LOCAL diffUnder IS MOD((lngFinal+360)-(lngInitial+360), 360).
	LOCAL diffOver IS MOD((lngInitial+360)-(lngFinal+360), 360).

	// Data for under and over maneuver types
	LOCAL underData IS LEXICON("deltaV", 0, "orbits", 0, "period", 0).
	LOCAL overData IS LEXICON("deltaV", 0, "orbits", 0, "period", 0).

	// Track number of orbits for thie calculations below
	LOCAL orbitsUnder IS 1.
	LOCAL orbitsOver IS 1.
	// Calculate the orbital period of orbit before maneuvering
	LOCAL period IS PeriodAtSMA(altFinal + BODY:RADIUS).

	// Calculate the under orbit first
	UNTIL FALSE {
		// Calculate a new period, semi-major axis and periapsis
		LOCAL tempPeriod IS period-ABS(MOD(diffUnder+360, 360))/360*period/orbitsUnder.
		LOCAL smaRequired IS SMAWithPeriod(tempPeriod).
		LOCAL peRequired IS smaRequired*2-BODY:RADIUS*2-altFinal.

		// Make sure the new periapsis is above the atmosphere
		IF peRequired > BODY:ATM:HEIGHT + 25000 {
			// Calculate the orbital speeds
			LOCAL obtEcc IS OrbitalEccentricity(altFinal, peRequired).
			LOCAL obtSpeedAtAP IS OrbitalSpeed(OrbitalRadius(0, altFinal + BODY:RADIUS, 0), altFinal + BODY:RADIUS).
			LOCAL newObtSpeedAtAP IS OrbitalSpeed(OrbitalRadius(180, smaRequired, obtEcc), smaRequired).
			LOCAL velDiff IS newObtSpeedAtAP - obtSpeedAtAP.
			// If change in velocity is below the max level, return the results
			IF ABS(velDiff) <= maxDv/2 {
				SET underData TO LEXICON("deltaV", velDiff, "orbits", orbitsUnder, "period", tempPeriod).
				BREAK.
			}
		}
		// If this calculation did not pass then add another orbit and try again
		SET orbitsUnder TO orbitsUnder+1.
	}
	// Calculate the over orbit first
	UNTIL FALSE {
		// Calculate a new period, semi-major axis and apoapsis
		LOCAL tempPeriod IS period+ABS(MOD(diffOver+360, 360))/360*period/orbitsOver.
		LOCAL smaRequired IS SMAWithPeriod(tempPeriod).
		LOCAL apRequired IS smaRequired*2-BODY:RADIUS*2-altFinal.

		// Make sure the new apoapsis is within the sphere of influence
		IF apRequired < BODY:SOIRADIUS - BODY:RADIUS - 25000 {
			// Calculate the orbital speeds
			LOCAL obtEcc IS OrbitalEccentricity(apRequired, altFinal).
			LOCAL obtSpeedAtPE IS OrbitalSpeed(OrbitalRadius(0, altFinal + BODY:RADIUS, 0), altFinal + BODY:RADIUS).
			LOCAL newObtSpeedAtPE IS OrbitalSpeed(OrbitalRadius(0, smaRequired, obtEcc), smaRequired).
			LOCAL velDiff IS newObtSpeedAtPE - obtSpeedAtPE.
			// If change in velocity is below the max level, return the results
			IF ABS(velDiff) <= maxDv/2 {
				SET overData TO LEXICON("deltaV", velDiff, "orbits", orbitsOver, "period", tempPeriod).
				BREAK.
			}
		}
		// If this calculation did not pass then add another orbit and try again
		SET orbitsOver TO orbitsOver+1.
	}
	IF tempOrbit = "over" { RETURN overData. }
	ELSE IF tempOrbit = "under" { RETURN underData. }
	ELSE IF tempOrbit = "any" {
		IF orbitsUnder < orbitsOver { RETURN underData. }
		ELSE IF orbitsUnder > orbitsOver { RETURN overData. }
		ELSE {
			IF underData:deltaV < overData:deltaV { RETURN underData. }
			ELSE { RETURN overData. }
		}
	}
	// Incorrect parameters have been passed, return 0s
	RETURN LEXICON("deltaV", 0, "orbits", 0, "period", 0).
}

// Calculates the initial maneuver that will get you a closest approach to target
// Assumes that you already matched your inclination with target
FUNCTION ManeuverToClosestApproach {
	// Make sure a target has been selected
	IF NOT HASTARGET { RETURN 0. }
	// Make sure that the target is either a vessel or a body
	IF NOT TARGET:ISTYPE("Vessel") { RETURN 0. }
	// Make sure that your target is orbiting the same body as your ship
	IF NOT TARGET:HASBODY OR TARGET:BODY <> SHIP:BODY { RETURN 0. }

	// Save the current time to use with all calculations
	LOCAL t IS TIME:SECONDS.

	// Get the closest approach lexicon
	LOCAL closestApproach IS GetClosestApproach().
	// Calculate how long will it take your target to get to the closest approach
	LOCAL targetEtaCA IS closestApproach:targetETA.
	// Get targets positiona at closest approach
	LOCAL targetCaPos IS POSITIONAT(TARGET, t+targetEtaCA).
	// Now calculate the time it will take us to get to the opposite side of closest approach
	LOCAL timeToMnvPos IS TimeToTrueAnomaly(TA_TargetToShip(closestApproach:targetTA+180)).

	// Now calculate the deltaV to change our orbit to the closest approach
	LOCAL mnvVel IS VELOCITYAT(SHIP, t+timeToMnvPos):ORBIT.
	LOCAL mnvPos IS POSITIONAT(SHIP, t+timeToMnvPos).
	LOCAL mnvPrograde IS VXCL(mnvPos - BODY:POSITION, mnvVel):NORMALIZED.
	LOCAL transferSMA IS (BODY:ALTITUDEOF(mnvPos)+BODY:ALTITUDEOF(targetCaPos)+BODY:RADIUS*2)/2.
	LOCAL transferPeriod IS PeriodAtSMA(transferSMA).
	LOCAL mnvEndSpeed IS OrbitalSpeed(BODY:ALTITUDEOF(mnvPos)+BODY:RADIUS, transferSMA).
	LOCAL mnvDv IS mnvPrograde*mnvEndSpeed - mnvVel.

	// Calculate in how many orbits we'll need to execute this maneuver
	LOCAL orbits IS 0.
	// Make a copy of targets ETA to Closest approach for use in calculations below
	LOCAL targetToCA IS targetEtaCA.
	IF transferPeriod < TARGET:OBT:PERIOD {
		// If our ship gets to the closest approach before the target, then we need to do our maneuver at the next close approach
		UNTIL targetToCA < (timeToMnvPos + transferPeriod/2) { SET targetToCA TO targetToCA - TARGET:OBT:PERIOD. PRINT "TEST". }
	} ELSE {
		// If our ship gets to the closest approach before the target, then we need to do our maneuver at the next close approach
		UNTIL targetToCA > (timeToMnvPos + transferPeriod/2) { SET targetToCA TO targetToCA + TARGET:OBT:PERIOD. }
	}
	LOCAL targetCaArrivalDiff IS targetToCA - (timeToMnvPos + transferPeriod/2).
	PRINT ROUND(targetCaArrivalDiff).

	// Depending on whether our transfer orbit period will be lower or higher,
	// than our targets orbital period, use an appropraite condition in the loop below
	LOCAL condition IS { RETURN targetCaArrivalDiff > 0. }.
	IF transferPeriod > TARGET:OBT:PERIOD { SET condition TO { RETURN targetCaArrivalDiff < 0. }. }

	// Keep adding 1 orbit untill we find the lowest negative/positive time delta (depending on current orbits).
	UNTIL condition() {
		SET orbits TO orbits + 1.
		SET targetCaArrivalDiff TO (targetToCA + TARGET:OBT:PERIOD * orbits) - (timeToMnvPos + transferPeriod/2 + OBT:PERIOD * orbits).
	}
	SET orbits TO orbits - 1.
	// Now get the final eta to maneuver
	LOCAL mnvEta IS timeToMnvPos + OBT:PERIOD * orbits.
	// Create a maneuver node for the transfer burn
	LOCAL transferBurn IS NodeFromVector(mnvDv, t+mnvEta).
	ADD transferBurn.
	
	WAIT 0.
	IF HASNODE { RETURN TRUE. }
	RETURN FALSE.
}

// Fine tune the closest approach by calculating a target orbital period that will end in an intercept
// after one full orbit. Intecept in this case means a closest approach with very small separation
FUNCTION FineTuneClosestApproach {
	// Make sure a tarket has been selected
	IF NOT HASTARGET { RETURN 0. }
	// Make sure that the target is either a vessel or a body
	IF NOT TARGET:ISTYPE("Vessel") { RETURN 0. }
	// Make sure that your target is orbiting the same body as your ship
	IF NOT TARGET:HASBODY OR TARGET:BODY <> SHIP:BODY { RETURN 0. }

	// Get closest approach data
	LOCAL closestApproach IS GetClosestApproach().

	// Get targets ETA to the closest approach on it's next orbit pass
	LOCAL targetEtaToCA IS closestApproach:targetETA + TARGET:OBT:PERIOD.
	// Calculate what orbital period we should have to intercept target at next orbit and get SMA with that period
	LOCAL desiredObtPeriod IS targetEtaToCA - closestApproach:ETA.
	LOCAL desiredObtSMA IS SMAWithPeriod(desiredObtPeriod).

	// Get position and velocity at the closest approach maneuver
	LOCAL mnvVel IS VELOCITYAT(SHIP, TIME:SECONDS+closestApproach:ETA):ORBIT.
	LOCAL mnvPos IS POSITIONAT(SHIP, TIME:SECONDS+closestApproach:ETA).

	// Calculate the velocity after the maneuver
	LOCAL desiredOrbitPrograde IS mnvVel:NORMALIZED.
	LOCAL desiredOrbitSpeed IS OrbitalSpeed(BODY:ALTITUDEOF(mnvPos) + BODY:RADIUS, desiredObtSMA).
	LOCAL desiredVelocity IS desiredOrbitPrograde * desiredOrbitSpeed.

	// Calculate the transfer delta velocity and create the maneuver node
	LOCAL mnvDeltaV IS desiredVelocity - mnvVel.		
	LOCAL maneuverNode IS NodeFromVector(mnvDeltaV, TIME:SECONDS + closestApproach:ETA).
	ADD maneuverNode.
	
	WAIT 0.
	IF HASNODE { RETURN TRUE. }
	RETURN FALSE.
}

// Once the closest approach is very close (<2.5km separation is recommended) Set up a maneuver to kill all the remaining relative velocity
// This maneuver completes the Randezvous
FUNCTION MatchVelocityWithTarget {
	// Make sure a tarket has been selected
	IF NOT HASTARGET { RETURN 0. }
	// Make sure that the target is either a vessel or a body
	IF NOT TARGET:ISTYPE("Vessel") { RETURN 0. }
	// Make sure that your target is orbiting the same body as your ship
	IF NOT TARGET:HASBODY OR TARGET:BODY <> SHIP:BODY { RETURN 0. }

	// Get closest approach data
	LOCAL closestApproach IS GetClosestApproach().

	// Get ETA to closest approach
	LOCAL mnvEta IS closestApproach:ETA.

	// Get separation at closest approach
	LOCAL mnvSep IS SeparationFromTargetAt(TIME:SECONDS+mnvEta).
	LOCAL nextObtSep IS SeparationFromTargetAt(TIME:SECONDS+mnvEta+OBT:PERIOD).
	IF nextObtSep < mnvSep { SET mnvEta TO mnvEta + OBT:PERIOD. }

	// Get our velocity and targets velocity at the maneuver
	LOCAL mnvVel IS VELOCITYAT(SHIP, TIME:SECONDS+mnvEta):ORBIT.
	LOCAL mnvTargetVel IS VELOCITYAT(TARGET, TIME:SECONDS+mnvEta):ORBIT.

	// Calculate the delta velocity and create the maneuver node
	LOCAL mnvDeltaV IS mnvTargetVel - mnvVel.
	LOCAL maneuverNode IS NodeFromVector(mnvDeltaV, TIME:SECONDS + mnvEta).
	ADD maneuverNode.
	
	WAIT 0.
	IF HASNODE { RETURN TRUE. }
	RETURN FALSE.
}

// Creates a maneuver to circularize the orbit at a specific time (usually time to apoapsis or equatorial nodes)
// If inclination change is also required then the maneuver has to be done at one of the equatorial nodes
FUNCTION CircularizationAt {
	PARAMETER timeToManeuver IS ETA:APOAPSIS, incRequired IS OBT:INCLINATION, overWaypoint IS FALSE.

	// Find the modulo of the time to maneuver
	LOCAL timeToManeuverMod IS MOD(timeToManeuver, OBT:PERIOD).

	// If inclination change is required, make sure that maneuver will take place at equator
	LOCAL nodeType IS "NONE".
	IF incRequired <> OBT:INCLINATION {
		LOCAL timeToAN IS TimeToTrueAnomaly(TA_EquatorialAN()).
		LOCAL timeToDN IS TimeToTrueAnomaly(TA_EquatorialDN()).
		IF timeToManeuverMod < timeToAN + 30 AND timeToManeuverMod > timeToAN - 30 {
			SET nodeType TO "AN".
		} ELSE IF timeToManeuverMod < timeToDN + 30 AND timeToManeuverMod > timeToDN - 30 {
			SET nodeType TO "DN".
		} ELSE {
			HUDTEXT("kOS: INCLINATION CHANGE MUST BE DONE AT EQUATORIAL NODE.", 30, 2, 20, RED, FALSE).
			RETURN LEXICON("deltaV", 0, "orbits", 0, "period", 0).
		}
	}

	// Determine the type of overWaypoint parameter provided
	LOCAL long IS -1.
	LOCAL lngMnv IS LEXICON("deltaV", 0, "orbits", 0, "period", 0).
	IF overWaypoint:ISTYPE("Waypoint") {
		SET long TO overWaypoint:GEOPOSITION:LNG.
	} ELSE IF overWaypoint:ISTYPE("String") {
		SET long TO WAYPOINT(overWaypoint):GEOPOSITION:LNG.
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
		LOCAL lngInitial IS MOD(BODY:GEOPOSITIONOF(mnvPos):LNG - 360*(timeToManeuverMod/BODY:ROTATIONPERIOD),360).
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
		IF lngMNV:deltaV <> 0 { RETURN lngMnv. }
	}
	IF lngMNV:deltaV <> 0 { RETURN lngMnv. }
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

	// Get position and velocity at the maneuver
	LOCAL mnvPos IS POSITIONAT(SHIP, t+timeToNode).
	LOCAL mnvVel IS VELOCITYAT(SHIP, t+timeToNode):ORBIT.

	// Estimated maneuver time
	LOCAL mnvTime IS BurnTime(SimplePlaneChangeDv(mnvVel, TARGET:OBT:INCLINATION, OBT:INCLINATION)).

	// Select whether to do the maneuver at AN or DN
	IF timeToAN < mnvTime + 60*2 {
		SET timeToNode TO timeToDN.
		SET nodeType TO "DN".
	} ELSE IF timeToDN < timeToAN AND timeToDN > mnvTime + 60*2  {
		SET timeToNode TO timeToDN.
		SET nodeType TO "DN".
	}

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

// Rodrigues vector rotation formula - Borrowed from PEGAS
FUNCTION Rodrigues {
	PARAMETER inVector. //  Expects a vector
	PARAMETER axis.   //  Expects a vector
	PARAMETER angle.  //  Expects a scalar

	SET axis TO axis:NORMALIZED.

	LOCAL outVector IS inVector*COS(angle).
	SET outVector TO outVector + VCRS(axis, inVector)*SIN(angle).
	SET outVector TO outVector + axis*VDOT(axis, inVector)*(1-COS(angle)).

	RETURN outVector.
}

// Execute the next node
FUNCTION ExecNode {
	PARAMETER RCSRequired, removeNode IS TRUE, addKACAlarm IS TRUE.
	
	SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.

	LOCAL kacAlarmAdvance IS 30.

	LOCAL n IS NEXTNODE.
	LOCAL v IS n:BURNVECTOR.

	LOCAL startTime IS TIME:SECONDS + n:ETA - BurnTime(v:MAG/2).

	// This will create an alarm 30 seconds before the maneuver needs to begin
	IF addKACAlarm AND ADDONS:AVAILABLE("KAC") {
		IF n:ETA > 600 {
			LOCAL attAlarm IS ADDALARM("Raw", startTime - 600, "Maneuver Alarm - Attitude Adjustment", SHIP:NAME + " has a scheduled maneuver in 10 minutes. Time to point at the Maneuver Node.").
			SET attAlarm:ACTION TO "KillWarpOnly".
			HUDTEXT("kOS: Timewarp can be used.", 10, 2, 20, GREEN, FALSE).
		}
		LOCAL mnvAlarm IS ADDALARM("Raw", startTime - kacAlarmAdvance, "Maneuver Alarm", SHIP:NAME + " has a scheduled maneuver in " + kacAlarmAdvance + " seconds.").
		SET mnvAlarm:ACTION TO "KillWarpOnly".
	}

	IF addKACAlarm { WAIT UNTIL TIME:SECONDS >= startTime - 600. }

	SAS OFF.
	LOCK STEERING TO LOOKDIRUP(v, SHIP:FACING:TOPVECTOR).
	SET steeringLocked TO TRUE.
	IF RCSRequired { RCS ON. }
	UNTIL VANG(SHIP:FACING:VECTOR, v) < 0.1 AND (SHIP:ANGULARVEL:MAG < 0.01) {
		HUDTEXT("kOS: Pointing at the Maneuver Node.", 1, 2, 20, RED, FALSE).
		HUDTEXT("kOS: V Ang Error - " + ROUND(VANG(SHIP:FACING:VECTOR, v),3) + " vs 0.1.", 1, 1, 20, RED, FALSE).
		HUDTEXT("kOS: V Vel Error - " + ROUND(SHIP:ANGULARVEL:MAG,3) + " vs 0.01.", 1, 1, 20, RED, FALSE).
		WAIT 1.
	}
	WAIT 5.
	HUDTEXT("kOS: Pointing at the Maneuver. Timewarp can be used.", 10, 2, 20, GREEN, FALSE).

	WAIT UNTIL TIME:SECONDS >= startTime -5.
	SET SHIP:CONTROL:FORE TO 1.
	WAIT UNTIL TIME:SECONDS >= startTime.
	SET SHIP:CONTROL:FORE TO 0.
	LOCK THROTTLE TO MAX(MIN(BurnTime(n:BURNVECTOR:MAG)/2, 1),0.05).
	LOCAL originalEpsilons IS LIST(STEERINGMANAGER:TORQUEEPSILONMIN, STEERINGMANAGER:TORQUEEPSILONMAX).
	SET STEERINGMANAGER:TORQUEEPSILONMAX TO 0.
	UNTIL VDOT(n:BURNVECTOR, v) < 0 {
		IF KUNIVERSE:TIMEWARP:WARP <> 0 AND KUNIVERSE:TIMEWARP:MODE = "RAILS" AND steeringLocked {
			SET steeringLocked TO FALSE.
			UNLOCK STEERING.
		} ELSE IF (KUNIVERSE:TIMEWARP:MODE <> "RAILS" OR KUNIVERSE:TIMEWARP:WARP = 0) AND NOT steeringLocked {
			SET steeringLocked TO TRUE.
			LOCK STEERING TO LOOKDIRUP(v, SHIP:FACING:TOPVECTOR).
		}
	}
	LOCK THROTTLE TO 0.
	SET STEERINGMANAGER:TORQUEEPSILONMIN TO originalEpsilons[0].
	SET STEERINGMANAGER:TORQUEEPSILONMAX TO originalEpsilons[1].
	UNLOCK STEERING.
	RCS OFF.
	IF removeNode { REMOVE n. }
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
	UNTIL VANG(SHIP:FACING:VECTOR, v) < 0.1 AND (SHIP:ANGULARVEL:MAG < 0.05) {
		HUDTEXT("kOS: Use MechJeb to point at the Maneuver Node.", 1, 2, 20, RED, FALSE).
		HUDTEXT("kOS: V Ang Error - " + ROUND(VANG(SHIP:FACING:VECTOR, v),3) + " vs 0.1.", 1, 2, 20, RED, FALSE).
		HUDTEXT("kOS: V Vel Error - " + ROUND(SHIP:ANGULARVEL:MAG,3) + " vs 0.05.", 1, 2, 20, RED, FALSE).
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