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

// Time to the closest equatorial node
FUNCTION TimeToEquatorialNode {
	LOCAL Mx IS 0.
	LOCAL M1 IS CONSTANT:PI/2 - OBT:ECCENTRICITY.
	LOCAL M2 IS 3*CONSTANT:PI/2 - OBT:ECCENTRICITY.

	IF OBT:TRUEANOMALY > 90 AND OBT:TRUEANOMALY <= 270 { SET Mx TO M2. }
	ELSE { SET Mx TO M1. }

	LOCAL n IS 2*CONSTANT:PI/OBT:PERIOD.
	RETURN (Mx - OBT:MEANANOMALYATEPOCH)/n.
}