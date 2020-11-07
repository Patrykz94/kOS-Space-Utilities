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

// Time to the closest equatorial node
FUNCTION TimeToEquatorialNode {
	LOCAL ClosestNode IS 0.
	// Mean Anomaly of Ascending Node
	LOCAL AN IS TrueToMean(MOD(360 - OBT:ARGUMENTOFPERIAPSIS, 360)).
	// Mean Anomaly of Descending node
	LOCAL DN IS TrueToMean(MOD(540 - OBT:ARGUMENTOFPERIAPSIS, 360)).
	// Current Mean anomaly of the ship
	LOCAL ShipMeanAnomaly IS TrueToMean().

	// Decide which node is the closest based on ships current position
	IF AN > DN AND ShipMeanAnomaly > AN { SET ClosestNode TO DN + 360. }
	ELSE IF AN > DN AND ShipMeanAnomaly > DN { SET ClosestNode TO AN. }
	ELSE IF DN > AN AND ShipMeanAnomaly > DN { SET ClosestNode TO AN + 360. }
	ELSE IF DN > AN AND ShipMeanAnomaly <= AN { SET ClosestNode TO AN. }
	ELSE { SET ClosestNode TO DN. }

	// Calculate Mean Motion
	LOCAL n IS 2*CONSTANT:PI/OBT:PERIOD.
	
	// Return the time to closest equatorial node
	RETURN (CONSTANT:DegToRad*(ClosestNode - ShipMeanAnomaly))/n.
}

// Calculate the altitude of a stationary orbit
FUNCTION StationaryOrbitAltitude {
	PARAMETER orbitBody IS OBT:BODY.

	RETURN ((orbitBody:MU * orbitBody:ROTATIONPERIOD^2)/(4*CONSTANT:PI^2))^(1.0/3.0)-orbitBody:RADIUS.
}