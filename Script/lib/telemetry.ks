@LAZYGLOBAL OFF.

// Gravity acceleration
FUNCTION Gravity {
	PARAMETER a IS SHIP:ALTITUDE.
	PARAMETER b IS SHIP:OBT:BODY.
	RETURN b:MU / (b:RADIUS + a)^2.
}

// Current thrust to weight ratio
FUNCTION ShipCurrentTWR {
	RETURN ShipActiveThrust() / SHIP:MASS / Gravity(SHIP:ALTITUDE).
}

// Ships maximum thrust to weight ratio
FUNCTION ShipTWR {
	RETURN SHIP:MAXTHRUST / SHIP:MASS / Gravity(SHIP:ALTITUDE).
}

// Active thrust of the ship at this moment
FUNCTION ShipActiveThrust {
	LOCAL activeThrust IS 0.
	LOCAL allEngines IS 0.
	LIST ENGINES IN allEngines.
	FOR engine IN allEngines {
		IF engine:IGNITION {
		SET activeThrust TO activeThrust + engine:THRUST.
		}
	}
	RETURN activeThrust.
}

// Time to get to altitude in freefall
FUNCTION TimeToAltitude {
	PARAMETER desiredAltitude.
	PARAMETER currentAltitude.

	IF currentAltitude-desiredAltitude <= 0 {
		RETURN 0.
	}
	RETURN (-VERTICALSPEED - SQRT( (VERTICALSPEED*VERTICALSPEED)-(2 * (-Gravity(currentAltitude)) * (currentAltitude - desiredAltitude))) ) /  ((-Gravity(currentAltitude))).
}

// Use hill-climbing algorithm to find the closest time when spacecrafts altitude will cross the provided value
// You should provide an optional timestamp value, otherwise current time will be used
// When you want to circularize at a certain altitude in a few orbits time, pass an estimated time in to get the precise time
// WARNING: If the altitude specified is very close to either Apoapsis or Periapsis then this function may not always return
// time to the nearest pass through that altitude. If this is a problem, please reduce the step sizes
FUNCTION TimeAtOrbitAltitude {
	PARAMETER desiredAltitude, startTime IS TIME:SECONDS.

	// If desired altitude is above apoapsis or below periapsis, return the closest values instead
	IF desiredAltitude >= SHIP:APOAPSIS { RETURN TIME:SECONDS + ETA:APOAPSIS. }
	ELSE IF desiredAltitude <= SHIP:PERIAPSIS { RETURN TIME:SECONDS + ETA:PERIAPSIS. }

	// The step size in seconds
	LOCAL stepSize IS 10.

	// Track the best result
	LOCAL closestTime IS startTime.
	LOCAL closestTimeAltDiff IS ABS(desiredAltitude - BODY:ALTITUDEOF(POSITIONAT(SHIP, closestTime))).

	// Function that contains the loop which looks for specified altitude along the orbit
	FUNCTION FindTimeToAltitude {
		UNTIL FALSE {
			LOCAL positiveStepTime IS closestTime+stepSize.
			LOCAL negativeStepTime IS closestTime-stepSize.
			// Calculate the altitude after a positive step change and after a negative step change
			LOCAL positiveStepDiff IS ABS(desiredAltitude - BODY:ALTITUDEOF(POSITIONAT(SHIP, positiveStepTime))).
			LOCAL negativeStepDiff IS ABS(desiredAltitude - BODY:ALTITUDEOF(POSITIONAT(SHIP, negativeStepTime))).

			// Compare the altitude differences after steps with the previous best results
			IF positiveStepDiff < closestTimeAltDiff {
				SET closestTime TO positiveStepTime.
				SET closestTimeAltDiff TO positiveStepDiff.
			} ELSE IF negativeStepDiff < closestTimeAltDiff {
				SET closestTime TO negativeStepTime.
				SET closestTimeAltDiff TO negativeStepDiff.
			} ELSE {
				// If neither step brought us closer then we know that with this step size we got to the closest point
				BREAK.
			}
		}
	}
	FindTimeToAltitude().
	SET stepSize TO 1.
	FindTimeToAltitude().
	SET stepSize TO 0.1.
	FindTimeToAltitude().

	// Make sure that the time is in the future
	IF closestTime < TIME:SECONDS {
		RETURN TimeAtOrbitAltitude(desiredAltitude, closestTime + OBT:PERIOD).
	}

	RETURN closestTime.
}

// Calculates the vessels distance from the body (Radius) at the point specified by true anomaly
FUNCTION OrbitalRadius {
	PARAMETER trueAnomaly IS OBT:TRUEANOMALY, semiMajaorAxis IS OBT:SEMIMAJORAXIS, ecc IS OBT:ECCENTRICITY.

	RETURN (semiMajaorAxis*(1-ecc^2))/(1+ecc*COS(trueAnomaly)).
}

// Calculates the vessels flight path angle at the specified true anomaly
FUNCTION OrbitalFlightPathAngle {
	PARAMETER trueAnomaly IS OBT:TRUEANOMALY, ecc IS OBT:ECCENTRICITY.

	RETURN ARCTAN((ecc*SIN(trueAnomaly))/(1+ecc*COS(trueAnomaly))).
}

// Calculates the speed of the vessel at the point specified by current radius (altitude + body radius)
FUNCTION OrbitalSpeed {
	PARAMETER radius IS (BODY:RADIUS + OBT:ALTITUDE), semiMajaorAxis IS OBT:SEMIMAJORAXIS, orbitingBody IS OBT:BODY.

	RETURN SQRT(orbitingBody:MU*((2/radius)-(1/semiMajaorAxis))).
}

// Caclucate eccentricity from the Apoapsis, Periapsis and Body Radius
FUNCTION OrbitalEccentricity {
	PARAMETER ap IS SHIP:APOAPSIS, pe IS SHIP:PERIAPSIS, bodyRadius IS OBT:BODY:RADIUS.

	RETURN ((ap + bodyRadius) - (pe + bodyRadius)) / ((ap+bodyRadius) + (pe+bodyRadius)).
}

// Calculating Mean Anomaly from True Anomaly and Eccentricity
FUNCTION TrueToMean {
	PARAMETER trueAnomaly IS OBT:TRUEANOMALY, ecc IS OBT:ECCENTRICITY.

	// Calculate the Eccentric Anomaly first
	LOCAL EccAnomaly IS ARCCOS((ecc + COS(trueAnomaly))/(1+ecc*COS(trueAnomaly))).
	// Use Eccentric Anomaly to calculate the Mean Anomaly
	LOCAL MeanAnomaly IS CONSTANT:RadToDeg * (CONSTANT:DegToRad*EccAnomaly-ecc*SIN(EccAnomaly)).

	IF trueAnomaly > 180 {
		// Using above calculations, the mean anomaly only goes up to 180 and then starts going down again.
		// This makes sure that the returned value will still be going up past 180
		RETURN 360 - MeanAnomaly.
	} ELSE {
		RETURN MeanAnomaly.
	}
}

// Calculates the angle between two orbits AKA the "Relative Inclination"
FUNCTION AngleBetweenOrbits {
	PARAMETER inc1, lan1, inc2, lan2.

	// Magic below, do not touch it. Don't even look at it. It just works ¯\_(ツ)_/¯
	LOCAL a1 IS SIN(inc1) * COS(lan1).
	LOCAL a2 IS SIN(inc1) * SIN(lan1).
	LOCAL a3 IS COS(inc1).

	LOCAL b1 IS SIN(inc2) * COS(lan2).
	LOCAL b2 IS SIN(inc2) * SIN(lan2).
	LOCAL b3 IS COS(inc2).

	RETURN ARCCOS(a1*b1+a2*b2+a3*b3).
}

// Should point to a vessel or body orbiting the same body as your ship
FUNCTION RelativeInclinationTo {
	PARAMETER targetOrbitable.

	// Make sure that the target is either a vessel or a body
	IF NOT targetOrbitable:ISTYPE("Vessel") AND NOT targetOrbitable:ISTYPE("Body") { RETURN 0. }
	// Make sure that your target is orbiting the same body as your ship
	IF NOT targetOrbitable:HASBODY OR targetOrbitable:BODY <> SHIP:BODY { RETURN 0. }

	// Use the ships orbit infirmation and the targets body 
	RETURN AngleBetweenOrbits(OBT:INCLINATION, OBT:LAN, targetOrbitable:OBT:INCLINATION, targetOrbitable:OBT:LAN).
}

// Calculate the current GeoCoordinates of the relative descending node
FUNCTION DescendingNodeCoordinates {
	PARAMETER inc1, lan1, inc2, lan2, orbitingBody IS OBT:BODY.

	// Magic below, do not touch it. Don't even look at it. It just works ¯\_(ツ)_/¯
	LOCAL a1 IS SIN(inc1) * COS(lan1).
	LOCAL a2 IS SIN(inc1) * SIN(lan1).
	LOCAL a3 IS COS(inc1).

	LOCAL b1 IS SIN(inc2) * COS(lan2).
	LOCAL b2 IS SIN(inc2) * SIN(lan2).
	LOCAL b3 IS COS(inc2).

	LOCAL c1 IS a2*b3-a3*b2.
	LOCAL c2 IS a3*b1-a1*b3.
	LOCAL c3 IS a1*b2-a2*b1.

	LOCAL ang IS { IF c1 < 0 { RETURN 90. } ELSE { RETURN 270. } }.

	LOCAL lat IS ARCTAN(c3/sqrt(c1^2 + c2^2)).
	LOCAL lng IS MOD(ARCTAN(c2/c1) + ang() - orbitingBody:ROTATIONANGLE + 360,360).

	RETURN LATLNG(lat,lng).
}

// Calculate the current GeoCoordinates of the relative ascending node node
FUNCTION AscendingNodeCoordinates {
	PARAMETER inc1, lan1, inc2, lan2, orbitingBody IS OBT:BODY.

	// Use the function to find descending node first
	LOCAL DN IS DescendingNodeCoordinates(inc1, lan1, inc2, lan2, orbitingBody).

	// Calculate the opposite point on the planet from the descending node
	LOCAL AN IS LATLNG(-DN:LAT, MOD(DN:LNG + 180,360)).

	RETURN AN.
}

// Get the current GeoCoordinates of the relative descending node with target
FUNCTION RelativeDescendingNodeTo {
	PARAMETER targetOrbitable.

	// Make sure that the target is either a vessel or a body
	IF NOT targetOrbitable:ISTYPE("Vessel") AND NOT targetOrbitable:ISTYPE("Body") { RETURN 0. }
	// Make sure that your target is orbiting the same body as your ship
	IF NOT targetOrbitable:HASBODY OR targetOrbitable:BODY <> SHIP:BODY { RETURN 0. }

	// Use the ships orbit infirmation and the targets body 
	RETURN DescendingNodeCoordinates(OBT:INCLINATION, OBT:LAN, targetOrbitable:OBT:INCLINATION, targetOrbitable:OBT:LAN, OBT:BODY).
}

// Get the current GeoCoordinates of the relative ascending node with target
FUNCTION RelativeAscendingNodeTo {
	PARAMETER targetOrbitable.

	// Make sure that the target is either a vessel or a body
	IF NOT targetOrbitable:ISTYPE("Vessel") AND NOT targetOrbitable:ISTYPE("Body") { RETURN 0. }
	// Make sure that your target is orbiting the same body as your ship
	IF NOT targetOrbitable:HASBODY OR targetOrbitable:BODY <> SHIP:BODY { RETURN 0. }

	// Use the ships orbit infirmation and the targets body 
	RETURN AscendingNodeCoordinates(OBT:INCLINATION, OBT:LAN, targetOrbitable:OBT:INCLINATION, targetOrbitable:OBT:LAN, OBT:BODY).
}

// True anomaly of the equatorial ascending node
FUNCTION TA_EquatorialAN {
	RETURN MOD(360 - OBT:ARGUMENTOFPERIAPSIS, 360).
}

// True anomaly of the equatorial descending node
FUNCTION TA_EquatorialDN {
	RETURN MOD(540 - OBT:ARGUMENTOFPERIAPSIS, 360).
}

// True anomaly of the relative ascending node with target
FUNCTION TA_RelativeAN {
	// Make sure a tarket has been selected
	IF NOT HASTARGET { RETURN 0. }
	// Make sure that the target is either a vessel or a body
	IF NOT TARGET:ISTYPE("Vessel") AND NOT TARGET:ISTYPE("Body") { RETURN 0. }
	// Make sure that your target is orbiting the same body as your ship
	IF NOT TARGET:HASBODY OR TARGET:BODY <> SHIP:BODY { RETURN 0. }

	// Get Coordinates of the node
	LOCAL NodeCoordinates IS RelativeAscendingNodeTo(TARGET).

	// Find position of the node
	LOCAL NodePosition IS NodeCoordinates:ALTITUDEPOSITION(0).
	// Find position of your periapsis
	LOCAL PEPosition IS POSITIONAT(SHIP, TIME:SECONDS + ETA:PERIAPSIS).

	// Vector from center of the body to the node
	LOCAL NodeVec IS NodePosition - BODY:POSITION.
	// Vector from center of the body to the periapsis
	LOCAL PEVec IS PEPosition - BODY:POSITION.

	// Absolute angle between the two vectors
	LOCAL NodeTrueAnomaly IS VANG(NodeVec, PEVec).

	// Check whether the node is in front of periapsis or behind it
	IF VANG(VCRS(NodeVec, PEVec), VCRS(SHIP:POSITION-BODY:POSITION, SHIP:VELOCITY:ORBIT)) < 1 {
		SET NodeTrueAnomaly TO 360-NodeTrueAnomaly.
	}

	// Return the true anomaly of the node
	RETURN NodeTrueAnomaly.
}

// True anomaly of the relative descending node with target
FUNCTION TA_RelativeDN {
	// Make sure a tarket has been selected
	IF NOT HASTARGET { RETURN 0. }
	// Make sure that the target is either a vessel or a body
	IF NOT TARGET:ISTYPE("Vessel") AND NOT TARGET:ISTYPE("Body") { RETURN 0. }
	// Make sure that your target is orbiting the same body as your ship
	IF NOT TARGET:HASBODY OR TARGET:BODY <> SHIP:BODY { RETURN 0. }

	// Get Coordinates of the node
	LOCAL NodeCoordinates IS RelativeDescendingNodeTo(TARGET).

	// Find position of the node
	LOCAL NodePosition IS NodeCoordinates:ALTITUDEPOSITION(0).
	// Find position of your periapsis
	LOCAL PEPosition IS POSITIONAT(SHIP, TIME:SECONDS + ETA:PERIAPSIS).

	// Vector from center of the body to the node
	LOCAL NodeVec IS NodePosition - BODY:POSITION.
	// Vector from center of the body to the periapsis
	LOCAL PEVec IS PEPosition - BODY:POSITION.

	// Absolute angle between the two vectors
	LOCAL NodeTrueAnomaly IS VANG(NodeVec, PEVec).

	// Check whether the node is in front of periapsis or behind it
	IF VANG(VCRS(NodeVec, PEVec), VCRS(SHIP:POSITION-BODY:POSITION, SHIP:VELOCITY:ORBIT)) < 1 {
		SET NodeTrueAnomaly TO 360-NodeTrueAnomaly.
	}

	// Return the true anomaly of the node
	RETURN NodeTrueAnomaly.
}

// Converts our targets True Anomaly to our ships True Anomaly.
// Useful for rendezvous with a target etc.
FUNCTION TA_TargetToShip {
	PARAMETER trueAnomaly.
	// Make sure a target has been selected
	IF NOT HASTARGET { RETURN 0. }
	// Make sure that the target is either a vessel or a body
	IF NOT TARGET:ISTYPE("Vessel") AND NOT TARGET:ISTYPE("Body") { RETURN 0. }
	// Make sure that your target is orbiting the same body as your ship
	IF NOT TARGET:HASBODY OR TARGET:BODY <> SHIP:BODY { RETURN 0. }

	// Calculate time it will take your target to get to a true anomaly first
	LOCAL tgtEtaToTrueAnomaly IS TimeToTrueAnomaly(trueAnomaly, TARGET).
	// Now get the position of our target at it's true anomaly
	LOCAL tgtPosition IS POSITIONAT(TARGET, TIME:SECONDS+tgtEtaToTrueAnomaly).

	// Vector from center of the body to the Targets true anomaly
	LOCAL tgtTAVec IS tgtPosition - BODY:POSITION.
	// Vector from center of the body to our Periapsis
	LOCAL PEVec IS POSITIONAT(SHIP, TIME:SECONDS+ETA:PERIAPSIS) - BODY:POSITION.
	// Absolute angle between the two vectors
	LOCAL tgtTATrueAnomaly IS VANG(tgtTAVec, PEVec).
	// Check whether the Targets true anomaly is in front of our periapsis or behind it
	IF VANG(VCRS(tgtTAVec, PEVec), VCRS(SHIP:POSITION-BODY:POSITION, SHIP:VELOCITY:ORBIT)) < 1 {
		SET tgtTATrueAnomaly TO 360-tgtTATrueAnomaly.
	}

	RETURN tgtTATrueAnomaly.
}

// True Anomaly of our Targets Periapsis along our orbit
FUNCTION TA_TargetPE { RETURN TA_TargetToShip(0). }

// True Anomaly of our Targets Apoapsis along our orbit
FUNCTION TA_TargetAP { RETURN TA_TargetToShip(180). }

// Time to the specified true anomaly.
// You need to specify the true anomaly that you need to find
FUNCTION TimeToTrueAnomaly {
	PARAMETER trueAnomaly, ves IS SHIP.

	// Current Mean anomaly of the ship
	LOCAL ShipMeanAnomaly IS TrueToMean(ves:OBT:TRUEANOMALY, ves:OBT:ECCENTRICITY).
	// Target mean anomaly
	LOCAL targetMean IS TrueToMean(trueAnomaly).

	// Make sure that we calculate time to and not since
	IF targetMean <= ShipMeanAnomaly { SET targetMean TO targetMean + 360. }

	// Calculate Mean Motion
	LOCAL n IS 2*CONSTANT:PI/ves:OBT:PERIOD.
	// Return the time to realative node
	RETURN (CONSTANT:DegToRad*(targetMean - ShipMeanAnomaly))/n.
}

// This function uses hill climbing method to find the closest approach with our target
FUNCTION GetClosestApproach {
	// Make sure a target has been selected
	IF NOT HASTARGET { RETURN 0. }
	// Make sure that the target is either a vessel or a body
	IF NOT TARGET:ISTYPE("Vessel") { RETURN 0. }
	// Make sure that your target is orbiting the same body as your ship
	IF NOT TARGET:HASBODY OR TARGET:BODY <> SHIP:BODY { RETURN 0. }

	// By how much do we need to step each time we run the calculations
	// The steps sizes are 10, 1, 0.1 and 0.01. This should give us enough precision
	LOCAL stepSize IS 10.

	// Track the best result (we will calculate the final time from eta to targets TA)
	LOCAL closestApproachTA IS 0.
	LOCAL closestApproachDist IS SeparationFromTargetAt(TIME:SECONDS+TimeToTrueAnomaly(TA_TargetToShip(closestApproachTA)), TIME:SECONDS+TimeToTrueAnomaly(closestApproachTA, TARGET)).

	// Function that contains the loop which compares closest approach distances along the orbit
	FUNCTION FindClosestApproach {
		UNTIL FALSE {
			LOCAL positiveStepTA IS MOD(closestApproachTA+stepSize,360).
			LOCAL negativeStepTA IS MOD(360+closestApproachTA-stepSize,360).
			// Calculate the distance after a positive step change and after a negative step change
			LOCAL positiveStepDist IS SeparationFromTargetAt(TIME:SECONDS+TimeToTrueAnomaly(TA_TargetToShip(positiveStepTA)), TIME:SECONDS+TimeToTrueAnomaly(positiveStepTA, TARGET)).
			LOCAL negativeStepDist IS SeparationFromTargetAt(TIME:SECONDS+TimeToTrueAnomaly(TA_TargetToShip(negativeStepTA)), TIME:SECONDS+TimeToTrueAnomaly(negativeStepTA, TARGET)).

			// Compare the distances after steps with the previous best distance
			IF positiveStepDist < closestApproachDist {
				SET closestApproachTA TO positiveStepTA.
				SET closestApproachDist TO positiveStepDist.
			} ELSE IF negativeStepDist < closestApproachDist {
				SET closestApproachTA TO negativeStepTA.
				SET closestApproachDist TO negativeStepDist.
			} ELSE {
				// If neither step brought us closer then we know that with this step size we got to the closest point
				BREAK.
			}
		}
	}

	FindClosestApproach().
	SET stepSize TO 1.
	FindClosestApproach().
	SET stepSize TO 0.1.
	FindClosestApproach().
	SET stepSize TO 0.01.
	FindClosestApproach().
	SET stepSize TO 0.001.
	FindClosestApproach().

	LOCAL shipEta IS TimeToTrueAnomaly(TA_TargetToShip(closestApproachTA)).
	LOCAL targetEta IS TimeToTrueAnomaly(closestApproachTA, TARGET).

	LOCAL results IS LEXICON(
		"ETA", shipEta,
		"targetETA", targetEta,
		"dist", closestApproachDist,
		"targetTA", closestApproachTA,
		"shipTA", TA_TargetToShip(closestApproachTA),
		"relSpeed", RelativeVelocityToTargetAt(shipEta)
	).

	RETURN results.
}

// This function tels us what's the absolute distance between us and the target at specified time
// Can be called with just one time parameter (will return distance at the set time)
// Can also be called with two time parameters (will return distance between positions at two different points in time)
// Note that it requires actual time, NOT an ETA
FUNCTION SeparationFromTargetAt {
	PARAMETER t1 IS TIME:SECONDS, t2 IS -1.
	// Make sure a target has been selected
	IF NOT HASTARGET { RETURN 0. }
	// Make sure that the target is either a vessel or a body
	IF NOT TARGET:ISTYPE("Vessel") { RETURN 0. }
	// Make sure that your target is orbiting the same body as your ship
	IF NOT TARGET:HASBODY OR TARGET:BODY <> SHIP:BODY { RETURN 0. }

	// If user hasn't manually specified a second time, use first time for both ship and target
	IF t2 = -1 { SET t2 TO t1. }

	LOCAL shipPos IS POSITIONAT(SHIP, t1).
	LOCAL targetPos IS POSITIONAT(TARGET, t2).
	RETURN (shipPos-targetPos):MAG.
}

// This function tels us what's the absolute relative velocity between us and the target at specified time
// Note that it requires actual time, NOT an ETA
FUNCTION RelativeVelocityToTargetAt {
	PARAMETER t IS TIME:SECONDS.
	// Make sure a target has been selected
	IF NOT HASTARGET { RETURN 0. }
	// Make sure that the target is either a vessel or a body
	IF NOT TARGET:ISTYPE("Vessel") { RETURN 0. }
	// Make sure that your target is orbiting the same body as your ship
	IF NOT TARGET:HASBODY OR TARGET:BODY <> SHIP:BODY { RETURN 0. }

	LOCAL shipVel IS VELOCITYAT(SHIP, t):ORBIT.
	LOCAL targetVel IS VELOCITYAT(TARGET, t):ORBIT.
	RETURN (shipVel-targetVel):MAG.
}

// Calculate the altitude of a stationary orbit
FUNCTION StationaryOrbitAltitude {
	PARAMETER orbitBody IS OBT:BODY.

	RETURN ((orbitBody:MU * orbitBody:ROTATIONPERIOD^2)/(4*CONSTANT:PI^2))^(1.0/3.0)-orbitBody:RADIUS.
}

// Orbital period at specified semi-major axis
FUNCTION PeriodAtSMA {
	PARAMETER sma IS OBT:SEMIMAJORAXIS, orbitBody IS OBT:BODY.

	RETURN 2*CONSTANT:PI*SQRT(sma^3/orbitBody:MU).
}

// Semi-major axis which would have specified orbital period
FUNCTION SMAWithPeriod {
	PARAMETER period IS OBT:PERIOD, orbitBody IS OBT:BODY.

	RETURN ((orbitBody:MU * period^2)/(4*CONSTANT:PI^2))^(1.0/3.0).
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