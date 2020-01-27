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
    SET ens_isp TO ens_isp + en:ISP.
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
FUNCTION HohmanDv {
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

// Execute the next node
FUNCTION ExecNode {
  PARAMETER autoWarp.

  LOCAL n IS NEXTNODE.
  LOCAL v IS n:BURNVECTOR.

  LOCAL startTime IS TIME:SECONDS + n:ETA - BurnTime(v:MAG)/2.
  LOCK STEERING TO n:BURNVECTOR.

  IF autoWarp { WAIT 1. WARPTO(startTime - 30). }

  WAIT UNTIL TIME:SECONDS >= startTime.
  LOCK THROTTLE TO MAX(MIN(BurnTime(n:BURNVECTOR:MAG), 1),0.05).
  WAIT UNTIL VDOT(n:BURNVECTOR, v) < 0.
  LOCK THROTTLE TO 0.
  UNLOCK STEERING.
}