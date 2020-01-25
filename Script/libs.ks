//  Rodrigues vector rotation formula - Borrowed from PEGAS
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

//  Function that returns a normal vector
FUNCTION GetNormalVec {
  PARAMETER prog IS SHIP:VELOCITY:SURFACE, pos IS SHIP:POSITION - BODY:POSITION.
  RETURN VCRS(prog,pos).
}

// nodeFromVector - originally created by reddit user ElWanderer_KSP
FUNCTION NodeFromVector {
  PARAMETER vec, n_time IS TIME:SECONDS.

  LOCAL s_pro IS VELOCITYAT(SHIP,n_time):SURFACE.
  LOCAL s_pos IS POSITIONAT(SHIP,n_time) - BODY:POSITION.
  LOCAL s_nrm IS VCRS(s_pro,s_pos).
  LOCAL s_rad IS VCRS(s_nrm,s_pro).

  RETURN NODE(n_time, VDOT(vec,s_rad:NORMALIZED), VDOT(vec,s_nrm:NORMALIZED), VDOT(vec,s_pro:NORMALIZED)).
}

FUNCTION Gravity {
  PARAMETER a IS SHIP:ALTITUDE.
  PARAMETER b IS SHIP:OBT:BODY.
  RETURN b:MU / (b:RADIUS + a)^2.
}

FUNCTION ShipCurrentTWR {
  RETURN ShipActiveThrust() / SHIP:MASS / Gravity(SHIP:ALTITUDE).
}

FUNCTION ShipTWR {
  RETURN SHIP:MAXTHRUST / SHIP:MASS / Gravity(SHIP:ALTITUDE).
}

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

FUNCTION TimeToAltitude {
  PARAMETER desiredAltitude.
  PARAMETER currentAltitude.
  
  IF currentAltitude-desiredAltitude <= 0 {
    RETURN 0.
  }
  RETURN (-VERTICALSPEED - SQRT( (VERTICALSPEED*VERTICALSPEED)-(2 * (-Gravity(currentAltitude)) * (currentAltitude - desiredAltitude))) ) /  ((-Gravity(currentAltitude))).
}

FUNCTION OrbitalVelocityAt{
  PARAMETER altitude.
  PARAMETER body IS SHIP:OBT:BODY.

  RETURN SQRT(body:MU/(body:RADIUS+altitude)).
}

FUNCTION GetMissionProfile {

  // Create a gui window
  LOCAL gui IS GUI(400).
  // Add widgets to the GUI
  LOCAL labelAlt IS gui:ADDLABEL("Target altitude [km]").
  SET labelAlt:STYLE:ALIGN TO "CENTER".
  SET labelAlt:STYLE:HSTRETCH TO TRUE. // Fill horizontaly
  LOCAL textAlt IS gui:ADDTEXTFIELD(90:TOSTRING).
  SET textAlt:STYLE:ALIGN TO "CENTER".
  SET textAlt:STYLE:HSTRETCH TO TRUE.
  SET textAlt:TOOLTIP TO "Minimum 80km".

  LOCAL labelDir IS gui:ADDLABEL("Target heading [deg]").
  SET labelDir:STYLE:ALIGN TO "CENTER".
  SET labelDir:STYLE:HSTRETCH TO TRUE. // Fill horizontaly
  LOCAL textDir IS gui:ADDTEXTFIELD(90:TOSTRING).
  SET textDir:STYLE:ALIGN TO "CENTER".
  SET textDir:STYLE:HSTRETCH TO TRUE.

  LOCAL labelGs IS gui:ADDLABEL("Launch g limit [g]").
  SET labelGs:STYLE:ALIGN TO "CENTER".
  SET labelGs:STYLE:HSTRETCH TO TRUE. // Fill horizontaly
  LOCAL valHLayout IS gui:ADDHLAYOUT().
  LOCAL checkGs IS valHLayout:ADDCHECKBOX("Enabled", TRUE).
  LOCAL sliderGs IS valHLayout:ADDHSLIDER(3,1.5,6).
  SET sliderGs:STYLE:HSTRETCH TO TRUE. // Fill horizontaly
  LOCAL textGs IS valHLayout:ADDTEXTFIELD(ROUND(sliderGs:VALUE,1):TOSTRING).
  SET textGs:STYLE:ALIGN TO "CENTER".
  SET textGs:STYLE:WIDTH TO 50.
  SET textGs:ENABLED TO FALSE.

  SET sliderGs:ONCHANGE TO {
    PARAMETER newValue.
    SET textGs:TEXT TO ROUND(newValue,1):TOSTRING.
  }.

  SET checkGs:ONTOGGLE TO {
    PARAMETER newState.
    SET sliderGs:ENABLED TO newState.
    IF newState {
      SET textGs:TEXT TO ROUND(sliderGs:VALUE,1):TOSTRING.
    } ELSE {
      SET textGs:TEXT TO 0:TOSTRING.
    }
  }.

  LOCAL buttonLaunch TO gui:ADDBUTTON("Launch!").
  // Show the GUI
  gui:SHOW().

  LOCAL isDone IS FALSE.
  UNTIL isDone {
    IF buttonLaunch:TAKEPRESS {
      IF textAlt:TEXT:TONUMBER(0) >= 80 {
        SET targetApoapsis TO textAlt:TEXT:TONUMBER()*1000.
        SET launchDirection TO textDir:TEXT:TONUMBER(90).
        IF checkGs:PRESSED { 
          SET launchGLimit TO ROUND(sliderGs:VALUE,1).
        }
        SET isDone TO TRUE.
      }
    }
    WAIT 0.1.
  }
  gui:HIDE().
  CLEARGUIS().
  RETURN TRUE.
}

FUNCTION CreateUI {
  CLEARSCREEN.
  SET TERMINAL:WIDTH TO 53.
  SET TERMINAL:HEIGHT TO 21.
  IF CORE:HASEVENT("open terminal") { CORE:DOEVENT("open terminal"). }
  
  PRINT ".---------------------------------------------------.".
  PRINT "| Launch -                                     v1.0 |".
  PRINT "|---------------------------------------------------|".
  PRINT "| Phase                    | Time                 s |".
  PRINT "|---------------------------------------------------|".
  PRINT "| TWR              /       | Mass               kg  |".
  PRINT "| Altitude              km | Vertical           m/s |".
  PRINT "| Apoapsis              km | Horizontal         m/s |".
  PRINT "| Target OBT            km | Velocity SRF       m/s |".
  PRINT "| Downrange             km | Velocity OBT       m/s |".
  PRINT "|---------------------------------------------------|".
  PRINT "|         |                                         |".
  PRINT "|         |                                         |".
  PRINT "|         |                                         |".
  PRINT "|         |                                         |".
  PRINT "|         |                                         |".
  PRINT "|         |                                         |".
  PRINT "|         |                                         |".
  PRINT "|         |                                         |".
  PRINT "'---------------------------------------------------'".
  
  PrintValue(SHIP:NAME, 1, 11, 44, "L").
}

//  Print text at the given place on the screen. Pad and trim when needed. - Borrowed from PEGAS
FUNCTION PrintValue {
  PARAMETER val.      //  Message to write (string/scalar)
  PARAMETER line.     //  Line to write to (scalar)
  PARAMETER start.    //  First column to write to, inclusive (scalar)
  PARAMETER end.      //  Last column to write to, exclusive (scalar)
  PARAMETER align IS "l". //  Align: "l"eft or "r"ight
  PARAMETER prec IS 0.  //  Decimal places (scalar)
  PARAMETER addSpaces IS TRUE.  //  Add spaces between every 3 digits

  LOCAL str IS "".
  IF val:ISTYPE("scalar") {
    SET str TO "" + ROUND(val, prec).
    //  Make sure the number has all the decimal places it needs to have
    IF prec > 0 {
      LOCAL hasZeros IS 0.
      IF str:CONTAINS(".") { SET hasZeros TO str:LENGTH - str:FIND(".") - 1. }
      ELSE { SET str TO str + ".". }
      FROM { LOCAL i IS hasZeros. } UNTIL i = prec STEP { SET i TO i + 1. } DO {
        SET str TO str + "0".
      }
    }
    //  Add a space between each 3 digits
    IF addSpaces {
      IF prec > 0 { SET prec TO prec+1. }
      IF str:LENGTH-prec > 3 {
        LOCAL addedSpaces IS FLOOR((str:LENGTH-prec-1)/3).
        LOCAL firstSpaceIndex IS (str:LENGTH-prec) - (addedSpaces*3).
        LOCAL desiredLength IS str:LENGTH - prec + addedSpaces.
        FROM { LOCAL i IS firstSpaceIndex. } UNTIL i + 4 >= desiredLength STEP { SET i TO i + 4. } DO {
          SET str TO str:INSERT(i, " ").
        }
      }
    }
  } ELSE { SET str TO val. }
  
  SET align TO align:TOLOWER().
  LOCAL flen IS end - start.
  //  If message is too long to fit in the field - trim, depending on type.
  IF str:LENGTH>flen {
    IF align="r" { SET str TO str:SUBSTRING(str:LENGTH-flen, flen). }
    ELSE IF align="l" { SET str TO str:SUBSTRING(0, flen). }
  }
  ELSE {
    IF align="r" { SET str TO str:PADLEFT(flen). }
    ELSE IF align="l" { SET str TO str:PADRIGHT(flen). }
  }
  PRINT str AT(start, line).
}

FUNCTION RefreshUI {
  IF runmode = 0 { PrintValue("Pre-launch " + subrunmode, 3, 8, 26, "R"). }
  ELSE IF runmode = 1 { IF mT - lT > 0 { PrintValue("Launch " + subrunmode, 3, 8, 26, "R"). } }
  ELSE IF runmode = 2 { PrintValue("Coasting " + subrunmode, 3, 8, 26, "R"). }
  ELSE IF runmode = 3 { PrintValue("Circularization " + subrunmode, 3, 8, 26, "R"). }
  ELSE IF runmode = 4 { PrintValue("Post-launch " + subrunmode, 3, 8, 26, "R"). }
  ELSE IF runmode = 5 { PrintValue("Ended " + subrunmode, 3, 8, 26, "R"). }
  IF mT-lT < 0 { PrintValue("T" + ROUND(mT-lT), 3, 34, 49, "R"). } ELSE { PrintValue("T+" + ROUND(mT-lT), 3, 34, 49, "R"). }
  PrintValue(ShipCurrentTWR(), 5, 13, 17, "R", 2). PrintValue(ShipTWR(), 5, 21, 25, "R", 2).
  PrintValue(currentAltitude/1000, 6, 11, 23, "R", 3).
  PrintValue(SHIP:OBT:APOAPSIS/1000, 7, 11, 23, "R", 3).
  PrintValue(targetApoapsis/1000, 8, 13, 23, "R", 3).
  PrintValue(launchSiteDistance/1000, 9, 12, 23, "R", 3).
  PrintValue(SHIP:MASS*1000, 5, 34, 47, "R").
  PrintValue(VERTICALSPEED, 6, 38, 47, "R").
  PrintValue(GROUNDSPEED, 7, 40, 47, "R").
  PrintValue(SHIP:VELOCITY:SURFACE:MAG, 8, 42, 47, "R").
  PrintValue(SHIP:VELOCITY:ORBIT:MAG, 9, 42, 47, "R").

  IF UILex["message"]:LENGTH <> UILexLength {
    UNTIL UILex["message"]:LENGTH <= 8 { UILex["message"]:REMOVE(0). UILex["time"]:REMOVE(0). }
    SET UILexLength TO UILex["message"]:LENGTH.

    FROM { LOCAL i IS UILexLength-1. LOCAL l IS 0. } UNTIL i < 0 STEP { SET i TO i - 1. SET l TO l + 1. } DO {
      IF UILex["time"][i] >= lT {
        PrintValue("T+" + (UILex["time"][i] - lT) + "s", 11 + l, 2, 8, "L").
      } ELSE {
        PrintValue("T" + (UILex["time"][i] - lT) + "s", 11 + l, 2, 8, "L").
      }
      PrintValue(UILex["message"][i], 11 + l, 12, 50, "L").
    }
  }
}

FUNCTION AddUIMessage {
  PARAMETER message IS FALSE.
  IF message:ISTYPE("String") {
    UILex["time"]:ADD(TIME:SECONDS).
    UILex["message"]:ADD(message).
  }
}

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