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

// Calculates the speed of the vessel at the point specified by true anomaly
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

// Time to the specified true anomaly.
// You need to specify the true anomaly that you need to find
FUNCTION TimeToTrueAnomaly {
	PARAMETER trueAnomaly.

	// Current Mean anomaly of the ship
	LOCAL ShipMeanAnomaly IS TrueToMean().
	// Target mean anomaly
	LOCAL targetMean IS TrueToMean(trueAnomaly).

	// Make sure that we calculate time to and not since
	IF targetMean <= ShipMeanAnomaly { SET targetMean TO targetMean + 360. }

	// Calculate Mean Motion
	LOCAL n IS 2*CONSTANT:PI/OBT:PERIOD.
	// Return the time to realative node
	RETURN (CONSTANT:DegToRad*(targetMean - ShipMeanAnomaly))/n.
}

// Calculate the altitude of a stationary orbit
FUNCTION StationaryOrbitAltitude {
	PARAMETER orbitBody IS OBT:BODY.

	RETURN ((orbitBody:MU * orbitBody:ROTATIONPERIOD^2)/(4*CONSTANT:PI^2))^(1.0/3.0)-orbitBody:RADIUS.
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