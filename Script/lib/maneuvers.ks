// Time to complete a maneuver
FUNCTION mnv_time {
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

// Delta v requirements for Hohmann Transfer
FUNCTION mnv_hohmann_dv {
  PARAMETER desiredAltitude.

  SET u  TO SHIP:OBT:BODY:MU.
  SET r1 TO SHIP:OBT:SEMIMAJORAXIS.
  SET r2 TO desiredAltitude + SHIP:OBT:BODY:RADIUS.

  // v1
  SET v1 TO SQRT(u / r1) * (SQRT((2 * r2) / (r1 + r2)) - 1).

  // v2
  SET v2 TO SQRT(u / r2) * (1 - SQRT((2 * r1) / (r1 + r2))).

  RETURN LIST(v1, v2).
}

// Execute the next node
FUNCTION mnv_exec_node {
  PARAMETER autoWarp.

  LOCAL n IS NEXTNODE.
  LOCAL v IS n:BURNVECTOR.

  LOCAL startTime IS TIME:SECONDS + n:ETA - mnv_time(v:MAG)/2.
  LOCK STEERING TO n:BURNVECTOR.

  IF autoWarp { WAIT 1. WARPTO(startTime - 30). }

  WAIT UNTIL TIME:SECONDS >= startTime.
  LOCK THROTTLE TO MAX(MIN(mnv_time(n:BURNVECTOR:MAG), 1),0.05).
  WAIT UNTIL VDOT(n:BURNVECTOR, v) < 0.
  LOCK THROTTLE TO 0.
  UNLOCK STEERING.
}